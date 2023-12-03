local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)
local Trove = require(ReplicatedStorage.Packages.Trove)
local AStarJPS = require(script.Parent.AStarJPS)
local CollisionGrid = require(script.Parent.CollisionGrid)
local GridUtil = require(script.Parent.GridUtil)
local Imports = require(script.Parent.Imports)
local NodeUtil = require(script.Parent.NodeUtil)
local Vector2Util = Imports.Vector2Util

type CollisionMap = CollisionGrid.CollisionMap
type CollisionGrid = CollisionGrid.CollisionGrid

local function sortMaps(maps: {string}): ()
	table.sort(maps, function(a,b)
		return a < b
	end)
end

local function getGroup(mapName: string, link: RoomLink): {[RoomLink]: true}?
	local group = link._groups[mapName]
	return group and group ~= true and group or nil
end

local function hasSameGroup(mapName: string, linkA: RoomLink, linkB: RoomLink): boolean
	local gA = getGroup(mapName, linkA)
	local gB = getGroup(mapName, linkB)
	return linkA == linkB or (gA ~= nil and gA == gB)
end

local function getMapsName(maps: {string}, noSort: boolean?): string
	if not noSort then
		sortMaps(maps)
	end
	local name = ''
	for _, map in ipairs(maps) do
		name ..= map
	end
	return name
end

local function getMaps(grid: CollisionGrid, maps: {string}): {CollisionMap}
	local _maps = {}
	for _, map in ipairs(maps) do
		local _map = grid:GetMap(map)
		if not _map then
			error(`CollisionMap '{map}' does not exist`)
		end
		table.insert(_maps, _map)
	end
	return _maps
end

local function getMapData(grid: CollisionGrid, mapsName: {string}, noSort: boolean?): MapData
	local maps = getMaps(grid, mapsName)
	local colX, colZ, colByDefault = CollisionGrid.combineMaps(maps)
	return {
		name = getMapsName(mapsName, noSort),
		colX = colX,
		colZ = colZ,
		colByDefault = colByDefault,
	}
end

local function getLinkKey(link: RoomLink): string
	return `{link.id}_{link.num}`
end

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

local function ungroupLink(linker, link: RoomLink, mapName: string?): ()
	if mapName then
		local group = getGroup(mapName, link)
		if group then
			group[link] = nil
		end
		link._groups[mapName] = nil -- Still set to nil (getGroup returns nil if link._groups[mapName] == true)
	else
		for name, group in pairs(link._groups) do
			link._groups[name] = nil
			if group == true then
				continue
			end
			group[link] = nil
		end
	end
end

local function removeLink(linker, link: RoomLink): ()
	local key = getLinkKey(link)
	-- Remove link from Linker
	linker._links[key] = nil
	-- Remove link from grid
	local grid = link.grid
	-- Remove link from linkByNodeId list
	grid.linksByNodeId[link.nodeId][key] = nil
	if next(grid.linksByNodeId[link.nodeId]) then
		grid.linksByNodeId[link.nodeId] = nil
	end
	-- Remove link from map links
	grid.links[key] = nil
	-- Remove link from group
	ungroupLink(linker, link)
	-- Remove link cost cache
	for _, otherLink in pairs(grid.links) do
		if otherLink == link then continue end
		for _, cache in pairs(otherLink._linkCosts) do
			cache[otherLink] = nil
		end
	end
	-- Fire link removed event
	linker.OnLinkRemoved:Fire(link)
end


local function groupLinks(linker, mapName: string, link: RoomLink, prevLink: RoomLink): ()
	if link == prevLink then
		return
	end
	-- Delete group if no links are left
	local links = getGroup(mapName, prevLink)
	if not links then
		links = {
			[prevLink] = true,
			[link] = true,
		}
		prevLink._groups[mapName] = links
	else
		links[link] = true
	end
	--
	link._groups[mapName] = links
end

local function iterateLinks(mapName: string, firstLink: RoomLink, iterator: (link: RoomLink) -> ()): ()
	local group = getGroup(mapName, firstLink)
	if group ~= nil then
		for link in pairs(group) do
			iterator(link)
		end
	else
		iterator(firstLink)
	end
