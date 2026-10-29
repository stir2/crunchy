extends SceneTree
## Frame-by-frame tests use actual CharacterBody2D collisions and Input Map actions.
var failures: int = 0
var lab: Node2D
var player: Player
var checks: int = 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func tick(count: int = 1) -> void:
	for index in range(count):
		await physics_frame
		await process_frame


func release_inputs() -> void:
	for action in ["Move Left", "Move Right", "Jump", "Action"]:
		Input.action_release(action)


func place(point: Vector2) -> void:
	release_inputs()
	player.position = point
	player.reset_movement()
	player.gravity_multiplier = 1.0
	player.coyote_frames = 6
	player.jump_buffer_frames = 6
	player.dash_charge_frames = 12
	player.dash_duration_frames = 9
	player.dash_recovery_frames = 8
	player.facing_direction = 1
	await tick(4)


func leave_ledge(grace: int = 6) -> void:
	await place(Vector2(526.5,320))
	player.coyote_frames = grace
	check(player.is_on_floor(), "Ledge setup is not grounded")
	player.velocity.x = player.run_speed
	Input.action_press("Move Right")
	await tick()
	Input.action_release("Move Right")
	check(not player.is_on_floor(), "Ledge setup did not walk off")
	check(player.coyote_frames_remaining == grace, "Grace did not begin at configured frame count")


func prepare_buffer(landing_tick: int, frames: int) -> void:
	await place(Vector2(704,240))
	player.gravity_multiplier = 0.0 # Precisely 10px per tick to a real floor.
	player.position.y = 320.0 - 10.0 * landing_tick
	player.velocity = Vector2(0,10.0 * Engine.physics_ticks_per_second)
	player.jump_buffer_frames = frames
	Input.action_press("Jump")


