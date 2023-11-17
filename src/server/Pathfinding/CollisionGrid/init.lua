local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Imports = require(script.Parent.Imports)
local ParallelJobHandler = require(ReplicatedStorage.Packages.ParallelJobHandler)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Vector2Util = Imports.Vector2Util
local Vector3Util = Imports.Vector3Util
local Bit32Util = require(script.Parent.Bit32Util)
local NodeUtil = require(script.Parent.NodeUtil)

type JobHandler = ParallelJobHandler.JobHandler
export type ObjectData = {
	cf: CFrame,
	size: Vector3,	
}
export type ObjNodes = {number} -- {x, z, x, z, ...}
export type CollisionMap = {
	height: number,
	[number]: {
		OnChanged: RBXScriptSignal, -- (nodes: ObjNodes, added: boolean)
		nodeMap: {[number]: number},
		nodesX: {[number]: number},
		nodesZ: {[number]: number},
	},
}
type Object = {
	nodes: ObjNodes,
	maps: {[string]: any}, -- [MapName]: any
}
export type ObjectType = number
export type ObjectTypeName = 'Collision' | 'Negation'

local XZ = Vector3.new(1,0,1)

local OBJ_TYPE = {
	Collision = 1,
	Negation = 2,
}
local MAP_DEFAULTS = {
	[OBJ_TYPE.Collision] = 0,
	[OBJ_TYPE.Negation] = 0xFFFFFFFF,
}
local MAP_BIT_SET = {
	[OBJ_TYPE.Collision] = 1,
	[OBJ_TYPE.Negation] = 0,
}
local MAP_BIT_UNSET = {
	[OBJ_TYPE.Collision] = 0,
	[OBJ_TYPE.Negation] = 1,
}

local CollisionGrid = {}
CollisionGrid.__index = CollisionGrid
CollisionGrid.OBJECT_TYPE = OBJ_TYPE

function CollisionGrid.getNodesInBox(origin, gridSize, cf, size): ObjNodes
	cf = origin:ToObjectSpace(cf)
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
	
	local nodes = {} -- {x,z, x,z, ...}
	for x = min.X, max.X do
		if x < 0 or x > gridSize.X then
			continue
		end
		for z = min.Y, max.Y do
			if z < 0 or z > gridSize.Y then
				continue
			end
			local cellPos = Vector2.new(x,z) - pos2d
			local v2 = Vector3Util.project(cellPos, line2d)
	
			-- Check if cell is past the line (vertical check)
			if math.ceil(lineMag2 - v2.Magnitude + .5) >= 0 then
				-- Check if cell is too far from the line (horizontal check)
				local dist = (v2 - cellPos).Magnitude
				if math.floor(dist - .5) <= (widV * size2).Magnitude then
					table.insert(nodes, x)
					table.insert(nodes, z)
				end
			end
		end
	end

	return nodes
end

function CollisionGrid.newAsync(origin: CFrame, gridSize: Vector2): CollisionGrid
	origin = origin * CFrame.new(-gridSize.X/2, 0, -gridSize.Y/2)
	local handler = ParallelJobHandler.new(script.Handler, 64, false)
	if not handler.IsReady then
		handler.OnReady:Wait()
	end
	local self = setmetatable({
		maps = {} :: {[string]: CollisionMap}, -- [mapName]: CollisionMap
		queued = {} :: {[string]: ObjectData}, -- [id]: ObjectData
		objects = {} :: {[string]: Object}, -- [id]: Object
		--
		_handler = handler,
		_job = handler:NewJob('CollisionGrid'),
		_origin = origin,
		_gridSize = gridSize,
		_numGroupsX = math.ceil(gridSize.X/32),
		_numGroupsZ = math.ceil(gridSize.Y/32),
	}, CollisionGrid)
	-- Setup job
	local job = self._job
	job:SetSharedTable("Data", SharedTable.new({
		origin = origin,
		gridSize = gridSize,
	}))

	-- Setup Job functions
	local function GetNodesInBox(actor): ()
		actor:SendMessage("GetNodesInBox", self:_GetQueued(32))
		return next(self.queued) == nil
	end
	self._GetNodesInBox = GetNodesInBox

	-- Setup topic handlers
	--[[
		TOPIC -> GetNodesInBox
	]]
	local function recvGetNodesInBox(id: string, nodes: ObjNodes, ...: string & ObjNodes): ()
		if id == nil then
			return
		end
		if self.objects[id] ~= nil then
			local object = self.objects[id]
			object.nodes = nodes
			for mapName, type in pairs(object.maps) do
				self:_AddMapNodes(nodes, mapName, type)
			end
		end
		--
		return recvGetNodesInBox(...)
	end
	job:BindTopic("GetNodesInBox", function(actor, ...: string & ObjNodes)
		recvGetNodesInBox(...)
	end)
	return self
