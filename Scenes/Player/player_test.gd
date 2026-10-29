extends Node2D
## Test-scene conveniences only; no respawn or display rules in the player.
## The village deliberately uses a 1920x1080 UI canvas. Override presentation
## only while this lab runs, then restore the host window on scene exit.
@export var enable_debug_shortcuts: bool = true
@export var fall_reset_y: float = 600.0
@export var base_viewport_size: Vector2i = Vector2i(640, 360)
@export var test_window_size: Vector2i = Vector2i(1280, 720)
var _saved_window: Dictionary = {}
@onready var player: Player = $Player
@onready var spawn: Marker2D = $Spawn


func _ready() -> void:
	var window := get_window()
	for property in ["content_scale_size", "content_scale_mode", "content_scale_aspect", "content_scale_stretch", "content_scale_factor", "size", "canvas_item_default_texture_filter"]:
		_saved_window[property] = window.get(property)
	window.content_scale_size = base_viewport_size
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	window.content_scale_factor = 1.0
	window.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	window.size = test_window_size


func _exit_tree() -> void:
	var window := get_window()
	for property in _saved_window:
		window.set(property, _saved_window[property])


func _physics_process(_delta: float) -> void:
	if player.global_position.y > fall_reset_y:
		respawn_player()


func respawn_player() -> void:
	move_player_to(spawn)


func move_player_to(marker: Marker2D) -> void:
	player.global_position = marker.global_position
	player.reset_movement()
	var camera: Camera2D = player.get_node("Camera2D")
	camera.reset_smoothing()


func _unhandled_input(event: InputEvent) -> void:
	if not enable_debug_shortcuts:
		return
	if event.is_action_pressed("Player Test Ledge"):
		move_player_to($CoyoteSpawn)
	elif event.is_action_pressed("Player Test Dash"):
		move_player_to($DashSpawn)
	elif event.is_action_pressed("Player Test Drop"):
		move_player_to($BufferSpawn)
