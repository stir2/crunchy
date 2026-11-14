extends CanvasLayer
## Pauses the scene tree while the menu itself keeps receiving input.

const MENU_STYLE = preload("res://Scenes/Menus/menu_style.gd")

@onready var panel: Control = $Panel
@onready var status_label: Label = %StatusLabel
@onready var leave_dialog: Control = $LeaveDialog
var _quit := false
var _help: Control
var _help_paper: PanelContainer
var _help_area: Button
var _help_back: Button
var _help_title: Label
var _help_message: Label
var _help_controls: Button
var _controls_scroll: ScrollContainer
var _controls_frame: MarginContainer
var _controls_label: Label
var _controls_controller := false
var _help_target: WeakRef


func _ready() -> void:
	_build_help()
	%HelpButton.pressed.connect(_open_help)
	%SettingsButton.pressed.connect(func():
		panel.hide()
		$SettingsPanel.open())
	$SettingsPanel.closed.connect(func(save_error: String):
		if not save_error.is_empty():
			status_label.text = save_error
		panel.show()
		%SettingsButton.grab_focus())
	panel.theme = MENU_STYLE.make_theme()
	leave_dialog.theme = MENU_STYLE.make_confirmation_theme()
	get_viewport().size_changed.connect(_fit_layout)
	$Panel/Layout/Paper.minimum_size_changed.connect(_fit_papers, CONNECT_DEFERRED)
	$LeaveDialog/Layout/Paper.minimum_size_changed.connect(_fit_papers, CONNECT_DEFERRED)
	_fit_layout()
	panel.hide()
	%ResumeButton.pressed.connect(resume)
	%SaveButton.pressed.connect(_save)
	%MainMenuButton.pressed.connect(_confirm_leave.bind(false))
	%QuitButton.pressed.connect(_confirm_leave.bind(true))
	%ConfirmLeaveButton.pressed.connect(_leave)
	%CancelLeaveButton.pressed.connect(func():
		leave_dialog.hide()
		%ResumeButton.grab_focus())


func _input(event: InputEvent) -> void:
	if _help.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("Controller Pause")):
		_close_help()
		get_viewport().set_input_as_handled()
		return
	if panel.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("Controller Pause")):
		if leave_dialog.visible:
			leave_dialog.hide()
		else:
			resume()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _help.visible:
		_close_help()
		return
	if $SettingsPanel.visible:
		$SettingsPanel.close()
		return
	if panel.visible:
		resume()
		return
	%HelpButton.visible = _tutorial_target() != null
	_fit_layout()
	%Day.text = "DAY %d" % GameController.day
	panel.modulate.a = 0
	panel.show()
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.18)
	DebugMenu.close()
	get_tree().paused = true
	Dialogic.paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	%SaveButton.disabled = not SaveManager.can_save()
	status_label.text = "" if SaveManager.can_save() else "Saving unlocks at home\nafter the night is resolved."
	if DialogueManager.is_busy():
		status_label.text = "Finish the conversation before saving."
	%ResumeButton.grab_focus()


func resume() -> void:
	_help_target = null
	_help.hide()
	if $SettingsPanel.visible:
		$SettingsPanel.close()
	leave_dialog.hide()
	panel.hide()
	get_tree().paused = false
	Dialogic.paused = false
	var scene := _game_scene()
	if scene != null and scene.scene_file_path == "res://Scenes/Cutscene/toll_cutscene.tscn":
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _save() -> void:
	status_label.text = "Game saved." if SaveManager.save_game() else SaveManager.last_error


func _confirm_leave(quit_game: bool) -> void:
	_quit = quit_game
	leave_dialog.show()
	%ConfirmLeaveButton.text = "Quit game" if _quit else "Leave run"
	%CancelLeaveButton.grab_focus()


func _leave() -> void:
	resume()
	if _quit:
		get_tree().quit()
	else:
		get_tree().current_scene.change_scene("res://Scenes/Menus/main_menu.tscn")


