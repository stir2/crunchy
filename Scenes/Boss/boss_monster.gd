extends Node2D
## Arm encounter. Attack clocks advance only in physics; pause freezes the whole rig.
signal ground_impact(point: Vector2, heavy: bool)
signal defeated
signal defeat_finished
signal waves_requested
signal floor_break_requested
signal volley_started
signal volley_burst(index: int)
signal attack_tell(strike: bool, duration: float)
signal arm_impact(strike: bool, point: Vector2)
signal slab_broken

enum Phase { REST, SWIPE_WINDUP, SWIPE_DROP, SWIPE_DRAG, SWIPE_RECOVER, SWIPE_RETRACT,
	SLAM_TRACK, SLAM_LOCK, SLAM_STRIKE, SLAM_IMPACT, SLAM_RECOVER, SLAM_RETRACT, WITHDRAW, WAVES, RETURN, BREAK, BREAK_RETRACT, VOLLEY, STOPPED, DEFEATED }

@export var target: Player
@export var maximum_health: int = 180
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
var _death_impact_played := false
var _death_origin := Vector2.ZERO
var lower_arena := false
var _breaking_floor := false
var _volley_next := true
var _slab_available := true
var _slab_armed := false
var _reflection_extended := false
var _reflection_earned := false
var _last_sweep := false
var _repeated := 0
const ATTACK_ART = preload("res://Scenes/Boss/boss_attack_art.gd")
const SWIPE_DROP_TIME := 0.26
const SWIPE_HANDOFF := 0.11
const SLAM_X := 486.0
const CLAW_LIFT := 183.0
const SWIPE_WRIST := Vector2(4, -71)
const SWEEP_ART_PIVOT := Vector2(246, 100)
const SWEEP_ART_PLANT := Vector2(105, 319)
const SWEEP_ART_WRIST := Vector2(151, 239)
const SWEEP_ART_ELBOW := Vector2(177, 166)
const BREAK_RETRACT_TIME := 0.72
# Lowest painted blade pixel in each held strike drawing, from contact to rest.
const STRIKE_ART_PIVOT := Vector2(400, 90)
const STRIKE_TIPS := {
	41: Vector2(493, 351), 43: Vector2(495, 344), 59: Vector2(494, 336), 63: Vector2(498, 338),
	66: Vector2(504, 333), 69: Vector2(511, 284), 71: Vector2(553, 272), 73: Vector2(552, 270),
}
const SLAM_LOCK_TIME := 0.43
const SLAM_FALL_TIME := 0.20
const COMBO_IMPACT := 0.64
const REVERSE_IMPACT := -0.10
const IMPACT_WINDOW := 0.20
const BURST_TIMES := [0.85, 1.24, 1.63]
const LEFT_REST := Vector2(96, 265)
const RIGHT_REST := Vector2(527, 265)

var _art: Node2D
var _layer_alpha := Vector4.ZERO
var _art_carry := Vector4.ZERO
var _last_art_strike := false
var _sweep_frame := 84.0
var _strike_frame := 84.0
var _sweep_frame_start := 84.0
var _strike_frame_start := 84.0
var _strike_tip := Vector2(494, 304)

@onready var health: HealthComponent = $Health
@onready var left: Node2D = $SwipeHand
@onready var right: Node2D = $ClawHand
@onready var left_hurt: CombatDamageable = $SwipeHand/Hurtbox
@onready var right_hurt: CombatDamageable = $ClawHand/Hurtbox
@onready var left_attack: CombatDamageArea = $SwipeHand/Attack
@onready var right_attack: CombatDamageArea = $ClawHand/Attack

