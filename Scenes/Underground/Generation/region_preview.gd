extends Node2D
## Finite logical region/route visualization. Cyan = OPEN, slate = PACKED.
@export var configuration: AbyssRegionConfig = AbyssRegionConfig.new()
@export var preview_origin: Vector2i = Vector2i(0, 0)
@export_range(1, 16) var preview_width_chunks: int = 4
@export_range(1, 16) var preview_height_chunks: int = 3
@export var show_classifications: bool = true
@export_range(0.0, 1.0) var classification_opacity: float = 0.25
@export var show_room_grid: bool = true
@export var show_chunk_grid: bool = false
@export var route_configuration: AbyssRouteConfig = AbyssRouteConfig.new()
@export var show_main_route: bool = true
@export var show_main_chunks: bool = false
@export var show_access_routes: bool = true
@export var show_branches: bool = true
@export var show_reconnections: bool = true
@export var show_boundary_connections: bool = false
@export var show_boundary_contracts: bool = false
@export var show_packed_openings: bool = false
@export var show_template_selection: bool = false
@export var template_registry: AbyssRoomTemplateRegistry = preload("res://Scenes/Underground/Rooms/example_registry.tres")
@export var show_terrain: bool = false
@export var terrain_configuration: AbyssTerrainConfig = AbyssTerrainConfig.new()
@export var enable_progression: bool = true
@export var progression_configuration: AbyssProgressionConfig = AbyssProgressionConfig.new()
@export var show_special_rooms: bool = true
var special_rooms: AbyssSpecialRooms
var room_state: AbyssRoomState
var _terrain: Node2D
var _boundary: AbyssCavernBoundaryField
@export var show_original_boundaries: bool = false
@export var show_final_boundaries: bool = false
var construction_statistics: Dictionary = {}
var _construction_requests: Dictionary[Vector2i, AbyssRoomConstructionRequest] = {}
var route_generator: AbyssRouteGenerator
var generator: AbyssRegionGenerator
var _room_count: Vector2i
var _first_room: Vector2i
const TILE_PIXELS := 8
@onready var _tiles: TileMapLayer = $ClassificationTiles


func _ready() -> void:
	regenerate()
	get_viewport().size_changed.connect(_fit_preview)


