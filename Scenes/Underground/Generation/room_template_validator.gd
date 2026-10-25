class_name AbyssRoomTemplateValidator
extends RefCounted
## Structural/boundary authoring checks only; not traversal or physics simulation.
static func validate(metadata: AbyssRoomTemplateMetadata) -> PackedStringArray:
	var errors := PackedStringArray()
	if metadata.room_size.x < 3 or metadata.room_size.y < 3 or metadata.opening_combinations.is_empty():
		errors.append("Missing combinations or invalid room dimensions")
		return errors
	if not is_finite(metadata.conditional_wall_probability) or metadata.conditional_wall_probability < 0.0 or metadata.conditional_wall_probability > 1.0:
		errors.append("Conditional wall probability must be finite and within [0, 1]")
	var variants: Dictionary = {}
	for profile in metadata.opening_combinations:
		if profile == null:
			errors.append("Null opening combination")
			continue
		if profile.variant_id == &"" or variants.has(profile.variant_id):
			errors.append("Missing/duplicate variant ID")
		variants[profile.variant_id] = true
		var scene := profile.scene if profile.scene != null else metadata.scene
		if scene == null:
			errors.append("Missing scene")
			continue
		var instance := scene.instantiate()
		if not instance is AbyssAuthoredRoom:
			errors.append("Scene root must use authored_room.gd")
			instance.free()
			continue
		var room := instance as AbyssAuthoredRoom
		if room.room_size != metadata.room_size or room.tile_pixels != metadata.tile_pixels or room.tile_pixels <= 0:
			errors.append("Scene/metadata dimensions or tile scale differ")
		if room.scale != Vector2.ONE or not is_zero_approx(room.rotation):
			errors.append("Room root must use identity rotation/scale")
		var layers: Array[TileMapLayer] = []
		for name_value in ["Solid", "Platforms", "Decorations"]:
			var layer := room.get_node_or_null(NodePath(name_value)) as TileMapLayer
			if layer == null or layer.tile_set == null:
				errors.append("Missing TileMapLayer/TileSet: " + name_value)
			else:
				layers.append(layer)
				if layer.tile_set.tile_size != Vector2i.ONE * room.tile_pixels or layer.position != Vector2.ZERO or layer.scale != Vector2.ONE or not is_zero_approx(layer.rotation):
					errors.append("Layers must use matching tile size and identity local transform")
				for cell in layer.get_used_cells():
					if not Rect2i(Vector2i.ZERO, metadata.room_size).has_point(cell):
						errors.append("Tile outside local room bounds")
		if layers.size() == 3:
			if not layers[0].collision_enabled or layers[2].collision_enabled:
				errors.append("Solid must enable collision; Decorations must disable it")
			var holes: Dictionary = {}
			if profile.opening_tiles.size() != profile.openings.size():
				errors.append("Opening IDs/coordinates differ")
			for id in profile.openings:
				var side := ["north", "east", "south", "west"].find(String(id).get_slice(":", 0))
				var slot := String(id).get_slice(":", 1)
				var cell: Vector2i = profile.opening_tiles.get(id, Vector2i(-1, -1))
				var size := metadata.room_size
				var on_side := (side == 0 and cell.y == 0) or (side == 1 and cell.x == size.x - 1) or (side == 2 and cell.y == size.y - 1) or (side == 3 and cell.x == 0)
				if not slot in ["0", "1"] or not on_side or not Rect2i(Vector2i.ZERO, size).has_point(cell):
					errors.append("Invalid opening ID/coordinate: %s" % id)
				holes[cell] = true
			for side in range(4):
				if profile.open_sides & (1 << side):
					var limit := metadata.room_size.x if side % 2 == 0 else metadata.room_size.y
					for offset in range(1, limit - 1):
						var cell := Vector2i(offset, 0 if side == 0 else metadata.room_size.y - 1) if side % 2 == 0 else Vector2i(metadata.room_size.x - 1 if side == 1 else 0, offset)
						holes[cell] = true
			var open_region := metadata.region == AbyssRoomTemplateMetadata.Compatibility.OPEN or (metadata.region == AbyssRoomTemplateMetadata.Compatibility.TRANSITION and metadata.transition_base_region == AbyssRoomData.Region.OPEN)
			if open_region and (profile.open_sides != 15 or not profile.openings.is_empty()):
				errors.append("OPEN rooms require all faces open")
			for y in range(metadata.room_size.y):
				for x in range(metadata.room_size.x):
					if x != 0 and y != 0 and x != metadata.room_size.x - 1 and y != metadata.room_size.y - 1:
						continue
					var cell := Vector2i(x, y)
					var should_open := open_region or holes.has(cell)
					if should_open:
						if _has_collision(layers[0], cell) or _has_collision(layers[1], cell):
							errors.append("Blocked declared opening at %s" % cell)
					elif not _has_solid_collision(layers[0], cell):
						errors.append("Undeclared boundary hole at %s" % cell)
		errors.append_array(_validate_conditional(room, metadata))
		errors.append_array(AbyssRoomFeatureValidator.validate(room,metadata,profile))
		room.free()
	return errors


static func _has_collision(layer: TileMapLayer, cell: Vector2i) -> bool:
	var data := layer.get_cell_tile_data(cell)
	if data == null:
		return false
	for i in range(layer.tile_set.get_physics_layers_count()):
		if data.get_collision_polygons_count(i) > 0:
			return true
	return false


static func _has_solid_collision(layer: TileMapLayer, cell: Vector2i) -> bool:
	var data := layer.get_cell_tile_data(cell)
	if data == null:
		return false
	for i in range(layer.tile_set.get_physics_layers_count()):
		for polygon in range(data.get_collision_polygons_count(i)):
			if not data.is_collision_polygon_one_way(i, polygon):
				return true
	return false


static func _validate_conditional(room: AbyssAuthoredRoom, metadata: AbyssRoomTemplateMetadata) -> PackedStringArray:
	var errors := PackedStringArray()
	var bounds := Rect2i(Vector2i.ZERO, metadata.room_size)
	for rect in room.reserved_route_rects:
		if rect.size.x <= 0 or rect.size.y <= 0 or not bounds.encloses(rect):
			errors.append("Reserved route rectangles must be positive and inside the room")
	var layer := room.get_node_or_null("ConditionalWalls") as TileMapLayer
	if layer == null:
		return errors # Compatibility with scenes authored before this optional layer.
	if layer.tile_set == null:
		errors.append("ConditionalWalls requires a TileSet")
		return errors
	if not layer.collision_enabled or layer.tile_set.tile_size != Vector2i.ONE * room.tile_pixels or layer.position != Vector2.ZERO or layer.scale != Vector2.ONE or not is_zero_approx(layer.rotation):
		errors.append("ConditionalWalls requires solid collision, matching tile size and identity transform")
	for cell in layer.get_used_cells():
		if not bounds.has_point(cell) or cell.x == 0 or cell.y == 0 or cell.x == metadata.room_size.x - 1 or cell.y == metadata.room_size.y - 1:
			errors.append("Conditional walls must be strictly inside the room: %s" % cell)
		if not _has_solid_collision(layer, cell):
			errors.append("Conditional wall tiles require non-one-way solid collision: %s" % cell)
		for rect in room.reserved_route_rects:
			if rect.has_point(cell):
				errors.append("Conditional wall overlaps reserved route: %s" % cell)
		for key in ["Solid", "Platforms"]:
			var permanent := room.get_node_or_null(NodePath(key)) as TileMapLayer
			if permanent != null and permanent.get_cell_source_id(cell) != -1:
				errors.append("Conditional wall overlaps permanent geometry: %s" % cell)
	return errors
