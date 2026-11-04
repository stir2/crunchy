extends Control
## Temporary title screen. Continue uses the single local save slot.

@onready var continue_button: Button = %ContinueButton
@onready var status_label: Label = %StatusLabel
@onready var new_game_dialog: ConfirmationDialog = $NewGameDialog


func _ready() -> void:
	continue_button.disabled = not SaveManager.has_save()
	%NewGameButton.pressed.connect(_new_game)
	continue_button.pressed.connect(_continue)
	%QuitButton.pressed.connect(func(): get_tree().quit())
	new_game_dialog.confirmed.connect(func(): get_tree().current_scene.start_new_game())
	%NewGameButton.grab_focus()


func _new_game() -> void:
	if SaveManager.has_save():
		new_game_dialog.popup_centered()
	else:
		get_tree().current_scene.start_new_game()


func _continue() -> void:
	if not get_tree().current_scene.continue_game():
		status_label.text = SaveManager.last_error
