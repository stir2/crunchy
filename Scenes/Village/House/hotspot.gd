class_name Hotspot
extends Area2D
## A clickable spot in the house. Emits "activated" when left-clicked.

signal activated(id: StringName)

## Set this in the Inspector: stairs, desk, or window.
@export var hotspot_id: StringName = &""


func _ready() -> void:
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		activated.emit(hotspot_id)


func _on_mouse_entered() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)


func _on_mouse_exited() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
