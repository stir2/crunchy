extends Node2D
## One-shot sprites stay at their world-space takeoff/impact point.
const FRAMES = preload("res://Scenes/Player/movement_effect_frames.tres")
@export var burst_offset: Vector2 = Vector2(-2, -15)
@onready var player: Player = get_parent() as Player

func _ready() -> void:
	player.jumped.connect(_on_jumped)
	player.landed.connect(_on_landed)
	player.movement_reset.connect(clear_bursts)

func _on_jumped() -> void:
	play_burst(&"jump")

func _on_landed(_impact_speed: float) -> void:
	play_burst(&"land")

func play_burst(animation_name: StringName) -> void:
	var burst := AnimatedSprite2D.new()
	burst.name = "JumpBurst" if animation_name == &"jump" else "LandBurst"
	burst.sprite_frames = FRAMES
	burst.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	burst.offset = burst_offset
	burst.z_index = 1
	burst.top_level = true
	add_child(burst)
	burst.global_position = player.global_position
	burst.animation_finished.connect(burst.queue_free)
	burst.play(animation_name)

func clear_bursts() -> void:
	for burst in get_children():
		(burst as CanvasItem).hide()
		burst.queue_free()
