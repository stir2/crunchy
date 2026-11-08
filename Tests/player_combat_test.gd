extends SceneTree
## Real physics, input edges, animation frames and damage components in the lab.
const DUMMY = preload("res://Tests/Scenes/Player/combat_dummy.tscn")
var failures: int = 0
var checks: int = 0
var lab: Node2D
var player: Player
var combat: PlayerCombatController
var sprite: AnimatedSprite2D
var targets: Array[CharacterBody2D] = []
var hits: Array[CombatHit] = []
var stops: Array[int] = []
var swing_freezes: Array[int] = []
var phases: Array[int] = []
var dash_states: Array[int] = []
var last_finish_tick: int = -1
var last_dash_tick: int = -1
var last_finish_frame: int = -1
var last_finish_interrupted: bool = false

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func tick(count: int = 1) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame

func release_inputs() -> void:
	for action in ["Move Left", "Move Right", "Move Down", "Move Up", "Jump", "Attack", "Action"]:
		Input.action_release(action)

func place(position: Vector2 = Vector2(2700,320), speed: Vector2 = Vector2.ZERO, facing: int = 1) -> void:
	release_inputs()
	for target in targets:
		target.queue_free()
	targets.clear()
	player.position = position
	player.reset_movement()
	player.stamina.reset_stamina()
	player.velocity = speed
	player._move_direction = facing
	player.update_facing_direction()
	combat.actions_enabled = true
	combat.repeat_while_held = false # Isolate explicit-click regression fixtures.
	combat.active_start_frame = 4
	combat.active_end_frame = 7
	combat.hitstop_frames = 3
	combat.swing_freeze_frames = 3
	combat.swing_speed_boost = 0.0 # Isolate existing checks from optional compensation.
	combat.swing_burst_speed = 0.0
	combat.swing_speed_boost_frames = 8
	combat.attack_movement_speed_multiplier = 0.65
	combat.attack_jump_multiplier = 1.0 # Existing jump fixtures retain their full arc.
	combat.dash_recovery_lock_frames = 2
	combat.attack_cancel_start_frame = 10
	combat.attack_damage = 1
	await tick(2)
	hits.clear()
	stops.clear()
	swing_freezes.clear()
	phases.clear()
	dash_states.clear()
	last_finish_tick = -1
	last_dash_tick = -1
	last_finish_frame = -1
	last_finish_interrupted = false

func target_at(position: Vector2) -> CharacterBody2D:
	var target := DUMMY.instantiate() as CharacterBody2D
	target.position = position
	target.auto_reset_seconds = 0.0
	target.get_node("Damageable").max_health = 20
	lab.add_child(target)
	targets.append(target)
	return target

func health(target: CharacterBody2D) -> int:
	return target.get_node("Damageable").health

func wait_phase(phase: int) -> void:
	for frame in range(100):
		if combat.attack_state == phase:
			return
		await tick()
	check(false,"Timed out waiting for phase " + str(phase))

func wait_end() -> void:
	for frame in range(100):
		if not combat.is_attacking():
			return
		check(player.movement_state == Player.MovementState.NORMAL,"Dash canceled an active attack/recovery")
		await tick()
	check(false,"Attack did not complete")

func press_attack() -> void:
	Input.action_press("Attack")
	await tick()
	check(combat.is_attacking(),"Attack press did not start swing")

func test_swing_freeze() -> void:
	await place(Vector2(2700,-200),Vector2(90,100))
	await press_attack()
	for frame in range(40):
		if combat.is_swing_frozen(): break
		await tick()
	check(combat.is_swing_frozen() and not combat.is_hitstopped(),"Swing did not start independent freeze")
	check(sprite.frame == combat.active_start_frame - 1 and not sprite.is_playing(),"Swing freeze held the wrong pose")
	check(combat.attack_state == combat.AttackState.WINDUP and combat.hit_shape.disabled,"Swing freeze enabled damage")
	check(swing_freezes == [3],"Swing did not request exactly three freeze ticks")
	var position := player.position
	var velocity := player.velocity
	var progress := sprite.frame_progress
	player.dash_cooldown_frames_remaining = 9
	# Native frame_changed can run before this coroutine observes the first frozen
	# physics tick. Verify the remaining ticks rather than adding three more.
	var remaining: int = combat._swing_freeze_ticks_left
	for frame in range(remaining):
		if frame == 0:
			Input.action_press("Action")
			Input.action_press("Jump")
		if frame == 1: Input.action_release("Jump")
		await tick()
		check(player.position.is_equal_approx(position) and player.velocity == velocity,"Swing freeze changed momentum/position")
		check(sprite.frame == combat.active_start_frame - 1 and is_equal_approx(sprite.frame_progress,progress),"Swing freeze advanced animation")
		check(player.dash_cooldown_frames_remaining == 9,"Swing freeze advanced movement timers")
	check(combat.buffered_dash and stops.is_empty() and not paused,"Swing freeze lost dash input or triggered contact hitstop")
	await tick()
	check(not combat.is_swing_frozen() and player.position.y > position.y and player.velocity.y > velocity.y,"Swing failed to resume falling")
	check(player.jump_buffer_frames_remaining > 0,"Swing freeze lost short jump input")
	await wait_end()
	check(swing_freezes.size() == 1,"Swing freeze repeated during the same attack")
	await tick()
	check(player.movement_state == Player.MovementState.DASH_CHARGING,"Swing freeze lost buffered dash after recovery")
	await place()
	combat.swing_freeze_frames = 0
	await press_attack()
	while combat.is_attacking():
		check(not combat.is_swing_frozen(),"Zero setting did not disable swing freeze")
		await tick()
	await place()
	await press_attack()
	for frame in range(40):
		if combat.is_swing_frozen():break
		await tick()
	combat.interrupt()
	await tick()
	check(not combat.is_swing_frozen() and not combat.is_attacking() and sprite.is_playing(),"Interruption retained swing freeze")

