extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func signature(room: Node) -> Array:
	var result: Array = []
	for key in ["Solid", "Platforms", "Decorations", "ConditionalWalls"]:
		var layer := room.get_node_or_null(NodePath(key)) as TileMapLayer
		if layer == null:
			result.append([])
			continue
		var cells := layer.get_used_cells()
		cells.sort()
		var values: Array = []
		for cell in cells:
			values.append([cell, layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)])
		result.append(values)
	return result
func run() -> void:
	var config := AbyssRegionConfig.new()
	config.smoothing_radius = 1
	config.smoothing_iterations = 2
	var routes := AbyssRouteConfig.new()
	var generator := AbyssRouteGenerator.new(config, routes)
	var registry: AbyssRoomTemplateRegistry = load("res://Scenes/Underground/Rooms/example_registry.tres")
	var selector := AbyssRoomTemplateSelector.new(registry, config.global_seed)
	var terrain := AbyssTerrainConfig.new()
	# Unconnected packed rooms stay solid; transition cuts remain reachable
	# from the cavern-facing boundary instead of forming sealed interior pockets.
	for seed_value in range(16):
		for open_sides in [0, 1, 2, 4, 8, 3, 15]:
			var req := AbyssRoomRequirements.new()
			req.room_size = config.room_size
			req.region = AbyssRoomData.Region.PACKED
			req.neighbor_open_sides = open_sides
			var request := AbyssRoomConstructionRequest.new()
			request.requirements = req
			request.room_seed = seed_value
			var room := AbyssRoomTerrainBuilder.build(request, terrain)
			var solid := room.get_node("Solid") as TileMapLayer
			if open_sides == 0:
				check(solid.get_used_cells().size() == req.room_size.x * req.room_size.y, "Unconnected packed room contains an artificial pocket")
			var pending: Array[Vector2i] = []
			for y in range(req.room_size.y):
				for x in range(req.room_size.x):
					if x == 0 or x == req.room_size.x - 1 or y == 0 or y == req.room_size.y - 1:
						pending.append(Vector2i(x, y))
			var reached: Dictionary = {}
			while not pending.is_empty():
				var cell: Vector2i = pending.pop_back()
				if reached.has(cell) or not Rect2i(Vector2i.ZERO, req.room_size).has_point(cell) or solid.get_cell_source_id(cell) != -1:
					continue
				reached[cell] = true
				for direction in AbyssRegionGenerator.DIRECTIONS:
					pending.append(cell + direction)
			check(reached.size() + solid.get_used_cells().size() == req.room_size.x * req.room_size.y, "Unconnected transition contains a sealed pocket")
			room.free()
	var snapshots: Dictionary = {}
	var stats := {"authored": 0, "procedural": 0, "solid": 0, "platforms": 0}
	for chunk in [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]:
		for data in generator.get_chunk(chunk).rooms:
			var request := selector.select_room(generator, data.global_coords)
			var room := AbyssRoomTerrainBuilder.build(request, terrain)
			var solid := room.get_node("Solid") as TileMapLayer
			var platforms := room.get_node("Platforms") as TileMapLayer
			var req := request.requirements
			snapshots[data.global_coords] = signature(room)
			stats["authored" if request.method == AbyssRoomConstructionRequest.Method.AUTHORED else "procedural"] += 1
			stats.solid += solid.get_used_cells().size()
			stats.platforms += platforms.get_used_cells().size()
			check(room.position == Vector2(data.global_coords * config.room_size * 16), "Room world grid mismatch")
			for layer in [solid, platforms]:
				for cell in layer.get_used_cells():
					check(Rect2i(Vector2i.ZERO, config.room_size).has_point(cell), "Overlapping room bounds")
			for id in req.required_openings:
				var cell: Vector2i = req.required_openings[id]
				check(not AbyssRoomTemplateValidator._has_collision(solid, cell) and not AbyssRoomTemplateValidator._has_collision(platforms, cell), "Blocked required opening")
				var side := ["north", "east", "south", "west"].find(String(id).get_slice(":", 0))
				var neighbor := selector.select_room(generator, data.global_coords + AbyssRegionGenerator.DIRECTIONS[side])
				if neighbor.requirements.region == AbyssRoomData.Region.PACKED:
					var opposite := AbyssRouteConfig.opening_id((side + 2) % 4, int(String(id).get_slice(":", 1)))
					check(neighbor.requirements.required_openings.has(opposite), "Adjacent slot mismatch")
			# Flood-fill empty cells: every required port must share one component.
			if not req.required_openings.is_empty():
				var pending: Array[Vector2i] = [req.required_openings.values()[0]]
				var visited: Dictionary = {}
				while not pending.is_empty():
					var cell: Vector2i = pending.pop_back()
					if visited.has(cell) or not Rect2i(Vector2i.ZERO, req.room_size).has_point(cell) or AbyssRoomTemplateValidator._has_collision(solid, cell):
						continue
					visited[cell] = true
					for direction in AbyssRegionGenerator.DIRECTIONS:
						pending.append(cell + direction)
				for opening in req.required_openings.values():
					check(visited.has(opening), "Disconnected required tunnel")
			for y in range(req.room_size.y):
				for x in range(req.room_size.x):
					if x > 0 and x < req.room_size.x - 1 and y > 0 and y < req.room_size.y - 1:
						continue
					var cell := Vector2i(x, y)
					if req.region == AbyssRoomData.Region.OPEN:
						check(not AbyssRoomTemplateValidator._has_collision(solid, cell) and not AbyssRoomTemplateValidator._has_collision(platforms, cell), "Open room enclosed")
					elif not req.required_openings.values().has(cell):
						var touches_open := (y == 0 and req.neighbor_open_sides & 1) or (x == req.room_size.x - 1 and req.neighbor_open_sides & 2) or (y == req.room_size.y - 1 and req.neighbor_open_sides & 4) or (x == 0 and req.neighbor_open_sides & 8)
						if not touches_open:
							check(AbyssRoomTemplateValidator._has_solid_collision(solid, cell), "Unintended packed boundary hole")
			if request.method == AbyssRoomConstructionRequest.Method.AUTHORED:
				var original := AbyssRoomSceneInstantiator.instantiate_authored(request)
				check(signature(original) == signature(room), "Authored tiles altered")
				check(original.get_node("ObjectMarkers").get_child_count() == room.get_node("ObjectMarkers").get_child_count(), "Markers lost")
				original.free()
			elif req.region == AbyssRoomData.Region.PACKED:
				check(not solid.get_used_cells().is_empty(), "No fallback terrain")
			room.free()
	var reordered := AbyssRouteGenerator.new(config, routes)
	var coords: Array = snapshots.keys()
	coords.reverse()
	for coord in coords:
		var room := AbyssRoomTerrainBuilder.build(selector.select_room(reordered, coord), terrain)
		check(signature(room) == snapshots[coord], "Seed/order changed geometry")
		room.free()
	var tiles := AbyssRoomTerrainBuilder.TILES
	var atlas := tiles.get_source(0) as TileSetAtlasSource
	check(atlas.get_tile_data(Vector2i.ZERO, 0).get_collision_polygons_count(0) == 1, "Missing solid collision")
	check(atlas.get_tile_data(Vector2i.RIGHT, 0).is_collision_polygon_one_way(0, 0), "Missing one-way collision")
	var abyss: Node = load("res://Scenes/Underground/abyss.tscn").instantiate()
	var preview = abyss.get_node("RegionPreview")
	preview.configuration = config
	preview.preview_width_chunks = 2
	preview.preview_height_chunks = 1
	preview.preview_origin = Vector2i(-1, 0)
	root.add_child(abyss)
	check(preview._terrain.get_child_count() == 2, "Missing physical chunks")
	check(preview.construction_statistics.authored + preview.construction_statistics.procedural == 128, "Missing physical rooms")
	for chunk in preview._terrain.get_children():
		for room in chunk.get_children():
			check(chunk.position + room.position == Vector2(room.construction_requirements.global_coords * config.room_size * 16), "Chunk-local room misplaced")
	var toggle := InputEventAction.new()
	toggle.action = &"Preview Toggle Terrain"
	toggle.pressed = true
	preview._unhandled_input(toggle)
	check(preview.get_child_count() == 1 and preview._tiles.visible, "Logical toggle failed")
	preview._unhandled_input(toggle)
	check(preview._terrain.get_child_count() == 2 and not preview._tiles.visible, "Terrain toggle failed")
	abyss.free()
	print("Physical terrain: ", stats, "; failures: ", failures)
	quit(0 if failures == 0 else 1)
