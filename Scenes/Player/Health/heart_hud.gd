class_name HeartHUD
extends Control
## Compact placeholder pixel hearts. Bind any HealthComponent, independent of Player.
@export var health_path: NodePath
@export_range(1, 6) var pixel_scale: int = 2
@export var full_color: Color = Color(0.92, 0.22, 0.28)
@export var empty_color: Color = Color(0.23, 0.2, 0.28)
var health: HealthComponent
const HEART: Array[String] = ["0110110", "1111111", "1111111", "0111110", "0011100", "0001000"]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not health_path.is_empty():
		bind_health(get_node_or_null(health_path) as HealthComponent)

func bind_health(component: HealthComponent) -> void:
	if is_instance_valid(health) and health.health_changed.is_connected(_on_health_changed):
		health.health_changed.disconnect(_on_health_changed)
	health = component
	if health != null:
		health.health_changed.connect(_on_health_changed)
	queue_redraw()

func heart_count() -> int:
	return ceili(health.max_health / 2.0) if is_instance_valid(health) else 0

## 0 empty, 1 half, 2 full. Also useful to skin this display with future artwork.
func heart_fill(index: int) -> int:
	return clampi(health.current_health - index * 2, 0, 2) if is_instance_valid(health) else 0

func _on_health_changed(_current: int, _maximum: int) -> void:
	queue_redraw()

func _draw() -> void:
	for heart in range(heart_count()):
		var fill := heart_fill(heart)
		for y in range(HEART.size()):
			for x in range(7):
				if HEART[y][x] == "1":
					var filled := fill == 2 or (fill == 1 and x < 3)
					var rect := Rect2(Vector2(heart * 9 + x, y) * pixel_scale, Vector2.ONE * pixel_scale)
					draw_rect(rect, full_color if filled else empty_color)
