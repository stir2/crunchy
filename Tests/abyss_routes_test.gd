extends SceneTree
var failures: int = 0
var tested_rooms: int = 0
var branch_edges: int = 0
var reconnect_edges: int = 0


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		if failures < 20:
			push_error(message)


func signature(room: AbyssRoomData, include_regions: bool = true) -> String:
	var result := "%s/%s/%s/%s" % [room.room_id, room.region, room.raw_openness, room.is_main_route]
	if not include_regions:
		result = "%s/%s" % [room.room_id, room.is_main_route]
	for edge in room.required_connections:
		result += "/%s,%s,%s,%s,%s" % [edge.edge_id, edge.kind, edge.neighbor, edge.slot, edge.opening_tile]
	return result


func _initialize() -> void:
	call_deferred("_run")


func _case(seed_value: int, size: Vector2i, width: int, height: int) -> void:
	var config := AbyssRegionConfig.new()
	config.global_seed = seed_value
	config.chunk_size = size
	var routes := AbyssRouteConfig.new()
	routes.main_route_horizontal_wander = 0.0
	routes.branching_probability = 1.0
	routes.reconnection_probability = 1.0
	var a := AbyssRouteGenerator.new(config, routes)
	var b := AbyssRouteGenerator.new(config, routes)
	var pure := AbyssRegionGenerator.new(config)
	var chunks: Array[Vector2i] = []
	for y in range(-1, height - 1):
		for x in range(-width / 2, width - width / 2):
			chunks.append(Vector2i(x, y))
	for c in chunks:
		a.get_chunk(c)
	chunks.reverse()
	for c in chunks:
		b.get_chunk(c)
	var rooms: Dictionary[Vector2i, AbyssRoomData] = {}
	var required_count := 0
	for c in chunks:
		for room in a.get_chunk(c).rooms:
			tested_rooms += 1
			rooms[room.global_coords] = room
			check(signature(room) == signature(b.get_room(room.global_coords)), "Order/determinism mismatch")
			var baseline := pure.get_room(room.global_coords)
			check(room.region == baseline.region and room.raw_openness == baseline.raw_openness and room.boundary_mask == baseline.boundary_mask, "Pass 1 modified")
			if not room.required_connections.is_empty():
				required_count += 1
			for edge in room.required_connections:
				branch_edges += int(edge.kind == AbyssRouteConnection.Kind.BRANCH)
				reconnect_edges += int(edge.kind == AbyssRouteConnection.Kind.RECONNECTION)
				var other := a.get_room(edge.neighbor)
				var reciprocal: AbyssRouteConnection = null
				for reverse in other.required_connections:
					if reverse.neighbor == room.global_coords:
						reciprocal = reverse
				check(reciprocal != null, "Missing reciprocal/shared boundary edge")
				if reciprocal != null:
					check(edge.edge_id == reciprocal.edge_id and edge.kind == reciprocal.kind and edge.slot == reciprocal.slot and (edge.side + 2) % 4 == reciprocal.side, "Incompatible boundary contract")
					check(edge.opening_tile.x == reciprocal.opening_tile.x if edge.side % 2 == 0 else edge.opening_tile.y == reciprocal.opening_tile.y, "Misaligned openings")
				if room.region == AbyssRoomData.Region.PACKED:
					check(room.required_openings.get(edge.opening_id) == edge.opening_tile, "Missing packed opening")
				else:
					check(room.required_openings.is_empty(), "OPEN required physical openings")
			for delta in AbyssRegionGenerator.DIRECTIONS:
				var other := a.get_room(room.global_coords + delta)
				check(room.allows_open_adjacency(other) == (room.region == AbyssRoomData.Region.OPEN and other.region == AbyssRoomData.Region.OPEN), "OPEN adjacency constrained")
	# A cropped preview may clip a valid side attachment. Include deterministic
	# parent chains for reachability rather than assuming horizontal highways.
	var traversal_rooms: Dictionary = rooms.duplicate()
	var min_band := -1
	var max_band := height - 2
	for c in chunks:
		var parent := c
		var guard := 0
		while parent.x != routes.entrance_chunk_x and guard < 100:
			parent = a.parent_chunk(parent)
			min_band = mini(min_band, parent.y)
			max_band = maxi(max_band, parent.y)
			for room in a.get_chunk(parent).rooms:
				traversal_rooms[room.global_coords] = room
			guard += 1
		check(guard < 100, "Chunk parent did not reach main spine")
	for band in range(min_band, max_band + 1):
		for room in a.get_chunk(Vector2i(routes.entrance_chunk_x, band)).rooms:
			traversal_rooms[room.global_coords] = room
	# BFS through required edges, including upward reciprocals.
	var start := a.entrance_for_band(-1)
	var queue: Array[Vector2i] = [start]
	var reached: Dictionary[Vector2i, bool] = {start: true}
	var index := 0
	while index < queue.size():
		var room: AbyssRoomData = traversal_rooms[queue[index]]
		index += 1
		for edge in room.required_connections:
			if traversal_rooms.has(edge.neighbor) and not reached.has(edge.neighbor):
				reached[edge.neighbor] = true
				queue.append(edge.neighbor)
	var reached_original := 0
	for pos in rooms:
		if reached.has(pos):
			reached_original += 1
	check(reached_original == required_count, "Disconnected exploration routes")
	# Every optional room lies within the configured growth length of a skeleton
	# room. This also checks branches cannot quietly become a second generator.
	var distances: Dictionary[Vector2i, int] = {}
	queue = []
	for room in rooms.values():
		for edge in room.required_connections:
			if edge.kind == AbyssRouteConnection.Kind.MAIN or edge.kind == AbyssRouteConnection.Kind.ACCESS:
				if not distances.has(room.global_coords):
					distances[room.global_coords] = 0
					queue.append(room.global_coords)
	index = 0
	while index < queue.size():
		var pos := queue[index]
		index += 1
		for edge in rooms[pos].required_connections:
			if rooms.has(edge.neighbor) and not distances.has(edge.neighbor):
				distances[edge.neighbor] = distances[pos] + 1
				queue.append(edge.neighbor)
	for distance in distances.values():
		check(distance <= routes.branch_length, "Branch length bound violated")
	# Follow MAIN-only edges across all vertical bands and to the bottom contract.
	queue = [start]
	reached = {start: true}
	index = 0
	while index < queue.size():
		var pos := queue[index]
		index += 1
		for edge in a.get_room(pos).required_connections:
			if edge.kind == AbyssRouteConnection.Kind.MAIN and rooms.has(edge.neighbor) and not reached.has(edge.neighbor):
				reached[edge.neighbor] = true
				queue.append(edge.neighbor)
	var exit := a.entrance_for_band(height - 1)
	check(reached.has(exit + Vector2i.UP), "Main route fails to reach bottom")
	var bottom := a.get_room(exit + Vector2i.UP)
	var exits := false
	for edge in bottom.required_connections:
		exits = exits or (edge.neighbor == exit and edge.kind == AbyssRouteConnection.Kind.MAIN)
	check(exits, "Main route terminates at boundary")
	# Querying a wider/deeper area cannot mutate earlier graphs.
	var before := signature(a.get_room(start))
	a.get_chunk(Vector2i(19, 27))
	check(before == signature(a.get_room(start)), "Preview extent mutated routes")


