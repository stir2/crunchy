extends SceneTree
## Focused generated-placement/input/streaming/save test. Never uses the real slot.
var checks: int = 0
var failures: int = 0
var runtime: AbyssRuntime
var host: Node
var player: Player
var controller: PlayerInteractionController

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

func press_interact() -> void:
	Input.action_release("Interact")
	await tick()
	Input.action_press("Interact")
	await tick()
	Input.action_release("Interact")
	await tick()

func load_room(coords: Vector2i) -> AbyssAuthoredRoom:
	if not runtime.stream.rooms.has(coords):
		runtime.stream._build_room(coords)
	await tick(3)
	var room: AbyssAuthoredRoom = runtime.stream.rooms[coords]
	runtime.stream._settling.erase(coords)
	room.visible = true
	return room

func target_in(room: AbyssAuthoredRoom, kind: StringName) -> InteractionTarget:
	for child in room.get_children():
		if child is InteractionTarget and child.request.kind == kind:
			return child
	return null

func approach(target: InteractionTarget) -> void:
	player.reset_movement()
	player.global_position = target.global_position + Vector2(0,18)
	await tick(2)

func passage_clear(room: AbyssAuthoredRoom, left: bool) -> bool:
	var boundary := room.get_node("LevelBoundaryEast" if left else "LevelBoundaryWest") as AbyssLevelBoundary
	for cell in boundary.gate_cells:
		if boundary.get_cell_source_id(cell) != -1:
			return false
	return not boundary.gate_cells.is_empty()

