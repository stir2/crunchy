extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func requirements(coords: Vector2i = Vector2i(-3,8)) -> AbyssRoomRequirements:
	var req := AbyssRoomRequirements.new()
	req.global_coords = coords
	req.room_size = AbyssRegionConfig.DEFAULT_ROOM_SIZE
	req.region = AbyssRoomData.Region.OPEN
	req.opening_schema = &"abyss_slots_v1"
	req.horizontal_offsets = Vector2i(6,17)
	req.vertical_offsets = Vector2i(6,17)
	return req
func pack(room: AbyssAuthoredRoom) -> PackedScene:
	var scene := PackedScene.new()
	check(scene.pack(room) == OK, "Could not pack fixture")
	return scene
func run() -> void:
	var metadata: AbyssRoomTemplateMetadata = load("res://Scenes/Underground/Rooms/Metadata/open_cavern.tres")
	var registry := AbyssRoomTemplateRegistry.new()
	registry.templates = [metadata]
	var bytes_before := FileAccess.get_file_as_bytes(metadata.scene.resource_path)
	var source := metadata.scene.instantiate() as AbyssAuthoredRoom
	var painted := source.get_node("ConditionalWalls") as TileMapLayer
	var groups := AbyssConditionalWallGroups.components(painted)
	check(groups.size() == 4 and painted.get_used_cells().size() == 12, "Sample must have four independent three-cell groups")
	check(AbyssRoomTemplateValidator.validate(metadata).is_empty(), "Sample metadata rejected")
	var patterns: Dictionary = {}
	var counts: Array[int] = [0,0,0,0]
	for seed_value in range(256):
		var selector := AbyssRoomTemplateSelector.new(registry, seed_value)
		var request := selector.select(requirements())
		check(request.conditional_wall_probability == 0.5, "Metadata probability not propagated")
		var a := AbyssRoomSceneInstantiator.instantiate_authored(request)
		var b := AbyssRoomTerrainBuilder.build(selector.select(requirements()), AbyssTerrainConfig.new())
		var pattern := ""
		for i in range(a.conditional_wall_groups.size()):
			var decision: Dictionary = a.conditional_wall_groups[i]
			pattern += "1" if decision.included else "0"
			counts[i] += int(decision.included)
			for cell in decision.cells:
				check((a.get_node("ConditionalWalls").get_cell_source_id(cell) != -1) == decision.included, "Group appeared partially")
				check(AbyssRoomTemplateValidator._has_solid_collision(a.get_node("ConditionalWalls"), cell) == decision.included, "Collision differs from visible group")
		check(a.conditional_wall_groups == b.conditional_wall_groups, "Same-seed construction differs")
		for key in ["Solid", "Platforms", "Decorations"]:
			check(a.get_node(key).tile_map_data == source.get_node(key).tile_map_data, "Permanent authored tiles changed")
		check(a.get_node("ObjectMarkers").get_child_count() == source.get_node("ObjectMarkers").get_child_count(), "Markers lost")
		patterns[pattern] = true
		a.free()
		b.free()
	check(patterns.size() == 16, "Separate groups did not produce independent combinations")
	for count in counts:
		check(count > 85 and count < 170, "Group roll rate far from 50 percent")
	# Reversed coordinates/request order and adding an earlier-sorting component.
	var selector := AbyssRoomTemplateSelector.new(registry, 98765)
	var snapshots: Dictionary = {}
	var coords_list := [Vector2i(-8,-1), Vector2i(-1,0), Vector2i(0,0), Vector2i(8,0)]
	for coords in coords_list:
		var room := AbyssRoomSceneInstantiator.instantiate_authored(selector.select(requirements(coords)))
		snapshots[coords] = room.conditional_wall_groups.duplicate(true)
		room.free()
	coords_list.reverse()
	for coords in coords_list:
		var room := AbyssRoomSceneInstantiator.instantiate_authored(selector.select(requirements(coords)))
		check(room.conditional_wall_groups == snapshots[coords], "Request order or neighboring room changed rolls")
		room.free()
	var extra := metadata.scene.instantiate() as AbyssAuthoredRoom
	extra.get_node("ConditionalWalls").set_cell(Vector2i(1,8),0,Vector2i.ZERO)
	var request := selector.select(requirements())
	var reference_roll := AbyssConditionalWallGroups.roll(request, Vector2i(3,3))
	var other_coords := selector.select(requirements(Vector2i(8,-1)))
	check(reference_roll != AbyssConditionalWallGroups.roll(other_coords, Vector2i(3,3)), "Room coordinates ignored by hash")
	var original_id := request.template_id
	request.template_id = &"another_template"
	check(reference_roll != AbyssConditionalWallGroups.roll(request, Vector2i(3,3)), "Template ID ignored by hash")
	request.template_id = original_id
	var original := AbyssRoomSceneInstantiator.instantiate_authored(request)
	request.scene = pack(extra)
	var added := AbyssRoomSceneInstantiator.instantiate_authored(request)
	for old in original.conditional_wall_groups:
		for group in added.conditional_wall_groups:
			if old.id == group.id:
				check(old.roll == group.roll and old.included == group.included, "Unrelated group changed existing roll")
	original.free()
	added.free()
	extra.free()
	# Diagonals are not connected; a one-cell empty gap separates components.
	var diagonal := TileMapLayer.new()
	diagonal.tile_set = AbyssRoomTerrainBuilder.TILES
	for cell in [Vector2i(2,2), Vector2i(3,3), Vector2i(5,3)]:
		diagonal.set_cell(cell,0,Vector2i.ZERO)
	check(AbyssConditionalWallGroups.components(diagonal).size() == 3, "Diagonal/gapped groups merged")
	diagonal.free()
	# Force include/exclude and verify real physics bodies at painted tile centers.
	var instances: Array[AbyssAuthoredRoom] = []
	for probability in [0.0,1.0]:
		var custom := metadata.duplicate(true) as AbyssRoomTemplateMetadata
		custom.conditional_wall_probability = probability
		var custom_registry := AbyssRoomTemplateRegistry.new()
		custom_registry.templates = [custom]
		var selected := AbyssRoomTemplateSelector.new(custom_registry,42).select(requirements(Vector2i(0,int(probability)*2)))
		var room := AbyssRoomSceneInstantiator.instantiate_authored(selected)
		root.add_child(room)
		instances.append(room)
		check(room.get_node("ConditionalWalls").get_used_cells().size() == (12 if probability == 1.0 else 0), "Probability endpoint failed")
	await physics_frame
	await physics_frame
	for i in range(instances.size()):
		var room := instances[i]
		for cell in painted.get_used_cells():
			var query := PhysicsPointQueryParameters2D.new()
			query.position = room.to_global((Vector2(cell) + Vector2(0.5,0.5)) * 16)
			query.collision_mask = 1
			check(not room.get_world_2d().direct_space_state.intersect_point(query).is_empty() if i == 1 else room.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "Physics body differs from selected group")
		room.free()
	# Defensive construction: never clip a group; suppress the whole group on
	# a route, reserved rectangle, or perimeter even if caller bypasses validation.
	var unsafe := metadata.scene.instantiate() as AbyssAuthoredRoom
	var conditional := unsafe.get_node("ConditionalWalls") as TileMapLayer
	for cell in [Vector2i(0,6),Vector2i(1,6),Vector2i(8,5),Vector2i(8,6),Vector2i(10,8),Vector2i(11,8)]:
		conditional.set_cell(cell,0,Vector2i.ZERO)
	var unsafe_metadata := metadata.duplicate(true) as AbyssRoomTemplateMetadata
	unsafe_metadata.scene = pack(unsafe)
	check(not AbyssRoomTemplateValidator.validate(unsafe_metadata).is_empty(), "Unsafe authoring accepted")
	request = selector.select(requirements())
	request.conditional_wall_probability = 1.0
	request.requirements.route_openings = {&"west:0":Vector2i(0,6),&"east:0":Vector2i(23,6)}
	request.scene = unsafe_metadata.scene
	var guarded := AbyssRoomSceneInstantiator.instantiate_authored(request)
	for cell in [Vector2i(0,6),Vector2i(1,6),Vector2i(8,5),Vector2i(8,6),Vector2i(10,8),Vector2i(11,8)]:
		check(guarded.get_node("ConditionalWalls").get_cell_source_id(cell) == -1, "Conditional wall blocks protected route")
	guarded.free()
	# A single required port also protects an interior approach in a dead end.
	request.requirements.route_openings.erase(&"east:0")
	guarded = AbyssRoomSceneInstantiator.instantiate_authored(request)
	check(guarded.get_node("ConditionalWalls").get_cell_source_id(Vector2i(8,6)) == -1, "Dead-end approach blocked")
	guarded.free()
	unsafe.free()
	for probability in [-0.1,1.1,NAN]:
		var invalid := metadata.duplicate(true) as AbyssRoomTemplateMetadata
		invalid.conditional_wall_probability = probability
		check(not AbyssRoomTemplateValidator.validate(invalid).is_empty(), "Invalid probability accepted")
	check(FileAccess.get_file_as_bytes(metadata.scene.resource_path) == bytes_before and painted.get_used_cells().size() == 12, "Source scene mutated")
	source.free()
	var gallery: Node = load("res://Scenes/Underground/Rooms/example_gallery.tscn").instantiate()
	root.add_child(gallery)
	var preview_seed: int = gallery.preview_seed
	var next_seed := InputEventAction.new()
	next_seed.action = &"Preview Next Seed"
	next_seed.pressed = true
	gallery._unhandled_input(next_seed)
	check(gallery.preview_seed == preview_seed + 1 and gallery.get_child_count() == 2, "Gallery seed preview failed or leaked old cards")
	gallery.free()
	print("Conditional walls: 256 seeds, %d/16 combinations, group inclusion counts %s, physics and route guards verified; %d failures" % [patterns.size(),counts,failures])
	quit(0 if failures == 0 else 1)
