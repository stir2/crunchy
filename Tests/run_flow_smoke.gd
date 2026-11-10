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
	hit.amount = 999
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
