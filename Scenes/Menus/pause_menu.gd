extends CanvasLayer
## Pauses the scene tree while the menu itself keeps receiving input.

@onready var panel: Control = $Panel
@onready var status_label: Label = %StatusLabel
@onready var leave_dialog: ConfirmationDialog = $LeaveDialog
var _quit := false


func _ready() -> void:
	panel.hide()
	%ResumeButton.pressed.connect(resume)
	%SaveButton.pressed.connect(_save)
	%MainMenuButton.pressed.connect(_confirm_leave.bind(false))
	%QuitButton.pressed.connect(_confirm_leave.bind(true))
	leave_dialog.confirmed.connect(_leave)


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
	panel.show()
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
	leave_dialog.popup_centered()


func _leave() -> void:
	resume()
	if _quit:
		get_tree().quit()
	else:
		get_tree().current_scene.change_scene("res://Scenes/Menus/main_menu.tscn")