func _ready() -> void:
	add_to_group("enemies")
	health.base_max_health = maximum_health
	health.reset_health()
	health.damage_received.connect(_on_damaged)
	health.died.connect(_on_died)
	left_attack.damage = attack_damage
	right_attack.damage = attack_damage
	right_attack.attack_direction = Vector2.DOWN
	_art = ATTACK_ART.new()
	add_child(_art)
	_layer_alpha = Vector4.ONE
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
		Phase.DEFEATED:
			# Regain a connected pose, then let the entire actor fall as one body.
			var release := smoothstep(0.0, 0.55, elapsed)
			left.position = _left_start.lerp(LEFT_REST, release)
			right.position = _right_start.lerp(RIGHT_REST, release)
			var fall := clampf((elapsed - 0.55) / 1.2, 0, 1)
			position = _death_origin + Vector2(0, 94 * fall * fall)
			if fall >= 1 and not _death_impact_played:
				_death_impact_played = true
				ground_impact.emit(_death_origin + Vector2(320, floor_y), true)
	if phase != Phase.VOLLEY:
		_body_shift = _body_start.lerp(Vector2.ZERO, smooth) + lean
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
			elif lower_arena and _volley_next:
				_volley_next = false
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
		Phase.VOLLEY: _start_arm_attack()
		Phase.SLAM_RECOVER: _set_phase(Phase.SLAM_RETRACT, 0.55)
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
	_art_carry = _layer_alpha
	_sweep_frame_start = _sweep_frame
	_strike_frame_start = _strike_frame
	if next == Phase.SWIPE_WINDUP:
		_right_contact_used = false
		_combo_landed = false
		_combo_wedged = false
	if next == Phase.SWIPE_DRAG:
		_left_contact_used = false
		left_attack.attack_direction = Vector2(signf(_sweep_to - _sweep_from), 0)
		# The authored plant already has a dust burst baked into its first frames.
		_dust_clock = SWIPE_HANDOFF if _sweep_to > _sweep_from else 0.0
	if next == Phase.SLAM_IMPACT:
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
	right_attack.active = next == Phase.SLAM_IMPACT
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
	_combo = lower_arena
	var sweep := lower_arena or (target.position.x < 320 if is_instance_valid(target) else not _last_sweep)
	if not lower_arena and _repeated >= 2:
		sweep = not _last_sweep
	_repeated = _repeated + 1 if sweep == _last_sweep else 1
	_last_sweep = sweep
	_sweep_from = 578.0 if _combo and _reverse_sweep else 52.0
	_sweep_to = 630.0 - _sweep_from
	if _combo:
		_reverse_sweep = not _reverse_sweep
	_slab_armed = false
	_volley_next = true
	_set_phase(Phase.SWIPE_WINDUP if sweep else Phase.SLAM_TRACK, 0.82 if lower_arena else 0.9)

func _idle_left() -> Vector2:
	return LEFT_REST + Vector2(0, sin(_age * 1.4) * 3)

func _idle_right() -> Vector2:
	return RIGHT_REST + Vector2(0, sin(_age * 1.2 + 1) * 3)

func _sweep_floor_at(x: float) -> float:
	return sweep_floor.call(x) if lower_arena and sweep_floor.is_valid() else floor_y

func _sweep_point(x: float) -> Vector2:
	if not lower_arena:
		return Vector2(x, floor_y)
	# Blend between tile centers so the wrist follows each lip without snapping.
	var left_center := floorf((x - 8.0) / 16.0) * 16.0 + 8.0
	var t := smoothstep(left_center, left_center + 16.0, x)
	return Vector2(x, lerpf(_sweep_floor_at(left_center), _sweep_floor_at(left_center + 16.0), t))

func _claw_contact() -> Vector2:
	return Vector2(SLAM_X, _sweep_floor_at(SLAM_X))

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
		_slab_armed = _slab_available and is_instance_valid(target) and absf(target.position.x - SLAM_X) <= 40.0
		arm_impact.emit(true, right.global_position)
	right_attack.active = _combo_landed and clock < end and not _right_contact_used
	if clock >= end and _slab_armed and _slab_available:
		_combo_wedged = true
		_slab_available = false
		slab_broken.emit()

func _pose_volley() -> void:
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

func volley_origin() -> Vector2:
	return to_global(Vector2(320, 135) + _body_shift)

