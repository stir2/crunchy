extends SceneTree
## Fresh E/V channels, checkpoint healing and real host/standalone extraction.
var checks: int = 0
var failures: int = 0
var host: Node
var runtime: AbyssRuntime
var player: Player
var controller: PlayerInteractionController
var checkpoint_coords: Vector2i
var checkpoint_id: String
var world: String

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

func press(action: StringName) -> void:
	Input.action_release(action)
	await tick()
	Input.action_press(action)
	await tick()
	Input.action_release(action)
	await tick()

func settle() -> bool:
	for frame in range(1000):
		if runtime.is_active() or not runtime.last_error.is_empty(): break
		await tick()
	check(runtime.is_active(),"Lifecycle startup failed: "+runtime.last_error)
	if not runtime.is_active(): return false
	player = runtime.player
	controller = runtime.interactions
	world = runtime.stream.specials.world
	runtime.stream.active = false
	runtime.camera.set_physics_process(false)
	player.gravity_multiplier = 0
	player.collision_mask = 0
	player.stamina.regeneration_per_second = 0
	return true

func enter_runtime() -> bool:
	host.change_scene("res://Scenes/Underground/abyss_runtime.tscn")
	runtime = host.active_scene
	return await settle()

func approach_checkpoint() -> InteractionTarget:
	if not runtime.stream.rooms.has(checkpoint_coords): runtime.stream._build_room(checkpoint_coords)
	await tick(3)
	var room: AbyssAuthoredRoom = runtime.stream.rooms[checkpoint_coords]
	runtime.stream._settling.erase(checkpoint_coords)
	room.visible = true
	for node in room.get_children():
		if node is InteractionTarget and node.get("request") is AbyssSpecialSpawnRequest and node.request.kind == &"checkpoint":
			player.reset_movement()
			player.global_position = node.global_position+Vector2(0,18)
			checkpoint_id = node.request.definition.id
			await tick(2)
			return node
	return null

