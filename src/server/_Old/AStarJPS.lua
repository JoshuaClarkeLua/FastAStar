local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Bit32Util = require(ReplicatedStorage.Shared.Bit32Util)
local GridUtil = require(ReplicatedStorage.Shared.GridUtil)
local NodeUtil = require(ReplicatedStorage.Shared.NodeUtil)
local PriorityQueue = require(ReplicatedStorage.Shared.PriorityQueue)
local Vector2Util = require(ReplicatedStorage.Shared.Vector2Util)
local CostGrid = require(ServerScriptService.Server.Pathfinding.CostGrid)

--[=[
	@function Chebyshev
	
	Heuristic used in grid-based maps where you can move in eight directions (including diagonals).

	@param nX number -- Current node X
	@param nY number -- Current node Y
	@param tnX number -- Target node X
	@param tnY number -- Target node Y
	@return number -- The node's heuristic value
]=]
local function Chebyshev(n: Vector2, tn: Vector2): number
	local dx = math.abs(n.X - tn.X)
	local dy = math.abs(n.Y - tn.Y)
	return math.max(dx, dy)
end

local function Diagonal(nodeA, nodeB): number
	local dx = math.abs(nodeA.X - nodeB.X)
	local dy = math.abs(nodeA.Y - nodeB.Y)
	return (dx + dy) + (1.4 - 2) * math.min(dx, dy)
end

local HEURISTIC = {
	["Chebyshev"] = Chebyshev,
	["Diagonal"] = Diagonal,
}
local BLOCKED = 65535
local AJPS = {}
AJPS.BLOCKED_COST = BLOCKED

local _partsFolder
local function clearParts()
	if _partsFolder then
		_partsFolder:Destroy()
	end
	local p = Instance.new("Folder")
	p.Name = "pathfinding_debug_parts"
	p.Parent = workspace
	_partsFolder = p
end
local origin = workspace.Baseplate.CFrame
local bSize2 = workspace.Baseplate.Size/2
local function _doPart(pos: Vector2): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = Vector3.one
	p.Position = (origin * CFrame.new(-bSize2.X, bSize2.Y, -bSize2.Z)):PointToWorldSpace(Vector3.new(pos.X, 0, pos.Y))
	p.Parent = _partsFolder
	return p
end

local function calF(self, node: Vector2): number
	return self.hFn(node, self.goal)
end

local function getG(self, nodeId: number): number
	return self.g[nodeId] or math.huge
end

local function nextNode(self): (Vector2?, number?)
	local node = self.open:Pop()
	if not node then
		return
	end
	local nodeId = NodeUtil.getNodeId(self.gridSize.X, node.X, node.Y)
	self.openDict[nodeId] = nil
	return node, nodeId
end
local function canWalk(self, x, z): boolean
	return GridUtil.isInGrid(self.gridSize.X, self.gridSize.Y, x, z)
		and CostGrid.GetCost(self.costsX, self.gridSize.X, x, z) < 1
end

local function allNeighbors(self, node): { Vector2 }
	local neighbors = {}
	for _, dir in ipairs(GridUtil.DIR) do
		local n = node + dir
		if canWalk(self, n.X, n.Y) then
			table.insert(neighbors, n)
		end
	end
	return neighbors
end

