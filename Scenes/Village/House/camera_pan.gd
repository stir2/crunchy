class_name HouseCamera
extends Camera2D
## Pans left and right when the mouse is near the edge of the screen.
## Set pan_enabled to false while a panel is open.

## Size of the house background in pixels.
@export var world_size := Vector2(3840, 1080)
## Share of the screen on each side that triggers panning.
@export var edge_fraction := 0.15
## Pan speed in pixels per second at the very edge of the screen.
@export var max_speed := 1400.0

var pan_enabled := true


func _ready() -> void:
	limit_left = 0
	limit_top = 0
	limit_right = int(world_size.x)
	limit_bottom = int(world_size.y)
	position = world_size / 2.0


func _process(delta: float) -> void:
	if not pan_enabled:
		return

	var view_width := get_viewport_rect().size.x
	var mouse_ratio := get_viewport().get_mouse_position().x / view_width

	var direction := 0.0
	if mouse_ratio < edge_fraction:
		direction = -(edge_fraction - mouse_ratio) / edge_fraction
	elif mouse_ratio > 1.0 - edge_fraction:
		direction = (mouse_ratio - (1.0 - edge_fraction)) / edge_fraction

	# Squaring keeps the pan slow near the inner edge and fast at the screen edge.
	direction = clampf(direction, -1.0, 1.0)
	direction *= absf(direction)

	var half_view := view_width / 2.0
	var new_x := position.x + direction * max_speed * delta
	position.x = clampf(new_x, half_view, world_size.x - half_view)
