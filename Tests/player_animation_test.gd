extends SceneTree
## Real input/state integration plus deterministic pose/atlas checks.
var checks: int = 0
var failures: int = 0
var world: Node2D
var player: Player
var sprite: AnimatedSprite2D
var impacts: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func tick(count: int = 1) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame

func release_inputs() -> void:
	for action in ["Move Left","Move Right","Move Up","Move Down","Jump","Attack","Action"]:
		Input.action_release(action)

func place(position: Vector2 = Vector2(96,320)) -> void:
	release_inputs()
	player.set_physics_process(true)
	player.position = position
	player.reset_movement()
	player.health.reset_health()
	player.stamina.reset_stamina()
	player._move_direction = 1
	player.update_facing_direction()
	player.jump_charge_frames = 5
	await tick(3)

func texture_source(name: StringName) -> String:
	var texture := sprite.sprite_frames.get_frame_texture(name,0) as AtlasTexture
	return texture.atlas.resource_path

func test_assets_and_origins() -> void:
	for name in [&"attack",&"attack_alt"]:
		check(sprite.sprite_frames.get_frame_count(name) == 17, "Slash must include all 17 frames")
		check(sprite.sprite_frames.get_animation_speed(name) == 24 and not sprite.sprite_frames.get_animation_loop(name), "Slash FPS/loop")
	check(texture_source(&"attack").ends_with("chiefSlash1_100x100_24fps.png"), "First slash source incorrect")
	check(texture_source(&"attack_alt").ends_with("chiefSlash2_100x100_24fps.png"), "Second slash source incorrect")
	check(texture_source(&"dash").ends_with("chiefRush_100x100_24fps.png") and sprite.sprite_frames.get_frame_count(&"dash") == 12, "Rush/dash source incorrect")
	check(texture_source(&"jump").ends_with("chiefJump_100x100_frames.png") and sprite.sprite_frames.get_frame_count(&"jump") == 6, "Jump source incorrect")
	for frame in range(6):
		var texture := sprite.sprite_frames.get_frame_texture(&"jump",frame) as AtlasTexture
		check(texture.get_size() == Vector2(100,100), "Jump margin changed frame canvas size")
		if frame >= 1 and frame <= 4:
			check(texture.region.position.x == frame * 100 + 23 and texture.margin.position.x == 23, "Guide dots not clipped while retaining origin")
	check(sprite.jump_offset == Vector2(0,3) and sprite.dash_offset == Vector2(0,3) and sprite.attack_offset == Vector2(0,3), "Shared foot baseline changed")
	check(player.get_node("MovementEffects").burst_offset == Vector2(-2,-15), "Existing effect origin changed")
	check(player.get_node("CollisionShape2D").shape.size == Vector2(30,36) and player.get_node("Hurtbox/CollisionShape2D").shape.size == Vector2(24,32), "Physical dimensions changed")
	check(player.combat.active_start_frame == 3 and player.combat.active_end_frame == 5 and player.combat.dash_recovery_lock_frames == 2, "Default phases do not match Slash poses")

func test_velocity_poses() -> void:
	await place(Vector2(96,-200))
	player.set_physics_process(false)
	var velocities: Array[float] = [-400,-30,-1,0,30,200]
	var poses: Array[int] = [1,2,2,3,3,4]
	for i in range(velocities.size()):
		player.velocity = Vector2(250,velocities[i])
		sprite.update_animation()
		check(sprite.animation == &"jump" and sprite.frame == poses[i] and not sprite.is_playing(), "Jump pose disagrees with vertical speed " + str(velocities[i]))
		check(player.velocity == Vector2(250,velocities[i]), "Pose selection mutated velocity")
	player.velocity.y = 100
	Input.action_press("Move Down")
	sprite.update_animation()
	check(sprite.animation == &"jump" and sprite.frame == 4, "Fast fall did not use falling pose")

func test_rush_phases() -> void:
	player.velocity = Vector2.ZERO
	player.set_movement_state(Player.MovementState.DASH_CHARGING,16)
	for ratio in [0.0,0.5,1.0]:
		player.dash_charge_ratio = ratio
		sprite.update_animation()
		check(sprite.animation == &"dash" and sprite.frame == mini(3,int(ratio*4)), "Rush charge pose mismatch")
	player.active_dash_duration_frames = 8
	player.set_movement_state(Player.MovementState.DASHING,8)
	for remaining in [8,6,4,2,1]:
		player.dash_phase_frames_remaining = remaining
		sprite.update_animation()
		check(sprite.animation == &"dash" and sprite.frame == 4 + clampi(int((1.0-remaining/8.0)*4),0,3), "Rush active pose mismatch")
		check(player.dash_phase_frames_remaining == remaining, "Animation changed dash clock")
	player.set_movement_state(Player.MovementState.RECOVERY,8)
	player.dash_recovery_frames = 8
	for remaining in [8,6,4,2,1]:
		player.dash_phase_frames_remaining = remaining
		sprite.update_animation()
		check(sprite.animation == &"dash" and sprite.frame >= 8 and sprite.frame <= 11, "Rush recovery pose mismatch")

