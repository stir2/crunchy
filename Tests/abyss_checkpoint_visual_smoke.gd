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
	check(request.method == AbyssRoomConstructionRequest.Method.AUTHORED and request.template_id == &"room_checkpoint1","Planned checkpoint did not select checkpoint pool")
	check(selector.select_room(routes,coords).template_id == request.template_id,"Checkpoint selection not deterministic")
	var ordinary := coords+Vector2i.RIGHT
	check(not service.has_checkpoint(ordinary),"Fixture ordinary room unexpectedly has checkpoint")
	check(selector.select_room(routes,ordinary).template_id != &"room_checkpoint1","Checkpoint room leaked into normal pool")
	var room := AbyssRoomTerrainBuilder.build(request,AbyssTerrainConfig.new(),null,AbyssRoomState.new(),service)
	root.add_child(room)
	var platforms := room.get_node("Platforms") as TileMapLayer
	var landing_valid := platforms.get_used_cells().size() == 13
	for x in range(14,27):
		landing_valid = landing_valid and platforms.get_cell_source_id(Vector2i(x,21)) == 0 and platforms.get_cell_atlas_coords(Vector2i(x,21)) == Vector2i(1,0)
	check(landing_valid,"Starter landing platform cells are invalid")
	var actor := checkpoint(room)
	check(actor != null,"Painted checkpoint did not instantiate")
	if actor == null: room.free(); quit(1); return
	check(actor.position == Vector2(328,312),"Painted tile did not determine exact checkpoint position")
	check(room.get_node("Decorations").get_used_cells().is_empty(),"Editor tile preview duplicated live checkpoint")
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