func run() -> void:
	var game := root.get_node("GameController")
	game.abyss_room_state = AbyssRoomState.new()
	game.abyss_progression_state = AbyssProgressionState.new()
	var region := AbyssRegionConfig.new()
	region.global_seed = 12
	region.noise_frequency = 0.085
	region.open_threshold = 0.0
	var progression := AbyssProgressionConfig.new()
	progression.checkpoint_probability = 1.0
	var configs: Array[Resource] = [region,AbyssRouteConfig.new(),AbyssTerrainConfig.new(),progression]
	game.abyss_room_state.world_settings = AbyssRuntimeWorldSettings.capture(configs,load("res://Scenes/Underground/Rooms/authored_registry.tres"))
	game.flesh = 146
	host = load("res://Scenes/Main/main.tscn").instantiate()
	root.add_child(host)
	current_scene = host
	var host_id := host.get_instance_id()
	if not await enter_runtime():
		quit(1)
		return
	check(controller.primary_action == &"Interact 1" and controller.travel_action == &"Interact 2","Input action names changed")
	check((InputMap.action_get_events("Interact 1")[0] as InputEventKey).physical_keycode == KEY_E and (InputMap.action_get_events("Interact 2")[0] as InputEventKey).physical_keycode == KEY_V,"E/V bindings changed")
	check(controller.travel_prompt.text == "V — Return to Village","Entrance travel prompt missing")
	await press(&"Interact 1")
	check(host.active_scene == runtime and not runtime._return_pending,"E extracted from entrance")
	# A blocked V must not replay after combat while the key remains held.
	Input.action_press("Attack")
	await tick()
	Input.action_release("Attack")
	Input.action_press("Interact 2")
	await tick()
	check(not runtime._return_pending and controller.travel_prompt.text.is_empty(),"Combat allowed extraction/prompt")
	for frame in range(150):
		await tick()
		if not player.combat.is_attacking(): break
	await tick(3)
	check(host.active_scene == runtime and not runtime._return_pending,"Held blocked V replayed after combat")
	Input.action_release("Interact 2")
	await tick()
	var found := false
	for y in range(2,12):
		for x in range(-8,9):
			var coords := Vector2i(x,y)
			if runtime.stream.specials.has_checkpoint(coords):
				checkpoint_coords = coords
				found = true
				break
		if found: break
	check(found,"Generated checkpoint fixture missing")
	if not found:
		quit(1)
		return
	var checkpoint := await approach_checkpoint()
	check(checkpoint != null,"Checkpoint object missing")
	if checkpoint == null:
		quit(1)
		return
	player.health.reset_health(4)
	player.stamina.reset_stamina(37)
	await tick()
	check(controller.prompt.text.contains("Activate Checkpoint") and controller.travel_prompt.text.is_empty(),"Inactive checkpoint shows wrong action prompts")
	var damage_hit := CombatHit.new()
	damage_hit.amount = 1
	check(player.damage.receive_hit(damage_hit),"Damage-reaction fixture failed")
	Input.action_press("Interact 1")
	Input.action_press("Interact 2")
	await tick()
	check(not game.abyss_progression_state.checkpoints.get(checkpoint_id,{}).get("activated",false) and not runtime._return_pending,"Damage reaction allowed E/V")
	player.health.reset_health(4)
	player.reset_movement()
	player.global_position = checkpoint.global_position+Vector2(0,18)
	await tick(2)
	check(not game.abyss_progression_state.checkpoints.get(checkpoint_id,{}).get("activated",false) and not runtime._return_pending,"Held blocked E/V replayed after damage")
	Input.action_release("Interact 1")
	Input.action_release("Interact 2")
	await tick()
	runtime.set_streaming_hold(true)
	Input.action_press("Interact 1")
	Input.action_press("Interact 2")
	await tick()
	check(controller.prompt.text.is_empty() and controller.travel_prompt.text.is_empty(),"Streaming hold retained interaction prompts")
	runtime.set_streaming_hold(false)
	await tick(2)
	check(not game.abyss_progression_state.checkpoints.get(checkpoint_id,{}).get("activated",false) and not runtime._return_pending,"Held blocked E/V replayed after streaming hold")
	Input.action_release("Interact 1")
	Input.action_release("Interact 2")
	await tick()
	await press(&"Interact 2")
	check(not game.abyss_progression_state.checkpoints.get(checkpoint_id,{}).get("activated",false) and player.health.current_health == 4,"V activated/healed inactive checkpoint")
	# Both fresh keys together must not unlock travel mid-tick on an inactive target.
	Input.action_press("Interact 1")
	Input.action_press("Interact 2")
	await tick()
	check(host.active_scene == runtime and game.abyss_progression_state.checkpoints[checkpoint_id].activated,"Simultaneous E/V extracted through newly activated checkpoint")
	Input.action_release("Interact 1")
	Input.action_release("Interact 2")
	await tick()
	check(player.health.current_health == 6 and player.stamina.current_stamina == 37,"Activation must heal exactly 2 HP and no stamina")
	check(controller.travel_prompt.text == "V — Return to Village","Activated checkpoint travel prompt missing")
	player.health.current_health = 4
	await press(&"Interact 1")
	check(player.health.current_health == 4,"Checkpoint healed twice in one descent")
	# Reconstruct from serialized room state in the same descent: charge stays spent.
	var restored := AbyssRoomState.new()
	check(restored.restore(game.abyss_room_state.serialize()) == OK,"Heal usage serialization failed")
	game.abyss_room_state = restored
	if not await enter_runtime():
		quit(1)
		return
	checkpoint = await approach_checkpoint()
	await press(&"Interact 1")
	check(player.health.current_health == 4 and not restored.exploration.checkpoint_heal_available(world,checkpoint_id),"Scene reload/save restored spent heal")
	game.collect_descent_flesh(world,24,player.global_position,"lifecycle-pickup")
	var trips: int = game.trips_left
	var day: int = game.day
	Input.action_press("Interact 2")
	await tick(3)
	check(host.get_instance_id() == host_id and host.active_path == host.HOUSE_SCENE,"Checkpoint return did not preserve Main/show village")
	check(game.flesh == 170 and game.current_descent_flesh(world) == 0,"Safe return failed one-time Flesh banking")
	check(game.health == 4 and game.stamina == 37,"V healed or changed carried vitals")
	check(game.trips_left == trips and game.day == day,"Return spent a trip or advanced day")
	check(host.active_scene.current_panel == host.active_scene.RoomPanel.STAIRS,"Return did not show village stairs")
	check(game.return_abyss_descent(world) == 0 and game.flesh == 170,"Return could bank twice")
	# Persist the spent heal/ended descent using the real village SaveManager.
	var saves := root.get_node("SaveManager")
	saves.save_path = "/tmp/crunchy-lifecycle-smoke.json"
	check(saves.save_game() and saves.load_game(),"Lifecycle save/load failed: "+saves.last_error)
	if not await enter_runtime():
		quit(1)
		return
	await tick(3)
	check(host.active_scene == runtime and not runtime._return_pending,"Held V instantly extracted on a new descent")
	Input.action_release("Interact 2")
	await tick()
	checkpoint = await approach_checkpoint()
	check(controller.prompt.text.contains("Heal 1 Heart") and controller.travel_prompt.text == "V — Return to Village","New descent should offer both E heal and V return")
	# V must not consume the newly available heal or restore HP.
	await press(&"Interact 2")
	check(host.active_path == host.HOUSE_SCENE and game.health == 4,"V healed an already-activated checkpoint")
	if not await enter_runtime():
		quit(1)
		return
	checkpoint = await approach_checkpoint()
	await press(&"Interact 1")
	check(player.health.current_health == 6,"Activated checkpoint did not heal on new descent")
	player.health.current_health = 4
	await press(&"Interact 1")
	check(player.health.current_health == 4,"Repeated E granted unlimited healing")
	game.collect_descent_flesh(world,5,player.global_position,"lifecycle-pickup-2")
	player.reset_movement()
	player.global_position = runtime.entrance_return.global_position+Vector2(0,18)
	await tick(2)
	await press(&"Interact 2")
	check(host.active_path == host.HOUSE_SCENE and game.flesh == 175,"Entrance V did not return/bank independently of activation")
	# F6 standalone extraction creates a persistent Main host without scene-tree replacement.
	host.queue_free()
	await tick()
	runtime = load("res://Scenes/Underground/abyss_runtime.tscn").instantiate() as AbyssRuntime
	root.add_child(runtime)
	current_scene = runtime
	if await settle():
		await press(&"Interact 2")
		check(current_scene != runtime and current_scene.has_method("change_scene") and current_scene.active_path == "res://Scenes/Village/House/house.tscn","Standalone safe return failed")
		current_scene.queue_free()
	DirAccess.remove_absolute(saves.save_path)
	await process_frame
	print("Abyss lifecycle: ",checks," checks; failures=",failures)
	quit(1 if failures else 0)
