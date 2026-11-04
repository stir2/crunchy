extends SceneTree
## Real input/physics checks, independent of the movement lab's designer tuning.
var failures: int = 0
var player: Player

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func tick(count: int = 1) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame

func place(vertical_speed: float) -> void:
	for action in ["Move Down", "Action", "Jump"]:
		Input.action_release(action)
	player.global_position = Vector2(0,-500)
	player.reset_movement()
	player.velocity.y = vertical_speed

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(0,320)
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(2000,32)
	collider.shape = shape
	floor_body.add_child(collider)
	world.add_child(floor_body)
	player = load("res://Scenes/Player/player.tscn").instantiate() as Player
	player.position = Vector2(0,-500)
	world.add_child(player)
	player.gravity_multiplier = 1.0
	await tick(2)
	place(120)
	await tick(10)
	var normal_speed := player.velocity.y
	var normal_y := player.position.y
	place(120)
	Input.action_press("Move Down")
	await tick()
	check(player.velocity.y >= player.fast_fall_speed, "Down did not give an immediate downward kick")
	var first_speed := player.velocity.y
	await tick()
	check(is_equal_approx(player.velocity.y - first_speed, player.get_gravity().y / Engine.physics_ticks_per_second), "Holding Down stacked impulses or increased gravity")
	await tick(8)
	check(player.velocity.y > normal_speed and player.position.y > normal_y, "Down did not accelerate descent")
	Input.action_release("Move Down")
	var before_release := player.velocity.y
	await tick()
	var ordinary_acceleration := player.velocity.y - before_release
	check(is_equal_approx(ordinary_acceleration, player.get_gravity().y / Engine.physics_ticks_per_second), "Gravity changed after release")
	check(player.velocity.y > before_release, "Release erased accumulated fall speed")
	place(-200)
	await tick(4)
	var rising_speed := player.velocity.y
	var rising_y := player.position.y
	place(-200)
	Input.action_press("Move Down")
	await tick(4)
	check(is_equal_approx(player.velocity.y,rising_speed) and is_equal_approx(player.position.y,rising_y), "Down changed ascent")
	place(120)
	player.fast_fall_speed = 0.0
	Input.action_press("Move Down")
	await tick(10)
	check(is_equal_approx(player.velocity.y,normal_speed), "Speed 0 did not disable boost")
	player.fast_fall_speed = 600.0
	place(800)
	Input.action_press("Move Down")
	await tick()
	check(player.velocity.y > 800, "Fast fall slowed an already faster fall")
	place(-10)
	Input.action_press("Move Down")
	await tick(5)
	check(player.velocity.y >= player.fast_fall_speed, "Held Down did not activate on descent")
	place(120)
	Input.action_press("Action")
	Input.action_press("Move Down")
	await tick(4)
	check(player.movement_state == Player.MovementState.DASH_CHARGING and player.velocity == Vector2.ZERO, "Down interrupted dash charge")
	var frozen := player.position
	await tick(3)
	check(player.position.is_equal_approx(frozen), "Down moved frozen dash charge")
	Input.action_release("Action")
	await tick(2)
	check(player.movement_state == Player.MovementState.DASHING and is_zero_approx(player.velocity.y), "Down added gravity during dash")
	place(0)
	player.position = Vector2(0,300)
	Input.action_press("Move Down")
	await tick(12)
	check(player.is_on_floor() and absf(player.position.y - 304) < 1, "Fast fall failed to land on solid terrain")
	var standing := player.position
	await tick(5)
	check(player.position.is_equal_approx(standing), "Held Down moved grounded player")
	for action in ["Move Down", "Action", "Jump"]:
		Input.action_release(action)
	world.free()
	print("Fast fall: immediate speed, ordinary gravity, no stacking/slowing, release, ascent, disabling, dash suspension and landing; failures=",failures)
	quit(1 if failures else 0)
