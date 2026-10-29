class_name Player
extends CharacterBody2D
## Movement uses one collision update per physics tick. Input names match Project Settings > Input Map exactly.
## The root is at the feet; the fixed 30x36 body is centered at (0, -18).

@export_group("Horizontal Movement")
@export_range(0.0, 1000.0, 1.0) var run_speed: float = 170.0
@export_range(0.0, 5000.0, 10.0) var ground_acceleration: float = 1700.0
@export_range(0.0, 5000.0, 10.0) var ground_friction: float = 1500.0
@export_range(0.0, 5000.0, 10.0) var air_acceleration: float = 900.0

@export_group("Collision Assistance")
## Vertical corner adjustment when horizontal travel is blocked. Zero disables it.
@export_range(0, 8, 1) var edge_correction_pixels: int = 6
## Time after impact to clear the wall and recover some horizontal momentum.
@export_range(0, 60) var wall_momentum_frames: int = 12
@export_range(0.0, 1.0, 0.05) var wall_momentum_retention: float = 0.75

@export_group("Jumping")
@export_range(-1000.0, -1.0, 1.0) var jump_velocity: float = -450.0
@export_range(0.0, 5.0, 0.05) var gravity_multiplier: float = 1.0
@export_range(0.0, 1.0, 0.05) var jump_release_multiplier: float = 0.6
## One horizontal impulse at takeoff, added to the momentum saved during charge.
@export_range(0.0, 300.0, 5.0) var jump_horizontal_boost: float = 30.0

## Fixed anticipation delay, not a strength charge. Zero makes takeoff immediate.
@export_range(0, 15) var jump_charge_frames: int = 6
@export_range(0, 60) var coyote_frames: int = 6
@export_range(0, 60) var jump_buffer_frames: int = 6

@export_group("Charged Dash")
@export_range(0, 120) var dash_charge_frames: int = 16
@export_range(1, 120) var dash_duration_frames: int = 13
@export_range(0, 120) var dash_recovery_frames: int = 8
## Independent of recovery/landing: every dash ending blocks another charge.
@export_range(0, 120) var dash_cooldown_frames: int = 12
## Existing speed/duration are the fully charged maximums.
@export_range(0.0, 2000.0, 10.0) var dash_speed: float = 500.0
@export_range(0.0, 2000.0, 10.0) var dash_min_speed: float = 380.0
@export_range(1, 120) var dash_min_duration_frames: int = 4
@export_range(0.0, 5000.0, 10.0) var dash_recovery_deceleration: float = 1800.0

enum MovementState { NORMAL, DASH_CHARGING, DASHING, RECOVERY }
signal movement_state_changed(state: MovementState)
signal jump_charge_changed(charging: bool)

var movement_state: MovementState = MovementState.NORMAL
var coyote_frames_remaining: int = 0
var jump_buffer_frames_remaining: int = 0
var jump_charge_frames_remaining: int = 0
var wall_momentum_frames_remaining: int = 0
var _wall_saved_speed: float = 0.0
var _wall_contact_direction: float = 0.0
var dash_phase_frames_remaining: int = 0
var dash_cooldown_frames_remaining: int = 0
var _dash_cooldown_started_this_tick: bool = false
var dash_available: bool = true
var dash_direction: int = 1
var dash_charge_frames_elapsed: int = 0
var dash_charge_ratio: float = 0.0
var active_dash_speed: float = 0.0
var active_dash_duration_frames: int = 0
var _dash_charge_limit_frames: int = 0
## 1 faces right; -1 faces left. Physics/collider scale never changes.
var facing_direction: int = 1
var _move_direction: float = 0.0
var _ground_jump_available: bool = false
var _jump_started_this_tick: bool = false
var _jump_cut_armed: bool = false
var _jump_pending: bool = false
var _jump_horizontal_speed: float = 0.0
var _jump_released_during_charge: bool = false
var _immediate_jump_press: bool = false
var _floor_history_valid: bool = false
var _ignore_jump_until_release: bool = false
var _ignore_dash_until_release: bool = false

