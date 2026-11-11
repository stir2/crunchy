extends Node2D
## Arm encounter. Attack clocks advance only in physics; pause freezes the whole rig.
signal ground_impact(point: Vector2, heavy: bool)
signal defeated
signal defeat_finished
signal waves_requested
signal last_toll_interrupted
signal floor_break_requested
signal volley_started
signal volley_burst(index: int)
signal attack_tell(strike: bool, duration: float)
signal arm_impact(strike: bool, point: Vector2)
signal slab_broken

enum Phase { REST, SWIPE_WINDUP, SWIPE_DROP, SWIPE_DRAG, SWIPE_RECOVER, SWIPE_RETRACT,
	SLAM_TRACK, SLAM_LOCK, SLAM_STRIKE, SLAM_IMPACT, SLAM_RECOVER, SLAM_RETRACT, WITHDRAW, WAVES, RETURN, BREAK, BREAK_RETRACT, VOLLEY, STOPPED, DEFEATED }

@export var target: Player
@export var maximum_health: int = 300
@export var attack_damage: int = 2
@export var floor_y: float = 304.0

var phase: Phase = Phase.REST
var elapsed := 0.0
var duration := 2.0
var _age := 0.0
var _hurt_time := 0.0
var _defeat_emitted := false
var _waves_pending := false
var _waves_played := false
var _left_start := Vector2.ZERO
var _right_start := Vector2.ZERO
var sweep_floor: Callable
var _dust_clock := 0.0
var _left_contact_used := false
var _right_contact_used := false
var _combo := false
var _reverse_sweep := false
var _sweep_from := 52.0
var _sweep_to := 578.0
var _combo_landed := false
var _combo_wedged := false
var _burst := 0
var _body_shift := Vector2.ZERO
var _body_start := Vector2.ZERO
var _hand_angle := 0.0
var _hand_angle_start := 0.0
var _head_tracking := 0.0
var _fall_left := Vector2.ZERO
var _fall_right := Vector2.ZERO
var _landing_head_offset := 0.0
var lower_arena := false
var _breaking_floor := false
var _volley_next := true
var _slab_available := true
var _slab_armed := false
var _reflection_extended := false
var _reflection_earned := false
var _upper_arm_attacks := 0
var _lower_combo_next := true
var _last_stand_started := false
var _last_toll := false
var _toll_stagger := false
var _toll_cancel_queued := false
const SWIPE_DROP_TIME := 0.30
const SLAM_X := 486.0
const CLAW_LIFT := 183.0
const DRAG_HAND = preload("res://BossSprites/Sweep Attack/bossHandDrag.png")
const SWIPE_WRIST := Vector2(4, -71)
const BREAK_RETRACT_TIME := 0.90
const SLAM_LOCK_TIME := 0.43
const SLAM_FALL_TIME := 0.20
const COMBO_IMPACT := 0.64
const REVERSE_IMPACT := -0.10
const IMPACT_WINDOW := 0.20
const BURST_TIMES := [0.85, 1.24, 1.63]
const LEFT_REST := Vector2(96, 265)
const RIGHT_REST := Vector2(527, 265)

@onready var health: HealthComponent = $Health
@onready var left: Node2D = $SwipeHand
@onready var right: Node2D = $ClawHand
@onready var left_hurt: CombatDamageable = $SwipeHand/Hurtbox
@onready var right_hurt: CombatDamageable = $ClawHand/Hurtbox
@onready var left_attack: CombatDamageArea = $SwipeHand/Attack
@onready var right_attack: CombatDamageArea = $ClawHand/Attack

@onready var _drag_sprite := Sprite2D.new()

func _ready() -> void:
	_drag_sprite.texture = DRAG_HAND
	_drag_sprite.centered = false
	_drag_sprite.offset = Vector2(-69, -6)
	left.add_child(_drag_sprite)
	add_to_group("enemies")
	health.base_max_health = maximum_health
	health.reset_health()
	health.damage_received.connect(_on_damaged)
	health.died.connect(_on_died)
	left_attack.damage = attack_damage
	right_attack.damage = attack_damage
	right_attack.attack_direction = Vector2.DOWN
	_set_phase(Phase.REST, 2.0)
	_pose()

