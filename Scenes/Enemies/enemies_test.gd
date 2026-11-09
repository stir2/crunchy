extends Node2D
## Isolated enemy arenas. Switching areas starts a fresh encounter.
var _arena_index: int = 0
var _encounters: Array[Array] = []
var _window_settings: Dictionary = {}
@onready var player: Player = $Player
@onready var camera: Camera2D = $Player/Camera2D
@onready var arenas: Array[Node] = [$Pursuit, $Climbing, $WebShots, $Mixed]
@onready var title: Label = $HUD/Title


func _ready() -> void:
	var window := get_window()
	for property in ["content_scale_size", "content_scale_mode", "content_scale_aspect", "size"]:
		_window_settings[property] = window.get(property)
	window.content_scale_size = Vector2i(640, 360)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.size = Vector2i(1280, 720)
	for arena in arenas:
		var encounter: Array = []
		for child in arena.get_children():
			if child is CharacterBody2D:
				encounter.append({"scene": load(child.scene_file_path), "position": child.get_meta("spawn_position", child.position), "name": child.name})
		_encounters.append(encounter)
	select_arena(0)


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
		_:
			return
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	var window := get_window()
	for property in _window_settings:
		window.set(property, _window_settings[property])
