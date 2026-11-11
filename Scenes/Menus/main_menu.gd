extends Control
## Temporary title screen. Continue uses the single local save slot.

@onready var continue_button: Button = %ContinueButton
@onready var status_label: Label = %StatusLabel
@onready var new_game_dialog: ConfirmationDialog = $NewGameDialog


func _ready() -> void:
	%NewGameButton.set_meta("own_click_sound", true)
	continue_button.set_meta("own_click_sound", true)
	continue_button.disabled = not SaveManager.has_save()
	%NewGameButton.pressed.connect(_new_game)
	continue_button.pressed.connect(_continue)
	%QuitButton.pressed.connect(func(): get_tree().quit())
	new_game_dialog.theme = preload("res://Scenes/Menus/menu_style.gd").make_confirmation_theme()
	new_game_dialog.ok_button_text = "Start New Game"
	new_game_dialog.cancel_button_text = "Cancel"
	var label := new_game_dialog.get_label()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	new_game_dialog.confirmed.connect(func(): get_tree().current_scene.start_new_game())
	%NewGameButton.grab_focus()


func _new_game() -> void:
	if SaveManager.has_save():
		new_game_dialog.popup_centered(Vector2i(660, 210))
		new_game_dialog.get_cancel_button().grab_focus()
	else:
		get_tree().current_scene.start_new_game()


func _continue() -> void:
	if not get_tree().current_scene.continue_game():
		status_label.text = SaveManager.last_error
