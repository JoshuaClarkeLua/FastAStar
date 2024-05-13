local ServerScriptService = game:GetService("ServerScriptService")
local CollisionGrid = require(ServerScriptService.Server.Pathfinding.CollisionGrid)
local cf = CFrame.fromOrientation(0, math.rad(90), 0) + Vector3.new(131.211, 227.5, 394.596)
local size = Vector2.new(260,260)

cf = cf * CFrame.new(-size.X/2, 0, -size.Y/2)

local jumpNodes = Instance.new("Folder", workspace)
jumpNodes.Name = "JumpNodes"
local nodes = Instance.new("Folder", workspace)
nodes.Name = "Nodes"

local Util = {}

function Util.clear(): ()
	jumpNodes:ClearAllChildren()
	nodes:ClearAllChildren()
end

function Util.jumpNode(x: number, z: number, c: Color3?): BasePart
	local nodeCF = cf:ToWorldSpace(CFrame.new(x,1,z))
	local p = Instance.new("Part")
	p.Size = Vector3.one
	p.CFrame = nodeCF
	p.Anchored = true
	p.CanCollide = false
	p.Transparency = 0.5
	p.Color = c or Color3.new(0,0,1)
	p.Parent = jumpNodes
	return p
end

function Util.node(x: number, z: number, c: Color3?): BasePart
	local nodeCF = cf:ToWorldSpace(CFrame.new(x,.5,z))
	local p = Instance.new("Part")
	p.Size = Vector3.one
	p.CFrame = nodeCF
	p.Anchored = true
	p.CanCollide = false
	p.Transparency = 0.3
	p.Color = c or Color3.new(.9,.9,.9)
	p.Parent = nodes
	return p
end

local i = 0
function Util.drawRowPath(xMov, rowSize, row, startCol, dir, collisionBit, groupId, force)
	--[[ i = (i + 1) % 5
	if i == 0 then
		task.wait()
	end
	if dir > 0 then
		for col = startCol, collisionBit and math.max(startCol, collisionBit - 1) or 31 do
			-- local x, z = CollisionGrid.GetCoords(rowSize, groupId, col)
			local x, z
			if xMov then
				z, x = CollisionGrid.GetCoords(rowSize, groupId, col)
			else
				x, z = CollisionGrid.GetCoords(rowSize, groupId, col)
			end
			Util.node(x, z)
		end
	else
		for col = collisionBit and math.min(startCol, collisionBit + 1) or 0, startCol do
			-- local x, z = CollisionGrid.GetCoords(rowSize, groupId, col)
			local x, z
			if xMov then
				z, x = CollisionGrid.GetCoords(rowSize, groupId, col)
			else
				x, z = CollisionGrid.GetCoords(rowSize, groupId, col)
			end
			Util.node(x, z)
		end
	end ]]
end

return Util