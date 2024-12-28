local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local AStarJPS = require(ServerScriptService.Server.Pathfinding.AStarJPS)
local CollisionGrid = require(ServerScriptService.Server.Pathfinding.CollisionGrid)
local Linker = require(ServerScriptService.Server.Pathfinding.Linker)

local function _doPart(pos: Vector3): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = Vector3.one
	p.Position = pos
	p.Parent = workspace
	return p
end


local Floor1 = workspace.Floor1
local Floor2 = workspace.Floor2
local Floor1Size2 = Floor1.Size/2
local Floor2Size2 = Floor2.Size/2
local Floor1GridSize = Vector2.new(Floor1.Size.X, Floor1.Size.Z)
local Floor2GridSize = Vector2.new(Floor2.Size.X, Floor2.Size.Z)

local Floor1Grid = CollisionGrid.new(Floor1.CFrame, Floor1GridSize)
local Floor2Grid = CollisionGrid.new(Floor2.CFrame, Floor2GridSize)
Floor1Grid:AddMap("Main")
Floor2Grid:AddMap("Main")



for _, part: BasePart in ipairs(workspace.Floor1.Objects:GetChildren()) do
	local id = HttpService:GenerateGUID(false)
	part:SetAttribute("Id", id)
	Floor1Grid:SetObject(id, part.CFrame, part.Size)
	Floor1Grid:AddMapObject(id, 'Main', 'Collision')

	part:GetPropertyChangedSignal('CFrame'):Connect(function()
		Floor1Grid:SetObject(id, part.CFrame, part.Size)
	end)
	part:GetPropertyChangedSignal('Size'):Connect(function()
		Floor1Grid:SetObject(id, part.CFrame, part.Size)
	end)
end
for _, part: BasePart in ipairs(workspace.Floor2.Objects:GetChildren()) do
	local id = HttpService:GenerateGUID(false)
	part:SetAttribute("Id", id)
	Floor2Grid:SetObject(id, part.CFrame, part.Size)
	Floor2Grid:AddMapObject(id, 'Main', 'Collision')

	part:GetPropertyChangedSignal('CFrame'):Connect(function()
		Floor2Grid:SetObject(id, part.CFrame, part.Size)
	end)
	part:GetPropertyChangedSignal('Size'):Connect(function()
		Floor2Grid:SetObject(id, part.CFrame, part.Size)
	end)
end

local Floor1Map = Floor1Grid:GetMap("Main")
local Floor2Map = Floor2Grid:GetMap("Main")
local grids = {Floor1Grid, Floor2Grid}


