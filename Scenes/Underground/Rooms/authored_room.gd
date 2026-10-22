@tool
class_name AbyssAuthoredRoom
extends Node2D
## Geometry container only. Metadata and mutable gameplay state live elsewhere.
@export var room_size: Vector2i = Vector2i(12, 12)
@export var tile_pixels: int = 16
@export var show_editor_guides: bool = true:
	set(value):
		show_editor_guides = value
		queue_redraw()
var construction_requirements: AbyssRoomRequirements


func _draw() -> void:
	if Engine.is_editor_hint() and show_editor_guides:
		draw_rect(Rect2(Vector2.ZERO, Vector2(room_size * tile_pixels)), Color(0.9, 0.75, 0.25, 0.8), false, 1.0)
