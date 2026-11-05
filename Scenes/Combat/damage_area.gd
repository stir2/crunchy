class_name CombatDamageArea
extends Area2D
## Explicit enemy/environment attack. Add a CollisionShape2D and use
## collision_layer=8 (layer 4). Player hurtboxes query it; collision_mask=0 is fine.
## On enemy scenes, set active=false initially and enable only for damage frames;
## disable on recovery/interruption/death. Merely being nearby must not attack.
## Persistent environmental areas may stay active (the default used by the lab).
@export var active: bool = true
@export_range(1, 1000) var damage: int = 1
@export var knockback: Vector2 = Vector2(180, -160)
## Point to the enemy root (".." when directly below it), relative to this area.
## Empty uses the area itself, suitable for a standalone environmental source.
@export var source_path: NodePath
@export var show_debug_shape: bool = false

func create_hit(target: Node2D) -> CombatHit:
	if not active:
		return null
	var hit := CombatHit.new()
	hit.amount = damage
	hit.source = get_node_or_null(source_path) as Node2D if not source_path.is_empty() else self
	hit.world_position = global_position
	var side := signf(target.global_position.x - global_position.x)
	hit.direction = Vector2(side if side != 0.0 else 1.0, 0)
	hit.knockback = Vector2(absf(knockback.x) * hit.direction.x, knockback.y)
	return hit

func _draw() -> void:
	if show_debug_shape:
		draw_rect(Rect2(-16, -24, 32, 48), Color(0.85, 0.25, 0.22, 0.35))
		draw_rect(Rect2(-16, -24, 32, 48), Color(1, 0.45, 0.25), false, 1)
