extends Control
## Title screen. Continue uses the single local save slot.

@onready var continue_button: Button = %ContinueButton
@onready var status_label: Label = %StatusLabel
@onready var new_game_dialog: ConfirmationDialog = $NewGameDialog


func _ready() -> void:
	var action_theme := Theme.new()
	preload("res://Scenes/Menus/menu_style.gd").apply_buttons(action_theme, 20, 8, 2)
	for child in $Buttons.get_children():
		if child is Button:
			child.theme = action_theme
	%SettingsButton.pressed.connect(func():
		$Buttons.hide()
		$SettingsPanel.open())
	$SettingsPanel.closed.connect(func(save_error: String):
		if not save_error.is_empty():
			status_label.text = save_error
		$Buttons.show()
		%SettingsButton.grab_focus())
	%NewGameButton.set_meta("own_click_sound", true)
	continue_button.set_meta("own_click_sound", true)
	var preview := SaveManager.menu_preview()
	continue_button.disabled = preview.is_empty()
	if not preview.is_empty():
		var window_art := preload("res://Scenes/Village/House/village_window_art.gd")
		$WindowView.texture = window_art.texture_for(preview.day, preview.boss_defeated)
	if continue_button.disabled and SaveManager.has_save_file():
		status_label.text = SaveManager.last_error
	%NewGameButton.pressed.connect(_new_game)
	continue_button.pressed.connect(_continue)
	%QuitButton.pressed.connect(func(): get_tree().quit())
	var dialog_shade := ColorRect.new()
	dialog_shade.color = Color(0.09, 0.05, 0.11, 0.56)
	add_child(dialog_shade)
	dialog_shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dialog_shade.hide()
	new_game_dialog.visibility_changed.connect(func(): dialog_shade.visible = new_game_dialog.visible)
	new_game_dialog.transparent_bg = true
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
	if SaveManager.has_save_file():
		new_game_dialog.popup_centered(Vector2i(560, 162))
		new_game_dialog.get_cancel_button().grab_focus()
	else:
		get_tree().current_scene.start_new_game()


func _continue() -> void:
	if not get_tree().current_scene.continue_game():
		status_label.text = SaveManager.last_error
