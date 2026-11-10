extends SceneTree
## Focused integration check; all marker fixtures are in memory, never authored files.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func tick(count: int = 1) -> void:
	for index in range(count):
		await physics_frame
		await process_frame

func run() -> void:
	var game := root.get_node("GameController")
	game.abyss_room_state = AbyssRoomState.new()
	game.abyss_progression_state = AbyssProgressionState.new()
	game.day = 1
	var runtime: AbyssRuntime = load("res://Scenes/Underground/abyss_runtime.tscn").instantiate()
	runtime.auto_start = false
	runtime.apply_pixel_presentation = false
	# Stable fixture registry: designer edits to active rooms must not change this test.
	runtime.template_registry = load("res://Scenes/Underground/Rooms/example_registry.tres")
	runtime.configuration.global_seed = 12
	runtime.configuration.noise_frequency = 0.085
	runtime.configuration.open_threshold = 0.0
	root.add_child(runtime)
	check(await runtime.enter_entrance(), "Runtime startup failed")
	if not runtime.is_active(): quit(1); return
	runtime.player.get_node("Hurtbox").invulnerable = true
	var manager: Node2D = runtime.get_node("EnemyPopulation")
	manager.set_physics_process(false)
	var pool: AbyssEnemyPool = manager.enemy_pool
	var allowed := [[], ["shambler", "runner", "stalker"], ["runner", "stalker", "spider_rusher"], ["shambler", "runner", "stalker", "spider_rusher", "web_shooter"]]
	for level in range(1, 4):
		var seen := {}
		var valid := true
		for index in range(80):
			var selected := pool.select(level, "seed12/marker/%d" % index)
			valid = valid and selected != null and String(selected.enemy_id) in allowed[level]
			valid = valid and selected == pool.select(level, "seed12/marker/%d" % index)
			seen[String(selected.enemy_id)] = true
		check(valid and seen.size() == allowed[level].size(), "Wrong/non-deterministic level %d pool" % level)
	check(pool.select(0, "marker") == null, "Outside-level marker spawned an enemy")
	manager.clear_population()
	manager.records.clear()
	# A room with six author markers and a known existing safe landing.
	var coords := runtime.stream.current_room + Vector2i.RIGHT
	var room := runtime.stream.rooms[coords] as AbyssAuthoredRoom
	room.spawn_requests.clear()
	for index in range(6):
		var request := EnemySpawnRequest.new()
		request.marker_id = StringName("smoke_enemy_%d" % index)
		request.room_coords = coords
		request.selected = true
		request._state = game.abyss_room_state
		request._initial_world_position = runtime.player.global_position
		room.spawn_requests.append(request)
	manager.register_room(room)
	check(manager.records.size() == 3, "Room cap did not select three of six markers")
	var ids: Array = manager.records.keys()
	room.spawn_requests.reverse()
	manager.register_room(room)
	check(manager.records.keys() == ids, "Marker order changed selection or duplicated records")
	manager._restore_ready()
	check(manager.actors.size() == 3, "Missing marker actors")
	manager._restore_ready()
	check(manager.actors.size() == 3, "Duplicate actor spawn")
	manager._physics_process(0.01)
	check(manager.actors[ids[0]].process_mode == Node.PROCESS_MODE_INHERIT, "Nearby actor stayed suspended")
	for nearby: CharacterBody2D in manager.actors.values(): manager._set_simulation(nearby, false)
	var id: String = ids[0]
	var actor: CharacterBody2D = manager.actors[id]
	# Stalkers/shamblers have enough HP; use whichever selected actor has >1.
	for candidate: String in ids:
		if manager.actors[candidate].get_node("Damageable").health > 1:
			id = candidate
			actor = manager.actors[id]
			break
	var health_before: int = actor.get_node("Damageable").health
	actor.call("take_damage", 1)
	check(int(manager.records[id].health) == health_before - 1, "Injury was not recorded immediately")
	var injury_save := AbyssRoomState.new()
	check(injury_save.restore(game.abyss_room_state.serialize()) == OK and int(JSON.parse_string(injury_save.markers[id]).health) == health_before - 1, "Injury lost across save/load")
	manager._retire(id)
	manager._restore_ready()
	actor = manager.actors[id]
	check(actor.get_node("Damageable").health == health_before - 1, "Injury lost on actor reload")
	# Origin room unload must leave the actor in its currently loaded neighbor.
	check(runtime.stream.unload_room(coords), "Origin-room unload failed")
	check(manager.actors.has(id), "Cross-room actor was freed with its origin")
	runtime.stream.request_neighborhood(runtime.stream.current_room)
	for index in range(180):
		if runtime.stream.neighborhood_ready(runtime.stream.current_room) and not runtime._holding: break
		await tick()
	check(not runtime._holding, "Fixture terrain did not become ready again")
	var home: Node2D = manager._homes[id]
	actor.global_position = home.global_position + Vector2(1000, 0)
	manager._update_pursuit(id, actor, 0.1)
	check(actor.get("target") == home, "Pursuit did not retarget home beyond its leash")
	manager._physics_process(0.01)
	check(actor.process_mode == Node.PROCESS_MODE_DISABLED, "Distant actor kept processing")
	actor.global_position = runtime.player.global_position
	manager._snapshot(id)
	var bank_before: int = game.flesh
	var carried_before: int = game.current_descent_flesh(runtime.stream.specials.world)
	actor.call("take_damage", 999)
	check(manager.records[id].defeated and manager.drops.has(id), "Death did not persist/create physical drop")
	check(game.flesh == bank_before and game.current_descent_flesh(runtime.stream.specials.world) == carried_before, "Enemy death automatically awarded Flesh")
	manager._enemy_died(id)
	check(manager.drops.size() == 1, "Duplicate death created another drop")
	manager._restore_ready()
	check(not manager.actors.has(id), "Defeated enemy respawned")
	# Uncollected drop survives a full actor/drop teardown and save round trip.
	manager.clear_population()
	var saved := AbyssRoomState.new()
	check(saved.restore(game.abyss_room_state.serialize()) == OK, "Enemy/drop save round trip rejected")
	check(JSON.parse_string(saved.markers[id]).defeated and not JSON.parse_string(saved.markers[id]).drop_collected, "Uncollected death/drop state lost")
	manager._restore_ready()
	var drop: Area2D = manager.drops[id]
	drop.global_position = runtime.player.global_position
	var reward: int = manager.records[id].reward
	await tick(40) # Real body overlap -> hover -> collect -> HUD flights.
	check(manager.records[id].drop_collected, "Touch pickup did not collect")
	check(game.current_descent_flesh(runtime.stream.specials.world) == carried_before + reward, "Touch reward amount incorrect")
	check(not manager.collect_drop(id), "Repeated collection paid twice")
	check(runtime.flesh_hud.displayed_current + runtime.flesh_hud.pending_amount() == carried_before + reward, "HUD flight accounting incorrect")
	manager.clear_population()
	manager._restore_ready()
	check(not manager.drops.has(id) and not manager.actors.has(id), "Collected drop or dead enemy respawned")
	var after := AbyssRoomState.new()
	check(after.restore(game.abyss_room_state.serialize()) == OK and JSON.parse_string(after.markers[id]).drop_collected, "Collected drop lost across save/load")
	# Day transition uses the existing lifecycle; only adapter namespace is reset.
	game.abyss_room_state.begin_day(2)
	manager._bind()
	check(not manager.records.has(id), "Yesterday's enemy did not reset")
	# Re-register same marker fixture to verify a fresh, living daily encounter.
	room = runtime.stream.rooms[runtime.stream.current_room]
	room.spawn_requests.clear()
	var fresh := EnemySpawnRequest.new()
	fresh.marker_id = &"next_day_enemy"
	fresh.room_coords = runtime.stream.current_room
	fresh.selected = true
	fresh._state = game.abyss_room_state
	fresh._initial_world_position = runtime.player.global_position
	room.spawn_requests.append(fresh)
	manager.register_room(room)
	manager._restore_ready()
	check(manager.actors.size() == 1, "Next-day marker did not spawn")
	# Exercise normal adapter/AI scheduling briefly on settled terrain.
	manager.set_physics_process(true)
	await tick(4)
	check(manager.actors.size() == 1, "Live simulation lost its managed actor")
	runtime.leave()
	runtime.queue_free()
	await tick(3)
	print("Abyss enemies: %d checks; failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
