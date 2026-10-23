extends SceneTree
var failures: int = 0
var config := AbyssRegionConfig.new()
var routes := AbyssRouteConfig.new()
var registry: AbyssRoomTemplateRegistry


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func requirements(ids: Array, coords: Vector2i = Vector2i.ZERO, region: AbyssRoomData.Region = AbyssRoomData.Region.PACKED, open_neighbors: int = 0) -> AbyssRoomRequirements:
	var room := AbyssRoomData.new()
	room.global_coords = coords
	room.region = region
	var neighbors: Array[AbyssRoomData] = []
	for side in range(4):
		var other := AbyssRoomData.new()
		other.global_coords = coords + AbyssRegionGenerator.DIRECTIONS[side]
		other.region = AbyssRoomData.Region.OPEN if open_neighbors & (1 << side) else AbyssRoomData.Region.PACKED
		if other.region != region:
			room.boundary_mask |= 1 << side
		neighbors.append(other)
	for id_text in ids:
		var id := StringName(id_text)
		var side := ["north", "east", "south", "west"].find(String(id).get_slice(":", 0))
		var slot := int(String(id).get_slice(":", 1))
		var edge := AbyssRouteConnection.new()
		edge.side = side
		edge.slot = slot
		edge.opening_id = id
		edge.opening_tile = routes.opening_position(side, slot, config.room_size)
		edge.neighbor = coords + AbyssRegionGenerator.DIRECTIONS[side]
		room.required_connections.append(edge)
		if region == AbyssRoomData.Region.PACKED:
			room.required_openings[id] = edge.opening_tile
	return AbyssRoomRequirements.from_room(room, config, routes, neighbors)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	registry = load("res://Scenes/Underground/Rooms/example_registry.tres")
	var selector := AbyssRoomTemplateSelector.new(registry, 12345)
	check(selector.registration_errors.is_empty(), "Example registration failed: %s" % selector.registration_errors)
	var cases := [
		[["west:0", "east:0"], AbyssRoomData.Region.PACKED, 0, "packed_horizontal"],
		[["north:0", "south:0"], AbyssRoomData.Region.PACKED, 0, "packed_vertical"],
		[["north:0", "east:0"], AbyssRoomData.Region.PACKED, 0, "packed_corner"],
		[["north:1", "east:0", "west:1"], AbyssRoomData.Region.OPEN, 15, "open_cavern"],
		[["west:0", "east:0"], AbyssRoomData.Region.PACKED, 8, "transition_west"]]
	for data in cases:
		var req := requirements(data[0], Vector2i.ZERO, data[1], data[2])
		var selected := selector.select(req)
		# Transition and ordinary packed horizontal can both be safe here; use
		# a transition-only registry to demonstrate the intentionally open face.
		if data[3] == "transition_west":
			var transition_registry := AbyssRoomTemplateRegistry.new()
			transition_registry.templates = [registry.templates[4]]
			selected = AbyssRoomTemplateSelector.new(transition_registry, 12345).select(req)
		check(selected.template_id == StringName(data[3]), "Wrong example selected: %s" % data[3])
		var scene := AbyssRoomSceneInstantiator.instantiate_authored(selected)
		check(scene != null, "Authored instantiation failed")
		if scene != null:
			check(scene.construction_requirements == req, "Geometry lost requirements snapshot")
			check(scene.get_node("Solid") is TileMapLayer and scene.get_node("Platforms") is TileMapLayer and scene.get_node("Decorations") is TileMapLayer, "Layer hierarchy changed")
			scene.free()
	for ids in [["east:0"], ["north:1", "south:1"], ["north:0", "south:0", "east:0"], []]:
		var fallback := selector.select(requirements(ids))
		check(fallback.method == AbyssRoomConstructionRequest.Method.PROCEDURAL and fallback.scene == null and fallback.requirements != null, "Unsupported combination did not fall back")
		check(fallback.global_seed == 12345 and fallback.room_seed == selector.select(requirements(ids)).room_seed, "Fallback seed missing or unstable")
		check(AbyssRoomSceneInstantiator.instantiate_authored(fallback) == null, "Fallback unexpectedly built geometry")
	var transition_registry := AbyssRoomTemplateRegistry.new()
	transition_registry.templates = [registry.templates[4]]
	var transition_selector := AbyssRoomTemplateSelector.new(transition_registry, 12)
	check(transition_selector.select(requirements(["east:0"], Vector2i.ZERO, AbyssRoomData.Region.PACKED, 0)).scene == null, "Transition leaked into packed neighbor")
	var unknown := requirements(["east:0"], Vector2i.ZERO, AbyssRoomData.Region.PACKED, 8)
	unknown.neighbor_open_sides = 0
	unknown.known_neighbor_sides = 0
	check(transition_selector.select(unknown).scene == null, "Unknown neighbor treated as open")
	check(transition_selector.select(requirements(["west:1", "east:0"], Vector2i.ZERO, AbyssRoomData.Region.PACKED, 8)).scene != null, "Full OPEN transition face did not cover the other slot")
	# Two adjacent authored PACKED rooms agree with the exact route conventions.
	var left := selector.select(requirements(["west:0", "east:0"]))
	var right := selector.select(requirements(["west:0", "east:0"], Vector2i.RIGHT))
	check(left.requirements.required_openings[&"east:0"].y == right.requirements.required_openings[&"west:0"].y, "Packed openings are misaligned")
	var custom := requirements(["west:0", "east:0"])
	custom.vertical_offsets.x = 4
	check(selector.select(custom).scene == null, "Changed opening positions incorrectly matched authored geometry")
	custom = requirements(["west:0", "east:0"])
	custom.opening_schema = &"different_schema"
	check(selector.select(custom).scene == null, "Opening schema mismatch accepted")
	custom = requirements(["west:0", "east:0"])
	custom.tile_pixels = 32
	check(selector.select(custom).scene == null, "World tile scale mismatch accepted")
	custom = requirements(["west:0", "east:0"])
	custom.room_size = Vector2i(16, 12)
	check(selector.select(custom).scene == null, "Room size mismatch accepted")
	# Weighted choice, input-order independence, and adding templates via registry.
	var weighted := AbyssRoomTemplateRegistry.new()
	var a := registry.templates[0].duplicate(true) as AbyssRoomTemplateMetadata
	var b := a.duplicate(true) as AbyssRoomTemplateMetadata
	a.template_id = &"a"
	a.selection_weight = 1
	b.template_id = &"b"
	b.selection_weight = 3
	weighted.templates = [b, a]
	var weighted_selector := AbyssRoomTemplateSelector.new(weighted, 12345)
	weighted.templates.reverse()
	var reversed := AbyssRoomTemplateSelector.new(weighted, 12345)
	var other_seed := AbyssRoomTemplateSelector.new(weighted, 98765)
	var b_count := 0
	var seed_changes := 0
	var chosen: Dictionary = {}
	for i in range(1000):
		var req := requirements(["west:0", "east:0"], Vector2i(i - 500, i % 31 - 15))
		var id := weighted_selector.select(req).template_id
		chosen[req.global_coords] = id
		b_count += int(id == &"b")
		seed_changes += int(id != other_seed.select(req).template_id)
	for coords in chosen.keys():
		check(reversed.select(requirements(["west:0", "east:0"], coords)).template_id == chosen[coords], "Registration order changed selection")
	for i in range(999, -1, -1):
		var coords := Vector2i(i - 500, i % 31 - 15)
		check(weighted_selector.select(requirements(["west:0", "east:0"], coords)).template_id == chosen[coords], "Request order changed selection")
	check(b_count > 650 and b_count < 850 and seed_changes > 100, "Weighted seeded selection did not vary as expected")
	# One template can declare several realizable combinations with scene overrides.
	var combo_registry := AbyssRoomTemplateRegistry.new()
	var combo := registry.templates[0].duplicate(true) as AbyssRoomTemplateMetadata
	combo.template_id = &"two_combinations"
	var vertical := registry.templates[1].opening_combinations[0].duplicate(true) as AbyssRoomOpeningProfile
	vertical.variant_id = &"vertical"
	vertical.scene = registry.templates[1].scene
	combo.opening_combinations.append(vertical)
	combo_registry.templates = [combo]
	var combo_selector := AbyssRoomTemplateSelector.new(combo_registry, 1)
	check(combo_selector.select(requirements(["north:0", "south:0"])).variant_id == &"vertical", "Combination scene override failed")
	check(combo_selector.select(requirements(["north:0", "east:0"])).scene == null, "Combinations incorrectly treated as arbitrary subsets")
	var duplicate := AbyssRoomTemplateRegistry.new()
	duplicate.templates = [a, a]
	var duplicate_selector := AbyssRoomTemplateSelector.new(duplicate, 1)
	check(not duplicate_selector.registration_errors.is_empty() and duplicate_selector.select(requirements(["west:0", "east:0"])).scene == null, "Duplicate stable IDs were not excluded")
	# Geometry authoring errors are excluded before they can create extra holes.
	var invalid := registry.templates[0].duplicate(true) as AbyssRoomTemplateMetadata
	invalid.opening_combinations[0].openings = [&"east:0"]
	invalid.opening_combinations[0].opening_tiles.erase(&"west:0")
	check(not AbyssRoomTemplateValidator.validate(invalid).is_empty(), "Undeclared physical hole not detected")
	invalid = registry.templates[0].duplicate(true) as AbyssRoomTemplateMetadata
	invalid.opening_combinations[0].opening_tiles[&"east:0"] = Vector2i(11, 8)
	check(not AbyssRoomTemplateValidator.validate(invalid).is_empty(), "Blocked slot marker not detected")
	for metadata in registry.templates:
		check(AbyssRoomTemplateValidator.validate(metadata).is_empty(), "Example geometry invalid: %s" % metadata.template_id)
	var base := load("res://Scenes/Underground/Rooms/room_base.tscn").instantiate() as AbyssAuthoredRoom
	check(base.get_node("OpeningGuides").get_child_count() == 8, "Base opening guides missing")
	base.free()
	# Real generated data integration; selection must not alter routes or regions.
	# Use a small explicit noise halo for test throughput, preserving live defaults.
	var test_config := config.duplicate() as AbyssRegionConfig
	test_config.smoothing_radius = 1
	test_config.smoothing_iterations = 2
	var generator := AbyssRouteGenerator.new(test_config, routes)
	var authored := 0
	var real_decisions: Dictionary = {}
	var fallback_count := 0
	for room in generator.get_chunk(Vector2i.ZERO).rooms:
		var region := room.region
		var connections := room.required_connections.duplicate()
		var openings := room.required_openings.duplicate()
		var decision := selector.select_room(generator, room.global_coords)
		real_decisions[room.global_coords] = [decision.method, decision.template_id, decision.variant_id, decision.room_seed]
		authored += int(decision.method == AbyssRoomConstructionRequest.Method.AUTHORED)
		fallback_count += int(decision.method == AbyssRoomConstructionRequest.Method.PROCEDURAL)
		check(room.region == region and room.required_connections == connections and room.required_openings == openings, "Selection modified logical room data")
	var reordered_generator := AbyssRouteGenerator.new(test_config, routes)
	reordered_generator.get_chunk(Vector2i(-1, -1))
	var reverse_coords: Array = real_decisions.keys()
	reverse_coords.reverse()
	for coords in reverse_coords:
		var decision := selector.select_room(reordered_generator, coords)
		check(real_decisions[coords] == [decision.method, decision.template_id, decision.variant_id, decision.room_seed], "Actual chunk request order changed template selection")
	check(authored + fallback_count == 64 and authored > 0 and fallback_count > 0, "Real generated-room integration not exercised")
	var world_request := selector.select(requirements(["west:0", "east:0"], Vector2i(-1, 2)))
	var world_scene := AbyssRoomSceneInstantiator.instantiate_authored(world_request)
	check(world_scene != null and world_scene.position == Vector2(-192, 384), "Authored world placement uses wrong tile coordinates")
	if world_scene != null:
		world_scene.free()
	var abyss := load("res://Scenes/Underground/abyss.tscn").instantiate() as Node2D
	var preview := abyss.get_node("RegionPreview")
	preview.configuration = test_config
	preview.preview_origin = Vector2i.ZERO
	preview.preview_width_chunks = 1
	preview.preview_height_chunks = 1
	preview.show_terrain = false
	preview.show_template_selection = true
	root.add_child(abyss)
	check(preview._construction_requests.size() == 64, "Generated preview selection overlay did not populate")
	check(preview.get_child_count() == 1, "Selection unexpectedly built world geometry")
	abyss.queue_free()
	var gallery: Node = load("res://Scenes/Underground/Rooms/example_gallery.tscn").instantiate()
	root.add_child(gallery)
	gallery.queue_free()
	print("Room templates: five examples validated; weighted b selection %d/1000; seed changes %d; generated chunk %d authored / %d fallback; %d failures" % [b_count, seed_changes, authored, fallback_count, failures])
	quit(0 if failures == 0 else 1)
