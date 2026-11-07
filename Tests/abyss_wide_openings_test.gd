extends SceneTree
## Fixed three-tile spans require no additional metadata fields.
var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func verify_guides(directory: String, routes: AbyssRouteConfig) -> void:
	for name in DirAccess.get_directories_at(directory):
		verify_guides(directory+"/"+name,routes)
	for name in DirAccess.get_files_at(directory):
		var path := directory+"/"+name
		if not name.ends_with(".tscn") or not FileAccess.get_file_as_string(path).contains("/authored_room.gd"):
			continue
		var room := (load(path) as PackedScene).instantiate() as AbyssAuthoredRoom
		for side in range(4):
			for slot in range(2):
				var id := AbyssRouteConfig.opening_id(side,slot)
				var guide := room.get_node_or_null("OpeningGuides/"+String(id).replace(":","_")) as Marker2D
				if guide != null:
					var expected := (Vector2(routes.opening_position(side,slot,room.room_size))+Vector2(0.5,0.5))*room.tile_pixels
					check(guide.position == expected,"Stale opening guide: "+path+"/"+String(id))
		room.free()

func _initialize() -> void:
	var routes := AbyssRouteConfig.new()
	check(routes.horizontal_offsets == Vector2i(5,18) and routes.vertical_offsets == Vector2i(5,18), "Opening centers did not move toward corners")
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
			check(metadata.opening_combinations[0].opening_tiles[id] == center, "Inspector checkbox uses stale slot coordinates")
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
	solid.set_cell(routes.opening_position(0,0,size)-Vector2i.RIGHT, 0, Vector2i.ZERO)
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
	# Saved settings migrate only the previous defaults, preserving the world seed.
	var region := AbyssRegionConfig.new()
	var old_routes := AbyssRouteConfig.new()
	old_routes.horizontal_offsets = Vector2i(6,17)
	old_routes.vertical_offsets = Vector2i(6,17)
	var configs: Array[Resource] = [region,old_routes,AbyssTerrainConfig.new(),AbyssProgressionConfig.new()]
	var registry := AbyssRoomTemplateRegistry.new()
	var saved := AbyssRuntimeWorldSettings.capture(configs,registry)
	check(AbyssRuntimeWorldSettings.apply(saved,configs), "Saved opening convention migration failed")
	check(old_routes.horizontal_offsets == routes.horizontal_offsets and old_routes.vertical_offsets == routes.vertical_offsets and region.global_seed == saved["0"].global_seed,"Migration changed seed or retained old centers")
	old_routes.horizontal_offsets = Vector2i(3,20)
	saved = AbyssRuntimeWorldSettings.capture(configs,registry)
	check(AbyssRuntimeWorldSettings.apply(saved,configs) and old_routes.horizontal_offsets == Vector2i(3,20),"Custom opening offsets were overwritten")
	verify_guides("res://Scenes/Underground/Rooms",routes)
	for name in ["packed_horizontal","packed_vertical","transition_west"]:
		var authored := load("res://Scenes/Underground/Rooms/Metadata/"+name+".tres") as AbyssRoomTemplateMetadata
		check(AbyssRoomTemplateValidator.validate(authored).is_empty(),"Shifted painted scene invalid: "+name)
		var instance := authored.scene.instantiate() as AbyssAuthoredRoom
		var layer := instance.get_node("Solid") as TileMapLayer
		for id in authored.opening_combinations[0].openings:
			var side := ["north","east","south","west"].find(String(id).get_slice(":",0))
			var slot := int(String(id).get_slice(":",1))
			var center := routes.opening_position(side,slot,size)
			check(authored.opening_combinations[0].opening_tiles[id] == center,"Stale saved metadata: "+name)
			for cell in AbyssRouteConfig.opening_cells(id,center):
				for depth in range(3):
					check(layer.get_cell_source_id(cell-AbyssRegionGenerator.DIRECTIONS[side]*depth) == -1,"Shifted authored throat blocked: "+name)
		instance.free()
	print("Three-tile connections: shifted centers, checkbox authoring, shoulders, neighboring alignment, procedural throats and saved settings; failures=", failures)
	quit(1 if failures else 0)
