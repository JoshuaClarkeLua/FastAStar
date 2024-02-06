local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Promise = require(ReplicatedStorage.Packages.Promise)
local AStarJPS = require(script.Parent.AStarJPS)
local CollisionGrid = require(script.Parent.CollisionGrid)
local Linker = require(script.Parent.Linker)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Trove = require(ReplicatedStorage.Packages.Trove)

type CollisionGrid = CollisionGrid.CollisionGrid
type CollisionGridList = CollisionGrid.CollisionGridList
type CollisionMap = CollisionGrid.CollisionMap
type Linker = Linker.Linker
type LinkPath = Linker.LinkPath
type RoomLink = Linker.RoomLink

local function plotLine(x0, y0, x1, y1)
	x0 = math.round(x0)
	y0 = math.round(y0)
	x1 = math.round(x1)
	y1 = math.round(y1)
	if x0 == x1 and y0 == y1 then
		return { Vector2.new(x0, y0) }
	end
	local dx = math.abs(x1 - x0)
	local dy = -math.abs(y1 - y0)
	local sx = x0 < x1 and 1 or -1
	local sy = y0 < y1 and 1 or -1
	local err = dx + dy

	local points = {}
	while true do
		table.insert(points, Vector2.new(x0, y0))
		if x0 == x1 and y0 == y1 then
			break
		end
		local e2 = err * 2
		if e2 >= dy then
			if x0 == x1 then
				break
			end
			err = err + dy
			x0 = x0 + sx
		end
		if e2 <= dx then
			if y0 == y1 then
				break
			end
			err = err + dx
			y0 = y0 + sy
		end
	end
	return points
end

local function forceNoDiagonal(points: { Vector2 }, padding: boolean?): { Vector2 }
	local i = 1
	while i < #points do
		local node = points[i]
		i += 1
		local next = points[i]
		if node.X ~= next.X and node.Y ~= next.Y then
			local x, y = next.X, node.Y
			table.insert(points, i, Vector2.new(x, y))
			if padding then
				i += 1
				x, y = node.X, next.Y
				table.insert(points, i, Vector2.new(x, y))
			end
		end
	end
	return points
end

local Path = {}
Path.__index = Path
Path.__tostring = function(self)
	local waypoints = self:GetWaypoints()
	local wps = `Path has {#waypoints} waypoints:\n`
	for _, waypoint in ipairs(waypoints) do
		wps ..= `\nPosition: {waypoint.Position};`
		if waypoint.Link then
			wps ..= `Link: {waypoint.Link:GetAttribute("Id")}; Label: {waypoint.Link.Label};`
		end
	end
	return wps
end

function Path.waypoint(
	position: Vector3,
	link: PathfindingLink?,
	label: string?,
	grid: CollisionGrid?,
	node: Vector2?
): Waypoint
	return {
		Position = position,
		Link = link,
		Label = label,
		_grid = grid,
		_node = node,
	}
end

function Path.new(linker: Linker, collisionGrids: { CollisionGrid }, labels: { string })
	local grids = {}
	for _, grid in pairs(collisionGrids) do
		grids[grid] = grid
	end
	local _labels = {}
	for _, label in pairs(labels) do
		_labels[label] = label
	end
	local trove = Trove.new()
	local self = setmetatable({
		trove = trove,
		_blockTrove = trove:Add(Trove.new()),
		--
		Start = nil :: Vector3?,
		Goal = nil :: Vector3?,
		IsBlocked = false,
		NoPath = true,
		--
		OnBlocked = trove:Add(Signal.new()),
		--
		_linker = linker,
		_grids = grids,
		_labels = labels,
		_labelDict = _labels,
		_mapName = Linker.GetMapName(labels),
		_waypoints = nil :: { Waypoint }?,
		_destroyed = false,
	}, Path)

	return self
end

function Path:_getGridFromPos(pos: Vector3): CollisionGrid?
	return CollisionGrid.GetGridFromPos(self._grids, pos)
end

function Path:_pauseGrids(callback: () -> ()): Promise
	local promises = {}
	local pausedGrids = {}
	for _, grid in pairs(self._grids) do
		table.insert(
			promises,
			Promise.try(function()
				-- Wait to resume (allows the map to be updated)
				grid:WaitForResume()
				-- Pauses the grid after the map has been updated
				grid:PauseAsync()
				table.insert(pausedGrids, grid)
			end)
		)
	end
	return Promise.all(promises):andThenCall(callback):finally(function()
		promises = {}
		for _, grid in ipairs(pausedGrids) do
			-- Resume the grid updates
			table.insert(promises, Promise.try(grid.ResumeAsync, grid))
		end
		return Promise.all(promises)
	end)
end

