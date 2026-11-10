@tool
extends Node2D
## Visual-only activation. Loading an already active checkpoint shows its last pose.
@export var active: bool = false
var _initialized: bool = false
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	sprite.animation_finished.connect(_finish_activation)
	_show_pose(active)

func set_state(value: bool) -> void:
	var animate := _initialized and value and not active
	active = value
	_initialized = true
	if not is_node_ready(): return
	if animate:
		sprite.play(&"activate")
		sprite.set_frame_and_progress(0,0.0)
	elif not sprite.is_playing() or not value:
		_show_pose(value)

func _show_pose(value: bool) -> void:
	sprite.animation = &"activate"
	sprite.pause()
	sprite.frame = sprite.sprite_frames.get_frame_count(&"activate")-1 if value else 0

func _finish_activation() -> void:
	_show_pose(active)
