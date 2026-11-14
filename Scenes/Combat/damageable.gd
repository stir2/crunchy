class_name CombatDamageable
extends Area2D
## Reusable hurtbox: attach DIRECTLY below the enemy's Node2D/CharacterBody2D root.
## damage_owner() uses that parent for self-hit rejection and per-swing deduplication.
## Enemy setup: collision_layer=32 (layer 6), collision_mask=0, monitorable=true,
## plus a CollisionShape2D. A passive hurtbox never damages the player.
## Connect damaged(hit, remaining_health) to apply hit.knockback/flash in the AI;
## connect died(hit) to stop attacks and handle death. Health is applied here.
## Enemy physics must respect is_hitstopped() and health <= 0 before steering or
## move_and_slide(); this component does not automatically pause/move its parent.
## See Tests/Scenes/Player/combat_dummy.gd for minimal working reaction code.
signal damaged(hit: CombatHit, remaining_health: int)
signal hit_confirmed(hit: CombatHit)
signal died(hit: CombatHit)
signal health_reset
@export_range(1, 1000, 1) var max_health: int = 6
@export var invulnerable: bool = false
## Optional player slash damage for encounters using a different boss damage scale.
## -1 keeps the attacker's normal damage. Projectiles and knockback are unaffected.
@export_range(-1, 100) var player_melee_damage_override: int = -1
## Empty creates an owned HealthComponent configured by max_health above.
## With an explicit Health node, configure HP on that node instead; max_health
## here is only used for the owned component. Paths are relative to this hurtbox.
@export var health_component_path: NodePath
var health_component: HealthComponent
var health: int:
	get:
		return health_component.current_health if is_instance_valid(health_component) else 0
var _owns_health: bool = false
var _normal_layer: int
var _hitstop_until_tick: int = -1
var _frozen_animations: Array[Dictionary] = []

func _ready() -> void:
	set_process(false)
	_normal_layer = collision_layer
	health_component = get_node_or_null(health_component_path) as HealthComponent if not health_component_path.is_empty() else null
	if health_component == null:
		_owns_health = true
		health_component = HealthComponent.new()
		health_component.base_max_health = max_health
		add_child(health_component)
	health_component.damage_received.connect(_on_damage_received)
	health_component.died.connect(_on_died)
	health_component.health_reset.connect(_on_reset)

func damage_owner() -> Node2D:
	return get_parent() as Node2D

func receive_hit(hit: CombatHit) -> bool:
	if hit == null or invulnerable or hit.source == damage_owner():
		return false
	return health_component.take_damage(hit)

## Reuse an actor's stagger/knockback reaction without damage or death rewards.
func receive_knockback(hit: CombatHit) -> bool:
	if hit == null or invulnerable or health <= 0 or hit.source == damage_owner():
		return false
	damaged.emit(hit, health)
	return true

func _on_damage_received(hit: CombatHit, _amount: int) -> void:
	damaged.emit(hit, health)
	hit_confirmed.emit(hit)

func _on_died(hit: CombatHit) -> void:
	set_deferred("collision_layer", 0)
	died.emit(hit)

func _on_reset() -> void:
	set_deferred("collision_layer", _normal_layer)
	_hitstop_until_tick = -1
	_resume_animations()
	health_reset.emit()

func begin_hitstop(ticks: int) -> void:
	if ticks > 0:
		_hitstop_until_tick = maxi(_hitstop_until_tick, Engine.get_physics_frames() + ticks)
		if _frozen_animations.is_empty():
			_freeze_animations(damage_owner())
		set_process(not _frozen_animations.is_empty())

func _process(_delta: float) -> void:
	if not _frozen_animations.is_empty() and not is_hitstopped():
		_resume_animations()

func _freeze_animations(node: Node) -> void:
	if node is AnimatedSprite2D or node is AnimationPlayer:
		_frozen_animations.append({"node":weakref(node), "speed":node.speed_scale})
		node.speed_scale = 0.0
	for child in node.get_children():
		_freeze_animations(child)

func _resume_animations() -> void:
	for entry in _frozen_animations:
		var animation: Node = entry.node.get_ref()
		if is_instance_valid(animation): animation.speed_scale = entry.speed
	_frozen_animations.clear()
	set_process(false)

func is_hitstopped() -> bool:
	return Engine.get_physics_frames() <= _hitstop_until_tick

func reset_damageable() -> void:
	if _owns_health:
		health_component.base_max_health = max_health
	health_component.reset_health()