func _physics_process(delta: float) -> void:
	if left_hurt.is_hitstopped() or right_hurt.is_hitstopped():
		return
	if phase != Phase.DEFEATED:
		_age += delta
		var gaze := 0.0
		if is_instance_valid(target) and phase != Phase.STOPPED:
			var side := to_local(target.global_position).x - 320.0
			gaze = signf(side) * smoothstep(32.0, 180.0, absf(side))
		_head_tracking = lerpf(_head_tracking, gaze, 1.0 - exp(-2.6 * delta))
	_hurt_time = maxf(0.0, _hurt_time - delta)
	elapsed += delta
	var t := clampf(elapsed / duration, 0.0, 1.0)
	var smooth := t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
	var sweep_direction := signf(_sweep_to - _sweep_from)
	var lean := Vector2.ZERO
	_hand_angle = lerpf(_hand_angle_start, 0.0, smooth)
	match phase:
		Phase.REST:
			left.position = _left_start.lerp(_idle_left(), smooth)
			right.position = _right_start.lerp(_idle_right(), smooth)
		Phase.SWIPE_WINDUP:
			left.position = _left_start.lerp(_sweep_point(_sweep_from) - Vector2(0, 88), smooth)
			right.position = _right_start.lerp(_raised_claw() if _combo else RIGHT_REST + Vector2(12, -26), smooth)
			lean = Vector2(-sweep_direction * 7, -5) * sin(smooth * PI)
		Phase.SWIPE_DROP:
			left.position = _left_start.lerp(_sweep_point(_sweep_from), t * t)
			lean = Vector2(sweep_direction * 7, 12) * t * t
			if _combo:
				_update_combo_claw(elapsed - duration)
		Phase.SWIPE_DRAG:
			left_attack.active = not _left_contact_used
			var x := lerpf(_sweep_from, _sweep_to, smooth)
			left.position = _sweep_point(x)
			lean = Vector2(sweep_direction * 7, 12) * smooth + Vector2(sweep_direction * 14, 0) * sin(smooth * PI)
			_dust_clock -= delta
			if _dust_clock <= 0:
				_dust_clock = 0.09
				var dust := Vector2(x, _sweep_floor_at(x))
				ground_impact.emit(to_global(dust), false)
			if _combo:
				_update_combo_claw(elapsed)
		Phase.SWIPE_RETRACT:
			var lift := sin(smooth * PI)
			left.position = _left_start.lerp(_idle_left(), smooth) - Vector2(0, 38 * lift)
			right.position = _right_start.lerp(_idle_right(), smooth) - Vector2(0, 38 * lift if _combo else 0)
			_hand_angle += sweep_direction * 0.42 * lift
		Phase.SLAM_TRACK:
			right.position = _right_start.lerp(_raised_claw(), smooth)
			lean = Vector2(-7, -9) * smooth
		Phase.SLAM_LOCK:
			right.position = _raised_claw() - Vector2(0, 10 * sin(smooth * PI))
			lean = Vector2(-7, -9) * smooth
		Phase.SLAM_STRIKE:
			right.position = _right_start.lerp(_claw_contact(), t * t)
			lean = Vector2(12, 12) * t * t
		Phase.SLAM_IMPACT:
			lean = Vector2(7, 9) * smooth
		Phase.SLAM_RECOVER:
			if _toll_stagger:
				left.position = _left_start.lerp(_idle_left(), smoothstep(0.0, 0.65, elapsed))
				right.position = _right_start.lerp(_claw_contact(), smoothstep(0.0, 0.40, elapsed))
				right_hurt.invulnerable = elapsed < 0.40
		Phase.SLAM_RETRACT, Phase.BREAK_RETRACT:
			right.position = _right_start.lerp(_idle_right(), smooth) - Vector2(0, 14 * sin(smooth * PI))
		Phase.VOLLEY:
			_pose_volley()
		Phase.WITHDRAW:
			left.position = _left_start.lerp(Vector2(70, 155), smooth)
			right.position = _right_start.lerp(Vector2(570, 155), smooth)
		Phase.WAVES:
			left.position = Vector2(70, 155)
			right.position = Vector2(570, 155)
		Phase.RETURN:
			left.position = _left_start.lerp(LEFT_REST + Vector2(0, sin(_age * 1.4) * 3), smooth)
			right.position = _right_start.lerp(RIGHT_REST + Vector2(0, sin(_age * 1.2 + 1) * 3), smooth)
	if phase != Phase.VOLLEY and phase != Phase.DEFEATED:
		_body_shift = _body_start.lerp(lean, smooth)
	if phase != Phase.DEFEATED:
		_pose()
	if elapsed < duration:
		return
	match phase:
		Phase.REST:
			if _waves_pending:
				_set_phase(Phase.WITHDRAW, 1.1)
				return
			if not lower_arena and health.current_health <= maximum_health * 0.5:
				_breaking_floor = true
				_set_phase(Phase.SLAM_TRACK, 1.2)
			elif lower_arena and not _last_stand_started and health.current_health <= maximum_health * 0.2:
				_last_stand_started = true
				_last_toll = true
				_combo = false
				_set_phase(Phase.VOLLEY, 3.2)
			elif (lower_arena and _volley_next) or _upper_arm_attacks >= 2:
				_volley_next = false
				_upper_arm_attacks = 0
				_set_phase(Phase.VOLLEY, 2.85)
			else:
				_start_arm_attack()
		Phase.SWIPE_WINDUP: _set_phase(Phase.SWIPE_DROP, SWIPE_DROP_TIME)
		Phase.SWIPE_DROP:
			arm_impact.emit(false, left.global_position)
			_set_phase(Phase.SWIPE_DRAG, 1.44 if _combo else 1.5)
		Phase.SWIPE_DRAG:
			_set_phase(Phase.SWIPE_RECOVER, 2.2 if _combo_wedged else (1.45 if _combo else 1.9))
		Phase.SWIPE_RECOVER: _set_phase(Phase.SWIPE_RETRACT, 0.66)
		Phase.SWIPE_RETRACT, Phase.SLAM_RETRACT: _set_phase(Phase.REST, 0.45 if lower_arena else 0.8)
		Phase.SLAM_TRACK: _set_phase(Phase.SLAM_LOCK, SLAM_LOCK_TIME)
		Phase.SLAM_LOCK: _set_phase(Phase.SLAM_STRIKE, SLAM_FALL_TIME)
		Phase.SLAM_STRIKE:
			arm_impact.emit(true, right.global_position)
			if _breaking_floor:
				_set_phase(Phase.BREAK, 1.0)
				floor_break_requested.emit()
				return
			_set_phase(Phase.SLAM_IMPACT, IMPACT_WINDOW)
		Phase.SLAM_IMPACT: _set_phase(Phase.SLAM_RECOVER, 1.8)
		Phase.VOLLEY:
			if _last_toll:
				_finish_last_toll(false)
			else:
				_start_arm_attack()
		Phase.SLAM_RECOVER:
			_toll_stagger = false
			_set_phase(Phase.SLAM_RETRACT, 0.55)
		Phase.BREAK_RETRACT: _set_phase(Phase.REST, 1.0 - BREAK_RETRACT_TIME)
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
	_body_start = _body_shift
	_hand_angle_start = _hand_angle
	if next == Phase.SWIPE_WINDUP:
		_right_contact_used = false
		_combo_landed = false
		_combo_wedged = false
	if next == Phase.SWIPE_DRAG:
		_left_contact_used = false
		left_attack.attack_direction = Vector2(signf(_sweep_to - _sweep_from), 0)
		# The authored plant already has a dust burst baked into its first frames.
		_dust_clock = 0.10
	if next == Phase.SLAM_TRACK:
		_right_contact_used = false
	if next == Phase.VOLLEY:
		_burst = 0
	phase = next
	elapsed = 0.0
	duration = maxf(0.01, seconds)
	if next in [Phase.SWIPE_RECOVER, Phase.SLAM_RECOVER]:
		_reflection_extended = false
		if _reflection_earned:
			_reflection_earned = false
			extend_recovery_from_web()
	left_attack.active = next == Phase.SWIPE_DRAG
	right_attack.active = next == Phase.SLAM_IMPACT and not _right_contact_used
	if next == Phase.SWIPE_DRAG and _combo:
		_update_combo_claw(0.0)
	left_hurt.invulnerable = next != Phase.SWIPE_RECOVER
	right_hurt.invulnerable = next != Phase.SLAM_RECOVER and not (_combo and next == Phase.SWIPE_RECOVER)
	if next == Phase.SWIPE_WINDUP:
		attack_tell.emit(false, seconds + SWIPE_DROP_TIME)
		if _combo:
			attack_tell.emit(true, seconds + SWIPE_DROP_TIME + _combo_impact_time())
	elif next == Phase.SLAM_TRACK:
		attack_tell.emit(true, seconds + SLAM_LOCK_TIME + SLAM_FALL_TIME)
	elif next == Phase.VOLLEY:
		volley_started.emit()
	_pose()

