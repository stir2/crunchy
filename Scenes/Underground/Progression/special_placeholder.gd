@tool
extends Node2D
## Nonblocking placeholder. Future gameplay calls the attached typed request.
@export_enum("checkpoint","fragment","gate") var feature: String = "checkpoint"
var request: AbyssSpecialSpawnRequest
func _ready() -> void:
	queue_redraw()
func _draw() -> void:
	var color := Color.CYAN if feature == "checkpoint" else (Color.GOLD if feature == "fragment" else Color.ORANGE_RED)
	draw_circle(Vector2.ZERO,7,color)
	draw_line(Vector2(-9,10),Vector2(9,10),color,2)
	draw_string(ThemeDB.fallback_font,Vector2(12,0),feature,HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
