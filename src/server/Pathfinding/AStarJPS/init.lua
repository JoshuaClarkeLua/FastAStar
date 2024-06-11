local Imports = require(script.Parent.Imports)
local PriorityQueue = Imports.PriorityQueue
local Vector2Util = Imports.Vector2Util
local AJPSUtil = require(script.AJPSUtil)
local Fill = require(script.Fill)
local MultipleGoals = require(script.MultipleGoals)
local NodeUtil = require(script.Parent.NodeUtil)
local CollisionGrid = require(script.Parent.CollisionGrid)
local GridUtil = require(script.Parent.GridUtil)
local SingleGoal = require(script.SingleGoal)

local AJPS = {}

local function reconstructPath(self, cNode): ()
	while cNode do
		table.insert(self.path, cNode)
		local pNode = self.parents[cNode]
		cNode = pNode
	end
end

local function plotLine(x0, y0, x1, y1)
	x0 = math.floor(x0)
	y0 = math.floor(y0)
	x1 = math.floor(x1)
	y1 = math.floor(y1)
	local dx = math.abs(x1 - x0)
	local dy = -math.abs(y1 - y0)
	local sx = x0 < x1 and 1 or -1
	local sy = y0 < y1 and 1 or -1
	local err = dx + dy

	local points = {}
	while true do
		table.insert(points, Vector2.new(x0, y0))
		if x0 == x1 and y0 == y1 then break end
		local e2 = err * 2
		if e2 >= dy then
			if x0 == x1 then break end
			err = err + dy
			x0 = x0 + sx
		end
		if e2 <= dx then
			if y0 == y1 then break end
			err = err + dx
			y0 = y0 + sy
		end
	end
	return points
end

function AJPS._setup(
	gridSize: Vector2,
	start: Vector2,
	heuristic: HeuristicName?,
	collisionsX: CollisionGrid.CollisionGridList,
	collisionsZ: CollisionGrid.CollisionGridList,
	collisionsByDefault: boolean?
)
	local self = {}
	self.collisionsByDefault = collisionsByDefault
	self.gridSize = gridSize
	-- Setup map lists
	self.costsX, self.costsZ = collisionsX, collisionsZ
	--
	self.hFn = AJPSUtil.Heuristic[heuristic] or AJPSUtil.Heuristic.Diagonal
	self.open = PriorityQueue.new(function(a, b)
		return a > b
	end)
	self.openDict = {}
	self.closed = {}
	self.parents = {}
	--
	self.g = {}
	
	-- Setup start position
	local validStart = true
	local _start = Vector2Util.floor(start)
	-- Try to get unobstructed start position
	-- Look around the original start position to avoid false positive collisions
	if not AJPSUtil.canWalk(self, _start.X, _start.Y) then
		validStart = false
		-- Check the closest nodes to the original position first
		local nodes = {} -- {{Vector2, Distance}}
		for _, dir in ipairs(GridUtil.DIR) do
			local n = _start + dir
			local dist = (n - start).Magnitude
			table.insert(nodes, {n, dist})
		end
		table.sort(nodes, function(a,b)
			return a[2] < b[2]
		end)
		for _, node in ipairs(nodes) do
			local n = node[1]
			if AJPSUtil.canWalk(self, n.X, n.Y) then
				_start = n
				validStart = true
				break
			end
		end
	end
	self.start = _start
	local startNodeId = NodeUtil.getNodeId(gridSize.X, _start.X, _start.Y)
	self.startNodeId = startNodeId
	self.g[startNodeId] = 0

	return validStart, self
end

function AJPS._getGoalData(self, goal: Vector2)
	goal = Vector2Util.floor(goal)
	local gridSize = self.gridSize
	if not GridUtil.isInGrid(gridSize.X, gridSize.Y, goal.X, goal.Y) or not AJPSUtil.canWalk(self, goal.X, goal.Y) then
		return
	end
	local goalGroupIdX = CollisionGrid.GetGroupId(gridSize.X, goal.X, goal.Y)
	local goalGroupIdZ = CollisionGrid.GetGroupId(gridSize.Y, goal.Y, goal.X)
	local goalBitX = goal.Y % 32
	local goalBitZ = goal.X % 32
	return {
		goal = goal,
		nodeId = NodeUtil.getNodeId(gridSize.X, goal.X, goal.Y),
		goalGroupIdX = goalGroupIdX,
		goalGroupIdZ = goalGroupIdZ,
		goalBitX = goalBitX,
		goalBitZ = goalBitZ,
	}
end

