extends SceneTree
## Five-wide contracts, preserved legacy templates, and saved layout compatibility.
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
		var local_routes := routes.duplicate() as AbyssRouteConfig
		var width := 3 if room.room_size == AbyssRegionConfig.LEGACY_ROOM_SIZE else AbyssRouteConfig.OPENING_WIDTH
		local_routes.horizontal_offsets = AbyssRouteConfig.default_offsets_for_extent(room.room_size.x,width)
		local_routes.vertical_offsets = AbyssRouteConfig.default_offsets_for_extent(room.room_size.y,width)
		for side in range(4):
			for slot in range(2):
				var id := AbyssRouteConfig.opening_id(side,slot)
				var guide := room.get_node_or_null("OpeningGuides/"+String(id).replace(":","_")) as Marker2D
				if guide != null:
					var expected := (Vector2(local_routes.opening_position(side,slot,room.room_size))+Vector2(0.5,0.5))*room.tile_pixels
					if width%2==0:
						expected -= (Vector2.RIGHT if side%2==0 else Vector2.DOWN)*room.tile_pixels*0.5
					check(guide.position == expected,"Stale opening guide: "+path+"/"+String(id))
		room.free()

func _initialize() -> void:
	var routes := AbyssRouteConfig.new()
	check(AbyssRouteConfig.opening_cells(&"north:0",Vector2i(9,0),4).size() == 4,"Explicit even-width override must remain exactly four cells")
	check(routes.horizontal_offsets == Vector2i(9,31) and routes.vertical_offsets == Vector2i(9,31), "Opening centers did not move toward corners")
	var size := Vector2i(40, 40)
	var metadata := AbyssRoomTemplateMetadata.new()
	metadata.room_size = size
	metadata.opening_width = routes.opening_width
	metadata.opening_schema = routes.opening_schema
	var room := AbyssAuthoredRoom.new()
	room.room_size = size
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
			check(span.size() == 5, "Wrong aperture size")
			for cell in span:
				solid.erase_cell(cell)
				check(AbyssRouteConfig.contains_opening(req.required_openings, cell), "Span membership")
				var opposite := routes.opening_position((side + 2) % 4, slot, size)
				check(AbyssRouteConfig.opening_cells(AbyssRouteConfig.opening_id((side + 2) % 4, slot), opposite).has(cell - AbyssRegionGenerator.DIRECTIONS[side] * size + AbyssRegionGenerator.DIRECTIONS[side]), "Neighbor span misaligned")
	var packed := PackedScene.new()
	check(packed.pack(room) == OK, "Pack fixture")
	metadata.scene = packed
	check(AbyssRoomTemplateValidator.validate(metadata).is_empty(), "Five-wide authored openings rejected")
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
	var region := AbyssRegionConfig.new()
	var configs: Array[Resource] = [region,routes,AbyssTerrainConfig.new(),AbyssProgressionConfig.new()]
	var registry := AbyssRoomTemplateRegistry.new()
	var saved := AbyssRuntimeWorldSettings.capture(configs,registry)
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(saved))
	check(AbyssRuntimeWorldSettings.compatibility_error(roundtrip,region,routes).is_empty(),"Current JSON save rejected")
	check(AbyssRuntimeWorldSettings.apply(roundtrip,configs),"Current settings failed restoration")
	var four_wide := saved.duplicate(true)
	four_wide["1"]["opening_width"] = 4
	check(not AbyssRuntimeWorldSettings.compatibility_error(four_wide,region,routes).is_empty(),"Four-wide save silently accepted")
	var old := saved.duplicate(true)
	old.version = 1
	old["0"].room_size = [24,24]
	check(not AbyssRuntimeWorldSettings.compatibility_error(old,region,routes).is_empty() and not AbyssRuntimeWorldSettings.apply(old,configs),"Old save was silently migrated")
	check(region.room_size == Vector2i(40,40),"Rejected save changed world dimensions")
	var remade := (load("res://Scenes/Underground/Rooms/Authored/TEMPLATE_PACKED.tscn") as PackedScene).instantiate() as AbyssAuthoredRoom
	remade.room_size = Vector2i(40,40)
	remade._refresh_opening_guides()
	check(remade.get_node("OpeningGuides/north_0").position == Vector2(152,8) and remade.get_node("OpeningGuides/east_1").position == Vector2(632,504),"Remade five-wide opening guides are off-center")
	check(remade.get_node("ObjectMarkers/RoomCenter").position == Vector2(320,320),"Remade room center guide incorrect")
	remade.free()
	verify_guides("res://Scenes/Underground/Rooms",routes)
	var library := load("res://Scenes/Underground/Rooms/authored_registry.tres") as AbyssRoomTemplateRegistry
	for authored in library.templates:
		var name := String(authored.template_id)
		var legacy_routes := AbyssRouteConfig.new()
		legacy_routes.horizontal_offsets = AbyssRouteConfig.default_offsets_for_extent(authored.room_size.x,authored.opening_width)
		legacy_routes.vertical_offsets = AbyssRouteConfig.default_offsets_for_extent(authored.room_size.y,authored.opening_width)
		check(AbyssRoomTemplateValidator.validate(authored).is_empty(),"Shifted painted scene invalid: "+name)
		var instance := authored.scene.instantiate() as AbyssAuthoredRoom
		var layer := instance.get_node("Solid") as TileMapLayer
		for id in authored.opening_combinations[0].openings:
			var side := ["north","east","south","west"].find(String(id).get_slice(":",0))
			var slot := int(String(id).get_slice(":",1))
			var center := legacy_routes.opening_position(side,slot,authored.room_size)
			check(authored.opening_combinations[0].opening_tiles[id] == center,"Stale saved metadata: "+name)
			for cell in AbyssRouteConfig.opening_cells(id,center,authored.opening_width):
				for depth in range(3 if authored.room_size == Vector2i(40,40) else 1):
					check(layer.get_cell_source_id(cell-AbyssRegionGenerator.DIRECTIONS[side]*depth) == -1,"Shifted authored throat blocked: "+name)
		instance.free()
	var resized := library.templates[1].duplicate(true) as AbyssRoomTemplateMetadata
	resized.room_size = Vector2i(40,40)
	check(resized.opening_schema == &"abyss_slots_v2" and resized.opening_width == 5,"Remade metadata did not adopt 40x40 contract")
	for id in resized.opening_combinations[0].openings:
		var side := ["north","east","south","west"].find(String(id).get_slice(":",0))
		check(resized.opening_combinations[0].opening_tiles[id] == routes.opening_position(side,int(String(id).get_slice(":",1)),Vector2i(40,40)),"Remade metadata retained legacy opening coordinates")
	print("Five-wide connections: exact five-cell spans, checkbox authoring, alignment, procedural throats, legacy assets and save compatibility; failures=", failures)
	quit(1 if failures else 0)