end

local function newLink(linker, id: string, num: number, cost: number, nodePos: Vector2, grid: GridData, toGrid: GridData, metadata: any): RoomLink
	local self = {
		id = id,
		num = num,
		key = `{id}_{num}`,
		cost = cost,
		metadata = metadata,
		--
		pos = nodePos,
		grid = grid,
		nodeId = CollisionGrid.GetNodeIdFromPos(grid.grid.Size, nodePos.X, nodePos.Y),
		toGrid = toGrid,
		_groups = {}, -- [mapsName]: {[RoomLink]: true} | true
		_linkCosts = {},
	}
	return self
end

local function findLink(grid: GridData, start: Vector2, map: MapData): RoomLink?
	local goals = {}
	for _, link in pairs(grid.links) do
		table.insert(goals, link.pos)
	end
	local reachedGoals = AStarJPS.findReachable(grid.grid.Size, start, goals, true, map.colX, map.colZ, map.colByDefault)
	if not reachedGoals or #reachedGoals == 0 then
		return
	end
	local goal = reachedGoals[1]
	local nodeId = NodeUtil.getNodeId(grid.grid.Size.Y, goal.X, goal.Y)
	local linkId = next(grid.linksByNodeId[nodeId])
	return grid.links[linkId]
end

local function _setLinkCosts(linker, pos: Vector2, links: {[RoomLink]: any}, map: MapData): ()
	local first: RoomLink? = next(links)
	if not first then
		error('No links')
	end
	local grid = first.grid
	-- Find the costs (distance) of each parent
	local goals = {}
	for parent in pairs(links) do
		table.insert(goals, parent.pos)
	end
	local _, data = AStarJPS.findReachable(grid.grid.Size, pos, goals, false, map.colX, map.colZ, map.colByDefault)
	if not data then
		return
	end
	-- Set link costs
	for _parent in pairs(links) do
		local cost = data.g[_parent.nodeId]
		links[_parent] = cost
	end
end

local function getChangedGroups(a: {[any]: any}, b: {[any]: any}, colByDefault): {[number]: any}
	local groups = {}
	for groupId,group in pairs(a) do
		local _group = CollisionGrid.GetGroup(b, groupId, CollisionGrid.OBJECT_TYPE.Collision, colByDefault)
		if group ~= _group then
			groups[groupId] = bit32.bxor(group, _group)
		end
	end
	for groupId,group in pairs(b) do
		if groups[groupId] then
			continue
		end
		local _group = CollisionGrid.GetGroup(a, groupId, CollisionGrid.OBJECT_TYPE.Collision, colByDefault)
		if group ~= _group then
			groups[groupId] = bit32.bxor(group, _group)
		end
	end
	return groups
end

