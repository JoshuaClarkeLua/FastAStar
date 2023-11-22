local HttpService = game:GetService("HttpService")
local AStarJPS = require(script.Parent.AStarJPS)
local CollisionGrid = require(script.Parent.CollisionGrid)
local GridUtil = require(script.Parent.GridUtil)
local Imports = require(script.Parent.Imports)
local NodeUtil = require(script.Parent.NodeUtil)
local Vector2Util = Imports.Vector2Util

type CollisionGridList = CollisionGrid.CollisionGridList
type CollisionMap = CollisionGrid.CollisionMap

local function getLinkKeys(id: string): {string}
	local keys = {}
	for i = 0, 1 do
		table.insert(keys, `{id}_{i}`)
	end
	return keys
end

local function getOtherLinkNum(num: number): number
	return num == 1 and 0 or 1
end

local function removeLink(linker, link: RoomLink): ()
	if link._groupLinks ~= nil then
		link._groupLinks[link] = nil
		link._groupLinks = nil
	end
	link.group = nil :: any
end

local function removeMapLink(linker, map: RoomLinkCollisionMap, link: RoomLink): ()
	-- Remove link from linkByNodeId list
	map.linksByNodeId[link.nodeId][link.id] = nil
	if next(map.linksByNodeId[link.nodeId]) then
		map.linksByNodeId[link.nodeId] = nil
	end
	-- Remove link from map links
	map.links[link.id] = nil
	-- Remove link from group
	removeLink(linker, link)
end


local function addLink(linker, link: RoomLink, prevLink: RoomLink): ()
	-- Delete group if no links are left
	local links = prevLink._groupLinks
	if not links then
		links = {
			[prevLink] = true,
			[link] = true,
		}
		prevLink._groupLinks = links
	else
		links[link] = true
	end
	--
	-- Update group id
	link.group = prevLink.group
	link._groupLinks = links
end

local function iterateLinks(firstLink: RoomLink, iterator: (link: RoomLink) -> ()): ()
	if firstLink._groupLinks ~= nil then
		for link in pairs(firstLink._groupLinks) do
			iterator(link)
		end
	else
		iterator(firstLink)
	end
end

local function newLink(linker, id: string, num: number, cost: number, nodePos: Vector2, map: string, toMap: string): RoomLink
	local _map = linker:GetMap(map)
	local self = {
		id = id,
		num = num,
		cost = cost,
		pos = nodePos,
		map = map,
		nodeId = NodeUtil.getNodeId(_map.gridSize.X, nodePos.X, nodePos.Y),
		toMap = toMap,
		group = HttpService:GenerateGUID(false),

		-- caches
		_linkCosts = {},
	}
	self._next = self
	self._prev = self
	return self
end

local function findLink(linker, map: RoomLinkCollisionMap, start: Vector2): RoomLink?
	local goals = {}
	for _, link in pairs(map.links) do
		table.insert(goals, link.pos)
	end
	local reachedGoals = AStarJPS.findReachable(map.gridSize, start, goals, true, map.nodesX, map.nodesZ)
	if not reachedGoals or #reachedGoals == 0 then
		return
	end
	local goal = reachedGoals[1]
	local nodeId = NodeUtil.getNodeId(map.gridSize.X, goal.X, goal.Y)
	local linkId = next(map.linksByNodeId[nodeId])
	return map.links[linkId]
end

local function _setLinkCosts(linker, pos: Vector2, links: {[RoomLink]: any}): ()
	local first: RoomLink? = next(links)
	if not first then
		error('No links')
	end
	-- Find the costs (distance) of each parent 
	local map = linker:GetMap(first.map)
	local goals = {}
	for parent in pairs(links) do
		table.insert(goals, parent.pos)
	end
	local _, data = AStarJPS.findReachable(map.gridSize, pos, goals, false, map.nodesX, map.nodesZ)
	if not data then
		return
	end
	-- Set link costs
	for _parent in pairs(links) do
		local cost = data.g[_parent.nodeId]
		links[_parent] = cost
	end
end

local function _doPart(pos: Vector3): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = Vector3.one
	p.Position = pos
	p.Transparency = .2
	p.Parent = workspace
	return p
end

