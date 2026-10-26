class_name AbyssRoomContent
extends RefCounted
## Construction-only orchestration. Behavior-specific state never lives in a group definition.
static func process(room: AbyssAuthoredRoom, request: AbyssRoomConstructionRequest, state: AbyssRoomState = null) -> void:
	room.persistent_state = state if state != null else AbyssRoomState.new()
	for key in ["ConditionalWalls", "ConditionalPlatforms", "BreakableWalls"]:
		var layer := room.get_node_or_null(NodePath(key)) as TileMapLayer
		if layer != null:
			room.tile_groups[key] = AbyssTileGroups.describe(layer, request.template_id, room.breakable_group_ids if key == "BreakableWalls" else {})
	room.protected_route_cells = AbyssConditionalWallGroups.reserved_cells(room, request.requirements)
	AbyssConditionalWallGroups.apply(room, request)
	var protected := room.protected_route_cells.duplicate()
	for rect in room.required_support_rects:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				protected[Vector2i(x,y)] = true
	var platforms := room.get_node_or_null("ConditionalPlatforms") as TileMapLayer
	for group in room.tile_groups.get("ConditionalPlatforms", []):
		var value := AbyssRoomRandom.roll(request, "conditional_platform", group.id)
		var reason := "selected" if value < request.conditional_platform_probability else "probability"
		for cell: Vector2i in group.cells:
			if _boundary(cell, room.room_size) or protected.has(cell):
				reason = "protected route/support: paint as a permanent platform"
				break
		var included := reason == "selected"
		if not included:
			for cell: Vector2i in group.cells:
				platforms.erase_cell(cell)
		room.conditional_platform_groups.append({"id":group.id,"cells":group.cells.duplicate(),"bounds":group.bounds,"roll":value,"included":included,"reason":reason})
		if reason.begins_with("protected"):
			room.content_warnings.append(reason)
	room.breakables = AbyssBreakableTerrain.new()
	room.breakables.setup(room,request,room.persistent_state,room.tile_groups.get("BreakableWalls",[]),protected)
	room.breakables.damaged.connect(func(id: String, health: float, point: Vector2) -> void: room.breakable_damaged.emit(id,health,point))
	room.breakables.destroyed.connect(func(id: String, cells: Array, point: Vector2) -> void: room.breakable_destroyed.emit(id,cells,point))
	var climbables := room.get_node_or_null("Climbables") as TileMapLayer
	if climbables != null:
		for cell in climbables.get_used_cells():
			if AbyssRoomTemplateValidator._has_collision(climbables,cell) and (_boundary(cell,room.room_size) or protected.has(cell)):
				climbables.erase_cell(cell)
				room.content_warnings.append("Colliding climbable on protected route omitted")
		room.climbable_regions = AbyssTileGroups.describe(climbables,request.template_id)
		for cell in climbables.get_used_cells():
			if AbyssClimbableTiles.is_climbable(climbables,cell):
				room.climbable_cells.append(cell)
	_process_markers(room,request,protected)

static func _boundary(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x <= 0 or cell.y <= 0 or cell.x >= size.x - 1 or cell.y >= size.y - 1

static func markers(node: Node) -> Array[RoomMarker]:
	var result: Array[RoomMarker] = []
	for child in node.get_children():
		if child is RoomMarker:
			result.append(child)
		result.append_array(markers(child))
	return result

static func _process_markers(room: AbyssAuthoredRoom, request: AbyssRoomConstructionRequest, protected: Dictionary) -> void:
	var seen: Dictionary = {}
	for marker in markers(room):
		if marker.marker_id == &"" or seen.has(marker.marker_id):
			room.content_warnings.append("Missing/duplicate marker ID: %s" % marker.marker_id)
			continue
		seen[marker.marker_id] = true
		var spawn := RoomMarkerHandlers.create(marker)
		if spawn == null:
			var message := "Unsupported room marker %s (%s)" % [marker.marker_id,marker.kind()]
			room.content_warnings.append(message)
			push_warning(message)
			continue
		spawn.marker_id = marker.marker_id
		spawn.kind = marker.kind()
		spawn.room_coords = request.requirements.global_coords
		spawn.local_position = local_transform(marker,room).origin
		spawn.tags = marker.tags.duplicate()
		spawn.configuration = marker.configuration
		spawn.roll = AbyssRoomRandom.roll(request,"marker",String(marker.marker_id))
		spawn.selected = spawn.roll < marker.spawn_probability
		spawn.persistent = marker.persistence == RoomMarker.Persistence.PERSISTENT
		spawn.state_key = AbyssRoomState.key(request,"marker",marker.persistence_id())
		spawn._state = room.persistent_state
		spawn._room = weakref(room)
		spawn._initial_world_position = room.to_global(spawn.local_position)
		var cell := Vector2i(floori(spawn.local_position.x / room.tile_pixels), floori(spawn.local_position.y / room.tile_pixels))
		spawn.protected_route = protected.has(cell)
		if spawn is AbyssSpecialSpawnRequest:
			spawn.selected = false
			spawn.reason = "Progression placement hint; requires special-room planner"
		elif spawn is EnemySpawnRequest:
			var depth := maxi(0,request.requirements.global_coords.y)
			spawn.eligible = request.difficulty >= spawn.difficulty_range.x and request.difficulty <= spawn.difficulty_range.y and depth >= spawn.depth_range.x and depth <= spawn.depth_range.y
		elif spawn is LootSpawnRequest:
			spawn.quantity = spawn.quantity_range.x + int(AbyssRoomRandom.roll(request,"loot_quantity",String(marker.marker_id)) * (spawn.quantity_range.y - spawn.quantity_range.x + 1))
		elif spawn is HazardSpawnRequest:
			for y in range(-spawn.avoidance_radius_tiles,spawn.avoidance_radius_tiles + 1):
				for x in range(-spawn.avoidance_radius_tiles,spawn.avoidance_radius_tiles + 1):
					spawn.protected_route = spawn.protected_route or protected.has(cell + Vector2i(x,y))
			spawn.eligible = not spawn.protected_route
			if not spawn.eligible:
				spawn.reason = "hazard intersects protected route"
		elif spawn is DecorationSpawnRequest:
			spawn.variation = spawn.variation_range.x + int(AbyssRoomRandom.roll(request,"decoration_variation",String(marker.marker_id)) * (spawn.variation_range.y - spawn.variation_range.x + 1))
		room.spawn_requests.append(spawn)


static func local_transform(node: Node2D, room: Node2D) -> Transform2D:
	# CanvasItem global transforms do not include off-tree parents yet. Requests
	# are built before add_child, so walk local transforms explicitly.
	var result := node.transform
	var parent := node.get_parent()
	while parent != null and parent != room:
		if parent is Node2D:
			result = parent.transform * result
		parent = parent.get_parent()
	return result
