extends SceneTree
var failures: int = 0
var checked_connections: int = 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		if failures < 15:
			push_error(message)


func _initialize() -> void:
	call_deferred("_run")


func signature(chunk: AbyssChunkData) -> String:
	var result := ""
	for room in chunk.rooms:
		result += "%s:%s:%s;" % [room.room_id, room.region, room.is_main_route]
		for edge in room.required_connections:
			result += "%s:%s:%s:%s;" % [edge.edge_id, edge.kind, edge.opening_id, edge.opening_tile]
	return result


func _case(seed_value: int, settings: AbyssRouteConfig, depth: int, start_band: int = 0) -> Dictionary:
	var config := AbyssRegionConfig.new()
	config.global_seed = seed_value
	var a := AbyssRouteGenerator.new(config, settings)
	var b := AbyssRouteGenerator.new(config, settings)
	check(a.main_column(0) == settings.entrance_chunk_x, "Main route misses entrance")
	var columns: Dictionary = {}
	var displacement := 0
	var step_sum := 0
	var crossings := 0
	var main_length := 0
	var branches := 0
	var branch_length := 0
	var reconnections: Dictionary = {}
	var chunks: Dictionary = {}
	var plan_signature := ""
	var min_band := start_band
	var max_band := start_band + depth - 1
	for band in range(start_band, start_band + depth):
		var x := a.main_column(band)
		var next := a.main_column(band + 1)
		step_sum += absi(next - x)
		plan_signature += str(x) + ","
		for coords in a.main_chunks_for_band(band):
			columns[coords.x] = true
			displacement = maxi(displacement, absi(coords.x - settings.entrance_chunk_x))
			check(absi(coords.x - settings.entrance_chunk_x) <= settings.main_route_max_horizontal_drift, "Main route escaped horizontal bounds")
			chunks[coords] = true
			var layout := a.debug_layout(coords)
			var main_ports := 0
			for contract in layout.contracts:
				main_ports += int(contract.kind == AbyssRouteConnection.Kind.MAIN)
			check(main_ports == 2, "A main chunk must have one arrival and one departure")
			main_length += maxi(0, layout.main_path.size() - 1) + 1
			for contract in layout.contracts:
				if contract.kind == AbyssRouteConnection.Kind.MAIN and contract.side == 1:
					crossings += 1
		# Side samples on both sides and parent closure must join the moving main.
		for side in [-1, 1]:
			var coords := Vector2i(x + side * 3, band)
			var seen: Dictionary = {}
			for step in range(64):
				check(not seen.has(coords), "Chunk parent cycle")
				seen[coords] = true
				chunks[coords] = true
				min_band = mini(min_band, coords.y)
				max_band = maxi(max_band, coords.y)
				if a.is_main_chunk(coords):
					break
				var parent := a.parent_chunk(coords)
				check((parent - coords).length_squared() == 1, "Nonadjacent parent jump")
				coords = parent
			check(a.is_main_chunk(coords), "Side chain failed to reach main route")
	# Include the main route's closure across all parent bands, independent of crop.
	for band in range(min_band, max_band + 1):
		for coords in a.main_chunks_for_band(band):
			chunks[coords] = true
	var ordered: Array = chunks.keys()
	ordered.sort_custom(func(c: Vector2i, d: Vector2i) -> bool: return c.y < d.y or (c.y == d.y and c.x < d.x))
	var originals: Dictionary = {}
	for coords in ordered:
		originals[coords] = signature(a.get_chunk(coords))
	# Stable independent permutation, unrelated to the route generator's RNG.
	var rng := RandomNumberGenerator.new()
	rng.seed = 91821
	for i in range(ordered.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp = ordered[i]
		ordered[i] = ordered[j]
		ordered[j] = temp
	b.get_chunk(Vector2i(100, 1000000)) # Deep random access without predecessor generation.
	var rooms: Dictionary = {}
	for coords in ordered:
		var chunk := b.get_chunk(coords)
		check(signature(chunk) == originals[coords], "Chunk generation order changed graph")
		check(b.main_chunks_for_band(coords.y) == a.main_chunks_for_band(coords.y), "Global plan differs")
		check(b.validate_chunk_layout(coords), "Local network disconnected")
		var layout := b.debug_layout(coords)
		for path in layout.branches:
			branches += 1
			branch_length += path.size() - 1
		for room in chunk.rooms:
			rooms[room.global_coords] = room
			var main_degree := 0
			for edge in room.required_connections:
				main_degree += int(edge.kind == AbyssRouteConnection.Kind.MAIN)
			check(main_degree == (2 if room.is_main_route else 0), "Main route is not a single bidirectional chain")
			for edge in room.required_connections:
				checked_connections += 1
				if edge.kind == AbyssRouteConnection.Kind.RECONNECTION:
					reconnections[edge.edge_id] = true
				var other := b.get_room(edge.neighbor)
				var reverse: AbyssRouteConnection = null
				for candidate in other.required_connections:
					if candidate.neighbor == room.global_coords:
						reverse = candidate
				check(reverse != null, "Unmatched boundary edge")
				if reverse != null:
					check(edge.kind == reverse.kind and edge.slot == reverse.slot and edge.edge_id == reverse.edge_id, "Shared kind/slot mismatch")
					check(edge.opening_tile.x == reverse.opening_tile.x if edge.side % 2 == 0 else edge.opening_tile.y == reverse.opening_tile.y, "Opening alignment mismatch")
				check(room.required_openings.has(edge.opening_id) == (room.region == AbyssRoomData.Region.PACKED), "Packed opening interface changed")
	# Room-level traversal, not just chunk-plan adjacency. Check MAIN-only descent
	# and bidirectional full-network reachability with the same finite closure.
	var entrance := b.entrance_for_band(min_band)
	for only_main in [false, true]:
		var queue: Array[Vector2i] = [entrance]
		var reached: Dictionary = {entrance: true}
		var index := 0
		while index < queue.size():
			var room: AbyssRoomData = rooms[queue[index]]
			index += 1
			for edge in room.required_connections:
				if only_main and edge.kind != AbyssRouteConnection.Kind.MAIN:
					continue
				if rooms.has(edge.neighbor) and not reached.has(edge.neighbor):
					reached[edge.neighbor] = true
					queue.append(edge.neighbor)
		for room in rooms.values():
			if (room.is_main_route if only_main else not room.required_connections.is_empty()):
				check(reached.has(room.global_coords), "Disconnected route segment")
		var bottom := b.entrance_for_band(max_band + 1) + Vector2i.UP
		check(reached.has(bottom), "Route failed to reach deepest boundary")
	var highways := 0
	for band in range(start_band, start_band + depth):
		# Never force a straight line through the entire configured main envelope.
		for y in range(band * 8, band * 8 + 8):
			var full := true
			for x in range((settings.entrance_chunk_x - 4) * 8, (settings.entrance_chunk_x + 5) * 8 - 1):
				var room: AbyssRoomData = rooms.get(Vector2i(x, y))
				var connected := false
				if room != null:
					for edge in room.required_connections:
						connected = connected or edge.neighbor == Vector2i(x + 1, y)
				full = full and connected
			highways += int(full)
	check(highways == 0, "Horizontal highway reintroduced")
	print("Wander seed %d: columns %d, max drift %d, mean band shift %.3f, main %.2fx, horizontal crossings %d, branches %d avg %.2f, reconnect edges %d" % [seed_value, columns.size(), displacement, float(step_sum) / depth, float(main_length) / (depth * 8), crossings, branches, float(branch_length) / maxi(1, branches), reconnections.size()])
	return {"columns": columns.size(), "plan": plan_signature, "branches": branches, "loops": reconnections.size()}


## Apples-to-apples counts in the same 320-chunk crop. Mode zero is the previous
## algorithm; only the three new planner controls differ between measurements.
func _compare_local_metrics() -> void:
	for wandering in [false, true]:
		var branch_count := 0
		var branch_steps := 0
		var loops := 0
		var side_ports := 0
		for seed_value in [12, 12345, -71, 8, 91, 314, 2026, 777]:
			var config := AbyssRegionConfig.new()
			config.global_seed = seed_value
			var settings := AbyssRouteConfig.new()
			if not wandering:
				settings.main_route_horizontal_wander = 0
			var gen := AbyssRouteGenerator.new(config, settings)
			var unique_loops: Dictionary = {}
			for y in range(-2, 6):
				for x in range(-2, 3):
					var layout := gen.debug_layout(Vector2i(x, y))
					for path in layout.branches:
						branch_count += 1
						branch_steps += path.size() - 1
					for edge in layout.edges.values():
						if edge[2] == AbyssRouteConnection.Kind.RECONNECTION:
							unique_loops[AbyssRouteGenerator._edge_id(edge[0], edge[1])] = true
					for contract in layout.contracts:
						side_ports += int(contract.side % 2 == 1 and contract.kind == AbyssRouteConnection.Kind.MAIN)
			loops += unique_loops.size()
		print("Comparison %s (same 320 chunks): branches %d avg %.2f, unique reconnect edges %d, horizontal MAIN boundary endpoints %d" % ["wandering" if wandering else "previous/zero-wander", branch_count, float(branch_steps) / branch_count, loops, side_ports])


func _run() -> void:
	var plans: Dictionary = {}
	for seed_value in [12, 12345, -71, 91]:
		var result := _case(seed_value, AbyssRouteConfig.new(), 64)
		check(result.columns >= 3, "Default main route did not wander across columns")
		check(result.branches > 0 and result.loops > 0, "Branch/reconnection behavior lost")
		plans[result.plan] = true
	check(plans.size() == 4, "World seeds produce identical macro routes")
	var narrow := AbyssRouteConfig.new()
	narrow.main_route_horizontal_wander = 0
	check(_case(12, narrow, 12).columns == 1, "Zero wander should retain single-column mode")
	var bounded := AbyssRouteConfig.new()
	bounded.entrance_chunk_x = -7
	bounded.main_route_horizontal_wander = 12
	bounded.main_route_max_horizontal_drift = 2
	bounded.main_route_wander_scale = 3
	_case(12345, bounded, 24)
	_case(-71, AbyssRouteConfig.new(), 8, -12)
	var rapid := AbyssRouteConfig.new()
	rapid.main_route_horizontal_wander = 3
	rapid.main_route_max_horizontal_drift = 3
	rapid.main_route_wander_scale = 1
	_case(91, rapid, 8)
	_compare_local_metrics()
	# Plan-only extreme/negative random access and jump continuity (all adjacent).
	var config := AbyssRegionConfig.new()
	var gen := AbyssRouteGenerator.new(config, bounded)
	for band in [-1000000, -33, -1, 0, 1000000]:
		var sequence := gen.main_chunks_for_band(band)
		for i in range(sequence.size()):
			check(absi(sequence[i].x + 7) <= 2, "Negative/deep bound failure")
			if i > 0:
				check((sequence[i] - sequence[i - 1]).length_squared() == 1, "Planner skipped a chunk")
	print("Main wander tests: %d connections checked, %d failures" % [checked_connections, failures])
	quit(0 if failures == 0 else 1)
