class_name AbyssRoomFeatureValidator
extends RefCounted
static func validate(room: AbyssAuthoredRoom, metadata: AbyssRoomTemplateMetadata, profile: AbyssRoomOpeningProfile) -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(metadata.conditional_platform_probability) or metadata.conditional_platform_probability < 0 or metadata.conditional_platform_probability > 1:
		errors.append("Conditional platform probability must be within [0,1]")
	if not is_finite(metadata.breakable_health) or metadata.breakable_health <= 0:
		errors.append("Breakable health must be positive and finite")
	var bounds := Rect2i(Vector2i.ZERO,room.room_size)
	for rect in room.required_support_rects:
		if rect.size.x <= 0 or rect.size.y <= 0 or not bounds.encloses(rect):
			errors.append("Required support rectangles must lie inside the room")
	var req := AbyssRoomRequirements.new()
	req.room_size = room.room_size
	req.route_openings = profile.opening_tiles.duplicate()
	var protected := AbyssConditionalWallGroups.reserved_cells(room,req)
	for key in ["Climbables","ConditionalPlatforms","BreakableWalls"]:
		var layer := room.get_node_or_null(NodePath(key)) as TileMapLayer
		if layer == null:
			continue
		if layer.tile_set == null:
			errors.append("%s requires a TileSet" % key)
			continue
		if layer.tile_set.tile_size != Vector2i.ONE * room.tile_pixels or layer.position != Vector2.ZERO or layer.scale != Vector2.ONE or not is_zero_approx(layer.rotation):
			errors.append("%s requires matching tiles and identity transform" % key)
		if key != "Climbables" and not layer.collision_enabled:
			errors.append("%s must enable collision" % key)
		for cell in layer.get_used_cells():
			if not bounds.has_point(cell):
				errors.append("%s tile outside room: %s" % [key,cell])
			if key == "Climbables":
				if not AbyssClimbableTiles.is_climbable(layer,cell):
					errors.append("Climbables requires climbable custom data")
				if AbyssRoomTemplateValidator._has_collision(layer,cell) and (AbyssRoomContent._boundary(cell,room.room_size) or protected.has(cell)):
					errors.append("Colliding climbable overlaps protected boundary/route")
				continue
			if AbyssRoomContent._boundary(cell,room.room_size) or protected.has(cell):
				errors.append("%s overlaps protected opening/route; use permanent terrain/support" % key)
			for rect in room.required_support_rects:
				if rect.has_point(cell):
					errors.append("%s overlaps required support; paint a permanent platform" % key)
			if key == "BreakableWalls" and not AbyssRoomTemplateValidator._has_solid_collision(layer,cell):
				errors.append("Breakable walls require solid collision")
			if key == "ConditionalPlatforms":
				var data := layer.get_cell_tile_data(cell)
				var one_way := false
				for physics in range(layer.tile_set.get_physics_layers_count()):
					for polygon in range(data.get_collision_polygons_count(physics)):
						if not data.is_collision_polygon_one_way(physics,polygon):
							errors.append("Conditional platforms require only one-way collision")
						one_way = true
				if not one_way:
					errors.append("Conditional platform missing one-way collision")
			for other_key in ["Solid","Platforms","ConditionalWalls","ConditionalPlatforms","BreakableWalls"]:
				var other := room.get_node_or_null(NodePath(other_key)) as TileMapLayer
				if other_key != key and other != null and other.get_cell_source_id(cell) != -1:
					errors.append("%s overlaps %s at %s" % [key,other_key,cell])
	# Hazard artwork is independent of blocking terrain and future damage logic.
	var hazards := room.get_node_or_null("Hazards") as TileMapLayer
	if hazards != null:
		if hazards.tile_set == null:
			errors.append("Hazards requires a TileSet")
		else:
			if hazards.collision_enabled:
				errors.append("Hazards must disable solid collision")
			if hazards.tile_set.tile_size != Vector2i.ONE * room.tile_pixels or hazards.position != Vector2.ZERO or hazards.scale != Vector2.ONE or not is_zero_approx(hazards.rotation):
				errors.append("Hazards requires matching tiles and identity transform")
			for cell in hazards.get_used_cells():
				if not bounds.has_point(cell):
					errors.append("Hazard tile outside room: %s" % cell)
				if protected.has(cell):
					errors.append("Hazard overlaps protected opening/route: %s" % cell)
				var data := hazards.get_cell_tile_data(cell)
				if data == null or hazards.tile_set.get_custom_data_layer_by_name("hazard_type") < 0:
					errors.append("Hazards requires hazard_type custom data")
				elif String(data.get_custom_data("hazard_type")).is_empty():
					errors.append("Paint hazard tiles on Hazards, not ordinary terrain: %s" % cell)
	var breakable := room.get_node_or_null("BreakableWalls") as TileMapLayer
	if breakable != null:
		var ids: Dictionary = {}
		var canonical: Dictionary = {}
		for group in AbyssTileGroups.describe(breakable,metadata.template_id,room.breakable_group_ids):
			canonical[group.canonical] = true
			if ids.has(group.id):
				errors.append("Duplicate breakable group ID: %s" % group.id)
			ids[group.id] = true
		for cell in room.breakable_group_ids:
			if not canonical.has(cell) or room.breakable_group_ids[cell].is_empty():
				errors.append("Explicit breakable IDs must target a group's canonical coordinate")
	var marker_ids: Dictionary = {}
	for marker in AbyssRoomContent.markers(room):
		if marker.marker_id == &"" or marker_ids.has(marker.marker_id):
			errors.append("Missing/duplicate room marker ID: %s" % marker.marker_id)
		marker_ids[marker.marker_id] = true
		if not is_finite(marker.spawn_probability) or marker.spawn_probability < 0 or marker.spawn_probability > 1:
			errors.append("Invalid marker spawn probability")
		if not Rect2(Vector2.ZERO,Vector2(room.room_size * room.tile_pixels)).has_point(AbyssRoomContent.local_transform(marker,room).origin):
			errors.append("Marker outside room: %s" % marker.marker_id)
		if marker is CheckpointMarker or marker is LevelGateMarker or marker is KeyFragmentMarker:
			var region := int(metadata.transition_base_region) if metadata.region == AbyssRoomTemplateMetadata.Compatibility.TRANSITION else int(metadata.region)
			var expected := AbyssRoomData.Region.PACKED if marker is KeyFragmentMarker else AbyssRoomData.Region.OPEN
			if region != expected:
				errors.append("Special marker %s has incompatible room region" % marker.marker_id)
		elif marker is EnemySpawnMarker:
			if not is_finite(marker.difficulty_range.x) or not is_finite(marker.difficulty_range.y) or marker.difficulty_range.x > marker.difficulty_range.y or marker.depth_range.x > marker.depth_range.y:
				errors.append("Invalid enemy difficulty/depth range")
		elif marker is LootSpawnMarker:
			if marker.quantity_range.x < 1 or marker.quantity_range.x > marker.quantity_range.y:
				errors.append("Invalid loot quantity range")
		elif marker is HazardSpawnMarker:
			if marker.avoidance_radius_tiles < 0 or marker.avoidance_radius_tiles > maxi(room.room_size.x,room.room_size.y):
				errors.append("Invalid hazard clearance radius")
		elif marker is DecorationMarker:
			if marker.variation_range.x < 0 or marker.variation_range.x > marker.variation_range.y:
				errors.append("Invalid decoration variation range")
	return errors
