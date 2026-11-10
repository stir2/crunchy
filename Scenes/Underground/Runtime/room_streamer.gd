class_name AbyssRoomStreamer
extends Node
## Room instances over deterministic chunk planning. Only derived caches are evicted.
signal room_loaded(coords: Vector2i)
signal room_unloaded(coords: Vector2i)
@export_range(1, 8) var load_radius: int = 2
@export_range(2, 10) var unload_radius: int = 4
@export_range(1, 8) var rooms_per_frame: int = 1
@export_range(0.1, 20.0, 0.1) var construction_budget_ms: float = 4.0
@export_range(0.0, 2.0, 0.05) var movement_lookahead_seconds: float = 0.7
var routes: AbyssRouteGenerator
var selector: AbyssRoomTemplateSelector
var boundary: AbyssCavernBoundaryField
var specials: AbyssSpecialRooms
var mutations: AbyssRoomState
var rooms: Dictionary[Vector2i, AbyssAuthoredRoom] = {}
var current_room: Vector2i
var active: bool = false
var player: Player
var camera: AbyssAxisFollowCamera
var container: Node2D
var runtime: Node
var terrain_config: AbyssTerrainConfig
var room_pixels: Vector2
var _room_size: Vector2i
var deferred_templates: PackedStringArray = []
var _pending: Array[Vector2i] = []
var _settling: Dictionary[Vector2i, int] = {}
var _required: Dictionary[Vector2i, bool] = {}
var _last_plan: String = ""
var _preparing: bool = false
var _preparing_coords: Vector2i
var _preparing_row: int = 0
var _cache_chunk := Vector2i(2147483647,2147483647)

func _ready() -> void:
	process_physics_priority = -100 # Guard motion before Player physics.

func configure(region: AbyssRegionConfig, route: AbyssRouteConfig, terrain: AbyssTerrainConfig, progression: AbyssProgressionConfig, registry: AbyssRoomTemplateRegistry, state: AbyssRoomState, progression_state: AbyssProgressionState) -> bool:
	routes = AbyssRouteGenerator.new(region,route,progression)
	specials = AbyssSpecialRooms.new(routes,progression,progression_state)
	selector = AbyssRoomTemplateSelector.new(registry,region.global_seed)
	selector.checkpoint_planner = specials
	if not selector.registration_errors.is_empty():
		push_error("Runtime room registry: " + "; ".join(selector.registration_errors))
		return false
	deferred_templates.clear()
	for metadata in registry.all_templates():
		if metadata.room_size != region.room_size or metadata.opening_schema != route.opening_schema or metadata.opening_width != route.opening_width:
			deferred_templates.append(String(metadata.template_id))
	_cache_chunk = Vector2i(2147483647,2147483647)
	terrain_config = terrain
	mutations = state
	boundary = AbyssCavernBoundaryField.new(routes,selector,terrain)
	room_pixels = Vector2(region.room_size * registry.tile_pixels)
	_room_size = region.room_size
	return true

func world_to_room(point: Vector2) -> Vector2i:
	var local := container.to_local(point)
	return Vector2i(floori(local.x/room_pixels.x),floori(local.y/room_pixels.y))

func room_ready(coords: Vector2i) -> bool:
	return rooms.has(coords) and not _settling.has(coords)

