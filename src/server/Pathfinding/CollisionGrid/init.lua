--!native
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Imports = require(script.Parent.Imports)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Vector2Util = Imports.Vector2Util
local Vector3Util = Imports.Vector3Util
local Bit32Util = require(script.Parent.Bit32Util)
local GridUtil = require(script.Parent.GridUtil)
local NodeUtil = require(script.Parent.NodeUtil)

local XZ = Vector3.new(1, 0, 1)
local PAD = 1 / 4

local OBJ_TYPE = {
	Collision = "Collision",
	Negation = "Negation",
}
local MAP_GROUP_DEFAULTS = {
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

local function newMap(collisionsByDefault: boolean?): CollisionMap
	return {
		CollisionsByDefault = collisionsByDefault or false,
		[OBJ_TYPE.Collision] = {
			nodeMap = {},
			invertedNodeMap = {},
			nodesX = {},
			nodesZ = {},
		},
		[OBJ_TYPE.Negation] = {
			nodeMap = {},
			nodesX = {},
			nodesZ = {},
		},
	}
end

local CollisionGrid = {}
CollisionGrid.__index = CollisionGrid
CollisionGrid.OBJECT_TYPE = OBJ_TYPE
CollisionGrid.DEFAULT_MAP = newMap()
CollisionGrid.DEFAULT_MAP_COL = newMap(true)
CollisionGrid.HANDLER_SCRIPT = script:FindFirstChild("Handler")

local function addMapNodes(self, nodes, _map, type, invert): ()
	-- Add nodes to map if nodes are already calculated
	if nodes ~= nil then
		self:_ChangeMapNodes(nodes, _map, type, true, invert)
	end
end

local function removeMapNodes(self, nodes, _map, type, invert): ()
	-- Remove nodes from map if nodes are already calculated
	if nodes ~= nil then
		self:_ChangeMapNodes(nodes, _map, type, false, invert)
	end
end

local function addMapObject(self, object, _map, type, invert): ()
	-- Add map to object
	object.maps[_map] = {
		type = type,
		invert = invert,
	}
	-- Add nodes to map
	addMapNodes(self, object.nodes, _map, type, invert)
end

local function removeMapObject(self, object, _map): ()
	local data = object.maps[_map]
	if not data then
		return
	end
	-- Remove nodes from map
	removeMapNodes(self, object.nodes, _map, data.type, data.invert)
	object.maps[_map] = nil
end

function CollisionGrid.getNodesInBox(origin, gridSize, cf, size): ObjNodes
	cf = origin:ToObjectSpace(cf)
	local pos = cf.Position
	local pos2d = Vector2.new(pos.X, pos.Z)
	local size2 = size / 2
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
	local lineMag2 = math.max(0.5, line2d.Magnitude / 2)
	local line_2 = cf:VectorToWorldSpace(size * widV) * XZ
	local line2d_2 = Vector2.new(line_2.X, line_2.Z)
	local lineMag2_2 = math.max(0.5, line2d_2.Magnitude / 2)
	-- Calculate the square's opposite corners which fit the line
	local rsize2 = cf:VectorToWorldSpace(size2) * XZ
	local nrsize2 = cf:VectorToWorldSpace(Vector3.new(-size2.X, 0, size2.Z))
	local p1 = rsize2
	local p2 = -rsize2
	local p3 = nrsize2
	local p4 = -nrsize2
	local min: Vector2 =
		Vector2Util.floor(pos2d + Vector2.new(math.min(p1.X, p2.X, p3.X, p4.X), math.min(p1.Z, p2.Z, p3.Z, p4.Z)))
	local max: Vector2 =
		Vector2Util.ceil(pos2d + Vector2.new(math.max(p1.X, p2.X, p3.X, p4.X), math.max(p1.Z, p2.Z, p3.Z, p4.Z)))

	local nodes = {} -- {x,z, x,z, ...}
	for x = min.X, max.X do
		if x < 0 or x > gridSize.X then
			continue
		end
		for z = min.Y, max.Y do
			if z < 0 or z > gridSize.Y then
				continue
			end
			local cellPos = Vector2.new(x, z) - pos2d
			local v2 = Vector3Util.project(cellPos, line2d)

			-- Check if cell is past the line (vertical check)
			if math.floor(lineMag2 - v2.Magnitude + PAD) >= 0 then
				-- Check if cell is too far from the line (horizontal check)
				v2 = Vector3Util.project(cellPos, line2d_2)
				if math.floor(lineMag2_2 - v2.Magnitude + PAD) >= 0 then
					table.insert(nodes, x)
					table.insert(nodes, z)
				end
			end
		end
	end

	return nodes
end

function CollisionGrid.new(
	origin: CFrame,
	gridSize: Vector2,
	config: CollisionGridConfig
): CollisionGrid
	if not config then
		error("Invalid Config")
	end
	origin = origin * CFrame.new(-gridSize.X / 2, 0, -gridSize.Y / 2)
	local trove = Trove.new()
	local self = setmetatable({
		Id = HttpService:GenerateGUID(false),
		Origin = origin,
		Size = gridSize,
		Config = config,
		maps = {} :: { [string]: CollisionMap }, -- [mapName]: CollisionMap
		objects = {} :: { [string]: Object }, -- [id]: Object
		--
		OnMapAdded = trove:Add(Signal.new()), -- (mapName: string, map: CollisionMap)
		OnMapRemoved = trove:Add(Signal.new()), -- (mapName: string)
		OnMapChanged = trove:Add(Signal.new()), -- (mapName: string, nodes: { [node: Vector2]: hasCollision })
		OnDestroy = Signal.new(),
		--
		_trove = trove,
		_numGroupsX = math.ceil(gridSize.X / 32),
		_numGroupsZ = math.ceil(gridSize.Y / 32),
	}, CollisionGrid)

	trove:Add(function()
		self.OnDestroy:Fire()
		self.OnDestroy:Destroy()
	end)

	return self
end

function CollisionGrid:Destroy(): ()
	self._trove:Destroy()
end

function CollisionGrid:AddMap(map: string, collisionsByDefault: boolean?): ()
	if self.maps[map] then
		error(`Map '{map}' already exists`)
	end
	self.maps[map] = newMap(collisionsByDefault)
	self.OnMapAdded:Fire(map, self.maps[map])
end

function CollisionGrid:RemoveMap(map: string): ()
	if self.maps[map] then
		error(`Map '{map}' does not exist`)
	end
	self.maps[map] = nil
	for _, object in pairs(self.objects) do
		object.maps[map] = nil
	end
	self.OnMapRemoved:Fire(map)
end

function CollisionGrid:HasMap(map: string): boolean
	return self.maps[map] ~= nil
end

function CollisionGrid:SetObject(id: string, cf: CFrame, size: Vector3): ()
	local object = self.objects[id]
	local nodes = CollisionGrid.getNodesInBox(self.Origin, self.Size, cf, size)
	if object ~= nil then
		-- Remove object old nodes that are not in the new nodes
		local oldNodes = object.nodes
		if oldNodes ~= nil then
			for mapName, data in pairs(object.maps) do
				removeMapNodes(self, object.nodes, mapName, data.type, data.invert)
			end
		end
	else
		-- Create object table if it does not exist
		object = {
			maps = {},
		}
		self.objects[id] = object
	end
	-- Add new nodes
	object.nodes = nodes
	for mapName, data in pairs(object.maps) do
		addMapNodes(self, object.nodes, mapName, data.type, data.invert)
	end
end

function CollisionGrid:RemoveObject(id: string): ()
	local object = self.objects[id]
	if not object then
		return
	end
	self.objects[id] = nil
	for map, data in pairs(object.maps) do
		removeMapObject(self, object, map)
	end
end

function CollisionGrid:HasObject(id: string): boolean
	return self.objects[id] ~= nil
end


local function updateCollisionGridList(collisionList: CollisionGridList, hasCollision: boolean, rowLen: number, row: number, col: number, groupDefault: number, bitSet: number, bitUnset: number): ()
	local groupId = CollisionGrid.GetGroupId(rowLen, row, col)
	local group = bit32.replace(collisionList[groupId] or groupDefault, hasCollision and bitSet or bitUnset, col % 32)
	collisionList[groupId] = group ~= groupDefault and group or nil
end
local function changeMapNode(
	self,
	nodeId: number,
	x: number,
	z: number,
	typeMap: CollisionTypeMap,
	groupDefault: number,
	nodeDefault: number,
	bitSet: number,
	bitUnset: number,
	add: boolean,
	inverted: boolean
): boolean?
	local newCollisionState: boolean?
	local size = self:GetSize()

	local collisions = (typeMap.nodeMap[nodeId] or nodeDefault)
	local nodeAdd = add and 1 or -1

	-- STEP 1 -- Add nodeAdd to appropriate node map
	local invertedNodes = typeMap.invertedNodeMap
	if inverted then
		if not invertedNodes then
			error("Inverted nodes are not available for this map")
		end
		-- Update inverted node map
		if invertedNodes[nodeId] then
			invertedNodes[nodeId] += nodeAdd
			if invertedNodes[nodeId] == 0 then
				invertedNodes[nodeId] = nil
			end
		else
			invertedNodes[nodeId] = nodeAdd
		end
	else
		collisions += nodeAdd
	end

	-- STEP 2 -- Update node map
	if collisions == nodeDefault then
		typeMap.nodeMap[nodeId] = nil
	else
		typeMap.nodeMap[nodeId] = collisions
	end

	-- STEP 3 -- Apply inverted nodes
	if invertedNodes then
		-- Remove 1 from collisions
		local numInvertedNodes = invertedNodes[nodeId]
		if numInvertedNodes and numInvertedNodes > 0 then
			collisions -= 1
		end
	end

	-- STEP 4 -- Update collisions if it went from 0 -> 1 or 1 -> 0
	if collisions == 0 or collisions == 1 then
		newCollisionState = collisions == 1
		-- Update nodesX
		updateCollisionGridList(typeMap.nodesX, newCollisionState :: boolean, size.Y, x, z, groupDefault, bitSet, bitUnset)
		-- Update nodesZ
		updateCollisionGridList(typeMap.nodesZ, newCollisionState :: boolean, size.X, z, x, groupDefault, bitSet, bitUnset)
	end

	return newCollisionState
end
function CollisionGrid:_ChangeMapNodes(nodes: ObjNodes, mapName: string, type: ObjectType, add: boolean, inverted: boolean): ()
	local map = self.maps[mapName]
	if not map then
		return
	end
	-- Get the type map
	local typeMap = map[type]
	--
	local groupDefault = MAP_GROUP_DEFAULTS[type]
	local nodeDefault = 0
	local bitSet = MAP_BIT_SET[type]
	local bitUnset = MAP_BIT_UNSET[type]
	if map.CollisionsByDefault and type == OBJ_TYPE.Collision then
		groupDefault = bit32.bnot(groupDefault)
		nodeDefault = 1
	end

	-- Add nodes
	local changedNodes = {} :: { [number]: boolean }
	for i = 1, #nodes, 2 do
		local x = nodes[i]
		local z = nodes[i + 1]
		local nodeId = NodeUtil.getNodeId(self.Size.X, x, z)
		local newCollisionState = changeMapNode(self, nodeId, x, z, typeMap, groupDefault, nodeDefault, bitSet, bitUnset, add, inverted)
		if newCollisionState ~= nil then
			changedNodes[Vector2.new(x, z)] = newCollisionState
		end
	end

	if next(changedNodes) ~= nil then
		self.OnMapChanged:Fire(map, changedNodes)
	end
end

function CollisionGrid:AddMapObject(id: string, map: string, typeName: ObjectTypeName, invert: boolean?): ()
	local newType = OBJ_TYPE[typeName]
	if not newType then
		error(`Invalid type '{typeName}'`)
	end
	if invert == true and newType ~= OBJ_TYPE.Collision then
		error(`Invalid object parameters: Object must be of type 'Collision' to be inverted`)
	end
	if not self.maps[map] then
		error(`Invalid map '{map}'`)
	end
	local object = self.objects[id]
	if not object then
		error(`Object '{id}' does not exist`)
	end
	invert = invert == true or false
	local oldMap = object.maps[map]
	if oldMap then
		-- Return if object was already added to map type
		if oldMap.type == newType and oldMap.invert == invert then
			return
		end
		removeMapObject(self, object, map)
	end
	-- Add object to map
	addMapObject(self, object, map, newType, invert)
end

function CollisionGrid:RemoveMapObject(id: string, map: string): ()
	local object = self.objects[id]
	if not object then
		return
	end
	local data = object.maps[map]
	if not data then
		return
	end
	if object.nodes ~= nil then
		removeMapObject(self, object, map)
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
			return "Collision"
		elseif type == OBJ_TYPE.Negation then
			return "Negation"
		end
	end
	return
end

function CollisionGrid:GetMap(mapName: string): CollisionMap?
	local map = self.maps[mapName]
	if map then
		return map
	end
	local default = self.Config.CollisionMaps[mapName]
	return newMap(default and default.CollisionsByDefault or false)
end

function CollisionGrid:ObserveMaps(observer: (name: string, map: CollisionMap) -> ()): RBXScriptConnection
	for name, map in pairs(self.maps) do
		observer(name, map)
	end
	return self.OnMapAdded:Connect(observer)
end

function CollisionGrid:GetSize(): Vector2
	return self.Size
end

function CollisionGrid:GetOrigin(): CFrame
	return self.Origin
end

function CollisionGrid:ToGridSpace(pos: Vector3): Vector3
	return self:GetOrigin():PointToObjectSpace(pos)
end

function CollisionGrid:ToWorldSpace(pos: Vector3): Vector3
	return self:GetOrigin():PointToWorldSpace(pos)
end

function CollisionGrid:HasPos3D(pos: Vector3): boolean
	local gridSize = self:GetSize()
	-- convert pos to grid space
	local _pos = self:ToGridSpace(pos)
	return GridUtil.isInGrid(gridSize.X, gridSize.Y, _pos.X, _pos.Z)
end

function CollisionGrid:GetMaps(names: { string }): { CollisionMap }
	local maps = {}
	for _, name in pairs(names) do
		local map = self:GetMap(name)
		if map then
			table.insert(maps, map)
		end
	end
	return maps
end

function CollisionGrid.GetPosFromNodeId(gridSize: Vector2, nodeId: number): (number, number)
	return NodeUtil.getPosFromId(gridSize.Y, nodeId)
end

function CollisionGrid.GetNodeIdFromPos(gridSize: Vector2, x: number, z: number): number
	return NodeUtil.getNodeId(gridSize.Y, x, z)
end

function CollisionGrid.GetGroupId(rowSize: number, row: number, col: number): number
	local numGroups = math.ceil((rowSize + 1) / 32)
	return (row * numGroups) + math.ceil((col + 1) / 32)
end

function CollisionGrid.HasCollision(
	grid: CollisionGridList,
	gridSize: number,
	row: number,
	col: number,
	collisionsByDefault: boolean?
): number
	local groupId = CollisionGrid.GetGroupId(gridSize, row, col)
	return bit32.extract(CollisionGrid.GetGroup(grid, groupId, OBJ_TYPE.Collision, collisionsByDefault), col % 32)
end

function CollisionGrid.GetBitsBehind(group: number, col: number, dir: number): number
	if dir > 0 then
		return bit32.band(group, Bit32Util.FILL_R[col])
	else
		return bit32.band(group, Bit32Util.FILL_L[31 - col])
	end
end

function CollisionGrid.GetBitsInFront(group: number, col: number, dir: number): number
	if dir > 0 then
		return bit32.band(group, Bit32Util.FILL_L[31 - col])
	else
		return bit32.band(group, Bit32Util.FILL_R[col])
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

function CollisionGrid.GetGroup(
	grid: CollisionGridList,
	groupId: number,
	type: ObjectType,
	collisionsByDefault: boolean?
): number
	local group = grid[groupId]
	if not group then
		group = MAP_GROUP_DEFAULTS[type]
		if collisionsByDefault and type == OBJ_TYPE.Collision then
			group = bit32.bnot(group)
		end
	end
	return group
end

function CollisionGrid.GetCollisionGroup(
	grid: CollisionGridList,
	groupId: number,
	collisionsByDefault: boolean?
): number
	return CollisionGrid.GetGroup(grid, groupId, OBJ_TYPE.Collision, collisionsByDefault)
end

function CollisionGrid.GetGridFromPos(grids: { [any]: CollisionGrid }, pos: Vector3): CollisionGrid?
	local validGrids = {}
	for _, grid in pairs(grids) do
		if grid:HasPos3D(pos) then
			table.insert(validGrids, grid)
		end
	end
	if #validGrids == 0 then
		return
	end

	local lowYDiff = math.huge
	local closestGrid = nil :: CollisionGrid?
	for _, grid in pairs(validGrids) do
		local yDiff = pos.Y - grid:GetOrigin().Y
		if yDiff >= -.001 and yDiff < lowYDiff then
			lowYDiff = yDiff
			closestGrid = grid
		end
	end
	return closestGrid
end

--[=[
	
	@return (number, number, number) -- First group in the row adjusted for the startCol and (first + dir) and last group id of the row starting at startCol in direction dir
]=]
function CollisionGrid.GetRowFromStartCol(
	grid: CollisionGridList,
	rowSize: number,
	row: number,
	startCol: number,
	dir: number,
	collisionsByDefault: boolean?
): (number?, number?, number?)
	local numGroups = math.ceil((rowSize + 1) / 32)
	local firstGroupId = CollisionGrid.GetGroupId(rowSize, row, startCol)
	local col = startCol % 32

	local firstGroup = CollisionGrid.GetGroup(grid, firstGroupId, OBJ_TYPE.Collision, collisionsByDefault)
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
	local numGroups = math.ceil((rowSize + 1) / 32)
	local x = math.floor((groupId - 1) / numGroups)
	local z = ((groupId - 1) % numGroups) * 32 + col
	return x, z
end

function CollisionGrid.iterX(
	gridSize: Vector2,
	obstaclesX: CollisionGridList,
	iterator: (x: number, z: number) -> ()
): ()
	local numGroups = math.ceil((gridSize.Y + 1) / 32)
	for groupId, group in obstaclesX do
		local x = math.floor((groupId - 1) / numGroups)
		local z = ((groupId - 1) % numGroups) * 32
		for col = 0, 31 do
			local val = bit32.extract(group, col)
			if val == 1 then
				iterator(x, z + col)
			end
		end
	end
end

function CollisionGrid.iterZ(
	gridSize: Vector2,
	obstaclesZ: CollisionGridList,
	iterator: (x: number, z: number) -> ()
): ()
	local numGroups = math.ceil((gridSize.Y + 1) / 32)
	for groupId, group in obstaclesZ do
		local z = math.ceil(groupId / numGroups) - 1
		local x = ((groupId - 1) % numGroups) * 32
		for i = 0, 31 do
			local val = bit32.extract(group, i)
			if val == 1 then
				iterator(x + i, z)
			end
		end
	end
end

function CollisionGrid.concat(
	fn: (new: number, old: number) -> number,
	default: number,
	collisionLists: { CollisionGridList }
): CollisionGridList
	local newList = table.remove(collisionLists, 1) -- sets newList as first list in ...
	if newList == nil then
		return {}
	end
	newList = table.clone(newList) -- Clone table to avoid modifying the original
	for _, list in pairs(collisionLists) do
		for groupId, group in pairs(list) do
			newList[groupId] = fn(group, newList[groupId] or default)
		end
	end
	return newList
end

function CollisionGrid.concatVariadic(
	fn: (new: number, old: number) -> number,
	default: number,
	...: CollisionGridList
): CollisionGridList
	local newList = ... -- sets newList as first list in ...
	if newList == nil then
		return {}
	end
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

function CollisionGrid._combineMaps(
	groupDefault: number,
	type,
	maps: { CollisionMap }
): (CollisionGridList, CollisionGridList)
	local X = {}
	local Z = {}
	for _, map in pairs(maps) do
		if map[type] then
			table.insert(X, map[type].nodesX)
			table.insert(Z, map[type].nodesZ)
		end
	end
	-- Combine maps
	local collisionsX, collisionsZ
	if #X > 0 then
		local fn = type == OBJ_TYPE.Collision and bit32.bor or bit32.band
		-- Combine collision maps
		collisionsX = CollisionGrid.concat(fn, groupDefault, X)
		collisionsZ = CollisionGrid.concat(fn, groupDefault, Z)
	end
	return collisionsX or {}, collisionsZ or {}
end

function CollisionGrid._combineGroups(
	groupsX: { [number]: any }?,
	groupsZ: { [number]: any }?,
	groupDefault: number,
	type,
	maps: { CollisionMap }
): (CollisionGridList, CollisionGridList)
	local X = {}
	local Z = {}
	for _, map in pairs(maps) do
		if map[type] then
			local _X = {}
			local _Z = {}
			if groupsX then
				for groupId in pairs(groupsX) do
					table.insert(_X, map[type].nodesX[groupId])
				end
			end
			if groupsZ then
				for groupId in pairs(groupsZ) do
					table.insert(_Z, map[type].nodesZ[groupId])
				end
			end
			table.insert(X, _X)
			table.insert(Z, _Z)
		end
	end
	-- Combine maps
	local collisionsX, collisionsZ
	if #X > 0 then
		local fn = type == OBJ_TYPE.Collision and bit32.bor or bit32.band
		-- Combine collision maps
		collisionsX = CollisionGrid.concat(fn, groupDefault, X)
		collisionsZ = CollisionGrid.concat(fn, groupDefault, Z)
	end
	return collisionsX or {}, collisionsZ or {}
end

function CollisionGrid.combineMaps(maps: { [any]: CollisionMap }): (CollisionGridList, CollisionGridList, boolean)
	local colDefault = MAP_GROUP_DEFAULTS[OBJ_TYPE.Collision]
	local invColDefault = bit32.bnot(MAP_GROUP_DEFAULTS[OBJ_TYPE.Collision])
	--
	local normalList = {}
	local collisionByDefaultList = {}
	local collisionsByDefault = false
	for _, map in pairs(maps) do
		if map.CollisionsByDefault then
			collisionsByDefault = true
			table.insert(collisionByDefaultList, map)
		else
			table.insert(normalList, map)
		end
	end
	-- Combine normal map collision maps
	local cX, cZ = CollisionGrid._combineMaps(colDefault, OBJ_TYPE.Collision, normalList)
	-- Combine collision maps with collisionsByDefault set to true
	if collisionsByDefault then
		-- Combine maps with collisionsByDefault set to true
		local colByDefaultX, colByDefaultZ =
			CollisionGrid._combineMaps(invColDefault, OBJ_TYPE.Collision, collisionByDefaultList)
		-- Combine normal maps with maps with collisionsByDefault set to true
		-- Order of maps is important, normal maps must be last
		cX = CollisionGrid.concatVariadic(bit32.bor, invColDefault, colByDefaultX, cX)
		cZ = CollisionGrid.concatVariadic(bit32.bor, invColDefault, colByDefaultZ, cZ)
	end
	-- Combine all negation maps together
	local nX, nZ = CollisionGrid._combineMaps(MAP_GROUP_DEFAULTS[OBJ_TYPE.Negation], OBJ_TYPE.Negation, maps)
	-- Combine negation maps with collision maps
	local default = collisionsByDefault and invColDefault or colDefault
	local collisionsX = CollisionGrid.concatVariadic(bit32.band, default, cX, nX)
	local collisionsZ = CollisionGrid.concatVariadic(bit32.band, default, cZ, nZ)
	return collisionsX or {}, collisionsZ or {}, collisionsByDefault
end

function CollisionGrid.combineGroups(
	groupsX: { [number]: any }?,
	groupsZ: { [number]: any }?,
	maps: { CollisionMap }
): (CollisionGridList, CollisionGridList, boolean)
	local colDefault = MAP_GROUP_DEFAULTS[OBJ_TYPE.Collision]
	local invColDefault = bit32.bnot(MAP_GROUP_DEFAULTS[OBJ_TYPE.Collision])
	--
	local normalList = {}
	local collisionByDefaultList = {}
	local collisionsByDefault = false
	for _, map in pairs(maps) do
		if map.CollisionsByDefault then
			collisionsByDefault = true
			table.insert(collisionByDefaultList, map)
		else
			table.insert(normalList, map)
		end
	end
	-- Combine normal map collision maps
	local cX, cZ = CollisionGrid._combineGroups(groupsX, groupsZ, colDefault, OBJ_TYPE.Collision, normalList)
	-- Combine collision maps with collisionsByDefault set to true
	if collisionsByDefault then
		-- Combine maps with collisionsByDefault set to true
		local colByDefaultX, colByDefaultZ =
			CollisionGrid._combineGroups(groupsX, groupsZ, invColDefault, OBJ_TYPE.Collision, collisionByDefaultList)
		-- Combine normal maps with maps with collisionsByDefault set to true
		-- Order of maps is important, normal maps must be last
		cX = CollisionGrid.concatVariadic(bit32.bor, invColDefault, colByDefaultX, cX)
		cZ = CollisionGrid.concatVariadic(bit32.bor, invColDefault, colByDefaultZ, cZ)
	end
	-- Combine all negation maps together
	local nX, nZ =
		CollisionGrid._combineGroups(groupsX, groupsZ, MAP_GROUP_DEFAULTS[OBJ_TYPE.Negation], OBJ_TYPE.Negation, maps)
	-- Combine negation maps with collision maps
	local default = collisionsByDefault and invColDefault or colDefault
	local collisionsX = CollisionGrid.concatVariadic(bit32.band, default, cX, nX)
	local collisionsZ = CollisionGrid.concatVariadic(bit32.band, default, cZ, nZ)
	return collisionsX or {}, collisionsZ or {}, collisionsByDefault
end

function CollisionGrid.getFilledCollisions(gridSize: Vector2): (CollisionGridList, CollisionGridList)
	local nodesX, nodesZ = {}, {}
	local numGroupsX = math.ceil(gridSize.X / 32)
	local numGroupsZ = math.ceil(gridSize.Y / 32)
	for i = 1, numGroupsX * gridSize.X do
		nodesX[i] = Bit32Util.FILL_R[31]
	end
	for i = 1, numGroupsZ * gridSize.Y do
		nodesZ[i] = Bit32Util.FILL_R[31]
	end
	return nodesX, nodesZ
end

export type ObjectData = {
	cf: CFrame,
	size: Vector3,
}
export type ObjNodes = { number } -- {x, z, x, z, ...}
export type CollisionMap = {
	CollisionsByDefault: boolean,
	Collision: {
		nodeMap: { [number]: number },
		invertedNodeMap: { [number]: number },
		nodesX: { [number]: number },
		nodesZ: { [number]: number },
	},
	Negation: {
		nodeMap: { [number]: number },
		nodesX: { [number]: number },
		nodesZ: { [number]: number },
	},
}
type CollisionTypeMap = {
	nodeMap: { [number]: number },
	invertedNodeMap: { [number]: number }?,
	nodesX: { [number]: number },
	nodesZ: { [number]: number },
}
type Object = {
	nodes: ObjNodes,
	maps: { [string]: any }, -- [MapName]: any
}
export type ObjectType = number
export type ObjectTypeName = "Collision" | "Negation"
export type CollisionGrid = typeof(CollisionGrid.new(...))
export type CollisionGridList = { [number]: number }
-- Config types
export type CollisionMapConfig = {
	CollisionsByDefault: boolean,
}
export type CollisionGridConfig = {
	CollisionMaps: { [string]: CollisionMapConfig },
}
type Promise = typeof(Promise.new(...))
return CollisionGrid