func _fit_layout() -> void:
	if not is_inside_tree(): return
	var viewport_size := get_viewport().get_visible_rect().size
	var pixel_mode := viewport_size.y <= 480.0
	for layout in [$Panel/Layout, $LeaveDialog/Layout]:
		layout.scale = Vector2.ONE
		layout.position = Vector2.ZERO
	var paper := $Panel/Layout/Paper as PanelContainer
	var buttons_box := $Panel/Layout/Paper/Buttons as VBoxContainer
	var leave_paper := $LeaveDialog/Layout/Paper as PanelContainer
	var leave_content := $LeaveDialog/Layout/Paper/Content as VBoxContainer
	var leave_title := $LeaveDialog/Layout/Paper/Content/Title as Label
	var leave_message := $LeaveDialog/Layout/Paper/Content/Message as Label
	var leave_buttons := $LeaveDialog/Layout/Paper/Content/Buttons as HBoxContainer
	%Day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$Panel/Layout/Paper/Buttons/Title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for button: Button in [%ResumeButton, %SaveButton, %SettingsButton, %MainMenuButton, %QuitButton, %HelpButton]:
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.custom_minimum_size.x = 112.0 if pixel_mode else roundf(clampf(viewport_size.x * 0.115, 144.0, 220.0))
	if pixel_mode:
		panel.theme = MENU_STYLE.make_theme(1.0, true)
		leave_dialog.theme = MENU_STYLE.make_confirmation_theme(true)
		var margin := 18.0
		paper.custom_minimum_size = Vector2(220, 0)
		paper.offset_left = margin
		paper.offset_top = margin
		paper.offset_right = 238.0
		paper.offset_bottom = paper.offset_top
		buttons_box.add_theme_constant_override("separation", 6)
		%Day.add_theme_font_size_override("font_size", 16)
		$Panel/Layout/Paper/Buttons/Title.add_theme_font_size_override("font_size", 32)
		status_label.add_theme_font_size_override("font_size", 12)
		for btn: Button in [%ResumeButton, %SaveButton, %SettingsButton, %MainMenuButton, %QuitButton, %HelpButton]:
			btn.custom_minimum_size = Vector2(112, 22)
			btn.add_theme_font_size_override("font_size", 14)
		leave_paper.custom_minimum_size = Vector2(286, 0)
		leave_paper.offset_left = -143.0
		leave_paper.offset_right = 143.0
		leave_paper.offset_top = 0.0
		leave_paper.offset_bottom = 0.0
		leave_content.add_theme_constant_override("separation", 8)
		leave_title.add_theme_font_size_override("font_size", 16)
		leave_message.add_theme_font_size_override("font_size", 16)
		leave_buttons.add_theme_constant_override("separation", 12)
		for btn: Button in [%CancelLeaveButton, %ConfirmLeaveButton]:
			btn.custom_minimum_size = Vector2(104, 22)
			btn.add_theme_font_size_override("font_size", 14)
	else:
		var s := clampf(minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0), 0.65, 2.0)
		panel.theme = MENU_STYLE.make_theme(1.15 * s, false)
		leave_dialog.theme = MENU_STYLE.make_confirmation_theme(false)
		var margin := roundf(72.0 * s)
		paper.custom_minimum_size = Vector2(roundf(360.0 * s), 0)
		paper.offset_left = margin
		paper.offset_top = margin
		paper.offset_right = roundf(620.0 * s)
		paper.offset_bottom = paper.offset_top
		buttons_box.add_theme_constant_override("separation", roundi(14 * s))
		%Day.add_theme_font_size_override("font_size", roundi(28 * s))
		$Panel/Layout/Paper/Buttons/Title.add_theme_font_size_override("font_size", roundi(64 * s))
		status_label.add_theme_font_size_override("font_size", roundi(22 * s))
		for btn: Button in [%ResumeButton, %SaveButton, %SettingsButton, %MainMenuButton, %QuitButton, %HelpButton]:
			btn.custom_minimum_size.y = roundf(46.0 * s)
			btn.add_theme_font_size_override("font_size", roundi(26 * s))
		var half_w := roundf(282.0 * s)
		leave_paper.custom_minimum_size = Vector2(half_w * 2.0, 0.0)
		leave_paper.offset_left = -half_w
		leave_paper.offset_right = half_w
		leave_paper.offset_top = 0.0
		leave_paper.offset_bottom = 0.0
		leave_content.add_theme_constant_override("separation", roundi(20 * s))
		leave_title.add_theme_font_size_override("font_size", roundi(36 * s))
		leave_message.add_theme_font_size_override("font_size", roundi(30 * s))
		leave_buttons.add_theme_constant_override("separation", roundi(24 * s))
		for btn: Button in [%CancelLeaveButton, %ConfirmLeaveButton]:
			btn.custom_minimum_size = Vector2(roundf(150.0 * s), roundf(44.0 * s))
			btn.add_theme_font_size_override("font_size", roundi(30 * s))

	leave_buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for button: Button in [%CancelLeaveButton, %ConfirmLeaveButton]:
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_fit_papers.call_deferred()
	_fit_help.call_deferred()