func test_swing_speed_boost() -> void:
	for facing in [-1,1]:
		await place(Vector2(3550,320),Vector2(player.run_speed * facing,0),facing)
		combat.attack_movement_speed_multiplier = 1.0
		combat.swing_speed_boost = 60.0
		Input.action_press("Move Left" if facing < 0 else "Move Right")
		await tick(4)
		await press_attack()
		for frame in range(40):
			if combat.is_swing_frozen():break
			await tick()
		check(combat.movement_speed_bonus() == 0,"Boost started before freeze ended")
		while combat.is_swing_frozen():
			await tick()
		check(combat.movement_speed_bonus() == 60 and absf(player.velocity.x) > player.run_speed,"Post-freeze speed boost missing")
		var settling_ticks := ceili(60.0 * Engine.physics_ticks_per_second / player.ground_acceleration) + 1
		await tick(settling_ticks)
		check(is_equal_approx(player.velocity.x,(player.run_speed + 60) * facing),"Boost did not follow held movement direction")
		check(is_zero_approx(player.velocity.y),"Horizontal boost changed vertical motion")
		while combat._swing_speed_boost_ticks_left > 0:
			await tick()
		await tick(settling_ticks)
		check(combat.movement_speed_bonus() == 0 and is_equal_approx(absf(player.velocity.x),player.run_speed),"Boost failed to expire back to normal speed")
	await place(Vector2(3550,320))
	combat.swing_speed_boost = 60
	await press_attack()
	for frame in range(40):
		if combat.is_swing_frozen():break
		await tick()
	while combat.is_swing_frozen():
		await tick()
	check(combat.movement_speed_bonus() > 0 and is_zero_approx(player.velocity.x),"Boost shoved a stationary player")
	combat.interrupt()
	check(combat.movement_speed_bonus() == 0,"Interruption retained speed boost")
	# A successful hit pauses the remaining boost duration, without reapplying it.
	await place()
	combat.swing_speed_boost = 60
	target_at(Vector2(2740,320))
	await tick(2)
	await press_attack()
	for frame in range(45):
		if combat.is_hitstopped():break
		await tick()
	var remaining: int = combat._swing_speed_boost_ticks_left
	check(remaining > 0 and remaining < 8,"Contact fixture missed boost window")
	await tick(3)
	check(combat._swing_speed_boost_ticks_left == remaining,"Hitstop consumed boost duration")
	await tick()
	check(combat._swing_speed_boost_ticks_left == remaining - 1,"Contact hitstop restarted swing boost")
	player.reset_movement()
	check(combat.movement_speed_bonus() == 0,"Respawn retained boost")
	await place()
	combat.swing_speed_boost = 60
	combat.swing_speed_boost_frames = 60
	await press_attack()
	Input.action_press("Action")
	await tick()
	await wait_end()
	await tick()
	check(player.movement_state == Player.MovementState.DASH_CHARGING and combat.movement_speed_bonus() == 0,"Boost leaked into dash cancel")
	await place()
	await press_attack()
	while combat.is_attacking():
		check(combat.movement_speed_bonus() == 0,"Zero boost setting failed to disable compensation")
		await tick()

func test_swing_burst() -> void:
	for facing in [-1,1]:
		for steering in [-1,0,1]:
			await place(Vector2(2700,320),Vector2.ZERO,facing)
			combat.swing_burst_speed = 100.0
			await press_attack()
			Input.action_release("Attack")
			if steering != 0:
				Input.action_press("Move Right" if steering > 0 else "Move Left")
			var before := player.position.x
			await wait_phase(combat.AttackState.ACTIVE)
			if not combat._swing_burst_used:
				await tick()
			check(combat._swing_burst_used,"Swing did not resolve its one burst opportunity")
			if steering == facing:
				var minimum := player.run_speed*combat.attack_movement_speed_multiplier+100.0
				check(player.velocity.x*facing >= minimum-1.0 and (player.position.x-before)*facing > 0.0,"Matching direction did not burst forward")
			else:
				check(absf(player.velocity.x) <= player.run_speed*combat.attack_movement_speed_multiplier+1.0,"Neutral/opposite input triggered a swing burst")
			check(combat.consume_swing_burst() == 0.0,"Burst repeated within one swing")
	# Airborne burst affects only horizontal momentum, with normal gravity.
	await place(Vector2(2700,-600),Vector2(0,100))
	combat.swing_burst_speed = 100.0
	await press_attack()
	Input.action_release("Attack")
	Input.action_press("Move Right")
	await wait_phase(combat.AttackState.ACTIVE)
	var falling_speed := player.velocity.y
	await tick()
	check(player.velocity.x > player.run_speed*combat.attack_movement_speed_multiplier and player.velocity.y > falling_speed,"Air burst failed or changed vertical physics")
	player.reset_movement()
	check(combat.consume_swing_burst() == 0.0,"Reset retained a burst")

