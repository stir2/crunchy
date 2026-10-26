class_name AbyssSpecialRoomConstruction
extends RefCounted
const TILES = preload("res://Assets/Tiles/room_placeholders.tres")
static func _blocked(room: AbyssAuthoredRoom, cell: Vector2i) -> bool:
	if not Rect2i(Vector2i.ZERO,room.room_size).has_point(cell):
		return true
	for key in ["Solid","ConditionalWalls","BreakableWalls","Platforms","ConditionalPlatforms","Climbables"]:
		var layer := room.get_node_or_null(NodePath(key)) as TileMapLayer
		if layer != null and layer.collision_enabled and AbyssRoomTemplateValidator._has_collision(layer,cell):
			return true
	return false
static func _clear(room: AbyssAuthoredRoom, cell: Vector2i) -> bool:
	for y in range(-2,1):
		for x in range(2):
			if _blocked(room,cell+Vector2i(x,y)):
				return false
	return true
static func spawn_area_clear(room: AbyssAuthoredRoom, point: Vector2) -> bool:
	var start := (point-Vector2(1,1.5)*room.tile_pixels)/room.tile_pixels
	var end := (point+Vector2(1,1.5)*room.tile_pixels)/room.tile_pixels
	for y in range(floori(start.y),ceili(end.y)):
		for x in range(floori(start.x),ceili(end.x)):
			if _blocked(room,Vector2i(x,y)):
				return false
	return true
static func _position(room: AbyssAuthoredRoom, kind: StringName) -> Vector2:
	for marker in AbyssRoomContent.markers(room):
		if marker.kind() == kind:
			var point := AbyssRoomContent.local_transform(marker,room).origin
			if spawn_area_clear(room,point):
				return point
	# Prefer an existing landing surface with 2x3 free cells. Never carve or
	# insert terrain into authored layouts or guaranteed corridors.
	var fallback := Vector2(-1,-1)
	for y in range(3,room.room_size.y-2):
		for x in range(2,room.room_size.x-3):
			var cell := Vector2i(x,y)
			if _clear(room,cell):
				var point := (Vector2(cell)+Vector2(1,-0.5))*room.tile_pixels
				if fallback.x < 0:
					fallback = point
				if _blocked(room,cell+Vector2i.DOWN) and _blocked(room,cell+Vector2i(1,1)):
					return point
	# Collectibles are nonblocking and can occupy narrow authored corridors;
	# they do not require a future player's checkpoint spawn footprint.
	if fallback.x < 0 and kind == &"fragment":
		for y in range(1,room.room_size.y-1):
			for x in range(1,room.room_size.x-1):
				if not _blocked(room,Vector2i(x,y)):
					return (Vector2(x,y)+Vector2(0.5,0.5))*room.tile_pixels
	return fallback
static func apply(room: AbyssAuthoredRoom, request: AbyssRoomConstructionRequest, service: AbyssSpecialRooms) -> void:
	var coords := request.requirements.global_coords
	var level := service.level_at(coords)
	if level == 0:
		return
	for definition in service.definitions_at(coords):
		var point := _position(room,definition.kind)
		if definition.kind == "gate":
			point = Vector2(room.room_size.x-0.5,room.room_size.y/2+0.5)*room.tile_pixels
		if point.x < 0:
			room.content_warnings.append("No clear special marker position: " + definition.id)
			continue
		var spawn := AbyssSpecialSpawnRequest.new()
		spawn.kind = StringName(definition.kind)
		spawn.marker_id = StringName(definition.id)
		spawn.room_coords = coords
		spawn.local_position = point
		spawn._room = weakref(room)
		spawn._initial_world_position = room.position + point
		spawn.selected = true
		spawn.definition = definition.duplicate(true)
		spawn.definition["spawn_x"] = spawn._initial_world_position.x
		spawn.definition["spawn_y"] = spawn._initial_world_position.y
		spawn.progression = service
		room.spawn_requests.append(spawn)
		if spawn.should_spawn():
			var scene := load("res://Scenes/Underground/Progression/%s.tscn" % definition.kind) as PackedScene
			var visual := scene.instantiate() as Node2D
			visual.position = point
			visual.request = spawn
			room.add_child(visual)
	var bounds := service.config.room_bounds(level,service.routes.get_chunk(Vector2i.ZERO).config.chunk_size.x)
	# Both sides own a tile: neither side can bypass the boundary by loading
	# only one neighbor. Outer world edges are sealed as well.
	for x in [0,room.room_size.x-1]:
		if (x == 0 and coords.x != bounds.x) or (x != 0 and coords.x != bounds.y-1):
			continue
		var left := coords if x != 0 else coords + Vector2i.LEFT
		var gate := service.gate_at(left)
		var barrier := AbyssLevelBoundary.new()
		barrier.name = "LevelBoundaryWest" if x == 0 else "LevelBoundaryEast"
		barrier.tile_set = TILES
		for y in range(room.room_size.y):
			barrier.set_cell(Vector2i(x,y),0,Vector2i.ZERO)
			if not gate.is_empty() and y >= room.room_size.y/2-1 and y <= room.room_size.y/2+1:
				barrier.gate_cells.append(Vector2i(x,y))
		room.add_child(barrier)
		barrier.configure(service,gate)
