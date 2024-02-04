local Imports = require(script.Parent.Parent.Imports)
local Vector2Util = Imports.Vector2Util
local NodeUtil = require(script.Parent.Parent.NodeUtil)
local Bit32Util = require(script.Parent.Parent.Bit32Util)
local CollisionGrid = require(script.Parent.Parent.CollisionGrid)
local GridUtil = require(script.Parent.Parent.GridUtil)


local Heuristic = {}

--[=[
	@function Chebyshev
	
	Heuristic used in grid-based maps where you can move in eight directions (including diagonals).

	@param nX number -- Current node X
	@param nY number -- Current node Y
	@param tnX number -- Target node X
	@param tnY number -- Target node Y
	@return number -- The node's heuristic value
]=]
function Heuristic.Chebyshev(n: Vector2, tn: Vector2): number
	local dx = math.abs(n.X - tn.X)
	local dy = math.abs(n.Y - tn.Y)
	return math.max(dx, dy)
end

function Heuristic.Diagonal(nodeA, nodeB): number
	local dx = math.abs(nodeA.X - nodeB.X)
	local dy = math.abs(nodeA.Y - nodeB.Y)
	return (dx + dy) + (1.4 - 2) * math.min(dx, dy)
end


local AJPS = {}

function AJPS.calF(self, node: Vector2): number
	return self.hFn(node, self.goal)
end

function AJPS.getG(self, nodeId: number): number
	return self.g[nodeId] or math.huge
end

function AJPS.nextNode(self): (Vector2?, number?)
	local node = self.open:Pop()
	if not node then
		return
	end
	local nodeId = NodeUtil.getNodeId(self.gridSize.X, node.X, node.Y)
	self.openDict[nodeId] = nil
	return node, nodeId
end
function AJPS.canWalk(self, x, z): boolean
	return GridUtil.isInGrid(self.gridSize.X, self.gridSize.Y, x, z)
		and CollisionGrid.HasCollision(self.costsX, self.gridSize.Y, x, z, self.collisionsByDefault) < 1
end

function AJPS.allNeighbors(self, node): { Vector2 }
	local neighbors = {}
	for _, dir in ipairs(GridUtil.DIR) do
		local n = node + dir
		if AJPS.canWalk(self, n.X, n.Y) then
			table.insert(neighbors, n)
		end
	end
	return neighbors
end