func rect_rooms(rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var first := world_to_room(rect.position)
	var last := world_to_room(rect.end-Vector2(0.01,0.01))
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			result.append(Vector2i(x,y))
	return result

func is_rect_ready(rect: Rect2) -> bool:
	for coords in rect_rooms(rect):
		if not room_ready(coords):
			return false
	return true

func neighborhood_ready(center: Vector2i) -> bool:
	for y in range(center.y-load_radius,center.y+load_radius+1):
		for x in range(center.x-load_radius,center.x+load_radius+1):
			if not room_ready(Vector2i(x,y)):
				return false
	return true

func request_neighborhood(center: Vector2i, velocity: Vector2 = Vector2.ZERO) -> void:
	var wanted: Dictionary[Vector2i, bool] = {}
	for y in range(center.y-load_radius,center.y+load_radius+1):
		for x in range(center.x-load_radius,center.x+load_radius+1):
			wanted[Vector2i(x,y)] = true
	# An extra leading row/column can use the hysteresis ring before it is needed.
	var forward := Vector2i(signf(velocity.x),0) if absf(velocity.x) >= absf(velocity.y) else Vector2i(0,signf(velocity.y))
	if forward != Vector2i.ZERO:
		for side in range(-1,2):
			var lead := center + forward * (load_radius+1)
			lead += Vector2i(0,side) if absf(velocity.x) >= absf(velocity.y) else Vector2i(side,0)
			wanted[lead] = true
	for coords in _required:
		wanted[coords] = true
	if _preparing and not wanted.has(_preparing_coords):
		_preparing = false
	_pending.clear()
	for coords in wanted:
		if not rooms.has(coords) and not (_preparing and coords == _preparing_coords):
			_pending.append(coords)
	var direction := velocity.normalized()
	_pending.sort_custom(func(a: Vector2i,b: Vector2i) -> bool:
		var sa := _priority(a,center,direction)
		var sb := _priority(b,center,direction)
		return sa < sb if not is_equal_approx(sa,sb) else (a.y < b.y or (a.y == b.y and a.x < b.x)))

func _priority(coords: Vector2i, center: Vector2i, direction: Vector2) -> float:
	return (-10000.0 if _required.has(coords) else 0.0) + Vector2(coords-center).length_squared()*10.0-Vector2(coords-center).dot(direction)*4.0

func _process(_delta: float) -> void:
	if not active:
		return
	var started := Time.get_ticks_usec()
	var built := 0
	while (_preparing or not _pending.is_empty()) and built < rooms_per_frame:
		if not _preparing:
			_preparing_coords = _pending.pop_front()
			if rooms.has(_preparing_coords):
				continue
			_preparing = true
			_preparing_row = 0
			if selector.select_room(routes,_preparing_coords).method == AbyssRoomConstructionRequest.Method.AUTHORED:
				_preparing_row = _room_size.y
		var size := _room_size
		if _preparing_row < size.y:
			# Warm the same deterministic boundary cache a row at a time. The
			# synchronous builder then reads cached samples instead of doing all
			# signed-field/noise work in one frame. No partial collision is exposed.
			for x in range(size.x):
				boundary.is_solid(_preparing_coords*size+Vector2i(x,_preparing_row))
			_preparing_row += 1
		if _preparing_row >= size.y:
			var coords := _preparing_coords
			_preparing = false
			_build_room(coords)
			built += 1
		if not active or Time.get_ticks_usec()-started >= construction_budget_ms*1000.0:
			break

func _build_room(coords: Vector2i) -> void:
	var request := selector.select_room(routes,coords)
	var room := AbyssRoomTerrainBuilder.build(request,terrain_config,boundary,mutations,specials)
	if room == null:
		active = false
		runtime.fail_startup("Unable to construct room " + str(coords))
		return
	room.name = "Room_%d_%d" % [coords.x,coords.y]
	room.visible = false
	container.add_child(room)
	rooms[coords] = room
	for child in room.get_children():
		if child is TileMapLayer:
			child.update_internals()
	# Two ticks cover tilemap/server synchronization before movement or visibility.
	_settling[coords] = Engine.get_physics_frames()+2

func _physics_process(delta: float) -> void:
	if not active:
		return
	for coords in _settling.keys():
		if Engine.get_physics_frames() >= _settling[coords]:
			_settling.erase(coords)
			rooms[coords].visible = true
			room_loaded.emit(coords)
	if runtime.is_starting():
		return
	current_room = world_to_room(player.global_position)
	var velocity := player.velocity
	if player.movement_state == Player.MovementState.DASH_CHARGING:
		velocity = Vector2(player.dash_direction*player.dash_speed,0)
	_required.clear()
	# Cover the swept body and any viewport that can follow the next physics step.
	var predicted := player.global_position + velocity*delta
	var body_sweep := Rect2(player.global_position-Vector2(16,37),Vector2(32,38))
	body_sweep = body_sweep.expand(predicted-Vector2(16,37)).expand(predicted+Vector2(16,1))
	for coords in rect_rooms(body_sweep.grow(16)):
		_required[coords] = true
	var view_size := camera.world_view_size()
	for coords in rect_rooms(Rect2(predicted+camera.follow_offset-view_size,view_size*2.0)):
		_required[coords] = true
	if camera.enabled:
		for coords in rect_rooms(camera.view_rect(camera.global_position).grow(16)):
			_required[coords] = true
	var lead := world_to_room(player.global_position + velocity.limit_length(room_pixels.length()*2.0)*movement_lookahead_seconds)
	var plan := "%s/%s/%s" % [current_room,lead,_required.keys()]
	if plan != _last_plan:
		_last_plan = plan
		request_neighborhood(current_room,velocity)
	var safe := true
	for coords in _required:
		if not room_ready(coords):
			safe = false
			break
	runtime.set_streaming_hold(not safe)
	_unload_distant()
	var chunk := routes.regions.room_to_chunk(current_room)
	if chunk != _cache_chunk and _pending.is_empty() and not _preparing and _settling.is_empty():
		_cache_chunk = chunk
		var chunk_bounds := Rect2i(chunk-Vector2i(2,2),Vector2i(5,5))
		var cache_radius := maxi(load_radius+6,specials.config.checkpoint_min_spacing_rooms+load_radius+3)
		var room_bounds := Rect2i(current_room-Vector2i.ONE*cache_radius,Vector2i.ONE*(cache_radius*2+1))
		boundary.retain_cached_rooms(room_bounds)
		specials.retain_cached_rooms(room_bounds)
		routes.retain_cached_chunks(chunk_bounds)

func _unload_distant() -> void:
	for coords in rooms.keys():
		var distance := maxi(absi(coords.x-current_room.x),absi(coords.y-current_room.y))
		if distance > maxi(unload_radius,load_radius+1) and not _required.has(coords):
			unload_room(coords)

func unload_room(coords: Vector2i) -> bool:
	if coords == current_room or coords == world_to_room(player.global_position):
		return false
	if rooms.has(coords):
		var room := rooms[coords]
		rooms.erase(coords)
		_settling.erase(coords)
		container.remove_child(room)
		room.queue_free()
		room_unloaded.emit(coords)
	return true

func clear_rooms() -> void:
	_preparing = false
	for room in rooms.values():
		container.remove_child(room)
		room.queue_free()
	rooms.clear()
	_settling.clear()
	_pending.clear()
	_required.clear()
	_last_plan = ""