func _start_arm_attack() -> void:
	var sweep := not lower_arena or _lower_combo_next
	_combo = sweep
	if lower_arena:
		_lower_combo_next = not _lower_combo_next
	if not lower_arena:
		_upper_arm_attacks += 1
	_sweep_from = 578.0 if _combo and _reverse_sweep else 52.0
	_sweep_to = 630.0 - _sweep_from
	if _combo:
		_reverse_sweep = not _reverse_sweep
	_slab_armed = false
	_volley_next = _combo
	_set_phase(Phase.SWIPE_WINDUP if sweep else Phase.SLAM_TRACK, 0.82 if lower_arena else 0.9)

func _idle_left() -> Vector2:
	return LEFT_REST + Vector2(0, sin(_age * 1.4) * 3)

func _idle_right() -> Vector2:
	return RIGHT_REST + Vector2(0, sin(_age * 1.2 + 1) * 3)

func _sweep_floor_at(x: float) -> float:
	return sweep_floor.call(x) if lower_arena and sweep_floor.is_valid() else floor_y

func sweep_direction() -> float:
	return signf(_sweep_to - _sweep_from)

func _sweep_point(x: float) -> Vector2:
	if not lower_arena:
		return Vector2(x, floor_y)
	# Blend between tile centers so the wrist follows each lip without snapping.
	var left_center := floorf((x - 8.0) / 16.0) * 16.0 + 8.0
	var t := smoothstep(left_center, left_center + 16.0, x)
	return Vector2(x, lerpf(_sweep_floor_at(left_center), _sweep_floor_at(left_center + 16.0), t))

