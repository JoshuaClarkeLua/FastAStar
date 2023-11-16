local ServerScriptService = game:GetService("ServerScriptService")
local GridConfig = require(script.GridConfig)
local PriorityQueue = require(script.Parent.PriorityQueue)
local Job = require(ServerScriptService.Server.Job)
type NodeGrid = GridConfig.NodeGrid

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



local partFolder = Instance.new("Folder")
partFolder.Name = "Grid Parts"
partFolder.Parent = workspace
local function part(pos: Vector2): BasePart
	local p = Instance.new("Part")
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Position = Vector3.new(pos.X, 0, pos.Y)
	p.Anchored = true
	p.Size = Vector3.one
	p.Parent = partFolder
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

local function getNodeCost(grid: any, x: number, y: number): number
	if grid[x] then
		return grid[x][y] or math.huge
	end
	return math.huge
end

local function setNodeCost(grid: any, x: number, y: number, cost: number): ()
	grid[x] = grid[x] or {}
	grid[x][y] = cost
end


local job = Job.new(script.FastMarch, 64, true)
if not job.IsReady then
	job.OnReady:Wait()
end

local s = os.clock()

local grid = {
	[TARGET[1]] = {
		[TARGET[2]] = TARGET_COST,
	}
}
local queue = {TARGET}
while #queue > 0 do
	-- get queued node
	local node = table.remove(queue, 1)
	--
	for _, dir in ipairs(DIR) do
		local nextNode = {node[1] + dir.X, node[2] + dir.Y}
		if isInGrid(nextNode[1], nextNode[2]) then
			local newCost = getNodeCost(grid, node[1], node[2]) + getDirCost(dir)
			if newCost < getNodeCost(grid, nextNode[1], nextNode[2]) then
				setNodeCost(grid, nextNode[1], nextNode[2], newCost)
				table.insert(queue, nextNode)
				-- task.defer(function()
				-- 	local nc = math.min(1, getNormCost(newCost))
				-- 	part(Vector2.new(nextNode[1], nextNode[2])).Color = Color3.new(nc,nc,nc)
				-- end)
			end
		end
	end
end

print('time: ', os.clock() - s)