@onready var visuals: Node2D = $Visuals
@onready var attack_pivot: Node2D = $AttackPivot


func _physics_process(delta: float) -> void:
	_dash_cooldown_started_this_tick = false
	var floor_before: bool = is_on_floor() and _floor_history_valid
	var had_coyote: bool = coyote_frames_remaining > 0
	var had_wall_momentum: bool = wall_momentum_frames_remaining > 0
	if had_wall_momentum and Input.get_axis("Move Left", "Move Right") * _wall_saved_speed < 0.0:
		clear_wall_momentum() # Turning away also cancels memory during charge.
	_jump_started_this_tick = false
	update_jump_charge()
	update_jump_timers()
	try_start_dash()
	var state_for_motion: MovementState = movement_state
	match state_for_motion:
		MovementState.NORMAL:
			# Commit before steering/friction, preserving the incoming speed.
			try_jump()
			if not is_jump_movement_paused() and not _jump_started_this_tick:
				handle_horizontal_movement(delta)
				apply_gravity(delta)
			handle_jump()
			if not is_jump_movement_paused():
				update_facing_direction()
		MovementState.DASH_CHARGING:
			update_dash_charge()
		MovementState.DASHING:
			update_dashing()
			try_dash_jump(floor_before)
		MovementState.RECOVERY:
			update_dash_recovery(delta)
	var vertical_speed_before: float = velocity.y
	if state_for_motion != MovementState.DASH_CHARGING and not is_jump_movement_paused():
		apply_edge_correction(delta)
		try_restore_wall_momentum(delta)
	var horizontal_speed_before: float = velocity.x
	move_and_slide()
	var new_wall_impact: bool = remember_wall_impact(horizontal_speed_before)
	if had_wall_momentum and not new_wall_impact:
		wall_momentum_frames_remaining = maxi(0, wall_momentum_frames_remaining - 1)
		if wall_momentum_frames_remaining == 0:
			_wall_saved_speed = 0.0
	update_floor_transitions(floor_before, vertical_speed_before, state_for_motion)
	if state_for_motion == MovementState.DASHING and not _jump_started_this_tick:
		try_dash_jump(is_on_floor()) # Also permit a press on this tick's landing.
	# A landing can consume the buffer now; upward movement starts next tick.
	# There is no second move_and_slide(), and no stale floor jump next tick.
	if state_for_motion == MovementState.NORMAL or state_for_motion == MovementState.RECOVERY:
		if is_on_floor() and not _jump_started_this_tick:
			try_jump()
	if had_coyote:
		coyote_frames_remaining = maxi(0, coyote_frames_remaining - 1)
	jump_buffer_frames_remaining = maxi(0, jump_buffer_frames_remaining - 1)
	advance_dash_phase(state_for_motion)
	# The ending tick is not charged against the new cooldown. Its next N
	# physics ticks all reject Dash, even while a jump wind-up freezes movement.
	if not _dash_cooldown_started_this_tick:
		dash_cooldown_frames_remaining = maxi(0, dash_cooldown_frames_remaining - 1)
	_floor_history_valid = true


func handle_horizontal_movement(delta: float) -> void:
	_move_direction = Input.get_axis("Move Left", "Move Right")
	var target_speed: float = _move_direction * run_speed
	var acceleration: float = air_acceleration
	if is_on_floor():
		acceleration = ground_acceleration if _move_direction != 0.0 else ground_friction
	# Air acceleration also slows horizontal drift when input is released.
	# Only X changes here; jumping and gravity own Y.
	velocity.x = move_toward(velocity.x, target_speed, acceleration * delta)


