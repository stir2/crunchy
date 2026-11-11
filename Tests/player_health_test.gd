extends SceneTree
## Deterministic HP checks plus real lab physics, overlap areas and tile hazards.
var checks: int = 0
var failures: int = 0
var lab: Node2D
var player: Player
var health: HealthComponent
var hud: HeartHUD
var deaths: int = 0
var reactions: int = 0

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
	for action in ["Move Left", "Move Right", "Move Down", "Jump", "Attack", "Action"]:
		Input.action_release(action)

func place(position: Vector2 = Vector2(2700, 320)) -> void:
	release_inputs()
	player.position = position
	player.reset_movement()
	health.reset_health()
	await tick(2)

func hit(amount: int = 1, side: float = -1.0) -> CombatHit:
	var payload := CombatHit.new()
	payload.amount = amount
	payload.direction = Vector2(side, 0)
	return payload

func test_health_and_hud() -> void:
	await place()
	check(health.current_health == 6 and health.max_health == 6, "Default health is not 6 HP")
	check(hud.health == health and hud.heart_count() == 3 and hud.heart_fill(2) == 2, "Initial three full hearts")
	var event_counts: Array[int] = [0,0,0]
	health.health_changed.connect(func(_hp: int, _max: int): event_counts[0] += 1)
	health.healed.connect(func(_amount: int): event_counts[1] += 1)
	player.get_node("Hurtbox").hit_confirmed.connect(func(_hit: CombatHit): event_counts[2] += 1)
	var before_reactions := reactions
	check(player.get_node("Hurtbox").receive_hit(hit()), "Hurtbox refused valid shared CombatHit")
	check(health.current_health == 5 and hud.heart_fill(2) == 1, "1 HP damage must show a half-heart")
	check(event_counts[0] == 1 and event_counts[2] == 1 and reactions == before_reactions + 1, "Damage/health/confirmation hooks")
	check(not player.damage.receive_hit(hit(2)) and health.current_health == 5, "Iframes failed to reject repeat damage")
	check(health.heal(1) == 1 and hud.heart_fill(2) == 2 and event_counts[1] == 1, "Healing/HUD did not update")
	health.temporary_max_health_bonus = 2
	check(health.max_health == 8 and hud.heart_count() == 4 and hud.heart_fill(3) == 0, "Temporary max HP did not update HUD")
	check(health.heal(50) == 2 and health.current_health == 8, "Heal did not clamp to maximum")
	player.get_node("Hurtbox").reset_damageable()
	check(health.max_health == 8 and health.base_max_health == 6, "Shared damage adapter reset changed base maximum")
	health.temporary_max_health_bonus = 0
	check(health.current_health == 6 and hud.heart_count() == 3, "Removing bonus did not clamp HP/HUD")
	health.reset_health(4)
	check(hud.heart_fill(0) == 2 and hud.heart_fill(1) == 2 and hud.heart_fill(2) == 0, "Empty hearts are incorrect")
	health.reset_health()
	check(player.damage.receive_hit(hit(2)) and health.current_health == 4 and hud.heart_fill(2) == 0, "Two-HP hit did not remove one full heart")
	health.reset_health()
	var zero := hit(0)
	check(not player.damage.receive_hit(zero), "Non-damaging payload applied damage")
	var own := hit()
	own.source = player
	check(not player.get_node("Hurtbox").receive_hit(own), "Self damage accepted")

func test_iframe_timing_and_knockback() -> void:
	await place(Vector2(2700, -100))
	var source := Node2D.new()
	source.position = player.position + Vector2(60, 0)
	lab.add_child(source)
	var payload := hit()
	payload.source = source
	var start := Engine.get_physics_frames()
	check(player.damage.receive_hit(payload), "Damage refused outside immunity")
	check(player.velocity.x < 0 and player.velocity.y < 0, "Knockback not away/up from source")
	var initial := player.position
	await tick(2)
	check(player.position.x < initial.x and player.position.y < initial.y, "Knockback failed to move body")
	check(player.get_node("Visuals/AnimatedSprite2D").self_modulate != Color.WHITE, "Hurt flash absent")
	check(player.collision_mask == 1 and player.get_node("Hurtbox").collision_layer == 4 and player.get_node("Hurtbox").monitoring, "Damage disabled terrain/hurtbox")
	var invulnerable_samples := 0
	while Engine.get_physics_frames() - start < health.invulnerability_frames:
		check(not player.damage.receive_hit(payload), "Damage accepted before 36 ticks elapsed")
		invulnerable_samples += 1
		await tick()
	check(invulnerable_samples > 20, "Timed immunity was not exercised")
	check(player.damage.receive_hit(payload) and health.current_health == 4, "Damage refused after exactly 36 ticks")
	await tick(player.damage.reaction_frames + 1)
	Input.action_press("Move Right")
	await tick(30)
	check(player.velocity.x > 0 and not player.damage.is_reacting(), "Normal movement did not resume")
	source.queue_free()

