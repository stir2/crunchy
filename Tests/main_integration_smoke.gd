extends SceneTree
## Main enemy rewards/parries against current runtime, HUD and pause behavior.
var checks: int = 0
var failures: int = 0

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

func run() -> void:
	var game := root.get_node("GameController")
	game.abyss_room_state = AbyssRoomState.new()
	game.abyss_progression_state = AbyssProgressionState.new()
	game.flesh = 146
	var unbound_enemy: CharacterBody2D = load("res://Scenes/Enemies/red_enemy.tscn").instantiate()
	unbound_enemy._collect_flesh_reward()
	check(game.flesh == 146 and game.abyss_room_state.exploration.descent_souls.is_empty(),"Unconfigured enemy lab created banked/orphan Flesh")
	unbound_enemy.free()
	var runtime := load("res://Scenes/Underground/abyss_runtime.tscn").instantiate() as AbyssRuntime
	runtime.auto_start = false
	runtime.configuration.global_seed = 12
	root.add_child(runtime)
	current_scene = runtime
	check(await runtime.enter_entrance(),"Integrated runtime startup failed")
	if not runtime.is_active():
		quit(1)
		return
	runtime.stream.active = false
	runtime.camera.set_physics_process(false)
	runtime.player.gravity_multiplier = 0
	runtime.player.collision_mask = 0
	var world := runtime.stream.specials.world
	var room := AbyssAuthoredRoom.new()
	room.room_size = Vector2i(40,40)
	room.construction_requirements = AbyssRoomRequirements.new()
	room.construction_requirements.global_coords = Vector2i(3,4)
	runtime.loaded_rooms.add_child(room)
	var expected := 0
	for kind in ["red","blue","green"]:
		var enemy: CharacterBody2D = load("res://Scenes/Enemies/"+kind+"_enemy.tscn").instantiate()
		enemy.target = runtime.player
		enemy.flesh_pickup_id = "integration-"+kind
		enemy.position = Vector2(2000,200)
		room.add_child(enemy)
		enemy.set_physics_process(false)
		expected += int(enemy.flesh_reward)
		enemy.take_damage(999)
		check(game.current_descent_flesh(world) == expected and game.flesh == 146,kind+" enemy bypassed descent Flesh accounting")
		enemy._on_died(CombatHit.new())
		check(game.current_descent_flesh(world) == expected,"Duplicate death paid twice")
	check(runtime.flesh_hud.displayed_previous == 146 and runtime.flesh_hud.pending_amount() == expected,"Enemy reward did not queue blue HUD animation")
	var duplicate: CharacterBody2D = load("res://Scenes/Enemies/red_enemy.tscn").instantiate()
	duplicate.target = runtime.player
	duplicate.flesh_pickup_id = "integration-red"
	room.add_child(duplicate)
	duplicate.set_physics_process(false)
	duplicate.take_damage(999)
	check(game.current_descent_flesh(world) == expected,"Stable enemy reward ID paid again after reconstruction")
	var parry_enemy: CharacterBody2D = load("res://Scenes/Enemies/red_enemy.tscn").instantiate()
	parry_enemy.target = runtime.player
	parry_enemy.position = Vector2(2500,200)
	room.add_child(parry_enemy)
	parry_enemy.set_physics_process(false)
	var player := runtime.player
	player.reset_movement()
	player.dash_direction = 1
	player.set_movement_state(Player.MovementState.DASHING,20)
	var hit := CombatHit.new()
	hit.source = parry_enemy
	hit.amount = 1
	hit.world_position = player.global_position+Vector2(24,-18)
	hit.direction = Vector2.LEFT
	var hp := player.health.current_health
	check(player.damage.try_dash_parry(hit) and player.health.current_health == hp,"Incoming melee dash parry failed")
	var remaining: int = player.damage._parry_flash_until-Engine.get_physics_frames()
	check(runtime.abyss_map.open_map(),"Map did not open during parry")
	await tick(15)
	runtime.abyss_map.close_map()
	check(player.damage._parry_flash_until-Engine.get_physics_frames() == remaining,"Map pause consumed parry flash")
	var shot: CombatDamageArea = load("res://Scenes/Enemies/enemy_projectile.gd").new()
	shot.source_actor = parry_enemy
	shot.travel_velocity = Vector2(-250,0)
	runtime.loaded_rooms.add_child(shot)
	shot.global_position = player.global_position+Vector2(24,-18)
	check(player.damage.try_dash_parry(hit,shot) and shot.reflected and shot.source_actor == player and shot.travel_velocity.x > 0,"Incoming projectile reflection failed")
	player.reset_movement()
	await tick(40)
	check(runtime.flesh_hud.displayed_current == expected and runtime.flesh_hud.displayed_previous == 146,"Enemy Flesh animation changed wrong balance")
	var sounds := root.get_node_or_null("SoundManager")
	check(sounds != null and sounds._progression == game.abyss_progression_state,"SoundManager autoload/progression binding missing")
	check(player.has_node("PlayerAudio"),"Main player audio component was not attached")
	runtime.leave()
	runtime.queue_free()
	await tick(3)
	print("Main integration: ",checks," checks; failures=",failures)
	quit(1 if failures else 0)
