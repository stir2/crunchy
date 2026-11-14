extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func settle() -> void:
	for frame in range(5):
		await process_frame
func contained(control: Control, bounds: Rect2, label: String) -> void:
	check(bounds.grow(1).encloses(control.get_global_rect()), label + " extends outside the viewport")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game := root.get_node("GameController")
	game.day = 10
	game.window_history["day_10_morning"] = true
	var viewport := root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var host: Node = load("res://Scenes/Main/main.tscn").instantiate()
	viewport.add_child(host)
	current_scene = host
	for dimensions in [Vector2i(640,360),Vector2i(824,789),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080),Vector2i(720,1280),Vector2i(320,568)]:
		viewport.size = dimensions
		var bounds := Rect2(Vector2.ZERO,Vector2(dimensions))
		host.change_scene(host.CUTSCENE_SCENE)
		var cutscene: Control = host.active_scene
		await settle()
		cutscene._reels[0].snap_to_final()
		await settle()
		var reel: Control = cutscene._reels[0]
		var icon: Control = reel._slots[1][0].get_node("InfinityIcon")
		check(icon.visible, "Final reel did not show the pixel infinity")
		check(icon.get_global_rect().get_center().distance_to(cutscene.housing.get_global_rect().get_center()) < 1, "Infinity is not centered inside its housing")
		check(cutscene.housing.get_global_rect().get_center().distance_to(bounds.get_center()) < 1, "Quota housing is not centered in the viewport")
		contained(cutscene.housing,bounds,"Quota housing")
		host.change_scene(host.MENU_SCENE)
		await settle()
		var menu: Control = host.active_scene
		contained(menu.get_node("Buttons"),bounds,"Main menu buttons")
		var settings: Control = menu.get_node("SettingsPanel")
		settings.open()
		await settle()
		contained(settings._paper,bounds,"Settings")
		check(settings._paper.get_global_rect().get_center().distance_to(bounds.get_center()) < 1,"Settings is not centered after resize")
		host.change_scene(host.HOUSE_SCENE)
		await settle()
		host.pause_menu.toggle()
		await settle()
		contained(host.pause_menu.get_node("Panel/Layout/Paper"),bounds,"Pause menu")
		var resume_button: Button = host.pause_menu.get_node("%ResumeButton")
		check(resume_button.get_global_rect().size.x <= 240, "Pause button is excessively wide")
		var pause_paper: Control = host.pause_menu.get_node("Panel/Layout/Paper")
		var paper_bounds := pause_paper.get_global_rect()
		for button_name in ["ResumeButton", "SaveButton", "MainMenuButton", "SettingsButton", "QuitButton", "HelpButton"]:
			var button: Button = host.pause_menu.get_node("%" + button_name)
			var button_bounds := button.get_global_rect()
			check(button_bounds.size.x <= paper_bounds.size.x * 0.72, "Pause button crowds the parchment edges")
			check(absf(button_bounds.get_center().x - paper_bounds.get_center().x) <= 4, "Pause button is not centered on the parchment")
		host.pause_menu._open_help()
		await settle()
		var help_paper: Control = host.pause_menu._help_paper
		contained(help_paper, bounds, "Help")
		check(help_paper.get_global_rect().get_center().distance_to(bounds.get_center()) < 1, "Help is not centered")
		host.pause_menu._close_help()
		host.pause_menu._confirm_leave(false)
		await settle()
		contained(host.pause_menu.get_node("LeaveDialog/Layout/Paper"),bounds,"Leave dialog")
		host.pause_menu.resume()
	# Exercise the presentation actually selected by AbyssRuntime, then restore it.
	game.day = 1
	game.boss_defeated = false
	game.monster_missing = false
	host.change_scene("res://Scenes/Underground/abyss_runtime.tscn")
	for frame in 1500:
		if host.active_scene.is_active(): break
		await process_frame
	var abyss: AbyssRuntime = host.active_scene
	check(abyss.is_active(), "Actual Abyss presentation did not start")
	var hud: AbyssFleshHUD = abyss.flesh_hud
	for dimensions in [Vector2i(640,360), Vector2i(1280,720), Vector2i(1920,1080), Vector2i(824,789), Vector2i(720,1280)]:
		root.size = dimensions
		hud.replay()
		await settle()
		var logical := root.get_visible_rect().size
		var bounds := Rect2(Vector2.ZERO, logical)
		var hint := hud._field_card.get_global_rect()
		contained(hud._field_card, bounds, "Actual Abyss hint")
		check(hint.size.x <= logical.x * 0.4 and hint.size.y <= logical.y * 0.4, "Hint dominates the actual Abyss viewport")
		check(hint.position.y >= abyss.abyss_map._minimap.get_global_rect().end.y, "Hint overlaps the minimap")
		host.pause_menu.toggle()
		host.pause_menu._open_help()
		await settle()
		var paper: Control = host.pause_menu._help_paper
		contained(paper, bounds, "Actual Abyss Help")
		check(paper.get_global_rect().size.x <= logical.x * 0.5 and paper.get_global_rect().size.y <= logical.y * 0.6, "Help dominates the actual Abyss viewport")
		host.pause_menu._show_controls(true)
		await settle()
		contained(paper, bounds, "Controls reference")
		check(host.pause_menu._controls_label.get_global_rect().position.x >= paper.get_global_rect().position.x + 16 * paper.scale.x, "Controls text lacks a left inset")
		check(host.pause_menu._controls_label.text.contains("Jump:") and host.pause_menu._controls_label.text.contains("Dash:"), "Keyboard reference missing core controls")
		check(host.pause_menu._controls_text(true).contains("Travel: RT"), "Controller travel reference is wrong")
		Input.action_press("Move Down")
		for frame in 12: await physics_frame
		Input.action_release("Move Down")
		check(host.pause_menu._controls_scroll.scroll_vertical > 0, "Controller/keyboard cannot scroll Controls")
		host.pause_menu._close_help()
		check(host.pause_menu._help.visible and not host.pause_menu._controls_scroll.visible and paused, "Controls Back did not return to paused Help")
		host.pause_menu.resume()
		hud._show_field_note("Flesh collected", "Return to the entrance to bring your carried Flesh home.")
		await settle()
		check(hud._field_card.get_global_rect().size.y <= hint.size.y, "Short pickup note retained tall empty paper")
		check(abyss.abyss_map.open_map(), "Actual-scale map did not open")
		await settle()
		check(abyss.abyss_map.view.size.y >= logical.y * 0.55, "Compact legend crowds the actual-scale map")
		contained(abyss.abyss_map.get_node("Panel/Legend"), bounds, "Actual-scale compact legend")
		abyss.abyss_map.close_map()
	host.change_scene(host.HOUSE_SCENE)
	await settle()
	check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED, "Abyss did not restore the previous presentation")
	print("Responsive UI: seven raw viewport sizes and five actual Abyss presentation sizes; failures=",failures)
	host.free()
	await process_frame
	quit(1 if failures else 0)