func test_attack_jump_multiplier() -> void:
	var launches: Array[float] = []
	var on_jump := func() -> void: launches.append(player.velocity.y)
	player.jumped.connect(on_jump)
	for charge in [0,5]:
		for attacking in [false,true]:
			await place()
			launches.clear()
			player.jump_charge_frames = charge
			combat.attack_jump_multiplier = 0.5
			combat.swing_freeze_frames = 0
			if attacking:
				await press_attack()
				Input.action_release("Attack")
			Input.action_press("Jump")
			await tick(8)
			var expected := player.jump_velocity*(0.5 if attacking else 1.0)
			check(launches.size() == 1 and is_equal_approx(launches[0],expected),"Combat jump multiplier changed normal jumps or failed at charge %d" % charge)
	# The jump keeps its reserved multiplier if the swing ends during charge;
	# an early button release still produces the existing shorter jump.
	await place()
	launches.clear()
	player.jump_charge_frames = 5
	combat.attack_jump_multiplier = 0.5
	combat.swing_freeze_frames = 0
	await press_attack()
	Input.action_release("Attack")
	Input.action_press("Jump")
	await tick()
	Input.action_release("Jump")
	combat.interrupt()
	await tick(8)
	check(launches.size() == 1 and is_equal_approx(launches[0],player.jump_velocity*0.5*player.jump_release_multiplier),"Attack jump lost charge snapshot or variable-height release")
	player.jumped.disconnect(on_jump)
	player.jump_charge_frames = 5

func test_phases_and_input() -> void:
	await place()
	check(sprite.sprite_frames.get_frame_count(&"attack") == 17 and sprite.sprite_frames.get_animation_speed(&"attack") == 24 and not sprite.sprite_frames.get_animation_loop(&"attack"),"Wrong attack asset/rate/loop")
	await press_attack()
	check(combat.attack_state == combat.AttackState.WINDUP and sprite.is_attack_animation(), "Attack did not begin in windup")
	check(not combat.hitbox.monitoring and combat.hit_shape.disabled,"Windup hitbox enabled")
	await wait_phase(combat.AttackState.ACTIVE)
	await tick()
	check(sprite.frame >= 4 and sprite.frame <= 7 and combat.hitbox.monitoring and not combat.hit_shape.disabled,"Active hitbox does not match frames 4-7")
	await wait_phase(combat.AttackState.RECOVERY)
	await tick()
	check(sprite.frame >= 8 and not combat.hitbox.monitoring and combat.hit_shape.disabled,"Recovery hitbox enabled")
	await wait_end()
	check(phases.has(combat.AttackState.WINDUP) and phases.has(combat.AttackState.ACTIVE) and phases.has(combat.AttackState.RECOVERY),"Missing attack phase")
	check(stops.is_empty(),"Miss triggered hitstop")
	var serial := combat.swing_id
	await tick(40)
	check(combat.swing_id == serial and not combat.is_attacking(),"Holding Attack repeated swing")
	Input.action_release("Attack")
	await tick()
	await press_attack()
	check(combat.swing_id == serial + 1,"Release/repress failed")
	# Early recovery clicks are ignored, including holding through the unlock.
	Input.action_release("Attack")
	await wait_phase(combat.AttackState.RECOVERY)
	Input.action_press("Attack")
	await tick()
	check(combat.swing_id == serial+1,"Early recovery click canceled the current swing")
	await wait_end()
	await tick(40)
	check(combat.swing_id == serial+1,"Early recovery click was queued or holding repeated swings")
	await place()
	combat.active_start_frame = 2
	combat.active_end_frame = 3
	await press_attack()
	await wait_phase(combat.AttackState.ACTIVE)
	check(sprite.frame in [2,3],"Inspector phase boundary ignored")
	await wait_phase(combat.AttackState.RECOVERY)
	check(sprite.frame == 4,"Configured recovery boundary ignored")

func test_recovery_cancel() -> void:
	await place()
	await press_attack()
	Input.action_release("Attack")
	await wait_phase(combat.AttackState.RECOVERY)
	check(sprite.speed_scale == 1.0,"Recovery animation did not keep normal playback speed")
	check(not combat.can_attack_cancel(),"Recovery canceled before configured frame")
	var serial := combat.swing_id
	for frame in range(30):
		if sprite.frame >= combat.attack_cancel_start_frame: break
		await tick()
	check(combat.can_attack_cancel(),"Configured attack cancel frame did not unlock")
	var old_animation := sprite.animation
	Input.action_press("Attack")
	await tick()
	check(combat.swing_id == serial+1 and combat.attack_state == combat.AttackState.WINDUP,"Recovery click did not immediately restart swing")
	check(last_finish_interrupted and last_finish_frame == 10,"Attack restart failed to interrupt at configured frame")
	check(sprite.frame == 0 and sprite.animation != old_animation and sprite.speed_scale == 1.0,"Restart failed to reset animation or alternate slash")
	check(not combat.hitbox.monitoring and combat.hit_shape.disabled,"Restart retained active hitbox")
	await wait_end()
	await tick(40)
	check(combat.swing_id == serial+1,"Holding Attack after cancel repeated swings")
	# Even frame zero never permits windup/active cancellation.
	await place()
	combat.attack_cancel_start_frame = 0
	await press_attack()
	Input.action_release("Attack")
	await tick()
	Input.action_press("Attack")
	await tick()
	serial = combat.swing_id
	check(not combat.can_attack_cancel(),"Windup was attack-cancelable")
	Input.action_release("Attack")
	await wait_phase(combat.AttackState.ACTIVE)
	Input.action_press("Attack")
	await tick()
	check(combat.swing_id == serial and not combat.can_attack_cancel(),"Active damage frames were attack-cancelable")
	Input.action_release("Attack")
	await wait_phase(combat.AttackState.RECOVERY)
	check(combat.can_attack_cancel(),"Frame zero did not enable cancellation from first recovery frame")
	# A frame beyond the animation disables cancel; clicks never queue.
	combat.attack_cancel_start_frame = 17
	Input.action_press("Attack")
	await tick()
	Input.action_release("Attack")
	await wait_end()
	await tick(10)
	check(combat.swing_id == serial,"Disabled cancel queued another swing")
	# Respawn clears the current swing and guards held input.
	await place()
	await press_attack()
	serial = combat.swing_id
	player.reset_movement()
	await tick(100)
	check(combat.swing_id == serial and not combat.is_attacking(),"Reset retained/restarted a swing")

