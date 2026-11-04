@tool
extends DialogicLayoutLayer
## Keep dialogue on one line where possible. Dialogic handles speakers and advancing.

@export var text_size: int = 24
@export var maximum_width: float = 1440.0
@export var bottom_margin: float = 48.0

var _fade: Tween

@onready var subtitles: Control = $Subtitles
@onready var content: Control = $Subtitles/Content
@onready var dialog_text: DialogicNode_DialogText = %DialogText


func _ready() -> void:
	connect("resized", _refresh_layout)
	dialog_text.minimum_size_changed.connect(_refresh_layout)
	Dialogic.Text.text_started.connect(_on_text_started)
	if not Engine.is_editor_hint():
		subtitles.visibility_changed.connect(_on_visibility_changed)
	_apply_export_overrides()


func _apply_export_overrides() -> void:
	if not is_node_ready():
		return
	var font_size: int = int(get_global_setting(&"font_size", text_size)) if not Engine.is_editor_hint() else text_size
	for key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		dialog_text.add_theme_font_size_override(key, font_size)
	_refresh_layout()


func _refresh_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size: Vector2 = get("size")
	var maximum_box_width := minf(maximum_width, viewport_size.x * 0.9)
	var font := dialog_text.get_theme_font("normal_font")
	var font_size := dialog_text.get_theme_font_size("normal_font_size")
	var full_text := dialog_text.get_parsed_text()
	var text_width := font.get_string_size(full_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var width := clampf(text_width + 112.0, 260.0, maximum_box_width)
	var text_height := font.get_multiline_string_size(full_text, HORIZONTAL_ALIGNMENT_LEFT, width - 96.0, font_size).y
	content.size = Vector2(width, maxf(56.0, text_height + 28.0))
	content.position = Vector2((viewport_size.x - content.size.x) * 0.5, viewport_size.y - bottom_margin - content.size.y)
	var frame: Panel = $Subtitles/Frame
	frame.position = content.position - Vector2(12, 8)
	frame.size = content.size + Vector2(24, 16)


func _on_text_started(_info: Dictionary) -> void:
	call_deferred("_refresh_layout")


func _on_visibility_changed() -> void:
	if _fade != null:
		_fade.kill()
	if subtitles.visible:
		subtitles.modulate.a = 0.0
		_fade = create_tween()
		_fade.tween_property(subtitles, "modulate:a", 1.0, 0.16)
