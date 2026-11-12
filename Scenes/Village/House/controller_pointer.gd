extends Sprite2D
## Send pointer events through the same GUI path as a mouse, including roster drags.
const VIRTUAL_DEVICE := 100
var _held := false


func _ready() -> void:
	texture = preload("res://Assets/Sprites/UI/cursor.png")
	centered = false
	z_index = 100
	hide()


func _process(delta: float) -> void:
	if _held and not Input.is_action_pressed("Village Pointer Click"):
		_click(false)
	var direction := Input.get_vector("Village Pointer Left", "Village Pointer Right",
		"Village Pointer Up", "Village Pointer Down")
	if direction.is_zero_approx():
		return
	_show_pointer()
	var bounds := get_viewport_rect()
	var next := (position + direction * bounds.size.y * delta * 0.9).clamp(bounds.position, bounds.end - Vector2.ONE)
	var motion := InputEventMouseMotion.new()
	motion.relative = next - position
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if _held else 0
	position = next
	_dispatch(motion)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.device != VIRTUAL_DEVICE and not _held:
		hide()
	if event.is_action_pressed("Village Pointer Click"):
		_show_pointer()
		_click(true)
		get_viewport().set_input_as_handled()
	elif _held and event.is_action_released("Village Pointer Click"):
		_click(false)
		get_viewport().set_input_as_handled()


func _show_pointer() -> void:
	if visible:
		return
	position = get_viewport_rect().get_center()
	show()


func _click(pressed: bool) -> void:
	if pressed:
		_dispatch(InputEventMouseMotion.new())
	_held = pressed
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	click.pressed = pressed
	_dispatch(click)


func _dispatch(event: InputEventMouse) -> void:
	event.device = VIRTUAL_DEVICE
	event.position = position
	event.global_position = position
	get_viewport().push_input.call_deferred(event, true)