local function triggerMapUpdate(linker, map: RoomLinkCollisionMap): ()
	if not map._updateScheduled then
		return
	end
	map._updateScheduled = false
		
	-- Return if no groups changed
	if next(map._groupChangesX) == nil and next(map._groupChangesZ) == nil then
		return
	end
	

	-- 1. Remove collisions from the changed nodes
	local changedNodes = {}
	local _nodesX, _nodesZ = map.nodesX, map.nodesZ
	local overshoot = map.gridSize.X % 32
	overshoot = overshoot ~= 0 and 32 - overshoot or 0
	for groupId, group in pairs(map._groupChangesX) do
		-- Add node ids to changedNodes
		local _group = group
		-- Calculate the id of the first node in the group
		local baseNodeId = (groupId - 1) * 32 + 1
		if overshoot > 0 then -- Accounts for extra nodes at the end of the last group of each row
			local numGroups = math.ceil(map.gridSize.X / 32)
			baseNodeId -= math.floor(groupId / numGroups) * overshoot
		end
		_group = group
		while _group ~= 0 do
			local col = bit32.countrz(_group)
			changedNodes[baseNodeId + col] = true
			_group = bit32.replace(_group, 0, col, 1)
		end
		-- Remove collisions from the nodes
		if _nodesX[groupId] ~= nil then
			local __group = bit32.band(_nodesX[groupId] or 0, bit32.bnot(group))
			_nodesX[groupId] = __group
		end
	end
	for groupId, group in pairs(map._groupChangesZ) do
		if _nodesZ[groupId] ~= nil then
			local __group = bit32.band(_nodesZ[groupId] or 0, bit32.bnot(group))
			_nodesZ[groupId] = __group
		end
	end
	
	-- 2. Find the groups of connected nodes
	local nodeGroups = {}
	local nodeId = next(changedNodes)
	while nodeId ~= nil do
		local node = Vector2.new(NodeUtil.getPosFromId(map.gridSize.X, nodeId))
		changedNodes[nodeId] = nil
		local nodes = {[nodeId] = true}
		local data = AStarJPS.fill(map.gridSize, node, map.nodesX, map.nodesZ)
		for _nodeId in pairs(data.nodesReached) do
			changedNodes[_nodeId] = nil
			nodes[_nodeId] = true
		end
		table.insert(nodeGroups, nodes)
		nodeId = next(changedNodes)
	end
	
	-- Get the groups which can reach a node group
	local affectedGroups = {}
	for _, nodes in pairs(nodeGroups) do
		for _, link in pairs(map.links) do
			if nodes[link.nodeId] and not affectedGroups[link.group] then
				affectedGroups[link.group] = link
			end
		end
	end
	

	-- Update the nodesX and nodesZ
	local nodesX, nodesZ = CollisionGrid.combineGroups(map._groupChangesX, map._groupChangesZ, table.unpack(map.maps))
	for gid, g in pairs(nodesX) do
		map.nodesX[gid] = g
	end
	for gid, g in pairs(nodesZ) do
		map.nodesZ[gid] = g
	end

	-- Update the groups (make new ones if needed)
	local goals = {}
	local queue = {}
	for _, link in pairs(map.links) do
		table.insert(goals, link.pos)
	end
	for _, link in pairs(affectedGroups) do
		-- Reset their _linkCosts cache
		iterateLinks(link, function(link: RoomLink)
			link._linkCosts = {}
			queue[link] = true
			removeLink(linker, link)
			link.group = nil :: any -- HttpService:GenerateGUID(false)
		end)
	end
	-- Update the groups
	local pLink = next(queue)
	while pLink do
		-- Remove from queue
		queue[pLink] = nil
		pLink.group = HttpService:GenerateGUID(false)
		-- Find other links in the group
		local _, data = AStarJPS.findReachable(map.gridSize, pLink.pos, goals, false, map.nodesX, map.nodesZ)
		if data then
			for goalId in pairs(data.goalsReached) do
				local links = map.linksByNodeId[goalId]
				if links then
					for linkId in pairs(links) do
						if linkId == pLink.linkId then
							continue
						end
						local link = map.links[linkId]
						-- Remove from queue
						queue[link] = nil
						link._linkCosts[pLink] = data.g[goalId]
						-- Add link to pLink group
						addLink(linker, link, pLink)
					end
				end
			end
		end
		--
		pLink = next(queue)
	end

	map._groupChangesX = {}
	map._groupChangesZ = {}
