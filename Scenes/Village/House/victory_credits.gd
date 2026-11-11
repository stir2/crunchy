extends CanvasLayer
## The final window remains beneath the parchment during the credits fade.

const MENU_STYLE = preload("res://Scenes/Menus/menu_style.gd")
const LOGO = preload("res://uiSprites/logoReal.png")
const ROLL_SPEED := 116.0
const CREDITS := [
	["JV", "Visual Art, Sprites & UI Artwork"],
	["Logan", "Music & Sound Effects"],
	["Sterling", "Level Generation, Movement & Map Programming"],
	["Vihan", "Village, Enemy & Boss Programming"],
	["Noah", "Abyss Programming"],
]

var _cover: Control
var _roll: VBoxContainer
var _end: VBoxContainer
var _menu: Button
var _travel := 0.0
var _rolling := false
var _at_end := false
var _finishing := false

func _ready() -> void:
	layer = 149
	_cover = Control.new()
	_cover.modulate.a = 0.0
	add_child(_cover)
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.clip_contents = true
	var dark := ColorRect.new()
	dark.color = Color("241914")
	_cover.add_child(dark)
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var paper := Panel.new()
	paper.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	paper.add_theme_stylebox_override("panel", MENU_STYLE.paper_style(0, 0))
	_cover.add_child(paper)
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_roll = VBoxContainer.new()
	_roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roll.add_theme_constant_override("separation", 50)
	_cover.add_child(_roll)
	_roll.add_child(_label("Credits", 66))
	for credit in CREDITS:
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 4)
		entry.add_child(_label(credit[0], 52))
		entry.add_child(_label(credit[1], 34))
		_roll.add_child(entry)
	_end = VBoxContainer.new()
	_end.add_theme_constant_override("separation", 32)
	_end.add_child(_label("Thanks to you, for playing", 58))
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(444, 252)
	_end.add_child(logo)
	_menu = Button.new()
	_menu.theme = MENU_STYLE.make_theme()
	_menu.text = "Main Menu"
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu.pressed.connect(_return_to_menu)
	_menu.modulate.a = 0.0
	_menu.disabled = true
	_end.add_child(_menu)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size.y = 340.0
	_roll.add_child(gap)
	_roll.add_child(_end)
	_cover.resized.connect(_layout_roll)
	_roll.resized.connect(_layout_roll)
	_layout_roll()
	var fade := create_tween()
	fade.tween_property(_cover, "modulate:a", 1.0, 1.35).set_trans(Tween.TRANS_SINE)
	fade.tween_callback(func(): _rolling = true)

func _label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", MENU_STYLE.INK)
	return label

func _layout_roll() -> void:
	var factor := minf(_cover.size.x / 1920.0, _cover.size.y / 1080.0)
	if factor <= 0.0:
		return
	_roll.scale = Vector2.ONE * factor
	_roll.size.x = 1480
	var viewport_height := _cover.size.y / factor
	var stop := viewport_height * 0.5 + _end.position.y + _end.size.y * 0.5
	var travel := stop if _at_end else minf(_travel, stop)
	_roll.position = Vector2((_cover.size.x - _roll.size.x * factor) * 0.5, (viewport_height - travel) * factor)
	if _rolling and _travel >= stop:
		_rolling = false
		_at_end = true
		var fade := create_tween()
		fade.tween_interval(1.2)
		fade.tween_property(_menu, "modulate:a", 1.0, 0.35)
		fade.tween_callback(func():
			_menu.disabled = false
			_menu.grab_focus())

func _process(delta: float) -> void:
	if _rolling:
		_travel += ROLL_SPEED * delta
		_layout_roll()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()

func _return_to_menu() -> void:
	if _finishing:
		return
	_finishing = true
	_menu.disabled = true
	var main := get_tree().current_scene
	main.transition_to_scene("res://Scenes/Menus/main_menu.tscn", 0.85)