func _build_help() -> void:
	_help = Control.new()
	_help.name = "Help"
	add_child(_help)
	_help.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.018, 0.03, 0.85)
	_help.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help_paper = PanelContainer.new()
	_help_paper.theme = MENU_STYLE.make_theme(1.0, true)
	_help_paper.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_help.add_child(_help_paper)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	_help_paper.add_child(content)
	var title := Label.new()
	_help_title = title
	title.text = "Help"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	content.add_child(title)
	var message := Label.new()
	_help_message = message
	message.text = "Replay this area's tutorial."
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = 240
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(message)
	_help_area = Button.new()
	_help_area.text = "Show this area's tutorial"
	_help_area.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_help_area.pressed.connect(_replay_tutorials)
	content.add_child(_help_area)
	_help_controls = Button.new()
	_help_controls.text = "Controls"
	_help_controls.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_help_controls.pressed.connect(_show_controls.bind(true))
	content.add_child(_help_controls)
	_controls_scroll = ScrollContainer.new()
	_controls_scroll.custom_minimum_size = Vector2(240, 136)
	_controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_controls_frame = MarginContainer.new()
	_controls_frame.add_theme_constant_override("margin_left", 12)
	_controls_frame.add_theme_constant_override("margin_right", 12)
	content.add_child(_controls_frame)
	_controls_frame.add_child(_controls_scroll)
	var controls_margin := MarginContainer.new()
	controls_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right"]:
		controls_margin.add_theme_constant_override(side, 10)
	controls_margin.add_theme_constant_override("margin_top", 4)
	controls_margin.add_theme_constant_override("margin_bottom", 4)
	_controls_scroll.add_child(controls_margin)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 8)
	controls_margin.add_child(controls)
	var devices := HBoxContainer.new()
	devices.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_child(devices)
	var device_group := ButtonGroup.new()
	for device_name in ["Keyboard", "Controller"]:
		var button := Button.new()
		button.text = device_name
		button.toggle_mode = true
		button.button_group = device_group
		button.set_pressed_no_signal((device_name == "Controller") == _controls_controller)
		button.pressed.connect(func():
			_controls_controller = device_name == "Controller"
			_controls_label.text = _controls_text(_controls_controller)
			_controls_scroll.scroll_vertical = 0)
		devices.add_child(button)
	_controls_label = Label.new()
	_controls_label.add_theme_font_size_override("font_size", 14)
	controls.add_child(_controls_label)
	_controls_scroll.hide()
	_controls_frame.hide()
	_help_back = Button.new()
	_help_back.text = "Back"
	_help_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_help_back.pressed.connect(_close_help)
	content.add_child(_help_back)
	_help.hide()


func _fit_help() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_help_paper.size = _help_paper.get_combined_minimum_size()
	var available := (viewport_size - Vector2(24, 24)).max(Vector2.ONE)
	var preferred := clampf(minf(viewport_size.x / 640.0, viewport_size.y / 360.0), 0.5, 3.0)
	var factor := minf(preferred, minf(available.x / _help_paper.size.x, available.y / _help_paper.size.y))
	_help_paper.scale = Vector2.ONE * factor
	_help_paper.position = (viewport_size - _help_paper.size * factor) * 0.5


func _open_help() -> void:
	var target := _tutorial_target()
	if target == null or not panel.visible or not get_tree().paused:
		return
	_help_area.text = "Show Abyss tutorial" if target is AbyssFleshHUD else "Show house tutorial"
	_show_controls(false)
	_help_target = weakref(target)
	panel.hide()
	_help.show()
	_fit_help.call_deferred()
	_help_area.grab_focus()


func _show_controls(show_controls: bool) -> void:
	_controls_scroll.visible = show_controls
	_controls_frame.visible = show_controls
	_help_area.visible = not show_controls
	_help_message.visible = not show_controls
	_help_controls.visible = not show_controls
	_help_title.text = "Controls" if show_controls else "Help"
	_controls_label.text = _controls_text(_controls_controller)
	_controls_scroll.scroll_vertical = 0
	_help_back.grab_focus()
	_fit_help.call_deferred()

