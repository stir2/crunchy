extends Node2D
## One summon intermission, with separate randomized zombie and spider waves.
signal completed
signal spawn_warning(point: Vector2)
const ZOMBIES := [preload("res://Scenes/Enemies/Zombies/zombie_shambler.tscn"), preload("res://Scenes/Enemies/Zombies/zombie_runner.tscn"), preload("res://Scenes/Enemies/Zombies/zombie_stalker.tscn")]
const SPIDERS := [preload("res://Scenes/Enemies/Spiders/spider_rusher.tscn"), preload("res://Scenes/Enemies/Spiders/spider_web_shooter.tscn")]
var target: Player
var active := false
var wave_index := 0
var _families: Array[int] = []
var _live: Array[Node] = []
var _pending: Array[Dictionary] = []
var _grace: Array[Dictionary] = []
var _timer := 0.0
var _rng := RandomNumberGenerator.new()

func start(player: Player) -> void:
	if active: return
	target = player
	_rng.randomize()
	_families.assign([0, 1] if _rng.randf() < 0.5 else [1, 0])
	wave_index = 0
	_timer = 0.8
	active = true

func _physics_process(delta: float) -> void:
	if not active: return
	if not is_instance_valid(target) or target.health.is_dead():
		stop()
		return
	for entry in _grace.duplicate():
		entry.time -= delta
		if entry.time <= 0:
			if is_instance_valid(entry.enemy): entry.enemy.set_physics_process(true)
			_grace.erase(entry)
	for entry in _pending.duplicate():
		entry.time -= delta
		if entry.time <= 0:
			_pending.erase(entry)
			_spawn(entry)
	_live = _live.filter(func(enemy): return is_instance_valid(enemy))
	if not _live.is_empty() or not _pending.is_empty() or not _grace.is_empty(): return
	_timer -= delta
	if _timer > 0: return
	if wave_index >= _families.size():
		_clear_projectiles()
		active = false
		completed.emit()
		return
	_queue_wave(_families[wave_index])
	wave_index += 1
	_timer = 1.2

func _queue_wave(family: int) -> void:
	_clear_projectiles()
	var pool: Array = ZOMBIES if family == 0 else SPIDERS
	var count := _rng.randi_range(2, 3) if family == 0 else 2
	var spots: Array[float] = [48.0, 592.0, 120.0, 520.0]
	spots.sort_custom(func(a, b): return absf(a - target.position.x) > absf(b - target.position.x))
	for i in count:
		var point := Vector2(spots[i], 304)
		spawn_warning.emit(point)
		_pending.append({"scene": pool[_rng.randi_range(0, pool.size() - 1)], "point": point, "time": 0.8 + i * 0.3})

func _spawn(entry: Dictionary) -> void:
	var enemy: CharacterBody2D = entry.scene.instantiate()
	enemy.position = entry.point
	enemy.target = target
	enemy.flesh_reward = 0
	add_child(enemy)
	enemy.hitbox.active = false
	enemy.set_physics_process(false)
	enemy.modulate.a = 0
	create_tween().tween_property(enemy, "modulate:a", 1.0, 0.4)
	_grace.append({"enemy": enemy, "time": 0.45})
	_live.append(enemy)
	enemy.died.connect(func(): _live.erase(enemy))

func _clear_projectiles() -> void:
	for child in get_children():
		if child.is_in_group("enemy_projectiles"): child.queue_free()

func stop() -> void:
	active = false
	_pending.clear()
	_grace.clear()
	_clear_projectiles()
	for enemy in _live:
		if is_instance_valid(enemy):
			enemy.hitbox.active = false
			enemy.set_physics_process(false)
