extends RefCounted
## Placement hint only: the existing progression planner authorizes the gate ID.
static func cells(room: AbyssAuthoredRoom) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var layer := room.get_node_or_null("Decorations") as TileMapLayer
	if layer == null or layer.tile_set == null or layer.tile_set.get_custom_data_layer_by_name("gate") < 0: return result
	for cell in layer.get_used_cells():
		var data := layer.get_cell_tile_data(cell)
		if data != null and data.get_custom_data("gate"): result.append(cell)
	result.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result

static func position_for(room: AbyssAuthoredRoom, cell: Vector2i) -> Vector2:
	return (Vector2(cell)+Vector2(0.5,1.0))*room.tile_pixels-Vector2(0,56)

static func validate(metadata: AbyssRoomTemplateMetadata) -> PackedStringArray:
	var errors := PackedStringArray()
	for profile in metadata.opening_combinations:
		if profile == null: continue
		var scene := profile.scene if profile.scene != null else metadata.scene
		if scene == null: continue
		var instance := scene.instantiate()
		if not instance is AbyssAuthoredRoom:
			instance.free()
			continue
		var room := instance as AbyssAuthoredRoom
		var painted := cells(room)
		if not painted.is_empty():
			var region := int(metadata.transition_base_region) if metadata.region == AbyssRoomTemplateMetadata.Compatibility.TRANSITION else int(metadata.region)
			if region != AbyssRoomData.Region.PACKED: errors.append("Gate placement tiles belong in PACKED rooms")
			if painted.size() != 1: errors.append("Use one gate placement tile per room")
			for cell in painted:
				var rect := Rect2(position_for(room,cell)-Vector2(8,56),Vector2(16,112))
				if not Rect2(Vector2.ZERO,Vector2(room.room_size*room.tile_pixels)).encloses(rect): errors.append("Gate door must fit inside the room")
		room.free()
	return errors
