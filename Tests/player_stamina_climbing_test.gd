extends SceneTree
## Real player input/physics plus deterministic standalone stamina arithmetic.
var failures: int = 0
var checks: int = 0
var lab: Node2D
var player: Player
var stamina: StaminaComponent
var climbing: PlayerClimbing
var hud: StaminaHUD
var rejections: int = 0
var exhaustions: int = 0

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
	for action in ["Move Left", "Move Right", "Move Up", "Move Down", "Jump", "Attack", "Action"]:
		Input.action_release(action)

func place(position: Vector2 = Vector2(2700,320)) -> void:
	release_inputs()
	player.position = position
	player.reset_movement()
	player.health.reset_health()
	stamina.max_stamina = 100.0
	stamina.dash_cost = 5.0
	stamina.regeneration_per_second = 3.0
	stamina.regeneration_delay = 0.75
	stamina.reset_stamina()
	player.jump_charge_frames = 5
	player.dash_charge_frames = 16
	player.combat.swing_freeze_frames = 4
	climbing.climb_speed = 100.0 # Fixture independent of current designer tuning.
	climbing.stamina_drain_per_second = 15.0
	await tick(2)

func press_up() -> void:
	Input.action_press("Move Up")
	await tick()

func test_pool() -> void:
	var pool := StaminaComponent.new()
	root.add_child(pool)
	var empty_count: Array[int] = [0]
	pool.exhausted.connect(func(): empty_count[0] += 1)
	check(pool.current_stamina == 100.0 and pool.can_spend(5), "Pool defaults/check API")
	check(pool.spend(5) and pool.current_stamina == 95.0, "Atomic spending")
	pool.advance(0.5)
	check(pool.current_stamina == 95.0, "Regenerated before delay")
	pool.advance(0.25)
	check(pool.current_stamina == 95.0, "Delay boundary regenerated a full tick")
	pool.advance(0.5)
	check(is_equal_approx(pool.current_stamina,96.5), "3 stamina/sec regeneration")
	pool.advance(3.0,true)
	check(is_equal_approx(pool.current_stamina,96.5), "Blocked regeneration")
	pool.reset_stamina(2)
	check(not pool.spend(5) and pool.current_stamina == 2.0, "Insufficient spend mutated pool")
	check(pool.drain(3) == 2.0 and pool.current_stamina == 0.0 and empty_count[0] == 1, "Partial drain/exhaustion")
	pool.drain(5)
	check(empty_count[0] == 1, "Repeated zero drain emitted exhaustion again")
	check(pool.restore(1000) == 100.0 and pool.current_stamina == 100.0, "Restoration clamping")
	pool.max_stamina = 150
	check(pool.current_stamina == 100.0, "Max upgrade automatically restored stamina")
	pool.reset_stamina()
	check(pool.current_stamina == 150.0, "Sleeping/full reset API")
	pool.max_stamina = 80
	check(pool.current_stamina == 80.0, "Max reduction did not clamp")
	pool.queue_free()

func test_stamina_bar_feedback() -> void:
	var pool := StaminaComponent.new()
	root.add_child(pool)
	var bar := StaminaHUD.new()
	root.add_child(bar)
	bar.bind_stamina(pool)
	check(not bar.is_processing(), "Idle full bar should not animate")
	pool.spend(10)
	check(pool.current_stamina == 90 and bar._drain_remaining > 0 and bar._regen_remaining == 0, "Spending did not start depletion feedback")
	check(bar._drain_from_ratio > bar.fill_ratio(), "Spent stamina left no depletion trail")
	bar._process(maxf(bar.drain_indicator_seconds,bar.drain_pulse_interval) + 0.01)
	check(not bar.is_processing(), "Depletion feedback did not settle")
	pool.advance(pool.regeneration_delay)
	pool.advance(1.0)
	check(pool.current_stamina == 93 and bar._regen_remaining > 0 and bar._drain_remaining == 0, "Real regeneration did not start refill feedback")
	pool.drain(1)
	check(bar._drain_remaining > 0 and bar._regen_remaining == 0, "Draining did not replace regeneration feedback")
	pool.reset_stamina()
	check(not bar.is_processing(), "Full reset left resource-change effects active")
	pool.max_stamina = 120
	check(not bar.is_processing(), "Maximum upgrade falsely indicated spending/regeneration")
	pool.restore(100)
	check(not bar.is_processing(), "Full stamina kept blinking")
	pool.spend(200)
	check(bar._flash_remaining > 0 and pool.current_stamina == 120, "Insufficient-stamina feedback regressed")
	bar.bind_stamina(null)
	pool.spend(5)
	check(not bar.is_processing(), "Unbound bar retained resource listeners/effects")
	bar.queue_free()
	pool.queue_free()

