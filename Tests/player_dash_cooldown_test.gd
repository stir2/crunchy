extends SceneTree
## Reproduces dash -> jump cancel -> dash, with exact independent cooldown ticks.
var checks: int = 0
var failures: int = 0
var world: Node2D
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


func release_inputs() -> void:
	for action in ["Move Left","Move Right","Jump","Action"]:
		Input.action_release(action)


func fresh_dash_press() -> void:
	Input.action_release("Action")
	Input.action_press("Action")


func prepare(point: Vector2 = Vector2(0,320)) -> void:
	release_inputs()
	player.position = point
	player.reset_movement()
	player.dash_charge_frames = 0
	player.dash_duration_frames = 3
	player.dash_recovery_frames = 2
	player.dash_cooldown_frames = 4
	player.jump_charge_frames = 8
	player.facing_direction = 1
	await tick(4)


func solid(point: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = point
	body.collision_layer = 1
	var shape_node := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape_node.shape = rectangle
	body.add_child(shape_node)
	world.add_child(body)


func run() -> void:
	world = Node2D.new()
	root.add_child(world)
	solid(Vector2(0,330),Vector2(20000,20))
	solid(Vector2(200,200),Vector2(20,240))
	player = load("res://Scenes/Player/player.tscn").instantiate() as Player
	world.add_child(player)
	check(player.dash_cooldown_frames == 12, "Default cooldown should be twelve physics ticks")

	# Original exploit: a new Dash edge immediately after jump-cancel.
	await prepare()
	Input.action_press("Action")
	await tick()
	check(player.movement_state == Player.MovementState.DASHING, "Initial dash failed")
	Input.action_release("Action")
	Input.action_press("Jump")
	await tick()
	check(player.movement_state == Player.MovementState.NORMAL and player.is_jump_charging(), "Ground dash jump-cancel failed")
	check(player.dash_cooldown_frames_remaining == 4, "Jump-cancel failed to start a full cooldown")
	var frozen: Vector2 = player.position
	for elapsed in range(1,5):
		fresh_dash_press()
		await tick()
		check(player.is_jump_charging() and player.movement_state == Player.MovementState.NORMAL, "Repeated Dash bypassed cooldown through jump charge")
		check(player.position.is_equal_approx(frozen), "Rejected dash destroyed frozen jump charge")
		check(player.dash_cooldown_frames_remaining == 4-elapsed, "Cooldown paused/reset during jump charge or expired early")
	fresh_dash_press()
	await tick()
	check(player.movement_state == Player.MovementState.DASHING and not player.is_jump_charging(), "Dash still blocked after the complete cooldown")
	Input.action_release("Jump")
	Input.action_press("Jump")
	await tick()
	check(player.is_jump_charging() and player.dash_cooldown_frames_remaining == 4, "Second jump-cancel bypassed starting another cooldown")

	# Ordinary end: recovery can finish, but the independent cooldown still blocks.
	await prepare()
	Input.action_press("Action")
	await tick(3)
	check(player.movement_state == Player.MovementState.RECOVERY and player.dash_cooldown_frames_remaining == 4, "Normal end did not start cooldown")
	for elapsed in range(1,5):
		fresh_dash_press()
		await tick()
		check(player.movement_state != Player.MovementState.DASHING and player.movement_state != Player.MovementState.DASH_CHARGING, "Recovery completion bypassed cooldown")
		check(player.dash_cooldown_frames_remaining == 4-elapsed, "Normal-end cooldown tick count incorrect")
	await tick() # Keep holding the rejected final press: no automatic dash queue.
	check(player.movement_state == Player.MovementState.NORMAL, "Held Dash auto-started when cooldown expired")
	fresh_dash_press()
	await tick()
	check(player.movement_state == Player.MovementState.DASHING, "Fresh press after cooldown failed")

	# Even zero recovery cannot skip the independent lockout.
	await prepare()
	player.dash_duration_frames = 1
	player.dash_recovery_frames = 0
	Input.action_press("Action")
	await tick()
	check(player.movement_state == Player.MovementState.NORMAL and player.dash_cooldown_frames_remaining == 4, "Zero recovery disabled cooldown")
	fresh_dash_press()
	await tick()
	check(player.movement_state == Player.MovementState.NORMAL, "Dash repeated immediately with zero recovery")

	# Wall stop is an early end and must use the same cooldown.
	await prepare(Vector2(150,320))
	player.dash_duration_frames = 20
	Input.action_press("Action")
	var elapsed: int = 0
	while elapsed < 10:
		await tick()
		elapsed += 1
		if player.movement_state == Player.MovementState.RECOVERY:
			break
	check(elapsed < 10 and player.position.x <= 175.1 and player.dash_cooldown_frames_remaining == 4, "Wall collision did not end dash with a full cooldown")

	# Landing restores budget, never the cooldown; expiry doesn't restore air budget.
	await prepare(Vector2(0,80))
	player.dash_duration_frames = 1
	player.dash_recovery_frames = 0
	Input.action_press("Action")
	await tick()
	await tick(4)
	check(player.dash_cooldown_frames_remaining == 0 and not player.dash_available, "Cooldown expiry restored the aerial dash budget")
	fresh_dash_press()
	await tick()
	check(player.movement_state == Player.MovementState.NORMAL, "Cooldown expiry permitted a second aerial dash")
	await prepare(Vector2(0,80))
	player.dash_duration_frames = 1
	player.dash_recovery_frames = 0
	player.dash_cooldown_frames = 12
	Input.action_press("Action")
	await tick()
	player.position.y = 319.5
	player.velocity.y = 60.0
	await tick()
	check(player.is_on_floor() and player.dash_available and player.dash_cooldown_frames_remaining == 11, "Landing cleared cooldown or failed to restore budget")
	fresh_dash_press()
	await tick()
	check(player.movement_state == Player.MovementState.NORMAL and player.dash_cooldown_frames_remaining == 10, "Landing bypassed dash lockout")

	player.reset_movement()
	check(player.dash_cooldown_frames_remaining == 0 and player.dash_available, "Respawn retained cooldown")
	await tick()
	check(player.movement_state == Player.MovementState.NORMAL, "Respawn retriggered held dash")

	# Inspector zero remains an explicit opt-out, rather than a hidden minimum.
	await prepare()
	player.dash_cooldown_frames = 0
	player.dash_recovery_frames = 0
	player.dash_duration_frames = 1
	Input.action_press("Action")
	await tick()
	check(player.dash_cooldown_frames_remaining == 0, "Zero cooldown imposed a lockout")
	player.dash_duration_frames = 3
	fresh_dash_press()
	await tick()
	check(player.movement_state == Player.MovementState.DASHING, "Zero cooldown did not permit a new press")
	release_inputs()
	world.free()
	print("Dash cooldown: ",checks," checks, failures=",failures)
	quit(1 if failures else 0)