func run() -> void:
	check(InputMap.has_action("Action"), "Dash action missing")
	check(not InputMap.action_get_events("Action").is_empty(), "Action has no configured bindings")
	lab = load("res://Scenes/Player/player_test.tscn").instantiate() as Node2D
	root.add_child(lab)
	player = lab.get_node("Player") as Player

	# Last valid coyote frame works, but cannot be consumed twice.
	await leave_ledge()
	await tick(5)
	check(player.coyote_frames_remaining == 1, "Coyote counter off by one before last valid tick")
	Input.action_press("Jump")
	await tick()
	check(player.is_jump_charging() and player.coyote_frames_remaining == 0, "Last-frame coyote jump was not reserved")
	await tick(player.jump_charge_frames)
	check(player.velocity.y == player.jump_velocity, "Reserved coyote jump did not launch after its delay")
	Input.action_release("Jump")
	await tick()
	var previous_y: float = player.velocity.y
	Input.action_press("Jump")
	await tick()
	check(player.velocity.y > previous_y, "Coyote allowed a second aerial jump")

	await leave_ledge()
	await tick(6)
	check(player.coyote_frames_remaining == 0, "Coyote did not expire after six ticks")
	Input.action_press("Jump")
	await tick()
	check(player.velocity.y >= 0, "Expired coyote allowed jump")
	await leave_ledge(0)
	Input.action_press("Jump")
	await tick()
	check(player.velocity.y >= 0, "Zero coyote setting still allowed grace")
	await leave_ledge(1)
	Input.action_press("Jump")
	await tick()
	check(player.is_jump_charging(), "One-frame coyote window was disabled by decrement order")
	await tick(player.jump_charge_frames)
	check(player.velocity.y == player.jump_velocity, "One-frame coyote jump did not launch after delay")

	await leave_ledge()
	Input.action_press("Jump")
	Input.action_press("Action")
	await tick()
	check(player.movement_state == Player.MovementState.DASH_CHARGING and player.coyote_frames_remaining == 0 and player.jump_buffer_frames_remaining == 0, "Dash did not cancel coyote/simultaneous jump")

	await place(Vector2(704,320))
	Input.action_press("Jump")
	await tick()
	check(player.coyote_frames_remaining == 0, "Normal jump granted coyote time")
	await place(Vector2(704,320))
	player.velocity.y = -200.0
	await tick()
	check(not player.is_on_floor() and player.coyote_frames_remaining == 0, "External upward launch granted coyote")

	await place(Vector2(704,320))
	Input.action_press("Jump")
	Input.action_release("Jump")
	await tick()
	check(player.is_jump_charging(), "Short tap skipped wind-up")
	await tick(player.jump_charge_frames)
	check(player.velocity.y == player.jump_velocity*player.jump_release_multiplier, "Delayed short tap lost variable height")

	# Input tick counts as buffered tick 1. Landing on tick N is still valid.
	await prepare_buffer(3,3)
	await tick()
	check(player.jump_buffer_frames_remaining == 2, "Buffer input tick count incorrect")
	Input.action_release("Jump")
	await tick()
	check(player.jump_buffer_frames_remaining == 1 and player.velocity.y > 0, "Buffer expired early or jumped before landing")
	await tick()
	check(player.is_jump_charging() and player.jump_buffer_frames_remaining == 0, "Buffered jump did not reserve on last valid landing tick")
	await tick(player.jump_charge_frames)
	check(player.velocity.y == player.jump_velocity*player.jump_release_multiplier, "Released buffered tap did not launch a short jump")
	await tick()
	check(player.velocity.y == player.jump_velocity*player.jump_release_multiplier and not player.is_on_floor(), "Buffered tap was cut twice or did not launch")
	player.gravity_multiplier = 1.0
	await tick(75)
	check(player.is_on_floor() and player.jump_buffer_frames_remaining == 0, "Buffered input was executed more than once")
	await prepare_buffer(3,2)
	await tick(3)
	check(player.is_on_floor() and player.velocity.y == 0 and player.jump_buffer_frames_remaining == 0, "Expired buffer launched a jump")
	await prepare_buffer(1,0)
	await tick()
	check(player.is_on_floor() and player.velocity.y == 0, "Zero buffer captured an unavailable airborne press")
	Input.action_release("Jump")
	await tick()
	Input.action_press("Jump")
	await tick()
	check(player.is_jump_charging(), "Zero buffer broke grounded jump reservation")
	await tick(player.jump_charge_frames)
	check(player.velocity.y == player.jump_velocity, "Zero buffer broke delayed takeoff")

	# Rising/falling charge cancels vertical momentum and every gravity tick.
	for incoming_y in [-220.0,220.0]:
		await place(Vector2(2080,100))
		player.velocity = Vector2(90,incoming_y)
		var frozen: Vector2 = player.position
		var visual_rest: Vector2 = player.visuals.position
		var saw_charge_shake: bool = false
		Input.action_press("Action")
		Input.action_press("Move Left") # Charge redirects toward held input.
		Input.action_press("Jump")
		for index in range(12):
			await tick()
			check(player.position.is_equal_approx(frozen), "Air charge moved position or applied gravity")
			saw_charge_shake = saw_charge_shake or player.visuals.position != visual_rest
			check(player.visuals.position.distance_to(visual_rest) <= 1.5 and player.get_node("CollisionShape2D").position == Vector2(0,-18) and player.get_node("Hurtbox").position == Vector2(0,-18), "Charge shake moved physics shapes or exceeded small visual offset")
			check(player.dash_direction == -1 and player.facing_direction == -1, "Charge did not follow directional input")
			check(player.coyote_frames_remaining == 0 and player.jump_buffer_frames_remaining == 0, "Charge retained jump/coyote input")
			if index < 11:
				check(player.movement_state == Player.MovementState.DASH_CHARGING and player.dash_phase_frames_remaining == 11-index and player.velocity == Vector2.ZERO, "Charge duration/timer off by one")
			else:
				check(player.movement_state == Player.MovementState.DASHING and player.dash_phase_frames_remaining == 9, "Charge did not launch automatically after 12 ticks")
		check(saw_charge_shake and player.visuals.position == visual_rest, "Charge did not shake visually or failed to reset offset at launch")
		var dash_start: Vector2 = player.position
		for index in range(9):
			if index % 2 == 0:
				Input.action_press("Action")
				Input.action_press("Jump")
			else:
				Input.action_release("Action")
				Input.action_release("Jump")
			await tick()
			check(player.jump_buffer_frames_remaining == 0, "Jump during dash queued a delayed jump")
			check(absf(player.position.y-dash_start.y)<0.001, "Dash applied vertical movement/gravity")
			if index < 8:
				check(player.movement_state == Player.MovementState.DASHING and player.dash_phase_frames_remaining == 8-index, "Dash duration counter off by one")
		check(player.movement_state == Player.MovementState.RECOVERY and player.dash_phase_frames_remaining == 8, "Dash did not finish after exactly nine movement ticks")
		var expected_distance: float = player.dash_speed * 9.0 / Engine.physics_ticks_per_second
		check(absf(player.position.x-dash_start.x-player.dash_direction*expected_distance)<0.01, "Dash distance does not match speed times tick duration")
		check(player.velocity.y == 0 and is_equal_approx(absf(player.velocity.x), player.dash_speed) and not player.dash_available, "Dash finish restored old velocity or availability")
		for index in range(8):
			Input.action_release("Action")
			await tick()
			check(player.velocity.y > 0, "Recovery failed to resume downward gravity")
			if index < 7:
				check(player.movement_state == Player.MovementState.RECOVERY, "Recovery ended before eight ticks")
			Input.action_press("Action")
		check(player.movement_state == Player.MovementState.NORMAL, "Recovery did not end after eight ticks")
		var expected_momentum: float = maxf(0,player.dash_speed-player.dash_recovery_deceleration*8.0/Engine.physics_ticks_per_second)
		check(is_equal_approx(player.velocity.x,player.dash_direction*expected_momentum), "Dash momentum did not decay using configured recovery braking")
		await tick()
		check(player.movement_state == Player.MovementState.NORMAL and not player.dash_available, "Repeated aerial dash was allowed")
		release_inputs()

	# Real wall collision shortens the dash instead of tunneling through it.
	await place(Vector2(2330,320))
	Input.action_press("Action")
	await tick(12)
	var ticks_to_wall: int = 0
	while player.movement_state == Player.MovementState.DASHING and ticks_to_wall < 9:
		await tick()
		ticks_to_wall += 1
	check(ticks_to_wall < 9 and player.movement_state == Player.MovementState.RECOVERY and player.position.x <= 2353.1, "Dash crossed wall or failed to stop early")

	# A landing during recovery restores budget but does not bypass recovery.
	await place(Vector2(2080,240))
	player.position.y = 319.0
	Input.action_press("Action")
	await tick(21)
	check(not player.dash_available and not player.is_on_floor(), "Air dash budget was reset before landing")
	await tick(3)
	check(player.is_on_floor() and player.dash_available and player.movement_state == Player.MovementState.RECOVERY, "Recovery landing did not restore aerial dash")
	Input.action_release("Action")
	await tick()
	Input.action_press("Action")
	await tick()
	check(player.movement_state == Player.MovementState.RECOVERY, "Landing bypassed recovery lock")
	await tick(3)
	while player.dash_cooldown_frames_remaining > 0:
		await tick()
	Input.action_release("Action")
	await tick()
	Input.action_press("Action")
	await tick()
	check(player.movement_state == Player.MovementState.DASH_CHARGING, "Landing did not permit next dash after recovery and cooldown")

	# Ground charge/one-way dash; holding Dash never repeatedly triggers.
	await place(Vector2(1808,256))
	check(player.is_on_floor(), "One-way dash setup not grounded")
	var platform_y: float = player.position.y
	Input.action_press("Action")
	await tick(12)
	check(absf(player.position.y-platform_y)<0.01, "Ground charge left one-way platform")
	await tick(9)
	check(absf(player.position.y-platform_y)<0.01 and not player.dash_available and player.coyote_frames_remaining == 0, "One-way departure granted coyote/dash or fell during dash")
	await place(Vector2(2080,320))
	Input.action_press("Action")
	await tick(35)
	check(player.movement_state == Player.MovementState.NORMAL and player.dash_available, "Held Dash restarted grounded charge or completed ground recovery failed to rearm budget")
	Input.action_release("Action")
	await tick()
	Input.action_press("Action")
	await tick()
	check(player.movement_state == Player.MovementState.DASH_CHARGING, "Repeated grounded dash unavailable after recovery")

	# Dash gap, starting grounded: collision and suspended gravity span the gap.
	await place(Vector2(1896,304))
	Input.action_press("Action")
	await tick(33)
	check(player.position.x > 1999 and player.is_on_floor(), "Ground dash failed to bridge runway gap")

	# Zero charge/recovery settings transition without a phantom timer frame.
	await place(Vector2(2080,100))
	player.dash_charge_frames = 0
	player.dash_duration_frames = 1
	player.dash_recovery_frames = 0
	var initial_x: float = player.position.x
	Input.action_press("Action")
	await tick()
	check(player.position.x > initial_x and player.movement_state == Player.MovementState.NORMAL, "Zero phase settings added phantom ticks")

	# Respawn is safe in either locked phase, and held input does not restart it.
	for phase_ticks in [1,13,23]:
		await place(Vector2(2080,100))
		Input.action_press("Action")
		await tick(phase_ticks)
		lab.respawn_player()
		check(player.movement_state == Player.MovementState.NORMAL and player.velocity == Vector2.ZERO and player.coyote_frames_remaining == 0 and player.jump_buffer_frames_remaining == 0 and player.dash_phase_frames_remaining == 0 and player.dash_available, "Respawn failed to reset state/timers/budget")
		await tick()
		check(player.movement_state == Player.MovementState.NORMAL, "Held dash restarted immediately after respawn")
		check(player.visuals.modulate == Color.WHITE and player.visuals.position == Vector2(0,-18), "Respawn did not restore placeholder appearance/position")
	var body: CollisionShape2D = player.get_node("CollisionShape2D")
	var hurt: CollisionShape2D = player.get_node("Hurtbox/CollisionShape2D")
	check(body.shape.size == Vector2(30,36) and hurt.shape.size == Vector2(24,32) and body.position == Vector2(0,-18) and body.scale == Vector2.ONE and player.scale == Vector2.ONE, "Dash changed collision geometry")
	release_inputs()
	lab.free()
	print("Charged dash / jump grace checks: ",checks," checks, failures=",failures)
	quit(1 if failures else 0)