local function triggerMapUpdate(linker, grid: GridData, map: MapData): boolean
	local old = grid._mapData[map.name]
	-- Return if map wasn't previously loaded
	if not old then
		return true
	end
	if map.colByDefault ~= old.colByDefault then
		-- Reset all link groups
		for _, link in pairs(grid.links) do
			link._groups[map.name] = nil
			link._linkCosts[map.name] = nil
		end
		-- Return, the next step in the resolveLinkGroups() function will update the groups
		return true
	end
	local groupChangesX, groupChangesZ = getChangedGroups(old.colX, map.colX, map.colByDefault), nil
	if next(groupChangesX) == nil then
		return false
	end
	groupChangesZ = getChangedGroups(old.colZ, map.colZ, map.colByDefault)
	local gridSize = grid.grid.Size
	

	-- 1. Remove collisions from the changed nodes
	local changedNodes = {}
	local _nodesX, _nodesZ = old.colX, old.colZ
	local overshoot = gridSize.X % 32
	overshoot = overshoot ~= 0 and 32 - overshoot or 0
	for groupId, group in pairs(groupChangesX) do
		-- Add node ids to changedNodes
		local _group = group
		-- Calculate the id of the first node in the group
		local baseNodeId = (groupId - 1) * 32 + 1
		if overshoot > 0 then -- Accounts for extra nodes at the end of the last group of each row
			local numGroups = math.ceil(gridSize.X / 32)
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
	for groupId, group in pairs(groupChangesZ) do
		if _nodesZ[groupId] ~= nil then
			local __group = bit32.band(_nodesZ[groupId] or 0, bit32.bnot(group))
			_nodesZ[groupId] = __group
		end
	end
	
	-- 2. Find the groups of connected nodes
	local nodeGroups = {}
	local nodeId = next(changedNodes)
	while nodeId ~= nil do
		local node = Vector2.new(NodeUtil.getPosFromId(gridSize.X, nodeId))
		changedNodes[nodeId] = nil
		local nodes = {[nodeId] = true}
		local data = AStarJPS.fill(gridSize, node, old.colX, old.colZ)
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
		for _, link in pairs(grid.links) do
			local group = getGroup(map.name, link)
			-- Node may not be in a group, add it anyways so that it can get processed
			if nodes[link.nodeId] and (not group or not affectedGroups[group]) then
				affectedGroups[group or link] = link
			end
		end
	end

	-- Update the groups (make new ones if needed)
	local goals = {}
	local queue = {}
	for _, link in pairs(grid.links) do
		table.insert(goals, link.pos)
	end
	for _, link in pairs(affectedGroups) do
		-- Reset their _linkCosts cache
		iterateLinks(map.name, link, function(link: RoomLink)
			-- clear cost cache
			link._linkCosts[map.name] = {}
			--
			queue[link] = true
			ungroupLink(linker, link, map.name)
			link._groups[map.name] = nil
		end)
	end
	-- Update the groups
	local pLink = next(queue)
	while pLink do
		-- Remove from queue
		queue[pLink] = nil
		-- Find other links in the group
		local _, data = AStarJPS.findReachable(gridSize, pLink.pos, goals, false, map.colX, map.colZ)
		if data then
			for goalId in pairs(data.goalsReached) do
				local links = grid.linksByNodeId[goalId]
				if links then
					for _, link in pairs(links) do
						if link == pLink then
							continue
						end
						-- Remove from queue
						queue[link] = nil
						-- cache cost
						link._linkCosts[map.name][pLink] = data.g[goalId]
						-- Add link to pLink group
						groupLinks(linker, map.name, link, pLink)
					end
				end
			end
		end
		--
		pLink = next(queue)
	end

	return true
end

local function getLinkCosts(linker, groupLink: RoomLink, mapName: string, children: {[RoomLink]: {[RoomLink]: any}}): {[RoomLink]: number}
	local grid = groupLink.grid
	-- Get CollisionMaps
	local map = linker:GetMapData(grid.grid, mapName, true)
	-- Get costs
	local costs = {
		[groupLink] = 0,
	}
	local goals = {groupLink.pos}
	-- Get goals
	iterateLinks(mapName, groupLink, function(link: RoomLink)
		-- cache costs
		local cache = link._linkCosts[mapName]
		if cache and cache[groupLink] then
			costs[link] = cache[groupLink]
		elseif children[groupLink][link] then
			table.insert(goals, link.pos)
		end
	end)
	-- Find goals
	if #goals > 1 then
		local _, data = AStarJPS.findReachable(grid.grid.Size, groupLink.pos, goals, false, map.colX, map.colZ, map.colByDefault)
		iterateLinks(mapName, groupLink, function(link: RoomLink)
			if not costs[link] and children[groupLink][link] then
				costs[link] = data.g[link.nodeId]
				-- cache costs
				local cache = link._linkCosts[mapName]
				if not cache then
					cache = {}
					link._linkCosts[mapName] = cache
				end
				cache[groupLink] = costs[link]
			end
		end)
	end
	return costs
end