end

function CollisionGrid:_GetQueued(amount: number): (...string & CFrame & Vector3)
	if amount == 0 then
		return
	end
	local id, data = next(self.queued)
	if id == nil then
		return
	end
	self.queued[id] = nil
	return id, data[1], data[2], self:_GetQueued(amount - 1)
end

function CollisionGrid:AddMap(map: string, mapHeight: number?, data: CollisionMap?): ()
	if self.maps[map] then
		error(`Map '{map}' already exists`)
	end
	self.maps[map] = data or {
		height = mapHeight or 0,
		[OBJ_TYPE.Collision] = {
			OnChanged = Signal.new(),
			nodeMap = {},
			nodesX = {},
			nodesZ = {},
		},
		[OBJ_TYPE.Negation] = {
			OnChanged = Signal.new(),
			nodeMap = {},
			nodesX = {},
			nodesZ = {},
		},
	}
end

function CollisionGrid:RemoveMap(map: string): ()
	if self.maps[map] then
		error(`Map '{map}' does not exist`)
	end
	self.maps[map] = nil
	for _, object in pairs(self.objects) do
		object.maps[map] = nil
	end
end

function CollisionGrid:HasMap(map: string): boolean
	return self.maps[map] ~= nil
end

function CollisionGrid:AddObject(id: string, cf: CFrame, size: Vector3): ()
	if not self.objects[id] then
		self.queued[id] = {cf, size}
		self.objects[id] = {
			maps = {},
		}
		-- Run job
		self._job:Run(self._GetNodesInBox)
	end
end

function CollisionGrid:RemoveObject(id: string): ()
	local object = self.objects[id]
	if not object then
		return
	end
	self.objects[id] = nil
	if object.nodes == nil then
		self.queued[id] = nil
	else
		for map, objType in pairs(object.maps) do
			self:_RemoveMapNodes(object.nodes, map, objType)
		end
	end
end

function CollisionGrid:HasObject(id: string): boolean
	return self.objects[id] ~= nil
end

function CollisionGrid:_AddMapNodes(nodes: ObjNodes, mapName: string, type: ObjectType): ()
	local map = self.maps[mapName]
	if not map then
		return
	end
	-- Get the type map
	local typeMap = map[type]
	--
	local default = MAP_DEFAULTS[type]
	local bitSet = MAP_BIT_SET[type]
	-- Add nodes
	local changedNodes = {}
	for i = 1, #nodes, 2 do
		local x = nodes[i]
		local z = nodes[i + 1]
		local nodeId = NodeUtil.getNodeId(self._gridSize.X, x, z)

		if typeMap.nodeMap[nodeId] then
			typeMap.nodeMap[nodeId] += 1
		else
			if not changedNodes[x] then
				changedNodes[x] = {
					[z] = true,
				}
			else
				changedNodes[x][z] = true
			end

			-- Update nodesX
			local groupId = CollisionGrid.GetGroupId(self._gridSize.X, x, z)
			local group = typeMap.nodesX[groupId] or default
			typeMap.nodesX[groupId] = bit32.replace(group, bitSet, z % 32)

			-- Update nodeMap
			if group == typeMap.nodesX[groupId] then -- Only add to node map when the bit was already set before (there are more than 2 objects occupying the same node)
			typeMap.nodeMap[nodeId] = 2 -- 2 because the first collision is already counted
			--
			-- Update nodesZ
			else
				groupId = CollisionGrid.GetGroupId(self._gridSize.Y, z, x)
				group = typeMap.nodesZ[groupId] or default
				typeMap.nodesZ[groupId] = bit32.replace(group, bitSet, x % 32)
			end
		end
	end

	if next(changedNodes) ~= nil then
		typeMap.OnChanged:Fire(changedNodes, true)
	end