func test_dash_cost() -> void:
	await place()
	Input.action_press("Action")
	await tick()
	check(player.movement_state == Player.MovementState.DASH_CHARGING and stamina.current_stamina == 95.0, "Cost not deducted at charge start")
	await tick(5)
	check(stamina.current_stamina == 95.0, "Charge spent twice or regenerated")
	Input.action_release("Action")
	await tick(2)
	check(player.movement_state == Player.MovementState.DASHING and stamina.current_stamina == 95.0, "Launch spent twice")
	Input.action_press("Attack")
	await tick()
	check(player.combat.is_attacking() and stamina.current_stamina == 95.0, "Canceled dash refunded stamina")
	await place()
	player.dash_charge_frames = 0
	Input.action_press("Action")
	await tick()
	check(player.movement_state == Player.MovementState.DASHING and stamina.current_stamina == 95.0, "Zero-charge dash cost incorrect")
	await place()
	stamina.regeneration_per_second = 0.0
	stamina.reset_stamina(4)
	var before := rejections
	Input.action_press("Action")
	await tick()
	check(player.movement_state == Player.MovementState.NORMAL and stamina.current_stamina == 4.0, "Insufficient dash started/spent")
	check(rejections == before+1 and hud._flash_remaining > 0.0, "Failed dash HUD feedback missing")
	check(not player.can_start_dash(), "Eligibility ignores stamina")
	stamina.max_stamina = 200
	stamina.restore(96)
	check(is_equal_approx(hud.fill_ratio(),0.5), "HUD maximum upgrade not reflected")

func test_regeneration_policy() -> void:
	await place()
	stamina.spend(10)
	await tick(ceili(0.5 * Engine.physics_ticks_per_second))
	check(stamina.current_stamina == 90.0, "Player regenerated during delay")
	await tick(Engine.physics_ticks_per_second)
	check(stamina.current_stamina > 91 and stamina.current_stamina < 93, "Grounded regeneration after delay")
	await place(Vector2(2700,-300))
	stamina.reset_stamina(50)
	await tick(10)
	check(stamina.current_stamina > 50.0, "Airborne regeneration disabled")
	await place()
	stamina.reset_stamina(50)
	Input.action_press("Attack")
	await tick(10)
	check(player.combat.is_attacking() and stamina.current_stamina == 50, "Melee regenerated stamina")
	await place()
	stamina.reset_stamina(50)
	player.dash_charge_frames = 120
	Input.action_press("Action")
	await tick(60)
	check(player.movement_state == Player.MovementState.DASH_CHARGING and stamina.current_stamina == 45, "Long charge regenerated after delay")
	Input.action_release("Action")
	await tick()
	var remaining := stamina.current_stamina
	await tick(2)
	check(player.movement_state == Player.MovementState.DASHING and stamina.current_stamina == remaining, "Dashing regenerated stamina")