func run() -> void:
	var game := root.get_node("GameController")
	game.abyss_room_state = AbyssRoomState.new()
	game.abyss_progression_state = AbyssProgressionState.new()
	host = load("res://Scenes/Main/main.tscn").instantiate()
	root.add_child(host)
	current_scene = host
	host.change_scene("res://Scenes/Underground/abyss_runtime.tscn")
	runtime = host.active_scene
	for frame in range(1200):
		if runtime.is_active() or not runtime.last_error.is_empty(): break
		await tick()
	check(runtime.is_active(),"Runtime startup failed: "+runtime.last_error)
	if not runtime.is_active():
		quit(1)
		return
	# Keep the test short: stream real generated rooms directly and position the
	# player at their targets. Terrain physics is checked separately below.
	runtime.stream.active = false
	runtime.camera.set_physics_process(false)
	player = runtime.player
	controller = player.get_node("InteractionController")
	player.gravity_multiplier = 0.0
	player.collision_mask = 0
	player.stamina.regeneration_per_second = 0.0
	var service := runtime.stream.specials
	var state := service.state
	check(controller.interaction_radius == 48,"Interaction radius changed")
	var binding := InputMap.action_get_events("Interact")[0] as InputEventKey
	check(binding.physical_keycode == KEY_E,"Interact is not mapped to E")
	var checkpoint_coords := Vector2i(2147483647,0)
	for y in range(10):
		for x in range(-8,9):
			if service.has_checkpoint(Vector2i(x,y)):
				checkpoint_coords = Vector2i(x,y)
				break
		if checkpoint_coords.x != 2147483647: break
	var room := await load_room(checkpoint_coords)
	var checkpoint := target_in(room,&"checkpoint")
	check(checkpoint != null,"Generated checkpoint missing")
	if checkpoint == null:
		quit(1)
		return
	await approach(checkpoint)
	check(not player.is_on_floor() and controller.current_target == checkpoint,"Airborne nearest interaction unavailable")
	player.health.current_health = 4
	player.stamina.reset_stamina(37)
	await press_interact()
	check(service.activated_checkpoints().size() == 1,"E did not activate checkpoint")
	check(player.health.current_health == 4 and player.stamina.current_stamina == 37,"Checkpoint changed vitals")
	check(not checkpoint.can_interact(player),"Activated checkpoint remains actionable")
	runtime.stream.unload_room(checkpoint_coords)
	await tick()
	room = await load_room(checkpoint_coords)
	checkpoint = target_in(room,&"checkpoint")
	check(checkpoint.get_node("Visuals").active and not checkpoint.can_interact(player),"Checkpoint activation lost on room reload")
	var gate_a: Dictionary = service.interval_definitions(1,0).gate
	var gate_b: Dictionary = service.interval_definitions(1,1).gate
	check(not gate_a.is_empty() and not gate_b.is_empty(),"Generated gates missing")
	var gate_coords := Vector2i(gate_a.x,gate_a.y)
	var gate_room := await load_room(gate_coords)
	var right_room := await load_room(gate_coords+Vector2i.RIGHT)
	var other_gate_room := await load_room(Vector2i(gate_b.x,gate_b.y))
	var gate := target_in(gate_room,&"gate")
	await approach(gate)
	check(controller.prompt.text.contains("0/") and not gate.can_interact(player),"Locked gate did not show fragment requirement")
	await press_interact()
	check(not service.is_gate_unlocked(gate_a) and not passage_clear(gate_room,true),"Insufficient fragments opened gate")
	var required := int(gate_a.fragments_per_key)
	# A fragment from another source level must not pay for this gate.
	var other_fragment: Dictionary = service.interval_definitions(2,0).fragment
	state.collect_fragment(other_fragment)
	var first_fragment_coords := Vector2i.ZERO
	for index in range(required):
		var definition: Dictionary = service.interval_definitions(1,index).fragment
		var coords := Vector2i(definition.x,definition.y)
		if index == 0: first_fragment_coords = coords
		room = await load_room(coords)
		var fragment := target_in(room,&"fragment")
		check(fragment != null,"Generated fragment missing")
		if fragment == null:
			quit(1)
			return
		await approach(fragment)
		# Blocked E must not be replayed once eligibility returns.
		if index == 0:
			player.set_movement_state(Player.MovementState.DASH_CHARGING,20)
			await press_interact()
			check(not state.fragments.has(definition.id),"Dash charging allowed interaction")
			player.reset_movement()
			await tick()
		Input.action_press("Interact")
		await tick()
		var count := state.collected_count(service.level_key(1))
		await tick(3)
		check(count == index+1 and state.collected_count(service.level_key(1)) == count,"Held E duplicated collection")
		check(not fragment.request.collect(),"Duplicate fragment collection accepted")
		check(not fragment.is_available(player) and controller.message.text.contains("fragment"),"Collection feedback/eligibility failed")
		Input.action_release("Interact")
		await tick()
	check(state.collected_count(service.level_key(2)) == 1,"Other-level fragments lost")
	await approach(gate)
	check(controller.prompt.text.contains("Unlock Level"),"Sufficient gate prompt missing")
	Input.action_press("Interact")
	await tick()
	check(state.collected_count(service.level_key(1)) == 0 and state.consumed_fragments.size() == required,"Unlock did not consume exact requirement")
	check(state.collected_count(service.level_key(2)) == 1,"Unlock spent fragments from wrong level")
	check(service.is_gate_unlocked(gate_a) and service.is_gate_unlocked(gate_b),"Destination gates did not unlock together")
	check(passage_clear(gate_room,true) and passage_clear(right_room,false) and passage_clear(other_gate_room,true),"Associated boundary tiles remain blocked")
	check(gate.get_node("Visuals").active and target_in(other_gate_room,&"gate").get_node("Visuals").active,"Associated gate visuals stayed locked")
	var spent := state.consumed_fragments.duplicate()
	await tick(4)
	check(not gate.request.unlock() and state.consumed_fragments == spent,"Unlock double-spent fragments")
	Input.action_release("Interact")
	var aperture := (gate_room.get_node("LevelBoundaryEast") as AbyssLevelBoundary).gate_cells[2]
	var query := PhysicsPointQueryParameters2D.new()
	query.position = gate_room.to_global((Vector2(aperture)+Vector2(0.5,0.5))*16)
	query.collision_mask = 1
	await tick(3)
	check(root.world_2d.direct_space_state.intersect_point(query).is_empty(),"Unlocked passage retained actual physics collision")
	player.health.current_health = 0
	await tick()
	check(not controller.actions_allowed() and state.consumed_fragments == spent,"Death modified progression or allowed interaction")
	player.health.reset_health()
	var saved_groups: Dictionary = game.abyss_room_state.groups.duplicate(true)
	var saved_markers: Dictionary = game.abyss_room_state.markers.duplicate(true)
	# Exercise the real save slot validation/load path using a temporary slot.
	runtime.leave()
	host.change_scene("res://Scenes/Village/House/house.tscn")
	await tick(2)
	var saves := root.get_node("SaveManager")
	saves.save_path = "/tmp/crunchy-interactions-smoke-save.json"
	check(saves.save_game(),"SaveManager save failed: "+saves.last_error)
	game.abyss_progression_state = AbyssProgressionState.new()
	check(saves.load_game(),"SaveManager load failed: "+saves.last_error)
	check(game.abyss_progression_state.consumed_fragments == spent and game.abyss_progression_state.fragments.has(other_fragment.id),"Save/load lost fragment ledger")
	check(game.abyss_room_state.groups == saved_groups and game.abyss_room_state.markers == saved_markers,"Progression changed room/breakable state")
	host.change_scene("res://Scenes/Underground/abyss_runtime.tscn")
	runtime = host.active_scene
	for frame in range(1200):
		if runtime.is_active() or not runtime.last_error.is_empty():break
		await tick()
	check(runtime.is_active(),"New descent after save failed")
	runtime.stream.active = false
	player = runtime.player
	player.set_physics_process(false)
	room = await load_room(first_fragment_coords)
	check(target_in(room,&"fragment") == null,"Consumed fragment respawned after save/new descent")
	room = await load_room(checkpoint_coords)
	check(target_in(room,&"checkpoint").get_node("Visuals").active,"Saved checkpoint lost activation")
	room = await load_room(Vector2i(gate_b.x,gate_b.y))
	check(passage_clear(room,true),"Gate relocked after save/new descent")
	game.abyss_room_state.begin_day(game.day+1)
	check(runtime.stream.specials.state.consumed_fragments == spent and passage_clear(room,true),"New day reset progression")
	var old_save: Dictionary = JSON.parse_string(runtime.stream.specials.state.serialize())
	old_save.version = 1
	old_save.erase("consumed_fragments")
	old_save.erase("unlocked_levels")
	old_save.gates[gate_a.id] = true
	var legacy := AbyssProgressionState.new()
	check(legacy.restore(JSON.stringify(old_save)) == OK and legacy.is_gate_unlocked(gate_b.id),"Legacy gate purchase did not preserve level-wide access")
	DirAccess.remove_absolute(saves.save_path)
	host.queue_free()
	await process_frame
	print("Abyss interactions: ",checks," checks; failures=",failures)
	quit(1 if failures else 0)
