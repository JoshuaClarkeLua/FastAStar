local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local AJPS = require(ServerScriptService.Server.Pathfinding.AStarJPS)
local CollisionGrid = require(ServerScriptService.Server.Pathfinding.CollisionGrid)


--[[
	00001000011000000000000000000000
	00000000000000000000000000000000

	1. count zeros until 1 is found
	2. save that position
	3. flip the bits
	4. Make the all bits from the first bit (depends which direction we're coming from) to the saved position all 0s
	5. count zeros from the same direction as before until 1 is found again (the 1 represents the bit after the end of the group of 1s)
	5.5. if no 1 is found, then there is no jump node, Return
	6. save that position
	6.5. if that position is the collision firstB - 1, then there is no jump node, Return
	7. return that as the jump node

	00000111
	00110000
]]

local base = workspace.Baseplate
local bSize = base.Size
local bSize2 = bSize/2
local origin = base.CFrame
local offsetOrigin = origin * CFrame.new(-bSize2.X, 0, -bSize2.Z)
local gridSize = Vector2.new(bSize.X, bSize.Z)

local costGrid = CollisionGrid.newAsync(origin, gridSize)
costGrid:AddMap("main")

local objects = workspace.Objects:GetChildren()
for _, part: BasePart in ipairs(objects) do
	local id = HttpService:GenerateGUID(false)
	part:SetAttribute("Id", id)
	costGrid:SetObject(id, part.CFrame, part.Size)
	costGrid:AddMapObject(id, 'main', 'Collision')
end

-- for _, part: BasePart in ipairs(workspace.Negations:GetChildren()) do
-- 	local id = HttpService:GenerateGUID(false)
-- 	part:SetAttribute("Id", id)
-- 	costGrid:AddObject(id, part.CFrame, part.Size)
-- 	costGrid:AddMapObject(id, 'main', CollisionGrid.OBJECT_TYPE.Negation)
-- end

local mainMap = costGrid:GetMapAsync("main")




local function _doAttachment(parent: BasePart, pos: Vector3, color: Color3?): BasePart
	-- local p = Instance.new("Part")
	-- p.Size = Vector3.one * .5
	-- p.Anchored = true
	local p = Instance.new("Attachment")
	p.Parent = parent
	p.WorldPosition = pos
	-- p.Color = color or p.Color
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


CollisionGrid.iterX(gridSize, mainMap[CollisionGrid.OBJECT_TYPE.Collision].nodesX, function(x,z,cost)
	local p = _doAttachment(base, offsetOrigin:PointToWorldSpace(Vector3.new(x, bSize2.Y, z)), Color3.new(cost, cost, cost))
	p:SetAttribute("Pos", `{x}, {z}`)
	p:SetAttribute("Cost", cost)
end)


local target = Vector2.new(math.random(0, gridSize.X),math.random(0, gridSize.Y))
-- local s = os.clock()
-- local path = AJPS.findPath(gridSize, Vector2.new(120,130), Vector2.new(260, 260), nodesX, nodesZ)
-- print(os.clock() - s)

local function doPath()
	local s = os.clock()
	local start = (origin * CFrame.new(-bSize2.X, 0, -bSize2.Z)):PointToObjectSpace(workspace.START.CFrame.Position)
	local goal = (origin * CFrame.new(-bSize2.X, 0, -bSize2.Z)):PointToObjectSpace(workspace.GOAL.CFrame.Position)
	local colX, colZ = CollisionGrid.combineMaps(mainMap)
	local path = AJPS.findPath(gridSize, Vector2.new(start.X,start.Z), Vector2.new(goal.X,goal.Z), nil, colX, colZ)
	s = os.clock() - s
	print(s)
	workspace.Parts:Destroy()
	local folder = Instance.new("Folder")
	folder.Name = 'Parts'
	if #path > 2 then
		local lastP
		for i = 1, #path do
			local node = path[i]
			local p = _doPart((origin * CFrame.new(-bSize2.X, bSize2.Y, -bSize2.Z)):PointToWorldSpace(Vector3.new(node.X, 0, node.Y)))
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
doPath()

--[[ for i = 1, 2 do
	task.spawn(function()
		local x = i
		handler:Run(function(actor)
			actor:SendMessage("Pathfind", gridSize, x, 260)
			return true
		end, {
			Pathfind = function(actor, _path)
				path = actor:GetSharedTable(`Path`)
				task.delay(.1, function()
					for _, node in path do
						local p = _doPart(offsetOrigin:PointToWorldSpace(Vector3.new(node.X, bSize2.Y, node.Y)))
						-- Debris:AddItem(p, .1)
						p.Color = Color3.new(1,0,0)
					end
				end)
				-- local node = path[1]
				-- if not node then return end
				-- local p = _doPart(offsetOrigin:PointToWorldSpace(Vector3.new(node.X, bSize2.Y, node.Y)))
				-- -- Debris:AddItem(p, .1)
				-- p.Color = Color3.new(1,0,0)
			end
		}, i)
	end)
end ]]

-- print(AJPS._forced(path, Vector2.new(84,198), Vector2.new(0,-1), true))
-- local path
-- SharedTableRegistry:SetSharedTable("CostGrid", costList)
-- local f = 0
-- local thread = coroutine.running()
-- for i = 1, 10 do
-- 	handler:Run(function(actor)
-- 		actor:SendMessage("Pathfind", gridSize)
-- 		return true
-- 	end, {
-- 		Pathfind = function(actor, _path)
-- 			path = actor:GetSharedTable(`Path`)
-- 		end
-- 	}):andThen(function()
-- 		f += 1
-- 		if f == 10 then
-- 			coroutine.resume(thread)
-- 		end
-- 	end)
-- end
-- coroutine.yield()
-- task.wait()
-- if SharedTable.size(path) == 0 then
-- 	print('no path')
-- end