--[=[
	@function forced

	Returns the position of the bit (representing a node) which is a forced neighbor in groupB *before the first collision (if any)*
	hasCollision is true if there is a collision

	@param groupA number -- The group we are checking for forced neighbors
	@param groupB number -- The group that could potentially have forced neighbors
	@param dir number -- The direction of travel (1 or -1)
	@return (boolean?, number?) -- (hasCollision, forceResult)
]=]
local function forced(groupA, groupB, dir): (boolean?, number?)
	-- Create collision mask
	local firstB = dir > 0 and bit32.countrz(groupA) or bit32.countlz(groupA)
	local hasCollision = firstB < 32
	if hasCollision then
		if firstB == 0 then
			return dir > 0 and firstB or 31 - firstB
		end
		local _firstB = math.max(firstB - 1, -1)
		local colMask = dir < 0 and Bit32Util.FILL_L[_firstB] or Bit32Util.FILL_R[_firstB]
		-- Apply collision mask
		groupB = bit32.band(groupB, colMask) -- Removes all the blocked nodes past the first collision node in groupA
		groupA = bit32.band(groupA, colMask)
	elseif groupB == 0 then
		return
	end
	-- Check for forced neighbors
	-- 1. count zeros until 1 is found, and save that position
	local startB = 31 - (dir > 0 and bit32.countrz(groupB) or bit32.countlz(groupB))
	-- 2. flip the bits
	local groupBFlip = bit32.bnot(groupB)
	-- 3. Make the all bits from the first bit (depends which direction we're coming from) to the saved position all 0s
	groupBFlip = bit32.band(groupBFlip, dir > 0 and Bit32Util.FILL_L[startB] or Bit32Util.FILL_R[startB])
	local jumpNode = dir > 0 and bit32.countrz(groupBFlip) or bit32.countlz(groupBFlip)
	-- Return if no jump node or if the jump node is one node before the collision node
	if hasCollision and jumpNode >= firstB then
		return hasCollision and (dir > 0 and firstB or 31 - firstB) or nil
	end
	return hasCollision and (dir > 0 and firstB or 31 - firstB) or nil, dir > 0 and jumpNode or 31 - jumpNode
end
local function isGroupInRow(
	rowSize: number,
	row: number,
	groupId: number,
	firstId: number,
	lastId: number,
	dir: number
): boolean
	return dir > 0 and (groupId >= firstId and groupId <= lastId) or (groupId <= firstId and groupId >= lastId)
end
local function checkGroup(
	row,
	rowSize,
	first,
	last,
	costs,
	dir,
	goalGroupId,
	goalBit,
	--
	groupA,
	groupB,
	groupIdA,
	groupIdB
): (number?, number?, number?, number?, number?)
	local collisionBit, force = forced(groupA, groupB, dir)

	-- Check if we can reach the goal
	--[[ if groupIdB == goalGroupId then
		-- Check to make sure we haven't passed the goal
		if (dir > 0 and bit32.countrz(groupB) > goalBit) or (dir < 0 and 31 - bit32.countlz(groupB) < goalBit) then
			return collisionBit, force, groupIdB, row, goalBit
		end
	end ]]
	--

	if force then
		-- Check next group if force is at end of current group
		if force == 32 or force == -1 then
			local nGroupId = groupIdA + dir
			if isGroupInRow(rowSize, row, nGroupId, first, last, dir) then
				local nGroup = costs[nGroupId] or 0
				local nGroupB = costs[groupIdB + dir] or 0
				if dir > 0 then
					if bit32.extract(nGroup, 0, 1) == 1 or bit32.extract(nGroupB, 0, 1) == 1 then
						force = nil
					end
				else
					if bit32.extract(nGroup, 31, 1) == 1 or bit32.extract(nGroupB, 31, 1) == 1 then
						force = nil
					end
				end
			end
		end
		if force then
			-- Check to make sure forced neighbor is not past the collision
			if not collisionBit or (dir > 0 and force < collisionBit) or (dir < 0 and force > collisionBit) then
				local r = row
				local c = force - dir -- subtract _dir to return the position of the jump node instead of the forced neighbor position
				return collisionBit, force, groupIdA, r, c
			end
		end
	end
	return collisionBit, force, groupIdA
end
function AJPS._forced(self, node, dir, debug: boolean?): (number?, number?)
	if dir.X ~= 0 and dir.Y ~= 0 then
		error("AJPS._forced() does not support Diagonal movement.")
	end

	local x, z = node.X, node.Y
	local sx, sz = self.gridSize.X, self.gridSize.Y

	local xMov = dir.X ~= 0
	local _dir = xMov and dir.X or dir.Y
	local costs = xMov and self.costsZ or self.costsX
	local rowSize = xMov and sx or sz
	local colSize = xMov and sz or sx
	local row = xMov and z or x
	local col = xMov and x or z
	local goalGroupId = xMov and self.goalGroupIdZ or self.goalGroupIdX
	local goalBit = xMov and self.goalBitZ or self.goalBitX
	local startCol = col % 32

	-- Return if at the end of the grid
	local _cpd = col + _dir
	if _cpd < 0 or _cpd > rowSize then
		return
	end

	local group, first, last = CostGrid.GetRowFromStartCol(costs, rowSize, row, col, _dir)
	local _groupId = first
	local groupU, firstU, lastU, _groupIdU
	-- Get group up if not at the top of the grid
	if row < colSize then
		groupU, firstU, lastU = CostGrid.GetRowFromStartCol(costs, rowSize, row + 1, col, _dir)
		_groupIdU = firstU
	end
	local groupD, firstD, lastD, _groupIdD
	-- Get group down if not at the bottom of the grid
	if row > 0 then
		groupD, firstD, lastD = CostGrid.GetRowFromStartCol(costs, rowSize, row - 1, col, _dir)
		_groupIdD = firstD
	end

	local r, c, rcGroupId
	local collisionBit, force
	-- print(first, group)
	while true do
		-- Check if we can reach the goal
		rcGroupId = _groupId
		if _groupId == goalGroupId then
			-- Check to make sure collision hasn't passed the goal
			if CostGrid.CanReachBit(CostGrid.GetGroup(costs, _groupId), startCol, goalBit, _dir) then
				r, c = row, goalBit
				break
			end
		end

		-- Check the upper group
		if groupU then
			collisionBit, force, rcGroupId, r, c = checkGroup(
				row,
				rowSize,
				first,
				last,
				costs,
				_dir,
				goalGroupId,
				goalBit,
				--
				group,
				groupU,
				_groupId,
				_groupIdU
			)
			if r then
				r += 1
				break
			end
		end

		-- Check the lower group
		if groupD then
			collisionBit, force, rcGroupId, r, c = checkGroup(
				row,
				rowSize,
				first,
				last,
				costs,
				_dir,
				goalGroupId,
				goalBit,
				--
				group,
				groupD,
				_groupId,
				_groupIdD
			)
			if r then
				r -= 1
				break
			end
		end


		if collisionBit then
			return
		end
		-- Go to next group
		_groupId += _dir
		-- Return if out of bounds (the other groups are automatically out of bounds too bc grid is rectangular)
		if not isGroupInRow(rowSize, row, _groupId, first, last, _dir) then
			return
		end
		-- Group
		group = costs[_groupId] or 0
		startCol = _dir > 0 and 0 or 31
		-- Group Up
		if _groupIdU then
			_groupIdU += _dir
			groupU = costs[_groupIdU] or 0
		end
		-- Group Down
		if _groupIdD then
			_groupIdD += _dir
			groupD = costs[_groupIdD] or 0
		end
	end

	local x, z

	if xMov then
		z, x = CostGrid.GetCoords(rowSize, rcGroupId, c)
	else
		x, z = CostGrid.GetCoords(rowSize, rcGroupId, c)
	end

	return x, z
end

function AJPS._hasForcedNeighbors(self, node, dir): boolean
	local n = node + dir
	-- Horizontal
	if dir.X ~= 0 and dir.Y == 0 then
		if
			(not canWalk(self, node.X, node.Y + 1) and canWalk(self, n.X, node.Y + 1))
			or (not canWalk(self, node.X, node.Y - 1) and canWalk(self, n.X, node.Y - 1))
		then
			return true
		end
		-- Vertical
	elseif dir.X == 0 and dir.Y ~= 0 then
		if
			(not canWalk(self, node.X + 1, node.Y) and canWalk(self, node.X + 1, n.Y))
			or (not canWalk(self, node.X - 1, node.Y) and canWalk(self, node.X - 1, n.Y))
		then
			return true
		end
		-- Diagonal
	elseif dir.X ~= 0 and dir.Y ~= 0 then
		if
			(not canWalk(self, node.X - dir.X, node.Y) and canWalk(self, node.X - dir.X, n.Y))
			or (not canWalk(self, node.X, node.Y - dir.Y) and canWalk(self, n.X, node.Y - dir.Y))
		then
			return true
		end
	end
	return false
end

function AJPS._findNeighbors(self, node, pNode): { Vector2 }
	local neighbors = {}
	if pNode == nil then
		return allNeighbors(self, node)
	end
	local dir = Vector2Util.sign(node - pNode)
	-- Directly forward (cardinal)
	local n = node + dir
	-- Add n to neighbors if not blocked
	if canWalk(self, n.X, n.Y) then
		table.insert(neighbors, n)
	end
	-- Move X
	if dir.X ~= 0 and dir.Y == 0 then
		-- Check for forced neighbors
		if not canWalk(self, node.X, node.Y + 1) and canWalk(self, n.X, node.Y + 1) then
			table.insert(neighbors, n + Vector2.yAxis)
		end
		if not canWalk(self, node.X, node.Y - 1) and canWalk(self, n.X, node.Y - 1) then
			table.insert(neighbors, n - Vector2.yAxis)
		end
		--
		-- Move Y
	elseif dir.X == 0 and dir.Y ~= 0 then
		-- Check for forced neighbors
		if not canWalk(self, node.X + 1, node.Y) and canWalk(self, node.X + 1, n.Y) then
			table.insert(neighbors, n + Vector2.xAxis)
		end
		if not canWalk(self, node.X - 1, node.Y) and canWalk(self, node.X - 1, n.Y) then
			table.insert(neighbors, n - Vector2.xAxis)
		end
		--
		-- Diagonal movement
	else
		if canWalk(self, n.X, node.Y) then
			table.insert(neighbors, node + Vector2.xAxis)
		end
		if canWalk(self, node.X, n.Y) then
			table.insert(neighbors, node + Vector2.yAxis)
		end
		-- Check for forced neighbors
		if not canWalk(self, node.X - dir.X, node.Y) and canWalk(self, node.X - dir.X, n.Y) then
			table.insert(neighbors, node + Vector2.new(-dir.X, dir.Y))
		end
		if not canWalk(self, node.X, node.Y - dir.Y) and canWalk(self, n.X, node.Y - dir.Y) then
			table.insert(neighbors, node + Vector2.new(dir.X, -dir.Y))
		end
	end
	return neighbors
end

function AJPS._queueJumpNode(self, node, pNode, _g): Vector2?
	if node == self.goal then
		self.parents[node] = pNode
		return node
	end

	local nodeId = NodeUtil.getNodeId(self.gridSize.X, node.X, node.Y)
	-- ignore node if not in grid
	-- ignore node if in closed set
	if not canWalk(self, node.X, node.Y) or self.closed[nodeId] then
		return
	end
	
	-- get node gcost
	local g = _g + Diagonal(node, pNode)
	if g < getG(self, nodeId) then
		self.parents[node] = pNode
		self.g[nodeId] = g
		if self.f[nodeId] == nil then
			self.f[nodeId] = calF(self, node)
		end
		if not self.openDict[nodeId] then
			self.openDict[nodeId] = true
			self.open:Add(node, self.f[nodeId])
		end
	end
	return
end

function AJPS._jump(self, node, pNode, pG): (Vector2?, number?)
	local nodeId = NodeUtil.getNodeId(self.gridSize.X, node.X, node.Y)

	if not canWalk(self, node.X, node.Y) then
		return
	end
	if node == self.goal then
		self.parents[node] = pNode
		return node
	end
	if self.closed[nodeId] then
		return
	end

	self.parents[node] = pNode

	local dir = Vector2Util.sign(node - pNode)
	local g = pG + Diagonal(node, pNode)

	-- Check forced neighbors in the direction of travel
	if AJPS._hasForcedNeighbors(self, node, dir) then
		return AJPS._queueJumpNode(self, node, pNode, g)
	end

	self.closed[nodeId] = true

	if dir.X ~= 0 and dir.Y ~= 0 then
		local goalNode = AJPS._jump(self, node + Vector2.new(dir.X, 0), node, g)
		if goalNode then
			return goalNode
		end
		goalNode = AJPS._jump(self, node + Vector2.new(0, dir.Y), node, g)
		if goalNode then
			return goalNode
		end
		return AJPS._jump(self, node + dir, pNode, g)
	end

	local jx, jz = AJPS._forced(self, node, dir)
	if jx then
		pNode = node -- The parent node is now the previous diagonal node
		local jNode = Vector2.new(jx, jz)
		g += Diagonal(jNode, node)
		return AJPS._queueJumpNode(self, jNode, node, g)
	end
	return
	-- return AJPS._jump(self, node + dir, node, g)
end

local function findGoalJPS(self, pNode, pNodeId): Vector2?
	while pNode do
		local neighbors = AJPS._findNeighbors(self, pNode, self.parents[pNode])
		local _g = getG(self, pNodeId)

		-- sort neighbors
		table.sort(neighbors, function(a,b)
			return Diagonal(a, self.goal) < Diagonal(b, self.goal)
		end)
		--

		for i, node in ipairs(neighbors) do
			local goalNode = AJPS._jump(self, node, pNode, _g)
			if goalNode then
				return goalNode
			end
		end

		pNode, pNodeId = nextNode(self)
	end
	return
end

local function findGoal(self, pNode: Vector2?, pNodeId: number?): Vector2?
	while pNode and pNodeId do
		if pNode == nil then
			break
		end
		-- If goal, backtrack through parent nodes
		if pNode == self.goal then
			return pNode
		end
		-- Add to closed set
		self.closed[pNodeId] = true
		local _g = self.g[pNodeId]
		-- Get neighbors
		for _, dir in ipairs(GridUtil.DIR) do
			local node = pNode + dir
			local nodeId = NodeUtil.getNodeId(self.gridSize.X, node.X, node.Y)
			-- ignore node if not walkable
			-- ignore node if in closed set
			if not canWalk(self, node.X, node.Y) or self.closed[nodeId] then
				continue
			end
			-- get node gcost
			local g = _g + Diagonal(node, pNode)
			if g < getG(self, nodeId) then
				self.parents[node] = pNode
				self.g[nodeId] = g
				self.f[nodeId] = g + calF(self, node)
				if not self.openDict[nodeId] then
					self.openDict[nodeId] = true
					self.open:Add(node, self.f[nodeId])
				end
			end
		end
		pNode, pNodeId = nextNode(self)
	end
	return
end

local function reconstructPath(self, cNode): ()
	local lastP
	while cNode do
		if self.debug then
			local node = cNode
			task.defer(function()
				local p = _doPart(node)
				p.Color = Color3.new(1,0,0)
				p.Transparency = .5
				local beam = Instance.new("Beam")
				beam.FaceCamera = true
				beam.Color = ColorSequence.new(Color3.new(1,0,0))
				local a1 = Instance.new("Attachment")
				a1.Parent = p
				beam.Attachment0 = a1
				beam.Parent = p
				if lastP then
					local a2 = Instance.new("Attachment")
					a2.Parent = p
					lastP.Beam.Attachment1 = a2
				end
				lastP = p
			end)
		end
		table.insert(self.path, cNode)
		local pNode = self.parents[cNode]
		cNode = pNode
	end
end

function AJPS.findPath(
	gridSize: Vector2,
	start: Vector2,
	goal: Vector2,
	costsX: CostGridList?,
	costsZ: CostGridList?,
	heuristic: HeuristicName?,
	debug: boolean?
): Path
	if debug then
		clearParts()
	end
	start = Vector2Util.round(start)
	goal = Vector2Util.round(goal)
	local self = {}
	self.debug = debug
	self.gridSize = gridSize
	self.start = start
	self.goal = goal
	self.goalGroupIdX = CostGrid.GetGroupId(gridSize.X, goal.X, goal.Y)
	self.goalGroupIdZ = CostGrid.GetGroupId(gridSize.Y, goal.Y, goal.X)
	self.goalBitX = goal.Y % 32
	self.goalBitZ = goal.X % 32
	self.costsX = costsX or {}
	self.costsZ = costsZ or {}
	self.hFn = HEURISTIC[heuristic] or HEURISTIC["Diagonal"]
	self.open = PriorityQueue.new(function(a, b)
		return a > b
	end)
	self.openDict = {}
	self.closed = {}
	self.parents = {}
	self.path = {}
	--
	self.g = {}
	self.f = {}
	local startNodeId = NodeUtil.getNodeId(gridSize.X, start.X, start.Y)
	self.g[startNodeId] = 0
	self.f[startNodeId] = calF(self, self.start)
	-- Find Goal
	-- local goalNode = findGoal(self, self.start, startNodeId)
	local goalNode = findGoalJPS(self, self.start, startNodeId)
	-- Reconstruct path
	reconstructPath(self, goalNode)
	return self.path
end

type CostGridList = CostGrid.CostGridList
export type Path = {Vector2}
export type HeuristicName = "Chebyshev"
return AJPS
