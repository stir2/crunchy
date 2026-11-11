extends Node2D
## One summon intermission, with two staggered mixed waves.
signal completed
signal wave_started
signal spawn_warning(point: Vector2)
const PORTRAITS = preload("res://Scenes/Village/villager_portraits.gd")
const ZOMBIES := [preload("res://Scenes/Enemies/Zombies/zombie_shambler.tscn"), preload("res://Scenes/Enemies/Zombies/zombie_runner.tscn"), preload("res://Scenes/Enemies/Zombies/zombie_stalker.tscn")]
const SPIDERS := [preload("res://Scenes/Enemies/Spiders/spider_rusher.tscn"), preload("res://Scenes/Enemies/Spiders/spider_web_shooter.tscn")]
const FORMATIONS := [[ZOMBIES[0], SPIDERS[1], ZOMBIES[1]], [SPIDERS[0], ZOMBIES[2], SPIDERS[1]]]
var target: Player
var _taken_name := ""
var active := false
var wave_index := 0
var _live: Array[Node] = []
var _pending: Array[Dictionary] = []
var _grace: Array[Dictionary] = []
var _timer := 0.0

func start(player: Player, taken_name: String) -> void:
	if active: return
	target = player
	_taken_name = taken_name
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
	if wave_index >= FORMATIONS.size():
		_clear_projectiles()
		active = false
		completed.emit()
		return
	_queue_wave()
	wave_index += 1
	_timer = 1.2

func _queue_wave() -> void:
	_clear_projectiles()
	wave_started.emit()
	var formation: Array = FORMATIONS[wave_index]
	var spots: Array[float] = [48.0, 592.0, 120.0, 520.0]
	spots.sort_custom(func(a, b): return absf(a - target.position.x) > absf(b - target.position.x))
	for i in formation.size():
		var point := Vector2(spots[i], 304)
		spawn_warning.emit(point)
		_pending.append({"scene": formation[i], "point": point, "bonus_health": 5, "time": 0.8 + i * 0.45})

func _spawn(entry: Dictionary) -> void:
	var enemy: CharacterBody2D = entry.scene.instantiate()
	enemy.position = entry.point
	enemy.target = target
	enemy.flesh_reward = 0
	enemy.base_health += int(entry.bonus_health)
	add_child(enemy)
	enemy.hitbox.active = false
	enemy.set_physics_process(false)
	enemy.modulate.a = 0
	create_tween().tween_property(enemy, "modulate:a", 1.0, 0.4)
	_grace.append({"enemy": enemy, "time": 0.45})
	_live.append(enemy)
	enemy.died.connect(func(): _live.erase(enemy))
	if not _taken_name.is_empty():
		var memory := Sprite2D.new()
		memory.texture = PORTRAITS.texture_for(_taken_name)
		_taken_name = ""
		memory.scale = Vector2.ONE * 0.4
		memory.modulate = Color(0.65, 0.77, 0.9, 0.85)
		add_child(memory)
		memory.global_position = enemy.global_position + Vector2(0, -51)
		var fade := memory.create_tween()
		fade.tween_property(memory, "modulate:a", 0.0, 0.8)
		fade.tween_callback(memory.queue_free)

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
