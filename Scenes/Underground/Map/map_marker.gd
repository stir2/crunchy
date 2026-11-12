extends Node2D
## Replace this scene/art without touching map discovery, graph or progression.
@export_enum("checkpoint","gate","fragment","grave","player") var kind: String = "checkpoint"
@export var active: bool = false

func _draw() -> void:
	match kind:
		"checkpoint":
			var diamond := PackedVector2Array([Vector2(0,-6),Vector2(5,0),Vector2(0,6),Vector2(-5,0),Vector2(0,-6)])
			if active: draw_colored_polygon(diamond,Color(0.7,1.0,0.9))
			else: draw_polyline(diamond,Color(0.7,0.9,0.85),1.5,true)
		"gate":
			if active:
				draw_rect(Rect2(-5,-10,10,20),Color(0.4,1,0.7,0.15))
				draw_rect(Rect2(-3,-8,6,16),Color(0.5,1,0.75))
			else:
				draw_rect(Rect2(-6,-9,12,18),Color(1,0.72,0.4),false,2)
				draw_line(Vector2(-3,0),Vector2(3,0),Color(1,0.72,0.4),2)
		"fragment":
			draw_circle(Vector2(0,-8),6,Color(1,0.75,0.2,0.12))
			draw_circle(Vector2(0,-8),3,Color(1,0.8,0.25),active,-1.0 if active else 1.0,true)
		"grave":
			draw_arc(Vector2(0,-3),4,PI,TAU,12,Color(0.9,0.95,1),2,false)
			draw_polyline(PackedVector2Array([Vector2(-4,-3),Vector2(-4,6),Vector2(4,6),Vector2(4,-3)]),Color(0.9,0.95,1),2,false)
			draw_line(Vector2(0,-2),Vector2(0,3),Color(0.9,0.95,1),1)
			draw_line(Vector2(-2,0),Vector2(2,0),Color(0.9,0.95,1),1)
		"player":
			draw_circle(Vector2.ZERO,4,Color.WHITE)
			draw_arc(Vector2.ZERO,7,0,TAU,20,Color(1,1,1,0.6),1)