func test_real_jump_landing_and_dash() -> void:
	await place()
	Input.action_press("Jump")
	await tick()
	sprite.update_animation()
	check(player.is_jump_charging() and sprite.animation == &"jump" and sprite.frame == 0, "Jump anticipation did not use first pose")
	await tick(player.jump_charge_frames)
	sprite.update_animation()
	check(sprite.animation == &"jump" and sprite.frame == 1 and player.velocity.y < 0, "Takeoff did not use green pose")
	Input.action_release("Jump")
	var before := impacts
	for frame in range(120):
		await tick()
		if impacts > before: break
	sprite.update_animation()
	check(impacts == before+1 and sprite.animation == &"jump" and sprite.frame == 5, "Landing did not use final pose")
	var x := player.position.x
	Input.action_press("Move Right")
	await tick()
	check(player.position.x > x, "Landing pose froze movement")
	await tick(sprite.landing_pose_frames+1)
	sprite.update_animation()
	check(sprite.animation == &"walk", "Landing pose did not return to locomotion")
	await place()
	Input.action_press("Action")
	await tick(2)
	sprite.update_animation()
	check(sprite.animation == &"dash" and sprite.frame <= 3, "Real charge did not select Rush")
	Input.action_press("Move Left")
	await tick(2)
	check(player.visuals.scale.x < 0 and sprite.flip_h, "Charge redirection lost normal source-facing convention")
	Input.action_release("Action")
	await tick(2)
	sprite.update_animation()
	check(player.movement_state == Player.MovementState.DASHING and sprite.animation == &"dash" and sprite.frame >= 4 and sprite.frame <= 7, "Real dash did not use Rush active frames")
	check(player.get_node("CollisionShape2D").scale == Vector2.ONE and player.get_node("Hurtbox").scale == Vector2.ONE, "Dash visuals flipped physics")

func test_slash_variants_and_hitstop() -> void:
	await place()
	var target := load("res://Tests/Scenes/Player/combat_dummy.tscn").instantiate() as CharacterBody2D
	target.position = Vector2(136,320)
	target.get_node("Damageable").max_health = 20
	world.add_child(target)
	player.combat.swing_freeze_frames = 2
	Input.action_press("Attack")
	await tick()
	check(sprite.animation == &"attack" and sprite.is_playing(), "First swing did not use Slash1")
	check(not sprite.flip_h and player.visuals.scale.x < 0, "Right Slash1 orientation incorrect")
	Input.action_release("Attack") # Verify one tapped swing independently of hold repetition.
	var saw_hitstop := false
	for frame in range(180):
		if not player.combat.is_attacking(): break
		if player.combat.is_hitstopped():
			saw_hitstop = true
			check(not sprite.is_playing(), "Slash hitstop advanced playback")
		if player.combat.attack_state == player.combat.AttackState.ACTIVE:
			check(sprite.frame >= 3 and sprite.frame <= 5, "Damage outside visible slash arc")
		await tick()
	check(not player.combat.is_attacking() and saw_hitstop and target.get_node("Damageable").health == 19, "Slash1 completion/one-hit/hitstop failed")
	Input.action_release("Attack")
	await tick()
	var left_target := load("res://Tests/Scenes/Player/combat_dummy.tscn").instantiate() as CharacterBody2D
	left_target.position = Vector2(56,320)
	left_target.get_node("Damageable").max_health = 20
	world.add_child(left_target)
	await tick(2)
	player._move_direction = -1
	player.update_facing_direction()
	Input.action_press("Attack")
	await tick()
	check(sprite.animation == &"attack_alt" and sprite.is_attack_animation(), "Independent second swing did not use Slash2")
	check(not sprite.flip_h and player.visuals.scale.x > 0, "Left Slash2 orientation incorrect")
	Input.action_release("Attack")
	for frame in range(180):
		if not player.combat.is_attacking(): break
		await tick()
	check(not player.combat.is_attacking(), "Slash2 completion did not release combat ownership")
	check(left_target.get_node("Damageable").health == 19, "Slash2 failed one-hit damage with its own frame clock")
	Input.action_release("Attack")
	await tick()
	Input.action_press("Attack")
	await tick()
	check(sprite.animation == &"attack", "Slash variants did not alternate on separate presses")
	player.damage.receive_hit(CombatHit.new())
	check(not player.combat.is_attacking(), "Damage did not interrupt new slash playback")
	target.queue_free()
	left_target.queue_free()

func run() -> void:
	world = Node2D.new()
	root.add_child(world)
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(0,336)
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(2000,32)
	collider.shape = shape
	floor_body.add_child(collider)
	world.add_child(floor_body)
	player = load("res://Scenes/Player/player.tscn").instantiate() as Player
	player.get_node("CombatController").mouse_aim_attacks = false
	player.position = Vector2(96,320)
	world.add_child(player)
	sprite = player.get_node("Visuals/AnimatedSprite2D")
	player.landed.connect(func(_speed: float): impacts += 1)
	await tick(3)
	test_assets_and_origins()
	await test_velocity_poses()
	test_rush_phases()
	await test_real_jump_landing_and_dash()
	await test_slash_variants_and_hitstop()
	release_inputs()
	world.queue_free()
	await process_frame
	print("Player animation: ",checks," checks; failures=",failures)
	quit(0 if failures == 0 else 1)