func _claw_contact() -> Vector2:
	return Vector2(SLAM_X, _sweep_floor_at(SLAM_X + 14.0) + 3.0)

func _raised_claw() -> Vector2:
	return Vector2(SLAM_X, floor_y - CLAW_LIFT)

func _combo_impact_time() -> float:
	return REVERSE_IMPACT if _sweep_to < _sweep_from else COMBO_IMPACT

func _update_combo_claw(clock: float) -> void:
	var impact := _combo_impact_time()
	var end := impact + IMPACT_WINDOW
	var fall := clampf(inverse_lerp(impact - SLAM_FALL_TIME, impact, clock), 0.0, 1.0)
	var contact := _claw_contact()
	if _combo_wedged:
		contact.y -= 16.0 * (1.0 - smoothstep(end, end + 0.18, clock))
	right.position = _raised_claw().lerp(contact, fall * fall)
	if fall >= 1.0 and not _combo_landed:
		_combo_landed = true
		_slab_armed = lower_arena and _slab_available and is_instance_valid(target) and absf(target.position.x - SLAM_X) <= 40.0
		arm_impact.emit(true, right.global_position)
	right_attack.active = _combo_landed and clock < end and not _right_contact_used
	if clock >= end and _slab_armed and _slab_available:
		_combo_wedged = true
		_slab_available = false
		slab_broken.emit()

