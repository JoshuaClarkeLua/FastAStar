local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedTableRegistry = game:GetService("SharedTableRegistry")
local NodeUtil = require(script.NodeUtil)
local ParallelJobHandler = require(ReplicatedStorage.Packages.ParallelJobHandler)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Vector2Util = require(ReplicatedStorage.Shared.Vector2Util)
local Vector3Util = require(ReplicatedStorage.Shared.Vector3Util)

type JobHandler = ParallelJobHandler.JobHandler
export type ObsData = {
	cf: CFrame,
	size: Vector3,	
}
export type ObsNodes = {number} -- {x, z, x, z, ...}

local XZ = Vector3.new(1,0,1)


local CostGrid = {}
CostGrid.__index = CostGrid
local MIN = -2^32/2
local MIN_V2 = Vector2.new(MIN, MIN)

local function doPart(parent: BasePart, pos: Vector3, color: Color3?): BasePart
	-- local p = Instance.new("Part")
	-- p.Size = Vector3.one * .5
	-- p.Anchored = true
	local p = Instance.new("Attachment")
	p.Parent = parent
	p.WorldPosition = pos
	-- p.Color = color or p.Color
	return p
end

function CostGrid.normalize(x: number, ...: number): ...number
	if x == nil then return end
	return x - MIN, CostGrid.normalize(...)
end

function CostGrid.denormalize(x: number, ...: number): ...number
	if x == nil then return end
	return x + MIN, CostGrid.denormalize(...)
end

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
					-- task.defer(function()
					-- 	task.synchronize()
					-- 	doPart(workspace.Baseplate, origin:PointToWorldSpace(Vector3.new(x,workspace.Baseplate.Size.Y/2,z)))
					-- end)
					-- local _x, _z = CostGrid.normalize(x,z)
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
		obsNodes = SharedTable.new({}), -- [x][z] = true
		--
		_handler = handler,
		_job = handler:NewJob('CostGrid'),
		_origin = origin,
		_gridSize = gridSize,
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
				local nodeId = NodeUtil.getNodeId(self._gridSize.X, x, z)
				local val = self.obsNodes[nodeId]
				if val then
					self.obsNodes[nodeId] = val and val + cost or cost
				else
					self.obsNodes[nodeId] = cost
				end
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

function CostGrid:AddCost(id: string, cf: CFrame, size: Vector3, cost: number): ()
	if cost ~= cost or cost <= 0 or cost == math.huge or cost == -math.huge then
		error("Cost must be a valid number greater than 0, got", cost)
	end
	self.queued[id] = {cf, size}
	self.costs[id] = cost
	-- Run job
	self._job:Run(self._GetNodesInBox)
end

function CostGrid:RemoveCost(id: string): ()
	local nodes = self.obstacles[id]
	local cost = self.costs[id]
	if cost ~= nil and nodes == nil then
		self.queued[id] = nil
	else
		for i = 1, #nodes, 2 do
			local x = nodes[i]
			local z = nodes[i + 1]
			local nodeId = NodeUtil.getNodeId(self._gridSize.X, x, z)
			local val = self.obsNodes[nodeId]
			if not val then
				continue
			end
			val -= cost
			if val == 0 then
				self.obsNodes[nodeId] = nil
			else
				self.obsNodes[nodeId] = val
			end
		end
		self.obstacles[id] = nil
	end
	self.costs[id] = nil
end

function CostGrid.GetCost(grid: CostGridList, gridSize: Vector2, x: number, z: number): number
	local nodeId = NodeUtil.getNodeId(gridSize.X, x, z)
	return grid[nodeId] or 0
end

function CostGrid:GetCostGridAsync(): CostGrid
	if self._job.Running then
		self._job.OnFinished:Wait()
	end
	return self.obsNodes
end

function CostGrid:GetCostGrid(): Promise
	return not self._job.Running and Promise.resolve(self.obsNodes) or Promise.fromEvent(self._job.OnFinished):andThen(function()
		return self.obsNodes
	end)
end

function CostGrid:Destroy(): ()
	SharedTableRegistry:SetSharedTable(`Data_{self._job._id}`, nil)
	self._handler:Remove(self._job)
end

function CostGrid.iter(gridSize: Vector2, costList: CostGridList, iterator: (x: number, z: number, cost: number) -> ()): ()
	for nodeId, cost in costList do
		local x, z = NodeUtil.getPosFromId(gridSize.X, nodeId)
		iterator(x, z, cost)
	end
end

export type CostGrid = typeof(CostGrid.new(...))
export type CostGridList = {[number]: number} -- [nodeId] = cost
type Promise = typeof(Promise.new(...))
return CostGrid


--[[
	Handle sync problems when removing obstacles while their nodes are still being calculated
	-> Set the obstacle data to false when adding it (false = not done calculating). If it's removed before it's finished calculating, set it back to nil.
	-> When the calculation is done, check to make sure it's still set to true before adding it to the obstructed nodes list.
]]