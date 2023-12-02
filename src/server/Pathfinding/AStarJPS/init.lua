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
	start = Vector2Util.round(start)
	-- Return if start or goal is outside of grid
	if not GridUtil.isInGrid(gridSize.X, gridSize.Y, start.X, start.Y) then
		return false, {}
	end
	--
	local self = {}
	self.collisionsByDefault = collisionsByDefault
	self.gridSize = gridSize
	self.start = start
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
	local startNodeId = NodeUtil.getNodeId(gridSize.X, start.X, start.Y)
	self.startNodeId = startNodeId
	self.g[startNodeId] = 0
	-- Check if start or goal is obstructed
	if not AJPSUtil.canWalk(self, start.X, start.Y) then
		return false, self
	end

	return true, self
end

function AJPS._getGoalData(self, goal: Vector2)
	goal = Vector2Util.round(goal)
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
	if goalNode and goal ~= goalNode then
		table.insert(self.path, goal)
	end
	-- Reconstruct path
	reconstructPath(self, goalNode)
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
	-- Remove the goal node if it's the same as the node before the goal
	-- (The findPath function adds the exact goal position to the path without the coordinates being integers)
	local goalNode: Vector2?
	if Vector2Util.round(path[1]) == path[2] then
		goalNode = table.remove(path, 1)
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
	if goalNode then
		table.insert(newPath, 1, goalNode)
	end
	return newPath
end

export type CollisionMap = CollisionGrid.CollisionMap
export type Path = {Vector2}
export type HeuristicName = "Chebyshev"
return AJPS
