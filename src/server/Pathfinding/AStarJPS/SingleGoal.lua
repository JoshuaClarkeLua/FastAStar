--!native
local Imports = require(script.Parent.Parent.Imports)
local Vector2Util = Imports.Vector2Util
local AJPSUtil = require(script.Parent.AJPSUtil)
local Draw = require(script.Parent.Draw)
local NodeUtil = require(script.Parent.Parent.NodeUtil)
local CollisionGrid = require(script.Parent.Parent.CollisionGrid)


local AJPS = {}

local Diagonal = AJPSUtil.Heuristic.Diagonal
local calF = AJPSUtil.calF
local getG = AJPSUtil.getG
local nextNode = AJPSUtil.nextNode
local canWalk = AJPSUtil.canWalk
local isGroupInRow = AJPSUtil.isGroupInRow
local checkGroup = AJPSUtil.checkGroup
local hasForcedNeighbors = AJPSUtil.hasForcedNeighbors
local findNeighbors = AJPSUtil.findNeighbors


function AJPS.findJumpNode(self, node, dir): (number?, number?)
	if dir.X ~= 0 and dir.Y ~= 0 then
		error("AJPS.findJumpNode() does not support Diagonal movement.")
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

	local group, first, last = CollisionGrid.GetRowFromStartCol(costs, rowSize, row, col, _dir, self.collisionsByDefault)
	local _groupId = first
	local groupU, firstU, lastU, _groupIdU
	-- Get group up if not at the top of the grid
	if row < colSize then
		groupU, firstU, lastU = CollisionGrid.GetRowFromStartCol(costs, rowSize, row + 1, col, _dir, self.collisionsByDefault)
		_groupIdU = firstU
	end
	local groupD, firstD, lastD, _groupIdD
	-- Get group down if not at the bottom of the grid
	if row > 0 then
		groupD, firstD, lastD = CollisionGrid.GetRowFromStartCol(costs, rowSize, row - 1, col, _dir, self.collisionsByDefault)
		_groupIdD = firstD
	end

	local r, c, rcGroupId
	local collisionBit, force
	while true do
		-- Check if we can reach the goal
		rcGroupId = _groupId
		if _groupId == goalGroupId then
			-- Check to make sure collision hasn't passed the goal
			if CollisionGrid.CanReachBit(CollisionGrid.GetCollisionGroup(costs, _groupId, self.collisionsByDefault), startCol, goalBit, _dir) then
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
		z, x = CollisionGrid.GetCoords(rowSize, rcGroupId, c)
	else
		x, z = CollisionGrid.GetCoords(rowSize, rcGroupId, c)
	end

	return x, z
end

function AJPS.queueJumpNode(self, node, pNode, _g): Vector2?
	if node == self.goal then
		self.parents[node] = pNode
		return node
	end

	-- ignore node if not in grid
	if not canWalk(self, node.X, node.Y) then
		return
	end
	-- ignore node if in closed set
	-- Must get the nodeId after checking if canWalk is true (z cannot be negative)
	local nodeId = NodeUtil.getNodeId(self.gridSize.X, node.X, node.Y)
	if self.closed[nodeId] then
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
		self.open:Add(node, g + self.f[nodeId])
	end
	return
end

function AJPS.jump(self, node, pNode, _g): (Vector2?, number?)
	if not canWalk(self, node.X, node.Y) then
		return
	end
	local nodeId = NodeUtil.getNodeId(self.gridSize.X, node.X, node.Y)
	if node == self.goal then
		self.parents[node] = pNode
		self.g[nodeId] = _g + Diagonal(node, pNode)
		return node
	end
	if self.closed[nodeId] then
		return
	end

	self.parents[node] = pNode

	local dir = Vector2Util.sign(node - pNode)

	-- Check forced neighbors in the direction of travel
	if hasForcedNeighbors(self, node, dir) then
		return AJPS.queueJumpNode(self, node, pNode, _g)
	end

	self.closed[nodeId] = true

	local g = _g + Diagonal(node, pNode)
	if dir.X ~= 0 and dir.Y ~= 0 then
		local goalNode = AJPS.jump(self, node + Vector2.new(dir.X, 0), node, g)
		if goalNode then
			return goalNode
		end
		goalNode = AJPS.jump(self, node + Vector2.new(0, dir.Y), node, g)
		if goalNode then
			return goalNode
		end
		return AJPS.jump(self, node + dir, pNode, _g)
	end

	local jx, jz = AJPS.findJumpNode(self, node, dir)
	if jx then
		pNode = node -- The parent node is now the previous diagonal node
		local jNode = Vector2.new(jx, jz)
		return AJPS.queueJumpNode(self, jNode, node, g)
	end
	return
end

function AJPS.findGoalJPS(self, pNode, pNodeId): Vector2?
	Draw.clear()
	while pNode do
		local neighbors = findNeighbors(self, pNode, self.parents[pNode])
		local _g = getG(self, pNodeId)

		-- sort neighbors
		table.sort(neighbors, function(a,b)
			return Diagonal(a, self.goal) < Diagonal(b, self.goal)
		end)
		--

		for i, node in ipairs(neighbors) do
			local goalNode = AJPS.jump(self, node, pNode, _g)
			if goalNode then
				return goalNode
			end
		end
		pNode, pNodeId = nextNode(self)
	end
	return
end

export type CollisionMap = CollisionGrid.CollisionMap
export type Path = {Vector2}
export type HeuristicName = "Chebyshev"
return AJPS