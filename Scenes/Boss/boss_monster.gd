extends Node2D
## Arm encounter. Attack clocks advance only in physics; pause freezes the whole rig.
signal ground_impact(point: Vector2, heavy: bool)
signal defeated
signal defeat_finished
signal waves_requested

enum Phase { REST, SWIPE_WINDUP, SWIPE_DROP, SWIPE_DRAG, SWIPE_RECOVER, SWIPE_RETRACT,
	SLAM_TRACK, SLAM_LOCK, SLAM_STRIKE, SLAM_IMPACT, SLAM_RECOVER, SLAM_RETRACT, WITHDRAW, WAVES, RETURN, STOPPED, DEFEATED }

@export var target: Player
@export var maximum_health: int = 180
@export var attack_damage: int = 2
@export var floor_y: float = 304.0
@export var swipe_duration: float = 1.65
@export var recovery_duration: float = 2.2

var phase: Phase = Phase.REST
var elapsed := 0.0
var duration := 2.0
var _age := 0.0
var _attack_index := 0
var _start := Vector2.ZERO
var _slam_x := 440.0
var _dust_clock := 0.0
var _hurt_time := 0.0
var _defeat_emitted := false
var _waves_pending := false
var _waves_played := false
var _left_start := Vector2.ZERO
var _right_start := Vector2.ZERO
var _right_rotation_start := 0.0
var _contact_used := false
var _death_impact_played := false
var _death_origin := Vector2.ZERO
const LEFT_REST := Vector2(96, 265)
const SWIPE_START := 56.0
const SWIPE_END := 282.0
const CLAW_SWEEP_START := 484.0
const CLAW_SWEEP_END := 326.0
const CLAW_SWEEP_LIFT := 37.0
const RIGHT_REST := Vector2(527, 265)

@onready var health: HealthComponent = $Health
@onready var left: Node2D = $SwipeHand
@onready var right: Node2D = $ClawHand
@onready var left_hurt: CombatDamageable = $SwipeHand/Hurtbox
@onready var right_hurt: CombatDamageable = $ClawHand/Hurtbox
@onready var left_attack: CombatDamageArea = $SwipeHand/Attack
@onready var right_attack: CombatDamageArea = $ClawHand/Attack
@onready var _claw_slam_shape: Shape2D = $ClawHand/Attack/Shape.shape
var _claw_sweep_shape: RectangleShape2D

func _ready() -> void:
	add_to_group("enemies")
	health.base_max_health = maximum_health
	health.reset_health()
	health.damage_received.connect(_on_damaged)
	health.died.connect(_on_died)
	left_attack.damage = attack_damage
	right_attack.damage = attack_damage
	_claw_sweep_shape = RectangleShape2D.new()
	_claw_sweep_shape.size = Vector2(30, 42)
	_set_phase(Phase.REST, 2.0)
	_pose()