end

local function scheduleMapUpdate(linker, map: RoomLinkCollisionMap): ()
	map._updateScheduled = true
end

local function onMapChanged(linker, map: RoomLinkCollisionMap, nodes: {Vector2}, addedCollisions: boolean): ()
	-- 1. Get group ids of node groups that changed
	local groupsX, groupsZ = {}, {}
	for _, node in ipairs(nodes) do
		local groupX = CollisionGrid.GetGroupId(map.gridSize.Y, node.X, node.Y)
		local groupZ = CollisionGrid.GetGroupId(map.gridSize.X, node.Y, node.X)
		groupsX[groupX] = true
		groupsZ[groupZ] = true
	end
	-- 2. Combine the groups from each map together
	local nodesX, nodesZ = CollisionGrid.combineGroups(groupsX, groupsZ, table.unpack(map.maps))

	-- 3. Save the changes to be processed when the map updates
	local changed = false
	local _nodesX, _nodesZ = map.nodesX, map.nodesZ

	for groupId in pairs(groupsX) do
		local _group = bit32.bxor(_nodesX[groupId] or 0, nodesX[groupId] or 0)
		if _group ~= 0 then
			changed = true
			local _other = map._groupChangesX[groupId]
			if _other then
				map._groupChangesX[groupId] = bit32.bor(_other, _group)
			else
				map._groupChangesX[groupId] = _group
			end
		end
	end
	for groupId in pairs(groupsZ) do
		local _group = bit32.bxor(_nodesZ[groupId] or 0, nodesZ[groupId] or 0)
		if _group ~= 0 then
			changed = true
			local _other = map._groupChangesZ[groupId]
			if _other then
				map._groupChangesZ[groupId] = bit32.bor(_other, _group)
			else
				map._groupChangesZ[groupId] = _group
			end
		end
	end
	-- 4. Schedule map update
	if changed then
		scheduleMapUpdate(linker, map)
	end
end


local Linker = {}
Linker.__index = Linker

function Linker.new()
	local self = setmetatable({}, Linker)

	self._maps = {} :: {[string]: RoomLinkCollisionMap} -- mapName -> RoomLinkCollisionMap
	
	return self
end

function Linker:Destroy(): ()
	for map in pairs(self._maps) do
		self:RemoveMap(map)
	end
end

function Linker:AddMap(mapName: string, gridSize: Vector2, ...: CollisionMap): ()
	if self._maps[mapName] then
		error(`Map '{mapName}' already exists`)
	end
	local nodesX, nodesZ = CollisionGrid.combineMaps(...)
	local connections = {}
	local maps = {...}
	if #maps == 0 then
		error('No maps')
	else
		for _, map in ipairs(maps) do
			if type(map) ~= "table" then
				error('Invalid map')
			end
		end
	end
	local map = {
		gridSize = gridSize,
		maps = maps,
		nodesX = nodesX,
		nodesZ = nodesZ,
		links = {}, -- {[string]: RoomLink}
		linksByNodeId = {}, -- {[nodeId]: {[string]: true}}
		_groupChangesX = {}, -- Keeps track of the groups that changed due to added or removed collisions
		_groupChangesZ = {}, -- Keeps track of the groups that changed due to added or removed collisions
		_connections = connections,
		_updateScheduled = false,
	}
	self._maps[mapName] = map

	for mapName, _map in ipairs(maps) do
		local colMap = _map[CollisionGrid.OBJECT_TYPE.Collision]
		local negMap = _map[CollisionGrid.OBJECT_TYPE.Negation]
		local colConn = colMap.OnChanged:Connect(function(nodes: {Vector2}, added: boolean)
			onMapChanged(self, map, nodes, added)
		end)
		local negConn = negMap.OnChanged:Connect(function(nodes: {Vector2}, added: boolean)
			onMapChanged(self, map, nodes, not added)
		end)
		table.insert(connections, colConn)
		table.insert(connections, negConn)
	end
