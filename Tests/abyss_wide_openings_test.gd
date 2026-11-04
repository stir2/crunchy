extends SceneTree
## Fixed three-tile spans require no additional metadata fields.
var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var routes := AbyssRouteConfig.new()
	var size := Vector2i(24, 24)
	var metadata := AbyssRoomTemplateMetadata.new()
	var room := AbyssAuthoredRoom.new()
	for layer_name in ["Solid", "Platforms", "Decorations"]:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = AbyssRoomTerrainBuilder.TILES
		layer.collision_enabled = layer_name != "Decorations"
		room.add_child(layer)
		layer.owner = room
	var solid := room.get_node("Solid") as TileMapLayer
	for y in range(size.y):
		for x in range(size.x):
			if x in [0, size.x - 1] or y in [0, size.y - 1]:
				solid.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	var req := AbyssRoomRequirements.new()
	req.room_size = size
	req.region = AbyssRoomData.Region.PACKED
	for side in range(4):
		for slot in range(2):
			var id := AbyssRouteConfig.opening_id(side, slot)
			var center := routes.opening_position(side, slot, size)
			metadata.set("Connections/" + String(id), true)
			req.required_openings[id] = center
			var span := AbyssRouteConfig.opening_cells(id, center)
			check(span.size() == 3, "Wrong aperture size")
			for cell in span:
				solid.erase_cell(cell)
				check(AbyssRouteConfig.contains_opening(req.required_openings, cell), "Span membership")
				var opposite := routes.opening_position((side + 2) % 4, slot, size)
				check(AbyssRouteConfig.opening_cells(AbyssRouteConfig.opening_id((side + 2) % 4, slot), opposite).has(cell - AbyssRegionGenerator.DIRECTIONS[side] * size + AbyssRegionGenerator.DIRECTIONS[side]), "Neighbor span misaligned")
	var packed := PackedScene.new()
	check(packed.pack(room) == OK, "Pack fixture")
	metadata.scene = packed
	check(AbyssRoomTemplateValidator.validate(metadata).is_empty(), "Three-tile authored openings rejected")
	# The center alone is insufficient: both shoulders must also be open.
	solid.set_cell(Vector2i(5, 0), 0, Vector2i.ZERO)
	packed = PackedScene.new()
	packed.pack(room)
	metadata.scene = packed
	check(str(AbyssRoomTemplateValidator.validate(metadata)).contains("Blocked declared opening"), "Blocked shoulder accepted")
	room.free()
	var request := AbyssRoomConstructionRequest.new()
	request.requirements = req
	for region in [AbyssRoomData.Region.PACKED, AbyssRoomData.Region.OPEN]:
		req.region = region
		req.route_openings = req.required_openings.duplicate()
		var built := AbyssRoomTerrainBuilder.build(request, AbyssTerrainConfig.new())
		var terrain := built.get_node("Solid") as TileMapLayer
		for id in req.required_openings:
			var side := ["north", "east", "south", "west"].find(String(id).get_slice(":", 0))
			for cell in AbyssRouteConfig.opening_cells(id, req.required_openings[id]):
				for depth in range(3):
					check(terrain.get_cell_source_id(cell - AbyssRegionGenerator.DIRECTIONS[side] * depth) == -1, "Procedural aperture/throat blocked")
		built.free()
	print("Three-tile connections: all eight slots, authored validation, shoulders, neighboring alignment and procedural throats; failures=", failures)
	quit(1 if failures else 0)