local function resolveLinkGroups(self, grid: GridData, sortedMapNames: {string}): ()

	--[[
		STEP #1

		Resolve groups which may have been updated
	]]
	local map = getMapData(grid.grid, sortedMapNames, true)
	local changed = triggerMapUpdate(self, grid, map)

	if changed then
		grid._mapData[map.name] = map
	end

	--[[
		STEP #2

		Resolve all groups for links which have never been resolved on this map combination
	]]
	local goals: {Vector2}
	for _, link in pairs(grid.links) do
		if not link._groups[map.name] then
			link._groups[map.name] = true
			-- Create goals table if it doesn't exist
			if goals == nil then
				goals = {}
				for _, link in pairs(grid.links) do
					table.insert(goals, link.pos)
				end
			end
			-- Find all links this link can reach
			local _, data = AStarJPS.findReachable(grid.grid.Size, link.pos, goals, false, map.colX, map.colZ, map.colByDefault)
			local groupLink: RoomLink
			local ungroupedLinks = {}
			for nodeId in pairs(data.goalsReached) do
				local links = grid.linksByNodeId[nodeId]
				if links then
					for _, otherLink in pairs(links) do
						if otherLink == link then
							continue
						end
						if otherLink._groups[map.name] then
							if not groupLink then
								groupLink = otherLink
							end
						else
							otherLink._groups[map.name] = true
							table.insert(ungroupedLinks, otherLink)
						end
					end
				end
			end
			-- Group all the ungrouped links
			if groupLink ~= nil then
				table.insert(ungroupedLinks, link)
			else
				groupLink = link
			end
			for _, otherLink in pairs(ungroupedLinks) do
				groupLinks(self, map.name, otherLink, groupLink)
			end
		end
	end
end


local Linker = {}
Linker.__index = Linker

function Linker.new()
	local self = setmetatable({
		OnLinkRemoved = Signal.new(), -- (grid: CollisionGrid, link: RoomLink)
	}, Linker)

	self._grids = {} :: {[string]: GridData} -- mapName -> GridData
	self._links = {} :: {[string]: RoomLink} -- linkId -> RoomLink
	
	return self
end

function Linker:Destroy(): ()
	for _, grid in pairs(self._grids) do
		grid.trove:Destroy()
	end
end

function Linker:_AddGrid(grid: CollisionGrid): ()
	if self._grids[grid.Id] then
		error(`Grid '{grid.Id}' already exists!`)
	end
	local gridData = {
		trove = Trove.new(),
		grid = grid,
		links = {}, -- {[string]: RoomLink}
		linksByNodeId = {}, -- {[nodeId]: {[string]: true}}
		_mapData = {},
	}
	self._grids[grid.Id] = gridData
end

function Linker:_RemoveGrid(id: string): ()
	local data = self._grids[id]
	if not data then
		return
	end
	self._grids[id] = nil
end

function Linker:GetGridData(id: string): GridData?
	return self._grids[id]
end

function Linker:GetMapData(grid: CollisionGrid, mapName: string): MapData?
	local gridData = self:GetGridData(grid.Id)
	if not gridData then
		return
	end
	return gridData._mapData[mapName]
end

function Linker:_GetOtherLink(link: RoomLink): RoomLink
	local key = `{link.id}_{getOtherLinkNum(link.num)}`
	return self._links[key]
end

function Linker:_FindLinkFromPos(grid: CollisionGrid, pos: Vector2, map: MapData): RoomLink?
	local gridData = self:GetGridData(grid.Id)
	if not gridData then
		return
	end

	-- Find link group
	local nodeId = NodeUtil.getNodeId(grid.Size.X, pos.X, pos.Y)
	local linksByNodeId = gridData.linksByNodeId[nodeId]
	-- Check if there are links at the same node
	if linksByNodeId then
		local linkId = next(linksByNodeId)
		return gridData.links[linkId]
	end
	-- Otherwise find a link that is reachable from the node
	return findLink(gridData, pos, map)
end

do
	local _linkNum = -1
	local function getLinkNum(): number
		_linkNum += 1
		return _linkNum % 2
	end
	function Linker:_AddLink(id: string, cost: number, fromPos: Vector2, fromGrid: CollisionGrid, toGrid: CollisionGrid, metadata: any): RoomLink

		-- Create link
		local num = getLinkNum()
		local gridData = self:GetGridData(fromGrid.Id)
		local link = newLink(self, id, num, cost, fromPos, gridData, self:GetGridData(toGrid.Id), metadata)

		-- Add link to grid
		local nodeId = NodeUtil.getNodeId(fromGrid.Size.X, fromPos.X, fromPos.Y)
		local linksByNodeId = gridData.linksByNodeId[nodeId]
		local key = getLinkKey(link)
		self._links[key] = link
		gridData.links[key] = link
		if linksByNodeId then
			linksByNodeId[key] = link
		else
			gridData.linksByNodeId[nodeId] = {
				[key] = link,
			}
		end
		return link
	end
