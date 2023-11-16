local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SharedTableRegistry = game:GetService("SharedTableRegistry")
local AJPS = require(ServerScriptService.Server.AJPS)
local CostGrid = require(ServerScriptService.Server.Pathfinding.CostGrid)
-- local DistanceGrid = require(ServerScriptService.Server.Pathfinding.DistanceGrid)
local ParallelJobHandler = require(ReplicatedStorage.Packages.ParallelJobHandler)

local actor = ParallelJobHandler.getActor()

local function recvGetNodesInBox(origin: CFrame, gridSize: Vector2, id: string, cf: CFrame, size: Vector3, ...: string & CFrame & Vector3): (string?, CostGridManager.ObsNodes?, ...string & CostGridManager.ObsNodes)
	if id == nil then
		return
	end
	return id, CostGrid.getNodesInBox(origin, gridSize, cf, size), recvGetNodesInBox(origin, gridSize, ...)
end

actor:BindToMessageParallel("GetNodesInBox", function(...: string & CFrame & Vector3)
	local data = SharedTableRegistry:GetSharedTable(`Data_{actor:GetJobId()}`)
	return recvGetNodesInBox(data.origin, data.gridSize, ...)
end)