end

function Linker:RemoveMap(map: string): ()
	local _map = self._maps[map]
	self._maps[map] = nil
	-- Stop map update thread
	if _map._updateScheduled then
		coroutine.close(_map._updateScheduled)
	end
	-- Disconnect connections
	for _, conn in ipairs(_map._connections) do
		conn:Disconnect()
	end
	-- Remove links
	for _, link: RoomLink in pairs(_map.links) do
		-- Remove other link from the other map
		local toMap = link.toMap
		if toMap ~= map then
			local _toMap = self:GetMap(toMap)
			if _toMap then
				removeMapLink(self, _toMap, self:_GetOtherLink(link))
			end
		end
		--
	end
end

function Linker:GetMap(map: string): CollisionGridList?
	return self._maps[map]
end

function Linker:_GetOtherLink(link: RoomLink): RoomLink
	local mapName = link.toMap
	local key = `{link.id}_{getOtherLinkNum(link.num)}`
	local map = self:GetMap(mapName)
	return map.links[key]
end

function Linker:FindLinkFromPos(map: string, pos: Vector2): RoomLink?
	local _map = self:GetMap(map)
	-- Update map
	triggerMapUpdate(self, _map)
	-- Find link group
	local nodeId = NodeUtil.getNodeId(_map.gridSize.X, pos.X, pos.Y)
	local linksByNodeId = _map.linksByNodeId[nodeId]
	-- Check if there are links at the same node
	if linksByNodeId then
		local linkId = next(linksByNodeId)
		return _map.links[linkId]
	end
	-- Otherwise find a link that is reachable from the node
	return findLink(self, _map, pos)
end

do
	local _linkNum = -1
	local function getLinkNum(): number
		_linkNum += 1
		return _linkNum % 2
	end
	function Linker:_AddLink(id: string, cost: number, fromPos: Vector2, fromMap: string, toMap: string): RoomLink?
		local map = self:GetMap(fromMap)
		if not map then
			error(`Map '{fromMap}' does not exist`)
		end
		if not GridUtil.isInGrid(map.gridSize.X, map.gridSize.Y, fromPos.X, fromPos.Y) then
			warn('fromPos is not in grid')
			return
		end
		-- Update map
		triggerMapUpdate(self, map)
		--
		fromPos = Vector2Util.floor(fromPos)
		-- Create link
		local num = getLinkNum()
		local link = newLink(self, id, num, cost, fromPos, fromMap, toMap)
		-- Find link group
		local linkGroup: RoomLink = self:FindLinkFromPos(fromMap, fromPos)
		-- Add link to link group
		if linkGroup ~= nil then
			addLink(self, link, linkGroup)
		end
		-- Add link to map
		local nodeId = NodeUtil.getNodeId(map.gridSize.X, fromPos.X, fromPos.Y)
		local linksByNodeId = map.linksByNodeId[nodeId]
		local key = `{id}_{num}`
		map.links[key] = link
		if linksByNodeId then
			linksByNodeId[key] = true
		else
			map.linksByNodeId[nodeId] = {
				[key] = true,
			}
		end
		return link
	end
end

function Linker:AddLink(id: string, cost: number, fromPos: Vector2, toPos: Vector2, fromMap: string, toMap: string?): ()
	assert(cost, 'Cost must be a number')
	fromPos = Vector2Util.floor(fromPos)
	toPos = Vector2Util.floor(toPos)
	toMap = toMap or fromMap
	--
	local linkA = self:_AddLink(id, cost, fromPos, fromMap, toMap)
	if not linkA then
		return
	end
	local linkB = self:_AddLink(id, cost, toPos, toMap, fromMap)
	if not linkB then
		removeLink(self, linkA)
		return
	end
end

function Linker:RemoveLink(id: string): ()
	for _, key in ipairs(getLinkKeys(id)) do
		for _, map in pairs(self._maps) do
			if map.links[key] then
				removeMapLink(self, map, map.links[key])
			end
		end
	end
end