function Path:_listenForBlocked(): ()
	-- Clear block trove
	local trove = self._blockTrove
	trove:Destroy()

	-- Reconstruct the path per-grid to be able to check if it gets blocked
	local waypoints = self:GetWaypoints()
	if #waypoints == 0 then
		return
	end

	local linker = self._linker
	local _gridNodes = {}
	local _links = {}
	for i, waypoint in pairs(waypoints) do
		-- Add link to links list
		local link = waypoint.Link
		if link then
			_links[link] = true
		end
		--
		local grid = waypoint._grid
		local node = waypoint._node
		local next = waypoints[i + 1]
		if not next then
			break
		elseif next._grid ~= grid then
			continue
		end
		next = next._node
		-- Get line of points between the two nodes
		local points = plotLine(node.X, node.Y, next.X, next.Y)
		-- Remove diagonal movement from the line (staircase pattern)
		points = forceNoDiagonal(points, true)
		-- Add the points to the grid's list of nodes
		local gridNodes = _gridNodes[grid]
		if not gridNodes then
			gridNodes = {
				[grid] = {},
			}
			_gridNodes[grid] = gridNodes
		end
		for _, point in ipairs(points) do
			local zT = gridNodes[point.X]
			if zT then
				zT[point.Y] = true
			else
				gridNodes[point.X] = { [point.Y] = true }
			end
		end
	end

	local _checkScheduled = false
	local function scheduleFullCheck(grid: CollisionGrid): ()
		if _checkScheduled then
			return
		end
		_checkScheduled = true
		task.defer(function()
			if self._destroyed or self.IsBlocked then
				return
			end
			local nodes = _gridNodes[grid]
			if not nodes then
				return
			end
			local colX, _, colByDefault = grid:GetMaps(self._labels)
			for x, zT in pairs(nodes) do
				for z in pairs(zT) do
					if CollisionGrid.HasCollision(colX, grid:GetSize().Y, x, z, colByDefault) then
						self.IsBlocked = true
						self.OnBlocked:Fire()
						return
					end
				end
			end
			_checkScheduled = false
		end)
	end

	local function checkBlocked(grid: CollisionGrid, nodes: { [Vector2]: boolean }): boolean
		local gridSize = grid:GetSize()
		local nodeList = _gridNodes[grid]
		local nodesX = {}
		for node: Vector2, collisionAdded: boolean in pairs(nodes) do
			-- Return if a collision was not added
			if collisionAdded == false then
				continue
			end
			if nodeList[node.X] and nodeList[node.X][node.Y] then
				-- 1. Combine the node from each map
				local groupId = CollisionGrid.GetGroupId(gridSize.Y, node.X, node.Y)
				local maps = grid:GetMaps(self._labels)
				local colByDefault
				if not nodesX[groupId] then
					local _nodesX
					_nodesX, _, colByDefault = CollisionGrid.combineGroups({ [groupId] = true }, nil, maps)
					nodesX[groupId] = _nodesX[groupId]
				end
				-- 2. Check if the node has a collision after combining it from all maps
				if CollisionGrid.HasCollision(nodesX, gridSize.Y, node.X, node.Y, colByDefault) then
					return true
				end
			end
		end
		return false
	end
	for grid: CollisionGrid in pairs(_gridNodes) do
		local listeners = {
			trove:Add(grid:ObserveMaps(function(name, map)
				if self._labelDict[name] then
					scheduleFullCheck()
				end
			end)),
			trove:Add(grid.OnMapRemoved:Connect(function(name: string)
				if self._labelDict[name] then
					scheduleFullCheck()
				end
			end)),
			trove:Add(grid.OnMapChanged:Connect(function(name: string, nodes: { [Vector2]: boolean })
				if not self.IsBlocked and checkBlocked(grid, nodes) then
					self.IsBlocked = true
					self.OnBlocked:Fire()
				end
			end)),
		}
		local conn
		conn = grid.OnDestroy:ConnectOnce(function()
			for _, listener in pairs(listeners) do
				listener:Disconnect()
				trove:Remove(listener)
			end
			trove:Remove(conn)
			if not self.IsBlocked then
				self.IsBlocked = true
				self.OnBlocked:Fire()
			end
		end)
	end

	trove:Add(linker.OnLinkRemoved:Connect(function(_link)
		local link = _link.metadata.link
		if not link then
			error("Link metadata.link not found!")
		end
		if not self.IsBlocked and _links[link] then
			self.IsBlocked = true
			self.OnBlocked:Fire()
		end
	end))

	trove:Add(function()
		self.IsBlocked = false
	end)
end

