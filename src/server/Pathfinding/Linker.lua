local HttpService = game:GetService("HttpService")
local AStarJPS = require(script.Parent.AStarJPS)
local CollisionGrid = require(script.Parent.CollisionGrid)
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

local function addGroup(linker, group: string): ()
	linker._groups[group] = {
		[group] = 1,
	}
end

local function removeGroup(linker, group: string): ()
	if not linker._groups[group] then
		return
	end
	for _group in pairs(linker._groups[group]) do
		linker._groups[_group][group] = nil
	end
	linker._groups[group] = nil
end

local function removeLink(linker, link: RoomLink): ()
	-- Return if circular
	if link._next == link then
		-- Delete the group
		removeGroup(linker, link.group)
		return
	end
	if link._prev then
		link._prev._next = link._next
	end
	if link._next then
		link._next._prev = link._prev
	end
end

local function removeMapLink(linker, map: RoomLinkCollisionMap, link: RoomLink): ()
	-- Remove link from linkByNodeId list
	local nodeId = NodeUtil.getNodeId(linker._gridSize.X, link.pos.X, link.pos.Y)
	map.linksByNodeId[nodeId][link.id] = nil
	if next(map.linksByNodeId[nodeId]) then
		map.linksByNodeId[nodeId] = nil
	end
	-- Remove link from map links
	map.links[link.id] = nil
	-- Remove link from group
	removeLink(linker, link)
end


local function addLink(linker, link: RoomLink, prevLink: RoomLink): ()
	-- Delete group if no links are left
	if link._next == link then
		removeGroup(linker, link.group)
	end
	--
	link._prev = prevLink
	link._next = prevLink._next
	prevLink._next._prev = link
	prevLink._next = link
	-- Update group id
	link.group = prevLink.group
end

local function iterateLinks(firstLink: RoomLink, iterator: (link: RoomLink) -> ()): ()
	local link = firstLink
	repeat
		iterator(link)
		link = link._next
	until link == firstLink
end

local function newLink(linker, id: string, num: number, cost: number, nodePos: Vector2, map: string, toMap: string): RoomLink
	local self = {
		id = id,
		num = num,
		cost = cost,
		pos = nodePos,
		map = map,
		nodeId = NodeUtil.getNodeId(linker._gridSize.X, nodePos.X, nodePos.Y),
		toMap = toMap,
		group = HttpService:GenerateGUID(false),

		-- caches
		_linkCosts = {},
	}
	self._next = self
	self._prev = self
	addGroup(linker, self.group)
	return self
end

local function findLink(linker, map: RoomLinkCollisionMap, start: Vector2): RoomLink?
	local goals = {}
	for _, link in pairs(map.links) do
		table.insert(goals, link.pos)
	end
	local reachedGoals = AStarJPS.findReachable(linker._gridSize, start, goals, true, map.nodesX, map.nodesZ)
	if #reachedGoals == 0 then
		return
	end
	local goal = reachedGoals[1]
	local nodeId = NodeUtil.getNodeId(linker._gridSize.X, goal.X, goal.Y)
	local linkId = next(map.linksByNodeId[nodeId])
	return map.links[linkId]
end

local function setLinkCosts(linker, pos: Vector2, links: {[RoomLink]: any}): ()
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
	local _, data = AStarJPS.findReachable(linker._gridSize, pos, goals, false, map.nodesX, map.nodesZ)
	-- Set link costs
	for _parent in pairs(links) do
		local cost = data.g[_parent.nodeId]
		links[_parent] = cost
	end
end

local function getGroupLinkCosts(linker, pos: Vector2, link: RoomLink): {[RoomLink]: number}
	local costs = {}
	iterateLinks(link, function(link: RoomLink)
		costs[link] = 0
	end)
	setLinkCosts(linker, pos, costs)
	return costs
end


local Linker = {}
Linker.__index = Linker

function Linker.new(gridSize: Vector2)
	local self = setmetatable({}, Linker)

	self._gridSize = gridSize
	self._maps = {} :: {[string]: RoomLinkCollisionMap} -- mapName -> RoomLinkCollisionMap
	self._groups = {} :: {[string]: {[string]: true}} -- [group]: { [group]: isConnected }
	
	return self
end

function Linker:AddMap(mapName: string, ...: CollisionMap): ()
	if self._maps[mapName] then
		error(`Map '{mapName}' already exists`)
	end
	local nodesX, nodesZ = CollisionGrid.combineMaps(...)
	self._maps[mapName] = {
		maps = {...},
		nodesX = nodesX,
		nodesZ = nodesZ,
		links = {}, -- {[string]: RoomLink}
		linksByNodeId = {}, -- {[nodeId]: {[string]: true}}
	}
end

function Linker:RemoveMap(map: string): ()
	local _map = self._maps[map]
	self._maps[map] = nil
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
		removeGroup(self, link.group)
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
	-- Find link group
	local nodeId = NodeUtil.getNodeId(self._gridSize.X, pos.X, pos.Y)
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
	function Linker:_AddLink(id: string, cost: number, fromPos: Vector2, fromMap: string, toMap: string): ()
		local map = self:GetMap(fromMap)
		if not map then
			error(`Map '{fromMap}' does not exist`)
		end
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
		local nodeId = NodeUtil.getNodeId(self._gridSize.X, fromPos.X, fromPos.Y)
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
	toMap = toMap or fromMap
	--
	self:_AddLink(id, cost, fromPos, fromMap, toMap)
	self:_AddLink(id, cost, toPos, toMap, fromMap)
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
	if not toMap then
		toMap = fromMap
	end
	--
	local startLink = self:FindLinkFromPos(fromMap, fromPos)
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
			-- iterateLinks(child, function(link: RoomLink)
			-- 	-- Only add to queue if link has children
			-- 	table.insert(queue, link)
			-- 	gTable[link] = 0
			-- end)
			continue
		end
		for parent in pairs(_parents) do
			addParent(children, parent, child)
			if not parents[parent] then
				-- Only add to queue if link has children
				table.insert(queue, parent)
				gTable[parent] = 0
			end
			if closed[parent] then continue end
			closed[parent] = true
			table.insert(lastChildren, parent)
		end
	end
	setLinkCosts(self, fromPos, gTable) -- Set first links' costs


	--[[
		STEP #3

		Find the best link path
	]]
	closed = {}
	parents = {} -- [link]: link
	local finalLinks: {[RoomLink]: number} = {}
	while #queue > 0 do
		local groupLink = table.remove(queue, 1)
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
				local _, data = AStarJPS.findReachable(self._gridSize, groupLink.pos, goals, false, self:GetMap(groupLink.map).nodesX, self:GetMap(groupLink.map).nodesZ)
				iterateLinks(groupLink, function(link: RoomLink)
					if link == groupLink or children[groupLink][link] then
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
				-- table.insert(finalLinks, nextLink)
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
	setLinkCosts(self, toPos, finalLinks)
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
	toMap = toMap or fromMap
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
	_prev: RoomLink,
	_next: RoomLink,

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
	maps: {CollisionMap},
	nodesX: {number},
	nodesZ: {number},
	links: {[string]: RoomLink},
	linksByNodeId: {[string]: {[string]: true}},
}
export type LinkPath = {RoomLink}
-- export type LinkGroup = typeof(LinkGroup.new(...))
export type Linker = typeof(Linker.new(...))
return Linker