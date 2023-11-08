local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local SharedTableRegistry = game:GetService("SharedTableRegistry")
local CostGridManager = require(ServerScriptService.Server.Pathfinding.CostGridManager)
local DistanceGrid = require(ServerScriptService.Server.Pathfinding.DistanceGrid)
local ParallelJobHandler = require(ReplicatedStorage.Packages.ParallelJobHandler)
--[[ local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vector2Util = require(ReplicatedStorage.Shared.Vector2Util)
local XZ = Vector3.new(1,0,1)

local function getObsNodes(cf, size)
	local pos = cf.Position
	local pos2d = Vector2.new(pos.X, pos.Z)
	local size2 = size/2
	-- Determine which axis is longer (for width and length)
	local lenV: Vector3, widV: Vector3
	if size.Z >= size.X then
		lenV = Vector3.zAxis
		widV = Vector3.xAxis
	else
		lenV = Vector3.xAxis
		widV = Vector3.zAxis
	end
	--
	local line = cf:VectorToWorldSpace(size * lenV) * XZ
	local line2d = Vector2.new(line.X, line.Z)
	local lineMag2 = line2d.Magnitude/2
	-- Calculate the square's opposite corners which fit the line
	local rsize2 = cf:VectorToWorldSpace(size2) * XZ
	local nrsize2 = cf:VectorToWorldSpace(Vector3.new(-size2.X, 0, size2.Z))
	local p1 = rsize2
	local p2 = -rsize2
	local p3 = nrsize2
	local p4 = -nrsize2
	local min: Vector2 = Vector2Util.floor(pos2d + Vector2.new(math.min(p1.X, p2.X, p3.X, p4.X), math.min(p1.Z, p2.Z, p3.Z, p4.Z)))
	local max: Vector2 = Vector2Util.ceil(pos2d + Vector2.new(math.max(p1.X, p2.X, p3.X, p4.X), math.max(p1.Z, p2.Z, p3.Z, p4.Z)))
	--
	local nx = math.ceil(max.X - min.X)
	local nz = math.ceil(max.Y - min.Y)
	-- Set data
	
end

local p = workspace.Objects.Part
local s = os.clock()
for i = 1, 200000 do
	obsData(p.CFrame, p.Size)
end
print(os.clock() - s) ]]

--[[ local function doPart(parent: BasePart, pos: Vector3, color: Color3?): BasePart
	-- local p = Instance.new("Part")
	-- p.Size = Vector3.one * .5
	-- p.Anchored = true
	local p = Instance.new("Attachment")
	p.Parent = parent
	p.WorldPosition = pos
	-- p.Color = color or p.Color
	return p
end



local originPart = workspace.Baseplate
local grid = Grid.new(originPart.CFrame)
local p = workspace.Objects.Part1

while true do
	local origin = originPart.CFrame
	local nodes = grid:AddObstacle(1, origin:ToObjectSpace(p.CFrame), p.Size)
	for i = 1, #nodes, 2 do
		local x = nodes[i]
		local z = nodes[i + 1]
		local p = doPart(originPart, origin:VectorToWorldSpace(Vector3.new(x, 0, z)) + Vector3.new(origin.X, 0, origin.Z))
		task.delay(.03, p.Destroy, p)
	end
	RunService.Stepped:Wait()
end
]]

local base = workspace.Baseplate
local bSize = base.Size
local bSize2 = bSize/2
local origin = base.CFrame
--
local handler = ParallelJobHandler.new(ServerScriptService.Server.Pathfinding.HandlerScript, 512, true)
if not handler.IsReady then
	handler.OnReady:Wait()
end
local gridSize = Vector2.new(bSize.X, bSize.Z)
local grid = CostGridManager.new(handler, origin, gridSize)

local objects = workspace.Objects:GetChildren()
for _, part: BasePart in ipairs(objects) do
	-- part.CFrame *= CFrame.fromAxisAngle(Vector3.yAxis, math.rad(math.random(0, 360)))
	local id = HttpService:GenerateGUID(false)
	part:SetAttribute("Id", id)
	grid:AddCost(id, part.CFrame, part.Size, DistanceGrid.COST.BLOCKED)
end

local costGrid = grid:GetCostGridAsync()
-- print(costGrid)

local min = Vector2.new(-bSize2.X, -bSize2.Z)
local max = Vector2.new(bSize2.X, bSize2.Z)
local s = os.clock()
local job = handler:NewJob()
local i = 0
-- job:BindTopic("GetDistanceGrid", function(actor, dgrid)
-- 	print(actor)
-- 	if i == 1 then return end
-- 	i = 1
-- 	task.defer(function()
-- 		local h = DistanceGrid.getHighestDist(dgrid)
-- 		DistanceGrid.iter(dgrid, function(x,z,cost)
-- 			local p = Instance.new("Part")
-- 			p.Size = Vector3.one
-- 			p.CFrame = CFrame.new(origin:PointToWorldSpace(Vector3.new(x, bSize2.Y, z))) * origin.Rotation
-- 			p.Anchored = true
-- 			p.Color = Color3.fromHSV(cost/h, 1, 1)
-- 			p.Parent = workspace.Objects
-- 			p:SetAttribute("Cost", cost)
-- 		end)
-- 	end)
-- end)

for x = 0, gridSize.X do
	for z = 0, gridSize.Y do
		local p = Instance.new("Part")
		p.Name = `{x};{z}`
		p.Size = Vector3.one
		p.CFrame = CFrame.new((origin * CFrame.new(-bSize2.X,0,-bSize2.Z)):PointToWorldSpace(Vector3.new(x, bSize2.Y, z))) * origin.Rotation
		p.Anchored = true
		p.Color = Color3.new()
		p.Parent = workspace.Parts
		p:SetAttribute("Cost", 0)
	end
end

local handler = ParallelJobHandler.new(ServerScriptService.Server.Pathfinding.HandlerScript, 12, true)
if not handler.IsReady then
	handler.OnReady:Wait()
end
local job = handler:NewJob('FastMarching')

job:BindTopic("GetDistanceGrid", function(actor, _grid)
	-- print(actor, _grid)
	local h = DistanceGrid.getHighestDist(_grid)
	DistanceGrid.iter(_grid, gridSize, function(x,z,cost)
		-- print(x,z)
		local p = DistanceGrid.getPart(x,z)
		if p then
			p.Color = Color3.fromHSV(cost/h, 1, 1)
			p:SetAttribute("Cost", cost)
		end
	end)
end)

SharedTableRegistry:SetSharedTable("CostGrid", costGrid)
SharedTableRegistry:SetSharedTable("JobData", SharedTable.new({}))
local s = os.clock()
for i = 1, 50 do
	DistanceGrid.new(job, costGrid, gridSize, Vector2.new(5,5))
end
job:OnFinish():andThen(function()
	print('TOTAL',os.clock() - s)
end)

--[[ local i = 1
job:Run(function(actor)
	actor:SendMessage("GetDistanceGrid", costGrid, min, max, Vector2.new(0,0))
	i += 1
	return i > 10
end) ]]