func test_buffered_dash() -> void:
	await place()
	Input.action_press("Attack")
	await tick()
	Input.action_press("Action")
	for frame in range(100):
		await tick()
		if player.movement_state == Player.MovementState.DASH_CHARGING: break
	check(player.movement_state == Player.MovementState.DASH_CHARGING and stamina.current_stamina == 95, "Buffered dash cost/charge incorrect")
	await tick(3)
	check(stamina.current_stamina == 95, "Buffered dash charged more than once")
	await place()
	stamina.regeneration_per_second = 0
	stamina.reset_stamina(0)
	Input.action_press("Attack")
	await tick()
	Input.action_press("Action")
	var before := rejections
	for frame in range(100):
		await tick()
		if rejections > before: break
	check(rejections == before+1 and hud._flash_remaining > 0, "Rejected buffered dash did not signal HUD")
	check(player.movement_state == Player.MovementState.NORMAL and not player.combat.buffered_dash, "Ineligible buffered dash was retained/started")
	check(player.combat.is_attacking(), "Insufficient dash canceled attack recovery")

func check_climb_pose(expected: int, message: String) -> void:
	var sprite: AnimatedSprite2D = player.get_node("Visuals/AnimatedSprite2D")
	sprite.update_animation()
	check(sprite.animation == &"jump" and sprite.frame == expected and not sprite.is_playing(), message)
	check(sprite.offset == sprite.jump_offset, "Climbing changed the jump sprite origin")

func test_climbing_motion() -> void:
	await place(Vector2(4392,320))
	check(climbing.overlaps_climbable(), "Real ladder tile not detected")
	var y := player.position.y
	await press_up()
	check(climbing.is_climbing() and player.velocity.y == -100 and player.position.y < y, "Up failed to attach/climb")
	check_climb_pose(1, "Climbing up did not use the green jump pose")
	await tick(15) # Leave enough room below to climb downward without hitting the floor.
	Input.action_release("Move Up")
	await tick()
	var stationary := player.position
	var remaining := stamina.current_stamina
	await tick(60)
	check(player.position.is_equal_approx(stationary) and player.velocity == Vector2.ZERO, "Idle climbing moved/fell")
	check(stamina.current_stamina == remaining, "Stationary climbing drained or regenerated")
	check_climb_pose(2, "Idle climbing did not hold the orange jump pose")
	Input.action_press("Move Down")
	await tick(5)
	check(climbing.is_climbing() and player.velocity.y == 100, "Climb Down triggered fast fall")
	check_climb_pose(4, "Climbing down did not use the red jump pose")
	var expected := 15.0 * 5.0 / Engine.physics_ticks_per_second
	check(is_equal_approx(remaining-stamina.current_stamina,expected), "Climb moving cost is not 15/sec")
	Input.action_release("Move Down")
	await tick()
	remaining = stamina.current_stamina
	Input.action_press("Action")
	await tick()
	check(climbing.is_climbing() and player.movement_state == Player.MovementState.NORMAL and stamina.current_stamina == remaining, "Dash began/spent while climbing")
	Input.action_release("Action")
	Input.action_press("Move Right")
	await tick()
	check(not climbing.is_climbing() and player.velocity.x > 0, "Horizontal detach failed")
	await place(Vector2(4392,320))
	await press_up()
	Input.action_release("Move Up")
	Input.action_press("Move Down")
	await tick(5) # Return to the solid floor while attached.
	remaining = stamina.current_stamina
	await tick(10)
	check(stamina.current_stamina == remaining and climbing.is_climbing(), "Blocked vertical input drained stationary climbing")
	await place(Vector2(4470,200))
	await press_up()
	check(not climbing.is_climbing(), "Up attached without climbable tiles")

func test_held_up_contact() -> void:
	await place(Vector2(4350,200))
	await press_up()
	await tick(2)
	check(not climbing.is_climbing(), "Held Up attached before tile contact")
	Input.action_press("Move Right")
	for frame in range(40):
		await tick()
		if climbing.is_climbing(): break
	check(climbing.is_climbing(), "Holding Up while approaching did not grab climbable")
	await tick(3)
	check(climbing.is_climbing() and player.velocity.x == 0.0, "Approach direction immediately detached the grab")
	Input.action_release("Move Right")
	await tick()
	Input.action_press("Move Right")
	await tick()
	check(not climbing.is_climbing(), "Fresh horizontal input failed to detach")
	Input.action_release("Move Right")
	await tick(2)
	check(not climbing.is_climbing(), "Held Up undid intentional detachment")
	Input.action_release("Move Up")
	await tick()
	await press_up()
	check(climbing.is_climbing(), "Releasing Up failed to rearm attachment")

