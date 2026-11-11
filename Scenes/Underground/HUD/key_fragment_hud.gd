extends Control
## Per-level key progress. No currency, collection or unlock mutation lives here.
@export var runtime_path: NodePath = NodePath("../..")
@export var hud_position: Vector2 = Vector2(12, 68)
@export var follow_flesh_counter: bool = true
@export_range(0, 32) var separator_gap: int = 10
@export var separator_color: Color = Color(0.55, 0.58, 0.63)
@export_range(4, 32) var separator_height: int = 16
@export_range(0.5, 6.0, 0.125) var pixel_scale: float = 1.25
@export var silhouette_color: Color = Color.BLACK
@export var outline_color: Color = Color.WHITE
@export_range(0, 4) var outline_width: int = 1
@export var first_half: Texture2D = preload("res://Assets/Tiles/keyhalf1_16x16.png")
@export var second_half: Texture2D = preload("res://Assets/Tiles/keyhalf2_16x16.png")
var shown_count: int = 0
var _level_id: String = ""
var _state: AbyssProgressionState
var _key_origin: Vector2
var _separator_origin: Vector2
var _outline_textures: Array[Texture2D] = []
@onready var _runtime: AbyssRuntime = get_node(runtime_path) as AbyssRuntime

func _ready() -> void:
	for texture in [first_half, second_half]:
		if texture == null:
			_outline_textures.append(null)
			continue
		var mask: Image = texture.get_image()
		if mask.is_compressed(): mask.decompress()
		mask.convert(Image.FORMAT_RGBA8)
		for y in range(mask.get_height()):
			for x in range(mask.get_width()):
				mask.set_pixel(x, y, Color(1, 1, 1, mask.get_pixel(x, y).a))
		_outline_textures.append(ImageTexture.create_from_image(mask))

func _process(_delta: float) -> void:
	_update_layout()
	if _runtime == null or _runtime.stream.specials == null:
		visible = false
		return
	var specials := _runtime.stream.specials
	var level := specials.level_at(_runtime.stream.world_to_room(_runtime.player.global_position))
	visible = _runtime.is_active() and level > 0
	if _state != specials.state:
		if _state != null: _state.changed.disconnect(_refresh)
		_state = specials.state
		_state.changed.connect(_refresh)
		_level_id = ""
	var level_id := specials.level_key(level)
	if level_id != _level_id:
		_level_id = level_id
		_refresh()

func _update_layout() -> void:
	var origin := hud_position
	var separator := Vector2.ZERO
	if follow_flesh_counter and _runtime != null:
		var flesh := _runtime.get_node("FleshHUD") as AbyssFleshHUD
		var end := flesh.current_label.get_global_rect().end.x
		var center := flesh.row.get_global_rect().get_center().y
		separator = Vector2(roundf(end + separator_gap), roundf(center - separator_height * 0.5))
		origin = Vector2(separator.x + separator_gap, roundf(center - 8 * pixel_scale))
	if origin != _key_origin or separator != _separator_origin:
		_key_origin = origin
		_separator_origin = separator
		queue_redraw()

func _refresh() -> void:
	shown_count = AbyssKeyFragmentArt.visible_halves(_state, _level_id)
	queue_redraw()

func _draw() -> void:
	if follow_flesh_counter:
		draw_line(_separator_origin, _separator_origin + Vector2(0, separator_height), separator_color, 1)
	var size := Vector2.ONE * 16 * pixel_scale
	# Draw both expanded masks first, so the joined key has no internal outline.
	for index in range(_outline_textures.size()):
		var mask := _outline_textures[index]
		if mask == null: continue
		for y in range(-outline_width, outline_width + 1):
			for x in range(-outline_width, outline_width + 1):
				if x == 0 and y == 0: continue
				var rect := Rect2(_key_origin + Vector2(size.x * index + x, y), size)
				draw_texture_rect(mask, rect, false, outline_color)
	for index in range(2):
		var texture := first_half if index == 0 else second_half
		if texture == null: continue
		var rect := Rect2(_key_origin + Vector2(size.x * index, 0), size)
		draw_texture_rect(texture, rect, false, silhouette_color)
		if index < shown_count:
			draw_texture_rect(texture, rect, false)
