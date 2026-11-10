extends Area2D
## Touch collection credits once; the existing HUD owns all flights and bounces.
signal touched
@export var artwork: Texture2D = preload("res://uiSprites/flesh.png")
@export var hover_seconds: float = 1
var _age: float = 0.0
var _collecting: bool = false

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
	$Sprite2D.position.y = -8.0 + sin(_age * 4.0) * 2.0
	if _collecting or _age < hover_seconds: return
	for body in get_overlapping_bodies():
		if body is Player and not body.damage.is_dead():
			_collecting = true
			touched.emit()
			break
