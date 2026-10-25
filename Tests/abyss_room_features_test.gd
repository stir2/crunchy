extends SceneTree
class CustomMarker extends RoomMarker:
	func kind() -> StringName:
		return &"test_custom"
var failures := 0
var damaged_count := 0
var destroyed_count := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func req(coords: Vector2i = Vector2i(-2,3)) -> AbyssRoomRequirements:
	var value := AbyssRoomRequirements.new()
	value.room_size = AbyssRegionConfig.DEFAULT_ROOM_SIZE
	value.global_coords = coords
	value.region = AbyssRoomData.Region.OPEN
	value.opening_schema = &"abyss_slots_v1"
	return value
func packed(room: AbyssAuthoredRoom) -> PackedScene:
	var scene := PackedScene.new()
	check(scene.pack(room) == OK,"Pack fixture failed")
	return scene
func run() -> void:
	var metadata: AbyssRoomTemplateMetadata = load("res://Scenes/Underground/Rooms/Metadata/feature_room.tres")
	check(AbyssRoomTemplateValidator.validate(metadata).is_empty(),"Feature template invalid: %s" % AbyssRoomTemplateValidator.validate(metadata))
	var registry := AbyssRoomTemplateRegistry.new()
	registry.templates = [metadata]
	var before := FileAccess.get_file_as_bytes(metadata.scene.resource_path)
	var selector := AbyssRoomTemplateSelector.new(registry,42)
	var request := selector.select(req())
	var state := AbyssRoomState.new()
	var room := AbyssRoomSceneInstantiator.instantiate_authored(request,state)
	root.add_child(room)
	check(room.tile_groups.ConditionalPlatforms.size() == 2 and room.tile_groups.BreakableWalls.size() == 1,"Wrong group cache")
	var cached: Array = room.tile_groups.ConditionalPlatforms.duplicate(true)
	check(cached[0].has("bounds") and cached[0].has("tiles") and cached[0].tile_type == &"ConditionalPlatforms","Missing reusable group data")
	var ladder: TileMapLayer = room.get_node("Climbables")
	check(room.climbable_cells.size() == 17 and room.climbable_regions.size() == 1,"Climbable construction data missing")
	check(cached[0].bounds == Rect2i(3,5,3,1),"Group bounding box excludes edge cells")
	var start := ladder.to_global(ladder.map_to_local(Vector2i(10,3)))
	var end := ladder.to_global(ladder.map_to_local(Vector2i(10,19)))
	check(AbyssClimbableTiles.sample(room.climbable_layers(),start).climbable,"Placed ladder not detected")
	check(AbyssClimbableTiles.vertical_path(room.climbable_layers(),start,end),"Connected vertical climb failed")
	check(not AbyssClimbableTiles.sample(room.climbable_layers(),end + Vector2(16,0)).climbable,"Climbable exit not detected")
	check(not AbyssRoomTemplateValidator._has_collision(ladder,Vector2i(10,4)),"Placeholder climbable blocks normal movement")
	room.position += Vector2(60,80)
	room.scale = Vector2(1.5,1.5)
	check(AbyssClimbableTiles.sample(room.climbable_layers(),ladder.to_global(ladder.map_to_local(Vector2i(10,8)))).climbable,"Transformed climb detection failed")
	var classes: Dictionary = {}
	for spawn in room.spawn_requests:
		classes[spawn.kind] = true
		check(spawn.world_position.is_equal_approx(room.get_node("ObjectMarkers/" + String(spawn.marker_id)).global_position),"Marker transform incorrect")
		match spawn.kind:
			&"enemy": check(spawn is EnemySpawnRequest,"Enemy request untyped")
			&"loot": check(spawn is LootSpawnRequest and spawn.quantity >= 1,"Loot request invalid")
			&"hazard": check(spawn is HazardSpawnRequest,"Hazard request untyped")
			&"transition": check(spawn is TransitionSpawnRequest,"Transition request untyped")
			&"interaction": check(spawn is InteractionSpawnRequest,"Interaction request untyped")
			&"decoration": check(spawn is DecorationSpawnRequest,"Decoration request untyped")
	check(classes.size() == 6 and room.spawn_requests.size() == 7,"Specialized marker discovery failed")
	# Seed independence between platform and wall domains, plus reproducible marker requests.
	var combinations: Dictionary = {}
	var cross_type: Dictionary = {}
	var decisions: Dictionary = {}
	var marker_patterns: Dictionary = {}
	var marker_snapshots: Dictionary = {}
	for seed_value in range(128):
		var selected := AbyssRoomTemplateSelector.new(registry,seed_value).select(req())
		var a := AbyssRoomSceneInstantiator.instantiate_authored(selected)
		var b := AbyssRoomTerrainBuilder.build(selected,AbyssTerrainConfig.new())
		check(a.conditional_platform_groups == b.conditional_platform_groups,"Platform determinism failed")
		var bits := ""
		for group in a.conditional_platform_groups:
			bits += "1" if group.included else "0"
			for cell: Vector2i in group.cells:
				var layer := a.get_node("ConditionalPlatforms") as TileMapLayer
				check((layer.get_cell_source_id(cell) != -1) == group.included,"Partial platform group")
				if group.included:
					var data := layer.get_cell_tile_data(cell)
					check(data.is_collision_polygon_one_way(0,0),"Conditional platform lost one-way collision")
		combinations[bits] = true
		cross_type[str(a.conditional_wall_groups[0].included) + "/" + str(a.conditional_platform_groups[0].included)] = true
		for i in range(a.spawn_requests.size()):
			check(a.spawn_requests[i].roll == b.spawn_requests[i].roll and a.spawn_requests[i].selected == b.spawn_requests[i].selected,"Marker seed determinism failed")
		var marker_bits := ""
		var marker_values: Array = []
		for spawn in a.spawn_requests:
			marker_bits += "1" if spawn.selected else "0"
			marker_values.append([spawn.marker_id,spawn.roll,spawn.selected])
		marker_patterns[marker_bits] = true
		marker_snapshots[seed_value] = marker_values
		decisions[seed_value] = bits
		a.free()
		b.free()
	check(marker_patterns.size() > 1,"Different seeds did not vary marker decisions")
	check(combinations.size() == 4 and cross_type.size() == 4,"Platform groups or wall/platform domains correlated")
	for seed_value in range(127,-1,-1):
		var a := AbyssRoomSceneInstantiator.instantiate_authored(AbyssRoomTemplateSelector.new(registry,seed_value).select(req()))
		var bits := ""
		for group in a.conditional_platform_groups:
			bits += "1" if group.included else "0"
		check(bits == decisions[seed_value],"Request order changes platforms")
		var values: Array = []
		for spawn in a.spawn_requests:
			values.append([spawn.marker_id,spawn.roll,spawn.selected])
		check(values == marker_snapshots[seed_value],"Request order changes markers")
		a.free()
	# Shared health, signals, visuals/collision removal and group-level persistence.
	room.breakable_damaged.connect(func(_id: String,_hp: float,_point: Vector2) -> void: damaged_count += 1)
	room.breakable_destroyed.connect(func(_id: String,_cells: Array,_point: Vector2) -> void: destroyed_count += 1)
	var break_layer := room.get_node("BreakableWalls") as TileMapLayer
	var hit := break_layer.to_global(break_layer.map_to_local(Vector2i(17,17)))
	await physics_frame
	await physics_frame
	var query := PhysicsPointQueryParameters2D.new()
	query.position = hit
	query.collision_mask = 1
	check(not room.get_world_2d().direct_space_state.intersect_point(query).is_empty(),"Intact breakable lacks collision")
	check(room.damage_breakable_at(hit,1),"Damage API failed")
	check(room.breakables.groups()[0].health == 2,"Group health not shared")
	var partial := AbyssRoomSceneInstantiator.instantiate_authored(request,state)
	check(partial.breakables.groups()[0].health == 2,"Partial damage lost on reconstruction")
	partial.free()
	check(room.damage_breakable_at(hit,2),"Group destruction failed")
	check(damaged_count == 2 and destroyed_count == 1,"Damage/destruction signals missing")
	check(break_layer.get_used_cells().is_empty(),"Destroyed group kept geometry")
	await physics_frame
	await physics_frame
	check(room.get_world_2d().direct_space_state.intersect_point(query).is_empty(),"Destroyed group kept collision")
	for spawn in room.spawn_requests:
		if spawn.kind in [&"loot",&"interaction"]:
			spawn.record_status("collected" if spawn.kind == &"loot" else "activated")
	var serialized := state.serialize()
	var restored := AbyssRoomState.new()
	check(restored.restore(serialized) == OK and restored.restore('{"version":99}') == ERR_INVALID_DATA,"State serialization/version validation failed")
	var again := AbyssRoomSceneInstantiator.instantiate_authored(request,restored)
	check(again.get_node("BreakableWalls").get_used_cells().is_empty(),"Destruction not persistent")
	for spawn in again.spawn_requests:
		if spawn.kind in [&"loot",&"interaction"]:
			check(not spawn.should_spawn() and not spawn.status().is_empty(),"Persistent marker status lost")
	check(state.groups.size() == 1,"Persistence saved per tile instead of per group")
	again.free()
	check(room.tile_groups.ConditionalPlatforms == cached,"Grouping rescanned/mutated during damage")
	room.free()
	# Extensible registered marker type, duplicate validation and protected supports.
	var source := metadata.scene.instantiate() as AbyssAuthoredRoom
	var custom := CustomMarker.new()
	custom.marker_id = &"custom"
	custom.position = Vector2(160,70)
	custom.name = "Custom"
	var nested := Node2D.new()
	nested.name = "Nested"
	nested.position = Vector2(16,8)
	nested.scale = Vector2(1.25,0.8)
	nested.rotation = 0.1
	source.get_node("ObjectMarkers").add_child(nested)
	nested.owner = source
	nested.add_child(custom)
	custom.owner = source
	RoomMarkerHandlers.register(&"test_custom",func(_marker: RoomMarker) -> RoomSpawnRequest: return RoomSpawnRequest.new())
	var custom_request := selector.select(req())
	custom_request.scene = packed(source)
	var extended := AbyssRoomSceneInstantiator.instantiate_authored(custom_request)
	check(extended.spawn_requests.size() == 8 and extended.spawn_requests.back().kind == &"test_custom","Registered marker extension not discovered")
	root.add_child(extended)
	extended.position += Vector2(25,50)
	check(extended.spawn_requests.back().world_position.is_equal_approx(extended.get_node("ObjectMarkers/Nested/Custom").global_position),"Nested marker transform lost during off-tree construction")
	extended.free()
	RoomMarkerHandlers.unregister(&"test_custom")
	var unsupported := AbyssRoomSceneInstantiator.instantiate_authored(custom_request)
	check(unsupported.spawn_requests.size() == 7 and not unsupported.content_warnings.is_empty(),"Unsupported marker not reported safely")
	unsupported.free()
	source.required_support_rects.append(Rect2i(3,5,3,1))
	var invalid := metadata.duplicate(true) as AbyssRoomTemplateMetadata
	invalid.scene = packed(source)
	check(not AbyssRoomTemplateValidator.validate(invalid).is_empty(),"Required conditional platform support accepted")
	source.free()
	# Probability endpoints, hazard clearance and independent state/world namespaces.
	for probability in [0.0,1.0]:
		var fixture := metadata.scene.instantiate() as AbyssAuthoredRoom
		for marker in AbyssRoomContent.markers(fixture):
			marker.spawn_probability = probability
			if marker is HazardSpawnMarker:
				marker.position = Vector2(12,12) * 16
		var selected := selector.select(req())
		selected.conditional_platform_probability = probability
		selected.scene = packed(fixture)
		var built := AbyssRoomSceneInstantiator.instantiate_authored(selected)
		check(built.get_node("ConditionalPlatforms").get_used_cells().size() == (6 if probability == 1 else 0),"Platform probability endpoint failed")
		root.add_child(built)
		await physics_frame
		await physics_frame
		var platform_query := PhysicsPointQueryParameters2D.new()
		platform_query.position = built.to_global(Vector2(3.5 * 16,5 * 16 + 1))
		platform_query.collision_mask = 1
		var platform_hit := not built.get_world_2d().direct_space_state.intersect_point(platform_query).is_empty()
		check(platform_hit == (probability == 1),"Omitted/included platform physics mismatch")
		for spawn in built.spawn_requests:
			check(spawn.selected == (probability == 1),"Marker probability endpoint failed")
			if spawn.kind == &"hazard":
				check(spawn.protected_route and not spawn.should_spawn(),"Hazard ignores protected route")
		built.free()
		fixture.free()
	var two := metadata.scene.instantiate() as AbyssAuthoredRoom
	two.get_node("BreakableWalls").set_cell(Vector2i(20,10),0,Vector2i(5,0))
	var selected := selector.select(req())
	selected.scene = packed(two)
	var two_state := AbyssRoomState.new()
	var built := AbyssRoomSceneInstantiator.instantiate_authored(selected,two_state)
	check(built.breakables.groups().size() == 2,"Independent breakable structures merged")
	check(built.damage_breakable_at(built.to_global(Vector2(17.5,17.5) * 16),3),"First breakable group not destroyed")
	check(built.get_node("BreakableWalls").get_used_cells() == [Vector2i(20,10)],"Destruction affected another group")
	check(two_state.groups.size() == 1,"Unexpected per-tile destruction records")
	built.free()
	# An explicit ID survives a changed canonical coordinate when the override is moved.
	two.get_node("BreakableWalls").set_cell(Vector2i(16,15),0,Vector2i(5,0))
	two.breakable_group_ids.erase(Vector2i(17,15))
	two.breakable_group_ids[Vector2i(16,15)] = "alcove_door"
	selected.scene = packed(two)
	built = AbyssRoomSceneInstantiator.instantiate_authored(selected,two_state)
	check(built.get_node("BreakableWalls").get_used_cells() == [Vector2i(20,10)],"Explicit group identity did not preserve destruction")
	built.free()
	selected.world_id = "another_world"
	built = AbyssRoomSceneInstantiator.instantiate_authored(selected,two_state)
	check(built.get_node("BreakableWalls").get_used_cells().size() > 1,"Destruction leaked to another world")
	built.free()
	two.free()
	# Runtime route guard when direct callers bypass static validation.
	var guarded_source := metadata.scene.instantiate() as AbyssAuthoredRoom
	guarded_source.get_node("BreakableWalls").set_cell(Vector2i(0,6),0,Vector2i(5,0))
	guarded_source.get_node("BreakableWalls").set_cell(Vector2i(1,6),0,Vector2i(5,0))
	for x in range(8,11):
		guarded_source.get_node("ConditionalPlatforms").set_cell(Vector2i(x,6),0,Vector2i.RIGHT)
	selected = selector.select(req())
	selected.conditional_platform_probability = 1
	selected.requirements.route_openings = {&"west:0":Vector2i(0,6),&"east:0":Vector2i(23,6)}
	selected.scene = packed(guarded_source)
	built = AbyssRoomSceneInstantiator.instantiate_authored(selected)
	check(built.get_node("BreakableWalls").get_cell_source_id(Vector2i(0,6)) == -1,"Breakable blocks required opening")
	check(built.get_node("ConditionalPlatforms").get_cell_source_id(Vector2i(9,6)) == -1 and not built.content_warnings.is_empty(),"Conditional support forced onto required route")
	built.free()
	guarded_source.free()
	check(FileAccess.get_file_as_bytes(metadata.scene.resource_path) == before,"Source template modified")
	print("Room features: climb detection, 128 seed platform/marker decisions, group damage/physics, serialized persistence and custom markers; %d failures" % failures)
	quit(0 if failures == 0 else 1)
