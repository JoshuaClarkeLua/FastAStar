local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedTableRegistry = game:GetService("SharedTableRegistry")
local ParallelJobHandler = require(ReplicatedStorage.Packages.ParallelJobHandler)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Bit32Util = require(ReplicatedStorage.Shared.Bit32Util)
local Vector2Util = require(ReplicatedStorage.Shared.Vector2Util)
local Vector3Util = require(ReplicatedStorage.Shared.Vector3Util)

type JobHandler = ParallelJobHandler.JobHandler
export type ObsData = {
	cf: CFrame,
	size: Vector3,	
}
export type ObsNodes = {number} -- {x, z, x, z, ...}

local XZ = Vector3.new(1,0,1)
local P2_32 = 2^32-1


local CostGrid = {}
CostGrid.__index = CostGrid

function CostGrid.getNodesInBox(origin, gridSize, cf, size): ObsNodes
	cf = origin:ToObjectSpace(cf)
	local pos = cf.Position
	local pos2d = Vector2.new(pos.X, pos.Z)
	local size2 = size/2
	-- Determine which axis is longer (for width and length)
	local lenV: Vector3, widV: Vector3
	if size.Z >= size.X then
		lenV = Vector3.zAxis
		widV = Vector3.xAxis
	else
		lenV = Vector3.xAxis
		widV = Vector3.zAxis
	end
	--
	local line = cf:VectorToWorldSpace(size * lenV) * XZ
	local line2d = Vector2.new(line.X, line.Z)
	local lineMag2 = line2d.Magnitude/2
	-- Calculate the square's opposite corners which fit the line
	local rsize2 = cf:VectorToWorldSpace(size2) * XZ
	local nrsize2 = cf:VectorToWorldSpace(Vector3.new(-size2.X, 0, size2.Z))
	local p1 = rsize2
	local p2 = -rsize2
	local p3 = nrsize2
	local p4 = -nrsize2
	local min: Vector2 = Vector2Util.floor(pos2d + Vector2.new(math.min(p1.X, p2.X, p3.X, p4.X), math.min(p1.Z, p2.Z, p3.Z, p4.Z)))
	local max: Vector2 = Vector2Util.ceil(pos2d + Vector2.new(math.max(p1.X, p2.X, p3.X, p4.X), math.max(p1.Z, p2.Z, p3.Z, p4.Z)))
	
	local nodes = {} -- {x,z, x,z, ...}
	for x = min.X, max.X do
		if x < 0 or x > gridSize.X then
			continue
		end
		for z = min.Y, max.Y do
			if z < 0 or z > gridSize.Y then
				continue
			end
			local cellPos = Vector2.new(x,z) - pos2d
			local v2 = Vector3Util.project(cellPos, line2d)
	
			-- Check if cell is past the line (vertical check)
			if math.ceil(lineMag2 - v2.Magnitude + .5) >= 0 then
				-- Check if cell is too far from the line (horizontal check)
				local dist = (v2 - cellPos).Magnitude
				if math.floor(dist - .5) <= (widV * size2).Magnitude then
					table.insert(nodes, x)
					table.insert(nodes, z)
				end
			end
		end
	end

	return nodes
end