func test_held_attacks() -> void:
	await place()
	combat.repeat_while_held = true
	await press_attack()
	var serial := combat.swing_id
	for repeat_index in range(3):
		for frame in range(100):
			if combat.swing_id > serial: break
			await tick()
		check(combat.swing_id == serial+1 and combat.attack_state == combat.AttackState.WINDUP,"Held Attack failed to repeat from recovery")
		check(last_finish_interrupted and last_finish_frame == combat.attack_cancel_start_frame,"Held Attack bypassed the configured recovery frame")
		check(sprite.speed_scale == 1.0 and not combat.hitbox.monitoring,"Repeated attack changed playback or retained damage hitbox")
		serial = combat.swing_id
	Input.action_release("Attack")
	await wait_end()
	await tick(40)
	check(combat.swing_id == serial,"Release failed to stop repeated attacks")
	# With cancellation disabled, hold still repeats after the complete animation.
	await place()
	combat.repeat_while_held = true
	combat.attack_cancel_start_frame = 17
	await press_attack()
	serial = combat.swing_id
	for frame in range(110):
		if combat.swing_id > serial: break
		await tick()
	check(combat.swing_id == serial+1 and not last_finish_interrupted and last_finish_frame == 16,"Held Attack failed to respect full recovery")
	# Buffered dash wins over automatic repetition, and stays a dash while held.
	Input.action_press("Action")
	await tick()
	serial = combat.swing_id
	for frame in range(110):
		if player.movement_state == Player.MovementState.DASH_CHARGING: break
		await tick()
	check(player.movement_state == Player.MovementState.DASH_CHARGING,"Held Attack starved a buffered dash")
	await tick(3)
	check(combat.swing_id == serial and not combat.is_attacking(),"Held Attack automatically canceled a buffered dash")
	player.reset_movement()
	await tick(100)
	check(combat.swing_id == serial and not combat.is_attacking(),"Reset failed to guard held Attack")
	Input.action_release("Attack")
	await tick()
	await press_attack()
	check(combat.swing_id == serial+1,"Release/repress after reset did not restore attacks")

func test_movement_and_lock() -> void:
	await place(Vector2(2700,320),Vector2(170,0))
	Input.action_press("Move Right")
	var before := player.velocity.x
	await press_attack()
	check(player.velocity.x > 0.0 and player.velocity.x <= before,"Attack abruptly zeroed or boosted momentum")
	await tick(5)
	check(is_equal_approx(player.velocity.x,player.run_speed * 0.65),"Attack movement multiplier missing")
	Input.action_release("Move Right")
	Input.action_press("Move Left")
	await tick(8)
	check(player.velocity.x < 0 and player.facing_direction == 1 and combat.locked_facing == 1,"Steering changed locked facing")
	check(not sprite.flip_h and player.visuals.scale.x < 0 and player.attack_pivot.scale.x > 0,"Right swing did not flip source art/lock hitbox")
	check(player.get_node("CollisionShape2D").scale == Vector2.ONE and player.get_node("Hurtbox").scale == Vector2.ONE,"Attack flipped physical shapes")
	await wait_end()
	await tick(10)
	check(is_equal_approx(player.velocity.x,-player.run_speed) and player.facing_direction == -1 and sprite.flip_h,"Movement/facing failed to restore")
	await place(Vector2(2700,100),Vector2(0,-180))
	var rising_y := player.position.y
	var rising_speed := player.velocity.y
	await press_attack()
	await tick(4)
	check(player.position.y < rising_y and player.velocity.y > rising_speed and player.velocity.y < 0,"Rising attack froze or changed gravity")
	check(sprite.is_attack_animation() and sprite.is_playing(),"Air animation overrode attack")
	await place(Vector2(2700,60),Vector2(0,100))
	Input.action_press("Move Down")
	var falling_y := player.position.y
	await press_attack()
	await tick(4)
	check(player.position.y > falling_y and player.velocity.y >= player.fast_fall_speed,"Falling/fast-falling attack failed")
	await place()
	Input.action_press("Jump")
	await tick()
	check(player.is_jump_charging(),"Jump test failed to charge")
	Input.action_press("Attack")
	await tick()
	check(not combat.is_attacking(),"Attack interrupted jump charge")
	# Jump input after an attack starts still uses the original charged jump.
	await place()
	await press_attack()
	Input.action_press("Jump")
	await tick()
	check(player.is_jump_charging() and combat.is_attacking(),"Attack blocked grounded charged jump")
	await tick(player.jump_charge_frames + 1)
	check(player.velocity.y < 0 and combat.is_attacking(),"Jump during swing failed to launch")
	await place(Vector2(3700,320))
	Input.action_press("Move Right")
	await press_attack()
	await tick(20)
	check(player.is_on_wall() and player.position.x <= 3713.1,"Attack bypassed normal wall collision")

