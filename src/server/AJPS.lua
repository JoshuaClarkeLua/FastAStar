local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GridUtil = require(ReplicatedStorage.Shared.GridUtil)
local PriorityQueue = require(ReplicatedStorage.Shared.PriorityQueue)
local Vector2Util = require(ReplicatedStorage.Shared.Vector2Util)
local Vector3Util = require(ReplicatedStorage.Shared.Vector3Util)
local CostGrid = require(ServerScriptService.Server.Pathfinding.CostGrid)
local NodeUtil = require(ServerScriptService.Server.Pathfinding.CostGrid.NodeUtil)

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

local function calF(self, node: Vector2): number
	return self.hFn(node, self.goal)
end

local function getG(self, nodeId: number): number
	return self.g[nodeId] or math.huge
end

local function nextNode(self): (Vector2?, number?)
	local node = self.open:Pop()
	if not node then return end
	local nodeId = NodeUtil.getNodeId(self.gridSize.X, node.X, node.Y)
	self.openDict[nodeId] = nil
	return node, nodeId
end
local function canWalk(self, x, y): boolean
	return GridUtil.isInGrid(self.gridSize.X, self.gridSize.Y, x, y) and CostGrid.GetCost(self.costs, self.gridSize, x, y) < BLOCKED
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
	local jumpNodeId = NodeUtil.getNodeId(self.gridSize.X, node.X, node.Y)
	if self.closed[jumpNodeId] then
		return
	end
	if node == self.goal then
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
	if self.closed[nodeId] or not canWalk(self, node.X, node.Y) then
		return
	end
	
	self.parents[node] = pNode

	if node == self.goal then
		return node
	end

	local dir = Vector2Util.sign(node - pNode)
	local g = pG + Diagonal(node, pNode)

	-- Check forced neighbors in the direction of travel
	if AJPS._hasForcedNeighbors(self, node, dir) then
		AJPS._queueJumpNode(self, node, pNode, g)
		return
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
	end

	return AJPS._jump(self, node + dir, node, g)
end

local function findGoalJPS(self, pNode, pNodeId): Vector2?
	while pNode do
		local neighbors = AJPS._findNeighbors(self, pNode, self.parents[pNode])
		local _g = getG(self, pNodeId)

		for _, node in ipairs(neighbors) do
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
	while cNode do
		table.insert(self.path, cNode)
		-- local p = _doPart(cNode)
		-- p.Color = Color3.new(1,0,0)
		local pNode = self.parents[cNode]
		cNode = pNode
	end
end

function AJPS.findPath(
	gridSize: Vector2,
	start: Vector2,
	goal: Vector2,
	costs: CostGridList?,
	heuristic: HeuristicName?
): AJPS
	local self = {}
	self.gridSize = gridSize
	self.start = start
	self.goal = goal
	self.costs = costs or {}
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
	return self
end

type CostGridList = CostGrid.CostGridList
export type AJPS = typeof(AJPS.findPath(...))
export type HeuristicName = "Chebyshev"
return AJPS
