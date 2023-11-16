local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PriorityQueue = require(ReplicatedStorage.Shared.PriorityQueue)
local Vector2Util = require(ReplicatedStorage.Shared.Vector2Util)
local Vector3Util = require(ReplicatedStorage.Shared.Vector3Util)
return {
	Vector2Util = Vector2Util,
	Vector3Util = Vector3Util,
	PriorityQueue = PriorityQueue,
}