end

function CollisionGrid:_RemoveMapNodes(nodes: ObjNodes, mapName: string, type: ObjectType): ()
	local map = self.maps[mapName]
	if not map then
		return
	end
	-- Get the type map
	local typeMap = map[type]
	--
	local default = MAP_DEFAULTS[type]
	local bitUnset = MAP_BIT_UNSET[type]
	-- Remove nodes
	local changedNodes = {}
	for i = 1, #nodes, 2 do
		local x = nodes[i]
		local z = nodes[i + 1]
		local nodeId = NodeUtil.getNodeId(self._gridSize.X, x, z)

		if typeMap.nodeMap[nodeId] then
			typeMap.nodeMap[nodeId] -= 1
			if typeMap.nodeMap[nodeId] < 2 then
				typeMap.nodeMap[nodeId] = nil
			end
		else
			if not changedNodes[x] then
				changedNodes[x] = {
					[z] = true,
				}
			else
				changedNodes[x][z] = true
			end

			-- Update nodesX
			local groupId = CollisionGrid.GetGroupId(self._gridSize.X, x, z)
			local group = typeMap.nodesX[groupId]
			if group ~= nil then
				local v = bit32.replace(group, bitUnset, z % 32)
				typeMap.nodesX[groupId] = v ~= default and v or nil
			end

			-- Update nodesZ
			groupId = CollisionGrid.GetGroupId(self._gridSize.Y, z, x)
			group = typeMap.nodesZ[groupId]
			if group ~= nil then
				local v = bit32.replace(group, bitUnset, x % 32)
				typeMap.nodesZ[groupId] = v ~= default and v or nil
			end
		end
	end

	if next(changedNodes) ~= nil then
		typeMap.OnChanged:Fire(changedNodes, false)
	end
end

function CollisionGrid:AddMapObject(id: string, map: string, type: ObjectTypeName): ()
	if not self.maps[map] then
		error(`Invalid map '{map}'`)
	end
	local object = self.objects[id]
	if not object then
		error(`Object '{id}' does not exist`)
	end
	local newType = OBJ_TYPE[type]
	if not newType then
		error(`Invalid type '{type}'`)
	end
	local oldType = object.maps[map]
	if oldType then
		-- Return if object was already added to map type
		if oldType == newType then
			return
		end
		self:_RemoveMapNodes(object.nodes, map, oldType)
	end
	-- Add object to map
	object.maps[map] = newType
	-- Add nodes to map if nodes are already calculated
	if object.nodes ~= nil then
		self:_AddMapNodes(object.nodes, map, newType)
	end
end

function CollisionGrid:RemoveMapObject(id: string, map: string): ()
	local object = self.objects[id]
	if not object then
		return
	end
	local currentType = object.maps[map]
	if not currentType then
		return
	end
	if object.nodes ~= nil then
		self:_RemoveMapNodes(object.nodes, map, currentType)
	end
	object.maps[map] = nil
end

function CollisionGrid:GetObjectType(id: string, map: string): ObjectTypeName?
	local object = self.objects[id]
	if not object then
		return
	end
	local type = object.maps[map]
	if type then
		if type == OBJ_TYPE.Collision then
			return 'Collision'
		elseif type == OBJ_TYPE.Negation then
			return 'Negation'
		end
	end
	return
end

function CollisionGrid:GetSize(): Vector2
	return self._gridSize