func _physics_process(delta: float) -> void:
	if left_hurt.is_hitstopped() or right_hurt.is_hitstopped():
		return
	if phase != Phase.DEFEATED:
		_age += delta
	_hurt_time = maxf(0.0, _hurt_time - delta)
	elapsed += delta
	var t := clampf(elapsed / duration, 0.0, 1.0)
	var smooth := smoothstep(0.0, 1.0, t)
	match phase:
		Phase.REST:
			left.position = LEFT_REST + Vector2(0, sin(_age * 1.4) * 3)
			right.position = RIGHT_REST + Vector2(0, sin(_age * 1.2 + 1) * 3)
		Phase.SWIPE_WINDUP:
			left.position = _left_start.lerp(Vector2(SWIPE_START, floor_y - 88), smooth)
			right.position = _right_start.lerp(Vector2(CLAW_SWEEP_START, floor_y - 95), smooth)
			right.rotation = lerp_angle(_right_rotation_start, PI / 2, smooth)
		Phase.SWIPE_DROP:
			left.position = _left_start.lerp(Vector2(SWIPE_START, floor_y), t * t)
			right.position = _right_start.lerp(Vector2(CLAW_SWEEP_START, floor_y - CLAW_SWEEP_LIFT), t * t)
		Phase.SWIPE_DRAG:
			left.position = Vector2(lerpf(SWIPE_START, SWIPE_END, smooth), floor_y)
			right.position = Vector2(lerpf(CLAW_SWEEP_START, CLAW_SWEEP_END, smooth), floor_y - CLAW_SWEEP_LIFT)
			right.rotation = PI / 2
			_dust_clock -= delta
			if _dust_clock <= 0:
				_dust_clock = 0.16
				ground_impact.emit(left.global_position, false)
				ground_impact.emit(Vector2(right.global_position.x + 60, floor_y), false)
		Phase.SWIPE_RECOVER:
			left.position = Vector2(SWIPE_END, floor_y)
			right.position = Vector2(CLAW_SWEEP_END, floor_y - CLAW_SWEEP_LIFT)
			right.rotation = PI / 2
		Phase.SWIPE_RETRACT:
			left.position = _left_start.lerp(LEFT_REST, smooth) + Vector2(0, -sin(t * PI) * 85)
			right.position = _right_start.lerp(RIGHT_REST, smooth) + Vector2(0, -sin(t * PI) * 45)
			right.rotation = lerp_angle(_right_rotation_start, 0, smooth)
		Phase.SLAM_TRACK:
			if is_instance_valid(target):
				_slam_x = move_toward(_slam_x, clampf(target.position.x, 370, 572), delta * 290)
			right.position = Vector2(_slam_x, lerpf(_start.y, floor_y - 135, smooth))
		Phase.SLAM_LOCK:
			right.position = Vector2(_slam_x, floor_y - 135 - sin(t * PI) * 5)
		Phase.SLAM_STRIKE:
			right.position = Vector2(_slam_x, lerpf(floor_y - 135, floor_y, t * t))
		Phase.SLAM_IMPACT, Phase.SLAM_RECOVER:
			right.position = Vector2(_slam_x, floor_y)
		Phase.SLAM_RETRACT:
			right.position = _start.lerp(RIGHT_REST, smooth) + Vector2(0, -sin(t * PI) * 45)
		Phase.WITHDRAW:
			left.position = _left_start.lerp(Vector2(70, 155), smooth)
			right.position = _right_start.lerp(Vector2(570, 155), smooth)
			right.rotation = lerp_angle(_right_rotation_start, 0, smooth)
		Phase.WAVES:
			left.position = Vector2(70, 155)
			right.position = Vector2(570, 155)
		Phase.RETURN:
			left.position = _left_start.lerp(LEFT_REST + Vector2(0, sin(_age * 1.4) * 3), smooth)
			right.position = _right_start.lerp(RIGHT_REST + Vector2(0, sin(_age * 1.2 + 1) * 3), smooth)
			right.rotation = lerp_angle(_right_rotation_start, 0, smooth)
		Phase.DEFEATED:
			# Regain a connected pose, then let the entire actor fall as one body.
			var release := smoothstep(0.0, 0.55, elapsed)
			left.position = _left_start.lerp(LEFT_REST, release)
			right.position = _right_start.lerp(RIGHT_REST, release)
			right.rotation = lerp_angle(_right_rotation_start, 0, release)
			var fall := clampf((elapsed - 0.55) / 1.2, 0, 1)
			position = _death_origin + Vector2(0, 94 * fall * fall)
			if fall >= 1 and not _death_impact_played:
				_death_impact_played = true
				ground_impact.emit(Vector2(320, floor_y), true)
	_pose()
	if elapsed < duration:
		return
	match phase:
		Phase.REST:
			if _waves_pending:
				_set_phase(Phase.WITHDRAW, 1.1)
				return
			_set_phase(Phase.SWIPE_WINDUP if _attack_index % 2 == 0 else Phase.SLAM_TRACK, 1.0)
			_attack_index += 1
		Phase.SWIPE_WINDUP: _set_phase(Phase.SWIPE_DROP, 0.32)
		Phase.SWIPE_DROP:
			ground_impact.emit(left.global_position, true)
			_set_phase(Phase.SWIPE_DRAG, swipe_duration)
		Phase.SWIPE_DRAG: _set_phase(Phase.SWIPE_RECOVER, recovery_duration)
		Phase.SWIPE_RECOVER: _set_phase(Phase.SWIPE_RETRACT, 0.85)
		Phase.SWIPE_RETRACT, Phase.SLAM_RETRACT: _set_phase(Phase.REST, 0.8)
		Phase.SLAM_TRACK: _set_phase(Phase.SLAM_LOCK, 0.65)
		Phase.SLAM_LOCK: _set_phase(Phase.SLAM_STRIKE, 0.22)
		Phase.SLAM_STRIKE:
			ground_impact.emit(right.global_position, true)
			_set_phase(Phase.SLAM_IMPACT, 0.16)
		Phase.SLAM_IMPACT: _set_phase(Phase.SLAM_RECOVER, recovery_duration)
		Phase.SLAM_RECOVER: _set_phase(Phase.SLAM_RETRACT, 0.75)
		Phase.RETURN: _set_phase(Phase.REST, 0.8)
		Phase.WITHDRAW:
			_set_phase(Phase.WAVES, 1.0)
			_waves_pending = false
			_waves_played = true
			waves_requested.emit()
		Phase.DEFEATED:
			if not _defeat_emitted:
				_defeat_emitted = true
				defeat_finished.emit()