func _pose_volley() -> void:
	if _last_toll:
		var plant := smoothstep(0.0, 0.55, elapsed)
		var draw := smoothstep(0.35, 1.45, elapsed)
		var release := smoothstep(1.45, 1.75, elapsed)
		left.position = _left_start.lerp(_sweep_point(155.0), plant)
		right.position = _right_start.lerp(_claw_contact(), plant)
		_body_shift = _body_start.lerp(Vector2(0, -22.0 * draw + 12.0 * release), plant)
		if _burst == 0 and elapsed >= 1.45:
			volley_burst.emit(0)
			_burst = 1
		return
	var rise := smoothstep(0.0, BURST_TIMES[0], elapsed)
	var settle := smoothstep(1.83, 2.85, elapsed)
	var charge := rise * (1.0 - settle)
	var recoil := 0.0
	if _burst > 0:
		recoil = sin(PI * clampf((elapsed - BURST_TIMES[_burst - 1]) / 0.20, 0.0, 1.0))
	_body_shift = Vector2(sin(elapsed * 5.5) * 34, -18 + recoil * 9) * charge
	left.position = _left_start.lerp(_idle_left(), settle) + Vector2(20 + _body_shift.x, -69) * charge
	right.position = _right_start.lerp(_idle_right(), settle) + Vector2(-20 + _body_shift.x, -85) * charge
	if _burst < BURST_TIMES.size() and elapsed >= BURST_TIMES[_burst]:
		volley_burst.emit(_burst)
		_burst += 1

func is_last_toll() -> bool:
	return _last_toll and phase == Phase.VOLLEY

func _finish_last_toll(interrupted: bool) -> void:
	if not is_last_toll():
		return
	_last_toll = false
	_toll_stagger = true
	_set_phase(Phase.SLAM_RECOVER, 4.0 if interrupted else 2.5)
	right_hurt.invulnerable = true
	if interrupted:
		last_toll_interrupted.emit()

func volley_origin() -> Vector2:
	return to_global(Vector2(320, 135) + _body_shift)

func begin_fall() -> void:
	_fall_left = left.position
	_fall_right = right.position

func pose_fall(progress: float) -> void:
	# Loose arms lag behind the descending torso, then reach for the floor.
	var lift := smoothstep(0.0, 0.30, progress)
	var plant := smoothstep(0.84, 1.0, progress)
	left.position = _fall_left.lerp(LEFT_REST - Vector2(8, 48), lift).lerp(Vector2(96, 256), plant)
	right.position = _fall_right.lerp(RIGHT_REST - Vector2(-12, 70), lift).lerp(Vector2(527, 304), plant)
	_body_shift = _body_start.lerp(Vector2.ZERO, lift)
	_pose()

func pose_landing_head(offset: float) -> void:
	_landing_head_offset = offset
	_pose()


func finish_floor_break() -> void:
	lower_arena = true
	_reverse_sweep = false
	_volley_next = true
	var sweep_shape := $SwipeHand/Attack/Shape as CollisionShape2D
	sweep_shape.shape = sweep_shape.shape.duplicate()
	(sweep_shape.shape as RectangleShape2D).size = Vector2(54, 32)
	left_attack.position.y = -18.0
	_breaking_floor = false
	_set_phase(Phase.BREAK_RETRACT, BREAK_RETRACT_TIME)

func resume_fight() -> void:
	_breaking_floor = false
	_last_toll = false
	_toll_stagger = false
	_toll_cancel_queued = false
	_set_phase(Phase.REST, 1.0)

