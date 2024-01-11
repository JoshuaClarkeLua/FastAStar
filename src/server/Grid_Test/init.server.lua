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

local base = workspace.Floor1
local bSize = base.Size
local bSize2 = bSize/2
local origin: CFrame = base.CFrame
local offsetOrigin = origin * CFrame.new(-bSize2.X, 0, -bSize2.Z)
local gridSize = Vector2.new(bSize.X, bSize.Z)

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

for _, part: BasePart in ipairs(workspace.Objects:GetChildren()) do
	task.spawn(function()
		while true do
			part:ClearAllChildren()
			local nodes = CollisionGrid.getNodesInBox(offsetOrigin, gridSize, part.CFrame, part.Size)
			local i = 1
			while i < #nodes do
				local x, y = nodes[i], nodes[i+1]
				local pos = Vector3.new(x, bSize2.Y, y)
				pos = origin:VectorToWorldSpace(pos)
				_doAttachment(part, pos)
				i += 2
			end
			task.wait(.05)
		end
	end)
end