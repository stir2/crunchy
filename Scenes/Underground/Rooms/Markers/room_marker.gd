@tool
class_name RoomMarker
extends Marker2D
## Subclasses expose only their own relevant spawn configuration.
enum Persistence { PERSISTENT, RESPAWN }
@export var marker_id: StringName
@export_range(0.0,1.0,0.01) var spawn_probability: float = 1.0
@export var tags: Array[StringName] = []
@export var persistence: Persistence = Persistence.PERSISTENT
@export var configuration: Resource
@export var show_debug: bool = false:
	set(value):
		show_debug = value
		queue_redraw()
func kind() -> StringName:
	return &"unsupported"
func make_request() -> RoomSpawnRequest:
	return null
func persistence_id() -> String:
	return String(marker_id)
func _draw() -> void:
	if not Engine.is_editor_hint() and not show_debug:
		return
	var colors := {&"checkpoint":Color.CYAN, &"fragment":Color.GOLD, &"gate":Color.ORANGE_RED, &"enemy":Color.CORAL, &"loot":Color.GOLD, &"hazard":Color.MAGENTA, &"transition":Color.CYAN, &"interaction":Color.CORNFLOWER_BLUE, &"decoration":Color.LIME_GREEN}
	var color: Color = colors.get(kind(), Color.WHITE)
	draw_circle(Vector2.ZERO, 6, Color(color,0.35))
	draw_rect(Rect2(-5,-5,10,10),color,false,1.5)
	draw_string(ThemeDB.fallback_font,Vector2(8,-8),"%s:%s" % [kind(),marker_id],HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
