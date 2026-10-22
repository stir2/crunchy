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
	_tiles.clear()
	_construction_requests.clear()
	if configuration == null or not configuration.is_valid():
		push_error("Invalid abyss preview configuration")
		return
	if route_configuration == null or not route_configuration.is_valid(configuration.room_size):
		push_error("Invalid abyss route configuration")
		return
	route_generator = AbyssRouteGenerator.new(configuration, route_configuration)
	generator = route_generator.regions
	_tiles.tile_set = _make_debug_tileset()
	_tiles.collision_enabled = false
	_tiles.show_behind_parent = true
	_tiles.visible = show_classifications
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
	if show_template_selection and template_registry != null:
		var selector := AbyssRoomTemplateSelector.new(template_registry, configuration.global_seed)
		for error in selector.registration_errors:
			push_warning("Room template registration: " + error)
		for cy in range(preview_origin.y, preview_origin.y + preview_height_chunks):
			for cx in range(preview_origin.x, preview_origin.x + preview_width_chunks):
				for room in route_generator.get_chunk(Vector2i(cx, cy)).rooms:
					_construction_requests[room.global_coords] = selector.select_room(route_generator, room.global_coords)
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

	_draw_routes()


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
