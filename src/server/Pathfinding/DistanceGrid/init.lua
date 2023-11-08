local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SharedTableRegistry = game:GetService("SharedTableRegistry")
local NodeUtil = require(ServerScriptService.Server.Pathfinding.CostGridManager.NodeUtil)
local ParallelJobHandler = require(ReplicatedStorage.Packages.ParallelJobHandler)
local CostGrid = require(script.Parent.CostGridManager)

type CostGrid = CostGrid.CostGrid

local DIR = {
	Vector2.new(-1,0), Vector2.new(1,0), Vector2.new(0,-1), Vector2.new(0,1), -- Cardinal
	-- Vector2.new(-1,-1), Vector2.new(1,-1), Vector2.new(-1,1), Vector2.new(1,1), -- Diagonal
}
local ALL_DIR = {
	Vector2.new(-1,0), Vector2.new(1,0), Vector2.new(0,-1), Vector2.new(0,1), -- Cardinal
	Vector2.new(-1,-1), Vector2.new(1,-1), Vector2.new(-1,1), Vector2.new(1,1), -- Diagonal
}
local DIR_COST = {
	[DIR[1]] = 1,
	[DIR[2]] = 1,
	[DIR[3]] = 1,
	[DIR[4]] = 1,
	-- [DIR[5]] = 1.4,
	-- [DIR[6]] = 1.4,
	-- [DIR[7]] = 1.4,
	-- [DIR[8]] = 1.4,
}
local MAX_ITER = 100
local TOLERANCE = 1e-6

local MAX_COST = 65535
local MIN_COST = 1
local TARGET_COST = MIN_COST - 1
local BLOCKED_COST = MAX_COST + 1

local DistanceGrid = {}
DistanceGrid.COST = {
	MAX = MAX_COST,
	MIN = MIN_COST,
	BLOCKED = BLOCKED_COST,
}

local function getDirCost(dir: Vector2): number
	return DIR_COST[dir] or error("Invalid direction")
end

local function isInGrid(min: {number}, max: {number}, x: number, z: number): boolean
	return x >= min[1] and x <= max[1] and z >= min[2] and z <= max[2]
end
local function isInGrid2(size: Vector2, x: number, z: number): boolean
	return x >= 0 and x <= size.X and z >= 0 and z <= size.Y
end

-- local function getNormCost(cost: number): number
-- 	return cost / MAX_COST
-- end

local function getNodeCost(grid: any, gridSize: Vector2, x: number, z: number, ifnil: any): number
	local nodeId = NodeUtil.getNodeId(gridSize.X, x, z)
	return grid[nodeId] or ifnil
end

local function setNodeCost(grid: any, gridSize: Vector2, x: number, z: number, cost: number): ()
	local nodeId = NodeUtil.getNodeId(gridSize.X, x, z)
	grid[nodeId] = cost
end