--[=[
	@function forced

	Returns the position of the bit (representing a node) which is a forced neighbor in groupB *before the first collision (if any)*
	collisionBit is true if there is a collision

	@param groupA number -- The group we are checking for forced neighbors
	@param groupB number -- The group that could potentially have forced neighbors
	@param dir number -- The direction of travel (1 or -1)
	@return (number?, number?) -- (collisionBit, forceResult)
]=]
function AJPS.forced(groupA, groupB, dir): (number?, number?)
	-- Create collision mask
	local firstB = dir > 0 and bit32.countrz(groupA) or bit32.countlz(groupA)
	local hasCollision = firstB < 32 -- firstB goes from 0 -> 32 regardless of the direction we are counting in
	if hasCollision then
		if firstB == 0 then
			return dir > 0 and 0 or 31, nil
		end
		local _firstB = math.max(firstB - 1, -1)
		local colMask = dir < 0 and Bit32Util.FILL_L[_firstB] or Bit32Util.FILL_R[_firstB]
		-- Apply collision mask
		groupB = bit32.band(groupB, colMask) -- Removes all the blocked nodes past the first collision node in groupA
		groupA = bit32.band(groupA, colMask)
	elseif groupB == 0 then
		return
	end
	-- Check for forced neighbors
	-- 1. count zeros until 1 is found, and save that position
	local startB = 31 - (dir > 0 and bit32.countrz(groupB) or bit32.countlz(groupB))
	-- 2. flip the bits
	local groupBFlip = bit32.bnot(groupB)
	-- 3. Make the all bits from the first bit (depends which direction we're coming from) to the saved position all 0s
	groupBFlip = bit32.band(groupBFlip, dir > 0 and Bit32Util.FILL_L[startB] or Bit32Util.FILL_R[startB])
	local jumpNode = dir > 0 and bit32.countrz(groupBFlip) or bit32.countlz(groupBFlip)
	-- Return if no jump node or if the jump node is at the collision node or past it
	if hasCollision and jumpNode >= firstB then
		return hasCollision and (dir > 0 and firstB or 31 - firstB) or nil
	end
	return hasCollision and (dir > 0 and firstB or 31 - firstB) or nil, dir > 0 and jumpNode or 31 - jumpNode
end
function AJPS.isGroupInRow(
	rowSize: number,
	row: number,
	groupId: number,
	firstId: number,
	lastId: number,
	dir: number
): boolean
	return dir > 0 and (groupId >= firstId and groupId <= lastId) or (groupId <= firstId and groupId >= lastId)
end
function AJPS.checkGroup(
	row,
	rowSize,
	first,
	last,
	costs,
	dir,
	--
	groupA,
	groupB,
	groupIdA,
	groupIdB
): (number?, number?, number?, number?, number?)
	local collisionBit, force = AJPS.forced(groupA, groupB, dir)

	if force then
		-- Check next group if force is at end of current group
		if force == 32 or force == -1 then
			local nextGroupId = groupIdA + dir
			if AJPS.isGroupInRow(rowSize, row, nextGroupId, first, last, dir) then
				local nextGroup = costs[nextGroupId] or 0
				local nextGroupB = costs[groupIdB + dir] or 0
				if dir > 0 then
					if bit32.extract(nextGroup, 0, 1) == 1 or bit32.extract(nextGroupB, 0, 1) == 1 then
						force = nil
					end
				else
					if bit32.extract(nextGroup, 31, 1) == 1 or bit32.extract(nextGroupB, 31, 1) == 1 then
						force = nil
					end
				end
			end
		end
		if force then
			-- Check to make sure forced neighbor is not past the collision
			if not collisionBit or (dir > 0 and force < collisionBit) or (dir < 0 and force > collisionBit) then
				local r = row
				local c = force - dir -- subtract _dir to return the position of the jump node instead of the forced neighbor position
				return collisionBit, force, groupIdA, r, c
			end
		end
	end
	return collisionBit, force, groupIdA
end

function AJPS.hasForcedNeighbors(self, node, dir): boolean
	local n = node + dir
	-- Horizontal
	if dir.X ~= 0 and dir.Y == 0 then
		if
			(not AJPS.canWalk(self, node.X, node.Y + 1) and AJPS.canWalk(self, n.X, node.Y + 1))
			or (not AJPS.canWalk(self, node.X, node.Y - 1) and AJPS.canWalk(self, n.X, node.Y - 1))
		then
			return true
		end
		-- Vertical
	elseif dir.X == 0 and dir.Y ~= 0 then
		if
			(not AJPS.canWalk(self, node.X + 1, node.Y) and AJPS.canWalk(self, node.X + 1, n.Y))
			or (not AJPS.canWalk(self, node.X - 1, node.Y) and AJPS.canWalk(self, node.X - 1, n.Y))
		then
			return true
		end
		-- Diagonal
	elseif dir.X ~= 0 and dir.Y ~= 0 then
		if
			(not AJPS.canWalk(self, node.X - dir.X, node.Y) and AJPS.canWalk(self, node.X - dir.X, n.Y))
			or (not AJPS.canWalk(self, node.X, node.Y - dir.Y) and AJPS.canWalk(self, n.X, node.Y - dir.Y))
		then
			return true
		end
	end
	return false
end

function AJPS.findNeighbors(self, node, pNode): { Vector2 }
	local neighbors = {}
	if pNode == nil then
		return AJPS.allNeighbors(self, node)
	end
	local dir = Vector2Util.sign(node - pNode)
	-- Directly forward (cardinal)
	local n = node + dir
	-- Add n to neighbors if not blocked
	if AJPS.canWalk(self, n.X, n.Y) then
		table.insert(neighbors, n)
	end
	-- Move X
	if dir.X ~= 0 and dir.Y == 0 then
		-- Check for forced neighbors
		if not AJPS.canWalk(self, node.X, node.Y + 1) and AJPS.canWalk(self, n.X, node.Y + 1) then
			table.insert(neighbors, n + Vector2.yAxis)
		end
		if not AJPS.canWalk(self, node.X, node.Y - 1) and AJPS.canWalk(self, n.X, node.Y - 1) then
			table.insert(neighbors, n - Vector2.yAxis)
		end
	--
	-- Move Y
	elseif dir.X == 0 and dir.Y ~= 0 then
		-- Check for forced neighbors
		if not AJPS.canWalk(self, node.X + 1, node.Y) and AJPS.canWalk(self, node.X + 1, n.Y) then
			table.insert(neighbors, n + Vector2.xAxis)
		end
		if not AJPS.canWalk(self, node.X - 1, node.Y) and AJPS.canWalk(self, node.X - 1, n.Y) then
			table.insert(neighbors, n - Vector2.xAxis)
		end
	--
	-- Diagonal movement
	else
		if AJPS.canWalk(self, n.X, node.Y) then
			-- table.insert(neighbors, node + Vector2.xAxis)
			table.insert(neighbors, node + Vector2.new(dir.X, 0))
		end
		if AJPS.canWalk(self, node.X, n.Y) then
			-- table.insert(neighbors, node + Vector2.yAxis)
			table.insert(neighbors, node + Vector2.new(0, dir.Y))
		end
		-- Check for forced neighbors
		if not AJPS.canWalk(self, node.X - dir.X, node.Y) and AJPS.canWalk(self, node.X - dir.X, n.Y) then
			table.insert(neighbors, node + Vector2.new(-dir.X, dir.Y))
		end
		if not AJPS.canWalk(self, node.X, node.Y - dir.Y) and AJPS.canWalk(self, n.X, node.Y - dir.Y) then
			table.insert(neighbors, node + Vector2.new(dir.X, -dir.Y))
		end
	end
	return neighbors
end

AJPS.Heuristic = Heuristic
return AJPS
