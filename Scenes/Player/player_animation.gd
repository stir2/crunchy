extends AnimatedSprite2D
## Visual-only locomotion. These sheets have no jump/dash-specific poses.
@export_range(0.0, 20.0, 0.5) var idle_speed_threshold: float = 1.0
## Normal movement walks. Run is reserved for momentum above normal speed.
@export_range(1.05, 4.0, 0.05) var run_threshold_ratio: float = 1.25
## Slower airborne cadence below the high-speed threshold (12 FPS at 0.5).
@export_range(0.1, 1.0, 0.05) var airborne_run_speed_scale: float = 0.5
## Each 100x100 sheet has different transparent padding around the feet.
@export var idle_offset: Vector2 = Vector2(0, -4)
@export var walk_offset: Vector2 = Vector2(0, -4)
@export var run_offset: Vector2 = Vector2(0, 3)
## Temporary crouched anticipation pose from the existing chief run sheet.
@export_range(0, 14) var jump_charge_pose_frame: int = 4
var _player: Player


func _ready() -> void:
	_player = get_parent().get_parent() as Player
	_player.jump_charge_changed.connect(_on_jump_charge_changed)
	update_animation()


func _on_jump_charge_changed(_charging: bool) -> void:
	update_animation()


func _process(_delta: float) -> void:
	update_animation()


func update_animation() -> void:
	if _player.movement_state == Player.MovementState.DASH_CHARGING:
		pause() # Keep the current pose while Visuals supplies tint and shake.
		return
	if _player.is_jump_movement_paused():
		animation = &"run"
		frame = clampi(jump_charge_pose_frame, 0, sprite_frames.get_frame_count(&"run") - 1)
		offset = run_offset
		pause()
		return
	var speed: float = absf(_player.velocity.x)
	var run_threshold: float = maxf(idle_speed_threshold, _player.run_speed * run_threshold_ratio)
	var airborne: bool = not _player.is_on_floor() or _player.velocity.y < 0.0
	speed_scale = airborne_run_speed_scale if airborne and speed < run_threshold else 1.0
	var next_animation: StringName = &"idle"
	if airborne:
		next_animation = &"run" # Keep the jump/fall lively, even without horizontal input.
	elif speed > idle_speed_threshold:
		next_animation = &"run" if speed >= run_threshold else &"walk"
	match next_animation:
		&"idle":
			offset = idle_offset
		&"walk":
			offset = walk_offset
		&"run":
			offset = run_offset
	if animation != next_animation or not is_playing():
		play(next_animation)
