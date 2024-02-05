local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local AJPS = require(ServerScriptService.Server.Pathfinding.AStarJPS)
local CollisionGrid = require(ServerScriptService.Server.Pathfinding.CollisionGrid)


local base = workspace.Floor1
local bSize = base.Size
local bSize2 = bSize/2
local origin = base.CFrame
local offsetOrigin = origin * CFrame.new(-bSize2.X, 0, -bSize2.Z)
local gridSize = Vector2.new(bSize.X, bSize.Z)
local CollisionsByDefault = true

local grid = CollisionGrid.newAsync(origin, gridSize)
grid:AddMap("main", CollisionsByDefault)
-- grid:AddMap("main2")

for _, part: BasePart in ipairs(workspace.Objects:GetChildren()) do
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
end

-- for _, part: BasePart in ipairs(workspace.Objects2:GetChildren()) do
-- 	local id = HttpService:GenerateGUID(false)
-- 	part:SetAttribute("Id", id)
-- 	grid:SetObjectAsync(id, part.CFrame, part.Size)
-- 	grid:AddMapObject(id, 'main', 'Collision', true)
-- end

--[[ for _, part: BasePart in ipairs(workspace.Negations:GetChildren()) do
	local id = HttpService:GenerateGUID(false)
	part:SetAttribute("Id", id)
	grid:SetObjectAsync(id, part.CFrame, part.Size)
	grid:AddMapObject(id, 'main', 'Negation')
end ]]

local main = grid:GetMapAsync("main")
-- local main2 = grid:GetMapAsync("main2")



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

local maps = grid:GetMaps({'main'})
local colX = CollisionGrid.combineMaps(maps)
CollisionGrid.iterX(grid:GetSize(), colX, function(x,z)
	local p = _doAttachment(base, grid:ToWorldSpace(Vector3.new(x,bSize2.Y,z)))
	p:SetAttribute("Pos", `{x}, {z}`)
end)

local function doPath()
	local s = os.clock()
	local start = (origin * CFrame.new(-bSize2.X, 0, -bSize2.Z)):PointToObjectSpace(workspace.START.CFrame.Position)
	local goal = (origin * CFrame.new(-bSize2.X, 0, -bSize2.Z)):PointToObjectSpace(workspace.GOAL.CFrame.Position)
	local path = AJPS.findPath(gridSize, Vector2.new(start.X,start.Z), Vector2.new(goal.X,goal.Z), nil, CollisionGrid.combineMaps({main}))
	s = os.clock() - s
	print(s)
	workspace.Parts:Destroy()
	local folder = Instance.new("Folder")
	folder.Name = 'Parts'
	if #path > 1 then
		local lastP
		for i = 1, #path do
			local node = path[i]
			local p = _doPart((origin * CFrame.new(-bSize2.X, bSize2.Y, -bSize2.Z)):PointToWorldSpace(Vector3.new(node.X, 0, node.Y)))
			p.Parent = folder
			p.Name = i
			p.Transparency = 1
			local beam = Instance.new("Beam")
			beam.FaceCamera = true
			beam.Color = ColorSequence.new(Color3.new(1,0,0))
			beam.Width0 = .4
			beam.Width1 = .4
			local a1 = Instance.new("Attachment")
			a1.Parent = p
			beam.Attachment0 = a1
			beam.Parent = p
			if lastP then
				local a2 = Instance.new("Attachment")
				a2.Parent = p
				lastP.Beam.Attachment1 = a2
			end
			lastP = p
		end
		--[[ for i = 1, #_path do
			local node = _path[i]
			local p = _doPart((origin * CFrame.new(-bSize2.X, bSize2.Y, -bSize2.Z)):PointToWorldSpace(Vector3.new(node.X, 0, node.Y)))
			p.Parent = folder
			p.Color = Color3.new(1,0,0)
			p.Transparency = .5
		end ]]
	end
	folder.Parent = workspace
end

workspace.START:GetPropertyChangedSignal("CFrame"):Connect(doPath)
workspace.GOAL:GetPropertyChangedSignal("CFrame"):Connect(doPath)
doPath()
