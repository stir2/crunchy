extends SceneTree
# Three OPEN quadrants leave a concave cavern corner against PACKED rock.
class CornerFixture extends AbyssRouteGenerator:
	func _init() -> void:
		super(AbyssRegionConfig.new(), AbyssRouteConfig.new())
	func get_room(coords: Vector2i) -> AbyssRoomData:
		var room := AbyssRoomData.new()
		room.global_coords = coords
		room.chunk_coords = regions.room_to_chunk(coords)
		room.region = AbyssRoomData.Region.OPEN if coords in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN] else AbyssRoomData.Region.PACKED
		return room

class FlatCavernFixture extends AbyssRouteGenerator:
	var vertical := false
	func _init() -> void:
		super(AbyssRegionConfig.new(), AbyssRouteConfig.new())
	func get_room(coords: Vector2i) -> AbyssRoomData:
		var room := AbyssRoomData.new()
		room.global_coords = coords
		room.chunk_coords = regions.room_to_chunk(coords)
		room.region = AbyssRoomData.Region.OPEN if (coords.x if vertical else coords.y) < 0 else AbyssRoomData.Region.PACKED
		return room

var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var corner_config := AbyssTerrainConfig.new()
	corner_config.transition_blend_width = 10.0
	corner_config.boundary_warp_amplitude = 0
	corner_config.boundary_detail_strength = 0
	corner_config.boundary_smoothing = false
	var corner_generator := CornerFixture.new()
	var corner_selector := AbyssRoomTemplateSelector.new(AbyssRoomTemplateRegistry.new(), 0)
	var corner_field := AbyssCavernBoundaryField.new(corner_generator, corner_selector, corner_config)
	check(not corner_field.is_solid(Vector2i(29, 29)), "Concave cavern corner remains rectangular")
	check(corner_field.is_solid(Vector2i(29, 40)), "Corner rounding erased the straight-wall reference")
	# Both orientations and negative/positive chunk seams: preserve the seal,
	# widen its root, and round its tip instead of leaving a two-cell fin.
	var authored_selector := AbyssRoomTemplateSelector.new(load("res://Scenes/Underground/Rooms/example_registry.tres"), 0)
	for seam_selector in [corner_selector, authored_selector]:
		for vertical in [false, true]:
			var seam_generator := FlatCavernFixture.new()
			seam_generator.vertical = vertical
			var seam_field := AbyssCavernBoundaryField.new(seam_generator, seam_selector, corner_config)
			for seam in [-192, 0, 192]:
				var root := Vector2i(seam + 2, 2) if not vertical else Vector2i(2, seam + 2)
				var tip_side := Vector2i(seam + 2, 0) if not vertical else Vector2i(0, seam + 2)
				var seal := Vector2i(seam, 0) if not vertical else Vector2i(0, seam)
				check(seam_field.is_solid(root), "Packed seal survives as a thin fin")
				check(not seam_field.is_solid(tip_side), "Seal support has a rectangular cap")
				check(seam_field.is_solid(seal), "Rounded seal opened packed adjacency")
	var config := AbyssRegionConfig.new()
	# Regression fixture stays independent of live designer seed/erosion tuning.
	config.global_seed = 85763282349367
	var routes := AbyssRouteConfig.new()
	var generator := AbyssRouteGenerator.new(config, routes)
	var registry: AbyssRoomTemplateRegistry = load("res://Scenes/Underground/Rooms/example_registry.tres")
	var selector := AbyssRoomTemplateSelector.new(registry, config.global_seed)
	var terrain := AbyssTerrainConfig.new()
	terrain.transition_blend_width = 10.0
	var field := AbyssCavernBoundaryField.new(generator, selector, terrain)
	var strong := terrain.duplicate() as AbyssTerrainConfig
	strong.boundary_warp_amplitude = 20
	var strong_field := AbyssCavernBoundaryField.new(generator, selector, strong)
	var flat := terrain.duplicate() as AbyssTerrainConfig
	flat.boundary_warp_amplitude = 0
	flat.boundary_detail_strength = 0
	var flat_field := AbyssCavernBoundaryField.new(generator, selector, flat)
	# Find a real OPEN room touching the x=0 chunk seam, then sample both chunks.
	var center := Vector2i.ZERO
	for y in range(-48, 49):
		if generator.get_room(Vector2i(0, y)).region == AbyssRoomData.Region.OPEN:
			center.y = y
			break
	var coords: Array[Vector2i] = []
	for y in range(center.y - 2, center.y + 3):
		for x in range(-3, 3):
			coords.append(Vector2i(x, y))
	var snapshots: Dictionary = {}
	var field_samples: Dictionary = {}
	var changed := 0
	var deep_changes := 0
	var seams := 0
	var openings := 0
	var authored := 0
	var isolated := 0
	var image := Image.create(6 * config.room_size.x * 2, 5 * config.room_size.y, false, Image.FORMAT_RGB8)
	for coord in coords:
		var request := selector.select_room(generator, coord)
		var room := AbyssRoomTerrainBuilder.build(request, terrain, field)
		var solid := room.get_node("Solid") as TileMapLayer
		var heavy_room := AbyssRoomTerrainBuilder.build(request, strong, strong_field)
		var heavy_solid := heavy_room.get_node("Solid") as TileMapLayer
		for opening in request.requirements.route_openings.values():
			check(heavy_solid.get_cell_source_id(opening) == -1, "High warp blocked required opening")
		heavy_room.free()
		var cells := solid.get_used_cells()
		cells.sort()
		snapshots[coord] = cells
		if request.method == AbyssRoomConstructionRequest.Method.AUTHORED:
			authored += 1
			var original := AbyssRoomSceneInstantiator.instantiate_authored(request)
			for name_value in ["Solid", "Platforms", "Decorations", "ConditionalWalls"]:
				check(room.get_node(name_value).tile_map_data == original.get_node(name_value).tile_map_data, "Authored tiles changed")
			original.free()
		for opening in request.requirements.route_openings.values():
			openings += 1
			check(solid.get_cell_source_id(opening) == -1, "Required opening blocked")
		# All packed ports still belong to one traversable tile component.
		if request.requirements.region == AbyssRoomData.Region.PACKED and not request.requirements.required_openings.is_empty():
			var pending: Array[Vector2i] = [request.requirements.required_openings.values()[0]]
			var reached: Dictionary = {}
			while not pending.is_empty():
				var cell: Vector2i = pending.pop_back()
				if reached.has(cell) or not Rect2i(Vector2i.ZERO, config.room_size).has_point(cell) or solid.get_cell_source_id(cell) != -1:
					continue
				reached[cell] = true
				for direction in AbyssRegionGenerator.DIRECTIONS:
					pending.append(cell + direction)
			for opening in request.requirements.required_openings.values():
				check(reached.has(opening), "Deformation disconnected tunnel")
		for y in range(config.room_size.y):
			for x in range(config.room_size.x):
				var local := Vector2i(x,y)
				var tile := coord * config.room_size + local
				if request.method != AbyssRoomConstructionRequest.Method.AUTHORED and solid.get_cell_source_id(local) != -1:
					var neighbors := 0
					for direction in AbyssRegionGenerator.DIRECTIONS:
						var adjacent := local + direction
						neighbors += int(solid.get_cell_source_id(adjacent) != -1) if Rect2i(Vector2i.ZERO, config.room_size).has_point(adjacent) else int(field.is_solid(tile + direction))
					if neighbors == 0:
						isolated += 1
				field_samples[tile] = field.is_solid(tile)
				if strong_field.is_solid(tile) != flat_field.is_solid(tile):
					changed += 1
					if local.x > 4 and local.x < 19 and local.y > 4 and local.y < 19:
						deep_changes += 1
				var pixel := (coord - Vector2i(-3, center.y - 2)) * config.room_size + local
				image.set_pixelv(pixel, Color("4c627d") if flat_field.is_solid(tile) else Color("0c1420"))
				image.set_pixelv(pixel + Vector2i(6 * config.room_size.x, 0), Color("4c627d") if strong_field.is_solid(tile) else Color("0c1420"))
				for side in range(4):
					var on_edge: bool = [y == 0, x == config.room_size.x - 1, y == config.room_size.y - 1, x == 0][side]
					if not on_edge or request.method == AbyssRoomConstructionRequest.Method.AUTHORED:
						continue
					var other := selector.select_room(generator, coord + AbyssRegionGenerator.DIRECTIONS[side])
					if request.requirements.region == AbyssRoomData.Region.PACKED and other.requirements.region == AbyssRoomData.Region.PACKED:
						check(solid.get_cell_source_id(local) != -1 or request.requirements.required_openings.values().has(local), "Undeclared packed hole")
					if request.requirements.region == AbyssRoomData.Region.OPEN and other.requirements.region == AbyssRoomData.Region.OPEN:
						check(solid.get_cell_source_id(local) == -1, "Open-open wall")
					seams += 1
		room.free()
	image.resize(image.get_width() * 3, image.get_height() * 3, Image.INTERPOLATE_NEAREST)
	image.save_png("/tmp/abyss-boundary-comparison.png")
	var reordered := AbyssRouteGenerator.new(config, routes)
	reordered.get_chunk(Vector2i(-1, 1))
	var reverse_field := AbyssCavernBoundaryField.new(reordered, selector, terrain)
	coords.reverse()
	for coord in coords:
		var room := AbyssRoomTerrainBuilder.build(selector.select_room(reordered, coord), terrain, reverse_field)
		var cells: Array[Vector2i] = room.get_node("Solid").get_used_cells()
		cells.sort()
		check(cells == snapshots[coord], "Construction order changed tiles")
		for y in range(config.room_size.y):
			for x in range(config.room_size.x):
				var tile := coord * config.room_size + Vector2i(x,y)
				check(reverse_field.is_solid(tile) == field_samples[tile], "Global field seam/order mismatch")
		room.free()
	# Exercise procedural OPEN construction too: the default library often
	# selects authored OPEN rooms, which intentionally bypass deformation.
	var empty_selector := AbyssRoomTemplateSelector.new(AbyssRoomTemplateRegistry.new(), config.global_seed)
	var fallback_field := AbyssCavernBoundaryField.new(generator, empty_selector, strong)
	for y in range(center.y - 1, center.y + 2):
		for x in range(-1, 2):
			var coord := Vector2i(x,y)
			var request := empty_selector.select_room(generator, coord)
			var room := AbyssRoomTerrainBuilder.build(request, strong, fallback_field)
			var solid := room.get_node("Solid") as TileMapLayer
			for opening in request.requirements.route_openings.values():
				check(solid.get_cell_source_id(opening) == -1, "Procedural OPEN/packed route blocked")
			room.free()
	check(isolated == 0, "Isolated procedural terrain tile")
	print("Isolated procedural tiles: ", isolated)
	check(changed > 100 and deep_changes > 10, "Warp amplitude has insufficient large-scale effect")
	print("Cavern boundaries: 30 rooms; %d changed tiles (%d deep); %d interface checks; %d ports; %d authored; %d failures" % [changed, deep_changes, seams, openings, authored, failures])
	quit(0 if failures == 0 else 1)
