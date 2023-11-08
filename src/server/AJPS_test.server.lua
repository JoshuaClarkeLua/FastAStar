local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SharedTableRegistry = game:GetService("SharedTableRegistry")
local CostGrid = require(ServerScriptService.Server.Pathfinding.CostGrid)
local ParallelJobHandler = require(ReplicatedStorage.Packages.ParallelJobHandler)
local AJPS = require(script.Parent.AJPS)


local base = workspace.Baseplate
local bSize = base.Size
local bSize2 = bSize/2
local origin = base.CFrame
local offsetOrigin = origin * CFrame.new(-bSize2.X, 0, -bSize2.Z)
local gridSize = Vector2.new(bSize.X, bSize.Z)

local handler = ParallelJobHandler.new(ServerScriptService.Server.Pathfinding.CostGrid.HandlerScript, 12, true)
if not handler.IsReady then
	handler.OnReady:Wait()
end

local costGrid = CostGrid.new(handler, origin, gridSize)

local objects = workspace.Objects:GetChildren()
for _, part: BasePart in ipairs(objects) do
	-- part.CFrame *= CFrame.fromAxisAngle(Vector3.yAxis, math.rad(math.random(0, 360)))
	local id = HttpService:GenerateGUID(false)
	part:SetAttribute("Id", id)
	costGrid:AddCost(id, part.CFrame, part.Size, AJPS.BLOCKED_COST)
end

local costList = costGrid:GetCostGridAsync()


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


CostGrid.iter(gridSize, costList, function(x,z,cost)
	_doAttachment(base, offsetOrigin:PointToWorldSpace(Vector3.new(x, bSize2.Y, z)), Color3.new(cost, cost, cost))
end)

local target = Vector2.new(math.random(0, gridSize.X),math.random(0, gridSize.Y))
print(target)
-- AJPS.findPath(Vector2.new(10,10), Vector2.new(1,1), Vector2.new(10,10))
-- local path = AJPS.findPath(gridSize, Vector2.new(1,1), target, costList)
-- AJPS.findPath(gridSize, Vector2.new(1,1), Vector2.new(2, 200), costList)
local path
SharedTableRegistry:SetSharedTable("CostGrid", costList)
local s = os.clock()
local f = 0
local thread = coroutine.running()
for i = 1, 10 do
	handler:Run(function(actor)
		actor:SendMessage("Pathfind", gridSize)
		return true
	end, {
		Pathfind = function(actor, _path)
			path = actor:GetSharedTable(`Path`)
		end
	}):andThen(function()
		f += 1
		if f == 10 then
			coroutine.resume(thread)
		end
	end)
end
coroutine.yield()
print(os.clock() - s)
if #path.path == 0 then
	print('no path')
end
for _, node in ipairs(path.path) do
	local p = _doPart(offsetOrigin:PointToWorldSpace(Vector3.new(node.X, bSize2.Y, node.Y)))
	p.Color = Color3.new(1,0,0)
end