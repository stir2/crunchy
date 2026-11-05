class_name PlayerHurtbox
extends CombatDamageable
## Explicit damage sources only; an arbitrary nearby area is not an attack.
signal damage_area_entered(area: Area2D)
signal damage_area_exited(area: Area2D)

func _ready() -> void:
	super._ready()
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func receive_hit(hit: CombatHit) -> bool:
	if hit == null or invulnerable or hit.source == damage_owner():
		return false
	return get_parent().get_node("DamageController").receive_hit(hit)

func _on_died(hit: CombatHit) -> void:
	# The player stays registered/monitoring even when dead. Health rejects hits.
	died.emit(hit)

func poll_damage_areas() -> void:
	# Query the current transform: cached Area overlaps lag one physics tick after
	# a teleport/reset and could otherwise damage the player from the old spot.
	var shape_node := get_node("CollisionShape2D") as CollisionShape2D
	if shape_node.disabled:
		return
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape_node.shape
	query.transform = shape_node.global_transform
	query.collision_mask = collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for result in get_world_2d().direct_space_state.intersect_shape(query):
		var area := result["collider"] as CombatDamageArea
		if area != null:
			receive_hit(area.create_hit(damage_owner()))

func _on_area_entered(area: Area2D) -> void:
	damage_area_entered.emit(area)
	# Poll on the player's physics tick, outside overlap-signal dispatch.

func _on_area_exited(area: Area2D) -> void:
	damage_area_exited.emit(area)