func regenerate() -> void:
	if is_instance_valid(_terrain):
		remove_child(_terrain)
		_terrain.free()
	_boundary = null
	construction_statistics = {"authored": 0, "procedural": 0, "solid_tiles": 0, "platform_tiles": 0, "conditional_tiles": 0}
	if room_state == null:
		room_state = GameController.abyss_room_state
	_tiles.clear()
	_construction_requests.clear()
	if template_registry == null:
		template_registry = AbyssRoomTemplateRegistry.new()
	if terrain_configuration == null:
		terrain_configuration = AbyssTerrainConfig.new()
	if configuration == null or not configuration.is_valid():
		push_error("Invalid abyss preview configuration")
		return
	if route_configuration == null or not route_configuration.is_valid(configuration.room_size):
		push_error("Invalid abyss route configuration")
		return
	if enable_progression and (progression_configuration == null or not progression_configuration.is_valid()):
		push_error("Invalid abyss progression configuration")
		return
	route_generator = AbyssRouteGenerator.new(configuration, route_configuration, progression_configuration if enable_progression else null)
	special_rooms = AbyssSpecialRooms.new(route_generator,progression_configuration,GameController.abyss_progression_state) if enable_progression else null
	generator = route_generator.regions
	_tiles.tile_set = _make_debug_tileset()
	_tiles.collision_enabled = false
	_tiles.show_behind_parent = true
	_tiles.visible = show_classifications and not show_terrain
	_tiles.modulate.a = classification_opacity
	_room_count = Vector2i(preview_width_chunks, preview_height_chunks) * configuration.chunk_size
	_first_room = preview_origin * configuration.chunk_size
	for cy in range(preview_origin.y, preview_origin.y + preview_height_chunks):
		for cx in range(preview_origin.x, preview_origin.x + preview_width_chunks):
			for room in route_generator.get_chunk(Vector2i(cx, cy)).rooms:
				var tile_origin := room.global_coords * configuration.room_size
				var atlas := Vector2i(0 if room.region == AbyssRoomData.Region.OPEN else 1, 0)
				for y in range(configuration.room_size.y):
					for x in range(configuration.room_size.x):
						_tiles.set_cell(tile_origin + Vector2i(x, y), 0, atlas)
	if (show_template_selection or show_terrain) and template_registry != null:
		var selector := AbyssRoomTemplateSelector.new(template_registry, configuration.global_seed)
		for error in selector.registration_errors:
			push_warning("Room template registration: " + error)
		for cy in range(preview_origin.y, preview_origin.y + preview_height_chunks):
			for cx in range(preview_origin.x, preview_origin.x + preview_width_chunks):
				for room in route_generator.get_chunk(Vector2i(cx, cy)).rooms:
					_construction_requests[room.global_coords] = selector.select_room(route_generator, room.global_coords)
	if show_terrain:
		_boundary = AbyssCavernBoundaryField.new(route_generator, AbyssRoomTemplateSelector.new(template_registry, configuration.global_seed), terrain_configuration)
		_terrain = Node2D.new()
		_terrain.name = "PhysicalChunks"
		# The debug canvas uses 8px tiles; physical content retains its 16px grid.
		_terrain.scale = Vector2.ONE * float(TILE_PIXELS) / template_registry.tile_pixels
		_terrain.show_behind_parent = true
		add_child(_terrain)
		for cy in range(preview_origin.y, preview_origin.y + preview_height_chunks):
			for cx in range(preview_origin.x, preview_origin.x + preview_width_chunks):
				var coords := Vector2i(cx, cy)
				var chunk := Node2D.new()
				chunk.name = "Chunk_%d_%d" % [cx, cy]
				chunk.position = Vector2(coords * configuration.chunk_size * configuration.room_size * template_registry.tile_pixels)
				_terrain.add_child(chunk)
				for data in route_generator.get_chunk(coords).rooms:
					var request: AbyssRoomConstructionRequest = _construction_requests[data.global_coords]
					var room := AbyssRoomTerrainBuilder.build(request, terrain_configuration, _boundary, room_state, special_rooms)
					chunk.add_child(room)
					room.terrain_changed.connect(queue_redraw)
					room.position -= chunk.position
					var key := "authored" if request.method == AbyssRoomConstructionRequest.Method.AUTHORED else "procedural"
					construction_statistics[key] += 1
					construction_statistics.solid_tiles += room.get_node("Solid").get_used_cells().size()
					var conditional := room.get_node_or_null("ConditionalWalls") as TileMapLayer
					if conditional != null:
						construction_statistics.conditional_tiles += conditional.get_used_cells().size()
					construction_statistics.platform_tiles += room.get_node("Platforms").get_used_cells().size()
		print("Abyss construction: ", construction_statistics)
	_fit_preview()
	queue_redraw()


func _make_debug_tileset() -> TileSet:
	var image := Image.create(TILE_PIXELS * 2, TILE_PIXELS, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(0, 0, TILE_PIXELS, TILE_PIXELS), Color("66d9df"))
	image.fill_rect(Rect2i(TILE_PIXELS, 0, TILE_PIXELS, TILE_PIXELS), Color("34445e"))
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = Vector2i(TILE_PIXELS, TILE_PIXELS)
	atlas.create_tile(Vector2i.ZERO)
	atlas.create_tile(Vector2i.RIGHT)
	var result := TileSet.new()
	result.tile_size = Vector2i(TILE_PIXELS, TILE_PIXELS)
	result.add_source(atlas, 0)
	return result


func _fit_preview() -> void:
	if _room_count == Vector2i.ZERO:
		return
	var viewport_size := get_viewport_rect().size
	var pixel_size := Vector2(_room_count * configuration.room_size * TILE_PIXELS)
	var available := Vector2(maxf(viewport_size.x - 360.0, 100.0), maxf(viewport_size.y - 80.0, 100.0))
	var fit := minf(available.x / pixel_size.x, available.y / pixel_size.y)
	scale = Vector2.ONE * fit
	position = Vector2(330, 40) - Vector2(_first_room * configuration.room_size * TILE_PIXELS) * fit