end

function CollisionGrid:GetOrigin(): CFrame
	return self._origin
end

function CollisionGrid.GetGroupId(rowSize: number, row: number, col: number): number
	local numGroups = math.ceil((rowSize + 1)/32)
	return (row * numGroups) + math.ceil((col + 1)/32)
end

function CollisionGrid.HasCollision(grid: CollisionGridList, gridSize: number, row: number, col: number): number
	local groupId = CollisionGrid.GetGroupId(gridSize, row, col)
	local group = grid[groupId] or 0
	return bit32.extract(group, col % 32)
end

function CollisionGrid.GetBitsBehind(group: number, col: number, dir: number): number
	if dir > 0 then
		return bit32.band(group, Bit32Util.FILL_R[col - 1])
	else
		return bit32.band(group, Bit32Util.FILL_L[31 - col - 1])
	end
end

function CollisionGrid.GetBitsInFront(group: number, col: number, dir: number): number
	if dir > 0 then
		return bit32.band(group, Bit32Util.FILL_L[31 - col - 1])
	else
		return bit32.band(group, Bit32Util.FILL_R[col - 1])
	end
end

function CollisionGrid.countz(group: number, dir: number): number
	return dir > 0 and bit32.countrz(group) or bit32.countlz(group)
end

function CollisionGrid.GetCollision(group: number, col: number, dir: number): number
	group = CollisionGrid.GetBitsInFront(group, col, dir)
	return CollisionGrid.countz(group, dir)
end

function CollisionGrid.CanReachBit(group: number, fromBit: number, toBit: number, dir): boolean
	local _dir = math.sign(toBit - fromBit) -- Do not use this for actual direction, may be 0
	if _dir ~= 0 and _dir ~= dir then
		return false
	end
	if dir > 0 then
		return CollisionGrid.GetCollision(group, fromBit, dir) > toBit
	else
		return 31 - CollisionGrid.GetCollision(group, fromBit, dir) < toBit
	end
end

function CollisionGrid.GetGroup(grid: CollisionGridList, groupId: number, type: ObjectType): number
	return grid[groupId] or MAP_DEFAULTS[type]
end

function CollisionGrid.GetCollisionGroup(grid: CollisionGridList, groupId: number): number
	return CollisionGrid.GetGroup(grid, groupId, OBJ_TYPE.Collision)
end

--[=[
	
	@return (number, number, number) -- First group in the row adjusted for the startCol and (first + dir) and last group id of the row starting at startCol in direction dir
]=]
function CollisionGrid.GetRowFromStartCol(grid: CollisionGridList, rowSize: number, row: number, startCol: number, dir: number): (number?, number?, number?)
	local numGroups = math.ceil((rowSize + 1)/32)
	local firstGroupId = CollisionGrid.GetGroupId(rowSize, row, startCol)
	local col = startCol % 32
	
	local firstGroup = grid[firstGroupId] or 0
	if firstGroup ~= 0 then
		firstGroup = CollisionGrid.GetBitsInFront(firstGroup, col, dir)
	end

	local lastGroupId
	if dir > 0 then
		lastGroupId = (row + 1) * numGroups -- actual last group idY
	elseif dir < 0 then
		lastGroupId = row * numGroups + 1 -- Start group id
	end
	
	return firstGroup, firstGroupId, lastGroupId
end

function CollisionGrid.GetCoords(rowSize: number, groupId: number, col: number): (number, number)
	local numGroups = math.ceil((rowSize + 1)/32)
	local x = math.floor((groupId - 1) / numGroups)
	local z = ((groupId - 1) % numGroups) * 32 + col
	return x, z
end

function CollisionGrid:GetMapAsync(mapName: string): CollisionMap?
	if not self.maps[mapName] then
		return
	end
	if self._job.Running then
		self._job.OnFinished:Wait()
		if not self._job.Active then
			return
		end
	end
	return self.maps[mapName]
end