func apply_edge_correction(delta: float) -> void:
	if edge_correction_pixels <= 0 or is_zero_approx(velocity.x):
		return
	var horizontal_motion := Vector2(velocity.x * delta, 0.0)
	# Probe first: a full-height wall must still stop the player and the dash.
	if not horizontal_path_hits_wall(global_transform, horizontal_motion):
		return
	for distance in range(1, edge_correction_pixels + 1):
		for direction in [-1, 1]:
			var offset := Vector2(0.0, float(distance * direction))
			# Sweep the adjustment itself, so we cannot skip through a thin ceiling
			# or floor. Charging never reaches this function.
			if test_move(global_transform, offset, null, safe_margin):
				continue
			var adjusted := global_transform.translated(offset)
			if not edge_position_is_clear(adjusted):
				continue
			if test_move(adjusted, horizontal_motion, null, safe_margin, true):
				continue
			# Gravity/jumping may add vertical motion this tick. Allow normal floor
			# contacts, but do not assist a path that would still hit the wall.
			if horizontal_path_hits_wall(adjusted, velocity * delta):
				continue
			global_position += offset
			return # Smallest adjustment; never resize shapes or add jump velocity.


func horizontal_path_hits_wall(from: Transform2D, motion: Vector2) -> bool:
	var contact := KinematicCollision2D.new()
	if not test_move(from, motion, contact, safe_margin, false):
		return false
	var normal := contact.get_normal()
	return absf(normal.x) > 0.9 and normal.x * motion.x < 0.0


func try_restore_wall_momentum(delta: float) -> void:
	if wall_momentum_frames <= 0 or wall_momentum_frames_remaining <= 0:
		clear_wall_momentum()
		return
	var direction: float = signf(_wall_saved_speed)
	var input_direction: float = Input.get_axis("Move Left", "Move Right")
	if input_direction * direction < 0.0 or velocity.x * direction < 0.0:
		clear_wall_momentum() # Turning away must not fling the player back.
		return
	var retained_speed: float = _wall_saved_speed * wall_momentum_retention
	var motion := Vector2(retained_speed * delta, 0.0)
	if horizontal_path_hits_wall(global_transform, motion):
		return # Still blocked: let normal collision stop the body.
	if absf(retained_speed) > absf(velocity.x):
		velocity.x = retained_speed
	clear_wall_momentum() # One restoration per impact; never add speed repeatedly.


func remember_wall_impact(incoming_speed: float) -> bool:
	var direction: float = 0.0
	if is_on_wall() and absf(get_wall_normal().x) > 0.9:
		direction = -signf(get_wall_normal().x)
	if direction != 0.0:
		var new_impact: bool = direction != _wall_contact_direction
		_wall_contact_direction = direction
		if new_impact and incoming_speed * direction > 0.0 and wall_momentum_frames > 0:
			_wall_saved_speed = incoming_speed
			wall_momentum_frames_remaining = wall_momentum_frames
			return true
	elif _wall_contact_direction != 0.0:
		# A stationary jump charge may clear is_on_wall() without leaving the wall.
		# Keep its contact latched until a small probe actually finds free space.
		var probe := Vector2(_wall_contact_direction, 0.0)
		if not horizontal_path_hits_wall(global_transform, probe):
			_wall_contact_direction = 0.0
	return false


func clear_wall_momentum() -> void:
	_wall_saved_speed = 0.0
	wall_momentum_frames_remaining = 0


func edge_position_is_clear(body_transform: Transform2D) -> bool:
	var collider: CollisionShape2D = $CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collider.shape
	query.transform = body_transform * collider.transform
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func apply_gravity(delta: float) -> void:
	if not is_on_floor() and not _jump_started_this_tick:
		# Uses the project's gravity settings (and any future gravity areas).
		velocity += get_gravity() * gravity_multiplier * delta


