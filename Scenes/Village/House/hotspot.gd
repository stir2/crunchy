class_name Hotspot
extends Area2D
## Emits activated through Interact (default left click) while hovered/picked.

signal activated(id: StringName)

## Set this in the Inspector: stairs, desk, or window.
@export var hotspot_id: StringName = &""
var _hovered: bool = false


func _ready() -> void:
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event.is_action_pressed("Interact"):
		activated.emit(hotspot_id)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard/controller rebindings activate the currently hovered hotspot too.
	if _hovered and event.is_action_pressed("Interact"):
		activated.emit(hotspot_id)
		get_viewport().set_input_as_handled()


func _on_mouse_entered() -> void:
	_hovered = true
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)


func _on_mouse_exited() -> void:
	_hovered = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