func stop_attacks() -> void:
	if phase != Phase.DEFEATED:
		_set_phase(Phase.STOPPED, 1.0)

func _pose() -> void:
	$Body.position = _body_shift + Vector2(0, sin(_age * 1.1) * 2)
	$Head.position = _body_shift + Vector2(_head_tracking * 4.0, sin(_age * 1.1 - 0.3) * 3 + _landing_head_offset)
	$Head.rotation = 0.0
	var shoulder: Vector2 = Vector2(252, 104) + $Body.position
	var hand_sprite: Sprite2D = $SwipeHand/Sprite
	var drag_blend := 0.0
	match phase:
		Phase.SWIPE_DROP:
			drag_blend = smoothstep(duration - 0.12, duration, elapsed)
		Phase.SWIPE_DRAG, Phase.SWIPE_RECOVER:
			drag_blend = 1.0
		Phase.SWIPE_RETRACT:
			drag_blend = 1.0 - smoothstep(0.0, 0.16, elapsed)
	var wrist_offset := SWIPE_WRIST.lerp(Vector2(4, -76), drag_blend)
	hand_sprite.rotation = _hand_angle
	hand_sprite.position = wrist_offset - SWIPE_WRIST.rotated(_hand_angle)
	hand_sprite.modulate.a = 1.0 - drag_blend
	_drag_sprite.visible = drag_blend > 0.0
	_drag_sprite.modulate.a = drag_blend
	_drag_sprite.transform = Transform2D(_hand_angle, Vector2(-1.0 if sweep_direction() < 0.0 else 1.0, 1.0), 0.0, wrist_offset)
	var wrist := left.position + wrist_offset
	var span: Vector2 = wrist - shoulder
	var elbow: Vector2 = shoulder + span * 0.5 - span.normalized().orthogonal() * 52
	_fit_bone($UpperArm, Vector2(238, 104), Vector2(156, 110), shoulder, elbow)
	_fit_bone($LowerArm, Vector2(135, 105), Vector2(106, 185), elbow, wrist)
	_fit_bone($ClawArm, Vector2(405, 88), Vector2(510, 175), Vector2(386, 104) + $Body.position, right.position + Vector2(-14, -75))
	var flash := Color(1.5, 0.65, 0.65) if _hurt_time > 0 else Color.WHITE
	$Head.modulate = flash
	left.modulate = flash
	right.modulate = flash

func _fit_bone(sprite: Sprite2D, a: Vector2, b: Vector2, start: Vector2, end: Vector2) -> void:
	# The original PNG canvas coordinates are the rig's source pivots.
	sprite.offset = -a
	var length_ratio := start.distance_to(end) / a.distance_to(b)
	# A uniform scale and rotation cannot shear the original pixel grid.
	sprite.position = start
	sprite.rotation = (end - start).angle() - (b - a).angle()
	sprite.scale = Vector2.ONE * length_ratio

func finish_waves() -> void:
	if phase == Phase.WAVES and not health.is_dead():
		_set_phase(Phase.RETURN, 1.15)

func extend_recovery_from_web() -> void:
	if not _reflection_extended and phase in [Phase.SWIPE_RECOVER, Phase.SLAM_RECOVER]:
		_reflection_extended = true
		var progress := clampf(elapsed / duration, 0.0, 0.98)
		duration += 1.0 / (1.0 - progress)
		elapsed = progress * duration


func _on_damaged(_hit: CombatHit, _amount: int) -> void:
	_hurt_time = 0.12
	if not _waves_played and health.current_health <= maximum_health * 0.75 and not health.is_dead():
		_waves_pending = true
	get_node("/root/SoundManager").play_limited(&"boss_hurt", -17, 0.15)