local function getGrid(pos: Vector3): CollisionGrid.CollisionGrid?
	local _grids = {}
	for _, grid in pairs(grids) do
		if grid:HasPos3D(pos) then
			table.insert(_grids, grid)
		end
	end
	-- print(#_grids)
	local grid
	if #grids > 1 then
		local low = math.huge
		for _, _grid in pairs(_grids) do
			local diff = pos.Y - _grid:GetOrigin().Y
			if diff >= 0 and diff < low then
				low = diff
				grid = _grid
			end
		end
	else
		grid = _grids[1]
	end
	return grid
end

--[[
	LINKER
]]
local linker = Linker.new()

for _, link in ipairs(workspace.Links:GetChildren()) do
	local id = HttpService:GenerateGUID(false)
	link:SetAttribute("LinkId", id)
	link.Name = id
	local from = link:FindFirstChild("1")
	local to = link:FindFirstChild("2")
	local fromGrid = getGrid(from.Position)
	local toGrid = getGrid(to.Position)
	--
	local fromPos = fromGrid:ToGridSpace(from.Position)
	local toPos = toGrid:ToGridSpace(to.Position)
	--
	local cost = 0
	linker:AddLink(id, cost, Vector2.new(fromPos.X,fromPos.Z), Vector2.new(toPos.X,toPos.Z), fromGrid, toGrid)
end

local start = workspace.START
local goal = workspace.GOAL
-- local function findLinkPath(): ()
-- 	-- Get start and goal positions
-- 	local startPos = origin:PointToObjectSpace(start.Position)
-- 	local goalPos = origin:PointToObjectSpace(goal.Position)
-- 	startPos = Vector2.new(startPos.X, startPos.Z)
-- 	goalPos = Vector2.new(goalPos.X, goalPos.Z)
-- 	--
-- 	local s = os.clock()
-- 	local hasPath, linkPath = linker:FindLinkPath(startPos, goalPos, 'main')
-- 	s = os.clock() - s
-- 	-- print(s)
-- 	workspace.Parts:Destroy()
-- 	local folder = Instance.new("Folder")
-- 	folder.Name = 'Parts'
-- 	if #linkPath > 1 then
-- 		local lastP
-- 		for i = 1, #linkPath do
-- 			local link = linkPath[i]
-- 			local node = link.pos
-- 			local p = _doPart(origin:PointToWorldSpace(Vector3.new(node.X, bSize2.Y, node.Y)))
-- 			p.Parent = folder
-- 			p.Color = Color3.new(1,0,0)
-- 			p.Transparency = .5
-- 			local beam = Instance.new("Beam")
-- 			beam.FaceCamera = true
-- 			beam.Color = ColorSequence.new(Color3.new(1,0,0))
-- 			local a1 = Instance.new("Attachment")
-- 			a1.Parent = p
-- 			beam.Attachment0 = a1
-- 			beam.Parent = p
-- 			if lastP then
-- 				local a2 = Instance.new("Attachment")
-- 				a2.Parent = p
-- 				lastP.Beam.Attachment1 = a2
-- 			end
-- 			lastP = p
-- 		end
-- 	end
-- 	folder.Parent = workspace
-- end

local function findLinkPath(): ()
	local fromGrid = getGrid(start.Position)
	local toGrid = getGrid(goal.Position)
	if not fromGrid or not toGrid then
		return
	end
	local startPos = fromGrid:ToGridSpace(start.Position)
	local goalPos = toGrid:ToGridSpace(goal.Position)
	startPos = Vector2.new(startPos.X, startPos.Z)
	goalPos = Vector2.new(goalPos.X, goalPos.Z)
	local s = os.clock()
	local hasPath, linkPath = linker:FindLinkPath({'Main'}, startPos, goalPos, fromGrid, toGrid)
	s = os.clock() - s
	print(s)
	-- print(hasPath, #linkPath)
	workspace.Parts:Destroy()
	local folder = Instance.new("Folder")
	folder.Name = 'Parts'
	if #linkPath > 1 then
		local lastP
		for i = 1, #linkPath do
			local link = linkPath[i]
			local grid = link.grid.grid
			local node = link.pos
			local p = _doPart(grid:ToWorldSpace(Vector3.new(node.X, Floor1.Size.Y/2, node.Y)))
			p.Parent = folder
			p.Color = Color3.new(1,0,0)
			p.Transparency = .5
			local beam = Instance.new("Beam")
			beam.FaceCamera = true
			beam.Color = ColorSequence.new(Color3.new(1,0,0))
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
	end
	folder.Parent = workspace
end

start:GetPropertyChangedSignal("CFrame"):Connect(findLinkPath)
goal:GetPropertyChangedSignal("CFrame"):Connect(findLinkPath)
findLinkPath()

--[[ local function doPath()
	local s = os.clock()
	local start = Floor1Origin:PointToObjectSpace(workspace.START.CFrame.Position)
	local goal = Floor1Origin:PointToObjectSpace(workspace.GOAL.CFrame.Position)
	local colX, colZ = CollisionGrid.combineMaps({Floor1Map})
	local path = AStarJPS.findPath(Floor1GridSize, Vector2.new(start.X,start.Z), Vector2.new(goal.X,goal.Z), nil, colX, colZ)
	s = os.clock() - s
	print(s)
	workspace.PathfindingParts:Destroy()
	local folder = Instance.new("Folder")
	folder.Name = 'PathfindingParts'
	if #path > 2 then
		local lastP
		for i = 1, #path do
			local node = path[i]
			local p = _doPart(Floor1Origin:PointToWorldSpace(Vector3.new(node.X, Floor1Size2.Y, node.Y)))
			p.Parent = folder
			p.Color = Color3.new(1,0,0)
			p.Transparency = .5
			local beam = Instance.new("Beam")
			beam.FaceCamera = true
			beam.Color = ColorSequence.new(Color3.new(1,0,0))
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
	end
	folder.Parent = workspace
end

workspace.START:GetPropertyChangedSignal("CFrame"):Connect(doPath)
workspace.GOAL:GetPropertyChangedSignal("CFrame"):Connect(doPath)
doPath() ]]