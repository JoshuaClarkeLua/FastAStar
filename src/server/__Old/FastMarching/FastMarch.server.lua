local ServerScriptService = game:GetService("ServerScriptService")
local GridConfig = require(ServerScriptService.Server.FastMarching.GridConfig)
local Job = require(ServerScriptService.Server.Job)

type NodeGrid = GridConfig.NodeGrid

--
local DIR = GridConfig.DIR
local DIR_COST = GridConfig.DIR_COST
local TARGET = GridConfig.TARGET
local TARGET_COST = GridConfig.TARGET_COST
local TARGET_COL = GridConfig.TARGET_COL
local MAX_COST = GridConfig.MAX_COST
--
local MIN_X = GridConfig.MIN_X
local MIN_Y = GridConfig.MIN_Y
local MAX_X = GridConfig.MAX_X
local MAX_Y = GridConfig.MAX_Y
--

local actor = Job.getActor()

local function part(pos: Vector2): BasePart
	local p = Instance.new("Part")
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Position = Vector3.new(pos.X, 0, pos.Y)
	p.Anchored = true
	p.Size = Vector3.one
	p.Parent = workspace
	if pos == TARGET then
		p.Color = TARGET_COL
	end
	return p
end

local function getDirCost(dir: Vector2): number
	return DIR_COST[dir] or error("Invalid direction")
end

local function isInGrid(x: number, y: number): boolean
	return x >= MIN_X and x <= MAX_X and y >= MIN_Y and y <= MAX_Y
end

local function getNormCost(cost: number): number
	return cost / MAX_COST
end

local function getXTable(grid: NodeGrid, x: number): SharedTable
	if grid[x] == nil then
		local thread = coroutine.running()
		SharedTable.update(grid, x, function(v)
			if v ~= nil then
				task.spawn(thread)
			else
				task.defer(thread)
			end
			return v or SharedTable.new({})
		end)
		while grid[x] == nil do
			coroutine.yield()
		end
	end
	return grid[x]
end

local function getNodeCost(grid: NodeGrid, x: number, y: number): number
	local xTable = getXTable(grid, x)
	if xTable then
		return grid[x][y] or math.huge
	end
	return math.huge
end

local function setNodeCost(grid: NodeGrid, x: number, y: number, cost: number): ()
	local xTable = getXTable(grid, x)
	grid[x][y] = cost
end

local function updateNodeCost(grid: NodeGrid, x: number, y: number): ()
	local xTable = getXTable(grid, x)
	SharedTable.update(xTable, y, function(_cost: number?)
		local cost = _cost or math.huge
	end)
end

actor:BindToMessageParallel("GetCost", function(self, data, ...: number)
	local grid = data.grid

	local costs = {}
	for i = 1, select('#', ...), 2 do
		local node = select(i, ...)
		local priority = select(i + 1, ...) + 1
		for _, dir in ipairs(DIR) do
			local nextNode = {node[1] + dir.X, node[2] + dir.Y}
			if isInGrid(nextNode[1], nextNode[2]) then
				local newCost = getNodeCost(grid, node[1], node[2]) + getDirCost(dir)
				table.insert(costs, {
					nextNode,
					priority,
					newCost,
				})
			end
		end
	end

	task.synchronize()
	for i, v in ipairs(costs) do
		local nextNode = v[1]
		local newCost = v[3]
		v[3] = nil
		if newCost < getNodeCost(grid, nextNode[1], nextNode[2]) then
			setNodeCost(grid, nextNode[1], nextNode[2], newCost)
			--
			task.defer(function()
				local nc = getNormCost(newCost)
				part(Vector2.new(nextNode[1], nextNode[2])).Color = Color3.new(nc,nc,nc)
			end)
		else
			table.remove(costs, i)
		end
	end
	self:Return(costs)
end)
