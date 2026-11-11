extends RefCounted
## Painted placement data only. The existing planner still decides checkpoint rooms.
static func cells(room: AbyssAuthoredRoom) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var layer := room.get_node_or_null("Decorations") as TileMapLayer
	if layer == null or layer.tile_set == null or layer.tile_set.get_custom_data_layer_by_name("checkpoint") < 0: return result
	for cell in layer.get_used_cells():
		var data := layer.get_cell_tile_data(cell)
		if data != null and data.get_custom_data("checkpoint"): result.append(cell)
	result.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result

static func position_for(room: AbyssAuthoredRoom, cell: Vector2i) -> Vector2:
	# Tile bottom is the art's baseline; interaction point is 24px above it.
	return (Vector2(cell)+Vector2(0.5,1.0))*room.tile_pixels-Vector2(0,24)

static func validate(metadata: AbyssRoomTemplateMetadata) -> PackedStringArray:
	var errors := PackedStringArray()
	if metadata.region not in [AbyssRoomTemplateMetadata.Compatibility.OPEN, AbyssRoomTemplateMetadata.Compatibility.PACKED]:
		errors.append("Checkpoint pool rooms must be OPEN or PACKED")
	for profile in metadata.opening_combinations:
		if profile == null: continue
		var scene := profile.scene if profile.scene != null else metadata.scene
		if scene == null: continue
		var instance := scene.instantiate()
		if not instance is AbyssAuthoredRoom:
			instance.free()
			continue # General template validation reports the root error.
		var room := instance as AbyssAuthoredRoom
		var painted := cells(room)
		if painted.size() != 1:
			errors.append("Checkpoint pool rooms require exactly one checkpoint tile on Decorations")
		elif not _clear(room,position_for(room,painted[0])):
			errors.append("Checkpoint tile needs a clear 32x48 interaction area above its baseline")
		room.free()
	return errors

static func _clear(room: AbyssAuthoredRoom, point: Vector2) -> bool:
	var start := (point-Vector2(16,24))/room.tile_pixels
	var end := (point+Vector2(16,24))/room.tile_pixels
	for y in range(floori(start.y),ceili(end.y)):
		for x in range(floori(start.x),ceili(end.x)):
			var cell := Vector2i(x,y)
			if not Rect2i(Vector2i.ZERO,room.room_size).has_point(cell): return false
			for key in ["Solid","ConditionalWalls","BreakableWalls","Platforms","ConditionalPlatforms","Climbables"]:
				var layer := room.get_node_or_null(NodePath(key)) as TileMapLayer
				if layer != null and layer.collision_enabled and AbyssRoomTemplateValidator._has_collision(layer,cell): return false
	return true
