extends Node
## Separate living enemies along their surface, without making them solid platforms.
static var _frame: int = -1
static var _actors: Array[Node] = []
@onready var actor: CharacterBody2D = get_parent()
@onready var body: CollisionShape2D = actor.get_node("CollisionShape2D")


func _physics_process(delta: float) -> void:
	if actor._dying or actor.damageable.is_hitstopped() or not actor._can_space():
		return
	if _frame != Engine.get_physics_frames():
		_frame = Engine.get_physics_frames()
		_actors = get_tree().get_nodes_in_group("spacing_enemies")
	var axis: Vector2 = actor._spacing_axis()
	var correction := 0.0
	for other in _actors:
		if not is_instance_valid(other) or other == actor or other._dying or not other._can_space():
			continue
		if absf(axis.dot(other._spacing_axis())) < 0.9:
			continue
		var other_body := other.get_node("CollisionShape2D") as CollisionShape2D
		var offset := body.global_position - other_body.global_position
		if offset.length_squared() > 42 * 42 or absf(offset.cross(axis)) > 22:
			continue
		var distance := offset.dot(axis)
		var minimum := _half_width(body.shape) + _half_width(other_body.shape) + 4.0
		if absf(distance) >= minimum:
			continue
		var side := signf(distance)
		if absf(distance) < 0.1:
			side = -1.0 if actor.get_instance_id() < other.get_instance_id() else 1.0
		correction += side * (minimum - absf(distance))
	var motion := axis * clampf(correction, -300 * delta, 300 * delta)
	if motion.length_squared() < 0.0001:
		return
	# A crowded enemy should not be shoved off a ledge to make room.
	var normal := Vector2(axis.y, -axis.x)
	var point := body.global_position + motion
	var floor_query := PhysicsRayQueryParameters2D.create(point, point - normal * 35, 1)
	if actor.get_world_2d().direct_space_state.intersect_ray(floor_query).is_empty():
		return
	actor.move_and_collide(motion)


func _half_width(shape: Shape2D) -> float:
	if shape is RectangleShape2D:
		return shape.size.x * 0.5
	if shape is CircleShape2D:
		return shape.radius
	return 14.0