func test_climb_jump_and_damage() -> void:
	await place(Vector2(4392,320))
	await press_up()
	player.dash_available = false
	player.dash_cooldown_frames_remaining = 12
	Input.action_press("Jump")
	await tick()
	check(not climbing.is_climbing() and player.is_jump_charging(), "Climb jump skipped existing charge")
	check(not player.dash_available and player.dash_cooldown_frames_remaining == 11, "Climb jump refunded dash/cooldown")
	await tick(player.jump_charge_frames)
	check(player.velocity.y == player.jump_velocity and not player.dash_available, "Climb jump failed normal launch or granted dash")
	Input.action_release("Jump")
	await tick()
	var before := player.velocity.y
	Input.action_press("Jump")
	await tick()
	check(not player.is_jump_charging() and player.velocity.y > before, "Climb jump allowed an extra midair jump")
	await tick(12)
	Input.action_press("Action")
	await tick()
	check(player.movement_state == Player.MovementState.NORMAL, "Climb jump granted an aerial dash")
	await place(Vector2(4392,320))
	await press_up()
	var payload := CombatHit.new()
	check(player.damage.receive_hit(payload), "Climbing rejected damage")
	check(not climbing.is_climbing() and player.damage.is_reacting() and player.velocity.y < 0, "Damage did not detach into knockback")
	await place(Vector2(4392,320))
	Input.action_press("Jump")
	await tick()
	await press_up()
	check(player.is_jump_charging() and not climbing.is_climbing(), "Climb interrupted charged jump")
	await place(Vector2(4392,320))
	Input.action_press("Jump")
	await press_up()
	check(player.is_jump_charging() and not climbing.is_climbing(), "Simultaneous Up swallowed the ground jump")
	await place(Vector2(4392,160))
	await press_up()
	Input.action_press("Move Right")
	Input.action_press("Jump")
	await tick()
	check(player.is_jump_charging() and not climbing.is_climbing(), "Horizontal detach swallowed simultaneous ladder jump")

func test_climb_combat_freeze_jump() -> void:
	await place(Vector2(4392,160))
	await press_up()
	player.dash_available = false
	Input.action_press("Attack")
	for frame in range(60):
		await tick()
		if player.combat.is_swing_frozen(): break
	check(player.combat.is_swing_frozen() and climbing.is_climbing(), "Climbing melee/freeze setup failed")
	var remaining := stamina.current_stamina
	Input.action_press("Jump")
	await tick()
	Input.action_release("Jump")
	await tick()
	check(stamina.current_stamina == remaining, "Frozen climbing spent/regenerated stamina")
	for frame in range(20):
		if not climbing.is_climbing(): break
		await tick()
	check(not climbing.is_climbing() and player.is_jump_charging() and not player.dash_available, "Freeze lost buffered ladder jump or restored air dash")
	await tick(player.jump_charge_frames)
	check(is_equal_approx(player.velocity.y,player.jump_velocity * player.combat.attack_jump_multiplier * player.jump_release_multiplier), "Buffered ladder attack jump lost combat multiplier or early release")

