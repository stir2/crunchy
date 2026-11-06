extends SceneTree
## Exercise takeoff/impact events through real physics, not simulated signal calls.
var failures: int = 0
var player: Player
var jumps: int = 0
var impacts: Array[float] = []

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

func place(y: float, speed: float = 0.0) -> void:
	Input.action_release("Jump")
	Input.action_release("Move Down")
	player.position = Vector2(240,y)
	player.reset_movement()
	player.velocity.y = speed

func await_landing() -> void:
	for frame in range(100):
		await tick()
		if player.is_on_floor():
			return
	check(false,"Timed out waiting for landing")

func run() -> void:
	var lab: Node2D = load("res://Scenes/Player/player_test.tscn").instantiate()
	root.add_child(lab)
	player = lab.get_node("Player") as Player
	player.jump_charge_frames = 6
	var effects: Node2D = player.get_node("MovementEffects")
	var camera: Camera2D = player.get_node("Camera2D")
	player.jumped.connect(func() -> void: jumps += 1)
	player.landed.connect(func(speed: float) -> void: impacts.append(speed))
	await tick(15)
	place(320)
	await tick(5)
	var initial_impacts := impacts.size()
	check(effects.get_child_count() == 0,"Respawn/standing created a burst")
	Input.action_press("Jump")
	await tick(2)
	check(jumps == 0 and effects.get_child_count() == 0,"Jump dust played during anticipation")
	await tick(6)
	check(jumps == 1,"Missing or duplicate takeoff event")
	var burst: AnimatedSprite2D = effects.get_node_or_null("JumpBurst")
	check(burst != null and burst.animation == &"jump" and burst.is_playing(),"Takeoff did not play jump sheet")
	if burst != null:
		check(burst.sprite_frames.get_frame_count(&"jump") == 10 and burst.sprite_frames.get_animation_speed(&"jump") == 24,"Incorrect sheet slicing or playback rate")
		var anchor := burst.global_position
		player.position.x += 40
		await tick(2)
		check(burst.global_position.is_equal_approx(anchor),"Jump dust followed the player")
	Input.action_release("Jump")
	await tick(65)
	check(not is_instance_valid(burst),"Completed burst leaked")

	place(280,200)
	await await_landing()
	check(impacts.size() > initial_impacts and impacts[-1] < camera.landing_shake_min_speed,"Gentle landing event/speed incorrect")
	check(camera.offset == Vector2.ZERO,"Gentle landing shook camera")
	var soft_burst: AnimatedSprite2D = effects.get_node_or_null("LandBurst")
	check(soft_burst != null and soft_burst.animation == &"land","Landing did not play land sheet")
	var before := impacts.size()
	await tick(8)
	check(impacts.size() == before,"Standing repeated landing effects")

	place(200,900)
	await await_landing()
	check(impacts.size() == before + 1 and impacts[-1] > camera.landing_shake_min_speed,"Hard landing lost incoming speed")
	check(camera.offset.length() > 0 and camera.offset.length() <= camera.landing_shake_pixels,"Hard landing shake absent or excessive")
	var resting := player.position
	await tick(30)
	check(camera.offset == Vector2.ZERO and not camera.is_processing(),"Camera shake did not settle")
	check(player.position.is_equal_approx(resting),"Shake affected player physics")
	place(200,900)
	await await_landing()
	player.reset_movement()
	check(camera.offset == Vector2.ZERO,"Reset retained camera shake")
	await tick()
	check(effects.get_child_count() == 0,"Reset retained dust")
	place(320)
	await tick(5)
	Input.action_press("Action")
	await tick(2)
	check(not camera.is_processing(),"Dash charge triggered launch shake early")
	Input.action_release("Action")
	await tick(2)
	check(camera.is_processing() and camera._shake_strength == camera.dash_shake_pixels,"Dash launch did not trigger configured shake")
	player.reset_movement()
	var hit := CombatHit.new()
	hit.amount = 1
	hit.direction = Vector2.LEFT
	check(player.damage.receive_hit(hit),"Feedback fixture rejected damage")
	check(camera.is_processing() and camera._shake_strength == camera.hurt_shake_pixels,"Successful damage did not trigger configured hurt shake")
	camera.reset_shake()
	check(not player.damage.receive_hit(hit) and not camera.is_processing(),"Ignored damage triggered hurt shake")
	camera.dash_shake_pixels = 0.0
	player.set_movement_state(Player.MovementState.DASHING,1)
	check(not camera.is_processing(),"Zero dash strength did not disable shake")
	# Short shakes must visibly alternate over multiple frames, including the
	# 60 FPS/0.1-second combination that sampled every horizontal sine at zero.
	for fps in [60,120]:
		camera.reset_shake()
		camera.start_shake(30.0,0.1,Vector2(1.0,0.35))
		var positive: int = 0
		var negative: int = 0
		for frame in range(fps/10):
			camera._process(1.0/fps)
			if camera.offset.x > 0.5: positive += 1
			if camera.offset.x < -0.5: negative += 1
		check(positive >= 2 and negative >= 2,"Dash shake disappeared across frames at %d FPS" % fps)
		camera._process(0.1)
		check(camera.offset == Vector2.ZERO and not camera.is_processing(),"Short shake did not finish cleanly")
	lab.free()
	print("Player feedback: delayed takeoff, world-space dust, cleanup, gentle/hard landing, camera-only shake and reset; failures=",failures)
	quit(1 if failures else 0)