func _set_phase(next: Phase, seconds: float) -> void:
	_left_start = left.position
	_right_start = right.position
	_right_rotation_start = right.rotation
	if next == Phase.SWIPE_DRAG or next == Phase.SLAM_STRIKE:
		_contact_used = false
	phase = next
	elapsed = 0.0
	duration = maxf(0.01, seconds)
	_start = left.position if next <= Phase.SWIPE_RETRACT else right.position
	left_attack.active = next == Phase.SWIPE_DRAG and not _contact_used
	right_attack.active = (next == Phase.SWIPE_DRAG or next == Phase.SLAM_STRIKE or next == Phase.SLAM_IMPACT) and not _contact_used
	left_hurt.invulnerable = next != Phase.SWIPE_RECOVER
	right_hurt.invulnerable = next != Phase.SLAM_RECOVER and next != Phase.SWIPE_RECOVER
	if next == Phase.SWIPE_WINDUP:
		# During a horizontal drag, only the blade's leading edge cuts.
		right_attack.position = Vector2(20, -20)
		$ClawHand/Attack/Shape.set_deferred("shape", _claw_sweep_shape)
	if next == Phase.SLAM_TRACK:
		right_attack.position = Vector2(0, -58)
		$ClawHand/Attack/Shape.set_deferred("shape", _claw_slam_shape)
		_slam_x = right.position.x

func stop_attacks() -> void:
	if phase != Phase.DEFEATED:
		_set_phase(Phase.STOPPED, 1.0)

func _pose() -> void:
	$Body.position.y = roundf(sin(_age * 1.1) * 2)
	$Head.position = Vector2(sin(_age * 0.7) * 2, sin(_age * 1.1 - 0.3) * 3).round()
	$Head.rotation = 0
	var shoulder: Vector2 = Vector2(252, 104) + $Body.position
	var wrist := left.position + Vector2(4, -71)
	var span: Vector2 = wrist - shoulder
	var elbow: Vector2 = shoulder + span * 0.5 - span.normalized().orthogonal() * 52
	_fit_bone($UpperArm, Vector2(238, 104), Vector2(156, 110), shoulder, elbow)
	_fit_bone($LowerArm, Vector2(135, 105), Vector2(106, 185), elbow, wrist)
	_fit_bone($ClawArm, Vector2(405, 88), Vector2(510, 175), Vector2(386, 104) + $Body.position, right.position + Vector2(-14, -75).rotated(right.rotation))
	var flash := Color(1.5, 0.65, 0.65) if _hurt_time > 0 else Color.WHITE
	$Head.modulate = flash
	left.modulate = flash
	right.modulate = flash

func _fit_bone(sprite: Sprite2D, a: Vector2, b: Vector2, start: Vector2, end: Vector2) -> void:
	# The original PNG canvas coordinates are the rig's source pivots.
	sprite.offset = -a
	var length_ratio := start.distance_to(end) / a.distance_to(b)
	# A uniform scale and rotation cannot shear the original pixel grid.
	sprite.position = start.round()
	sprite.rotation = (end - start).angle() - (b - a).angle()
	sprite.scale = Vector2.ONE * length_ratio

func finish_waves() -> void:
	if phase == Phase.WAVES and not health.is_dead():
		_set_phase(Phase.RETURN, 1.15)

func _on_damaged(_hit: CombatHit, _amount: int) -> void:
	_hurt_time = 0.12
	if not _waves_played and health.current_health <= maximum_health * 0.75 and not health.is_dead():
		_waves_pending = true
	get_node("/root/SoundManager").play_limited(&"cleaver_impact", -13, 0.06)

func _on_died(_hit: CombatHit) -> void:
	_death_origin = position
	_hurt_time = 0
	_set_phase(Phase.DEFEATED, 4.5)
	defeated.emit()

func set_target(actor: Player) -> void:
	target = actor
	if not target.health.damage_received.is_connected(_on_target_damaged):
		target.health.damage_received.connect(_on_target_damaged)
	if not target.damage.attack_parried.is_connected(_on_target_parried):
		target.damage.attack_parried.connect(_on_target_parried)

func _on_target_damaged(hit: CombatHit, _amount: int) -> void:
	if hit.source == self:
		_consume_contact()

func _on_target_parried(hit: CombatHit, projectile: bool) -> void:
	if hit.source == self and not projectile:
		_consume_contact()

func _consume_contact() -> void:
	# Shared across both hands: one accepted hit or parry resolves this attack.
	_contact_used = true
	left_attack.active = false
	right_attack.active = false
