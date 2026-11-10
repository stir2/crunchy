extends SceneTree
## Production scenes with a temporary save slot. No fixture edits to spawning or balance.

const MENU := "res://Scenes/Menus/main_menu.tscn"
const HOUSE := "res://Scenes/Village/House/house.tscn"
const BOSS := "res://Scenes/Boss/boss_arena.tscn"

var failures := 0
var host: Node
var saves: Node

func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func wait_for(condition: Callable) -> bool:
	for frame in range(1800):
		if condition.call():
			return true
		await process_frame
	return false


func check_boss_settles(monster: Node, retract: int) -> void:
	check(await wait_for(func():
		return monster.phase == retract and monster.elapsed >= monster.duration - 0.03
	), "Boss did not play the end of its retract animation")
	var drawings: Array[Texture2D] = []
	var positions: Array[Vector2] = []
	var scales: Array[Vector2] = []
	for layer: Sprite2D in monster._art._layers:
		drawings.append(layer.texture)
		positions.append(layer.position)
		scales.append(layer.scale)
	check(await wait_for(func(): return monster.phase == monster.Phase.REST), "Boss did not settle to idle after retracting")
	for i in monster._art._layers.size():
		var layer: Sprite2D = monster._art._layers[i]
		check(layer.visible and layer.modulate.a == 1.0 and layer.texture == drawings[i]
			and layer.position.distance_to(positions[i]) < 3.0 and layer.scale.distance_to(scales[i]) < 0.03,
			"Boss layer %s swapped silhouettes or jumped between retract and idle" % i)


func check_cutscene_pause() -> void:
	var cutscene: Node = host.active_scene
	if not await wait_for(func(): return not cutscene._intro_running):
		check(false, "Quota cutscene never accepted input")
		return
	var phase: int = cutscene._phase
	for button in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		var scroll := InputEventMouseButton.new()
		scroll.button_index = button
		scroll.pressed = true
		cutscene._unhandled_input(scroll)
	check(cutscene._phase == phase, "Mouse wheel skipped the quota cutscene")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	cutscene._unhandled_input(click)
	check(cutscene._phase == cutscene.Phase.HOLD, "Click could not reveal the quota")
	host.pause_menu.toggle()
	await create_timer(cutscene.HOLD_TIME + 0.2).timeout
	check(cutscene._phase == cutscene.Phase.HOLD, "Paused quota reveal expired")
	host.pause_menu.resume()


func check_blocked_extraction(abyss: AbyssRuntime) -> void:
	var entrance := abyss.entrance_return.global_position
	var origin := abyss.interactions.origin.global_position
	var wall := StaticBody2D.new()
	wall.position = origin + Vector2(21, 0)
	var collision := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(8, 60)
	collision.shape = box
	wall.add_child(collision)
	abyss.add_child(wall)
	abyss.entrance_return.global_position = origin + Vector2(42, 0)
	await physics_frame
	await physics_frame
	abyss.interactions._update_prompt()
	check(abyss.interactions.travel_prompt.text.is_empty(), "Exit prompt showed through a wall")
	check(not abyss.request_safe_return(abyss.entrance_return), "Extracted through a wall")
	wall.queue_free()
	abyss.entrance_return.global_position = entrance
	await physics_frame


func finish() -> void:
	if saves != null:
		DirAccess.remove_absolute(saves.save_path)
		DirAccess.remove_absolute(saves.save_path + ".tmp")
	print("Run flow smoke: failures=", failures)
	quit(int(failures > 0))


