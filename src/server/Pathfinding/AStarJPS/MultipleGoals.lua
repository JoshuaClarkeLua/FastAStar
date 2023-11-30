local Imports = require(script.Parent.Parent.Imports)
local Vector2Util = Imports.Vector2Util
local AJPSUtil = require(script.Parent.AJPSUtil)
local NodeUtil = require(script.Parent.Parent.NodeUtil)
local CollisionGrid = require(script.Parent.Parent.CollisionGrid)


local AJPS = {}

local Diagonal = AJPSUtil.Heuristic.Diagonal
local getG = AJPSUtil.getG
local nextNode = AJPSUtil.nextNode
local canWalk = AJPSUtil.canWalk
local isGroupInRow = AJPSUtil.isGroupInRow
local checkGroup = AJPSUtil.checkGroup
local hasForcedNeighbors = AJPSUtil.hasForcedNeighbors
local findNeighbors = AJPSUtil.findNeighbors

local function getGoalsReached(self, costs, groupId, startCol, dir, xMov): {Vector2}
	local reachedAll = true
	local goalsReached = {}
	for _, goal in pairs(self.goals) do
		local goalGroupId = xMov and goal.goalGroupIdZ or goal.goalGroupIdX
		local goalBit = xMov and goal.goalBitZ or goal.goalBitX
		if groupId == goalGroupId then
			-- Check to make sure collision hasn't passed the goal
			if CollisionGrid.CanReachBit(CollisionGrid.GetCollisionGroup(costs, groupId, self.collisionsByDefault), startCol, goalBit, dir) then
				table.insert(goalsReached, goal.goal)
				-- Continue, we already know the goal was reached
				continue
			end
		end
		-- Check if goal was reached previously
		if not self.goalsReached[goal.nodeId] then
			reachedAll = false
		end
	end
	if reachedAll then
		self.reachedAll = true
	end
	return goalsReached
end

local function getCoordsWithGroupIdAndColumn(rowSize: number, groupId: number, column: number, xMov: boolean): (number, number)
	local x,z
	if xMov then
		z, x = CollisionGrid.GetCoords(rowSize, groupId, column)
	else
		x, z = CollisionGrid.GetCoords(rowSize, groupId, column)
	end
	return x,z
end

local function isNodeGoal(self, node): GoalData?
	for _, goal in pairs(self.goals) do
		if node == goal.goal then
			return goal
		end
	end
	return 
end

function AJPS.findJumpNode(self, node, dir, _g): (number?, number?)
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
	-- print(first, group)
	while true do
		-- Check if we can reach the goal
		rcGroupId = _groupId
		local goalsReached = getGoalsReached(self, costs, _groupId, startCol, _dir, xMov)
		if #goalsReached > 0 then
			if self.stopAtFirst then
				local goal = goalsReached[1]
				return goal.X, goal.Y
			else
				for _, goal: Vector2 in pairs(goalsReached) do
					local g = _g + Diagonal(goal, node)
					local nodeId = NodeUtil.getNodeId(self.gridSize.X, goal.X, goal.Y)
					self.goalsReached[nodeId] = true
					if g < getG(self, nodeId) then
						self.g[nodeId] = g
					end
				end
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

	return getCoordsWithGroupIdAndColumn(rowSize, rcGroupId, c, xMov)
end

function AJPS.queueJumpNode(self, node, pNode, _g): Vector2?

	local g = _g + Diagonal(node, pNode)
	if isNodeGoal(self, node) then
		local nodeId = NodeUtil.getNodeId(self.gridSize.X, node.X, node.Y)
		self.goalsReached[nodeId] = nodeId
		if g < getG(self, nodeId) then
			self.g[nodeId] = g
		end
		if self.stopAtFirst then
			return node
		end
	end
	if self.reachedAll == true then
		return
	end

	local nodeId = NodeUtil.getNodeId(self.gridSize.X, node.X, node.Y)
	-- ignore node if not in grid
	-- ignore node if in closed set
	if not canWalk(self, node.X, node.Y) or self.closed[nodeId] then
		return
	end
	
	-- get node gcost
	if g < getG(self, nodeId) then
		self.parents[node] = pNode
		if g < getG(self, nodeId) then
			self.g[nodeId] = g
		end
		if not self.openDict[nodeId] then
			self.openDict[nodeId] = true
			self.open:Add(node, g)
		end
	end
	return
end

function AJPS.jump(self, node, pNode, _g): Vector2?
	if self.reachedAll == true then
		return
	end

	if not canWalk(self, node.X, node.Y) then
		return
	end
	local nodeId = NodeUtil.getNodeId(self.gridSize.X, node.X, node.Y)

	if isNodeGoal(self, node) then
		self.goalsReached[nodeId] = true
		local g = _g + Diagonal(node, pNode)
		if g < getG(self, nodeId) then
			self.g[nodeId] = g
		end
		if self.stopAtFirst then
			return node
		end
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

	local jx, jz = AJPS.findJumpNode(self, node, dir, g)
	if jx then
		pNode = node -- The parent node is now the previous diagonal node
		local jNode = Vector2.new(jx, jz)
		return AJPS.queueJumpNode(self, jNode, node, g)
	end
	return
end

function AJPS.findGoals(self, pNode, pNodeId): Vector2?
	if isNodeGoal(self, pNode) then
		self.goalsReached[pNodeId] = true
		if self.stopAtFirst then
			return pNode
		end
	end
	while pNode do
		local neighbors = findNeighbors(self, pNode, self.parents[pNode])
		local _g = getG(self, pNodeId)

		for i, node in ipairs(neighbors) do
			local goalNode = AJPS.jump(self, node, pNode, _g)
			if goalNode then
				local nodeId = NodeUtil.getNodeId(self.gridSize.X, goalNode.X, goalNode.Y)
				self.goalsReached[nodeId] = true
				if self.stopAtFirst then
					return goalNode
				end
			end
		end

		if self.reachedAll == true then
			break
		end
		pNode, pNodeId = nextNode(self)
	end
	return
end

type ObstacleGridList = CollisionGrid.CollisionGridList
type GoalData = {
	goal: Vector2,
	nodeId: number,
	goalGroupIdX: number,
	goalGroupIdZ: number,
	goalBitX: number,
	goalBitZ: number,
}
export type CollisionMap = CollisionGrid.CollisionMap
export type Path = {Vector2}
export type HeuristicName = "Chebyshev"
return AJPS