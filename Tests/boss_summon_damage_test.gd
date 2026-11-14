extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func strike(player: Player, target: CombatDamageable) -> void:
	player.reset_movement()
	player.combat.mouse_aim_attacks = false
	player.combat.hitstop_frames = 0
	player.facing_direction = 1
	player.global_position = target.global_position - Vector2(31, -18)
	player.combat._attack_requested = true
	check(player.combat.try_start_attack(), "Could not start test swing")
	player.combat._swing_freeze_used = true
	player.combat.sprite.set_frame_and_progress(player.combat.active_start_frame, 0)
	player.combat._sync_phase()
	player.combat.end_physics_tick()
func run() -> void:
	var game := root.get_node("GameController")
	for bonus in [0, 2]:
		game.set_stat_bonus("damage", bonus)
		var arena: Node2D = load("res://Scenes/Boss/boss_arena.tscn").instantiate()
		root.add_child(arena)
		current_scene = arena
		arena.player.set_physics_process(false)
		arena.monster.set_physics_process(false)
		var waves: Node2D = arena.get_node("Waves")
		waves.target = arena.player
		for scene in waves.ZOMBIES + waves.SPIDERS:
			waves._spawn({"scene":scene,"point":Vector2(180,304),"bonus_health":2})
			var enemy: CharacterBody2D = waves._live[-1]
			await physics_frame
			var hp: int = enemy.damageable.health
			check(hp == {"zombie_shambler.tscn":4,"zombie_runner.tscn":3,"zombie_stalker.tscn":5,"spider_rusher.tscn":4,"spider_web_shooter.tscn":4}[scene.resource_path.get_file()], "Summon did not receive base HP +2")
			strike(arena.player, enemy.damageable)
			check(enemy.damageable.health == hp - (1 + bonus), "Summon did not take normal Abyss slash damage")
			if bonus == 0:
				check(enemy.damageable.health > 0, "A fresh summon died to one unboosted test swing")
			enemy.free()
		var hand: CombatDamageable = arena.monster.left_hurt
		hand.invulnerable = false
		await physics_frame
		var hp: int = hand.health
		strike(arena.player, hand)
		check(hand.health == hp - (10 + bonus), "Boss hand lost its existing damage scale")
		arena.free()
		await process_frame
	print("Boss summon damage: all five variants, F6 baseline and blacksmith bonus; failures=",failures)
	quit(1 if failures else 0)
