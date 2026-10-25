extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var current := AbyssRegionConfig.new()
	var routes := AbyssRouteConfig.new()
	check(current.room_size == Vector2i(24, 24) and current.chunk_size == Vector2i(8, 8), "Default dimensions incorrect")
	var registry: AbyssRoomTemplateRegistry = load("res://Scenes/Underground/Rooms/example_registry.tres")
	var selector := AbyssRoomTemplateSelector.new(registry, current.global_seed)
	check(selector.registration_errors.is_empty(), "Migrated library invalid")
	var base: AbyssAuthoredRoom = load("res://Scenes/Underground/Rooms/room_base.tscn").instantiate()
	var scenes: Array[AbyssAuthoredRoom] = [base]
	for metadata in registry.templates:
		check(metadata.room_size == current.room_size, "Metadata dimensions differ")
		scenes.append(metadata.scene.instantiate())
	for room in scenes:
		check(room.room_size == current.room_size and room.tile_pixels == 16 and room.scale == Vector2.ONE, "Room size/scale incorrect")
		check(room.get_node("ObjectMarkers/RoomCenter").position == Vector2(current.room_size * 16) / 2, "Center marker misplaced")
		for side in range(4):
			for slot in range(2):
				var id := "%s_%d" % [["north", "east", "south", "west"][side], slot]
				check(room.get_node("OpeningGuides/" + id).position == (Vector2(routes.opening_position(side, slot, current.room_size)) + Vector2(0.5, 0.5)) * 16, "Guide misplaced")
		room.free()
	# Configurability: one differently sized world falls back rather than mixing
	# the registered 24x24 scenes into a larger room grid.
	var custom := current.duplicate() as AbyssRegionConfig
	custom.room_size = Vector2i(32, 28)
	var custom_generator := AbyssRouteGenerator.new(custom, routes)
	var fallback := selector.select_room(custom_generator, Vector2i(-1, 2))
	check(fallback.method == AbyssRoomConstructionRequest.Method.PROCEDURAL and fallback.requirements.room_size == custom.room_size, "Custom world lost dimensions or selected mixed-size geometry")
	var compared := 0
	for seed_value in [current.global_seed, 12345, -71]:
		var config := current.duplicate() as AbyssRegionConfig
		config.global_seed = seed_value
		var legacy := config.duplicate() as AbyssRegionConfig
		legacy.room_size = Vector2i(12, 12)
		var legacy_routes := routes.duplicate() as AbyssRouteConfig
		legacy_routes.horizontal_offsets = Vector2i(3, 8)
		legacy_routes.vertical_offsets = Vector2i(3, 8)
		var before := AbyssRouteGenerator.new(legacy, legacy_routes)
		var after := AbyssRouteGenerator.new(config, routes)
		for cy in range(-1, 2):
			for cx in range(-1, 2):
				for room in after.get_chunk(Vector2i(cx, cy)).rooms:
					compared += 1
					var old := before.get_room(room.global_coords)
					check(room.region == old.region and room.raw_openness == old.raw_openness and room.boundary_mask == old.boundary_mask and room.is_main_route == old.is_main_route, "Room classification changed")
					check(room.required_connections.size() == old.required_connections.size(), "Logical edge count changed")
					for i in range(room.required_connections.size()):
						var edge := room.required_connections[i]
						var previous := old.required_connections[i]
						check(edge.edge_id == previous.edge_id and edge.kind == previous.kind and edge.neighbor == previous.neighbor and edge.slot == previous.slot and edge.opening_id == previous.opening_id, "Logical graph changed")
						var opposite := routes.opening_position((edge.side + 2) % 4, edge.slot, config.room_size)
						var delta := edge.neighbor * config.room_size + opposite - (room.global_coords * config.room_size + edge.opening_tile)
						check(delta == AbyssRegionGenerator.DIRECTIONS[edge.side], "Physical openings fail to align")
					var request := selector.select_room(after, room.global_coords)
					check(request.requirements.room_size == config.room_size, "Construction request size incorrect")
	# Slot contracts also align for both slots even when a sample graph uses one.
	for side in range(4):
		for slot in range(2):
			check(AbyssRegionGenerator.DIRECTIONS[side] * current.room_size + routes.opening_position((side + 2) % 4, slot, current.room_size) - routes.opening_position(side, slot, current.room_size) == AbyssRegionGenerator.DIRECTIONS[side], "Slot alignment incorrect")
	print("Room dimension migration: %d logical rooms unchanged; %d failures" % [compared, failures])
	quit(0 if failures == 0 else 1)