func test_hits_and_stop() -> void:
	await place()
	var right := target_at(Vector2(2740,320))
	var second := target_at(Vector2(2747,320))
	var left := target_at(Vector2(2660,320))
	var outside := target_at(Vector2(2780,320))
	var ignored := target_at(Vector2(2735,320))
	ignored.get_node("Damageable").collision_layer = 8
	await tick(2)
	await press_attack()
	for frame in range(45):
		if not hits.is_empty(): break
		if combat.attack_state == combat.AttackState.WINDUP:
			check(health(right) == 20,"Damage during windup")
		await tick()
	check(health(right) == 19 and health(second) == 19 and hits.size() == 2,"Swing missed pre-existing overlap or multiple targets")
	check(health(left) == 20 and health(outside) == 20 and health(ignored) == 20,"Wrong side/range/layer received damage")
	check(stops == [3] and combat.is_hitstopped() and not sprite.is_playing(),"Successful hit did not start one three-tick hitstop")
	check(hits[0].source == player and hits[0].amount == 1 and hits[0].direction == Vector2.RIGHT,"Damage payload incorrect")
	check(right.velocity.x > 0 and right.velocity.y < 0 and right._flash_left > 0,"Knockback or hit flash missing")
	var position := player.position
	var velocity := player.velocity
	var enemy_position := right.position
	var frame_index := sprite.frame
	var progress := sprite.frame_progress
	var camera: Camera2D = player.get_node("Camera2D")
	camera._on_landed(900) # The existing camera feedback must keep processing.
	var camera_before := camera.offset
	left.velocity.x = -100
	var unrelated_position := left.position
	player.dash_cooldown_frames_remaining = 9
	for index in range(3):
		if index == 0: Input.action_press("Jump")
		if index == 1: Input.action_release("Jump")
		await tick()
		check(player.position.is_equal_approx(position) and player.velocity == velocity,"Hitstop lost player motion state")
		check(right.position.is_equal_approx(enemy_position),"Hitstop moved struck enemy")
		check(sprite.frame == frame_index and is_equal_approx(sprite.frame_progress,progress),"Hitstop advanced sprite/phase")
		check(player.dash_cooldown_frames_remaining == 9,"Hitstop advanced movement timer")
		check(hits.size() == 2,"Hitstop repeated damage")
	check(not paused and Engine.time_scale == 1.0,"Hitstop paused/scaled the entire world")
	check(left.position.x < unrelated_position.x and not left.get_node("Damageable").is_hitstopped(),"Hitstop froze an unrelated enemy")
	check(not camera.offset.is_equal_approx(camera_before),"Hitstop froze camera feedback")
	await tick()
	check(player.is_jump_charging(),"Short jump press during hitstop was lost")
	await tick(player.jump_charge_frames + 1)
	check(player.velocity.y < 0,"Buffered hitstop jump did not launch")
	await wait_end()
	check(health(right) == 19 and health(second) == 19 and stops.size() == 1,"Swing dealt repeated damage/hitstop")
	await tick(8)
	check(not combat.hitbox.monitoring and not combat.is_hitstopped(),"Attack failed to shut down hitbox/hitstop")
	await place(Vector2(2700,320),Vector2.ZERO,-1)
	left = target_at(Vector2(2660,320))
	right = target_at(Vector2(2740,320))
	combat.attack_damage = 2
	await tick(2)
	await press_attack()
	check(not sprite.flip_h and player.visuals.scale.x > 0,"Left swing did not use unflipped source")
	await wait_end()
	check(health(left) == 18 and health(right) == 20 and hits.size() == 1,"Left-facing hit or configurable damage incorrect")
	# Damage confirmation/death and resetting are reusable, not tied to attack timing.
	var death_count: Array[int] = []
	left.get_node("Damageable").died.connect(func(_hit: CombatHit) -> void: death_count.append(1))
	var hit := CombatHit.new()
	hit.source = player
	hit.amount = 99
	check(left.get_node("Damageable").receive_hit(hit),"Reusable damage interface rejected valid hit")
	check(death_count.size() == 1 and health(left) == 0,"Death notification incorrect")
	check(not left.get_node("Damageable").receive_hit(hit) and death_count.size() == 1,"Dead target accepted more damage")
	left.reset_dummy()
	check(health(left) == 20 and left.get_node("Damageable").collision_layer == 32,"Dummy reset failed")
	# Vertical overlap comes from the configured 42px rectangle, not separate attacks.
	for height in [-28,28]:
		await place(Vector2(2700,320))
		var target := target_at(Vector2(2740,320 + height))
		target.set_physics_process(false)
		combat.hitstop_frames = 0
		await tick(2)
		await press_attack()
		await wait_end()
		check(health(target) == 19,"Slightly raised/lowered hurtbox not reached: " + str(height))
		check(stops.is_empty(),"Zero hitstop setting still froze the attack")
	await place()
	var invulnerable := target_at(Vector2(2740,320))
	invulnerable.get_node("Damageable").invulnerable = true
	await tick(2)
	await press_attack()
	await wait_end()
	check(health(invulnerable) == 20 and hits.is_empty() and stops.is_empty(),"Rejected hit dealt damage or caused hitstop")
	# Even a damageable area on the enemy layer cannot make the player self-hit.
	await place()
	var self_hurtbox := CombatDamageable.new()
	self_hurtbox.position = Vector2(30,-18)
	self_hurtbox.collision_layer = 32
	self_hurtbox.collision_mask = 0
	var self_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(20,42)
	self_shape.shape = rectangle
	self_hurtbox.add_child(self_shape)
	player.add_child(self_hurtbox)
	await tick(2)
	await press_attack()
	await wait_end()
	check(self_hurtbox.health == self_hurtbox.max_health and hits.is_empty(),"Attack damaged its source")
	self_hurtbox.queue_free()