func update_jump_timers() -> void:
	_immediate_jump_press = false
	if not Input.is_action_pressed("Jump"):
		_ignore_jump_until_release = false
	if not Input.is_action_pressed("Action"):
		_ignore_dash_until_release = false
	if movement_state == MovementState.DASH_CHARGING or movement_state == MovementState.DASHING:
		clear_jump_buffer()
		return
	if _jump_pending:
		return
	if Input.is_action_just_pressed("Jump") and not _ignore_jump_until_release:
		clear_jump_buffer()
		_immediate_jump_press = can_jump()
		jump_buffer_frames_remaining = maxi(1, jump_buffer_frames) if _immediate_jump_press else jump_buffer_frames


func clear_jump_buffer() -> void:
	jump_buffer_frames_remaining = 0


func can_jump() -> bool:
	return not _jump_pending and ((_ground_jump_available and is_on_floor() and velocity.y >= 0.0) or coyote_frames_remaining > 0)


func try_jump() -> void:
	if jump_buffer_frames_remaining <= 0 or not can_jump():
		return
	# Reserve this legal ground/coyote jump now, so the delay cannot expire its
	# permission or let repeated presses create additional jumps.
	_ground_jump_available = false
	coyote_frames_remaining = 0
	jump_charge_frames_remaining = maxi(0, jump_charge_frames)
	_jump_released_during_charge = not Input.is_action_pressed("Jump")
	clear_jump_buffer()
	_jump_horizontal_speed = velocity.x
	_jump_pending = true
	_jump_cut_armed = false
	if jump_charge_frames_remaining == 0:
		launch_jump()
	else:
		velocity = Vector2.ZERO # Pause motion and preserve the saved momentum.
		jump_charge_changed.emit(true)


func is_jump_charging() -> bool:
	return _jump_pending


func is_jump_movement_paused() -> bool:
	return _jump_pending


func update_jump_charge() -> void:
	if not _jump_pending:
		return
	velocity = Vector2.ZERO
	# Remember short taps even if the button was released before takeoff.
	if not Input.is_action_pressed("Jump") or Input.is_action_just_released("Jump"):
		_jump_released_during_charge = true
	jump_charge_frames_remaining = maxi(0, jump_charge_frames_remaining - 1)
	if jump_charge_frames_remaining == 0:
		launch_jump()


func launch_jump() -> void:
	_jump_pending = false
	jump_charge_frames_remaining = 0
	var jump_input: float = Input.get_axis("Move Left", "Move Right")
	var boost: float = 0.0
	# Charge freezes velocity, so compare held input with the saved momentum.
	# Check at takeoff: releasing or reversing input during charge removes boost.
	if not is_zero_approx(_jump_horizontal_speed) and jump_input * _jump_horizontal_speed > 0.0:
		boost = signf(_jump_horizontal_speed) * jump_horizontal_boost
	velocity = Vector2(_jump_horizontal_speed + boost, jump_velocity)
	_jump_horizontal_speed = 0.0
	if _jump_released_during_charge:
		velocity.y *= jump_release_multiplier
	_jump_cut_armed = not _jump_released_during_charge
	_jump_released_during_charge = false
	_ground_jump_available = false
	_jump_started_this_tick = true
	jump_charge_changed.emit(false)


func handle_jump() -> void:
	try_jump()
	if _jump_cut_armed and Input.is_action_just_released("Jump") and not Input.is_action_pressed("Jump") and velocity.y < 0.0:
		velocity.y *= jump_release_multiplier
		_jump_cut_armed = false
	if velocity.y >= 0.0:
		_jump_cut_armed = false


func update_floor_transitions(floor_before: bool, vertical_speed: float, state_for_motion: MovementState) -> void:
	if is_on_floor() and not _jump_started_this_tick and vertical_speed >= 0.0:
		if not _jump_pending:
			_ground_jump_available = true
		coyote_frames_remaining = 0
		if not floor_before:
			dash_available = true # Actual collision landing, never coyote/buffer input.
	elif floor_before and not is_on_floor():
		# Only ordinary horizontal departure seeds grace. Jumps, dash phases,
		# and external nonzero vertical launches do not grant it.
		if state_for_motion == MovementState.NORMAL and not _jump_started_this_tick and is_zero_approx(vertical_speed) and _ground_jump_available:
			coyote_frames_remaining = coyote_frames
		_ground_jump_available = false