func test_exhaustion_and_fast_fall() -> void:
	await place(Vector2(4648,160))
	stamina.reset_stamina(1)
	stamina.regeneration_per_second = 0
	var before := exhaustions
	await press_up()
	await tick(10)
	check(stamina.current_stamina == 0 and not climbing.is_climbing() and exhaustions == before+1, "Exhaustion failed to detach once")
	check(player.velocity.y > 0, "Exhaustion failed to restore gravity")
	stamina.restore(5)
	await tick(3)
	check(not climbing.is_climbing(), "Held Up automatically reattached after exhaustion")
	Input.action_release("Move Up")
	await tick()
	await press_up()
	check(climbing.is_climbing(), "Fresh Up with sufficient stamina could not reattach")
	player.reset_movement()
	check(not climbing.is_climbing(), "Movement reset failed to detach")
	await place(Vector2(4392,160))
	player.velocity.y = 80
	Input.action_press("Move Down")
	await press_up()
	check(not climbing.is_climbing() and player.velocity.y >= player.fast_fall_speed, "Down+Up grabbed ladder during fast fall")
	await place(Vector2(4392,160))
	stamina.regeneration_per_second = 0
	stamina.reset_stamina(0.5)
	await press_up()
	check(not climbing.is_climbing(), "Reattached below minimum stamina")

func test_full_shaft_exhaustion() -> void:
	await place(Vector2(4648,320))
	stamina.regeneration_per_second = 0
	await press_up()
	await tick(ceili(100.0 / 15.0 * Engine.physics_ticks_per_second) + 2)
	check(stamina.current_stamina == 0 and not climbing.is_climbing(), "Full pool failed to exhaust on tall shaft")
	check(player.position.y < 0 and player.position.y > -450, "Tall shaft did not exhaust before its top")

func test_top_and_dynamic_rooms() -> void:
	await place(Vector2(4392,320))
	await press_up()
	await tick(ceili(3.3 * Engine.physics_ticks_per_second))
	check(not climbing.is_climbing() and player.is_on_floor() and absf(player.position.y-80) < 1.0, "Could not exit short ladder onto top platform")
	var room := AbyssAuthoredRoom.new()
	room.position = Vector2(-500,-100)
	var layer := TileMapLayer.new()
	layer.name = "Climbables"
	layer.tile_set = load("res://Assets/Tiles/room_placeholders.tres")
	layer.collision_enabled = false
	layer.set_cell(Vector2i.ZERO,0,Vector2i(3,0))
	room.add_child(layer)
	lab.add_child(room)
	await place(Vector2(-492,-74))
	await press_up()
	check(climbing.is_climbing(), "New translated authored room was not detected")
	room.queue_free()
	await tick(2)
	check(not climbing.is_climbing(), "Removed room left player attached")

func test_death_preserves_stamina() -> void:
	await place()
	stamina.reset_stamina(37)
	var lethal := CombatHit.new()
	lethal.amount = 99
	player.damage.receive_hit(lethal)
	await tick(90)
	check(stamina.current_stamina == 37, "Death regenerated/reset remaining stamina")
	lab.respawn_player()
	check(stamina.current_stamina == 37, "Lab respawn restored stamina instead of preserving it")
	stamina.reset_stamina()
	check(stamina.current_stamina == 100 and is_equal_approx(hud.fill_ratio(),1.0), "Full restoration hook/HUD")

func run() -> void:
	await test_pool()
	test_stamina_bar_feedback()
	lab = load("res://Scenes/Player/player_test.tscn").instantiate()
	root.add_child(lab)
	player = lab.get_node("Player")
	stamina = player.stamina
	climbing = player.climbing
	hud = player.get_node("StaminaHUD")
	stamina.spend_failed.connect(func(_amount: float): rejections += 1)
	stamina.exhausted.connect(func(): exhaustions += 1)
	await test_dash_cost()
	await test_regeneration_policy()
	await test_buffered_dash()
	await test_climbing_motion()
	await test_held_up_contact()
	await test_climb_jump_and_damage()
	await test_climb_combat_freeze_jump()
	await test_exhaustion_and_fast_fall()
	await test_full_shaft_exhaustion()
	await test_top_and_dynamic_rooms()
	await test_death_preserves_stamina()
	release_inputs()
	lab.queue_free()
	await process_frame
	print("Player stamina/climbing: ",checks," checks; failures=",failures)
	quit(0 if failures == 0 else 1)
