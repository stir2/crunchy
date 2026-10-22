extends SceneTree
var failures: int = 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := AbyssRegionConfig.new()
	# Fixed statistical regression fixture, independent of designer tuning in
	# the live Inspector/script defaults. Scene integration still uses live data.
	config.global_seed = 12345
	config.noise_frequency = 0.035
	config.open_threshold = 0.27
	config.smoothing_radius = 1
	config.smoothing_iterations = 2
	var a := AbyssRegionGenerator.new(config)
	var b := AbyssRegionGenerator.new(config)
	var coords: Array[Vector2i] = []
	for y in range(-2, 3):
		for x in range(-2, 3):
			coords.append(Vector2i(x, y))
	for c in coords:
		a.get_chunk(c)
	coords.reverse()
	for c in coords:
		b.get_chunk(c)
	for c in coords:
		for room in a.get_chunk(c).rooms:
			var other := b.get_room(room.global_coords)
			check(room.region == other.region and room.raw_openness == other.raw_openness and room.boundary_mask == other.boundary_mask, "Order/reconstruction mismatch")
			check(a.room_to_chunk(room.global_coords) == c, "Negative coordinate mapping mismatch")
			for i in range(4):
				var neighbor := a.get_room(room.global_coords + AbyssRegionGenerator.DIRECTIONS[i])
				check(bool(room.boundary_mask & (1 << i)) == (neighbor.region != room.region), "Boundary mismatch")
	# Repartitioning the same global rooms is a stronger seam check than comparing
	# adjacent cells: it places former chunk-edge rooms inside differently sized chunks.
	var alternate := config.duplicate() as AbyssRegionConfig
	alternate.chunk_size = Vector2i(13, 11)
	var repartitioned := AbyssRegionGenerator.new(alternate)
	for y in range(-18, 19):
		for x in range(-18, 19):
			var pos := Vector2i(x, y)
			check(a.get_room(pos).region == repartitioned.get_room(pos).region and a.get_room(pos).boundary_mask == repartitioned.get_room(pos).boundary_mask, "Chunk seam dependence")
	var changed := config.duplicate() as AbyssRegionConfig
	changed.global_seed += 1
	var other_seed := AbyssRegionGenerator.new(changed)
	var different := 0
	var open_count := 0
	var isolated := 0
	var total := 0
	for cy in range(-16, 16):
		for cx in range(-16, 16):
			for room in a.get_chunk(Vector2i(cx, cy)).rooms:
				total += 1
				if room.region == AbyssRoomData.Region.OPEN:
					open_count += 1
					if room.boundary_mask == 15:
						isolated += 1
				if cx >= -2 and cx <= 2 and cy >= -2 and cy <= 2:
					if room.region != other_seed.get_room(room.global_coords).region:
						different += 1
	var ratio := float(open_count) / total
	print("Sample: %d rooms, %.2f%% OPEN, %d isolated OPEN rooms, %d changed rooms across seeds" % [total, ratio * 100, isolated, different])
	check(ratio > 0.24 and ratio < 0.36, "Default distribution outside approximate 70/30 target")
	check(different > 100, "Seeds did not meaningfully change layout")
	check(isolated < open_count * 0.01, "Too many isolated open rooms")
	# Scene integration, filled 12x12 footprints, no collision, preview resizing.
	var scene := load("res://Scenes/Underground/abyss.tscn").instantiate() as Node2D
	root.add_child(scene)
	var preview := scene.get_node("RegionPreview")
	var tiles := preview.get_node("ClassificationTiles") as TileMapLayer
	check(tiles.get_used_cells().size() == 4 * 3 * 8 * 8 * 12 * 12, "Incorrect tile coverage")
	check(not tiles.collision_enabled and tiles.tile_set.get_physics_layers_count() == 0, "Debug collision enabled")
	var before: AbyssRoomData = preview.generator.get_room(Vector2i(0, 4))
	preview.preview_width_chunks = 5
	preview.preview_height_chunks = 2
	preview.regenerate()
	check(before.region == preview.generator.get_room(Vector2i(0, 4)).region, "Preview dimensions affected layout")
	for y in range(48, 60):
		for x in range(12):
			check(tiles.get_cell_atlas_coords(Vector2i(x, y)).x == (0 if before.region == AbyssRoomData.Region.OPEN else 1), "Room footprint mismatch")
	scene.queue_free()
	print("Abyss region tests: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
