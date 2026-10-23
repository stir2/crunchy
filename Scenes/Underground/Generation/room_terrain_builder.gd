class_name AbyssRoomTerrainBuilder
extends RefCounted
## Stateless construction. Every random choice belongs to the request's room seed.
const TILES = preload("res://Assets/Tiles/room_placeholders.tres")

static func build(request: AbyssRoomConstructionRequest, config: AbyssTerrainConfig) -> AbyssAuthoredRoom:
	if request.method == AbyssRoomConstructionRequest.Method.AUTHORED:
		return AbyssRoomSceneInstantiator.instantiate_authored(request)
	var room := AbyssAuthoredRoom.new()
	var req := request.requirements
	room.room_size = req.room_size
	room.tile_pixels = req.tile_pixels
	room.construction_requirements = req
	room.position = Vector2(req.global_coords * req.room_size * req.tile_pixels)
	for layer_name in ["Solid", "Platforms", "Decorations"]:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = TILES
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layer.collision_enabled = layer_name != "Decorations"
		room.add_child(layer)
	var solid := room.get_node("Solid") as TileMapLayer
	var platforms := room.get_node("Platforms") as TileMapLayer
	var rng := RandomNumberGenerator.new()
	rng.seed = request.room_seed
	if req.region == AbyssRoomData.Region.OPEN:
		if rng.randf() < config.platform_probability:
			for i in range(rng.randi_range(1, maxi(1, config.max_platforms)) if config.max_platforms > 0 else 0):
				var length := rng.randi_range(2, 5)
				var start := Vector2i(rng.randi_range(1, req.room_size.x - length - 1), rng.randi_range(2, req.room_size.y - 3))
				for x in range(length):
					var cell := start + Vector2i(x, 0)
					# Keep route landing corridors clear even of one-way collision.
					var clear := true
					for opening in req.route_openings.values():
						if cell.distance_to(opening) < 2.0:
							clear = false
					if clear:
						platforms.set_cell(cell, 0, Vector2i.RIGHT)
		return room
	for y in range(req.room_size.y):
		for x in range(req.room_size.x):
			solid.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	var hub := req.room_size / 2 + Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
	_brush(solid, hub, config.tunnel_width + int(rng.randf() < config.internal_openness), req.room_size)
	var ids: Array = req.required_openings.keys()
	ids.sort()
	for id in ids:
		var opening: Vector2i = req.required_openings[id]
		var side := ["north", "east", "south", "west"].find(String(id).get_slice(":", 0))
		var inward: Vector2i = -AbyssRegionGenerator.DIRECTIONS[side]
		var point := opening + inward * 2
		# Winding Manhattan paths are connected by construction, with bounded bends.
		var bend := Vector2i(clampi(point.x + rng.randi_range(-config.shape_variation, config.shape_variation), 2, req.room_size.x - 3), hub.y)
		_line(solid, point, bend, config.tunnel_width, req.room_size, rng)
		_line(solid, bend, hub, config.tunnel_width, req.room_size, rng)
		_brush(solid, opening + inward, config.tunnel_width, req.room_size)
		solid.erase_cell(opening)
	# Erode only faces touching known OPEN rooms. Wedges stay attached to the
	# packed mass; no isolated rock is placed in the neighboring cavern.
	for side in range(4):
		if not (req.neighbor_open_sides & (1 << side)):
			continue
		var limit := req.room_size.x if side % 2 == 0 else req.room_size.y
		for offset in range(1, limit - 1):
			var depth := rng.randi_range(1, maxi(1, config.transition_depth))
			for d in range(depth):
				var cell := Vector2i(offset, d if side == 0 else req.room_size.y - 1 - d) if side % 2 == 0 else Vector2i(req.room_size.x - 1 - d if side == 1 else d, offset)
				solid.erase_cell(cell)
	_remove_floating_rock(solid, req)
	return room

static func _brush(layer: TileMapLayer, center: Vector2i, width: int, size: Vector2i) -> void:
	var low := -width / 2
	for y in range(low, low + width):
		for x in range(low, low + width):
			var cell := center + Vector2i(x, y)
			if cell.x > 0 and cell.y > 0 and cell.x < size.x - 1 and cell.y < size.y - 1:
				layer.erase_cell(cell)

static func _line(layer: TileMapLayer, start: Vector2i, end: Vector2i, width: int, size: Vector2i, rng: RandomNumberGenerator) -> void:
	var point := start
	while point != end:
		_brush(layer, point, width, size)
		if point.x != end.x and (point.y == end.y or rng.randf() < 0.5):
			point.x += signi(end.x - point.x)
		else:
			point.y += signi(end.y - point.y)
	_brush(layer, end, width, size)


static func _remove_floating_rock(layer: TileMapLayer, req: AbyssRoomRequirements) -> void:
	# Carving junctions can leave small islands. Keep only rock anchored to a
	# closed boundary, where neighboring packed rock continues the formation.
	var visited: Dictionary = {}
	for start in layer.get_used_cells():
		if visited.has(start):
			continue
		var pending: Array[Vector2i] = [start]
		var component: Array[Vector2i] = []
		var anchored := false
		while not pending.is_empty():
			var cell: Vector2i = pending.pop_back()
			if visited.has(cell) or layer.get_cell_source_id(cell) == -1:
				continue
			visited[cell] = true
			component.append(cell)
			anchored = anchored or (cell.y == 0 and not req.neighbor_open_sides & 1) or (cell.x == req.room_size.x - 1 and not req.neighbor_open_sides & 2) or (cell.y == req.room_size.y - 1 and not req.neighbor_open_sides & 4) or (cell.x == 0 and not req.neighbor_open_sides & 8)
			for direction in AbyssRegionGenerator.DIRECTIONS:
				pending.append(cell + direction)
		if not anchored:
			for cell in component:
				layer.erase_cell(cell)