end

function Linker:AddLink(id: string, cost: number, fromPos: Vector2, toPos: Vector2, fromGrid: CollisionGrid, toGrid: CollisionGrid?, bidirectional: boolean?, metadata: any): ()
	assert(cost, 'Cost must be a number')
	assert(self._links[`{id}_0`] == nil, 'A Link with this id already exists')
	toGrid = toGrid or fromGrid
	if not GridUtil.isInGrid(fromGrid.Size.X, fromGrid.Size.Y, fromPos.X, fromPos.Y) then
		warn('fromPos is not in grid')
		return
	end
	if not GridUtil.isInGrid(toGrid.Size.X, toGrid.Size.Y, toPos.X, toPos.Y) then
		warn('toPos is not in grid')
		return
	end
	-- Add grids
	if not self:GetGridData(fromGrid.Id) then
		self:_AddGrid(fromGrid)
	end
	if toGrid ~= fromGrid and not self:GetGridData(toGrid.Id) then
		self:_AddGrid(toGrid)
	end
	fromPos = Vector2Util.floor(fromPos)
	toPos = Vector2Util.floor(toPos)
	bidirectional = bidirectional ~= false
	-- Add links
	self:_AddLink(id, cost, fromPos, fromGrid, toGrid, metadata)
	self:_AddLink(id, bidirectional and cost or math.huge, toPos, toGrid, fromGrid, metadata)
end

function Linker:RemoveLink(id: string): ()
	for _, key in pairs(getLinkKeys(id)) do
		removeLink(self, self._links[key])
	end
end

