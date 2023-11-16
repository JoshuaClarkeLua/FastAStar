local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local PriorityQueue = require(ReplicatedStorage.Shared.PriorityQueue)
local Vector2Util = require(ReplicatedStorage.Shared.Vector2Util)
local CollisionGrid = require(ServerScriptService.Server.Pathfinding.CollisionGrid)
local GridUtil = require(ServerScriptService.Server.Pathfinding.GridUtil)

type CollisionGridList = CollisionGrid.CollisionGridList
type CollisionMap = CollisionGrid.CollisionMap

local function _doPart(node)
	local p = Instance.new("Part")
	p.Size = Vector3.one
	p.Anchored = true
	p.Position = Vector3.new(node.X, workspace.Baseplate.Size.Y/2, node.Y)
	p.Parent = workspace
end

local Room = {}
Room.__index = Room

local function getEdges(self, firstNode: Vector2)
	local nodesX = self.map.nodesX
	local edges = {}
	local queue = {firstNode}
	local closed = {}
	local s = os.clock()
	while #queue > 0 do
		local node = table.remove(queue, 1)
		for _, dir in ipairs(GridUtil.CARDINAL_DIR) do
			local edge = node + dir
			-- Skip if closed
			if closed[edge.X] then
				if closed[edge.X][edge.Y] then
					continue
				end
				closed[edge.X][edge.Y] = true
			else
				closed[edge.X] = {
					[edge.Y] = true
				}
			end
			-- Check if the neighbor is an edge
			if not GridUtil.isInGrid(self.gridSize.X, self.gridSize.Y, edge.X, edge.Y) or CollisionGrid.HasCollision(nodesX, self.gridSize.X, edge.X, edge.Y) == 1 then
				if edges[edge.X] then
					edges[edge.X][edge.Y] = dir
				else
					edges[edge.X] = {
						[edge.Y] = dir
					}
				end
			else
				table.insert(queue, edge)
			end
		end
	end
	s = os.clock() - s
	print(s)
	return edges
end

function Room.new(gridSize: Vector2, map: RoomLinkCollisionMap, pos: Vector2)
	local self = setmetatable({}, Room)

	self.Id = HttpService:GenerateGUID(false)
	self.map = map
	self.gridSize = gridSize
	self.edgeNodes = getEdges(self, Vector2Util.floor(pos)) -- {[x]: {[z]: Vector2}}
	self.links = {} :: {[string]: any} -- linkId -> any
	self.organizedLinks = {} :: {[string]: {[string]: {[string]: any}}} -- toMap -> toRoom -> linkId -> any
	
	-- TODO: Calculate room bounds (edge nodes)

	return self
end

function Room:Destroy()

end

function Room:SetLink(id: string, pos: Vector2, toMap: string, toRoom: string): ()
	if self.links[id] then
		local link = self.links[id]
		self.organizedLinks[link.toMap][link.toRoom][id] = nil
	end
	local link = {
		id = id,
		pos = pos,
		toMap = toMap,
		toRoom = toRoom,
	}
	self.links[id] = link
	self.organizedLinks[toMap][toRoom][id] = link
end

function Room:RemoveLink(id: string): ()
	local link = self.links[id]
	if not link then
		return
	end
	self.links[id] = nil
	self.organizedLinks[link.toMap][link.toRoom][id] = nil
end

function Room.isNodeInRoom(room: Room, nodePos: Vector2): boolean
	local nx,nz = nodePos.X, nodePos.Y
	local zT = room.edgeNodes[nx]
	-- Return false if no edge nodes at x
	if not zT then
		return false
	end
	-- Return false if nodePos is an edge node
	if zT[nz] then
		return false
	end
	-- Get edge node closest to nodePos with z higher than nodePos
	-- Get edge node closest to nodePos with z lower than nodePos
	local zHigh
	local zLow
	for z in pairs(zT) do
		if z > nz then
			if not zHigh or z < zHigh then
				zHigh = z
			end
		elseif z < nz then
			if not zLow or z > zLow then
				zLow = z
			end
		end
	end
	-- Return false if no zHigh or zLow (should be impossible as we already checked if nodePos is an edge node)	
	if not zHigh or not zLow then
		return false
	end
	-- Check to make sure the direction of zHigh and zLow both face toward each other
	-- zHigh's direction must be -1 (facing toward lower z edge nodes) or 0 (double edge)
	-- zLow's direction must be 1 (facing toward higher z edge nodes) or 0 (double edge)
	return zT[zHigh].Z <= 0 and zT[zLow].Z >= 0