function CostGrid.new(handler: JobHandler, origin: CFrame, gridSize: Vector2): CostGrid
	assert(handler.IsReady, "JobHandler is not ready. Please wait for it to be ready before creating a new CostGrid instance with it.")
	local self = setmetatable({
		queued = {} :: {[string]: ObsData}, -- [id]: ObsData
		obstacles = {} :: {[string]: ObsNodes}, -- [id]: ObsNodes
		costs = {} :: {[string]: number}, -- [id]: number
		nodesX = {},
		nodesZ = {},
		--
		_handler = handler,
		_job = handler:NewJob('CostGrid'),
		_origin = origin,
		_gridSize = gridSize,
		_numGroupsX = math.ceil(gridSize.X/32),
		_numGroupsZ = math.ceil(gridSize.Y/32),
	}, CostGrid)
	-- Setup job
	local job = self._job
	SharedTableRegistry:SetSharedTable(`Data_{self._job._id}`, SharedTable.new({
		origin = origin * CFrame.new(-gridSize.X/2, 0, -gridSize.Y/2),
		gridSize = gridSize,
	}))

	-- Setup Job functions
	local function GetNodesInBox(actor): ()
		actor:SendMessage("GetNodesInBox", self:_GetQueued(32))
		return next(self.queued) == nil
	end
	self._GetNodesInBox = GetNodesInBox

	-- Setup topic handlers
	--[[
		TOPIC -> GetNodesInBox
	]]
	local function recvGetNodesInBox(id: string, nodes: ObsNodes, ...: string & ObsNodes): ()
		if id == nil then
			return
		end
		local cost = self.costs[id]
		if cost ~= nil then
			self.obstacles[id] = nodes
			-- Add nodes
			for i = 1, #nodes, 2 do
				local x = nodes[i]
				local z = nodes[i + 1]
				-- Update nodesX
				local groupId = (x * self._numGroupsX) + math.ceil((z + 1)/32)
				local group = self.nodesX[groupId] or 0
				self.nodesX[groupId] = bit32.replace(group, 1, z % 32)
				-- Update nodesZ
				groupId = (z * self._numGroupsZ) + math.ceil((x + 1)/32)
				group = self.nodesZ[groupId] or 0
				self.nodesZ[groupId] = bit32.replace(group, 1, x % 32)
			end
		end
		--
		return recvGetNodesInBox(...)
	end
	job:BindTopic("GetNodesInBox", function(actor, ...: string & ObsNodes)
		recvGetNodesInBox(...)
	end)
	--
	return self
end

function CostGrid:_GetQueued(amount: number): (...string & CFrame & Vector3)
	if amount == 0 then
		return
	end
	local id, data = next(self.queued)
	if id == nil then
		return
	end
	self.queued[id] = nil
	return id, data[1], data[2], self:_GetQueued(amount - 1)
end

function CostGrid:Add(id: string, cf: CFrame, size: Vector3, cost: number): ()
	if cost ~= cost or cost <= 0 or cost == math.huge or cost == -math.huge then
		error("Cost must be a valid number greater than 0, got", cost)
	end
	self.queued[id] = {cf, size}
	self.costs[id] = cost
	-- Run job
	self._job:Run(self._GetNodesInBox)
end

function CostGrid:Remove(id: string): ()
	local nodes = self.obstacles[id]
	local cost = self.costs[id]
	if cost ~= nil and nodes == nil then
		self.queued[id] = nil
	else
		for i = 1, #nodes, 2 do
			local x = nodes[i] + 1
			local z = nodes[i + 1]
			-- Update nodesX
			local groupId = (x * self._numGroupsX) + math.ceil((z + 1)/32)
			local group = self.nodesX[groupId]
			if group then
				local v = bit32.replace(group, 1, z % 32)
				self.nodesX[groupId] = v ~= 0 and v or nil
			end
			-- Update nodesZ
			groupId = (z * self._numGroupsZ) + math.ceil((x + 1)/32)
			group = self.nodesZ[groupId]
			if group then
				local v = bit32.replace(group, 1, x % 32)
				self.nodesZ[groupId] = v ~= 0 and v or nil
			end
		end
		self.obstacles[id] = nil
	end
	self.costs[id] = nil
end

function CostGrid.GetGroupId(rowSize: number, row: number, col: number): number
	local numGroups = math.ceil((rowSize + 1)/32)
	return (row * numGroups) + math.ceil((col + 1)/32)
end

function CostGrid.GetCost(grid: CostGridList, gridSize: number, row: number, col: number): number
	local groupId = CostGrid.GetGroupId(gridSize, row, col)
	local group = grid[groupId] or 0
	return bit32.extract(group, col % 32)
end

function CostGrid.GetCostX(grid: CostGridList, gridSize: Vector2, x: number, z: number): number
	local groupId = CostGrid.GetGroupId(gridSize.X, x, z)
	local group = grid[groupId] or 0
	return bit32.extract(group, z % 32)
end

function CostGrid.GetCostZ(grid: CostGridList, gridSize: Vector2, x: number, z: number): number
	local groupId = CostGrid.GetGroupId(gridSize.Y, z, x)
	local group = grid[groupId] or 0
	return bit32.extract(group, x % 32)
