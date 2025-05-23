local Imports = require(script.Parent.Imports)
local Vector3Util = Imports.Vector3Util
local Util = {}

function Util.getNodeId(gridSize: number, nodeX: number, nodeZ: number): number
	if nodeZ < 0 then
		error("nodeZ must be greater than or equal to 0")
	end
	return math.floor((nodeX * gridSize) + nodeZ + 1)
end

function Util.getPosFromId(gridSize: number, nodeId: number): (number, number)
	return math.floor((nodeId - 1) / gridSize), (nodeId - 1) % gridSize
end

function Util.getPosFromWorld(nodeSize: number, position: Vector3, origin: Vector3): Vector3
	local _origin: Vector3 = origin or Vector3.zero
	local pos = (position - _origin) * Vector3.new(1,0,1)
	return Vector3Util.floor(pos / nodeSize) * nodeSize
end

function Util.getNodeAtPos(nodeSize: number, position: Vector3, origin: Vector3): number
	local _origin: Vector3 = origin or Vector3.zero
	local pos = position - _origin
	local nodePos = Vector3Util.floor(pos / nodeSize) * nodeSize
	return Util.getNodeId(nodeSize, nodePos.X, nodePos.Z)
end

return Util