end


local RoomLinker = {}
RoomLinker.__index = RoomLinker

function RoomLinker.new(gridSize: Vector2)
	local self = setmetatable({}, RoomLinker)

	self._gridSize = gridSize
	self._maps = {} :: {[string]: CollisionGridList} -- mapName -> CollisionGridList (nodesX)
	self._mapRooms = {} :: {[string]: {[string]: Room}} -- mapName -> roomId -> Room
	
	return self
end

function RoomLinker:AddMap(mapName: string, ...: CollisionMap): ()
	if self._maps[mapName] then
		error(`Map '{mapName}' already exists`)
	end
	local nodesX, nodesZ = CollisionGrid.combineMaps(...)
	self._maps[mapName] = {
		maps = {...},
		nodesX = nodesX,
		nodesZ = nodesZ,
	}
	self._mapRooms[mapName] = {}
end

function RoomLinker:RemoveMap(map: string): ()
	self._maps[map] = nil
	local rooms = self._mapRooms[map]
	if rooms then
		self._mapRooms[map] = nil
		for _, room in pairs(rooms) do
			room:Destroy()
		end
	end
end

function RoomLinker:_AddRoom(map: string, room: Room): ()
	self._mapRooms[map][room.Id] = room
end

function RoomLinker:GetMap(map: string): CollisionGridList?
	return self._maps[map]
end

function RoomLinker:GetRoomAtPos(map: string, pos: Vector2): Room?
	-- Floor the vector to get the node's position
	pos = Vector2Util.floor(pos)
	-- Find the room at that position (if any)
	for _, room in pairs(self._mapRooms[map]) do
		if Room.isNodeInRoom(room, pos) then
			return room
		end
	end
	return
end

function RoomLinker:AddLink(id: string, fromPos: Vector2, toPos: Vector2, fromMap: string, toMap: string?)
	toMap = toMap or fromMap
	-- Find the room in fromMap fromPos is in
	local fromRoom = self:GetRoomAtPos(fromMap, fromPos)
	-- If fromPos is not in an existing room in fromMap, create a new room
	if not fromRoom then
		local map = self:GetMap(fromMap)
		if not map then
			error(`Map '{fromMap}' does not exist`)
		end
		fromRoom = Room.new(self._gridSize, map, fromPos)
		self:_AddRoom(fromMap, fromRoom)
	end
	-- Repeat for toPos and toMap
	local toRoom = self:GetRoomAtPos(toMap, toPos)
	if not toRoom then
		local map = self:GetMap(toMap)
		if not map then
			error(`Map '{toMap}' does not exist`)
		end
		toRoom = Room.new(self._gridSize, map, toPos)
		self:_AddRoom(toMap, toRoom)
	end
	-- Add the link to the rooms
	fromRoom:SetLink(id, fromPos, toMap, toRoom)
	toRoom:SetLink(id, toPos, fromMap, fromRoom)
end

function RoomLinker:FindLinkPath(fromPos: Vector2, toPos: Vector2, fromMap: string, toMap: string?)
	toMap = toMap or fromMap
	local fromRoom = self:GetRoomAtPos(fromMap, fromPos)
	local toRoom = self:GetRoomAtPos(toMap, toPos)
	-- Return if either room does not exist
	if not (fromRoom and toRoom) then
		return {}
	end
	-- Return if toPos is reachable within the same room
	if fromRoom == toRoom then
		return {{fromMap, toPos}}
	end
	-- TODO: Find the path of links to take to get from fromMap -> fromRoom to toMap -> toRoom
	local queue = {}
	local parents = {}
	local path = {}
	-- Add fromRoom links to queue
	for _, link in pairs(fromRoom._links) do
		table.insert(queue, link)
	end
	-- Loop ting
	while #queue > 0 do
		local link = table.remove(queue, 1)

	end
	return path
end

type RoomLink = {
	id: string,
	pos: Vector2,
	toMap: string,
	toRoom: string,
}
type MapGroupLink = {
	id: string,
	fromPos: Vector2,
	toPos: Vector2,
	fromMap: string,
	toMap: string,
}
type RoomLinkCollisionMap = {
	maps: {CollisionMap},
	nodesX: {number},
	nodesZ: {number},
}
export type LinkPath = {{string & Vector2}} -- {{mapName, linkId | pos}}
export type Room = typeof(Room.new(...))
export type RoomLinker = typeof(RoomLinker.new(...))
return RoomLinker