func test_interruptions() -> void:
	await place()
	Input.action_press("Attack")
	await tick()
	Input.action_press("Action")
	await tick()
	check(player.combat.is_attacking() and player.combat.buffered_dash, "Swing/dash buffer setup failed")
	check(player.damage.receive_hit(hit()), "Swing damage failed")
	check(not player.combat.is_attacking() and not player.combat.buffered_dash, "Damage failed to clear swing and queued dash")
	check(not player.combat.try_start_attack() and not player.can_start_dash(), "Actions permitted during hurt reaction")
	await tick(player.damage.reaction_frames + 2)
	check(player.movement_state == Player.MovementState.NORMAL, "Held dash leaked out of damaged swing")
	await place(Vector2(2700,-80))
	Input.action_press("Action")
	await tick()
	check(player.movement_state == Player.MovementState.DASH_CHARGING, "Dash charge setup failed")
	check(player.damage.receive_hit(hit()), "Dash charge damage failed")
	check(player.movement_state == Player.MovementState.NORMAL and player.velocity.y < 0, "Dash charge failed to cancel into knockback")
	check(not player.dash_available and player.dash_cooldown_frames_remaining > 0, "Damage refunded dash budget/cooldown")
	var y := player.position.y
	await tick(3)
	check(player.position.y != y, "Canceled charge left physics frozen")
	await place(Vector2(2700,-80))
	Input.action_press("Action")
	await tick(player.dash_charge_frames + 1)
	check(player.movement_state == Player.MovementState.DASHING, "Dashing setup failed")
	check(player.damage.receive_hit(hit()), "Dashing damage failed")
	check(player.movement_state == Player.MovementState.NORMAL and absf(player.velocity.x) < player.dash_min_speed, "Dash momentum overrode damage")
	# Interrupt an actual combat freeze, not just ordinary animation playback.
	await place(Vector2(2700,-100))
	player.combat.swing_freeze_frames = 6
	Input.action_press("Attack")
	for frame in range(40):
		await tick()
		if player.combat.is_swing_frozen(): break
	check(player.combat.is_swing_frozen(), "Combat freeze setup failed")
	player.damage.receive_hit(hit())
	check(not player.combat.is_swing_frozen() and not player.combat.is_hitstopped(), "Damage left combat frozen")
	y = player.position.y
	await tick(2)
	check(player.position.y != y and not player.combat.is_attacking(), "Freeze interruption failed to resume physics")
	# A pending charged jump is canceled too.
	await place()
	player.jump_charge_frames = 5
	Input.action_press("Jump")
	await tick()
	check(player.is_jump_charging(), "Charged jump setup failed")
	player.damage.receive_hit(hit())
	check(not player.is_jump_charging(), "Damage failed to cancel jump charge")

func test_immunity_during_combat_freeze() -> void:
	await place(Vector2(2700,-100))
	player.damage.reaction_frames = 0
	player.combat.swing_freeze_frames = 60
	var start := Engine.get_physics_frames()
	player.damage.receive_hit(hit())
	Input.action_press("Attack")
	for frame in range(40):
		await tick()
		if player.combat.is_swing_frozen(): break
	check(player.combat.is_swing_frozen(), "Immunity/freeze setup failed")
	while Engine.get_physics_frames() - start < health.invulnerability_frames:
		await tick()
	check(player.combat.is_swing_frozen() and not health.is_invulnerable(), "Combat freeze stalled independent immunity")
	check(player.damage.receive_hit(hit()) and not player.combat.is_swing_frozen(), "Damage could not interrupt frozen swing after immunity")
	player.damage.reaction_frames = 8
	player.combat.swing_freeze_frames = 6
	# Contact hitstop is a separate local freeze and must also be interrupted.
	await place()
	player.combat.swing_freeze_frames = 0
	var target := load("res://Tests/Scenes/Player/combat_dummy.tscn").instantiate() as CharacterBody2D
	target.position = Vector2(2732,320)
	lab.add_child(target)
	Input.action_press("Attack")
	for frame in range(40):
		await tick()
		if player.combat.is_hitstopped(): break
	check(player.combat.is_hitstopped(), "Contact hitstop setup failed")
	player.damage.receive_hit(hit())
	check(not player.combat.is_hitstopped() and not player.combat.is_attacking(), "Damage left contact hitstop active")
	target.queue_free()
	player.combat.swing_freeze_frames = 6

