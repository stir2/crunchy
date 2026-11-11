@tool
extends Node2D
## Door artwork only. Unlock state and collision belong to the gate interaction.
@export var active: bool = false
var _initialized: bool = false
@onready var closed_door: Sprite2D = $ClosedDoor
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	sprite.animation_finished.connect(func() -> void: _show_pose(active))
	_show_pose(active)

func set_state(value: bool) -> void:
	var animate := _initialized and value and not active
	active = value
	_initialized = true
	if not is_node_ready(): return
	if animate:
		closed_door.visible = false
		sprite.visible = true
		sprite.play(&"open")
		sprite.set_frame_and_progress(0,0.0)
	elif not sprite.is_playing() or not value:
		_show_pose(value)

func _show_pose(value: bool) -> void:
	closed_door.visible = not value
	sprite.visible = value
	sprite.animation = &"open"
	sprite.pause()
	sprite.frame = sprite.sprite_frames.get_frame_count(&"open")-1 if value else 0
