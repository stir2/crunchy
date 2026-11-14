extends SceneTree
## Replay changes tutorial history only; no real save slots are used.
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func settle() -> void:
	for frame in 6:
		await process_frame
func snapshot(game: Node) -> Array:
	return [game.day, game.flesh, game.trips_left, game.potions, game.rations, game.health, game.stamina, game.stats.duplicate(true), game.abyss_room_state.serialize(), game.abyss_progression_state.serialize(), root.get_node("VillageManager").get_save_data().duplicate(true)]
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game := root.get_node("GameController")
	game.day = 3
	game.window_history = {"day1_tutorial_skipped":true,"day1_tutorial_toll":true,"day1_tutorial_field":true,"unrelated_story_event":true}
	var host = load("res://Scenes/Main/main.tscn").instantiate()
	root.add_child(host)
	current_scene = host
	host.change_scene(host.HOUSE_SCENE)
	await settle()
	var tutorial = host.active_scene.get_node("UI/DayOneTutorial")
	check(not tutorial.visible, "Late-game tutorial appeared without request")
	var before: Array = snapshot(game)
	host.pause_menu.toggle()
	host.pause_menu._open_help()
	check(paused and host.pause_menu._help.visible and not host.pause_menu.panel.visible, "Help did not keep gameplay paused")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	host.pause_menu._input(escape)
	check(paused and not host.pause_menu._help.visible and host.pause_menu.panel.visible, "Escape did not return to pause menu")
	host.pause_menu._open_help()
	host.pause_menu._replay_tutorials()
	check(snapshot(game) == before, "Area replay changed gameplay progress")
	check(game.window_history.has("day1_tutorial_field") and game.window_history.has("unrelated_story_event"), "House replay reset another area's or story flags")
	host.pause_menu.resume()
	await settle()
	check(tutorial.visible and tutorial._step == "toll", "House replay failed after Day 1/skipped tutorial")
	tutorial._advance()
	await settle()
	check(tutorial._step == "food", "Replayed house tutorial did not advance")
	var village := root.get_node("VillageManager")
	var worker = village.get_idle_workers()[0]
	check(village.assign(worker.id, &"farmer"), "Could not prepare staffed farm")
	host.active_scene.village_panel.show()
	await settle()
	check(tutorial._step == "village_done", "Completed staffing required repeating an action")
	host.active_scene.village_panel.hide()
	game.trips_left = 1
	host.active_scene.set_panel(host.active_scene.RoomPanel.STAIRS)
	await settle()
	check(tutorial.visible and tutorial._step == "stairs", "Replay hid stairs after completed trips")
	host.pause_menu.toggle()
	host.pause_menu._open_help()
	before = snapshot(game)
	host.pause_menu._replay_tutorials()
	check(snapshot(game) == before, "Repeated house replay changed gameplay progress")
	check(not game.window_history.has("tutorial_abyss_enabled") and game.window_history.has("day1_tutorial_field"), "House replay enabled Abyss guidance")
	host.pause_menu.resume()
	host.change_scene("res://Scenes/Underground/abyss_runtime.tscn")
	await settle()
	check(host.active_scene is AbyssRuntime, "Abyss did not load")
	var hud = host.active_scene.flesh_hud
	check(not hud._field_card.visible, "House replay leaked into Abyss guidance")
	hud._dismiss_field_note()
	host.pause_menu.toggle()
	host.pause_menu._open_help()
	before = snapshot(game)
	var house_history: Dictionary = game.window_history.duplicate(true)
	host.pause_menu._replay_tutorials()
	check(hud._field_card.visible and hud._field_note_timer.time_left > 19, "Current Abyss replay did not reopen/reset hint")
	check(snapshot(game) == before, "Abyss replay changed gameplay progress")
	check(paused, "Replay unexpectedly unpaused gameplay")
	for key in ["day1_tutorial_toll", "day1_tutorial_food", "day1_tutorial_prepare", "tutorial_house_enabled"]:
		check(game.window_history.get(key) == house_history.get(key), "Abyss replay changed house history")
	host.pause_menu._open_help()
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	host.pause_menu._input(start)
	check(not host.pause_menu._help.visible and paused, "Controller pause did not return from Help")
	hud.unbind()
	host.pause_menu._open_help()
	check(not host.pause_menu._help.visible and host.pause_menu._tutorial_target() == null, "Unbound Abyss HUD accepted Help")
	host.pause_menu.resume()
	host.change_scene(host.CUTSCENE_SCENE)
	await settle()
	host.pause_menu.toggle()
	host.pause_menu._open_help()
	check(not host.pause_menu.get_node("%HelpButton").visible and not host.pause_menu._help.visible, "Unsupported scene offered Help")
	var history_before: Dictionary = game.window_history.duplicate(true)
	host.pause_menu._replay_tutorials()
	check(game.window_history == history_before, "Unsupported scene changed tutorial history")
	host.pause_menu.resume()
	host.change_scene(host.HOUSE_SCENE)
	await settle()
	tutorial = host.active_scene.get_node("UI/DayOneTutorial")
	tutorial._skip_tutorial()
	await settle()
	check(not tutorial.visible and not game.window_history.has("tutorial_house_enabled") and not game.window_history.has("tutorial_abyss_enabled"), "Skip did not disable replay guidance")
	host.pause_menu.toggle()
	host.pause_menu._open_help()
	history_before = game.window_history.duplicate(true)
	# Main-hosted boss must not offer Help either.
	host.change_scene("res://Scenes/Boss/boss_arena.tscn")
	await settle()
	host.pause_menu._replay_tutorials()
	check(game.window_history == history_before and not host.pause_menu._help.visible, "Stale Help callback affected a changed scene")
	host.pause_menu.resume()
	host.pause_menu.toggle()
	host.pause_menu._open_help()
	check(not host.pause_menu.get_node("%HelpButton").visible and not host.pause_menu._help.visible, "Main-hosted boss offered Help")
	host.pause_menu.resume()
	host.free()
	await settle()
	# F6 boss is the scene root, with no Main.active_scene property.
	var boss = load("res://Scenes/Boss/boss_arena.tscn").instantiate()
	root.add_child(boss)
	current_scene = boss
	await settle()
	var menu = boss._pause_menu
	menu.toggle()
	history_before = game.window_history.duplicate(true)
	menu._open_help()
	menu._replay_tutorials()
	check(not menu.get_node("%HelpButton").visible and not menu._help.visible, "F6 boss offered Help")
	check(game.window_history == history_before and paused, "F6 boss Help changed history/pause")
	menu.resume()
	check(not paused, "F6 boss could not resume")
	boss.free()
	await settle()
	# Unknown roots and an empty current_scene are also unsupported.
	var unknown := Node2D.new()
	root.add_child(unknown)
	current_scene = unknown
	menu = load("res://Scenes/Menus/pause_menu.tscn").instantiate()
	unknown.add_child(menu)
	menu.toggle()
	menu._open_help()
	check(not menu.get_node("%HelpButton").visible and not menu._help.visible, "Unknown F6 root offered Help")
	menu.resume()
	current_scene = null
	check(menu._tutorial_target() == null, "Empty current_scene resolved a tutorial")
	unknown.free()
	# Direct house roots can still replay their own tutorial.
	var house = load("res://Scenes/Village/House/house.tscn").instantiate()
	root.add_child(house)
	current_scene = house
	menu = load("res://Scenes/Menus/pause_menu.tscn").instantiate()
	house.add_child(menu)
	await settle()
	menu.toggle()
	menu._open_help()
	check(menu._help.visible and menu._help_area.text == "Show house tutorial", "F6 house did not offer contextual Help")
	tutorial = house.get_node("UI/DayOneTutorial")
	for length in [5, 10]:
		game.run_length = length
		game.day = length
		game.boss_defeated = false
		game.monster_missing = false
		before = snapshot(game)
		tutorial.replay()
		tutorial._process(0)
		check(tutorial._step == "window" and tutorial._body.text.contains("Window"), "Final-day replay did not point to the Window")
		check(not tutorial._body.text.contains("Bring home") and not tutorial._body.text.contains("sleep"), "Final-day replay retained ordinary toll instructions")
		check(snapshot(game) == before, "Final-day replay changed campaign state")
		tutorial._advance()
		tutorial._process(0)
		check(not tutorial.visible, "Final-day guidance did not dismiss")
		game.monster_missing = true
		tutorial._process(0)
		check(tutorial._step == "investigate" and tutorial._body.text.contains("Stairs"), "Changed finale objective did not refresh guidance")
		game.boss_defeated = true
		tutorial._process(0)
		check(tutorial._step == "complete" and tutorial._body.text.contains("complete"), "Victory retained hunting guidance")
		tutorial._advance()
		tutorial._process(0)
		check(not tutorial.visible, "Victory guidance did not dismiss")
		tutorial.replay()
		tutorial._process(0)
		check(tutorial._step == "complete", "Victory guidance could not replay")
	tutorial.queue_free()
	history_before = game.window_history.duplicate(true)
	menu._replay_tutorials()
	check(game.window_history == history_before and not menu._help.visible, "Queued tutorial accepted stale replay")
	menu.resume()
	house.free()
	await settle()
	print("Tutorial replay: %d checks; failures=%d" % [checks, failures])
	quit(1 if failures else 0)