function Linker:_FindLinkPath(sortedMapNames: {string}, fromPos: Vector2, toPos: Vector2, fromGrid: GridData, toGrid: GridData): (RoomLink?, {[RoomLink]: RoomLink}?)
	local mapName = getMapsName(sortedMapNames, true)
	-- Resolve any unresolved link groups
	for _, gridData in pairs(self._grids) do
		resolveLinkGroups(self, gridData, sortedMapNames)
	end
	-- Get map data
	local fromMap = self:GetMapData(fromGrid.grid, mapName)
	local toMap = self:GetMapData(toGrid.grid, mapName)
	--
	local startLink = self:_FindLinkFromPos(fromGrid.grid, fromPos, fromMap) -- Triggers a map update
	local goalLink = self:_FindLinkFromPos(toGrid.grid, toPos, toMap)
	-- Return if link is in goalGroup
	if not startLink or not goalLink then
		return
	end
	if hasSameGroup(mapName, startLink, goalLink) then
		return startLink
	end
	

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

		Trace all possible link paths and save last children
	]]
	local lastChildren = {}
	while #queue > 0 do
		local groupLink = table.remove(queue, 1)
		iterateLinks(mapName, groupLink, function(parentLink: RoomLink)
			if closed[parentLink] or parentLink.cost == math.huge then
				return
			end

			-- Update parentLink
			if groupLink ~= startLink then
				addParent(parents, parentLink, groupLink)
			end

			-- Get link that parentLink leads to
			local nextLink = self:_GetOtherLink(parentLink)
			-- Return if nextLink is closed or in the same group as its parent
			if closed[nextLink] or hasSameGroup(mapName, nextLink, parentLink) then
				return
			end
			closed[nextLink] = true

			-- Add parentLink to nextLink
			addParent(parents, nextLink, parentLink)

			-- Insert nextLink in finalLinks if it is in the goal group
			if hasSameGroup(mapName, nextLink, goalLink) then
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
	local first = {}
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
				-- Only add to queue if link has no parents (i.e. is a start link)
				table.insert(queue, parent)
				first[parent] = true
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
	

	_setLinkCosts(self, fromPos, gTable, fromMap) -- Set first links' costs


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
		if not first[groupLink] and children[groupLink] then
			costs = getLinkCosts(self, groupLink, mapName, children)
			do
				local _costs = {}
				for link, cost in pairs(costs) do
					_costs[link.id] = cost
				end
			end
		else
			costs = gTable
		end
		iterateLinks(mapName, groupLink, function(parentLink: RoomLink)
			if closed[parentLink] or not children[parentLink] or not costs[parentLink] then
				return
			end

			-- Update parentLink
			local _g
			if parentLink ~= groupLink and not first[groupLink] then
				_g = gTable[groupLink] + costs[parentLink]
				if not gTable[parentLink] or _g < gTable[parentLink] then
					parents[parentLink] = groupLink
					gTable[parentLink] = _g
				end
			else
				_g = gTable[parentLink] or costs[parentLink]
			end

			-- Get link that parentLink leads to
			local nextLink = self:_GetOtherLink(parentLink)

			-- Return if nextLink is not in parentLink's children or in the same group as its parent
			if not children[parentLink][nextLink] or hasSameGroup(mapName, nextLink, parentLink) then
				return
			end

			-- Update nextLink parent if it is better
			if not gTable[nextLink] or _g + parentLink.cost < gTable[nextLink] then
				parents[nextLink] = parentLink
				gTable[nextLink] = _g + parentLink.cost
			end

			-- Return if nextLink was already added to the queue
			if closed[nextLink] then
				return
			end
			closed[nextLink] = true

			-- Insert nextLink in finalLinks if it is in the goal group
			if hasSameGroup(mapName, nextLink, goalLink) then
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
	_setLinkCosts(self, toPos, finalLinks, toMap)
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
function Linker:FindLinkPath(mapNames: {string}, fromPos: Vector2, toPos: Vector2, fromGrid: CollisionGrid, toGrid: CollisionGrid?): LinkPath
	fromPos = Vector2Util.floor(fromPos)
	toPos = Vector2Util.floor(toPos)
	if not toGrid then
		toGrid = fromGrid
	end
	if not GridUtil.isInGrid(fromGrid.Size.X, fromGrid.Size.Y, fromPos.X, fromPos.Y) then
		return {}
	end
	if not GridUtil.isInGrid(toGrid.Size.X, toGrid.Size.Y, toPos.X, toPos.Y) then
		return {}
	end
	local fromGridData = self:GetGridData(fromGrid.Id)
	local toGridData = self:GetGridData(toGrid.Id)
	-- Check if one of the maps has no links
	if not fromGridData or not toGridData or next(fromGridData.links) == nil or next(toGridData.links) == nil then
		return {} -- Return true because it may still have a path
	end
	-- Find all possible paths
	sortMaps(mapNames) -- sort the map names
	local goalLink, parents = self:_FindLinkPath(mapNames, fromPos, toPos, fromGridData, toGridData)
	if not goalLink then
		return {}
	end
	local path = {}

	if parents then
		local current = goalLink
		while current do
			table.insert(path, current)
			current = parents[current]
		end
	end
	return path
end

function Linker.GetMapName(labels: {string}): string
	return getMapsName(labels, true)
end

export type RoomLink = {
	id: string,
	num: number,
	key: string,
	metadata: any,
	cost: number,
	pos: Vector2,
	nodeId: number,
	grid: GridData,
	toGrid: GridData,
	_groups: {[string]: {[RoomLink]: true} | true}, -- map_combination_name -> true
	_linkCosts: {[string]: {[RoomLink]: number}},
}
type Signal = typeof(Signal.new(...))
type Trove = typeof(Trove.new(...))
export type GridData = {
	trove: Trove,
	grid: CollisionGrid,
	links: {[string]: RoomLink},
	linksByNodeId: {[number]: {[string]: true}},
	_mapData: {[string]: MapData}
}
export type LinkPath = {RoomLink}
export type Linker = typeof(Linker.new(...))
type MapData = typeof(getMapData(...))
return Linker