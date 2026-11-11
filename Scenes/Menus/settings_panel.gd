extends CenterContainer

signal closed(save_error: String)

const MENU_STYLE = preload("res://Scenes/Menus/menu_style.gd")
const AUDIO_LABELS := [&"Master", &"Music", &"Sound effects"]

var _paper: PanelContainer
var _content: VBoxContainer
var _fullscreen_button: Button
var _title: Label
var _audio_rows: Array[HBoxContainer] = []
var _sliders: Dictionary = {}
var _volume_labels: Dictionary = {}


func _ready() -> void:
	_paper = PanelContainer.new()
	add_child(_paper)
	_content = VBoxContainer.new()
	_paper.add_child(_content)

	_title = _label("Settings")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(_title)
	_section("Display")
	var display_row := HBoxContainer.new()
	_content.add_child(display_row)
	var display_label := _label("Fullscreen")
	display_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display_row.add_child(display_label)
	_fullscreen_button = Button.new()
	_fullscreen_button.toggle_mode = true
	_fullscreen_button.custom_minimum_size.x = 88
	display_row.add_child(_fullscreen_button)
	_fullscreen_button.toggled.connect(func(enabled: bool):
		GameSettings.set_fullscreen(enabled)
		_refresh_display())

	_section("Audio")
	for index in GameSettings.AUDIO_BUSES.size():
		_add_audio_row(GameSettings.AUDIO_BUSES[index], AUDIO_LABELS[index])

	var done_button := Button.new()
	done_button.text = "Done"
	done_button.pressed.connect(_close)
	_content.add_child(done_button)

	get_viewport().size_changed.connect(_fit_layout)
	resized.connect(queue_redraw)
	_fit_layout()
	hide()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.05, 0.11, 0.62))


func open() -> void:
	_refresh_display()
	for bus in _sliders:
		var percent: int = GameSettings.volumes[bus]
		_sliders[bus].set_value_no_signal(percent)
		_volume_labels[bus].text = "%d%%" % percent
	show()
	_fullscreen_button.grab_focus()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	var save_error := ""
	if GameSettings.save() != OK:
		save_error = "Could not save settings. Changes apply for this session."
	hide()
	closed.emit(save_error)


func _refresh_display() -> void:
	_fullscreen_button.set_pressed_no_signal(GameSettings.fullscreen)
	_fullscreen_button.text = "On" if GameSettings.fullscreen else "Off"


func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	return label


func _section(value: String) -> void:
	var row := HBoxContainer.new()
	_content.add_child(row)
	row.add_child(_label(value))
	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(line)


func _add_audio_row(bus: StringName, title: String) -> void:
	var row := HBoxContainer.new()
	_content.add_child(row)
	_audio_rows.append(row)
	var label := _label(title)
	row.add_child(label)

	var slider := HSlider.new()
	slider.max_value = 100
	slider.step = 1
	slider.value = GameSettings.volumes[bus]
	slider.tooltip_text = title + " volume"
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	_sliders[bus] = slider

	var value := _label("%d%%" % slider.value)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	_volume_labels[bus] = value
	slider.value_changed.connect(func(percent: float):
		GameSettings.set_volume(bus, int(percent))
		value.text = "%d%%" % percent)


func _fit_layout() -> void:
	if not is_inside_tree():
		return
	var pixel_mode := get_viewport().get_visible_rect().size.y <= 480
	theme = MENU_STYLE.make_confirmation_theme(pixel_mode)
	var rule := StyleBoxLine.new()
	rule.color = Color("866446")
	rule.thickness = 2
	theme.set_stylebox("separator", "HSeparator", rule)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("594139")
	track.content_margin_top = 3 if pixel_mode else 5
	track.content_margin_bottom = track.content_margin_top
	theme.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color("926346")
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	for state in ["grabber", "grabber_highlight", "grabber_disabled"]:
		var knob_size := Vector2i(9, 14) if pixel_mode else Vector2i(16, 24)
		var knob := Image.create_empty(knob_size.x, knob_size.y, false, Image.FORMAT_RGBA8)
		var face := Color("80573d") if state == "grabber_highlight" else Color("594139")
		knob.fill(Color("34251f"))
		knob.fill_rect(Rect2i(Vector2i(1, 1), knob_size - Vector2i(2, 2)), face)
		knob.fill_rect(Rect2i(knob_size.x / 2, 3, 1 if pixel_mode else 2, knob_size.y - 6), Color("f6dcab"))
		theme.set_icon(state, "HSlider", ImageTexture.create_from_image(knob))
	_paper.custom_minimum_size.x = 360 if pixel_mode else 660
	_content.add_theme_constant_override("separation", 7 if pixel_mode else 18)
	_title.add_theme_font_size_override("font_size", 26 if pixel_mode else 48)
	for child in _content.get_children():
		if child is HBoxContainer:
			child.add_theme_constant_override("separation", 12 if pixel_mode else 24)
	for row in _audio_rows:
		row.get_child(0).custom_minimum_size.x = 112 if pixel_mode else 200
		row.get_child(2).custom_minimum_size.x = 48 if pixel_mode else 90