func test_dash_buffers() -> void:
	for phase in [combat.AttackState.WINDUP,combat.AttackState.ACTIVE,combat.AttackState.RECOVERY]:
		await place()
		await press_attack()
		await wait_phase(phase)
		Input.action_press("Action")
		await tick()
		check(combat.buffered_dash and player.movement_state == Player.MovementState.NORMAL,"Dash not buffered in phase " + str(phase))
		await wait_end()
		await tick()
		check(player.movement_state == Player.MovementState.DASH_CHARGING and not combat.buffered_dash,"Buffered dash did not use existing charge")
		check(last_dash_tick >= last_finish_tick and last_finish_frame == 10,"Buffered dash missed the late-recovery cancel window")
		Input.action_release("Action")
		await tick()
		check(player.movement_state == Player.MovementState.DASHING,"Buffered charge failed to launch")
	# Releasing before the cancel window removes the request in every phase.
	for phase in [combat.AttackState.WINDUP,combat.AttackState.ACTIVE,combat.AttackState.RECOVERY]:
		await place()
		await press_attack()
		await wait_phase(phase)
		Input.action_press("Action")
		await tick()
		check(combat.buffered_dash,"Dash cancellation fixture failed to buffer")
		Input.action_release("Action")
		await tick()
		check(not combat.buffered_dash,"Released Action retained its queued dash")
		await wait_end()
		await tick(3)
		check(not dash_states.has(Player.MovementState.DASH_CHARGING) and not dash_states.has(Player.MovementState.DASHING),"Released dash produced a phantom charge/launch")
		check(player.stamina.current_stamina == player.stamina.max_stamina and player.dash_available,"Canceled request spent stamina or aerial dash")
	# Release must also be observed while local freeze pauses attack progression.
	for contact in [false,true]:
		await place()
		combat.swing_freeze_frames = 8
		if contact: target_at(Vector2(2740,320))
		await press_attack()
		for frame in range(60):
			if (combat.is_hitstopped() if contact else combat.is_swing_frozen()): break
			await tick()
		Input.action_press("Action")
		await tick()
		Input.action_release("Action")
		await tick()
		check(not combat.buffered_dash,"Local freeze retained released dash input")
		await wait_end()
		await tick(3)
		check(not dash_states.has(Player.MovementState.DASH_CHARGING),"Freeze released request started dash charge")
	for cooldown in [false,true]:
		await place(Vector2(2700,-600))
		await press_attack()
		if cooldown: player.dash_cooldown_frames_remaining = 200
		else: player.dash_available = false
		Input.action_press("Action")
		await tick()
		await wait_end()
		await tick()
		check(player.movement_state == Player.MovementState.NORMAL and not combat.buffered_dash,"Ineligible buffered dash was not discarded")
		player.dash_cooldown_frames_remaining = 0
		player.dash_available = true
		await tick(3)
		check(player.movement_state == Player.MovementState.NORMAL,"Discarded dash launched later")
	# Hitstop delays both the attack clock and the buffered dash.
	await place()
	target_at(Vector2(2740,320))
	await tick(2)
	await press_attack()
	for frame in range(40):
		if combat.is_hitstopped(): break
		await tick()
	check(combat.is_hitstopped(),"Buffer hitstop fixture missed")
	Input.action_press("Action")
	await tick()
	check(combat.buffered_dash and player.movement_state == Player.MovementState.NORMAL,"Hitstop lost dash press")
	await wait_end()
	await tick()
	check(player.movement_state == Player.MovementState.DASH_CHARGING and last_dash_tick >= last_finish_tick and last_finish_frame == 10,"Hitstop buffered dash started before late recovery or disappeared")