func finish_floor_break() -> void:
	lower_arena = true
	var sweep_shape := $SwipeHand/Attack/Shape as CollisionShape2D
	sweep_shape.shape = sweep_shape.shape.duplicate()
	(sweep_shape.shape as RectangleShape2D).size = Vector2(54, 32)
	left_attack.position.y = -18.0
	_breaking_floor = false
	_set_phase(Phase.BREAK_RETRACT, BREAK_RETRACT_TIME)

func resume_fight() -> void:
	_breaking_floor = false
	_set_phase(Phase.REST, 1.0)

func stop_attacks() -> void:
	if phase != Phase.DEFEATED:
		_set_phase(Phase.STOPPED, 1.0)

func _pose() -> void:
	$Body.position = _body_shift + Vector2(0, sin(_age * 1.1) * 2)
	$Head.position = _body_shift + Vector2(sin(_age * 0.7) * 2, sin(_age * 1.1 - 0.3) * 3)
	$Head.rotation = _body_shift.x * 0.001
	var shoulder: Vector2 = Vector2(252, 104) + $Body.position
	var hand_sprite: Sprite2D = $SwipeHand/Sprite
	var wrist_offset := SWIPE_WRIST
	var hand_scale := 1.0
	var hand_angle := _hand_angle
	var carry := 0.0
	var scale_from_art := Vector2.ONE
	if phase == Phase.SWIPE_DRAG and _sweep_to > _sweep_from:
		# Start the moving rig from the painted wrist, then relax into its drag pose.
		carry = 1.0 - smoothstep(0.0, 0.23, elapsed)
		scale_from_art = _sweep_art_scale(SWEEP_ART_PLANT)
		var painted_wrist := (SWEEP_ART_WRIST - SWEEP_ART_PLANT) * scale_from_art
		wrist_offset = SWIPE_WRIST.lerp(painted_wrist, carry)
		hand_scale = wrist_offset.length() / SWIPE_WRIST.length()
		hand_angle += SWIPE_WRIST.angle_to(wrist_offset)
	hand_sprite.scale = Vector2.ONE * hand_scale
	hand_sprite.rotation = hand_angle
	hand_sprite.position = wrist_offset - (SWIPE_WRIST * hand_scale).rotated(hand_angle)
	var wrist := left.position + wrist_offset
	var span: Vector2 = wrist - shoulder
	var elbow: Vector2 = shoulder + span * 0.5 - span.normalized().orthogonal() * 52
	if carry > 0.0:
		var painted_elbow := left.position + (SWEEP_ART_ELBOW - SWEEP_ART_PLANT) * scale_from_art
		elbow = elbow.lerp(painted_elbow, carry)
	_fit_bone($UpperArm, Vector2(238, 104), Vector2(156, 110), shoulder, elbow)
	_fit_bone($LowerArm, Vector2(135, 105), Vector2(106, 185), elbow, wrist)
	_fit_bone($ClawArm, Vector2(405, 88), Vector2(510, 175), Vector2(386, 104) + $Body.position, right.position + Vector2(-14, -75))
	var flash := Color(1.5, 0.65, 0.65) if _hurt_time > 0 else Color.WHITE
	$Head.modulate = flash
	left.modulate = flash
	right.modulate = flash
	_pose_authored(flash)