func _run() -> void:
	for seed_value in [12, 12345, -71]:
		_case(seed_value, Vector2i(8, 8), 5, 5)
		_case(seed_value, Vector2i(5, 3), 3, 3)
		_case(seed_value, Vector2i.ONE, 3, 4)
	check(branch_edges > 0 and reconnect_edges > 0, "Missing optional route kinds")
	for probability in [0.0, 1.0]:
		var config := AbyssRegionConfig.new()
		var settings := AbyssRouteConfig.new()
		settings.main_route_horizontal_wander = 0.0
		settings.branching_probability = probability
		settings.reconnection_probability = 0.0
		var generator := AbyssRouteGenerator.new(config, settings)
		for y in range(-2, 3):
			var layout := generator.debug_layout(Vector2i(0, y))
			var vertices: Dictionary = {}
			var internal_edges := 0
			var rect := Rect2i(Vector2i(0, y) * config.chunk_size, config.chunk_size)
			for edge in layout.edges.values():
				for endpoint in [edge[0], edge[1]]:
					if rect.has_point(endpoint):
						vertices[endpoint] = true
				if rect.has_point(edge[0]) and rect.has_point(edge[1]):
					internal_edges += 1
			check(internal_edges == vertices.size() - 1, "Zero reconnection setting produced an unintended cycle")
			for room in generator.get_chunk(Vector2i(0, y)).rooms:
				for edge in room.required_connections:
					check(edge.kind != AbyssRouteConnection.Kind.RECONNECTION, "Reconnection probability zero violated")
					if probability == 0.0:
						check(edge.kind != AbyssRouteConnection.Kind.BRANCH, "Branch probability zero violated")
	# Stable IDs and arbitrary opening positions are a construction-independent interface.
	var custom := AbyssRouteConfig.new()
	custom.main_route_horizontal_wander = 0.0
	custom.horizontal_offsets = Vector2i(2, 9)
	custom.vertical_offsets = Vector2i(1, 10)
	check(custom.is_valid(Vector2i(12, 12)), "Valid custom slots rejected")
	var generator := AbyssRouteGenerator.new(AbyssRegionConfig.new(), custom)
	for room in generator.get_chunk(Vector2i.ZERO).rooms:
		for edge in room.required_connections:
			check(edge.opening_tile == custom.opening_position(edge.side, edge.slot, Vector2i(12, 12)), "Custom opening ignored")
	var changed_config := AbyssRegionConfig.new()
	var original := AbyssRouteGenerator.new(changed_config, custom)
	changed_config.global_seed += 37
	var changed := AbyssRouteGenerator.new(changed_config, custom)
	var changed_rooms := 0
	for y in range(-8, 16):
		for x in range(-8, 16):
			if signature(original.get_room(Vector2i(x, y)), false) != signature(changed.get_room(Vector2i(x, y)), false):
				changed_rooms += 1
	check(changed_rooms > 100, "Different seeds failed to change layout")
	print("Route tests: %d rooms, %d branch endpoints, %d reconnect endpoints, %d failures" % [tested_rooms, branch_edges, reconnect_edges, failures])
	quit(0 if failures == 0 else 1)