function DistanceGrid.fmm(grid: any, min: {number}, max: {number}, costs: SharedTable, target: {number})
	local queue = {
		[1] = {target[1],target[2]},
		[2] = {},
	}
	while #queue[1] > 0 do
	-- local queue = {target}
	-- while #queue > 0 do
		-- task.wait()
		-- local node = table.remove(queue, 1)
		local x = queue[1][1]
		local z = queue[1][2]
		local numQ1 = #queue[1]
		queue[1][1] = nil
		queue[1][2] = nil
		queue[1][1] = queue[1][numQ1 - 1]
		queue[1][2] = queue[1][numQ1]
		queue[1][numQ1 - 1] = nil
		queue[1][numQ1] = nil
		local nodeCost = getNodeCost(grid, x, z)
		--
		for _, dir in ipairs(DIR) do
			-- local nextNode = {node[1] + dir.X, node[2] + dir.Y}
			local nx, nz = x + dir.X, z + dir.Y
			
			if isInGrid(min, max, nx, nz) then
				local zT = costs[nx]
				local cost = zT and zT[nz] or nil
				-- Ignore blocked nodes
				if cost and cost > MAX_COST then
					continue
				end
				-- Multiply dir cost by node cost
				-- local totalCost = getDirCost(dir)
				-- if cost then
				-- 	totalCost *= cost + 1
				-- end
				--
				local newCost = nodeCost + 1
				if newCost < getNodeCost(grid, nx,nz) then
					setNodeCost(grid, nx,nz, newCost)
					-- table.insert(queue, nextNode)
					queue[2][#queue[2] + 1] = nx
					queue[2][#queue[2] + 1] = nz
					-- table.insert(queue[2], nextNode)
				end
			end
		end
		if #queue[1] == 0 then
			queue[1] = queue[2]
			queue[2] = {}
		end
	end
end

function DistanceGrid.fmm2(grid: any, size: Vector2, costs: SharedTable, target: {number})
	setNodeCost(grid, size, target[1], target[2], TARGET_COST)
	local queue = {
		[1] = {target[1],target[2]},
		[2] = {},
	}
	while #queue[1] > 0 do
	-- local queue = {target}
	-- while #queue > 0 do
		-- task.wait()
		-- local node = table.remove(queue, 1)
		local x = queue[1][1]
		local z = queue[1][2]
		local numQ1 = #queue[1]
		queue[1][1] = nil
		queue[1][2] = nil
		queue[1][1] = queue[1][numQ1 - 1]
		queue[1][2] = queue[1][numQ1]
		queue[1][numQ1 - 1] = nil
		queue[1][numQ1] = nil
		local nodeCost = getNodeCost(grid, size, x, z, math.huge)
		--
		for _, dir in ipairs(DIR) do
			-- local nextNode = {node[1] + dir.X, node[2] + dir.Y}
			local nx, nz = x + dir.X, z + dir.Y
			
			if isInGrid2(size, nx, nz) then
				local cost = getNodeCost(costs, size, nx, nz)
				-- Ignore blocked nodes
				if cost and cost > MAX_COST then
					continue
				end
				-- Multiply dir cost by node cost
				-- local totalCost = getDirCost(dir)
				-- if cost then
				-- 	totalCost *= cost + 1
				-- end
				--
				local newCost = nodeCost + 1
				if newCost < getNodeCost(grid, size, nx, nz, math.huge) then
					setNodeCost(grid, size, nx, nz, newCost)
					-- table.insert(queue, nextNode)
					queue[2][#queue[2] + 1] = nx
					queue[2][#queue[2] + 1] = nz
					-- table.insert(queue[2], nextNode)
				end
			end
		end
		if #queue[1] == 0 then
			queue[1] = queue[2]
			queue[2] = {}
		end
	end
end

local function getV(grid: any, x: number, z: number, ifnil: any): number
	return grid[x] and grid[x][z] or ifnil or math.huge
end
local function setV(grid: any, x: number, z: number, cost: number): ()
	local zT = grid[x]
	if not zT then
		grid[x] = {
			[z] = cost,
		}
	else
		-- zT = grid[x]
		zT[z] = cost
	end
end
local function fsm(grid: any, min: {number}, max: {number}, costs: SharedTable, target: {number})
	local minX,minZ = min[1], min[2]
	local maxX,maxZ = max[1], max[2]
	local tx, tz = target[1], target[2]

	local tcost = getV(costs, tx, tz, 1)
	local tc = getV(grid, tx, tz)
	local min_dtZ = math.abs(minZ - tz)
	local min_dtX = math.abs(minX - tx)
	local max_dtZ = math.abs(maxZ - tz)
	local max_dtX = math.abs(maxX - tx)
	for x = minX, maxX do
		local dtx = math.abs(x - tx)
		setV(grid, x, minZ, tc + (dtx + min_dtZ) * tcost)
		setV(grid, x, maxZ, tc + (dtx + max_dtZ) * tcost)
	end
	for z = minZ, maxZ do
		local dtz = math.abs(z - tz)
		setV(grid, minX, z, tc + (dtz + min_dtX) * tcost)
		setV(grid, maxX, z, tc + (dtz + max_dtX) * tcost)
	end

	
	-- Main FSM loop
	for iteration = 1, MAX_ITER do
		local maxChange = 0.0
	
		-- Sweep from top to bottom, left to right
		for i = minX + 1, maxX do
			for j = minZ + 1, maxZ do
				local cost = getV(grid,i,j)
				local newCost = math.min(
					cost,
					getV(grid,i,j-1) + getV(costs, i, j - 1, 1),
					getV(grid,i-1,j) + getV(costs, i - 1, j, 1)
				)
				if newCost > MAX_COST then
					continue
				end
	
				if math.abs(cost - newCost) > maxChange then
					maxChange = math.abs(cost - newCost)
				end
	
				setV(grid,i,j,newCost)
			end
		end
	
		-- Sweep from bottom to top, right to left
		for i = maxX - 1, minX, -1 do
			for j = maxZ - 1, minZ, -1 do
				local cost = getV(grid,i,j)
				local newCost = math.min(
					cost,
					getV(grid,i,j+1) + getV(costs, i, j + 1, 1),
					getV(grid,i+1,j) + getV(costs, i + 1, j, 1)
				)
				if newCost > MAX_COST then
					continue
				end
	
				if math.abs(cost - newCost) > maxChange then
					maxChange = math.abs(cost - newCost)
				end
	
				setV(grid,i,j,newCost)
			end
		end
	
		-- Check for convergence
		if maxChange < TOLERANCE then
			print(iteration, maxChange)
			break
		end
	end
end

function DistanceGrid.setTarget(grid: any, min: {number}, max: {number}, costs: SharedTable, target: {number})
	local minX,minZ = min[1], min[2]
	local maxX,maxZ = max[1], max[2]
	local tx, tz = target[1], target[2]

	local tc = getV(grid, tx, tz)
	local min_dtZ = math.abs(minZ - tz)
	local min_dtX = math.abs(minX - tx)
	local max_dtZ = math.abs(maxZ - tz)
	local max_dtX = math.abs(maxX - tx)
	for x = minX, maxX do
		local dtx = math.abs(x - tx)
		setV(grid, x, minZ, tc + (dtx + min_dtZ) * getV(costs, x, minZ, 1))
		setV(grid, x, maxZ, tc + (dtx + max_dtZ) * getV(costs, x, maxZ, 1))
	end
	for z = minZ, maxZ do
		local dtz = math.abs(z - tz)
		setV(grid, minX, z, tc + (dtz + min_dtX) * getV(costs, minX, z, 1))
		setV(grid, maxX, z, tc + (dtz + max_dtX) * getV(costs, maxX, z, 1))
	end
end

local function barrierSync(bSync: BindableEvent, bStart: BindableEvent, fn: () -> ()): ()
	task.synchronize()
	local resumed = false
	local thread = coroutine.running()
	bStart.Event:Once(function()
		resumed = true
		coroutine.resume(thread)
	end)
	bSync:Fire()
	if not resumed then
		coroutine.yield()
	end
	fn()
	task.desynchronize()
end

local function syncMaxChange(maxChangeRecv: BindableEvent, maxChangeSend: BindableEvent, _maxChange: number): number
	task.synchronize()
	local thread = coroutine.running()
	local maxChange
	maxChangeRecv.Event:Once(function(_maxChange: number)
		maxChange = _maxChange
		-- print('max change received', _maxChange)
		coroutine.resume(thread)
	end)
	maxChangeSend:Fire(_maxChange)
	if not maxChange then
		coroutine.yield()
	end
	task.desynchronize()
	return maxChange
end

function DistanceGrid.getPart(x,z): BasePart
	return workspace.Parts:FindFirstChild(`{x};{z}`)
end

local function _updateColor(grid): ()
	task.synchronize()
	local h = DistanceGrid.getHighestDist(grid)
	DistanceGrid.iter(grid, function(x,z,cost)
		local p = getPart(x,z)
		if p then
			p.Color = Color3.fromHSV(cost/h, 1, 1)
			p:SetAttribute("Cost", cost)
		end
	end)
	task.desynchronize()
end

function DistanceGrid.fsm(tid,jid,minX,maxX, bSync: BindableEvent, bStart: BindableEvent, maxChangeRecv: BindableEvent, maxChangeSend: BindableEvent)
	local grid = SharedTableRegistry:GetSharedTable(`DistanceGrid_{jid}`)
	local costs = SharedTableRegistry:GetSharedTable(`CostGrid_{jid}`)
	local data = SharedTableRegistry:GetSharedTable(`Data_{jid}`)
	local min, max = data.min, data.max
	local minZ, maxZ = min[2], max[2]
	local target = data.target


	local s = os.clock()
	-- Main FSM loop
	for iteration = 1, MAX_ITER do
		local maxChange = 0.0
	
		-- Sweep from top to bottom, left to right
		-- for i = math.max(minX, min[1] + 1), math.min(maxX + 1, max[1]) do
		-- 	for j = math.max(minZ, min[2] + 1), math.min(maxZ + 1, min[2]) do
		for i = minX + 1, maxX do
			for j = minZ + 1, maxZ do
				local cost = getV(grid,i,j)
				local newCost = math.min(
					cost,
					getV(grid,i,j-1) + getV(costs, i, j - 1, 1),
					getV(grid,i-1,j) + getV(costs, i - 1, j, 1)
				)
				if newCost > MAX_COST then
					continue
				end
	
				if math.abs(cost - newCost) > maxChange then
					maxChange = math.abs(cost - newCost)
				end
	
				setV(grid,i,j,newCost)
			end
		end

		-- print('barrier')
		-- _updateColor(grid)
		-- task.wait(2)
		barrierSync(bSync, bStart, function()
			-- print(tid, 'X',CostGrid.denormalize(minX))
			-- print(tid, 'Z',CostGrid.denormalize(math.max(minZ, min[2] + 1), minZ + 1))

			for j = minZ + 1, maxZ do
				-- minX
				local i = minX
				local cost = getV(grid,i,j)
				local newCost = math.min(
					cost,
					getV(grid,i,j-1) + getV(costs, i, j-1, 1),
					getV(grid,i-1,j) + getV(costs, i-1, j, 1)
				)
				if newCost > MAX_COST then
					continue
				end
	
				if math.abs(cost - newCost) > maxChange then
					maxChange = math.abs(cost - newCost)
				end
	
				setV(grid,i,j,newCost)
				-- maxX
				--[[ local i = maxX
				local cost = getV(grid,i,j)
				local newCost = math.min(
					cost,
					getV(grid,i,j+1) + getV(costs, i, j+1, 1),
					getV(grid,i+1,j) + getV(costs, i+1, j, 1)
				)
				if newCost > MAX_COST then
					continue
				end
	
				if math.abs(cost - newCost) > maxChange then
					maxChange = math.abs(cost - newCost)
				end
	
				setV(grid,i,j,newCost) ]]
			end
		end)
	
		-- Sweep from bottom to top, right to left
		-- for i = math.min(maxX, max[1] - 1), math.max(minX - 1, min[1]), -1 do
		-- 	for j = math.min(maxZ, max[2] - 1), math.max(minZ - 1, min[2]), -1 do
		for i = maxX - 1, minX, -1 do
			for j = maxZ - 1, minZ, -1 do
				local cost = getV(grid,i,j)
				local newCost = math.min(
					cost,
					getV(grid,i,j+1) + getV(costs, i, j + 1, 1),
					getV(grid,i+1,j) + getV(costs, i + 1, j, 1)
				)
				if newCost > MAX_COST then
					continue
				end
	
				if math.abs(cost - newCost) > maxChange then
					maxChange = math.abs(cost - newCost)
				end
	
				setV(grid,i,j,newCost)
			end
		end
		
		-- print('barrier')
		-- _updateColor(grid)
		-- task.wait(2)
		barrierSync(bSync, bStart, function()
			-- print(tid, 'X',CostGrid.denormalize(math.min(maxX, max[1] - 1), maxX - 1))
			-- print(tid, 'Z',CostGrid.denormalize(math.min(maxZ, max[2] - 1), maxZ - 1))
			for j = maxZ - 1, minZ, -1 do
				-- maxX
				local i = maxX
				local cost = getV(grid,i,j)
				local newCost = math.min(
					cost,
					getV(grid,i,j+1) + getV(costs, i, j+1, 1),
					getV(grid,i+1,j) + getV(costs, i+1, j, 1)
				)
				if newCost > MAX_COST then
					continue
				end
	
				if math.abs(cost - newCost) > maxChange then
					maxChange = math.abs(cost - newCost)
				end
	
				setV(grid,i,j,newCost)
				-- minX
				--[[ local i = minX
				local cost = getV(grid,i,j)
				local newCost = math.min(
					cost,
					getV(grid,i,j-1) + getV(costs, i, j-1, 1),
					getV(grid,i-1,j) + getV(costs, i-1, j, 1)
				)
				if newCost > MAX_COST then
					continue
				end
	
				if math.abs(cost - newCost) > maxChange then
					maxChange = math.abs(cost - newCost)
				end
	
				setV(grid,i,j,newCost) ]]
			end
		end)
		-- print(maxChange)
		maxChange = syncMaxChange(maxChangeRecv, maxChangeSend, maxChange)
	
		-- Check for convergence
		if maxChange < TOLERANCE then
			-- print(iteration, maxChange)
			break
		end
	end
	warn(tid, os.clock() - s)
end


type JobHandler = ParallelJobHandler.JobHandler
function DistanceGrid.new(job: ParallelJobHandler.Job, costGrid: CostGrid, size: Vector2, target: Vector2): DistanceGrid
	local _target = {target.X, target.Y}
	local _min, _max = {1,1},{size.X,size.Y}


	--[[ for i = 1, 2 do
		local job: ParallelJobHandler.Job = handler:NewJob(i)
		local jid = job._id
		local _target = {CostGrid.normalize(target.X, target.Y)}
		local _grid = SharedTable.new({})
		setV(_grid, _target[1], _target[2], TARGET_COST)
		local _min, _max = {CostGrid.normalize(min.X, min.Y)},{CostGrid.normalize(max.X, max.Y)}
		local bSync = Instance.new("BindableEvent")
		local bStart = Instance.new("BindableEvent")
		local maxChangeSend = Instance.new("BindableEvent")
		local maxChangeRecv = Instance.new("BindableEvent")
		local barrierReached = 0
		bSync.Event:Connect(function()
			barrierReached += 1
			if barrierReached == job:NumActors() then
				-- print('barrier reached')
				barrierReached = 0
				bStart:Fire()
			end
		end)
		local maxChangeSent = 0
		local maxChange = 0
		maxChangeSend.Event:Connect(function(_maxChange: number)
			maxChangeSent += 1
			maxChange = math.max(maxChange, _maxChange)
			if maxChangeSent == job:NumActors() then
				-- print('max change reached', maxChange)
				-- print('------------------------------------------------------')
				_maxChange = maxChange
				maxChangeSent = 0
				maxChange = 0
				maxChangeRecv:Fire(_maxChange)
			end
		end)

		SharedTableRegistry:SetSharedTable(`DistanceGrid_{jid}`, _grid)
		SharedTableRegistry:SetSharedTable(`CostGrid_{jid}`, costGrid)
		DistanceGrid.setTarget(_grid, _min, _max, costGrid, _target)
		local data = SharedTable.new({
			min = _min,
			max = _max,
			target = _target,
		})
		SharedTableRegistry:SetSharedTable(`Data_{jid}`, data)

		
		local threads = 4
		local tid = 1
		local xPerThread = math.ceil((_max[1] - _min[1]) / threads)

		local s = os.clock()
		-- job:BindTopic("FSM", function(actor)
		-- 	-- print(os.clock() - s)
		-- end)
		job:Run(function(actor: ParallelJobHandler.JobActor)
			local xStart, xEnd = _min[1] + xPerThread * (tid - 1) + 1, _min[1] + xPerThread * tid
			-- local xStart, xEnd = _min[1], _max[1]
			actor:SendMessage("FSM", tid, xStart, math.min(xEnd, _max[1]), bSync, bStart, maxChangeRecv, maxChangeSend)
			tid += 1
			return tid > threads
		end)
		job:OnFinish():andThen(function()
			print(`FINISHED {i}`)
			print(os.clock() - s)
			-- local h = DistanceGrid.getHighestDist(_grid)
			-- DistanceGrid.iter(_grid, function(x,z,cost)
			-- 	local p = getPart(x,z)
			-- 	if p then
			-- 		p.Color = Color3.fromHSV(cost/h, 1, 1)
			-- 		p:SetAttribute("Cost", cost)
			-- 	end
			-- end)
		end)
	end ]]

	-- local s = os.clock()
	-- fsm(_grid, _min, _max, costGrid, _target)
	-- DistanceGrid.fmm(_grid, _min, _max, costGrid, {_target})
	job:Run(function(actor: ParallelJobHandler.JobActor)
		actor:SendMessage("GetDistanceGrid", size, _target)
		return true
	end)
	-- print(os.clock() - s)

	-- Convert to shared table
	-- local grid = {}
	-- for x, zT in pairs(_grid) do
	-- 	grid[x] = SharedTable.new(zT)
	-- end
	-- return SharedTable.new(grid)
	-- return _grid
end

function DistanceGrid.recalculate(grid: DistanceGrid, costGrid: CostGrid, min: Vector2, max: Vector2, startNodes: {{number}}): ()
	if #startNodes == 0 then
		return
	end
	-- Normalize nodes
	for _, node in ipairs(startNodes) do
		node[1], node[2] = CostGrid.normalize(node[1], node[2])
	end
	-- Sort queue to start with lower cost nodes first
	table.sort(startNodes, function(a: {number}, b: {number})
		return getNodeCost(grid, a[1], a[2]) < getNodeCost(grid, b[1], b[2])
	end)
	--
	local _min, _max = {CostGrid.normalize(min.X, min.Y)},{CostGrid.normalize(max.X, max.Y)}
	DistanceGrid.fmm(grid, _min, _max, costGrid, startNodes)
end

function DistanceGrid.getHighestDist(grid: DistanceGrid): number
	local highest = 0
	for nodeId, cost in grid do
		if cost > highest then
			highest = cost
		end
	end
	return highest
end

function DistanceGrid.iter(grid: DistanceGrid, gridSize: Vector2, iterator: (x: number, z: number, dist: number) -> ()): ()
	for nodeId, cost in grid do
		local x, z = NodeUtil.getPosFromId(gridSize.X, nodeId)
		iterator(x, z, cost)
	end
end

function DistanceGrid.getLowestNeighbor(grid: DistanceGrid, x: number, z: number): (number, number)
	local lowest = getNodeCost(grid, x, z)
	local lx, lz = x, z
	for _, dir in ipairs(ALL_DIR) do
		local _x = x + dir.X
		local _z = z + dir.Y
		local cost = getNodeCost(grid, _x, _z)
		if cost < lowest then
			lowest = cost
			lx, lz = _x, _z
		end
	end
	return CostGrid.denormalize(lx, lz)
end

export type DistanceGrid = typeof(DistanceGrid.new(...))
return DistanceGrid