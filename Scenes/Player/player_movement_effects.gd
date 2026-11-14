extends Node2D
## One-shot sprites stay at their world-space takeoff/impact point.
const FRAMES = preload("res://Scenes/Player/movement_effect_frames.tres")
@export var burst_offset: Vector2 = Vector2(-2, -15)
var _was_dashing := false
var _dash_facing := 1
@onready var player: Player = get_parent() as Player

func _ready() -> void:
	player.jumped.connect(_on_jumped)
	player.landed.connect(_on_landed)
	player.movement_state_changed.connect(_on_movement_state_changed)
	player.movement_reset.connect(clear_bursts)

func _on_jumped() -> void:
	play_burst(&"jump", &"JumpBurst", burst_offset)

func _on_landed(_impact_speed: float) -> void:
	play_burst(&"land", &"LandBurst", burst_offset)

func _on_movement_state_changed(state: Player.MovementState) -> void:
	var dashing := state == Player.MovementState.DASHING
	if dashing:
		_dash_facing = player.dash_direction
		if player.is_on_floor():
			play_burst(&"dash_start", &"DashStartBurst", Vector2(0, -15), _dash_facing > 0)
	elif _was_dashing and player.is_on_floor():
		play_burst(&"dash_end", &"DashEndBurst", Vector2(0, -15), _dash_facing > 0)
	_was_dashing = dashing

func play_burst(animation_name: StringName, burst_name: StringName,
		sprite_offset: Vector2, flip_h: bool = false) -> void:
	var burst := AnimatedSprite2D.new()
	burst.name = burst_name
	burst.sprite_frames = FRAMES
	burst.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	burst.offset = sprite_offset
	burst.flip_h = flip_h
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
