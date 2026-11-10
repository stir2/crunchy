class_name PlayerDamageController
extends Node
## Actor reaction policy; Health owns HP/immunity, Player owns physical movement.
signal damage_reaction(hit: CombatHit, amount: int)
signal died(hit: CombatHit)
signal attack_parried(hit: CombatHit, projectile: bool)
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
var _parry_flash_until: int = -1
var _parry_sources: Dictionary[int, bool] = {}
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
	player.movement_state_changed.connect(_on_movement_state_changed)

func receive_hit(hit: CombatHit, allow_parry := true) -> bool:
	if hit == null or hit.source == player or hurtbox.invulnerable:
		return false
	if allow_parry and try_dash_parry(hit):
		return false
	return health.take_damage(hit)

func try_dash_parry(hit: CombatHit, projectile: Node2D = null) -> bool:
	if hit == null or is_dead() or hurtbox.invulnerable or player.movement_state != Player.MovementState.DASHING:
		return false
	# Melee parries apply to enemies, never floor spikes or damage volumes.
	if projectile == null and (not is_instance_valid(hit.source) or not hit.source.is_in_group("enemies")):
		return false
	var offset := hit.world_position - (player.global_position + Vector2(0, -18))
	if absf(offset.y) > 40.0:
		return false
	var facing: float = player.dash_direction
	# A near-vertical attack centered over the Chief can be deflected either way.
	var overhead := absf(hit.direction.y) > 0.9 and absf(offset.x) <= 8.0
	if not overhead:
		var approach := offset.x if absf(offset.x) > 2.0 else -hit.direction.x
		if approach * facing <= 0.0:
			return false
	if projectile != null and not projectile.reflect_from(player):
		return false
	var source: Node2D = projectile
	if source == null:
		source = hit.attack_area if is_instance_valid(hit.attack_area) else hit.source
	var identity := source.get_instance_id()
	if not _parry_sources.has(identity):
		_parry_sources[identity] = true
		_parry_flash_until = Engine.get_physics_frames() + 6
		get_node("/root/SoundManager").play_limited(&"parry", -14, 0.08)
		attack_parried.emit(hit, projectile != null)
	return true

func _on_movement_state_changed(state: int) -> void:
	if state == Player.MovementState.DASHING:
		_parry_sources.clear()

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
	if health.is_dead(): return # Lethal hits preserve the fall instead of launching a hurt reaction.
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
	player.velocity = Vector2(0,maxf(player.velocity.y,0.0))
	_reaction_until = -1
	died.emit(hit)

func _clear_reaction() -> void:
	_reaction_until = -1
	_flash_until = -1
	_parry_flash_until = -1
	_parry_sources.clear()
	sprite.self_modulate = Color.WHITE

func _on_reset() -> void:
	_clear_reaction()

func _process(_delta: float) -> void:
	# Dash charge owns Visuals.modulate; damage owns only sprite.self_modulate.
	var color := Color.WHITE
	var tick := Engine.get_physics_frames()
	if is_dead():
		color = Color.WHITE # Preserve the supplied death sheet colors.
	elif tick < _parry_flash_until:
		color = Color(0.4, 1.0, 1.0)
	elif tick < _flash_until:
		color = Color(1.0, 0.35, 0.35)
	elif health.is_invulnerable() and (tick / blink_period_frames) % 2 == 0:
		color.a = invulnerable_alpha
	sprite.self_modulate = color

## Preserve frame-based deadlines across an explicit gameplay pause.
func compensate_paused_ticks(start_tick: int, ticks: int) -> void:
	if _reaction_until > start_tick:
		_reaction_until += ticks
	if _flash_until > start_tick:
		_flash_until += ticks
	if _parry_flash_until > start_tick:
		_parry_flash_until += ticks
