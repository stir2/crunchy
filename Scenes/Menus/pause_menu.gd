extends CanvasLayer
## Pauses the scene tree while the menu itself keeps receiving input.

const MENU_STYLE = preload("res://Scenes/Menus/menu_style.gd")

@onready var panel: Control = $Panel
@onready var status_label: Label = %StatusLabel
@onready var leave_dialog: Control = $LeaveDialog
var _quit := false


func _ready() -> void:
	panel.theme = MENU_STYLE.make_theme()
	leave_dialog.theme = MENU_STYLE.make_confirmation_theme()
	get_viewport().size_changed.connect(_fit_layout)
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
	if panel.visible and event.is_action_pressed("ui_cancel"):
		if leave_dialog.visible:
			leave_dialog.hide()
		else:
			resume()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if panel.visible:
		resume()
		return
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
	status_label.text = "" if SaveManager.can_save() else "Saving is available at home, after the night is resolved."
	if DialogueManager.is_busy():
		status_label.text = "Finish the conversation before saving."
	%ResumeButton.grab_focus()


func resume() -> void:
	leave_dialog.hide()
	panel.hide()
	get_tree().paused = false
	Dialogic.paused = false
	if get_tree().current_scene.active_path == "res://Scenes/Cutscene/toll_cutscene.tscn":
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
	if pixel_mode:
		panel.theme = MENU_STYLE.make_theme(1.0, true)
		leave_dialog.theme = MENU_STYLE.make_confirmation_theme(true)
		var margin := 18.0
		paper.offset_left = margin
		paper.offset_top = margin
		paper.offset_right = 278.0
		paper.offset_bottom = viewport_size.y - margin
		buttons_box.add_theme_constant_override("separation", 6)
		%Day.add_theme_font_size_override("font_size", 16)
		$Panel/Layout/Paper/Buttons/Title.add_theme_font_size_override("font_size", 32)
		status_label.add_theme_font_size_override("font_size", 16)
		for btn: Button in [%ResumeButton, %SaveButton, %MainMenuButton, %QuitButton]:
			btn.custom_minimum_size.y = 26
			btn.add_theme_font_size_override("font_size", 16)
		leave_paper.custom_minimum_size = Vector2(300, 0)
		leave_paper.offset_left = -150.0
		leave_paper.offset_right = 150.0
		leave_paper.offset_top = -64.0
		leave_paper.offset_bottom = 64.0
		leave_content.add_theme_constant_override("separation", 10)
		leave_title.add_theme_font_size_override("font_size", 16)
		leave_message.add_theme_font_size_override("font_size", 16)
		leave_buttons.add_theme_constant_override("separation", 12)
		for btn: Button in [%CancelLeaveButton, %ConfirmLeaveButton]:
			btn.custom_minimum_size.y = 26
			btn.add_theme_font_size_override("font_size", 16)
	else:
		var s := clampf(minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0), 0.65, 2.0)
		panel.theme = MENU_STYLE.make_theme(1.15 * s, false)
		leave_dialog.theme = MENU_STYLE.make_confirmation_theme(false)
		var margin := roundf(72.0 * s)
		paper.offset_left = margin
		paper.offset_top = margin
		paper.offset_right = roundf(620.0 * s)
		paper.offset_bottom = viewport_size.y - margin
		buttons_box.add_theme_constant_override("separation", roundi(14 * s))
		%Day.add_theme_font_size_override("font_size", roundi(28 * s))
		$Panel/Layout/Paper/Buttons/Title.add_theme_font_size_override("font_size", roundi(64 * s))
		status_label.add_theme_font_size_override("font_size", roundi(26 * s))
		for btn: Button in [%ResumeButton, %SaveButton, %MainMenuButton, %QuitButton]:
			btn.custom_minimum_size.y = roundf(68.0 * s)
			btn.add_theme_font_size_override("font_size", roundi(32 * s))
		var half_w := roundf(340.0 * s)
		var half_h := roundf(140.0 * s)
		leave_paper.custom_minimum_size = Vector2(half_w * 2.0, half_h * 2.0)
		leave_paper.offset_left = -half_w
		leave_paper.offset_right = half_w
		leave_paper.offset_top = -half_h
		leave_paper.offset_bottom = half_h
		leave_content.add_theme_constant_override("separation", roundi(20 * s))
		leave_title.add_theme_font_size_override("font_size", roundi(36 * s))
		leave_message.add_theme_font_size_override("font_size", roundi(30 * s))
		leave_buttons.add_theme_constant_override("separation", roundi(24 * s))
		for btn: Button in [%CancelLeaveButton, %ConfirmLeaveButton]:
			btn.custom_minimum_size.y = roundf(58.0 * s)
			btn.add_theme_font_size_override("font_size", roundi(30 * s))
