local Imports = require(script.Parent.Imports)
local PriorityQueue = Imports.PriorityQueue
local Vector2Util = Imports.Vector2Util
local AJPSUtil = require(script.AJPSUtil)
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

function AJPS._setup(
	gridSize: Vector2,
	start: Vector2,
	heuristic: HeuristicName?,
	...: CollisionMap
)
	start = Vector2Util.round(start)
	-- Return if start or goal is outside of grid
	if not GridUtil.isInGrid(gridSize.X, gridSize.Y, start.X, start.Y) then
		return
	end
	--
	local self = {}
	self.gridSize = gridSize
	self.start = start
	-- Setup map lists
	self.costsX, self.costsZ = CollisionGrid.combineMaps(...)
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
		return
	end

	return self
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
	...: CollisionMap
): Path
	local self = AJPS._setup(gridSize, start, heuristic, ...)
	if not self then return {} end
	-- Setup goal data
	local goalData = AJPS._getGoalData(self, goal)
	if not goalData then return {} end
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
	local goalNode = SingleGoal.findGoalJPS(self, self.start, self.startNodeId)
	if goalNode and goal ~= goalNode then
		table.insert(self.path, goal)
	end
	-- Reconstruct path
	reconstructPath(self, goalNode)
	return self.path
end

function AJPS.findReachable(
	gridSize: Vector2,
	start: Vector2,
	goals: {Vector2},
	stopAtFirst: boolean?,
	...: CollisionMap
): {Vector2}
	local self = AJPS._setup(gridSize, start, nil, ...)
	if not self then return {} end
	-- Setup goal data
	local goalData = {}
	for _, goal in ipairs(goals) do
		local data = AJPS._getGoalData(self, goal)
		if data then
			table.insert(goalData, data)
		end
	end
	if #goalData == 0 then return {} end
	self.goals = goalData
	self.stopAtFirst = stopAtFirst or false
	self.goalsReached = {} -- {[nodeId]: true}
	-- Find Goals
	MultipleGoals.findGoals(self, self.start, self.startNodeId)
	-- Convert goalsReached to a list of Vector2
	local goalsReached = {}
	for nodeId in pairs(self.goalsReached) do
		local x,z = NodeUtil.getPosFromId(gridSize.X, nodeId)
		table.insert(goalsReached, Vector2.new(x,z))
	end
	return goalsReached
end

export type CollisionMap = CollisionGrid.CollisionMap
export type Path = {Vector2}
export type HeuristicName = "Chebyshev"
return AJPS