func _draw() -> void:
	if _room_count == Vector2i.ZERO:
		return
	var step := configuration.room_size * TILE_PIXELS
	var start := Vector2(_first_room * step)
	var extent := Vector2(_room_count * step)
	for x in range(_room_count.x + 1):
		var chunk_line := x % configuration.chunk_size.x == 0
		if (chunk_line and show_chunk_grid) or show_room_grid:
			var color := Color(0.65, 0.7, 0.8, 0.55) if chunk_line and show_chunk_grid else Color(0.55, 0.6, 0.7, 0.16)
			if chunk_line and show_chunk_grid:
				draw_dashed_line(start + Vector2(x * step.x, 0), start + Vector2(x * step.x, extent.y), color, 1.0, 8.0)
			else:
				draw_line(start + Vector2(x * step.x, 0), start + Vector2(x * step.x, extent.y), color, 1.0)
	for y in range(_room_count.y + 1):
		var chunk_line := y % configuration.chunk_size.y == 0
		if (chunk_line and show_chunk_grid) or show_room_grid:
			var color := Color(0.65, 0.7, 0.8, 0.55) if chunk_line and show_chunk_grid else Color(0.55, 0.6, 0.7, 0.16)
			if chunk_line and show_chunk_grid:
				draw_dashed_line(start + Vector2(0, y * step.y), start + Vector2(extent.x, y * step.y), color, 1.0, 8.0)
			else:
				draw_line(start + Vector2(0, y * step.y), start + Vector2(extent.x, y * step.y), color, 1.0)

	_draw_boundary_overlays()
	_draw_routes()
	_draw_special_rooms()


