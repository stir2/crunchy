extends Control
## Title screen. Campaign selection controls both New Game and Continue.

var _run_length := GameController.RUN_LENGTH
var _default_window: Texture2D

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
	_default_window = $WindowView.texture
	_run_length = GameController.run_length
	var campaigns := HBoxContainer.new()
	campaigns.name = "CampaignPicker"
	campaigns.add_theme_constant_override("separation", 8)
	$Buttons.add_child(campaigns)
	$Buttons.move_child(campaigns, 1)
	# A filled gold frame marks the active campaign. Keyboard focus uses an
	# outline outside the button so it stays distinct from selection.
	var selected := action_theme.get_stylebox("pressed", "Button").duplicate() as StyleBoxFlat
	selected.bg_color = Color("825637")
	selected.border_color = Color("f3cc88")
	selected.set_border_width_all(3)
	selected.border_width_bottom = 5
	var campaign_focus := action_theme.get_stylebox("focus", "Button").duplicate() as StyleBoxFlat
	campaign_focus.border_color = Color("fff1d8")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		campaign_focus.set_expand_margin(side, 3)
	var group := ButtonGroup.new()
	for length in [GameController.RUN_LENGTH, GameController.SHORT_RUN_LENGTH]:
		var button := Button.new()
		button.name = "Campaign%d" % length
		button.text = "%d-Day Campaign" % length
		button.theme = action_theme
		button.add_theme_stylebox_override("pressed", selected)
		button.add_theme_stylebox_override("hover_pressed", selected)
		button.add_theme_stylebox_override("focus", campaign_focus)
		button.add_theme_font_size_override("font_size", 24)
		button.custom_minimum_size.y = 48
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_group = group
		campaigns.add_child(button)
		button.set_pressed_no_signal(length == _run_length)
		button.pressed.connect(_select_campaign.bind(length))
	_refresh_preview()
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
	new_game_dialog.confirmed.connect(func(): get_tree().current_scene.start_new_game(_run_length))
	%NewGameButton.grab_focus()


func _select_campaign(length: int) -> void:
	_run_length = length
	_refresh_preview()


func _refresh_preview() -> void:
	var preview := SaveManager.menu_preview(_run_length)
	continue_button.disabled = preview.is_empty()
	var window_art := preload("res://Scenes/Village/House/village_window_art.gd")
	$WindowView.texture = _default_window if preview.is_empty() else window_art.texture_for(preview.day, preview.boss_defeated, _run_length)
	status_label.text = SaveManager.last_error if continue_button.disabled and SaveManager.has_save_file(_run_length) else ""


func _new_game() -> void:
	if SaveManager.has_save_file(_run_length):
		new_game_dialog.dialog_text = "Saving a new run will overwrite your %d-day campaign save." % _run_length
		new_game_dialog.popup_centered(Vector2i(560, 162))
		new_game_dialog.get_cancel_button().grab_focus()
	else:
		get_tree().current_scene.start_new_game(_run_length)


func _continue() -> void:
	if not get_tree().current_scene.continue_game(_run_length):
		status_label.text = SaveManager.last_error
