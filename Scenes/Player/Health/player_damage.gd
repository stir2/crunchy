class_name PlayerDamageController
extends Node
## Actor reaction policy; Health owns HP/immunity, Player owns physical movement.
signal damage_reaction(hit: CombatHit, amount: int)
signal died(hit: CombatHit)
@export var default_knockback: Vector2 = Vector2(180, -160)
@export_range(0, 120) var reaction_frames: int = 8
@export_range(0.0, 5000.0, 10.0) var knockback_deceleration: float = 600.0
@export_range(0, 120) var hurt_flash_frames: int = 6
@export_range(1, 60) var blink_period_frames: int = 6
@export_range(0.1, 1.0) var invulnerable_alpha: float = 0.45
@export_range(1, 100) var spike_damage: int = 1
@export var spike_knockback: Vector2 = Vector2(180, -180)
var _reaction_until: int = -1
var _flash_until: int = -1
@onready var player: CharacterBody2D = get_parent()
@onready var health: HealthComponent = player.get_node("Health")
@onready var hurtbox: PlayerHurtbox = player.get_node("Hurtbox")
@onready var hazards: PlayerHazardDetector = player.get_node("HazardDetector")
@onready var sprite: AnimatedSprite2D = player.get_node("Visuals/AnimatedSprite2D")

func _ready() -> void:
	health.damage_received.connect(_on_damage_received)
	health.died.connect(_on_died)
	health.health_reset.connect(_on_reset)
	player.movement_reset.connect(_clear_reaction)

func receive_hit(hit: CombatHit) -> bool:
	if hit == null or hit.source == player or hurtbox.invulnerable:
		return false
	return health.take_damage(hit)

func is_dead() -> bool:
	return health.is_dead()

func is_reacting() -> bool:
	return Engine.get_physics_frames() < _reaction_until

func is_action_locked() -> bool:
	return is_dead() or is_reacting()

func begin_physics_tick() -> void:
	if not is_dead() and not health.is_invulnerable():
		hurtbox.poll_damage_areas()
		check_hazards()

func check_hazards() -> void:
	if not is_dead() and not health.is_invulnerable():
		receive_hit(hazards.overlapping_hit(spike_damage, spike_knockback))

func apply_reaction_motion(delta: float) -> void:
	player.velocity.x = move_toward(player.velocity.x, 0.0, knockback_deceleration * delta)
	player.apply_gravity(delta)

func _on_damage_received(hit: CombatHit, amount: int) -> void:
	player.interrupt_for_damage()
	var knockback := hit.knockback if hit.knockback != Vector2.ZERO else default_knockback
	# Explicit sources supply their impact location (tiles are not room origins).
	var origin := hit.world_position
	if origin == Vector2.ZERO and is_instance_valid(hit.source):
		origin = hit.source.global_position
	var side := signf(player.global_position.x - origin.x) if is_instance_valid(hit.source) else signf(hit.direction.x)
	if side == 0.0:
		side = -player.facing_direction
	player.velocity = Vector2(absf(knockback.x) * side, knockback.y)
	_reaction_until = Engine.get_physics_frames() + reaction_frames
	_flash_until = Engine.get_physics_frames() + hurt_flash_frames
	damage_reaction.emit(hit, amount) # Future impact audio/particles subscribe here.

func _on_died(hit: CombatHit) -> void:
	player.interrupt_for_damage()
	player.velocity = Vector2.ZERO
	_reaction_until = -1
	died.emit(hit)

func _clear_reaction() -> void:
	_reaction_until = -1
	_flash_until = -1
	sprite.self_modulate = Color.WHITE

func _on_reset() -> void:
	_clear_reaction()

func _process(_delta: float) -> void:
	# Dash charge owns Visuals.modulate; damage owns only sprite.self_modulate.
	var color := Color.WHITE
	var tick := Engine.get_physics_frames()
	if is_dead():
		color = Color(0.4, 0.4, 0.45)
	elif tick < _flash_until:
		color = Color(1.0, 0.35, 0.35)
	elif health.is_invulnerable() and (tick / blink_period_frames) % 2 == 0:
		color.a = invulnerable_alpha
	sprite.self_modulate = color
