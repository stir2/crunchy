class_name AbyssBreakableTerrain
extends RefCounted
signal damaged(group_id: String, remaining_health: float, world_position: Vector2)
signal destroyed(group_id: String, cells: Array, world_position: Vector2)
var _room: WeakRef
var _state: AbyssRoomState
var _groups: Dictionary = {}
var _by_cell: Dictionary = {}
func setup(room: AbyssAuthoredRoom, request: AbyssRoomConstructionRequest, state: AbyssRoomState, definitions: Array, protected: Dictionary) -> void:
	_room = weakref(room)
	_state = state
	var layer := room.get_node_or_null("BreakableWalls") as TileMapLayer
	if layer == null:
		return
	for definition in definitions:
		var safe := true
		for cell: Vector2i in definition.cells:
			if cell.x <= 0 or cell.y <= 0 or cell.x >= room.room_size.x - 1 or cell.y >= room.room_size.y - 1 or protected.has(cell):
				safe = false
		var key := AbyssRoomState.key(request, "breakable", definition.id)
		var health: float = state.groups.get(key, request.breakable_health)
		var group: Dictionary = definition.duplicate(true)
		group["key"] = key
		group["health"] = health
		group["protected"] = not safe
		_groups[definition.id] = group
		for cell: Vector2i in definition.cells:
			_by_cell[cell] = definition.id
			if health <= 0 or not safe:
				layer.erase_cell(cell)
		if not safe:
			room.content_warnings.append("Breakable group %s intersects a protected route; omitted" % definition.id)
func damage_at(world_position: Vector2, amount: float) -> bool:
	var room := _room.get_ref() as AbyssAuthoredRoom
	if room == null:
		return false
	var layer := room.get_node("BreakableWalls") as TileMapLayer
	var cell := layer.local_to_map(layer.transform.affine_inverse() * room.to_local(world_position))
	return damage_group(_by_cell.get(cell, ""), amount)
func damage_group(identity: String, amount: float) -> bool:
	if not is_finite(amount) or amount <= 0 or not _groups.has(identity):
		return false
	var room := _room.get_ref() as AbyssAuthoredRoom
	var group: Dictionary = _groups[identity]
	if room == null or group.health <= 0 or group.protected:
		return false
	group.health = maxf(0, group.health - amount)
	_state.groups[group.key] = group.health
	var world_position := room.to_global((Vector2(group.canonical) + Vector2(0.5,0.5)) * room.tile_pixels)
	damaged.emit(identity, group.health, world_position)
	if group.health == 0:
		for cell: Vector2i in group.cells:
			room.get_node("BreakableWalls").erase_cell(cell)
		destroyed.emit(identity, group.cells.duplicate(), world_position)
		room.terrain_changed.emit()
	return true
func groups() -> Array:
	return _groups.values().duplicate(true)

func destroy_group(identity: String) -> bool:
	return _groups.has(identity) and damage_group(identity, _groups[identity].health)

## A swing/dash may touch several cells of one group; charge it only once.
func damage_at_once(world_position: Vector2, amount: float, hit_groups: Dictionary) -> bool:
	var room := _room.get_ref() as AbyssAuthoredRoom
	if room == null:
		return false
	var layer := room.get_node("BreakableWalls") as TileMapLayer
	var cell := layer.local_to_map(layer.to_local(world_position))
	var identity: String = _by_cell.get(cell, "")
	var key := str(room.get_instance_id()) + ":" + identity
	if identity.is_empty() or hit_groups.has(key) or not damage_group(identity, amount):
		return false
	hit_groups[key] = true
	return true

func damage_in_polygon(polygon: PackedVector2Array, amount: float, hit_groups: Dictionary) -> bool:
	var room := _room.get_ref() as AbyssAuthoredRoom
	if room == null or polygon.is_empty():
		return false
	var layer := room.get_node("BreakableWalls") as TileMapLayer
	var local := PackedVector2Array()
	for point in polygon:
		local.append(layer.to_local(point))
	var bounds := Rect2(local[0], Vector2.ZERO)
	for point in local:
		bounds = bounds.expand(point)
	var first := layer.local_to_map(bounds.position)
	var last := layer.local_to_map(bounds.end)
	var touched := Rect2i(first, last-first+Vector2i.ONE).intersection(layer.get_used_rect())
	var connected := false
	var half := Vector2(layer.tile_set.tile_size)*0.5
	for y in range(touched.position.y, touched.end.y):
		for x in range(touched.position.x, touched.end.x):
			var cell := Vector2i(x,y)
			if not _by_cell.has(cell):
				continue
			var center := layer.map_to_local(cell)
			var tile := PackedVector2Array([center-half, center+Vector2(half.x,-half.y), center+half, center+Vector2(-half.x,half.y)])
			if not Geometry2D.intersect_polygons(local,tile).is_empty():
				connected = damage_at_once(layer.to_global(center),amount,hit_groups) or connected
	return connected