func _controls_text(controller: bool) -> String:
	var lines: PackedStringArray = []
	var buttons := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3"}
	for entry in [["Move left", "Move Left"], ["Move right", "Move Right"], ["Climb up", "Move Up"], ["Climb down", "Move Down"], ["Jump", "Jump"], ["Attack", "Attack"], ["Dash", "Dash"], ["Interact", "Interact 1"], ["Travel", "Interact 2"], ["Potion", "Use Potion"], ["Map", "Abyss Map"], ["Minimap", "Abyss Minimap"], ["Map center", "Map Recenter"], ["Zoom in", "Map Zoom In"], ["Zoom out", "Map Zoom Out"], ["Pause", "Controller Pause" if controller else "ui_cancel"]]:
		var bindings: PackedStringArray = []
		for event in InputMap.action_get_events(entry[1]):
			var binding := ""
			if not controller and event is InputEventKey:
				binding = OS.get_keycode_string(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
			elif not controller and event is InputEventMouseButton:
				binding = "Left click" if event.button_index == MOUSE_BUTTON_LEFT else event.as_text()
			elif controller and event is InputEventJoypadButton:
				binding = buttons.get(event.button_index, "D-pad")
			elif controller and event is InputEventJoypadMotion:
				binding = "RT" if event.axis == JOY_AXIS_TRIGGER_RIGHT else ("LT" if event.axis == JOY_AXIS_TRIGGER_LEFT else "Left stick")
			if not binding.is_empty() and not bindings.has(binding):
				bindings.append(binding)
		lines.append("%s: %s" % [entry[0], " / ".join(bindings)])
	lines.append("\nHold Dash to charge; release to dash.")
	lines.append("Menus: stick / D-pad; A select; B back." if controller else "Menus: arrows; Enter select; Esc back.")
	if controller:
		lines.append("Village pointer: right stick; RB click.")
	lines.append("Scroll: W/S or left stick; mouse wheel.")
	return "\n".join(lines)

func _process(delta: float) -> void:
	if _help.visible and _controls_scroll.visible:
		_controls_scroll.scroll_vertical += roundi(Input.get_axis("Move Up", "Move Down") * 220.0 * delta)

func _close_help() -> void:
	if _controls_scroll.visible:
		_show_controls(false)
		return
	_help_target = null
	_help.hide()
	panel.show()
	%HelpButton.visible = _tutorial_target() != null
	if %HelpButton.visible:
		%HelpButton.grab_focus()
	else:
		%ResumeButton.grab_focus()


func _replay_tutorials() -> void:
	if not _help.visible:
		return
	# Resolve again at activation, so a stale callback cannot affect another area.
	var target := _tutorial_target()
	if target == null or _help_target == null or target != _help_target.get_ref():
		_close_help()
		return
	target.replay()
	_close_help()
	status_label.text = "Tutorials enabled. Resume when ready."
	_fit_papers.call_deferred()


func _game_scene() -> Node:
	if not is_inside_tree():
		return null
	var scene := get_tree().current_scene
	if not is_instance_valid(scene) or scene.is_queued_for_deletion():
		return null
	# Main owns active_scene; F6 scenes are already the gameplay root.
	if scene.scene_file_path == "res://Scenes/Main/main.tscn":
		scene = scene.get("active_scene") as Node
	return scene if is_instance_valid(scene) and not scene.is_queued_for_deletion() else null


func _tutorial_target() -> Node:
	var scene := _game_scene()
	if scene is AbyssRuntime:
		var hud: AbyssFleshHUD = scene.flesh_hud
		return hud if is_instance_valid(hud) and hud.can_replay() else null
	if scene != null and scene.scene_file_path == "res://Scenes/Village/House/house.tscn":
		var tutorial := scene.get_node_or_null("UI/DayOneTutorial")
		if is_instance_valid(tutorial) and not tutorial.is_queued_for_deletion() and tutorial.has_method("replay"):
			return tutorial
	return null


func _fit_papers() -> void:
	if not is_inside_tree(): return
	var viewport_size := get_viewport().get_visible_rect().size
	var available := (viewport_size - Vector2(24, 24)).max(Vector2.ONE)
	for paper: Control in [$Panel/Layout/Paper, $LeaveDialog/Layout/Paper]:
		paper.size = Vector2(paper.get_combined_minimum_size().x, 0)
		paper.reset_size()
		var factor := minf(1.0, minf(available.x / maxf(1, paper.size.x), available.y / maxf(1, paper.size.y)))
		paper.scale = Vector2.ONE * factor
		paper.position = (viewport_size - paper.size * factor) * 0.5 if paper == $LeaveDialog/Layout/Paper else paper.position.clamp(Vector2(12, 12), (viewport_size - paper.size * factor - Vector2(12, 12)).max(Vector2(12, 12)))
