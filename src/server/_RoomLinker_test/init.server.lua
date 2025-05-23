local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local AStarJPS = require(ServerScriptService.Server.Pathfinding.AStarJPS)
local CollisionGrid = require(ServerScriptService.Server.Pathfinding.CollisionGrid)
local Linker = require(ServerScriptService.Server.Pathfinding.Linker)

local base = workspace.Baseplate
local bSize = base.Size
local bSize2 = bSize/2
local origin = base.CFrame
local gridSize = Vector2.new(bSize.X, bSize.Z)

local costGrid = CollisionGrid.new(origin, gridSize)
origin = costGrid:GetOrigin()
costGrid:AddMap("main")

local objects = workspace.Objects:GetChildren()
local function _doAttachment(parent: BasePart, pos: Vector3, color: Color3?): BasePart
	local p = Instance.new("Attachment")
	p.Parent = parent
	p.WorldPosition = pos
	return p
end
for _, part: BasePart in ipairs(objects) do
	local id = HttpService:GenerateGUID(false)
	part:SetAttribute("Id", id)
	costGrid:SetObject(id, part.CFrame, part.Size)
	costGrid:AddMapObject(id, 'main', 'Collision')

	part:GetPropertyChangedSignal('CFrame'):Connect(function()
		costGrid:SetObject(id, part.CFrame, part.Size)
	end)
	part:GetPropertyChangedSignal('Size'):Connect(function()
		costGrid:SetObject(id, part.CFrame, part.Size)
	end)
end

for _, part: BasePart in ipairs(workspace.Negations:GetChildren()) do
	local id = HttpService:GenerateGUID(false)
	part:SetAttribute("Id", id)
	costGrid:AddObject(id, part.CFrame, part.Size)
	costGrid:AddMapObject(id, 'main', 'Negation')
end

local mainMap = costGrid:GetMap("main")




local function _doPart(pos: Vector3): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = Vector3.one
	p.Position = pos
	p.Parent = workspace
	return p
end

CollisionGrid.iterX(gridSize, mainMap[CollisionGrid.OBJECT_TYPE.Collision].nodesX, function(x,z,cost)
	local p = _doAttachment(base, origin:PointToWorldSpace(Vector3.new(x, bSize2.Y, z)), Color3.new(cost, cost, cost))
	p:SetAttribute("Pos", `{x}, {z}`)
	p:SetAttribute("Cost", cost)
end)
--[[ mainMap[CollisionGrid.OBJECT_TYPE.Collision].OnChanged:Connect(function()
	for _, p in ipairs(base:GetChildren()) do
		if p:IsA("Attachment") then
			p:Destroy()
		end
	end
	CollisionGrid.iterX(gridSize, mainMap[CollisionGrid.OBJECT_TYPE.Collision].nodesX, function(x,z,cost)
		local p = _doAttachment(base, origin:PointToWorldSpace(Vector3.new(x, bSize2.Y, z)), Color3.new(cost, cost, cost))
		p:SetAttribute("Pos", `{x}, {z}`)
		p:SetAttribute("Cost", cost)
	end)
end) ]]

local linker = Linker.new(gridSize)
linker:AddMap('main', mainMap)

for _, link in ipairs(workspace.RoomLinks:GetChildren()) do
	local id = HttpService:GenerateGUID(false)
	link:SetAttribute("LinkId", id)
	local from = link:FindFirstChild("1")
	local to = link:FindFirstChild("2")
	local fromPos = origin:PointToObjectSpace(from.Position)
	local toPos = origin:PointToObjectSpace(to.Position)
	-- local cost = (fromPos - toPos).Magnitude
	local cost = 0
	linker:AddLink(id, cost, Vector2.new(fromPos.X,fromPos.Z), Vector2.new(toPos.X,toPos.Z), 'main')
	link.Name = id
end

local start = workspace.START
local goal = workspace.GOAL
local function findLinkPath(): ()
	-- Get start and goal positions
	local startPos = origin:PointToObjectSpace(start.Position)
	local goalPos = origin:PointToObjectSpace(goal.Position)
	startPos = Vector2.new(startPos.X, startPos.Z)
	goalPos = Vector2.new(goalPos.X, goalPos.Z)
	--
	local s = os.clock()
	local hasPath, linkPath = linker:FindLinkPath(startPos, goalPos, 'main')
	s = os.clock() - s
	-- print(s)
	workspace.Parts:Destroy()
	local folder = Instance.new("Folder")
	folder.Name = 'Parts'
	if #linkPath > 1 then
		local lastP
		for i = 1, #linkPath do
			local link = linkPath[i]
			local node = link.pos
			local p = _doPart(origin:PointToWorldSpace(Vector3.new(node.X, bSize2.Y, node.Y)))
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

-- local s = os.clock()
-- AStarJPS.fill(gridSize, Vector2.new(0,0), CollisionGrid.combineMaps(mainMap))
-- s = os.clock() - s
-- print(s)
-- local s = os.clock()
-- local path = AStarJPS.findReachable(gridSize, Vector2.new(0,0), {Vector2.new(40,11)}, true, CollisionGrid.combineMaps(mainMap))
-- s = os.clock() - s
-- print(s)
-- print(path)

local function doPath()
	local s = os.clock()
	local start = origin:PointToObjectSpace(workspace.START.CFrame.Position)
	local goal = origin:PointToObjectSpace(workspace.GOAL.CFrame.Position)
	local colX, colZ = CollisionGrid.combineMaps({mainMap})
	local path = AStarJPS.findPath(gridSize, Vector2.new(start.X,start.Z), Vector2.new(goal.X,goal.Z), nil, colX, colZ)
	s = os.clock() - s
	print(s)
	workspace.PathfindingParts:Destroy()
	local folder = Instance.new("Folder")
	folder.Name = 'PathfindingParts'
	if #path > 2 then
		local lastP
		for i = 1, #path do
			local node = path[i]
			local p = _doPart(origin:PointToWorldSpace(Vector3.new(node.X, bSize2.Y, node.Y)))
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

-- workspace.START:GetPropertyChangedSignal("CFrame"):Connect(doPath)
-- workspace.GOAL:GetPropertyChangedSignal("CFrame"):Connect(doPath)
-- doPath()