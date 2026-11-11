extends Node2D
## Isolated enemy arenas. Switching areas starts a fresh encounter.
const RUNNER_SCENE = preload("res://Scenes/Enemies/Zombies/zombie_runner.tscn")
const SHAMBLER_SCENE = preload("res://Scenes/Enemies/Zombies/zombie_shambler.tscn")
const STALKER_SCENE = preload("res://Scenes/Enemies/Zombies/zombie_stalker.tscn")
const RUSHER_SCENE = preload("res://Scenes/Enemies/Spiders/spider_rusher.tscn")
const WEB_SHOOTER_SCENE = preload("res://Scenes/Enemies/Spiders/spider_web_shooter.tscn")

var _arena_index: int = 0
var _encounters: Array[Array] = []
var _window_settings: Dictionary = {}
@onready var player: Player = $Player
@onready var camera: Camera2D = $Player/Camera2D
@onready var arenas: Array[Node] = [$Pursuit, $Climbing, $WebShots, $Mixed]
@onready var title: Label = $HUD/Title
@onready var subtitle: Label = $HUD.get_child(1) if $HUD.get_child_count() > 1 else null


func _ready() -> void:
	var window := get_window()
	for property in ["content_scale_size", "content_scale_mode", "content_scale_aspect", "size"]:
		_window_settings[property] = window.get(property)
	window.content_scale_size = Vector2i(640, 360)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.size = Vector2i(1280, 720)

	_setup_arena_terrain()

	for arena in arenas:
		var encounter: Array = []
		for child in arena.get_children():
			if child is CharacterBody2D:
				encounter.append({"scene": load(child.scene_file_path), "position": child.get_meta("spawn_position", child.position), "name": child.name})
		_encounters.append(encounter)
	select_arena(0)


func _setup_arena_terrain() -> void:
	# 1. Pursuit arena: Add multi-tier ledges, gaps, and one-way platforms
	var pursuit_terrain: TileMapLayer = $Pursuit/Terrain
	# Ledge 1: x = 16 to 22, y = 16 (+64px)
	for x in range(16, 23):
		pursuit_terrain.set_cell(Vector2i(x, 16), 0, Vector2i(0, 0))
	# Ledge 2: x = 26 to 32, y = 12 (+128px)
	for x in range(26, 33):
		pursuit_terrain.set_cell(Vector2i(x, 12), 0, Vector2i(0, 0))
	# Ledge 3 (One-way drop-through): x = 36 to 42, y = 15 (+80px)
	for x in range(36, 43):
		pursuit_terrain.set_cell(Vector2i(x, 15), 0, Vector2i(1, 0))
	# High ledge: x = 46 to 52, y = 9 (+176px)
	for x in range(46, 53):
		pursuit_terrain.set_cell(Vector2i(x, 9), 0, Vector2i(0, 0))
	# Gaps in floor to test gap jumping
	for y in range(20, 25):
		for x in [23, 24, 25, 32, 33, 34]:
			pursuit_terrain.erase_cell(Vector2i(x, y))

	# 2. Climbing arena: Floating island platforms with gaps, ceiling overhangs, and vertical pillar
	var climbing_terrain: TileMapLayer = $Climbing/Terrain
	# Floating platform 1 (x=16..22, y=14)
	for x in range(16, 23):
		for y in range(14, 16):
			climbing_terrain.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	# Floating platform 2 with gap (x=27..33, y=10)
	for x in range(27, 34):
		for y in range(10, 12):
			climbing_terrain.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	# Floating platform 3 with gap (x=38..44, y=14)
	for x in range(38, 45):
		for y in range(14, 16):
			climbing_terrain.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	# Vertical pillar (x=48..49, y=6..19)
	for x in range(48, 50):
		for y in range(6, 20):
			climbing_terrain.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	# Ceiling ledge (x=20..44, y=3)
	for x in range(20, 45):
		climbing_terrain.set_cell(Vector2i(x, 3), 0, Vector2i(0, 0))


func select_arena(index: int) -> void:
	_arena_index = clampi(index, 0, arenas.size() - 1)
	for projectile in get_tree().get_nodes_in_group("enemy_projectiles"):
		projectile.queue_free()
	for i in range(arenas.size()):
		arenas[i].visible = i == _arena_index
		arenas[i].process_mode = Node.PROCESS_MODE_INHERIT if i == _arena_index else Node.PROCESS_MODE_DISABLED
	var arena := arenas[_arena_index]
	for child in arena.get_children():
		if child is CharacterBody2D:
			arena.remove_child(child)
			child.queue_free()
	for entry: Dictionary in _encounters[_arena_index]:
		var enemy: CharacterBody2D = entry.scene.instantiate()
		enemy.name = entry.name
		enemy.position = entry.position
		enemy.target = player
		arena.add_child(enemy)
	player.global_position = arena.get_node("Spawn").global_position
	player.reset_movement()
	player.health.reset_health()
	camera.limit_left = int(arena.position.x)
	camera.limit_right = int(arena.position.x + 1152)
	camera.limit_top = -64
	camera.limit_bottom = 448
	camera.reset_smoothing()
	title.text = "%d / 4   %s" % [_arena_index + 1, arena.get_meta("title")]
	if subtitle != null:
		subtitle.text = "[1-4] Switch Arena  [R] Reset  |  [5-7] Zombies  [8] Rusher  [9] Web Spider  [H] Heal"


func spawn_enemy_at_player(packed_scene: PackedScene, offset_x: float = 80.0) -> void:
	if packed_scene == null:
		return
	var arena := arenas[_arena_index]
	var enemy: CharacterBody2D = packed_scene.instantiate()
	enemy.position = arena.to_local(player.global_position + Vector2(offset_x, 0))
	enemy.target = player
	arena.add_child(enemy)


func _physics_process(_delta: float) -> void:
	if player.global_position.y > 600:
		select_arena(_arena_index)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			select_arena(event.physical_keycode - KEY_1)
		KEY_R:
			select_arena(_arena_index)
		KEY_5:
			spawn_enemy_at_player(RUNNER_SCENE, 100.0)
		KEY_6:
			spawn_enemy_at_player(SHAMBLER_SCENE, 100.0)
		KEY_7:
			spawn_enemy_at_player(STALKER_SCENE, 100.0)
		KEY_8:
			spawn_enemy_at_player(RUSHER_SCENE, 120.0)
		KEY_9:
			spawn_enemy_at_player(WEB_SHOOTER_SCENE, 140.0)
		KEY_H:
			player.health.heal(player.health.base_max_health)
		_:
			return
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	var window := get_window()
	for property in _window_settings:
		window.set(property, _window_settings[property])