function Path:Compute(start: Vector3, goal: Vector3): Promise
	assert(start, "Invalid argument #2: 'start' is nil")
	assert(goal, "Invalid argument #3: 'goal' is nil")
	if typeof(start) ~= "Vector3" then
		error("Invalid argument #2: expected Vector3, got" .. typeof(start))
	elseif typeof(goal) ~= "Vector3" then
		error("Invalid argument #3: expected Vector3, got" .. typeof(goal))
	end
	self.Goal = goal
	self.Start = start
	self.NoPath = true
	self._waypoints = nil

	-- Prevent grids from getting any further updates
	return self:_pauseGrids(function()
		-- Get grids
		local fromGrid = self:_getGridFromPos(start)
		local toGrid = self:_getGridFromPos(goal)
		local linker = self._linker
		if not fromGrid or not toGrid then
			return
		end

		--[[
			STEP #1

			Get positional data
		]]
		-- Normalize the positions
		local gridStart = fromGrid:ToGridSpace(start)
		local gridGoal = toGrid:ToGridSpace(goal)
		-- Get 2D position vectors
		local fromPos = Vector2.new(gridStart.X, gridStart.Z)
		local toPos = Vector2.new(gridGoal.X, gridGoal.Z)

		local wps: { Waypoint } = {}
		--[[
			STEP #2

			Attempt to find path if start and goal are in the same grid
		]]
		if fromGrid == toGrid then
			local maps = {}
			for _, label in ipairs(self._labels) do
				local map = fromGrid:GetMap(label)
				if map then
					table.insert(maps, map)
				end
			end
			local path = AStarJPS.findPath(fromGrid:GetSize(), fromPos, toPos, nil, CollisionGrid.combineMaps(maps))
			-- Convert all node Vector2s to Vector3s (if path found) and return
			if #path > 0 then
				for j, node in path do
					wps[j] =
						Path.waypoint(fromGrid:ToWorldSpace(Vector3.new(node.X, 0, node.Y)), nil, nil, fromGrid, node)
				end
			end
			--
		end

		if #wps == 0 then
			--[[
				STEP #3

				Attempt to get link path
			]]
			local linkPath = linker:FindLinkPath(self._labels, fromPos, toPos, fromGrid, toGrid)
			if #linkPath == 0 then
				return
			end

			--[[
				STEP #4

				Construct path from gridStart to gridGoal using link path (if any)
			]]
			if #linkPath > 1 then
				local lastPos = toPos
				for i = 1, #linkPath, 2 do
					-- Get link pair
					local linkB = linkPath[i]
					-- Get linkB positional data
					local grid: CollisionGrid = linkB.grid.grid
					if not self._grids[grid] then
						error(
							`Link '{linkB.id}' is located on a grid that was not passed to Path.new() grid list! All grids in the linker must be included in the list.`
						)
					end
					local map = linker:GetMapData(grid, self._mapName)
					-- Get path from lastPos to linkB
					local path =
						AStarJPS.findPath(grid:GetSize(), linkB.pos, lastPos, nil, map.colX, map.colZ, map.colByDefault)
					-- Return if no path found (should never happen)
					if #path == 0 then
						warn("Failed to find path to link.")
						return
					end
					-- Add path to wps (convert to Vector3's)
					for _, node in ipairs(path) do
						table.insert(
							wps,
							Path.waypoint(grid:ToWorldSpace(Vector3.new(node.X, 0, node.Y)), nil, nil, grid, node)
						)
					end
					-- Add linkB
					table.insert(
						wps,
						Path.waypoint(
							grid:ToWorldSpace(Vector3.new(linkB.pos.X, 0, linkB.pos.Y)),
							nil,
							nil,
							grid,
							linkB.pos
						)
					)

					-- Add linkA
					local linkA = linkPath[i + 1]
					local nextGrid = linkA.grid.grid
					table.insert(
						wps,
						Path.waypoint(
							nextGrid:ToWorldSpace(Vector3.new(linkA.pos.X, 0, linkA.pos.Y)),
							linkA.metadata.link,
							linkA.metadata.label,
							nextGrid,
							linkA.pos
						)
					)
					-- Set lastPos to linkA
					lastPos = linkA.pos
				end

				-- Get path from lastPos to gridGoal
				local map = linker:GetMapData(fromGrid, self._mapName)
				local path =
					AStarJPS.findPath(fromGrid:GetSize(), fromPos, lastPos, nil, map.colX, map.colZ, map.colByDefault)
				if #path == 0 then
					warn("Failed to find path to link.")
					return
				end
				for _, node in ipairs(path) do
					table.insert(
						wps,
						Path.waypoint(fromGrid:ToWorldSpace(Vector3.new(node.X, 0, node.Y)), nil, nil, fromGrid, node)
					)
				end
			end
		end

		if #wps > 0 then
			self.NoPath = false
			self._waypoints = wps
			self:_listenForBlocked()
		end
	end)
end

function Path:GetWaypoints(): { Waypoint }
	return self._waypoints or {}
end

function Path:Destroy(): Path
	self._destroyed = true
	self.trove:Destroy()
	return self
end

type Promise = typeof(Promise.new(...))
export type Waypoint = typeof(Path.waypoint(...))
export type Path = typeof(Path.new(...))
return Path