func _pose_authored(flash: Color) -> void:
	var t := clampf(elapsed / duration, 0.0, 1.0)
	var alpha := Vector4.ONE
	var strike := phase in [Phase.SLAM_TRACK, Phase.SLAM_LOCK, Phase.SLAM_STRIKE,
		Phase.SLAM_IMPACT, Phase.SLAM_RECOVER, Phase.SLAM_RETRACT, Phase.BREAK, Phase.BREAK_RETRACT]
	var sweep := phase in [Phase.SWIPE_WINDUP, Phase.SWIPE_DROP, Phase.SWIPE_DRAG,
		Phase.SWIPE_RECOVER, Phase.SWIPE_RETRACT]
	var left_origin := _sweep_from < _sweep_to
	if strike:
		match phase:
			Phase.SLAM_TRACK:
				_strike_frame = _clip_frame(0, 31, t)
				var enter := smoothstep(0.0, 0.18, elapsed)
				alpha.y = lerpf(_art_carry.y, 1.0, enter)
				alpha.z = lerpf(_art_carry.z, 1.0, enter)
			Phase.SLAM_LOCK: _strike_frame = _clip_frame(31, 40, t)
			Phase.SLAM_STRIKE: _strike_frame = 40
			Phase.SLAM_IMPACT: _strike_frame = _clip_frame(41, 43, t)
			Phase.SLAM_RECOVER: _strike_frame = _clip_frame(43, 68, t)
			Phase.SLAM_RETRACT, Phase.BREAK_RETRACT:
				_strike_frame = _clip_frame(43 if phase == Phase.BREAK_RETRACT else 68, 84, t)
			Phase.BREAK: _strike_frame = 43.0
		_strike_tip = _claw_tip()
	elif sweep:
		alpha = Vector4(1.0, 0.0, 1.0, 1.0)
		match phase:
			Phase.SWIPE_WINDUP:
				_sweep_frame = _clip_frame(0, 19, t)
				var enter := smoothstep(0.0, 0.20, elapsed)
				alpha.y = lerpf(_art_carry.y, 1.0 if left_origin else 0.0, enter)
				alpha.z = lerpf(_art_carry.z, 1.0, enter)
			Phase.SWIPE_DROP:
				_sweep_frame = _clip_frame(19, 24, t * t)
				alpha.y = 1.0 if left_origin else 0.0
			Phase.SWIPE_DRAG:
				_sweep_frame = _clip_frame(24, 52, t)
				alpha.y = 1.0 - smoothstep(0.0, SWIPE_HANDOFF, elapsed) if left_origin else 0.0
			Phase.SWIPE_RECOVER: _sweep_frame = _clip_frame(52, 68, t)
			Phase.SWIPE_RETRACT:
				_sweep_frame = _clip_frame(68, 84, t)
				# Once the moving hand is near rest, join JV's shared idle silhouette.
				alpha.y = smoothstep(77.5, 84.0, _sweep_frame)
		if _combo:
			var clock := elapsed - SWIPE_DROP_TIME if phase == Phase.SWIPE_DROP else elapsed
			match phase:
				Phase.SWIPE_WINDUP: _strike_frame = _clip_frame(0, 31, t)
				Phase.SWIPE_DROP, Phase.SWIPE_DRAG:
					var impact := _combo_impact_time()
					_strike_frame = 40 if clock < impact else _clip_frame(41, 43, (clock - impact) / IMPACT_WINDOW)
				Phase.SWIPE_RECOVER: _strike_frame = _clip_frame(43, 68, t)
				Phase.SWIPE_RETRACT: _strike_frame = _clip_frame(68, 84, t)
			_strike_tip = _claw_tip()
		_last_art_strike = false
	else:
		# Idle uses the final drawings of the attack that just finished. Only
		# independently moving arms switch to the rig for non-attack motion.
		var settle := smoothstep(0.0, 0.32, elapsed)
		_sweep_frame = lerpf(_sweep_frame_start, 84.0, settle)
		_strike_frame = lerpf(_strike_frame_start, 84.0, settle)
		var arm_blend := 1.0 - smoothstep(0.0, 0.23, elapsed)
		alpha.y = _art_carry.y * arm_blend
		alpha.z = _art_carry.z * arm_blend
		if phase == Phase.REST:
			var idle_blend := smoothstep(0.32, 0.72, elapsed)
			var completed := _strike_frame_start >= 84.0 if _last_art_strike else (
				_sweep_frame_start >= 84.0 and (not _combo or _strike_frame_start >= 84.0))
			alpha.y = 1.0 if completed else lerpf(alpha.y, 1.0, idle_blend)
			alpha.z = 1.0 if completed else lerpf(alpha.z, 1.0, idle_blend)
		_strike_tip = _claw_tip()
	if strike:
		_last_art_strike = true
	_art.modulate = flash
	var main_clip: StringName = &"Strike" if _last_art_strike else &"Sweep"
	var main_frame := _strike_frame if _last_art_strike else _sweep_frame
	_layer_alpha = alpha
	# Carry the small idle motion into the identical first and final drawings.
	var idle_motion := maxf(1.0 - smoothstep(0.0, 9.0, main_frame), smoothstep(76.0, 84.0, main_frame))
	var body_offset: Vector2 = $Body.position * idle_motion
	var head_offset: Vector2 = $Head.position * idle_motion
	var body_alpha: float = _art.paint(ATTACK_ART.Layer.BODY, main_clip, main_frame, alpha.x, Vector2.ONE, body_offset)
	var head_alpha: float = _art.paint(ATTACK_ART.Layer.HEAD, main_clip, main_frame, alpha.w, Vector2.ONE, head_offset)
	var left_scale := Vector2.ONE
	var left_offset := Vector2.ZERO
	if sweep and phase in [Phase.SWIPE_WINDUP, Phase.SWIPE_DROP, Phase.SWIPE_DRAG] and alpha.y > 0.0 and left_origin:
		# Pin the planted fingers to the sweep lane and stretch from the shoulder.
		var tip := Vector2(94, 262).lerp(SWEEP_ART_PLANT, smoothstep(19.0, 24.0, _sweep_frame))
		left_scale = _sweep_art_scale(tip)
		left_offset = SWEEP_ART_PIVOT * (Vector2.ONE - left_scale)
	elif main_frame >= 77.5:
		left_scale = _sweep_art_scale(Vector2(96, 265))
		left_offset = SWEEP_ART_PIVOT * (Vector2.ONE - left_scale)
	var left_alpha: float = _art.paint(ATTACK_ART.Layer.LEFT, main_clip, main_frame, alpha.y, left_scale, left_offset)
	var claw_clip: StringName = &"Strike" if _last_art_strike or _combo else &"Sweep"
	var claw_frame := _strike_frame if claw_clip == &"Strike" else _sweep_frame
	var claw_scale := Vector2.ONE
	var claw_offset := Vector2.ZERO
	if claw_clip == &"Strike" and roundi(claw_frame) >= 41:
		# Keep the blade tip attached to the same contact path through the lift.
		var tip: Vector2 = STRIKE_TIPS[41]
		var frame := roundi(claw_frame)
		for key: int in STRIKE_TIPS:
			if key > frame:
				break
			tip = STRIKE_TIPS[key]
		claw_scale = (_strike_tip - STRIKE_ART_PIVOT) / (tip - STRIKE_ART_PIVOT)
		claw_offset = STRIKE_ART_PIVOT * (Vector2.ONE - claw_scale)
	var claw_alpha: float = _art.paint(ATTACK_ART.Layer.RIGHT, claw_clip, claw_frame, alpha.z, claw_scale, claw_offset)
	$Body.self_modulate.a = 1.0 - body_alpha
	$Head.self_modulate.a = 1.0 - head_alpha
	for sprite: Sprite2D in [$UpperArm, $LowerArm, $SwipeHand/Sprite]:
		sprite.self_modulate.a = 1.0 - left_alpha
	for sprite: Sprite2D in [$ClawArm, $ClawHand/Sprite]:
		sprite.self_modulate.a = 1.0 - claw_alpha

func _claw_tip() -> Vector2:
	var release := smoothstep(SLAM_X, RIGHT_REST.x, right.position.x)
	return right.position + Vector2(lerpf(8.0, 25.0, release), 0.0)

func _sweep_art_scale(tip: Vector2) -> Vector2:
	return (left.position - SWEEP_ART_PIVOT) / (tip - SWEEP_ART_PIVOT)

func _clip_frame(first: int, last: int, progress: float) -> float:
	return lerpf(first, last, clampf(progress, 0.0, 1.0))

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
		duration += 1.0


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
		_consume_contact(hit.attack_area)

func _on_target_parried(hit: CombatHit, projectile: bool) -> void:
	if hit.source != self:
		return
	if projectile:
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
