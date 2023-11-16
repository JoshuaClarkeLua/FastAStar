local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollisionGrid = require(ServerScriptService.Server.Pathfinding.CollisionGrid)
local ParallelJobHandler = require(ReplicatedStorage.Packages.ParallelJobHandler)

local actor = ParallelJobHandler.getActor()

local function recvGetNodesInBox(origin: CFrame, gridSize: Vector2, id: string, cf: CFrame, size: Vector3, ...: string & CFrame & Vector3): (string?, CollisionGrid.ObjNodes?, ...string & CollisionGrid.ObjNodes)
	if id == nil then
		return
	end
	return id, CollisionGrid.getNodesInBox(origin, gridSize, cf, size), recvGetNodesInBox(origin, gridSize, ...)
end

actor:BindToMessageParallel("GetNodesInBox", function(...: string & CFrame & Vector3)
	local data = actor:GetJobSharedTable("Data")
	return recvGetNodesInBox(data.origin, data.gridSize, ...)
end)
