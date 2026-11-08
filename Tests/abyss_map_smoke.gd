extends SceneTree
## One focused map/discovery/grave/save scenario; no production save slot writes.
var checks: int = 0
var failures: int = 0
var runtime: AbyssRuntime
var host: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func tick(count: int = 1) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame

func map_key() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_M
	event.pressed = true
	Input.parse_input_event(event)
	await tick()
	event = InputEventKey.new()
	event.physical_keycode = KEY_M
	event.pressed = false
	Input.parse_input_event(event)
	await tick()

func has_marker(graph: Dictionary, kind: String, active: bool) -> bool:
	for marker: Dictionary in graph.markers:
		if marker.kind == kind and marker.active == active: return true
	return false

func run() -> void:
	var game := root.get_node("GameController")
	game.abyss_room_state = AbyssRoomState.new()
	game.abyss_progression_state = AbyssProgressionState.new()
	# Keep this placement fixture independent of the designer's current world seed.
	var fixture := AbyssRegionConfig.new()
	fixture.global_seed = 12
	fixture.noise_frequency = 0.085
	fixture.open_threshold = 0.0
	var progression := AbyssProgressionConfig.new()
	progression.checkpoint_probability = 1.0
	var configs: Array[Resource] = [fixture,AbyssRouteConfig.new(),AbyssTerrainConfig.new(),progression]
	game.abyss_room_state.world_settings = AbyssRuntimeWorldSettings.capture(configs,load("res://Scenes/Underground/Rooms/authored_registry.tres"))
	host = load("res://Scenes/Main/main.tscn").instantiate()
	root.add_child(host)
	current_scene = host
	host.change_scene("res://Scenes/Underground/abyss_runtime.tscn")
	runtime = host.active_scene
	for frame in range(1000):
		if runtime.is_active() or not runtime.last_error.is_empty(): break
		await tick()
	check(runtime.is_active(),"Map runtime startup failed: "+runtime.last_error)
	if not runtime.is_active():
		quit(1)
		return
	var player := runtime.player
	var overlay := runtime.abyss_map
	var tracker := runtime.exploration
	var state := tracker.state
	var service := runtime.stream.specials
	var world := service.world
	var model := overlay.model
	var coords := runtime.stream.world_to_room(player.global_position)
	runtime.stream.active = false # Keep the scenario short without moving the streaming window.
	runtime.camera.set_physics_process(false)
	player.gravity_multiplier = 0
	player.collision_mask = 0
	tracker.visit_dwell_seconds = 0.15
	tracker.leave()
	state.visited.clear()
	player.reset_movement()
	player.global_position = runtime.loaded_rooms.to_global(model.room_center(coords)+Vector2(57,-31))
	await tick(3)
	check(not state.is_visited(world,coords),"Streaming/short occupancy discovered a room")
	await map_key()
	check(overlay.opened and paused,"M did not open/pause map")
	check(overlay.panel.modulate.a < 1.0,"Map skipped short fade")
	var position := player.global_position
	var dwell: float = tracker._dwell
	await tick(22)
	check(is_equal_approx(overlay.panel.modulate.a,1.0),"Map fade did not complete during pause")
	check(player.global_position == position and tracker._dwell == dwell and not state.is_visited(world,coords),"Gameplay or discovery advanced while map paused")
	check(overlay.view.center.is_equal_approx(runtime.loaded_rooms.to_local(position)),"Map did not center on exact player position")
	check(not overlay.view.player_position.is_equal_approx(model.room_center(coords)),"Player marker snapped to room center")
	var old_center := overlay.view.center
	overlay.view.pan_screen(Vector2(30,12))
	check(overlay.view.center != old_center,"Map panning failed")
	overlay.view.zoom_at(1.2,Vector2(100,100))
	check(is_equal_approx(overlay.view.map_zoom,1.2),"Map zoom failed")
	await map_key()
	check(not overlay.opened and not paused,"M did not close/unpause map")
	await tick(20)
	check(state.is_visited(world,coords),"Dwell time did not discover current room")
	var graph := model.snapshot(service.level_at(coords))
	check(graph.nodes[coords].visited and graph.edges.is_empty(),"Single visited room revealed unexplored connections")
	var connections := model.connections(coords)
	check(not connections.is_empty(),"Entrance has no graph connections")
	var adjacent: Vector2i = connections[0].neighbor
	check(graph.nodes.has(adjacent) and not graph.nodes[adjacent].visited,"Adjacent unvisited room not shown as faint node")
	check(graph.nodes[adjacent].color.a < graph.nodes[coords].color.a,"Frontier node is not translucent")
	for key: Vector2i in graph.nodes:
		check(key == coords or absi(key.x-coords.x)+absi(key.y-coords.y) == 1,"Map revealed distant unvisited room")
	state.visit(world,adjacent)
	graph = model.snapshot(service.level_at(coords))
	check(not graph.edges.is_empty(),"Visited neighbor has no graph edge")
	check((graph.edges[0].points[1] == connections[0].a and graph.edges[0].points[2] == connections[0].b) or (graph.edges[0].points[2] == connections[0].a and graph.edges[0].points[1] == connections[0].b),"Graph ignored actual opening positions")
	check(model.color_for(1,1) == AbyssMapModel.LEVEL_COLORS[0] and model.color_for(2,2) == AbyssMapModel.LEVEL_COLORS[1] and model.color_for(3,3) == AbyssMapModel.LEVEL_COLORS[2],"Level palette incorrect")
	check(model.color_for(2,1) == AbyssMapModel.OTHER_LEVEL and model.color_for(3,1) == AbyssMapModel.OTHER_LEVEL,"Other levels are not translucent gray")
	var gate: Dictionary = service.interval_definitions(1,0).gate
	var gate_coords := Vector2i(gate.x,gate.y)
	state.visit(world,gate_coords)
	var cp: Dictionary = {}
	for y in range(10):
		for x in range(-8,9):
			for definition in service.definitions_at(Vector2i(x,y)):
				if definition.kind == "checkpoint": cp = definition
			if not cp.is_empty(): break
		if not cp.is_empty(): break
	state.visit(world,Vector2i(cp.x,cp.y))
	var fragment: Dictionary = service.interval_definitions(1,0).fragment
	state.visit(world,Vector2i(fragment.x,fragment.y))
	graph = model.snapshot(1)
	check(has_marker(graph,"checkpoint",false) and has_marker(graph,"gate",false),"Inactive checkpoint/locked gate markers missing")
	check(not has_marker(graph,"fragment",true),"Uncollected fragment revealed on map")
	cp.spawn_x = model.room_center(Vector2i(cp.x,cp.y)).x
	cp.spawn_y = model.room_center(Vector2i(cp.x,cp.y)).y
	service.state.activate_checkpoint(cp)
	for index in range(int(gate.fragments_per_key)):
		service.state.collect_fragment(service.interval_definitions(1,index).fragment)
	check(service.unlock_gate(gate),"Generated gate unlock failed")
	graph = model.snapshot(1)
	check(has_marker(graph,"checkpoint",true) and has_marker(graph,"gate",true),"Activated checkpoint/unlocked gate markers missing")
	check(has_marker(graph,"fragment",true) and service.state.collected_count(service.level_key(1)) == 0,"Consumed fragment memory marker missing")
	var fragment_coords := Vector2i(fragment.x,fragment.y)
	state.visited[world].erase(AbyssExplorationState.room_key(fragment_coords))
	check(has_marker(model.snapshot(1),"fragment",true) and not state.is_visited(world,fragment_coords),"Fast collection lost its memory dot or bypassed dwell discovery")
	var flesh: int = game.flesh
	state.add_descent_souls(world,9)
	player.health.reset_health()
	var hit := CombatHit.new()
	hit.amount = 999
	check(player.damage.receive_hit(hit),"Death test damage failed")
	var grave: Dictionary = state.graves.get(world,{})
	check(not grave.is_empty() and int(grave.souls) == 4 and state.descent_souls[world] == 0,"Death did not preserve half of descent souls")
	check(game.flesh == flesh and has_marker(model.snapshot(1),"grave",true),"Grave touched village currency or failed map display")
	# Preserve global-tick damage/health deadlines across map pause too.
	player.health.reset_health()
	player.health._invulnerable_until = Engine.get_physics_frames()+10
	var before := player.health._invulnerable_until-Engine.get_physics_frames()
	check(overlay.open_map(),"Map failed to reopen")
	await tick(20)
	overlay.close_map()
	check(abs((player.health._invulnerable_until-Engine.get_physics_frames())-before) <= 1,"Map pause consumed invulnerability")
	var saved_visited := state.visited.duplicate(true)
	# Leave and use the existing village SaveManager flow, isolated from the real slot.
	runtime.leave()
	host.change_scene("res://Scenes/Village/House/house.tscn")
	await tick(2)
	var saves := root.get_node("SaveManager")
	saves.save_path = "/tmp/crunchy-map-smoke-save.json"
	check(saves.save_game(),"Map save failed: "+saves.last_error)
	game.abyss_room_state = AbyssRoomState.new()
	check(saves.load_game(),"Map load failed: "+saves.last_error)
	state = game.abyss_room_state.exploration
	check(state.visited == saved_visited and state.graves[world].id == grave.id,"Visited/grave state lost on save/load")
	host.change_scene("res://Scenes/Underground/abyss_runtime.tscn")
	runtime = host.active_scene
	for frame in range(1000):
		if runtime.is_active() or not runtime.last_error.is_empty(): break
		await tick()
	check(runtime.is_active(),"New descent failed after map save")
	runtime.stream.active = false
	runtime.camera.set_physics_process(false)
	player = runtime.player
	player.gravity_multiplier = 0
	player.collision_mask = 0
	state = runtime.exploration.state
	var death_coords := Vector2i(int(grave.x),int(grave.y))
	if not runtime.stream.rooms.has(death_coords): runtime.stream._build_room(death_coords)
	runtime.stream._settling.erase(death_coords)
	runtime.stream.rooms[death_coords].visible = true
	runtime.exploration.refresh_grave()
	await tick(3)
	var grave_actor: InteractionTarget = runtime.exploration._grave
	check(grave_actor != null and has_marker(runtime.abyss_map.model.snapshot(1),"grave",true),"Grave did not reconstruct with loaded room")
	player.reset_movement()
	player.global_position = runtime.loaded_rooms.to_global(Vector2(grave.position_x,grave.position_y))+Vector2(0,18)
	await tick(2)
	Input.action_press("Interact 1")
	await tick()
	Input.action_release("Interact 1")
	await tick()
	check(not state.graves.has(world) and int(state.descent_souls[world]) == 4,"E grave recovery failed or paid wrong souls")
	check(not has_marker(runtime.abyss_map.model.snapshot(1),"grave",true),"Recovered grave remained on map")
	check(state.recover_grave(world,grave.id).is_empty(),"Duplicate grave recovery paid twice")
	var restored := AbyssRoomState.new()
	check(restored.restore(game.abyss_room_state.serialize()) == OK and not restored.exploration.graves.has(world),"Recovered grave returned on serialization")
	check(state.visited_rooms("another-world").is_empty(),"Exploration leaked between worlds")
	var old_save: Dictionary = JSON.parse_string(game.abyss_room_state.serialize())
	old_save.erase("exploration")
	var legacy := AbyssRoomState.new()
	check(legacy.restore(JSON.stringify(old_save)) == OK and legacy.exploration.visited.is_empty(),"Pre-map saves are not backward compatible")
	paused = true
	check(not runtime.abyss_map.open_map() and paused,"Map took over an existing pause")
	paused = false
	check(runtime.abyss_map.open_map(),"Map failed before scene exit")
	runtime.leave()
	check(not paused,"Leaving runtime leaked map pause")
	DirAccess.remove_absolute(saves.save_path)
	host.queue_free()
	await process_frame
	print("Abyss map: ",checks," checks; failures=",failures)
	quit(1 if failures else 0)