func test_action_cancels() -> void:
	for airborne in [false,true]:
		for phase in [Player.MovementState.DASH_CHARGING,Player.MovementState.DASHING]:
			await place(Vector2(2700,-500 if airborne else 320))
			Input.action_press("Action")
			await tick()
			if phase == Player.MovementState.DASHING:
				Input.action_release("Action")
				await tick(3)
			check(player.movement_state == phase,"Dash-to-swing phase fixture failed")
			var incoming := player.velocity
			var serial := combat.swing_id
			await press_attack()
			check(player.movement_state == Player.MovementState.NORMAL and combat.attack_state == combat.AttackState.WINDUP,"Attack failed to cancel dash/charge")
			check(player.dash_phase_frames_remaining == 0,"Canceled dash kept its phase timer")
			if player.dash_cooldown_frames > 0:
				check(player.dash_cooldown_frames_remaining > 0,"Dash cancellation skipped cooldown")
			if phase == Player.MovementState.DASHING:
				check(player.velocity.x > 0 and player.velocity.x <= incoming.x,"Dash-to-swing discarded horizontal momentum")
			if airborne:
				check(not player.dash_available,"Dash cancellation refunded aerial dash")
				Input.action_release("Action")
				await tick()
				Input.action_press("Action")
				await tick()
			await wait_end()
			await tick(3)
			check(combat.swing_id == serial + 1,"Held Attack repeated after dash cancellation")
			check(player.movement_state == Player.MovementState.NORMAL,"Old held Action restarted dash or aerial budget was bypassed")
	# A fresh press at frame 10 immediately cancels only the late recovery.
	await place()
	await press_attack()
	check(not combat.can_dash_cancel(),"Windup was dash-cancelable")
	await wait_phase(combat.AttackState.ACTIVE)
	check(not combat.can_dash_cancel(),"Active frames were dash-cancelable")
	await wait_phase(combat.AttackState.RECOVERY)
	check(not combat.can_dash_cancel(),"Early recovery was dash-cancelable")
	while sprite.frame < 10:
		await tick()
	check(combat.can_dash_cancel(),"Late recovery cancel window missing")
	Input.action_press("Action")
	await tick()
	check(player.movement_state == Player.MovementState.DASH_CHARGING and last_finish_frame == 10 and last_finish_interrupted,"Late recovery press did not cancel into dash charge")
	check(combat.hit_shape.disabled and not combat.hitbox.monitoring,"Recovery cancel left hitbox active")
	# A failed request must leave recovery running, not cancel the swing for free.
	for cooldown in [false,true]:
		await place(Vector2(2700,-600))
		await press_attack()
		if cooldown: player.dash_cooldown_frames_remaining = 200
		else: player.dash_available = false
		await wait_phase(combat.AttackState.RECOVERY)
		Input.action_press("Action")
		await tick()
		for frame in range(15):
			if sprite.frame >= 10 and not combat.buffered_dash:break
			await tick()
		check(combat.attack_state == combat.AttackState.RECOVERY and not combat.buffered_dash,"Ineligible cancel interrupted recovery or retained request")
		await wait_end()
		check(not last_finish_interrupted and last_finish_frame == 16,"Ineligible cancel cut the swing short")
	# Inspector controls support both full recovery and the whole recovery window.
	for lock_frames in [17,0]:
		await place()
		combat.dash_recovery_lock_frames = lock_frames
		await press_attack()
		await wait_phase(combat.AttackState.RECOVERY)
		Input.action_press("Action")
		await tick()
		await wait_end()
		await tick()
		check(player.movement_state == Player.MovementState.DASH_CHARGING,"Configured cancel did not start charge")
		check(last_finish_frame == (16 if lock_frames == 17 else 8),"Inspector recovery lock ignored")
		check(last_finish_interrupted == (lock_frames == 0),"Natural finish/cancel distinction lost")
	# Count from recovery, even when the authored active period changes.
	for last_active in [3,5,7]:
		await place()
		combat.active_start_frame = 2
		combat.active_end_frame = last_active
		combat.dash_recovery_lock_frames = 3
		await press_attack()
		Input.action_release("Attack")
		Input.action_press("Action")
		await tick()
		for frame in range(100):
			if not combat.is_attacking(): break
			check(player.movement_state == Player.MovementState.NORMAL,"Dash bypassed protected recovery")
			await tick()
		check(last_finish_interrupted and last_finish_frame == last_active+1+3,"Dash lock did not count completed recovery frames")
		check(player.movement_state == Player.MovementState.DASH_CHARGING,"Recovery cancel bypassed existing dash charge")

func test_dash_swing_jump_air_dash() -> void:
	# A grounded dash spent the previous budget. A legal ground-derived jump must
	# start a fresh airtime even when it is reserved during a swing or local freeze.
	for dash_phase in [Player.MovementState.DASH_CHARGING,Player.MovementState.DASHING]:
		for jump_timing in ["windup","swing_freeze","hitstop"]:
			await place(Vector2(3550,320))
			combat.swing_freeze_frames = 6
			combat.swing_speed_boost = 80
			combat.attack_movement_speed_multiplier = 1.0
			Input.action_press("Action")
			await tick()
			if dash_phase == Player.MovementState.DASHING:
				Input.action_release("Action")
				await tick(3)
			check(player.movement_state == dash_phase,"Dash/swing/jump fixture did not dash")
			if jump_timing == "hitstop":
				target_at(player.position + Vector2(52,0))
			await press_attack()
			check(not player.dash_available,"Dash cancel incorrectly refunded airtime before jump")
			Input.action_release("Action")
			if jump_timing != "windup":
				for frame in range(60):
					if (jump_timing == "swing_freeze" and combat.is_swing_frozen()) or (jump_timing == "hitstop" and combat.is_hitstopped()):break
					await tick()
				check(combat.is_swing_frozen() if jump_timing == "swing_freeze" else combat.is_hitstopped(),"Jump timing fixture missed freeze")
			var cooldown_before_jump := player.dash_cooldown_frames_remaining
			Input.action_press("Jump")
			await tick()
			if jump_timing == "windup":
				check(player.is_jump_charging() and player.dash_cooldown_frames_remaining == maxi(0,cooldown_before_jump - 1),"Ground jump bypassed the remaining cooldown")
			for frame in range(45):
				await tick()
				if player.velocity.y < 0 and not player.is_jump_charging():break
			check(player.velocity.y < 0 and not player.is_on_floor(),"Swing-buffered ground jump failed to launch")
			check(player.dash_available,"Legal ground jump failed to restore fresh aerial dash")
			await wait_end()
			check(player.dash_cooldown_frames_remaining == 0,"Cooldown did not expire while swinging/jumping")
			check(not player.is_on_floor(),"Aerial re-dash fixture landed too soon")
			Input.action_press("Action")
			await tick()
			check(player.movement_state == Player.MovementState.DASH_CHARGING,"Dash -> swing -> jump could not air dash after cooldown")
			check(not player.dash_available,"New air dash did not consume its budget")
	# Coyote is still a legal ground-derived jump, not a midair budget refill.
	await place(Vector2(526.5,320))
	player.dash_available = false
	player.velocity.x = player.run_speed
	Input.action_press("Move Right")
	await tick()
	check(not player.is_on_floor() and player.coyote_frames_remaining > 0,"Coyote fixture did not leave ledge")
	player.dash_cooldown_frames_remaining = 9
	Input.action_press("Jump")
	await tick()
	check(player.is_jump_charging() and player.dash_available,"Legal coyote jump did not restore airtime budget")
	check(player.dash_cooldown_frames_remaining == 8,"Coyote jump reset cooldown")
	# A spent aerial dash followed by a swing cannot gain a dash from an illegal jump.
	await place(Vector2(3550,-600))
	Input.action_press("Action")
	await tick()
	await press_attack()
	Input.action_release("Action")
	Input.action_press("Jump")
	await tick()
	check(not player.is_jump_charging() and not player.dash_available,"Invalid midair jump refunded a spent dash")
	await wait_end()
	check(player.dash_cooldown_frames_remaining == 0 and not player.dash_available,"Cooldown expiry refunded air dash without legal ground jump")
	Input.action_press("Action")
	await tick()
	check(player.movement_state == Player.MovementState.NORMAL,"Air dash -> swing -> invalid jump bypassed one-air-dash limit")

