extends SceneTree
## Exact physics-tick checks for visible anticipation and fixed jump strength.
var failures: int = 0
var checks: int = 0
var lab: Node2D
var player: Player


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


func place() -> void:
	for action in ["Move Left", "Move Right", "Jump", "Action"]:
		Input.action_release(action)
	player.position = Vector2(704,320)
	player.reset_movement()
	await tick(4)


func run() -> void:
	lab = load("res://Scenes/Player/player_test.tscn").instantiate() as Node2D
	root.add_child(lab)
	player = lab.get_node("Player") as Player
	await place()
	check(player.jump_charge_frames > 0, "Configured anticipation is disabled")
	check(player.jump_release_multiplier > 0 and player.jump_release_multiplier < 1, "Variable-height jump is disabled")
	var sprite: AnimatedSprite2D = player.get_node("Visuals/AnimatedSprite2D")
	var body: CollisionShape2D = player.get_node("CollisionShape2D")
	var hurt: CollisionShape2D = player.get_node("Hurtbox/CollisionShape2D")
	var signals_seen: Array[bool] = []
	player.jump_charge_changed.connect(func(charging: bool) -> void: signals_seen.append(charging))
	var reference_height: float = -1.0

	# Holding the button gives identical strength at every delay, including zero.
	for delay in [0,1,3,6]:
		await place()
		player.jump_charge_frames = delay
		var floor_y: float = player.position.y
		signals_seen.clear()
		Input.action_press("Jump")
		await tick()
		if delay > 0:
			check(player.is_jump_charging() and player.jump_charge_frames_remaining == delay, "Press tick skipped or shortened the anticipation timer")
			check(sprite.animation == &"run" and sprite.frame == 4 and not sprite.is_playing(), "Anticipation pose is not visible")
			check(player.visuals.modulate != Color.WHITE, "Jump wind-up has no visual feedback")
			for elapsed in range(1,delay):
				await tick()
				check(player.is_on_floor() and is_zero_approx(player.velocity.y) and absf(player.position.y-floor_y)<0.01, "Takeoff occurred before the configured delay")
				check(player.jump_charge_frames_remaining == delay-elapsed, "Jump charge counter off by one")
			await tick()
		check(not player.is_jump_charging() and player.jump_charge_frames_remaining == 0 and not player.is_on_floor(), "Jump did not launch when charge expired")
		check(player.velocity.y == player.jump_velocity, "Charge duration changed jump strength")
		check(player.visuals.modulate == Color.WHITE, "Jump tint did not clear at takeoff")
		if delay > 0:
			check(signals_seen == [true,false], "Charge feedback did not start/end exactly once")
		var highest: float = player.position.y
		await tick()
		for index in range(50):
			await tick()
			highest = minf(highest,player.position.y)
		var height: float = floor_y-highest
		if reference_height < 0:
			reference_height = height
		check(absf(height-reference_height)<0.05, "Added anticipation changed held-jump apex height")

	# Releasing before takeoff remains a short jump; repeated taps don't restart it.
	await place()
	player.jump_charge_frames = 6
	Input.action_press("Jump")
	await tick()
	Input.action_release("Jump")
	await tick()
	Input.action_press("Jump")
	await tick()
	check(player.jump_charge_frames_remaining == 4, "Repeated jump press restarted anticipation")
	await tick(4)
	check(player.velocity.y == player.jump_velocity*player.jump_release_multiplier, "Release before takeoff was lost or scaled twice")
	Input.action_release("Jump")
	await tick()
	var rising_speed: float = player.velocity.y
	Input.action_press("Jump")
	await tick()
	check(player.velocity.y > rising_speed and not player.is_jump_charging(), "Pending jump permitted an extra airborne jump")

	# Charge freezes position and preserves incoming speed, even against input.
	await place()
	player.velocity.x = 500.0
	Input.action_press("Jump")
	Input.action_press("Move Left")
	var charge_position: Vector2 = player.position
	for index in range(player.jump_charge_frames):
		await tick()
		check(player.is_jump_charging() and player.position.is_equal_approx(charge_position) and player.velocity == Vector2.ZERO, "Jump charge moved or applied steering/friction")
	await tick()
	check(not player.is_jump_charging() and player.velocity.x == 500.0 - player.jump_horizontal_boost and player.velocity.y == player.jump_velocity, "Takeoff did not retain momentum and add the input-directed boost")

	# Grounded dash jump-cancel uses the same delay without destroying momentum.
	await place()
	player.dash_charge_frames = 0
	Input.action_press("Action")
	await tick()
	Input.action_press("Jump")
	await tick()
	check(player.movement_state == Player.MovementState.NORMAL and player.is_jump_charging() and player.velocity == Vector2.ZERO, "Dash jump-cancel skipped frozen anticipation")
	await tick(6)
	check(player.velocity.y == player.jump_velocity and player.velocity.x > player.run_speed and not player.is_jump_charging(), "Dash-canceled delayed jump did not launch with preserved momentum")

	# Starting another ability cancels the committed jump, rather than launching later.
	await place()
	player.dash_charge_frames = 16
	Input.action_press("Jump")
	await tick()
	Input.action_press("Action")
	await tick()
	check(not player.is_jump_charging() and player.jump_charge_frames_remaining == 0 and player.movement_state == Player.MovementState.DASH_CHARGING, "Dash did not cancel pending takeoff")
	await tick(8)
	check(player.velocity.y == 0, "Canceled jump launched during dash charging")
	await place()
	Input.action_press("Jump")
	await tick()
	lab.respawn_player()
	check(not player.is_jump_charging() and player.jump_charge_frames_remaining == 0 and player.visuals.modulate == Color.WHITE, "Respawn retained jump anticipation")
	await tick(8)
	check(player.velocity.y >= 0 and not player.is_jump_charging(), "Respawn replayed the old jump press")
	check(body.shape.size == Vector2(30,36) and hurt.shape.size == Vector2(24,32), "Anticipation changed collision dimensions")
	for action in ["Move Left", "Move Right", "Jump", "Action"]:
		Input.action_release(action)
	lab.free()
	print("Jump anticipation: ", checks, " checks, held apex=", snappedf(reference_height,0.1), "px; failures=", failures)
	quit(1 if failures else 0)