func test_explicit_areas() -> void:
	await place(Vector2(3840,320)) # Actual lab fixture; no polling-only fake.
	await tick(3)
	check(health.current_health == 5, "Explicit damage area did not damage player")
	var hp := health.current_health
	await tick(5)
	check(health.current_health == hp, "Attack area bypassed iframes")
	lab.get_node("CombatSection/DamageArea").active = false
	await place(Vector2(3840,320))
	check(health.current_health == 6, "Inactive attack area still dealt damage")
	lab.get_node("CombatSection/DamageArea").active = true
	await tick()
	check(health.current_health == 5, "Enabled attack area failed to apply damage")
	lab.get_node("CombatSection/DamageArea").active = false
	await place(Vector2(3840,320))
	Input.action_press("Action")
	await tick()
	check(player.movement_state == Player.MovementState.DASH_CHARGING, "Area-interrupt charge setup failed")
	lab.get_node("CombatSection/DamageArea").active = true
	await tick()
	check(player.movement_state == Player.MovementState.NORMAL and health.current_health == 5, "Incoming area failed to interrupt dash")
	check(player.dash_cooldown_frames_remaining == player.dash_cooldown_frames, "Damage shortened dash cooldown on its start tick")
	await place(Vector2(2800,320)) # Passive dummy hurtbox is never an attack.
	await tick(5)
	check(health.current_health == 6, "Passive enemy proximity caused damage")

func test_spikes() -> void:
	await place(Vector2(3958,320)) # Body right edge overlaps spike at x3968; center is outside.
	check(health.current_health == 5, "Authored spike body-edge overlap was missed")
	check(lab.get_node("CombatSection/SpikeExample").hazard_type_at(Vector2(3976,312)) == &"spike", "Lab is not using authored hazard query")
	var hp := health.current_health
	player.position = Vector2(3980,320)
	await tick(3)
	check(health.current_health == hp, "Spikes bypassed shared iframes")
	# Newly added translated authored providers are registered automatically.
	var room := Node2D.new()
	room.set_script(load("res://Tests/Scenes/Player/lab_spikes.gd"))
	room.position = Vector2(2650,-100)
	var layer := TileMapLayer.new()
	layer.name = "Hazards"
	layer.tile_set = load("res://Assets/Tiles/room_placeholders.tres")
	layer.collision_enabled = false
	room.add_child(layer)
	lab.add_child(room)
	await place(Vector2(2640,-84))
	check(health.current_health == 5, "Dynamically added transformed room hazard missed")
	room.queue_free()
	await place()
	check(health.current_health == 6, "Removed provider caused ghost spike damage")

func test_death_and_reset() -> void:
	await place()
	var before := deaths
	check(player.damage.receive_hit(hit(100)), "Lethal hit refused")
	check(health.current_health == 0 and deaths == before + 1, "Death did not fire once")
	check(not player.damage.receive_hit(hit()) and health.heal(6) == 0 and deaths == before + 1, "Dead player still takes damage/heals/dies again")
	Input.action_press("Attack")
	Input.action_press("Action")
	Input.action_press("Jump")
	Input.action_press("Move Right")
	var position := player.position
	await tick(45)
	check(player.position == position and player.velocity == Vector2.ZERO and not player.combat.is_attacking(), "Dead player continued moving/attacking")
	check(player.get_node("Visuals/AnimatedSprite2D").animation == &"death", "Death animation did not play")
	check(not player.can_start_dash() and not player.can_jump(), "Dead player can start abilities")
	check(player.get_node("Hurtbox").collision_layer == 4 and player.get_node("Hurtbox").monitoring, "Death disabled Hurtbox")
	lab.respawn_player()
	check(health.current_health == 6 and not health.is_invulnerable() and not player.damage.is_action_locked(), "Explicit lab reset did not reset HP/reaction")
	check(player.get_node("Hurtbox").collision_layer == 4 and player.get_node("Hurtbox").monitoring, "Death disabled player Hurtbox")
	check(not player.combat.buffered_dash and not player.combat.is_hitstopped(), "Reset left combat buffers/freeze")
	release_inputs()
	await tick(2)
	Input.action_press("Attack")
	await tick()
	check(player.combat.is_attacking(), "Reset did not restore attacks")
	player.combat.interrupt()

func run() -> void:
	lab = load("res://Scenes/Player/player_test.tscn").instantiate()
	root.add_child(lab)
	player = lab.get_node("Player")
	player.get_node("CombatController").mouse_aim_attacks = false
	health = player.health
	hud = lab.get_node("HealthCanvas/HeartHUD")
	player.damage.died.connect(func(_hit: CombatHit): deaths += 1)
	player.damage.damage_reaction.connect(func(_hit: CombatHit, _amount: int): reactions += 1)
	await tick(2)
	await test_health_and_hud()
	await test_iframe_timing_and_knockback()
	await test_interruptions()
	await test_immunity_during_combat_freeze()
	await test_explicit_areas()
	await test_spikes()
	await test_death_and_reset()
	release_inputs()
	lab.queue_free()
	await process_frame
	print("Player health: ", checks, " checks; failures=", failures)
	quit(0 if failures == 0 else 1)
