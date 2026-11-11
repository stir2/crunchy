extends SceneTree
## Focused checkpoint-pool, painted placement, activation and restore checks.
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func tick(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame

func checkpoint(room: Node) -> Node2D:
	for child in room.get_children():
		if child.get("request") is AbyssSpecialSpawnRequest and child.request.kind == &"checkpoint": return child
	return null

func run() -> void:
	var registry: AbyssRoomTemplateRegistry = load("res://Scenes/Underground/Rooms/authored_registry.tres")
	var selector := AbyssRoomTemplateSelector.new(registry,12)
	check(selector.registration_errors.is_empty(),"Checkpoint registry invalid: "+str(selector.registration_errors))
	var checkpoint_ids: Array[StringName] = []
	for metadata in registry.checkpoint_templates: checkpoint_ids.append(metadata.template_id)
	var region := AbyssRegionConfig.new()
	region.global_seed = 12
	region.open_threshold = 0.0
	region.noise_frequency = 0.085
	var progression := AbyssProgressionConfig.new()
	progression.checkpoint_probability = 1.0
	var routes := AbyssRouteGenerator.new(region,AbyssRouteConfig.new(),progression)
	var state := AbyssProgressionState.new()
	var service := AbyssSpecialRooms.new(routes,progression,state)
	var coords := Vector2i(2147483647,0)
	for y in range(12):
		for x in range(-8,9):
			if service.has_checkpoint(Vector2i(x,y)):
				coords = Vector2i(x,y)
				break
		if coords.x != 2147483647: break
	check(coords.x != 2147483647,"No planned checkpoint found")
	if coords.x == 2147483647: quit(1); return
	var request := selector.select_room(routes,coords)
	check(request.method == AbyssRoomConstructionRequest.Method.AUTHORED and checkpoint_ids.has(request.template_id),"Planned checkpoint did not select checkpoint pool")
	check(selector.select_room(routes,coords).template_id == request.template_id,"Checkpoint selection not deterministic")
	var ordinary := coords+Vector2i.RIGHT
	check(not service.has_checkpoint(ordinary),"Fixture ordinary room unexpectedly has checkpoint")
	check(not checkpoint_ids.has(selector.select_room(routes,ordinary).template_id),"Checkpoint room leaked into normal pool")
	var authored := request.scene.instantiate() as AbyssAuthoredRoom
	var painted := preload("res://Scenes/Underground/Progression/checkpoint_tile.gd")
	var expected_position: Vector2 = painted.position_for(authored,painted.cells(authored)[0])
	var expected_platforms: Dictionary = {}
	var authored_platforms := authored.get_node("Platforms") as TileMapLayer
	for cell in authored_platforms.get_used_cells():
		expected_platforms[cell] = [authored_platforms.get_cell_source_id(cell),authored_platforms.get_cell_atlas_coords(cell),authored_platforms.get_cell_alternative_tile(cell)]
	authored.free()
	var room := AbyssRoomTerrainBuilder.build(request,AbyssTerrainConfig.new(),null,AbyssRoomState.new(),service)
	root.add_child(room)
	var platforms := room.get_node("Platforms") as TileMapLayer
	var landing_valid := platforms.get_used_cells().size() == expected_platforms.size()
	for cell: Vector2i in expected_platforms:
		landing_valid = landing_valid and expected_platforms[cell] == [platforms.get_cell_source_id(cell),platforms.get_cell_atlas_coords(cell),platforms.get_cell_alternative_tile(cell)]
	check(landing_valid,"Authored checkpoint platforms changed during construction")
	var actor := checkpoint(room)
	check(actor != null,"Painted checkpoint did not instantiate")
	if actor == null: room.free(); quit(1); return
	check(actor.position == expected_position,"Painted tile did not determine exact checkpoint position")
	check(painted.cells(room).is_empty(),"Editor tile preview duplicated live checkpoint")
	var visuals: Node2D = actor.get_node("Visuals")
	var sprite: AnimatedSprite2D = visuals.get_node("AnimatedSprite2D")
	check(sprite.sprite_frames.get_frame_count(&"activate") == 31 and sprite.sprite_frames.get_animation_speed(&"activate") == 24,"Sprite sheet frames/FPS incorrect")
	check(not sprite.is_playing() and sprite.frame == 0,"Inactive checkpoint did not show first pose")
	check(actor.request.activate(),"Checkpoint activation rejected")
	check(sprite.is_playing(),"Activation did not play animation")
	await tick(10)
	check(sprite.frame > 0,"Activation animation did not advance")
	var before := sprite.frame
	state.changed.emit()
	check(sprite.frame == before,"Repeated state refresh restarted activation")
	await tick(160)
	check(not sprite.is_playing() and sprite.frame == 30,"Activation did not settle on activated pose")
	var saved := AbyssProgressionState.new()
	check(saved.restore(state.serialize()) == OK,"Checkpoint state save round trip failed")
	room.free()
	service.state = saved
	room = AbyssRoomTerrainBuilder.build(request,AbyssTerrainConfig.new(),null,AbyssRoomState.new(),service)
	root.add_child(room)
	actor = checkpoint(room)
	sprite = actor.get_node("Visuals/AnimatedSprite2D")
	check(actor.get_node("Visuals").active and sprite.frame == 30 and not sprite.is_playing(),"Reload replayed activation or lost active pose")
	check(not actor.request.activate(),"Repeated activation was accepted")
	room.free()
	print("Checkpoint visuals/pool: %d checks; failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)
