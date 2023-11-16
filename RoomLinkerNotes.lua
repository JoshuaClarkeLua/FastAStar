--[[
	:AddLink(fromPos: Vector2, toPos: Vector2, fromMapList: CollisionGridList, toMap: CollisionGridList?)
		- Forms a link with nodes located at fromPos and toPos.
		- fromMap is the map that the fromPos node is located in.
		- toMap is the map that the toPos node is located in. If nil, fromMap is used.

	:AddRoom(pos: Vector2, map: CollisionGridList)
		- Forms a room with the node located at pos.
		- map is the map that the pos node is located in.
]]


--[[
	Option 2
	- No rooms

	If goal is on the same map as start:
	1. Try find path from start to goal.
	1.1. If path found, return path.
	2. If path not found, iterate through each link on the map to find a link that reaches the goal.
	2.1. If no link reaches the goal, there is no valid path.
	3. If link is found, trace back using other links that are connected directly or indirectly to the link that reaches the goal.

	NOTE:
	- For the links to work with different maps for diff. types of NPCs, they must be added multiple times with the different map types.
	e.g. If a link needs to work with Dog and Human NPCs:
	-- Add link for dog maps
	:AddLink(fromPos, toPos, fromDogMap, toDogMap)
	-- Add link for human maps
	:AddLink(fromPos, toPos, fromHumanMap, toHumanMap)


	Storing paths to handle going from link to link:
	- Do not store the path, only store the distance from link to other link if it's reachable from that start link.


	To handle map changes:
	- Iterate over each link that has no valid path to see if it now has a path. 
	- Iterate over each of the cached paths and check if the path is still valid (no nodes are blocked).
		Pros:
			- No need to recalculate the path every time something changes.
		Cons:
			- May no longer be the shortest path.



	Notes:
	PATHFIND APPROACH:
	- When collision nodes change, send the list of nodes that changed to the RoomLinker module and whether collisions were added or removed. The module needs to find which *CHANGED* nodes are connected together and form a node group.
		--
		- IMPORTANT: If a link group has only 1 link, and the change added collisions, ignore the change.
		--
		- For each group of inter-connected nodes, check if there are any link groups that can reach one of the nodes in the node group. Do this by checking if the link group's main link can reach at least one of the nodes (main node) per node group.
			- If it can't reach, ignore that link group.
		- If it reaches a node group,
			- If the change added collisions, 
				- Check if each of the links in the link group can still reach each other link. 
					- If they can't reach, remove the link from the group, and put it in its own group. (Split the links into separate groups accordingly)
			- If the change removed collisions, add it to a list of link groups that can reach the node group.
				- Once all link groups have checked each node group and added to the list, connect link groups that can reach the same node group.
	- If I remove a collision, I only need to check one link of each link group to see if it can form a new connection with other link groups.
	- If I add a collision, I only need to check links within each group to see if they can still be connected together as a group.

	- Batch updates to the collision grid together so that the RoomLinker module can process changes in the same frame all at once.


	ROOMS APPROACH:
	If we have rooms, we can find which rooms are directly touching a group of changed nodes. We can then find the nodes that touch the group of changed nodes from each room.

	If the change removed collisions:
		We only need to check if rooms were connected together (it's impossible for a room to be separated if we only removed collisions)
		When finding all rooms that touch a node group, if a node group has multiple rooms touching it, we can assume the rooms are now connected together.
	If the change added collisions:
		We only need to check if rooms were separated (it's impossible for a room to be connected if we only added collisions)
		Cache in which groups collisions were added.
		Wait until next frame, and pathfind from each link to each other link to find which links can still reach each other.
		Change rooms accordingly


	EDGES APPROACH (TAKES TOO LONG):
	- Same as rooms, except we also save lists of the edges within a room.
	- Rooms can have multiple edges (imagine a room with walls in the middle)
	- Edge node = node with a collidable node next to it



	RoomLinker (IMPORTANT):
	- :AddMap() used to add a map to the RoomLinker. A map can be a combination of collision maps.
	- When any of the CollisionMaps update, something (external) needs to update the maps in the RoomLinker 
		accordingly. This means *keep track* of which CollisionMaps are combine with which RoomLinker maps.
		That way we can do the proper updates on the RoomLinker.
	- Add a function to update the node groups stored in the RoomLinker.
		```lua
		--[=[
			@param mapName string -- The name of the RoomLinker map to update
			@param addCollisions boolean -- Whether the update added collisions or removed collisions
			@param nodes {number} -- The list of nodes that changed
			@param ... CollisionMap -- The list of CollisionMaps that should be used to update the RoomLinker map
		]=]
		-- NOTE: use the maps OnChanged signal to do this
		RoomLinker:UpdateMap(mapName: string, addCollisions: boolean, nodes: {number}, ...: CollisionMap)
		-- 1. Get all the group ids that are affected by this change (by iterating over the nodes)
		-- 2. Combine the groups from each CollisionMap
		-- 3. Get the groups of inter-connected nodes where the change occured
		-- 4. Check the rooms that can reach the node groups
		-- If change removed collisions:
			-- 1. Check if 2 or more rooms reach the same node group. If so, connect those rooms together into one.
			-- 2. Update the room edges
		-- If change added collisions:
			-- 1. Wait next frame (so we don't do this multiple times on same frame), iterate through all links in room, check which ones are disconnected.
			-- 2. Create new rooms from the disconnected links (if multiple links are in same room, put them together)
			-- 3. Update the edges of the rooms that were split
		```



	NOTE: It takes .08s to flood the whole plot to find the edges if there are no collisions.
		- That is way to slow to do every time a collision is added or removed.
		- Pathfinding takes .0005 to .001s to find a path across the whole plot.

	IDEA: Allow the AStarJPS module to pathfind for multiple paths at once. Do not stop recursion until all possible paths are found
		OR there are no more nodes in the queue (i.e. natural stop)

	WELP throwing the whole room idea away. Will use a different approach. I will basically 
	pathfind from each change to figure out which links (staircases) are connected together. 
	And I will implement a function that allows me to pathfind multiple paths at the same time 
		in my pathfinding module so that I don't need to re-scan the same areas multiple times.

	- When collision added, check if it is on a path. If so, recalculate that
	path. If that path no longer valid, remove.
	- Function to pathfind the first goal out of a list of goals
	- Function to pathfind multiple goals at same time

	When scanning multiple paths, if goal is found, never return.
	Always just add its path to list of paths and continue like normal.
	Also remove the heuristic (f) because there are multiple goals.

	Ignore finding fastest path when pathfinding multiple paths. Just need to know if goals
	are reachable or not.
	Same thing with pathfinding *until* a goal is found. Use this to find the group of links a position is
	able to reach. (they are all connected so reaching one will tell us the others)

	If you need to find the fastest path, just pathfind to each goal found after.

	To find connected groups when object removed, use multi-pathfinding to find all links
	affected by the change. Then if there are multiple groups, pathfind from each leader to
	each other leader to find the connected groups.
]]