function Linker:_FindLinkPath(fromPos: Vector2, toPos: Vector2, fromMap: string, toMap: string?): (RoomLink?, {[RoomLink]: RoomLink}?)
	--
	local startLink = self:FindLinkFromPos(fromMap, fromPos) -- Triggers a map update
	local goalLink = self:FindLinkFromPos(toMap, toPos)
	-- Return if link is in goalGroup
	if not startLink or not goalLink then
		return
	end
	if startLink.group == goalLink.group then
		return startLink
	end
	
	local goalGroup = goalLink.group

	local queue = {startLink} -- {RoomLink}
	local parents = {}
	local closed = {} -- [RoomLink]: true

	local function addParent(t, child, parent): ()
		if t[child] then
			t[child][parent] = true
		else
			t[child] = {
				[parent] = true
			}
		end
	end

	--[[
		STEP #1

		Trace all possible link paths and save children
	]]
	local lastChildren = {}
	while #queue > 0 do
		local groupLink = table.remove(queue, 1)
		iterateLinks(groupLink, function(parentLink: RoomLink)
			if closed[parentLink] then
				return
			end

			-- Update parentLink
			if groupLink ~= startLink then
				addParent(parents, parentLink, groupLink)
			end

			-- Get link that parentLink leads to
			local nextLink = self:_GetOtherLink(parentLink)
			-- Return if nextLink is closed or in the same group as its parent
			if closed[nextLink] or nextLink.group == parentLink.group then
				return
			end
			closed[nextLink] = true

			-- Add parentLink to nextLink
			addParent(parents, nextLink, parentLink)

			-- Insert nextLink in finalLinks if it is in the goal group
			if nextLink.group == goalGroup then
				table.insert(lastChildren, nextLink)
				return
			end

			-- Update nextLink parents
			table.insert(queue, nextLink)
		end)
	end


	--[[
		STEP #2

		Trace back the children that lead to the goal group
	]]
	closed = {}
	queue = {}
	local gTable = {} -- [RoomLink]: number
	local children = {}
	while #lastChildren > 0 do
		local child = table.remove(lastChildren, 1)
		local _parents = parents[child]
		if not _parents then
			continue
		end
		for parent in pairs(_parents) do
			addParent(children, parent, child)
			if not parents[parent] then
				-- Only add to queue if link has no children (i.e. is a start link)
				table.insert(queue, parent)
				gTable[parent] = 0
			end
			if closed[parent] then continue end
			closed[parent] = true
			table.insert(lastChildren, parent)
		end
	end
	if next(gTable) == nil then
		return
	end
	_setLinkCosts(self, fromPos, gTable) -- Set first links' costs


	--[[
		STEP #3

		Find the best link path
	]]
	closed = {}
	parents = {} -- [link]: link
	local finalLinks: {[RoomLink]: number} = {}
	while #queue > 0 do
		local groupLink = table.remove(queue, 1)
		local map = self:GetMap(groupLink.map)
		local costs
		if groupLink ~= startLink and children[groupLink] then
			costs = {
				[groupLink] = 0,
			}
			local goals = {groupLink.pos}
			-- Get goals
			iterateLinks(groupLink, function(link: RoomLink)
				-- if link == groupLink then return end
				if link._linkCosts[groupLink] then
					costs[link] = link._linkCosts[groupLink]
				elseif children[groupLink][link] then
					table.insert(goals, link.pos)
				end
			end)
			-- Find goals
			if #goals > 1 then
				local _, data = AStarJPS.findReachable(map.gridSize, groupLink.pos, goals, false, map.nodesX, map.nodesZ)
				iterateLinks(groupLink, function(link: RoomLink)
					if not costs[link] and (link == groupLink or children[groupLink][link]) then
						costs[link] = data.g[link.nodeId]
						link._linkCosts[groupLink] = costs[link]
					end
				end)
			end
		else
			costs = gTable
		end
		iterateLinks(groupLink, function(parentLink: RoomLink)
			if not children[parentLink] or not costs[parentLink] or closed[parentLink] then
				return
			end

			-- Update parentLink
			local _g
			if groupLink ~= startLink then
				_g = gTable[groupLink] + costs[parentLink]
				if _g < (gTable[parentLink] or math.huge) then
					parents[parentLink] = groupLink
					gTable[parentLink] = _g
				end
			else
				_g = costs[parentLink]
			end

			-- Get link that parentLink leads to
			local nextLink = self:_GetOtherLink(parentLink)
			-- Return if nextLink is not in parentLink's children, is closed or in the same group as its parent
			if not children[parentLink][nextLink] or closed[nextLink] or nextLink.group == parentLink.group then
				return
			end
			closed[nextLink] = true

			-- Add parentLink to nextLink
			parents[nextLink] = parentLink
			gTable[nextLink] = _g + parentLink.cost

			-- Insert nextLink in finalLinks if it is in the goal group
			if nextLink.group == goalGroup then
				finalLinks[nextLink] = 0
				return
			end

			-- Update nextLink parents
			table.insert(queue, nextLink)
		end)
	end




	--[[
		STEP #4

		Find the best goal link to use
	]]
	if not next(finalLinks) then
		return
	end
	_setLinkCosts(self, toPos, finalLinks)
	local lowestG: number = math.huge
	local finalLink: RoomLink
	for link, cost in pairs(finalLinks) do
		local g = gTable[link] + cost
		if not finalLink or g < lowestG then
			finalLink = link
			lowestG = g
		end
	end

	return finalLink, parents
