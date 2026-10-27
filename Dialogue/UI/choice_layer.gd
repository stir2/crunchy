@tool
extends "res://addons/dialogic/Modules/DefaultLayoutParts/Layer_VN_Choices/vn_choice_layer.gd"
## Keep choices above the subtitles, using Dialogic's existing choice buttons.


func _ready() -> void:
	connect("resized", _refresh_layout)
	get_choices().minimum_size_changed.connect(_refresh_layout)
	_refresh_layout()


func _apply_export_overrides() -> void:
	super._apply_export_overrides()
	var sounds := get_button_sound()
	sounds.sound_pressed = null
	sounds.sound_hover = null
	sounds.sound_focus = null
	for child in get_choices().get_children():
		if child is DialogicNode_ChoiceButton:
			child.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_refresh_layout()


func _refresh_layout() -> void:
	if not is_inside_tree():
		return
	var choices := get_choices()
	var viewport_size: Vector2 = get("size")
	var width := minf(1120.0, viewport_size.x * 0.84)
	var subtitle_height := 112.0
	if not Engine.is_editor_hint():
		for text in get_tree().get_nodes_in_group("dialogic_dialog_text"):
			if text.get_parent() is VBoxContainer:
				subtitle_height = text.get_parent().get_combined_minimum_size().y
	choices.set_anchors_preset(Control.PRESET_TOP_LEFT)
	choices.size = Vector2(width, choices.get_combined_minimum_size().y)
	choices.position = Vector2((viewport_size.x - width) * 0.5, viewport_size.y - 54.0 - subtitle_height - 28.0 - choices.size.y)
