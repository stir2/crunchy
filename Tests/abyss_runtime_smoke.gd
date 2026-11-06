extends SceneTree
## One focused runtime scenario; no world/save files are written.
var failures: int = 0
var checks: int = 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func tick(count: int = 1) -> void:
	for i in range(count):
		await physics_frame
		await process_frame
func settled(runtime: Node, center: Vector2i) -> void:
	for i in range(300):
		if runtime.stream.neighborhood_ready(center):
			return
		await tick()
	check(false,"Streaming neighborhood timed out")
func fingerprint(room: AbyssAuthoredRoom) -> Dictionary:
	var result := {}
	for layer in room.get_children():
		if layer is TileMapLayer:
			var cells: Array[Vector2i] = layer.get_used_cells()
			cells.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
			var data: Array = []
			for cell in cells:
				data.append([cell,layer.get_cell_source_id(cell),layer.get_cell_atlas_coords(cell)])
			result[layer.name] = data
	return result
func run() -> void:
	var started := Time.get_ticks_msec()
	var game := root.get_node("GameController")
	game.abyss_room_state = AbyssRoomState.new()
	game.abyss_progression_state = AbyssProgressionState.new()
	game.health = 5
	game.stamina = 73
	var main: Node = load("res://Scenes/Main/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var host_id: int = main.get_instance_id()
	main.change_scene("res://Scenes/Underground/abyss_runtime.tscn")
	var runtime: Node = main.active_scene
	for i in range(300):
		if runtime.is_active() or not runtime.last_error.is_empty(): break
		await tick()
	check(runtime.is_active(),"Runtime failed entrance startup: " + runtime.last_error)
	if not runtime.is_active():
		quit(1)
		return
	await tick(3)
	var stream: AbyssRoomStreamer = runtime.stream
	var entrance: Vector2i = runtime.destination.room_coords
	var spawn: Vector2 = runtime.player.global_position
	check(main.get_instance_id() == host_id and current_scene == main,"Runtime replaced persistent Main")
	check(runtime.player.is_on_floor() and runtime.player.health.current_health == 5,"Entrance lacks support or resets HP")
	check(stream.neighborhood_ready(entrance) and stream.rooms.size() == 49,"Initial 7x7 footprint incomplete")
	check(stream.is_rect_ready(runtime.camera.view_rect(runtime.camera.global_position)),"Visible startup terrain missing")
	check(not stream.unload_room(stream.current_room),"Streamer unloaded player's current room")
	check(stream.world_to_room(stream.container.to_global(Vector2(-1,-1))) == Vector2i(-1,-1),"Negative room floor division")
	check(stream.routes.regions.room_to_chunk(Vector2i(-1,-1)) == Vector2i(-1,-1),"Negative chunk floor division")
	var original := fingerprint(stream.rooms[entrance])
	# Force a cold leading room at dash/fast-fall speed: motion must wait for
	# collision instead of entering the missing room, without losing momentum.
	var ahead := entrance+Vector2i.RIGHT
	stream.unload_room(ahead)
	runtime.player.global_position.x = (entrance.x+1)*stream.room_pixels.x-2
	runtime.player.velocity = Vector2(runtime.player.dash_speed,900)
	var held_position: Vector2 = runtime.player.global_position
	var held_velocity: Vector2 = runtime.player.velocity
	await tick()
	check(runtime._holding and runtime.player.global_position == held_position and runtime.player.velocity == held_velocity,"High-speed motion entered cold terrain or lost momentum")
	runtime.player.global_position = spawn
	runtime.player.reset_movement()
	await settled(runtime,entrance)
	await tick(3)
	check(not runtime._holding and stream.is_rect_ready(runtime.camera.view_rect(runtime.camera.global_position)),"Streaming hold did not resume with complete visible collision")
	var mutation_room := Vector2i(2147483647,0)
	var mutation_key := ""
	var mutated: Dictionary = {}
	for coords in stream.rooms:
		if coords == stream.current_room or stream.rooms[coords].breakables == null: continue
		for group in stream.rooms[coords].breakables.groups():
			if not group.protected and group.health > 0:
				mutation_room = coords
				mutation_key = group.key
				stream.rooms[coords].destroy_breakable_group(group.id)
				mutated = fingerprint(stream.rooms[coords])
				break
		if not mutation_key.is_empty(): break
	check(not mutation_key.is_empty(),"Startup footprint contains no mutable authored breakable to verify")
	# Use a real generated horizontal contract at the next chunk edge.
	var crossing: Dictionary = {}
	# User seeds can leave chunk zero without an eastward route contract.
	# Search nearby chunks instead of assuming one particular generated layout.
	for y in range(4):
		for x in range(1,4):
			for edge in stream.routes.boundary_contracts(Vector2i(x,y)):
				if edge.side == 1:
					crossing = edge
					break
			if not crossing.is_empty(): break
		if not crossing.is_empty(): break
	check(not crossing.is_empty(),"No horizontal chunk contract available for scenario")
	if not crossing.is_empty():
		var a: Vector2i = crossing.a
		var b: Vector2i = crossing.b
		var port := Vector2i.ZERO
		for edge in stream.routes.get_room(a).required_connections:
			if edge.neighbor == b: port = edge.opening_tile
		var border := (a.x+1)*stream.room_pixels.x
		runtime.player.global_position = Vector2(border-20,a.y*stream.room_pixels.y+(port.y+0.5)*16+18)
		runtime.player.reset_movement()
		await settled(runtime,a)
		runtime.camera.activate(runtime.player,stream)
		Input.action_press("Move Right")
		for i in range(40):
			await tick()
			if runtime.player.global_position.x >= border+16: break
		Input.action_release("Move Right")
		check(stream.world_to_room(runtime.player.global_position) == b,"Player failed physical chunk-boundary crossing")
		check(stream.room_ready(a) and stream.room_ready(b),"Boundary crossing lacked ready terrain")
		check(not stream.rooms.has(entrance),"Rooms outside hysteresis were not unloaded")
	# Return to the same existing landing; derived caches may be discarded safely.
	runtime.player.global_position = spawn
	runtime.player.reset_movement()
	stream.boundary.retain_cached_rooms(Rect2i(10000,10000,1,1))
	stream.routes.retain_cached_chunks(Rect2i(1000,1000,1,1))
	await settled(runtime,entrance)
	runtime.camera.activate(runtime.player,stream)
	check(fingerprint(stream.rooms[entrance]) == original,"Room reconstruction changed terrain")
	if not mutation_key.is_empty():
		check(stream.unload_room(mutation_room),"Could not evict noncurrent mutation room")
		stream.request_neighborhood(entrance)
		await settled(runtime,entrance)
		check(fingerprint(stream.rooms[mutation_room]) == mutated and stream.mutations.groups.get(mutation_key) == 0,"Breakable mutation lost on reconstruction")
	var border_coords := Vector2i(stream.specials.config.room_bounds(1,8).y-1,0)
	var barrier_room := AbyssRoomTerrainBuilder.build(stream.selector.select_room(stream.routes,border_coords),stream.terrain_config,stream.boundary,stream.mutations,stream.specials)
	check(barrier_room.get_node("LevelBoundaryEast").get_used_cells().size() == 24,"Locked level border missing")
	barrier_room.free()
	# Probe hysteresis without changing movement parameters.
	runtime.player.set_physics_process(false)
	runtime.camera.activate(runtime.player,stream)
	runtime.player.velocity = Vector2(170,runtime.camera.vertical_enter_speed*0.8)
	await tick(30)
	check(runtime.camera.axis_switches == 0,"Camera oscillated below vertical threshold")
	runtime.player.velocity.y = runtime.camera.vertical_enter_speed*1.3
	await tick(30)
	check(runtime.camera.axis == runtime.camera.FollowAxis.VERTICAL,"Camera did not prioritize substantial vertical movement")
	var switches: int = runtime.camera.axis_switches
	for i in range(30):
		runtime.player.velocity.y = runtime.camera.vertical_enter_speed*(0.8 if i%2==0 else 1.05)
		await tick()
	check(runtime.camera.axis_switches == switches,"Camera rapidly switched axes around threshold")
	check(runtime.camera.view_rect(runtime.camera.global_position).has_point(runtime.player.global_position+Vector2(0,-18)),"Camera lost player")
	runtime.player.health.current_health = 4
	runtime.player.stamina.reset_stamina(37.5)
	runtime.player.stamina.regeneration_delay_remaining = 0.75
	var state: AbyssRoomState = game.abyss_room_state
	state.markers["permanent_marker"] = "collected"
	game.abyss_progression_state.checkpoints["retained"] = {"activated":true}
	game.abyss_progression_state.fragments["retained"] = "level1"
	game.abyss_progression_state.gates["retained"] = true
	runtime.leave()
	check(not runtime.visible and not runtime.get_node("HealthCanvas").visible,"Inactive runtime retained its UI")
	var restored := AbyssRoomState.new()
	check(restored.restore(state.serialize()) == OK,"Runtime state/save round trip failed")
	game.abyss_room_state = restored
	runtime.player.health.current_health = 2 # Discarded actor must not overwrite loaded state.
	main.change_scene("res://Scenes/Underground/abyss_runtime.tscn")
	runtime = main.active_scene
	for i in range(300):
		if runtime.is_active(): break
		await tick()
	check(runtime.is_active() and runtime.player.health.current_health == 4 and is_equal_approx(runtime.player.stamina.current_stamina,37.5),"New descent reset/overwrote saved vitals")
	check(restored.world_settings == state.world_settings,"World settings/seed changed across descents")
	check(fingerprint(runtime.stream.rooms[entrance]) == original,"Save round trip changed generated geometry")
	runtime.leave()
	restored.begin_day(2)
	check(mutation_key.is_empty() or not restored.groups.has(mutation_key),"Daily breakable did not reset")
	check(restored.markers.has("permanent_marker") and game.abyss_progression_state.gates.has("retained") and game.abyss_progression_state.fragments.has("retained") and game.abyss_progression_state.checkpoints.has("retained"),"Daily reset cleared permanent state")
	main.queue_free()
	await process_frame
	print("Abyss runtime: ",checks," checks; failures=",failures," elapsed_ms=",Time.get_ticks_msec()-started)
	quit(0 if failures == 0 else 1)