func run() -> void:
	var game := root.get_node("GameController")
	var village := root.get_node("VillageManager")
	saves = root.get_node("SaveManager")
	saves.save_path = "user://run-flow-%d.json" % OS.get_process_id()
	change_scene_to_file("res://Scenes/Main/main.tscn")
	if not await wait_for(func(): return current_scene != null):
		check(false, "Main did not open")
		finish()
		return
	host = current_scene
	host.active_scene.get_node("%NewGameButton").pressed.emit()
	await check_cutscene_pause()
	if not await wait_for(func(): return host.active_path == HOUSE and not host._transitioning):
		check(false, "New Game did not reach the village")
		finish()
		return

	var workers: Array = village.get_idle_workers()
	var jobs: Array[StringName] = [&"apothecary", &"blacksmith", &"farmer"]
	for index in jobs.size():
		check(village.assign(workers[index].id, jobs[index]), "Assignment failed")
	check(game.village_health == 76, "Village health did not update after staffing")
	game.window_history["descend_first"] = true
	var house: Node = host.active_scene
	house._descend()
	var abyss := host.active_scene as AbyssRuntime
	check(game.trips_left == 3, "Trip spent before loading finished")
	if abyss == null or not await wait_for(abyss.is_active):
		check(false, "Descent failed")
		finish()
		return
	check(game.trips_left == 2, "Successful entry did not consume exactly one trip")
	check(abyss.player.health.max_health == 8 and abyss.player.stamina.max_stamina == 115, "Village vitals did not reach the Abyss")
	check(abyss.player.combat.attack_damage == 3, "Blacksmith bonus or Abyss baseline incorrect")
	check(is_equal_approx(abyss.player.stamina.regeneration_per_second, 3.3), "Abyss Farmer percentage incorrect")
	var hit := CombatHit.new()
	abyss.player.health.take_damage(hit)
	var remaining := abyss.player.health._invulnerable_until - Engine.get_physics_frames()
	host.pause_menu.toggle()
	for frame in range(90):
		await physics_frame
	host.pause_menu.resume()
	check(remaining == abyss.player.health._invulnerable_until - Engine.get_physics_frames(), "Pause consumed immunity")
	abyss.player.health.reset_health()
	await check_blocked_extraction(abyss)
	game.collect_descent_flesh(abyss.stream.specials.world, game.current_quota())
	check(abyss.request_safe_return(abyss.entrance_return), "Could not extract at the entrance")
	if not await wait_for(func(): return host.active_path == HOUSE):
		check(false, "Extraction did not return to the village")
		finish()
		return
	check(game.flesh == 12, "Extraction did not bank the toll")
	check(saves.save_game(), "Current layout save failed")
	host.change_scene(MENU)
	check(host.continue_game(), "Current layout Continue failed")
	if not await wait_for(func(): return host.active_path == HOUSE and not host._transitioning):
		check(false, "Continue did not return to the village")
		finish()
		return
	check(game.flesh == 12 and game.trips_left == 2, "Continue lost daily progress")
	host.active_scene._on_sleep_requested()
	if not await wait_for(func(): return host.active_path == host.CUTSCENE_SCENE):
		check(false, "Sleep did not reach the morning cutscene")
		finish()
		return
	if not await wait_for(func(): return host.active_path == HOUSE and not host._transitioning):
		check(false, "Morning cutscene did not reach the village")
		finish()
		return
	check(game.day == 2 and game.flesh == 0 and game.trips_left == 3, "Daily progress did not reset")

	while host.active_scene.refugee_modal.visible:
		host.active_scene._on_turn_away_refugee_pressed()
	var second_house: Node = host.active_scene
	second_house._on_sleep_requested()
	check(second_house.sleep_dialog.visible and second_house.sleep_dialog.dialog_text.contains("monster will choose"), "Sleep did not show a large shortfall")
	second_house.sleep_dialog.hide()
	game.flesh = 16
	second_house._on_sleep_requested()
	check(second_house.sleep_dialog.visible and second_house.sleep_dialog.dialog_text.contains("You will choose"), "Sleep did not show the close-toll choice")
	second_house.sleep_dialog.hide()
	game.flesh = 0
	check(game.day == 2 and not game.night_in_progress, "Dismissed sleep confirmation advanced the day")
	var current_settings: Dictionary = game.abyss_room_state.world_settings.duplicate(true)
	var room_state: AbyssRoomState = game.abyss_room_state
	room_state.world_settings.erase("2")
	check(saves.save_game(), "Could not create the incomplete save fixture")
	check(not saves.load_game() and saves.last_error.contains("incomplete"), "Incomplete terrain settings passed Continue validation")
	check(game.abyss_room_state == room_state, "Rejected Continue modified the active run")
	room_state.world_settings = current_settings.duplicate(true)
	room_state.world_settings.version = 1
	check(saves.save_game(), "Could not create the legacy save fixture")
	check(not saves.load_game() and not saves.last_error.is_empty(), "Legacy layout passed Continue validation")
	host.active_scene._descend()
	abyss = host.active_scene as AbyssRuntime
	check(abyss != null and not abyss.last_error.is_empty() and game.trips_left == 3, "Failed descent consumed a trip or hid the error")
	if abyss == null:
		finish()
		return
	abyss.get_node("StartupStatusCanvas/Panel/ReturnButton").pressed.emit()
	check(host.active_path == HOUSE, "Failed descent did not provide a return route")
	game.abyss_room_state.world_settings = current_settings

	# Jump to the end-state setup to keep the regression independent of encounter balance.
	game.day = 10
	game.start_day()
	game.monster_missing = true
	host.active_scene._descend()
	check(host.active_path == BOSS, "Day 10 did not open the boss")
	var arena: Node = host.active_scene
	check(is_equal_approx(arena.player.stamina.regeneration_per_second, 3.3), "Boss Farmer percentage incorrect")
	var monster: Node = arena.monster
	var boss_cues: Array[StringName] = []
	arena.child_entered_tree.connect(func(child: Node):
		if child is AudioStreamPlayer:
			boss_cues.append(child.name))
	arena.player.get_node("Hurtbox").invulnerable = true
	arena.player.position.x = 100
	check(await wait_for(func(): return monster.phase == monster.Phase.SWIPE_WINDUP and monster._layer_alpha.y > 0.99), "Sweep did not render the authored left arm during windup")
	check(await wait_for(func(): return monster.phase == monster.Phase.SWIPE_DRAG), "Left-side positioning did not draw a sweep")
	check(monster.left_attack.active and not monster.right_attack.active, "Upper sweep enabled the wrong hand")
	check(not arena.get_node("Effects").get_children().any(func(effect: Node): return effect is Sprite2D), "Sweep added a second airborne dust effect")
	var dust_positions: Array[Vector2] = []
	monster.ground_impact.connect(func(point: Vector2, heavy: bool):
		if monster.phase == monster.Phase.SWIPE_DRAG and not heavy:
			dust_positions.append(point))
	var sweep_start: float = monster.left.position.x
	check(await wait_for(func(): return monster.phase == monster.Phase.SWIPE_RECOVER), "Sweep did not open a punish window")
	check(monster.left.position.x - sweep_start > 480 and dust_positions.size() >= 10, "Sweep did not cross the arena and trail dust")
	if dust_positions.size() >= 2:
		check(dust_positions[-1].x - dust_positions[0].x > 470, "Sweep dust stayed in one location")
	check(not monster.left_hurt.invulnerable and monster.right_hurt.invulnerable, "Sweep opened the wrong hand")
	hit.amount = 48
	monster.health.take_damage(hit)
	await check_boss_settles(monster, monster.Phase.SWIPE_RETRACT)
	var waves := arena.get_node("Waves")
	check(await wait_for(func(): return waves.active), "Boss did not summon the intermission")
	var families: Array[int] = []
	waves.wave_started.connect(func(family: int): families.append(family))
	for tick in 750:
		if not waves.active:
			break
		for enemy: Node in waves._live.duplicate():
			enemy.take_damage(999)
		await process_frame
	check(families == [0, 1] and not waves.active, "Zombie and spider waves did not complete in order")
	hit.amount = 55
	monster.health.take_damage(hit)
	check(await wait_for(func(): return arena._dropping), "Boss did not start the floor break")
	check(monster._strike_frame == 43 and monster._layer_alpha.z == 1.0, "Floor-breaking slam did not render JV's impact pose")
	check(await wait_for(func(): return arena._hud.has_node("FallingVillagers")), "Arena fall did not show village portraits")
	check(arena._hud.get_node("FallingVillagers").get_child_count() > 0, "The fall showed no villagers from the run")
	check(await wait_for(func(): return arena._lower and not arena._dropping), "Boss did not complete the floor break")
	check(not arena._hud.has_node("FallingVillagers"), "Portrait echoes stayed on screen after landing")
	check(monster.phase == monster.Phase.BREAK_RETRACT and monster._layer_alpha.z > 0.99
		and not monster.left_attack.active and not monster.right_attack.active,
		"Phase-two handoff dropped the authored claw pose or enabled an attack before retracting")
	check(monster.health.current_health == 77 and monster.position.y == arena.LOWER_OFFSET, "Floor break reset boss health or left the boss behind")
	check(arena.get_node("Terrain").get_cell_source_id(Vector2i(10, 19)) == -1 and arena._lower_floor_row(20) > arena._lower_floor_row(30), "Lower arena did not replace the upper floor with a dip")
	arena.player.position = Vector2(486, arena.LOWER_OFFSET + 303)
	await check_boss_settles(monster, monster.Phase.BREAK_RETRACT)
	check(await wait_for(func(): return monster.phase == monster.Phase.VOLLEY and monster.elapsed > 0.45), "Lower arena skipped the volley windup")
	check(monster._body_shift.length() > 10 and get_nodes_in_group("enemy_projectiles").is_empty(), "Volley fired without visible anticipation")
	var paused_windup: float = monster.elapsed
	host.pause_menu.toggle()
	await create_timer(0.5).timeout
	check(monster.elapsed == paused_windup and get_nodes_in_group("enemy_projectiles").is_empty(), "Volley advanced while paused")
	host.pause_menu.resume()
	check(await wait_for(func(): return get_nodes_in_group("enemy_projectiles").size() >= 7), "First volley did not fire a multi-shot fan")
	check(await wait_for(func(): return get_nodes_in_group("enemy_projectiles").size() >= 14), "Fan pulses never overlapped")

	var chief: Player = arena.player
	var hurtbox: PlayerHurtbox = chief.get_node("Hurtbox")
	var prior_health := chief.health.current_health
	chief.set_physics_process(false)
	hurtbox.invulnerable = false
	for direction in [-1.0, 1.0]:
		chief.set_movement_state(Player.MovementState.DASHING, 9)
		chief.dash_direction = direction
		arena._fire_web(chief.global_position - Vector2(0, 32), Vector2(0, 280))
		var shot: Node = arena.get_node("Effects").get_child(-1)
		check(await wait_for(func(): return not is_instance_valid(shot) or shot.reflected), "Overhead web did not contact the Chief")
		check(is_instance_valid(shot) and shot.reflected, "Overhead web could not be reflected in dash direction %s" % direction)
	check(chief.health.current_health == prior_health, "Reflected web still dealt damage")
	chief.reset_movement()
	hurtbox.invulnerable = true
	chief.set_physics_process(true)

	check(await wait_for(func(): return monster.left_attack.active and monster.right_attack.active), "Lower combo never overlapped both attacks")
	check(monster.right.position.x == 486 and monster.left.position.x > 240, "Red claw left its fixed right lane during the sweep")
	chief.set_physics_process(false)
	hurtbox.invulnerable = false
	chief.set_movement_state(Player.MovementState.DASHING, 9)
	chief.dash_direction = -1.0
	chief.global_position = monster.left.global_position + Vector2(24, 0)
	hurtbox.poll_damage_areas()
	check(not monster.left_attack.active and monster.right_attack.active, "Sweep parry did not consume only the left hit")
	chief.global_position = monster.right.global_position + Vector2(20, 0)
	hurtbox.poll_damage_areas()
	check(not monster.right_attack.active and chief.health.current_health == prior_health, "Right slam was not independently parryable")
	chief.reset_movement()
	hurtbox.invulnerable = true
	chief.set_physics_process(true)
	check(await wait_for(func(): return monster.phase == monster.Phase.SWIPE_RECOVER), "Lower combo did not open a punish window")
	var terrain: TileMapLayer = arena.get_node("Terrain")
	check(terrain.get_cell_source_id(Vector2i(30, 41)) == -1 and terrain.get_cell_source_id(Vector2i(30, 42)) != -1, "Breakable slab was not removed above its support floor")
	check(monster.duration >= 3.2 and not monster.left_hurt.invulnerable and not monster.right_hurt.invulnerable, "Baited slam and web parry did not extend the combo punish window")
	check(await wait_for(func(): return chief.is_on_floor() and chief.position.y > 665), "Chief did not fall into the recess after the slab broke")
	await check_boss_settles(monster, monster.Phase.SWIPE_RETRACT)
	check(await wait_for(func():
		return get_nodes_in_group("enemy_projectiles").filter(func(web: Node): return is_equal_approx(web.travel_velocity.x, 74.0)).size() >= 7
	), "Second volley did not fire a staggered curtain")
	chief.position = Vector2(136, arena.LOWER_OFFSET + 248)
	chief.reset_movement()
	check(await wait_for(func(): return monster.phase == monster.Phase.SWIPE_DROP and monster.right_attack.active), "Reverse combo did not slam before the sweep started")
	hurtbox.invulnerable = false
	check(await wait_for(func(): return monster.phase == monster.Phase.SWIPE_DRAG and monster.left.position.x > 560 and not monster.right_attack.active), "Second lower combo did not separate the two hits")
	check(await wait_for(func(): return monster.phase == monster.Phase.SWIPE_RECOVER), "Second lower combo never finished")
	check(chief.health.current_health == prior_health and chief.position.y < arena.LOWER_OFFSET + 259, "Sweep hit the Chief on the refuge shelf")

	hurtbox.invulnerable = true
	chief.position = Vector2(330, arena.LOWER_OFFSET + 335)
	chief.reset_movement()
	check(await wait_for(func(): return monster.phase == monster.Phase.SWIPE_DRAG and monster.elapsed >= 0.53), "Third combo did not start its forward sweep")
	hurtbox.invulnerable = false
	Input.action_press("Jump")
	check(await wait_for(func(): return monster.elapsed >= 0.88), "Sweep did not pass the jumping Chief")
	Input.action_release("Jump")
	check(chief.position.y < arena.LOWER_OFFSET + 300 and chief.health.current_health == prior_health, "A normal jump did not clear the forward sweep in the basin")
	arena.player.health.reset_health()
	game.village_health = 0
	hit.amount = 999
	arena.player.position.y -= 65.0
	arena.player.health.take_damage(hit)
	var chief_sprite := chief.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	await physics_frame
	check(chief.is_physics_processing() and not arena._hud.has_node("VillageRevival"), "Revival cut away before the airborne Chief could land")
	# The final grave frame is timed to the wall-clock death audio.
	var revival_deadline := Time.get_ticks_msec() + 6500
	while chief_sprite.animation != &"death" or chief_sprite.frame < chief_sprite.sprite_frames.get_frame_count(&"death") - 1 or chief_sprite.is_playing():
		if Time.get_ticks_msec() >= revival_deadline:
			break
		await process_frame
	check(chief_sprite.animation == &"death" and chief_sprite.frame == chief_sprite.sprite_frames.get_frame_count(&"death") - 1, "Death animation did not settle on the grave")
	check(not arena._hud.has_node("VillageRevival"), "Villagers appeared before the grave had a beat on screen")
	check(await wait_for(func(): return arena._hud.has_node("VillageRevival") and not chief.health.is_dead()), "Chief did not revive behind the overlay")
	check(not chief.is_physics_processing() and chief_sprite.animation != &"death", "Revival reveal exposed a dead pose or resumed controls too early")
	check(await wait_for(func(): return arena._revival_used and not arena._reviving and not arena.player.health.is_dead()), "Chief did not receive the village revival")
	check(arena.player.health.current_health == ceili(arena.player.health.max_health * 0.75), "Low village health did not grant the minimum revival heal")
	check(arena._lower and monster.health.current_health == 77, "Revival reset the boss phase or health")
	for cue: StringName in [&"Cue_monster_rumbling_1", &"Cue_monster_rumbling_2", &"Cue_hard_land_stone", &"Cue_gate_unlock", &"Cue_toll_impact", &"Cue_night_bell-1", &"Cue_geiger_counter_tick"]:
		check(boss_cues.has(cue), "Boss fight missed audio cue %s" % cue)
	arena.player.health.take_damage(hit)
	# The death pose waits for audio playback, which uses wall time even at fixed FPS.
	var defeat_deadline := Time.get_ticks_msec() + 6000
	while not arena._result.visible and Time.get_ticks_msec() < defeat_deadline:
		await process_frame
	check(arena._result.visible, "Boss defeat result did not appear")
	check(not game.boss_defeated and arena._retry_button.visible, "Defeat incorrectly ended the run or hid retry")
	arena._retry()
	arena = host.active_scene
	arena.monster.health.take_damage(hit)
	check(await wait_for(func(): return arena._result.visible), "Boss victory result did not appear")
	check(game.boss_defeated and not arena._retry_button.visible, "Victory did not complete the run")
	arena._return_home()
	check(host.active_scene.descend_btn.disabled, "Finished run can enter the boss again")
	check(saves.save_game(), "Completed run could not be saved")
	game.boss_defeated = false
	check(saves.load_game() and game.boss_defeated, "Continue lost the victory flag")
	host.queue_free()
	await process_frame
	finish()