func try_start_dash() -> void:
	if movement_state != MovementState.NORMAL or dash_cooldown_frames_remaining > 0 or _ignore_dash_until_release or not Input.is_action_just_pressed("Action"):
		return
	if not dash_available and not (is_on_floor() and velocity.y >= 0.0):
		return
	clear_wall_momentum()
	dash_available = false
	dash_direction = facing_direction
	dash_charge_frames_elapsed = 0
	dash_charge_ratio = 0.0
	active_dash_speed = 0.0
	active_dash_duration_frames = 0
	_dash_charge_limit_frames = maxi(0, dash_charge_frames)
	cancel_jump_grace()
	velocity = Vector2.ZERO
	if _dash_charge_limit_frames > 0:
		set_movement_state(MovementState.DASH_CHARGING, _dash_charge_limit_frames)
	else:
		begin_dash()


func cancel_jump_grace() -> void:
	## Future external launches should call this before assigning launch velocity.
	var was_charging: bool = _jump_pending
	_jump_pending = false
	_jump_horizontal_speed = 0.0
	jump_charge_frames_remaining = 0
	_jump_released_during_charge = false
	coyote_frames_remaining = 0
	clear_jump_buffer()
	_ground_jump_available = false
	_jump_cut_armed = false
	_immediate_jump_press = false
	if was_charging:
		jump_charge_changed.emit(false)


func update_dash_charge() -> void:
	# Do not replay saved vertical speed afterward. Collision/snap still owns
	# contact resolution, but input and gravity cannot move an airborne charge.
	velocity = Vector2.ZERO
	var direction_input: float = Input.get_axis("Move Left", "Move Right")
	if not is_zero_approx(direction_input):
		dash_direction = 1 if direction_input > 0.0 else -1
		_move_direction = direction_input
		update_facing_direction()
	# Releasing direction keeps the last choice. Redirection never resets charge.
	if Input.is_action_pressed("Action"):
		dash_charge_frames_elapsed = mini(dash_charge_frames_elapsed + 1, _dash_charge_limit_frames)
		dash_charge_ratio = float(dash_charge_frames_elapsed) / maxi(1, _dash_charge_limit_frames)


func begin_dash() -> void:
	# Snapshot strength once: letting go cannot alter an already launched dash.
	dash_charge_ratio = clampf(float(dash_charge_frames_elapsed) / _dash_charge_limit_frames, 0.0, 1.0) if _dash_charge_limit_frames > 0 else 1.0
	var full_speed: float = maxf(0.0, dash_speed)
	var full_duration: int = maxi(1, dash_duration_frames)
	active_dash_speed = lerpf(clampf(dash_min_speed, 0.0, full_speed), full_speed, dash_charge_ratio)
	active_dash_duration_frames = roundi(lerpf(float(clampi(dash_min_duration_frames, 1, full_duration)), float(full_duration), dash_charge_ratio))
	set_movement_state(MovementState.DASHING, active_dash_duration_frames)
	velocity = Vector2(dash_direction * active_dash_speed, 0.0)


func update_dashing() -> void:
	velocity = Vector2(dash_direction * active_dash_speed, 0.0)


func try_dash_jump(ground_contact_valid: bool) -> void:
	if movement_state != MovementState.DASHING or not ground_contact_valid or not is_on_floor():
		return
	if _ignore_jump_until_release or not Input.is_action_just_pressed("Jump"):
		return
	# A real ground contact allows a new jump/airtime. Keep the dash's horizontal
	# momentum, but immediately release its movement lock and phase timer.
	start_dash_cooldown()
	set_movement_state(MovementState.NORMAL, 0)
	dash_available = true
	_ground_jump_available = true
	_immediate_jump_press = true
	jump_buffer_frames_remaining = 1
	handle_jump()


