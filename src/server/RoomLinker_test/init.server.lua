local ServerScriptService = game:GetService("ServerScriptService")
local CollisionGrid = require(ServerScriptService.Server.Pathfinding.CollisionGrid)
local RoomLinker = require(ServerScriptService.Server.Pathfinding.RoomLinker)

local base = workspace.Baseplate
local bSize = base.Size
local bSize2 = bSize/2
local origin = base.CFrame
local offsetOrigin = origin * CFrame.new(-bSize2.X, 0, -bSize2.Z)
local gridSize = Vector2.new(bSize.X, bSize.Z)

local costGrid = CollisionGrid.newAsync(origin, gridSize)
costGrid:AddMap("main")
costGrid:AddMap("neg")

--[[ local objects = workspace.Objects:GetChildren()
for _, part: BasePart in ipairs(objects) do
	local id = HttpService:GenerateGUID(false)
	part:SetAttribute("Id", id)
	costGrid:AddObject(id, part.CFrame, part.Size, "main")
end

for _, part: BasePart in ipairs(workspace.Negations:GetChildren()) do
	local id = HttpService:GenerateGUID(false)
	part:SetAttribute("Id", id)
	costGrid:AddObject(id, part.CFrame, part.Size, "neg")
end ]]

local mainMap = costGrid:GetMapAsync("main")
local negMap = costGrid:GetMapAsync("neg")




local function _doAttachment(parent: BasePart, pos: Vector3, color: Color3?): BasePart
	local p = Instance.new("Attachment")
	p.Parent = parent
	p.WorldPosition = pos
	return p
end

CollisionGrid.iterX(gridSize, mainMap[CollisionGrid.OBJECT_TYPE.Collision].nodesX, function(x,z,cost)
	local p = _doAttachment(base, offsetOrigin:PointToWorldSpace(Vector3.new(x, bSize2.Y, z)), Color3.new(cost, cost, cost))
	p:SetAttribute("Pos", `{x}, {z}`)
	p:SetAttribute("Cost", cost)
end)

local roomLinker = RoomLinker.new(gridSize)
roomLinker:AddMap('main', mainMap, negMap)
roomLinker:AddLink('1', Vector2.new(0,0), Vector2.new(50,50), 'main')