func _draw_routes() -> void:
	if route_generator == null:
		return
	var step := Vector2(configuration.room_size * TILE_PIXELS)
	var enabled := [show_main_route, show_access_routes, show_branches, show_reconnections]
	var colors := [Color("ffed70"), Color("b4acff"), Color("ff9955"), Color("ff60cf")]
	for cy in range(preview_origin.y, preview_origin.y + preview_height_chunks):
		for cx in range(preview_origin.x, preview_origin.x + preview_width_chunks):
			if show_main_chunks and route_generator.is_main_chunk(Vector2i(cx, cy)):
				var origin := Vector2(Vector2i(cx, cy) * configuration.chunk_size) * step
				var size := Vector2(configuration.chunk_size) * step
				draw_rect(Rect2(origin, size), Color(1.0, 0.88, 0.3, 0.09))
			if show_boundary_contracts:
				for contract in route_generator.boundary_contracts(Vector2i(cx, cy)):
					var point := (Vector2(contract.a + contract.b) * 0.5 + Vector2(0.5, 0.5)) * step
					draw_rect(Rect2(point - Vector2(7, 7), Vector2(14, 14)), Color("55ddff"), false, 2.0)
			for room in route_generator.get_chunk(Vector2i(cx, cy)).rooms:
				var center := (Vector2(room.global_coords) + Vector2(0.5, 0.5)) * step
				if show_template_selection and _construction_requests.has(room.global_coords):
					var request: AbyssRoomConstructionRequest = _construction_requests[room.global_coords]
					var authored := request.method == AbyssRoomConstructionRequest.Method.AUTHORED
					draw_string(ThemeDB.fallback_font, center + Vector2(8, -8), "A" if authored else "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("9bf5b1") if authored else Color("ffd08a"))
				for connection in room.required_connections:
					var target := (Vector2(connection.neighbor) + Vector2(0.5, 0.5)) * step
					# Half edges keep overlays inside the finite preview, including seams.
					if enabled[connection.kind]:
						draw_line(center, (center + target) * 0.5, colors[connection.kind], 4.0)
					var crosses := generator.room_to_chunk(connection.neighbor) != room.chunk_coords
					if crosses and show_boundary_connections:
						draw_circle((center + target) * 0.5, 5.0, Color.WHITE)
					if show_packed_openings and room.region == AbyssRoomData.Region.PACKED:
						var tile := Vector2(room.global_coords * configuration.room_size + connection.opening_tile) + Vector2(0.5, 0.5)
						draw_circle(tile * TILE_PIXELS, 5.0, Color("ff5555"))


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_B:
				show_original_boundaries = not show_original_boundaries
				queue_redraw()
			KEY_F:
				show_final_boundaries = not show_final_boundaries
				queue_redraw()
			KEY_T:
				show_terrain = not show_terrain
				regenerate()
			KEY_G:
				show_room_grid = not show_room_grid
				queue_redraw()
			KEY_O:
				show_packed_openings = not show_packed_openings
				queue_redraw()
			KEY_R:
				var enabled := not show_main_route
				show_main_route = enabled
				show_access_routes = enabled
				show_branches = enabled
				show_reconnections = enabled
				queue_redraw()
			KEY_A:
				show_template_selection = not show_template_selection
				regenerate()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var factor := 1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2
			var anchor: Vector2 = event.position
			position = anchor + (position - anchor) * factor
			scale *= factor
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		position += event.relative


func _draw_boundary_overlays() -> void:
	if show_original_boundaries and generator != null:
		var step := configuration.room_size * TILE_PIXELS
		for y in range(_first_room.y, _first_room.y + _room_count.y):
			for x in range(_first_room.x, _first_room.x + _room_count.x):
				var coords := Vector2i(x, y)
				var room := generator.get_room(coords)
				var origin := Vector2(coords * step)
				if room.boundary_mask & 1:
					draw_line(origin, origin + Vector2(step.x, 0), Color.CYAN, 2.0)
				if room.boundary_mask & 8:
					draw_line(origin, origin + Vector2(0, step.y), Color.CYAN, 2.0)
	if show_final_boundaries and show_terrain and is_instance_valid(_terrain):
		var occupied: Dictionary = {}
		for chunk in _terrain.get_children():
			for room in chunk.get_children():
				var origin: Vector2i = room.construction_requirements.global_coords * configuration.room_size
				for key in ["Solid", "ConditionalWalls", "BreakableWalls"]:
					var layer := room.get_node_or_null(NodePath(key)) as TileMapLayer
					if layer != null:
						for cell in layer.get_used_cells():
							occupied[origin + cell] = true
		for cell in occupied:
			var origin := Vector2(cell * TILE_PIXELS)
			for side in range(4):
				if occupied.has(cell + AbyssRegionGenerator.DIRECTIONS[side]):
					continue
				var a: Vector2 = [Vector2.ZERO, Vector2(TILE_PIXELS, 0), Vector2(TILE_PIXELS, TILE_PIXELS), Vector2(0, TILE_PIXELS)][side]
				var b: Vector2 = [Vector2(TILE_PIXELS, 0), Vector2(TILE_PIXELS, TILE_PIXELS), Vector2(0, TILE_PIXELS), Vector2.ZERO][side]
				draw_line(origin + a, origin + b, Color.GREEN_YELLOW, 1.0)


func _draw_special_rooms() -> void:
	if not show_special_rooms or special_rooms == null:
		return
	var step := Vector2(configuration.room_size * TILE_PIXELS)
	for y in range(_first_room.y,_first_room.y + _room_count.y):
		for x in range(_first_room.x,_first_room.x + _room_count.x):
			for definition in special_rooms.definitions_at(Vector2i(x,y)):
				var color := Color.CYAN if definition.kind == "checkpoint" else (Color.GOLD if definition.kind == "fragment" else Color.ORANGE_RED)
				var point := (Vector2(x,y)+Vector2(0.5,0.5))*step
				draw_circle(point,step.x*0.15,color)
				draw_string(ThemeDB.fallback_font,point,definition.kind,HORIZONTAL_ALIGNMENT_LEFT,-1,16,color)
	for level in range(1,5):
		var x := (progression_configuration.first_chunk_x + (level-1)*progression_configuration.level_width_chunks)*configuration.chunk_size.x
		if x >= _first_room.x and x <= _first_room.x+_room_count.x:
			draw_line(Vector2(x*step.x,_first_room.y*step.y),Vector2(x*step.x,(_first_room.y+_room_count.y)*step.y),Color.ORANGE_RED,3)
