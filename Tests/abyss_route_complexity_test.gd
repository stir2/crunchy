extends SceneTree
var failures: int = 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_steps := 0
	var direct_steps := 0
	var runs: Array[int] = []
	var branch_lengths: Array[int] = []
	var secondary_branches := 0
	var junctions := 0
	var dead_ends := 0
	var cycles := 0
	var crossing_sides := [0, 0, 0, 0]
	var horizontal_offsets: Dictionary = {}
	var vertical_offsets: Dictionary = {}
	var upward_steps := 0
	var long_horizontal_rows := 0
	var shape_signatures: Dictionary = {}
	var all_edges: Array = []
	for seed_value in [12, 12345, -71, 8, 91, 314, 2026, 777]:
		var config := AbyssRegionConfig.new()
		config.global_seed = seed_value
		var routes := AbyssRouteConfig.new()
		routes.main_route_horizontal_wander = 0.0
		var gen := AbyssRouteGenerator.new(config, routes)
		var rooms: Dictionary = {}
		var edges: Dictionary = {}
		var shapes := ""
		for cy in range(-2, 6):
			for cx in range(-2, 3):
				var coords := Vector2i(cx, cy)
				var layout := gen.debug_layout(coords)
				check(gen.validate_chunk_layout(coords), "Invalid local network")
				for room in gen.get_chunk(coords).rooms:
					rooms[room.global_coords] = room
				for id in layout.edges:
					edges[id] = layout.edges[id]
				var branch_rooms: Dictionary = {}
				for path in layout.branches:
					secondary_branches += int(branch_rooms.has(path[0]))
					branch_lengths.append(path.size() - 1)
					for i in range(1, path.size()):
						branch_rooms[path[i]] = true
				for contract in layout.contracts:
					crossing_sides[contract.side] += 1
					if int(contract.side) % 2 == 0:
						vertical_offsets[posmod(contract.a.x, 8)] = true
					else:
						horizontal_offsets[posmod(contract.a.y, 8)] = true
				if cx == 0:
					var path: Array = layout.main_path
					main_steps += path.size() # internal edges + next vertical contract
					direct_steps += 8
					shapes += str(path)
					var direction := Vector2i.ZERO
					var run := 0
					for i in range(1, path.size()):
						var next: Vector2i = path[i] - path[i - 1]
						upward_steps += int(next == Vector2i.UP)
						if next == direction:
							run += 1
						else:
							if run > 0:
								runs.append(run)
							run = 1
							direction = next
					if run > 0:
						runs.append(run)
		shape_signatures[shapes] = true
		# Count independent cycles E-V+C in the induced finite graph, rather
		# than assuming every edge tagged RECONNECTION is a unique cycle.
		var adjacency: Dictionary = {}
		var edge_count := 0
		for edge in edges.values():
			if rooms.has(edge[0]) and rooms.has(edge[1]):
				edge_count += 1
				for endpoint in [edge[0], edge[1]]:
					if not adjacency.has(endpoint):
						adjacency[endpoint] = []
				adjacency[edge[0]].append(edge[1])
				adjacency[edge[1]].append(edge[0])
				if seed_value == 12:
					all_edges.append([edge[0].x, edge[0].y, edge[1].x, edge[1].y, edge[2]])
		var components := 0
		var visited: Dictionary = {}
		for pos in adjacency:
			junctions += int(adjacency[pos].size() >= 3)
			# Exclude crop boundaries from dead-end measurements.
			if pos.x > -16 and pos.x < 23 and pos.y > -16 and pos.y < 47:
				dead_ends += int(adjacency[pos].size() == 1)
			if visited.has(pos):
				continue
			components += 1
			var queue: Array = [pos]
			visited[pos] = true
			var index := 0
			while index < queue.size():
				var cursor: Vector2i = queue[index]
				index += 1
				for next in adjacency[cursor]:
					if not visited.has(next):
						visited[next] = true
						queue.append(next)
		var local_cycles := edge_count - adjacency.size() + components
		check(local_cycles > 0, "No cycles for representative seed")
		cycles += local_cycles
		# None of the sampled rows should be a continuous 5-chunk highway.
		for y in range(-16, 48):
			var continuous := true
			for x in range(-16, 23):
				if not edges.has(AbyssRouteGenerator._edge_id(Vector2i(x, y), Vector2i(x + 1, y))):
					continuous = false
			long_horizontal_rows += int(continuous)
	var branch_sum := 0
	var meaningful := 0
	for length in branch_lengths:
		branch_sum += length
		meaningful += int(length >= 3)
	var run_sum := 0
	var run_max := 0
	for length in runs:
		run_sum += length
		run_max = maxi(run_max, length)
	check(main_steps > direct_steps * 1.3, "Main routes are not meaningfully winding")
	check(upward_steps > 0, "No upward detours")
	check(secondary_branches > 0, "No branches grow from branches")
	check(meaningful > 30, "Missing meaningful multi-room branches")
	check(long_horizontal_rows == 0, "Repeated full-width highways")
	check(shape_signatures.size() == 8, "Seeds do not vary route shapes")
	check(horizontal_offsets.size() > 4 and vertical_offsets.size() > 4, "Boundary crossings lack variety")
	print("Route metrics: 8 seeds, 320 chunks, main stretch %.2fx, straight runs avg %.2f max %d, upward steps %d" % [float(main_steps) / direct_steps, float(run_sum) / runs.size(), run_max, upward_steps])
	print("Branches: %d, average %.2f, max %d, >=3 rooms %d; junctions %d, interior dead ends %d, independent cycles %d" % [branch_lengths.size(), float(branch_sum) / maxi(1, branch_lengths.size()), branch_lengths.max(), meaningful, junctions, dead_ends, cycles])
	print("Secondary branch starts: %d" % secondary_branches)
	print("Boundary endpoints N/E/S/W: %s; offsets horizontal %d/8 vertical %d/8; highways %d; shape variants %d" % [crossing_sides, horizontal_offsets.size(), vertical_offsets.size(), long_horizontal_rows, shape_signatures.size()])
	var file := FileAccess.open("/tmp/abyss_route_edges.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(all_edges))
	print("Route complexity tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)