func start_dash_cooldown() -> void:
	dash_cooldown_frames_remaining = maxi(dash_cooldown_frames_remaining, maxi(0, dash_cooldown_frames))
	_dash_cooldown_started_this_tick = true


func finish_dash() -> void:
	start_dash_cooldown()
	# Preserve horizontal momentum. Recovery/normal friction slow it naturally;
	# wall collision has already removed any blocked horizontal velocity.
	velocity.y = 0.0
	set_movement_state(MovementState.RECOVERY if dash_recovery_frames > 0 else MovementState.NORMAL, dash_recovery_frames)
	if dash_recovery_frames <= 0 and is_on_floor():
		dash_available = true


func update_dash_recovery(delta: float) -> void:
	try_jump() # Capture momentum before recovery braking can reduce it.
	if not is_jump_movement_paused() and not _jump_started_this_tick:
		velocity.x = move_toward(velocity.x, 0.0, dash_recovery_deceleration * delta)
		apply_gravity(delta)
	handle_jump() # Ground/buffer jumps remain available; steering/dash wait.


func advance_dash_phase(state_for_motion: MovementState) -> void:
	if movement_state != state_for_motion:
		return # Ground jump canceled the dash; do not finish/zero its jump velocity.
	if state_for_motion == MovementState.NORMAL:
		return
	if state_for_motion == MovementState.RECOVERY and (is_jump_movement_paused() or _jump_started_this_tick):
		return # Pause recovery braking/timing through anticipation and takeoff.
	if state_for_motion == MovementState.DASH_CHARGING:
		dash_phase_frames_remaining = maxi(0, _dash_charge_limit_frames - dash_charge_frames_elapsed)
		if not Input.is_action_pressed("Action") or dash_phase_frames_remaining == 0:
			begin_dash() # Release early, or launch automatically at full charge.
		return
	if state_for_motion == MovementState.DASHING and is_on_wall():
		finish_dash()
		return
	# The input tick counts as the first charge tick. New phases start their
	# movement on the NEXT tick, so every configured phase gets exactly N ticks.
	dash_phase_frames_remaining = maxi(0, dash_phase_frames_remaining - 1)
	if dash_phase_frames_remaining > 0:
		return
	match state_for_motion:
		MovementState.DASHING:
			finish_dash()
		MovementState.RECOVERY:
			if is_on_floor() and velocity.y >= 0.0:
				dash_available = true # Completed recovery with actual floor support.
			set_movement_state(MovementState.NORMAL, 0)


func set_movement_state(next_state: MovementState, frames: int) -> void:
	dash_phase_frames_remaining = frames
	if movement_state != next_state:
		movement_state = next_state
		movement_state_changed.emit(movement_state)


func reset_movement() -> void:
	## Respawn/teleport callers reset temporary state, not just velocity.
	dash_cooldown_frames_remaining = 0
	_dash_cooldown_started_this_tick = false
	clear_wall_momentum()
	_wall_contact_direction = 0.0
	velocity = Vector2.ZERO
	cancel_jump_grace()
	dash_available = true
	dash_direction = facing_direction
	dash_charge_frames_elapsed = 0
	dash_charge_ratio = 0.0
	active_dash_speed = 0.0
	active_dash_duration_frames = 0
	_dash_charge_limit_frames = 0
	_move_direction = 0.0
	_jump_started_this_tick = false
	_floor_history_valid = false
	_ignore_jump_until_release = Input.is_action_pressed("Jump")
	_ignore_dash_until_release = Input.is_action_pressed("Action")
	set_movement_state(MovementState.NORMAL, 0)


func update_facing_direction() -> void:
	if _move_direction == 0.0:
		return
	facing_direction = 1 if _move_direction > 0.0 else -1
	visuals.scale.x = absf(visuals.scale.x) * facing_direction
	attack_pivot.scale.x = absf(attack_pivot.scale.x) * facing_direction
