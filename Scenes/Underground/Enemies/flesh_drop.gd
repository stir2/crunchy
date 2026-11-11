extends Area2D
## Touch collection credits once; the existing HUD owns all flights and bounces.
signal touched
signal landed
const FALL_SPEED := 400.0
@export var artwork: Texture2D = preload("res://uiSprites/flesh.png")
@export var hover_seconds: float = 1
var terrain_ready: Callable
var _age: float = 0.0
var _collecting: bool = false
var _grounded := false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 20
	shape.shape = circle
	add_child(shape)
	$Sprite2D.texture = artwork
	if artwork != null: $Sprite2D.scale = Vector2.ONE * 12.0 / artwork.get_width()

func _physics_process(delta: float) -> void:
	_age += delta
	_fall(delta)
	$Sprite2D.position.y = -8.0 + sin(_age * 4.0) * 2.0
	if _collecting or _age < hover_seconds: return
	for body in get_overlapping_bodies():
		if body is Player and not body.damage.is_dead():
			_collecting = true
			touched.emit()
			break


func _fall(delta: float) -> void:
	var destination := global_position if _grounded else global_position + Vector2.DOWN * FALL_SPEED * delta
	var probe := destination + Vector2.DOWN
	var swept := Rect2(global_position, Vector2.ONE).expand(probe)
	if terrain_ready.is_valid() and not terrain_ready.call(swept):
		return
	var ray := PhysicsRayQueryParameters2D.create(global_position, probe, 1)
	ray.hit_from_inside = true
	var contact := get_world_2d().direct_space_state.intersect_ray(ray)
	if contact.is_empty():
		global_position = destination
		_grounded = false
	elif not _grounded:
		global_position.y = maxf(global_position.y, float(contact.position.y) - 0.5)
		_grounded = true
		landed.emit()