function CollisionGrid:GetMapPromise(mapName: string): Promise
	if not self.maps[mapName] then
		return
	end
	if not self._job.Running then
		return Promise.resolve(self.obsNodes)
	end
	local promise = Promise.fromEvent(self._job.OnFinished):andThen(function()
		if not self._job.Active then
			local p = Promise.new()
			p:cancel()
			return p
		end
		return
	end):andThen(function()
		local map = self.maps[mapName]
		if not map then
			local p = Promise.new()
			p:cancel()
			return p
		end
		return map
	end)
	return promise
end

function CollisionGrid:Destroy(): ()
	(self._job :: ParallelJobHandler.Job):SetSharedTable("Data", nil)
	self._handler:Remove(self._job)
	self._handler:Destroy()
end

function CollisionGrid.iterX(gridSize: Vector2, obstaclesX: CollisionGridList, iterator: (x: number, z: number) -> ()): ()
	local numGroups = math.ceil((gridSize.X + 1)/32)
	for groupId, group in obstaclesX do
		local x = math.ceil(groupId/numGroups) - 1
		local z = ((groupId - 1) % numGroups) * 32
		for i = 0, 31 do
			local val = bit32.extract(group, i)
			if val == 1 then
				iterator(x, z + i)
			end
		end
	end
end

function CollisionGrid.iterZ(gridSize: Vector2, obstaclesZ: CollisionGridList, iterator: (x: number, z: number) -> ()): ()
	local numGroups = math.ceil((gridSize.Y + 1)/32)
	for groupId, group in obstaclesZ do
		local z = math.ceil(groupId/numGroups) - 1
		local x = ((groupId - 1) % numGroups) * 32
		for i = 0, 31 do
			local val = bit32.extract(group, i)
			if val == 1 then
				iterator(x + i, z)
			end
		end
	end
end

function CollisionGrid.concat(fn: (new: number, old: number) -> number, default: number, ...: CollisionGridList): CollisionGridList
	local newList = ... -- sets newList as first list in ...
	newList = table.clone(newList) -- Clone table to avoid modifying the original
	local i = 2
	local list = select(i, ...)
	while list ~= nil do
		for groupId, group in pairs(list) do
			newList[groupId] = fn(group, newList[groupId] or default)
		end
		i += 1
		list = select(i, ...)
	end
	return newList
end

function CollisionGrid.combineMaps(...: CollisionMap): (CollisionGridList, CollisionGridList)
	local colX = {}
	local colZ = {}
	local negX = {}
	local negZ = {}
	local i = 1
	local map = select(i, ...)
	while map ~= nil do
		if map[CollisionGrid.OBJECT_TYPE.Collision] then
			table.insert(colX, map[CollisionGrid.OBJECT_TYPE.Collision].nodesX)
			table.insert(colZ, map[CollisionGrid.OBJECT_TYPE.Collision].nodesZ)
		end
		if map[CollisionGrid.OBJECT_TYPE.Negation] then
			table.insert(negX, map[CollisionGrid.OBJECT_TYPE.Negation].nodesX)
			table.insert(negZ, map[CollisionGrid.OBJECT_TYPE.Negation].nodesZ)
		end
		i += 1
		map = select(i, ...)
	end
	-- Combine maps
	local collisionsX, collisionsZ
	if #colX > 0 then
		-- Combine collision maps
		collisionsX = CollisionGrid.concat(bit32.bor, 0, table.unpack(colX))
		collisionsZ = CollisionGrid.concat(bit32.bor, 0, table.unpack(colZ))
		-- Combine negation maps with collision maps
		collisionsX = CollisionGrid.concat(bit32.band, 0, collisionsX, table.unpack(negX))
		collisionsZ = CollisionGrid.concat(bit32.band, 0, collisionsZ, table.unpack(negZ))
	end
	return collisionsX or {}, collisionsZ or {}
end

export type CollisionGrid = typeof(CollisionGrid.newAsync(...))
export type CollisionGridList = {[number]: number}
type Promise = typeof(Promise.new(...))
return CollisionGrid