func test_blocks_and_reset() -> void:
	await place()
	Input.action_press("Action")
	await tick()
	Input.action_release("Action")
	await tick()
	for frame in range(60):
		if player.movement_state == Player.MovementState.RECOVERY:break
		await tick()
	check(player.movement_state == Player.MovementState.RECOVERY,"Dash recovery fixture missed")
	Input.action_press("Attack")
	await tick()
	check(not combat.is_attacking(),"Attack interrupted dash recovery")
	await place()
	combat.actions_enabled = false
	Input.action_press("Attack")
	await tick()
	check(not combat.is_attacking(),"Disabled combat allowed attack")
	await place()
	await press_attack()
	Input.action_press("Action")
	await tick()
	combat.interrupt()
	await tick(2)
	check(not combat.is_attacking() and not combat.buffered_dash and not combat.hitbox.monitoring,"Interruption retained attack/hitbox/dash")
	check(player.movement_state == Player.MovementState.NORMAL,"Interruption launched buffered dash")
	await place()
	target_at(Vector2(2740,320))
	await tick(2)
	await press_attack()
	for frame in range(40):
		if combat.is_hitstopped():break
		await tick()
	Input.action_press("Action")
	await tick()
	player.reset_movement()
	await tick(3)
	check(not combat.is_attacking() and not combat.is_hitstopped() and not combat.buffered_dash and not combat.hitbox.monitoring,"Respawn retained combat state")
	check(player.movement_state == Player.MovementState.NORMAL,"Held inputs restarted combat after reset")

func run() -> void:
	lab = load("res://Scenes/Player/player_test.tscn").instantiate() as Node2D
	lab.start_in_combat_section = false # Test fixture independent of lab authoring defaults.
	lab.start_in_damage_section = false
	lab.start_in_climbing_section = false
	root.add_child(lab)
	player = lab.get_node("Player") as Player
	player.jump_charge_frames = 5 # Explicitly exercise anticipation despite user tuning.
	combat = player.get_node("CombatController") as PlayerCombatController
	check(combat.repeat_while_held,"Held attack repetition is not enabled by default")
	sprite = player.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	combat.hit_confirmed.connect(func(_target: CombatDamageable, hit: CombatHit) -> void: hits.append(hit))
	combat.hitstop_started.connect(func(ticks: int) -> void: stops.append(ticks))
	combat.swing_freeze_started.connect(func(ticks: int) -> void: swing_freezes.append(ticks))
	combat.phase_changed.connect(func(phase: int) -> void:
		phases.append(phase)
		if phase == combat.AttackState.IDLE and sprite.is_attack_animation():last_finish_frame = sprite.frame)
	combat.attack_finished.connect(func(interrupted: bool) -> void:
		last_finish_tick = Engine.get_physics_frames()
		last_finish_interrupted = interrupted)
	player.movement_state_changed.connect(func(state: int) -> void:
		dash_states.append(state)
		if state == Player.MovementState.DASH_CHARGING: last_dash_tick = Engine.get_physics_frames())
	await tick(5)
	await test_swing_freeze()
	await test_swing_speed_boost()
	await test_swing_burst()
	await test_attack_jump_multiplier()
	await test_phases_and_input()
	await test_recovery_cancel()
	await test_held_attacks()
	await test_movement_and_lock()
	await test_hits_and_stop()
	await test_dash_buffers()
	await test_action_cancels()
	await test_dash_swing_jump_air_dash()
	await test_blocks_and_reset()
	release_inputs()
	lab.free()
	# The optional combat spawn and respawn reset stay independent of the old lab.
	lab = load("res://Scenes/Player/player_test.tscn").instantiate() as Node2D
	lab.start_in_combat_section = true
	lab.start_in_damage_section = false
	lab.start_in_climbing_section = false
	root.add_child(lab)
	await tick(5)
	var spawned_player: Player = lab.get_node("Player")
	check(spawned_player.position.x == lab.get_node("CombatSpawn").position.x,"Combat start option ignored")
	var dummy: Node = lab.get_node("CombatSection/DummyNear")
	var hit := CombatHit.new()
	hit.source = spawned_player
	dummy.get_node("Damageable").receive_hit(hit)
	lab.respawn_player()
	check(dummy.get_node("Damageable").health == dummy.get_node("Damageable").max_health,"Lab respawn did not reset dummies")
	lab.free()
	print("Chief melee: ",checks," checks; phases, input, facing, movement, damage, hitstop, dash buffering and reset; failures=",failures)
	quit(1 if failures else 0)
