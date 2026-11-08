@tool
extends Node2D
## Replaceable visual only: no input, progression or collision ownership.
signal collection_finished
@export_enum("checkpoint","fragment","gate") var feature: String = "checkpoint"
@export var active: bool = false:
	set(value):
		active = value
		queue_redraw()
var _effect: float = 0.0

func set_state(value: bool) -> void:
	active = value

func play_collected() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self,"_effect",1.0,0.3)
	tween.tween_property(self,"scale",Vector2(1.8,1.8),0.3)
	tween.tween_property(self,"modulate:a",0.0,0.3)
	tween.chain().tween_callback(func() -> void:
		visible = false
		collection_finished.emit())
	tween.step_finished.connect(func(_index: int) -> void: queue_redraw())

func _draw() -> void:
	match feature:
		"checkpoint":
			var color := Color(0.3,1.0,0.8) if active else Color(0.4,0.5,0.6)
			draw_rect(Rect2(-8,6,16,4),color)
			draw_rect(Rect2(-2,-12,4,18),color)
			draw_rect(Rect2(2,-12,10,8),Color(0.5,1.0,0.9) if active else Color(0.3,0.4,0.5))
			if active:
				draw_circle(Vector2(-5,-9),2,Color.WHITE)
		"fragment":
			var points := PackedVector2Array([Vector2(0,-9),Vector2(6,0),Vector2(0,9),Vector2(-6,0)])
			draw_colored_polygon(points,Color.GOLD)
			draw_line(Vector2(0,-6),Vector2(0,5),Color(1,1,0.8),2)
			if active:
				draw_arc(Vector2.ZERO,10+_effect*10,0,TAU,16,Color.GOLD,1)
		"gate":
			var color := Color(0.3,1.0,0.6) if active else Color(1.0,0.45,0.2)
			for x in [-7,7]:
				draw_rect(Rect2(x-1,-30,3,60),color)
			if not active:
				for y in range(-24,25,12):
					draw_line(Vector2(-6,y),Vector2(7,y),color,2)
