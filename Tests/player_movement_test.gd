extends SceneTree
## Real physics/input checks in the editable movement lab, no abyss generation.
var failures: int = 0
var lab: Node2D
var player: Player


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame


func release_inputs() -> void:
	for action in ["Move Left", "Move Right", "Move Up", "Move Down", "Jump", "Attack", "Action"]:
		Input.action_release(action)


func place(position: Vector2) -> void:
	release_inputs()
	player.global_position = position
	player.reset_movement()
	await frames(4)


func jump_height(hold_frames: int) -> float:
	await place(Vector2(240, 320))
	var start_y: float = player.position.y
	var highest_y: float = start_y
	Input.action_press("Jump")
	for index in range(65):
		if index == hold_frames:
			Input.action_release("Jump")
		await frames(1)
		highest_y = minf(highest_y, player.position.y)
	release_inputs()
	return start_y - highest_y


func run() -> void:
	for action in ["Move Left", "Move Right", "Move Up", "Move Down", "Jump", "Attack", "Action"]:
		check(InputMap.has_action(action), "Missing original action: " + action)
	var original_viewport_size: Vector2i = root.content_scale_size
	var original_scale_mode: int = root.content_scale_mode
	lab = load("res://Scenes/Player/player_test.tscn").instantiate() as Node2D
	root.add_child(lab)
	player = lab.get_node("Player") as Player
	await frames(15)
	check(player.is_on_floor() and absf(player.position.y - 320.0) < 1.0, "Player did not land on solid floor")
	check(player.collision_layer == 2 and player.collision_mask == 1, "Player collision does not match terrain")
	var body_shape := player.get_node("CollisionShape2D") as CollisionShape2D
	check(body_shape.shape is RectangleShape2D and body_shape.shape.size == Vector2(30,36), "Body must be exactly 30x36")
	check(body_shape.position == Vector2(0,-18) and player.visuals.position == body_shape.position, "Feet origin/visual alignment incorrect")
	var hurtbox := player.get_node("Hurtbox") as PlayerHurtbox
	var hurt_shape := hurtbox.get_node("CollisionShape2D") as CollisionShape2D
	check(hurt_shape.shape is RectangleShape2D and hurt_shape.shape.size == Vector2(24,32), "Hurtbox must be exactly 24x32")
	check(hurtbox.position == Vector2(0,-18) and hurt_shape.position == Vector2.ZERO, "Hurtbox not centered inside body")
	check(hurtbox.collision_layer == 4 and hurtbox.collision_mask == 8 and hurtbox.monitoring, "Hurtbox damage-area filtering incorrect")
	var entered: Array[Area2D] = []
	var exited: Array[Area2D] = []
	hurtbox.damage_area_entered.connect(func(area: Area2D) -> void: entered.append(area))
	hurtbox.damage_area_exited.connect(func(area: Area2D) -> void: exited.append(area))
	var damage_area := Area2D.new()
	damage_area.collision_layer = 16 # Unrelated layer should be ignored.
	damage_area.collision_mask = 0
	damage_area.monitoring = false
	damage_area.position = player.position + Vector2(0,-18)
	var damage_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12,12)
	damage_shape.shape = rectangle
	damage_area.add_child(damage_shape)
	lab.add_child(damage_area)
	await frames(4)
	check(entered.is_empty(), "Hurtbox detected incompatible area layer")
	var unrelated_area := damage_area
	damage_area = unrelated_area.duplicate() as Area2D
	damage_area.collision_layer = 8
	lab.add_child(damage_area)
	unrelated_area.queue_free()
	await frames(4)
	check(entered.has(damage_area) and player.is_on_floor(), "Compatible damage overlap hook failed")
	var before_overlap_move: float = player.position.x
	Input.action_press("Move Right")
	await frames(14)
	check(player.position.x > before_overlap_move+24 and player.is_on_floor(), "Damage area/hurtbox blocked movement")
	check(exited.has(damage_area), "Damage exit hook failed")
	release_inputs()
	damage_area.queue_free()

	# Verify 2x/3x viewport transforms without changing collision pixels.
	for size in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = size
		await frames(2)
		check(root.content_scale_size == Vector2i(640,360) and root.get_visible_rect().size == Vector2(640,360), "Base viewport changed with desktop window size")
		check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT and root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP and root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER, "Pixel-art presentation modes incorrect")
		var expected_scale := float(size.x)/640.0
		check(root.get_final_transform().get_scale().is_equal_approx(Vector2.ONE*expected_scale), "Viewport did not scale at integer 2x/3x")
		check(body_shape.shape.size == Vector2(30,36) and hurt_shape.shape.size == Vector2(24,32), "Window scaling changed collision sizes")
	check(root.canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST, "Lab default filter is not nearest")
	check(player.get_node("Visuals/AnimatedSprite2D").scale == Vector2.ONE and player.get_node("Visuals/AnimatedSprite2D").texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Sprite scaled/distorted or filtering not nearest")
	var hitbox := player.get_node("AttackPivot/AttackHitbox") as Area2D
	check(not hitbox.monitoring and not hitbox.monitorable and hitbox.collision_mask == 0 and hitbox.get_node("CollisionShape2D").disabled and hitbox.get_node("CollisionShape2D").shape == null, "Attack hitbox is active")
	check(not player.get_node("ClimbDetector").monitoring, "Climbing detector should be inactive")

	# Ground acceleration ramps up; direction changes brake smoothly.
	await place(Vector2(240, 320))
	Input.action_press("Move Right")
	await frames(1)
	check(player.velocity.x > 0 and player.velocity.x < player.run_speed, "Ground acceleration was instantaneous or absent")
	await frames(12)
	check(is_equal_approx(player.velocity.x, player.run_speed), "Player did not reach run speed")
	Input.action_release("Move Right")
	Input.action_press("Move Left")
	await frames(1)
	check(player.velocity.x > 0 and player.velocity.x < player.run_speed, "Direction reversal did not decelerate smoothly")
	check(player.facing_direction == -1 and player.visuals.scale.x < 0 and player.attack_pivot.scale.x < 0, "Left facing did not flip visual/pivot")
	await frames(20)
	check(player.velocity.x < 0, "Left movement failed")
	Input.action_release("Move Left")
	await frames(12)
	check(is_zero_approx(player.velocity.x), "Ground friction did not stop player")
	check(player.facing_direction == -1, "Facing reset when input was released")
	check(body_shape.scale == Vector2.ONE and hurtbox.scale == Vector2.ONE and hurtbox.global_position.is_equal_approx(body_shape.global_position), "Left facing flipped or misaligned collision shapes")

	# Ordinary horizontal calculations leave vertical velocity alone.
	player.velocity.y = -123.0
	Input.action_press("Move Right")
	player.handle_horizontal_movement(1.0 / 60.0)
	check(player.velocity.y == -123.0, "Horizontal movement changed vertical velocity")
	check(player.velocity.x > 0, "Horizontal calculation did not accelerate")
	release_inputs()

	await place(Vector2(240, 320))
	Input.action_press("Jump")
	await frames(1)
	check(player.is_jump_charging() and player.is_on_floor() and player.velocity.y == 0, "Jump did not enter grounded wind-up")
	await frames(player.jump_charge_frames)
	check(player.velocity.y < -350 and not player.is_on_floor(), "Ground jump failed")
	Input.action_release("Jump")
	await frames(1)
	var before_second_jump: float = player.velocity.y
	Input.action_press("Jump")
	await frames(1)
	check(player.velocity.y > before_second_jump, "Midair input incorrectly created another jump")
	Input.action_press("Move Right")
	await frames(5)
	check(player.velocity.x > 0 and player.velocity.x < player.run_speed and player.velocity.y > before_second_jump, "Air acceleration interfered with gravity")
	check(player.facing_direction == 1 and player.visuals.scale.x > 0, "Right facing failed")
	release_inputs()

	var full_height: float = await jump_height(50)
	var short_height: float = await jump_height(4)
	check(full_height > short_height + 15.0 and short_height > 0, "Early release did not reduce jump height")

	# The existing TileSet supplies real one-way collision: pass up, land down.
	await place(Vector2(144, 320))
	Input.action_press("Jump")
	var crossed_above: bool = false
	var landed_on_platform: bool = false
	for index in range(65):
		await frames(1)
		crossed_above = crossed_above or player.position.y < 256.0
		landed_on_platform = landed_on_platform or (player.is_on_floor() and absf(player.position.y - 256.0) < 1.0)
	check(crossed_above and landed_on_platform, "Player could not jump through and land on one-way platform")
	release_inputs()

	# Run into the solid wall on the right side of the lab.
	await place(Vector2(1308, 320))
	Input.action_press("Move Right")
	await frames(30)
	check(player.is_on_wall() and player.position.x <= 1329.1, "Solid wall failed to block horizontal movement")
	release_inputs()

	# Comfortable and tight passages both fit the fixed body. Jump into a real ceiling.
	await place(Vector2(824,320))
	Input.action_press("Move Right")
	await frames(20)
	check(player.position.x > 868 and player.is_on_floor(), "Comfortable passage blocked player")
	release_inputs()
	await frames(1)
	Input.action_press("Jump")
	var ceiling_hit: bool = false
	var highest_feet: float = player.position.y
	for index in range(30):
		await frames(1)
		ceiling_hit = ceiling_hit or player.is_on_ceiling()
		highest_feet = minf(highest_feet,player.position.y)
	check(ceiling_hit and highest_feet >= 291.9, "Player passed through passage ceiling")
	release_inputs()
	await place(Vector2(976,320))
	Input.action_press("Move Right")
	await frames(30)
	check(player.position.x > 1032 and player.is_on_floor(), "48px tight passage does not fit 36px body")
	await frames(20)
	check(player.is_on_wall() and player.position.x <= 1073.1, "Player incorrectly fit through 16px passage")
	release_inputs()

	# A 30px-wide body fits a 32px shaft, with only 1px on either side.
	await place(Vector2(1120,200))
	await frames(35)
	check(player.is_on_floor() and absf(player.position.y-288.0)<1 and absf(player.position.x-1120.0)<0.1, "30px body failed to fit 32px shaft")
	await place(Vector2(1208,200))
	await frames(40)
	check(player.is_on_floor() and absf(player.position.y-320.0)<1, "Comfortable 48px shaft blocked body")

	# At full speed, the intended 96px floor gap is jumpable.
	await place(Vector2(460, 320))
	Input.action_press("Move Right")
	await frames(13)
	check(player.is_on_floor() and player.position.x < 512, "Gap test approach left floor too early")
	Input.action_press("Jump")
	var crossed_gap: bool = false
	var landed_after_gap: bool = false
	for index in range(120 + player.jump_charge_frames):
		await frames(1)
		crossed_gap = crossed_gap or player.position.x > 608
		if crossed_gap and player.is_on_floor():
			landed_after_gap = true
			break
	check(crossed_gap and landed_after_gap, "Player failed to cross and land beyond the test gap")
	release_inputs()

	# Up/Down/Attack are reserved and must not move the player or enable a hitbox.
	await place(Vector2(240, 320))
	var resting_position: Vector2 = player.position
	for action in ["Move Up", "Move Down", "Attack"]:
		Input.action_press(action)
	await frames(5)
	check(player.position.is_equal_approx(resting_position) and not hitbox.monitoring, "Reserved inputs changed movement/combat")
	release_inputs()

	player.position = Vector2(560, 700)
	await frames(3)
	check(player.position.distance_to(lab.get_node("Spawn").position) < 10 and player.velocity.y >= 0, "Fall respawn failed")

	# The reusable scene also works under an ordinary parent without lab/camera.
	var second := load("res://Scenes/Player/player.tscn").instantiate() as Player
	second.position = Vector2(740, 304)
	lab.add_child(second)
	await frames(20)
	check(second.is_on_floor(), "Player could not be reused in another scene context")
	var first_shape := player.get_node("CollisionShape2D").shape as RectangleShape2D
	var second_shape := second.get_node("CollisionShape2D").shape as RectangleShape2D
	check(first_shape != second_shape, "Collider resources are shared between instances")
	check(first_shape.size == Vector2(30,36) and body_shape.position == Vector2(0,-18) and player.scale == Vector2.ONE, "Movement/facing changed body dimensions or feet offset")
	check(hurtbox.global_position.is_equal_approx(body_shape.global_position) and hurtbox.scale == Vector2.ONE and hurt_shape.scale == Vector2.ONE and body_shape.scale == Vector2.ONE, "Facing/movement misaligned physics and hurtbox")
	check(hurt_shape.shape.size == Vector2(24,32), "Hurtbox changed size during movement")
	lab.free()
	check(root.content_scale_size == original_viewport_size and root.content_scale_mode == original_scale_mode, "Lab did not restore host presentation settings")
	print("Player movement checks: full jump=%.1fpx, short jump=%.1fpx, failures=%d" % [full_height, short_height, failures])
	quit(1 if failures else 0)