end

function CostGrid.GetBitsBehind(group: number, col: number, dir: number): number
	if dir > 0 then
		return bit32.band(group, Bit32Util.FILL_R[col - 1])
	else
		return bit32.band(group, Bit32Util.FILL_L[31 - col - 1])
	end
end

function CostGrid.GetBitsInFront(group: number, col: number, dir: number): number
	if dir > 0 then
		return bit32.band(group, Bit32Util.FILL_L[31 - col - 1])
	else
		return bit32.band(group, Bit32Util.FILL_R[col - 1])
	end
end

function CostGrid.countz(group: number, dir: number): number
	return dir > 0 and bit32.countrz(group) or bit32.countlz(group)
end

function CostGrid.GetCollision(group: number, col: number, dir: number): number
	group = CostGrid.GetBitsInFront(group, col, dir)
	return CostGrid.countz(group, dir)
end

function CostGrid.CanReachBit(group: number, fromBit: number, toBit: number, dir): boolean
	local _dir = math.sign(toBit - fromBit) -- Do not use this for actual direction, may be 0
	if _dir ~= 0 and _dir ~= dir then
		return false
	end
	if dir > 0 then
		return CostGrid.GetCollision(group, fromBit, dir) > toBit
	else
		return 31 - CostGrid.GetCollision(group, fromBit, dir) < toBit
	end
end

function CostGrid.GetGroup(grid: CostGridList, groupId: number): number
	return grid[groupId] or 0
end

--[=[
	
	@return (number, number, number) -- First group in the row adjusted for the startCol and (first + dir) and last group id of the row starting at startCol in direction dir
]=]
function CostGrid.GetRowFromStartCol(grid: CostGridList, rowSize: number, row: number, startCol: number, dir: number): (number?, number?, number?)
	local numGroups = math.ceil((rowSize + 1)/32)
	local firstGroupId = CostGrid.GetGroupId(rowSize, row, startCol)
	local col = startCol % 32
	
	local firstGroup = grid[firstGroupId] or 0
	if firstGroup ~= 0 then
		firstGroup = CostGrid.GetBitsInFront(firstGroup, col, dir)
	end

	local lastGroupId
	if dir > 0 then
		lastGroupId = (row + 1) * numGroups -- actual last group idY
	elseif dir < 0 then
		lastGroupId = row * numGroups + 1 -- Start group id
	end
	
	return firstGroup, firstGroupId, lastGroupId
end

function CostGrid.GetCoords(rowSize: number, groupId: number, col: number): (number, number)
	local numGroups = math.ceil((rowSize + 1)/32)
	local x = math.floor((groupId - 1) / numGroups)
	local z = ((groupId - 1) % numGroups) * 32 + col
	return x, z
end

function CostGrid:GetCostGridAsync(): CostGrid
	if self._job.Running then
		self._job.OnFinished:Wait()
	end
	return self.nodesX, self.nodesZ
end

function CostGrid:GetCostGrid(): Promise
	return not self._job.Running and Promise.resolve(self.obsNodes) or Promise.fromEvent(self._job.OnFinished):andThen(function()
		return self.nodesX, self.nodesZ
	end)
end

function CostGrid:Destroy(): ()
	SharedTableRegistry:SetSharedTable(`Data_{self._job._id}`, nil)
	self._handler:Remove(self._job)
end

function CostGrid.iterX(gridSize: Vector2, costList: CostGridList, iterator: (x: number, z: number, cost: number) -> ()): ()
	local numGroups = math.ceil((gridSize.X + 1)/32)
	for groupId, group in costList do
		local x = math.ceil(groupId/numGroups) - 1
		local z = ((groupId - 1) % numGroups) * 32
		for i = 0, 31 do
			local val = bit32.extract(group, i)
			if val == 1 then
				iterator(x, z + i, val)
			end
		end
	end
end

export type CostGrid = typeof(CostGrid.new(...))
export type CostGridList = {[number]: number} -- [nodeId] = cost
type Promise = typeof(Promise.new(...))
return CostGrid