function AJPS.findPath(
	gridSize: Vector2,
	start: Vector2,
	goal: Vector2,
	heuristic: HeuristicName?,
	collisionsX: CollisionGrid.CollisionGridList,
	collisionsZ: CollisionGrid.CollisionGridList,
	collisionsByDefault: boolean?
): (Path, {[any]: any})
	local success, self = AJPS._setup(gridSize, start, heuristic, collisionsX, collisionsZ, collisionsByDefault)
	if not success then return {}, self end
	-- Setup goal data
	local goalData = AJPS._getGoalData(self, goal)
	if not goalData then return {}, self end
	self.goal = goalData.goal
	self.goalGroupIdX = goalData.goalGroupIdX
	self.goalGroupIdZ = goalData.goalGroupIdZ
	self.goalBitX = goalData.goalBitX
	self.goalBitZ = goalData.goalBitZ
	-- Setup start node
	self.f = {}
	self.f[self.startNodeId] = AJPSUtil.calF(self, self.start)
	--
	self.path = {}


	-- Find Goal
	local goalNode
	if self.start == self.goal then
		goalNode = self.start
	else
		goalNode = SingleGoal.findGoalJPS(self, self.start, self.startNodeId)
	end
	-- Reconstruct path
	reconstructPath(self, goalNode)
	if #self.path > 0 and goal ~= self.goal then
		table.insert(self.path, 1, goal)
	end
	return self.path, self
end

function AJPS.findReachable(
	gridSize: Vector2,
	start: Vector2,
	goals: {[any]: Vector2},
	stopAtFirst: boolean?,
	collisionsX: CollisionGrid.CollisionGridList,
	collisionsZ: CollisionGrid.CollisionGridList,
	collisionsByDefault: boolean?
): ({Vector2}, {[any]: any})
	local success, self = AJPS._setup(gridSize, start, nil, collisionsX, collisionsZ, collisionsByDefault)
	self.goalsReached = {} -- {[nodeId]: true}
	if not success then return {}, self end
	-- Setup goal data
	local goalData = {}
	for _, goal in pairs(goals) do
		local data = AJPS._getGoalData(self, goal)
		if data then
			table.insert(goalData, data)
		end
	end
	if #goalData == 0 then return {}, self end
	self.goals = goalData
	self.stopAtFirst = stopAtFirst or false
	-- Find Goals
	MultipleGoals.findGoals(self, self.start, self.startNodeId)
	-- Convert goalsReached to a list of Vector2
	local goalsReached = {}
	for nodeId in pairs(self.goalsReached) do
		local x,z = NodeUtil.getPosFromId(gridSize.X, nodeId)
		table.insert(goalsReached, Vector2.new(x,z))
	end
	return goalsReached, self
end

function AJPS.fill(
	gridSize: Vector2,
	start: Vector2,
	collisionsX: CollisionGrid.CollisionGridList,
	collisionsZ: CollisionGrid.CollisionGridList,
	collisionsByDefault: boolean?
): any
	local success, self = AJPS._setup(gridSize, start, nil, collisionsX, collisionsZ, collisionsByDefault)
	self.goalsReached = {} -- {[nodeId]: true}
	self.nodesReached = {} -- {[nodeId]: true}
	if not success then return self end
	self.goals = {{
		goal = Vector3.new(-1,0),
		nodeId = -1,
		goalGroupIdX = -1,
		goalGroupIdZ = -1,
		goalBitX = 0,
		goalBitZ = 0,
	}}
	self.stopAtFirst = false
	self.open = {}
	-- Find Goals
	Fill.fill(self, self.start, self.startNodeId)
	return self
end

function AJPS.reconstructPath(path: {Vector2}, noDiagonal: boolean?, diagonalPadding: boolean?): {Vector2}
	local newPath = {}
	if #path < 2 then
		return newPath
	end
	for i, node in ipairs(path) do
		local next = path[i+1]
		if not next then
			break
		end
		local points = plotLine(node.X, node.Y, next.X, next.Y)
		table.move(points, 1, #points, math.max(#newPath,1), newPath)
	end
	-- Add nodes to make the path not have any diagonal nodes
	if noDiagonal or diagonalPadding then
		local i = 1
		while i < #newPath do
			local node = newPath[i]
			i += 1
			local next = newPath[i]
			if node.X ~= next.X and node.Y ~= next.Y then
				local x, y = next.X, node.Y
				table.insert(newPath, i, Vector2.new(x, y))
				if diagonalPadding then
					i += 1
					x, y = node.X, next.Y
					table.insert(newPath, i, Vector2.new(x, y))
				end
			end
		end
	end
	return newPath
end

export type CollisionMap = CollisionGrid.CollisionMap
export type Path = {Vector2}
export type HeuristicName = "Chebyshev"
return AJPS