end

--[=[
	@method FindLinkPath
	@within Linker

	Tries to find the best path of links to get from fromPos on fromMap to toPos on toMap.
	If toMap = nil, fromMap is used.

	This function returns isReachable boolean as well as the path. The reason for the isReachable
	boolean is because the path will be empty if the goal position is in the same room as the start position.
	i.e. No links are needed to get to the goal position.

	@param fromPos Vector2 -- The position to start from
	@param toPos Vector2 -- The position to end at
	@param fromMap string -- The map to start from
	@param toMap string? -- The map to end at. If nil, fromMap is used.
	@return (boolean, LinkPath) -- (isReachable, path)
]=]
function Linker:FindLinkPath(fromPos: Vector2, toPos: Vector2, fromMap: string, toMap: string?): (boolean, LinkPath)
	fromPos = Vector2Util.floor(fromPos)
	toPos = Vector2Util.floor(toPos)
	if not toMap then
		toMap = fromMap
	end
	local _fromMap = self:GetMap(fromMap)
	local _toMap = self:GetMap(toMap)
	if not _fromMap then
		error(`Map '{fromMap}' does not exist`)
	end
	if not _toMap then
		error(`Map '{toMap}' does not exist`)
	end
	if not GridUtil.isInGrid(_fromMap.gridSize.X, _fromMap.gridSize.Y, fromPos.X, fromPos.Y) then
		return false, {}
	end
	if not GridUtil.isInGrid(_toMap.gridSize.X, _toMap.gridSize.Y, toPos.X, toPos.Y) then
		return false, {}
	end
	-- Check if one of the maps has no links
	if next(_fromMap.links) == nil or next(_toMap.links) == nil then
		return true, {} -- Return true because it may still have a path
	end
	-- Find all possible paths
	local goalLink, parents = self:_FindLinkPath(fromPos, toPos, fromMap, toMap)
	if not goalLink then
		return false, {}
	end
	local path = {}

	if parents then
		local current = goalLink
		while current do
			table.insert(path, current)
			current = parents[current]
		end
	end
	return true, path
end

type RoomLink = {
	id: string,
	num: number,
	cost: number,
	pos: Vector2,
	nodeId: number,
	map: string,
	toMap: string,
	group: string,
	_groupLinks: {[RoomLink]: true}?,

	-- caches
	_linkCosts: {[RoomLink]: number},
}
type MapGroupLink = {
	id: string,
	fromPos: Vector2,
	toPos: Vector2,
	fromMap: string,
	toMap: string,
}
type RoomLinkCollisionMap = {
	gridSize: Vector2,
	maps: {CollisionMap},
	nodesX: {number},
	nodesZ: {number},
	links: {[string]: RoomLink},
	linksByNodeId: {[number]: {[string]: true}},
	_groupChangesX: {[number]: number},
	_groupChangesZ: {[number]: number},
	_connections: {RBXScriptConnection},
	_updateScheduled: boolean,
}
export type LinkPath = {RoomLink}
export type Linker = typeof(Linker.new(...))
return Linker