func _on_died(_hit: CombatHit) -> void:
	_hurt_time = 0
	_set_phase(Phase.DEFEATED, 4.5)
	_pose()
	_drop_defeated_part($SwipeHand/Sprite, 0.15, -22.0, false)
	_drop_defeated_part($ClawHand/Sprite, 0.25, 26.0, false)
	_drop_defeated_part($LowerArm, 0.36, -28.0, false)
	_drop_defeated_part($ClawArm, 0.46, 18.0, false)
	_drop_defeated_part($UpperArm, 0.56, -14.0, false)
	_drop_defeated_part($Body, 0.72, -30.0, false)
	_drop_defeated_part($Head, 1.0, 24.0, true)
	defeated.emit()


func _drop_defeated_part(part: Sprite2D, delay: float, drift: float, heavy: bool) -> void:
	# Use the opaque pixels so the transparent canvas does not stop above the floor.
	var pixels := part.texture.get_image().get_used_rect()
	var bounds := part.get_rect()
	if part.region_enabled:
		pixels = pixels.intersection(Rect2i(part.region_rect))
		pixels.position -= Vector2i(part.region_rect.position)
	var local_bounds := Rect2(bounds.position + Vector2(pixels.position), Vector2(pixels.size))
	var world_bounds: Rect2 = part.global_transform * local_bounds
	var impact_x := to_local(world_bounds.get_center()).x + drift
	var floor_point := to_global(Vector2(impact_x, _sweep_floor_at(impact_x)))
	var drop := maxf(0.0, floor_point.y - world_bounds.end.y)
	var landing := part.global_position + Vector2(drift, drop)
	var fall := create_tween()
	fall.tween_interval(delay)
	fall.tween_property(part, "global_position", landing, clampf(sqrt(drop / 440.0), 0.22, 1.0)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if heavy:
		fall.tween_callback(func(): ground_impact.emit(floor_point, true))
		var start_rotation := part.rotation
		var center := local_bounds.get_center()
		var center_x := (part.global_transform * center).x + drift
		var image := part.texture.get_image()
		var contact_points := PackedVector2Array()
		for x in range(pixels.position.x, pixels.end.x):
			for y in range(pixels.end.y - 1, pixels.position.y - 1, -1):
				if image.get_pixel(x, y).a > 0.5:
					contact_points.append(bounds.position + Vector2(x + 0.5, y + 1))
					break
		fall.tween_method(func(progress: float):
			part.rotation = start_rotation + deg_to_rad(28.0) * progress
			var transform := part.global_transform
			var horizontal_shift := center_x + 14.0 * progress - (transform * center).x
			transform.origin.x += horizontal_shift
			var vertical_shift := INF
			for point in contact_points:
				var world_point := transform * point
				var floor_y_at_point := to_global(Vector2(0, _sweep_floor_at(to_local(world_point).x))).y
				vertical_shift = minf(vertical_shift, floor_y_at_point - world_point.y)
			part.global_position += Vector2(horizontal_shift, vertical_shift),
			0.0, 1.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func set_target(actor: Player) -> void:
	target = actor
	if not target.health.damage_received.is_connected(_on_target_damaged):
		target.health.damage_received.connect(_on_target_damaged)
	if not target.damage.attack_parried.is_connected(_on_target_parried):
		target.damage.attack_parried.connect(_on_target_parried)

func _on_target_damaged(hit: CombatHit, _amount: int) -> void:
	if hit.source == self:
		_consume_contact(hit.attack_area)

func _on_target_parried(hit: CombatHit, projectile: bool) -> void:
	if hit.source != self:
		return
	if projectile:
		if is_last_toll() and is_instance_valid(hit.attack_area) and hit.attack_area.has_meta(&"last_toll"):
			if not _toll_cancel_queued:
				_toll_cancel_queued = true
				_finish_last_toll.call_deferred(true)
			return
		if phase in [Phase.SWIPE_RECOVER, Phase.SLAM_RECOVER]:
			extend_recovery_from_web()
		else:
			_reflection_earned = true
	else:
		_consume_contact(hit.attack_area)

func _consume_contact(area: Area2D) -> void:
	if area == left_attack:
		_left_contact_used = true
		left_attack.active = false
	elif area == right_attack:
		_right_contact_used = true
		right_attack.active = false
