class_name AbyssFleshHUD
extends CanvasLayer
## Display-only flight queue. No animation callback changes persistent balances.
@export var icon_texture: Texture2D = preload("res://uiSprites/flesh.png")
@export var hud_position: Vector2 = Vector2(12,12)
@export var previous_color: Color = Color(0.55,0.58,0.63)
@export var current_color: Color = Color(0.5,0.85,1.0)
@export_range(8,48,1) var icon_pixels: int = 20
@export_range(8,32,1) var font_pixels: int = 16
@export_range(0,24,1) var item_spacing: int = 6
@export_range(0.05,2.0,0.05) var flight_seconds: float = 0.45
@export_range(0.0,0.2,0.01) var flight_stagger: float = 0.04
@export_range(1,24,1) var max_icons_per_collection: int = 8
@export_range(1.0,2.0,0.05) var bounce_scale: float = 1.25
var displayed_previous: int = 0
var displayed_current: int = 0
var _game: Node
var _state: AbyssExplorationState
var _world: String
var _source: Node2D
var _serial: int = 0
var _pending: Dictionary = {}
var _bounce: Tween
var _field_card: PanelContainer
var _field_heading: Label
var _field_note: Label
var _field_note_timer: Timer
@onready var row: HBoxContainer = $Row
@onready var icon: TextureRect = $Row/Icon
@onready var previous_label: Label = $Row/Previous
@onready var current_label: Label = $Row/Current

func _ready() -> void:
	apply_style()
	_render_current()
	previous_label.text = "0"
	var menu_style := preload("res://Scenes/Menus/menu_style.gd")
	_field_card = PanelContainer.new()
	_field_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field_card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_field_card.theme = menu_style.make_theme(1.0, true)
	_field_card.add_theme_stylebox_override("panel", menu_style.paper_style(15, 5))
	add_child(_field_card)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 2)
	_field_card.add_child(content)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(header)
	_field_heading = Label.new()
	_field_heading.add_theme_font_size_override("font_size", 14)
	_field_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_field_heading)
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "Dismiss hint"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 12)
	for state in ["normal", "hover", "pressed"]:
		var style := _field_card.theme.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
		style.content_margin_left = 4
		style.content_margin_right = 4
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		close.add_theme_stylebox_override(state, style)
	close.pressed.connect(_dismiss_field_note)
	header.add_child(close)
	_field_note = Label.new()
	_field_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_field_note.add_theme_font_size_override("font_size", 13)
	content.add_child(_field_note)
	get_viewport().size_changed.connect(_layout_field_note)
	_field_card.hide()
	_field_note_timer = Timer.new()
	_field_note_timer.one_shot = true
	_field_note_timer.timeout.connect(_dismiss_field_note)
	add_child(_field_note_timer)

func _show_field_note(title: String, message: String) -> void:
	_field_heading.text = title
	_field_note.text = message
	_layout_field_note()
	_field_card.show()
	_field_note_timer.start(12.0)

func _dismiss_field_note() -> void:
	_field_card.hide()
	_field_note_timer.stop()

func _layout_field_note() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_width := viewport.get_visible_rect().size.x
	var width := minf(246.0, maxf(1.0, viewport_width - 24.0))
	_field_note.size.x = maxf(1.0, width - 40.0)
	_field_card.position = Vector2(viewport_width - width - 10.0, 38.0)
	_field_card.size = Vector2(width, _field_card.get_combined_minimum_size().y)


func _tutorial_enabled() -> bool:
	return is_instance_valid(_game) and _game.day == 1 and not _game.window_history.has("day1_tutorial_skipped")

func apply_style() -> void:
	row.position = hud_position
	row.add_theme_constant_override("separation",item_spacing)
	icon.texture = icon_texture
	icon.custom_minimum_size = Vector2.ONE*icon_pixels
	previous_label.add_theme_color_override("font_color",previous_color)
	current_label.add_theme_color_override("font_color",current_color)
	for label in [previous_label,current_label]: label.add_theme_font_size_override("font_size",font_pixels)

