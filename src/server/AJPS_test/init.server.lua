local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local AJPS = require(ServerScriptService.Server.Pathfinding.AStarJPS)
local CollisionGrid = require(ServerScriptService.Server.Pathfinding.CollisionGrid)
local Linker = require(ServerScriptService.Server.Pathfinding.Linker)
local Path = require(ServerScriptService.Server.Pathfinding.Path)

local GridConfig = {
	CollisionMaps = {
		main = {
			CollisionsByDefault = false,
		}
	},
}

local base = workspace.Floor1
local bSize = base.Size
local bSize2 = bSize/2
local origin = base.CFrame
local gridSize = Vector2.new(bSize.X, bSize.Z)

local grid = CollisionGrid.newAsync(origin, gridSize, GridConfig)
local linker = Linker.new()
for mapName, mapConfig in pairs(GridConfig.CollisionMaps) do
	grid:AddMap(mapName, mapConfig.CollisionsByDefault)
end

--[[ for _, part: BasePart in ipairs(workspace.Objects:GetChildren()) do
	local id = HttpService:GenerateGUID(false)
	part:SetAttribute("Id", id)
	grid:SetObjectAsync(id, part.CFrame, part.Size)
	grid:AddMapObject(id, 'main', 'Collision')
	part:GetPropertyChangedSignal("CFrame"):Connect(function()
		grid:SetObjectAsync(id, part.CFrame, part.Size)
	end)
end

for _, part: BasePart in ipairs(workspace.InvertedObjects:GetChildren()) do
	local id = HttpService:GenerateGUID(false)
	part:SetAttribute("Id", id)
	grid:SetObjectAsync(id, part.CFrame, part.Size)
	grid:AddMapObject(id, 'main', 'Collision', true)
	part:GetPropertyChangedSignal("CFrame"):Connect(function()
		grid:SetObjectAsync(id, part.CFrame, part.Size)
	end)
end ]]

local function _doAttachment(parent: BasePart, pos: Vector3): Attachment
	local p = Instance.new("Attachment")
	p.Parent = parent
	p.WorldPosition = pos
	return p
end
local function _doPart(pos: Vector3): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = Vector3.one
	p.Position = pos
	p.Parent = workspace
	return p
end

--[[ local maps = grid:GetMaps({'main'})
local colX = CollisionGrid.combineMaps(maps)
CollisionGrid.iterX(grid:GetSize(), colX, function(x,z)
	local p = _doAttachment(base, grid:ToWorldSpace(Vector3.new(x,bSize2.Y,z)))
	p:SetAttribute("Pos", `{x}, {z}`)
end) ]]

local path = Path.new(linker, {grid}, {'main'})
path:SetDrawOffset(Vector3.new(0,bSize2.Y,0))
local function doPath()
	path:Compute(workspace.START.CFrame.Position, workspace.GOAL.CFrame.Position)
end

workspace.START:GetPropertyChangedSignal("CFrame"):Connect(doPath)
workspace.GOAL:GetPropertyChangedSignal("CFrame"):Connect(doPath)
doPath()