func bind_state(game: Node, state: AbyssExplorationState, world: String, source: Node2D) -> void:
	unbind()
	_game = game
	_state = state
	_world = world
	_source = source
	_game.flesh_changed.connect(_on_previous_changed)
	_state.flesh_collected.connect(_on_collected)
	_state.changed.connect(_sync_balance)
	_sync_balance()
	_on_previous_changed(int(_game.flesh))
	if _tutorial_enabled() and not _game.window_history.has("day1_tutorial_field"):
		_game.window_history["day1_tutorial_field"] = true
		_show_field_note("Hunt for Flesh", "A/D move · W/S climb · Space jump\nClick attack · Hold/release Shift: dash\nM map · Q potion")

func unbind() -> void:
	if _field_card != null:
		_dismiss_field_note()
	if _state != null:
		_state.flesh_collected.disconnect(_on_collected)
		_state.changed.disconnect(_sync_balance)
	if is_instance_valid(_game) and _game.flesh_changed.is_connected(_on_previous_changed):
		_game.flesh_changed.disconnect(_on_previous_changed)
	cancel_flights()
	_state = null
	_game = null

func _on_previous_changed(amount: int) -> void:
	displayed_previous = amount
	previous_label.text = str(amount) # Never tween the banked value on pickups.

func _render_current() -> void:
	current_label.text = "+ %d" % displayed_current

func pending_amount() -> int:
	var total := 0
	for entry: Dictionary in _pending.values(): total += int(entry.amount)
	return total

func _sync_balance() -> void:
	if _state == null: return
	var authoritative := _state.current_flesh(_world)
	if authoritative != displayed_current+pending_amount():
		cancel_flights() # Death, banking, loading and other non-pickup changes.
		displayed_current = authoritative
		_render_current()

func cancel_flights() -> void:
	for entry: Dictionary in _pending.values():
		if is_instance_valid(entry.icon): entry.icon.queue_free()
	_pending.clear()
	if _bounce != null: _bounce.kill()
	if is_instance_valid(icon): icon.scale = Vector2.ONE

func _on_collected(world: String, amount: int, origin: Vector2) -> void:
	if world != _world or amount <= 0: return
	if _tutorial_enabled() and not _game.window_history.has("day1_tutorial_pickup"):
		_game.window_history["day1_tutorial_pickup"] = true
		_show_field_note("Flesh collected", "The + number is carried Flesh. Follow the map (M) back to the entrance and interact to bank it.")
	var start := origin
	if not start.is_finite(): start = _source.global_position if is_instance_valid(_source) else Vector2.ZERO
	start = get_viewport().get_canvas_transform()*start
	var count := mini(amount,max_icons_per_collection)
	for index in range(count):
		var assigned := amount/count + (1 if index < amount%count else 0)
		_serial += 1
		var id := _serial
		var flying := Sprite2D.new()
		flying.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		flying.texture = icon_texture
		if icon_texture != null: flying.scale = Vector2.ONE*icon_pixels/maxf(1.0,icon_texture.get_width())
		flying.position = start
		$Flights.add_child(flying)
		_pending[id] = {"amount":assigned,"icon":flying}
		var target := icon.get_global_rect().get_center()
		var control := start+Vector2((index%3-1)*20,-32-index*3)
		var tween := flying.create_tween()
		tween.tween_method(func(t: float) -> void:
			flying.position = start.bezier_interpolate(control,control,target,t),0.0,1.0,flight_seconds+index*flight_stagger)
		tween.tween_callback(complete_arrival.bind(id))

func complete_arrival(id: int) -> void:
	if not _pending.has(id): return
	var entry: Dictionary = _pending[id]
	_pending.erase(id) # A callback can never increment this display twice.
	if is_instance_valid(entry.icon): entry.icon.queue_free()
	displayed_current += int(entry.amount)
	_render_current()
	if _bounce != null: _bounce.kill()
	icon.pivot_offset = icon.size*0.5
	icon.scale = Vector2.ONE
	_bounce = create_tween()
	_bounce.tween_property(icon,"scale",Vector2.ONE*bounce_scale,0.05)
	_bounce.tween_property(icon,"scale",Vector2.ONE,0.10)
