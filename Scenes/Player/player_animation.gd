extends AnimatedSprite2D
## Movement owns physics; combat owns slash playback. Jump/dash poses follow state.
@export_range(0.0, 20.0, 0.5) var idle_speed_threshold: float = 1.0
@export_range(1.05, 4.0, 0.05) var run_threshold_ratio: float = 1.25
@export var idle_offset: Vector2 = Vector2(0, -4)
@export var walk_offset: Vector2 = Vector2(0, -4)
@export var run_offset: Vector2 = Vector2(0, 3)
@export var attack_offset: Vector2 = Vector2(0, 3)
@export var dash_offset: Vector2 = Vector2(0, 3)
@export var jump_offset: Vector2 = Vector2(0, 3)
@export_group("Jump Poses")
@export_range(0, 5) var jump_charge_pose_frame: int = 0
@export_range(0, 5) var jump_rise_frame: int = 1
@export_range(0, 5) var jump_apex_rising_frame: int = 2
@export_range(0, 5) var jump_apex_falling_frame: int = 3
@export_range(0, 5) var jump_fall_frame: int = 4
@export_range(0, 5) var jump_land_frame: int = 5
## Pixels/second around the apex; split the two orange poses at zero velocity.
@export_range(0.0, 200.0, 1.0) var jump_apex_speed: float = 50.0
@export_range(0, 30) var landing_pose_frames: int = 3
var _player: Player
var _landing_until_tick: int = -1
var _next_slash: int = 0

func _ready() -> void:
	_player = get_parent().get_parent() as Player
	_player.jump_charge_changed.connect(_on_jump_charge_changed)
	_player.landed.connect(_on_landed)
	_player.jumped.connect(_clear_landing)
	_player.movement_reset.connect(_on_reset)
	update_animation()

func _on_jump_charge_changed(_charging: bool) -> void:
	update_animation()

func _on_landed(_impact_speed: float) -> void:
	_landing_until_tick = Engine.get_physics_frames() + landing_pose_frames

func _clear_landing() -> void:
	_landing_until_tick = -1

func _on_reset() -> void:
	_clear_landing()
	_next_slash = 0
	update_animation()

func _process(_delta: float) -> void:
	update_animation()

func _pose(name: StringName, pose_frame: int, pose_offset: Vector2) -> void:
	animation = name
	frame = clampi(pose_frame, 0, sprite_frames.get_frame_count(name)-1)
	offset = pose_offset
	speed_scale = 1.0
	pause()

func update_animation() -> void:
	if is_instance_valid(_player.damage) and _player.damage.is_action_locked():
		_pose(&"run", 4, run_offset) # Existing temporary hurt/death indication.
		return
	if is_instance_valid(_player.combat) and _player.combat.is_attacking():
		return # Combat owns both slash variants, including local freeze/hitstop.
	if is_instance_valid(_player.climbing) and _player.climbing.is_climbing():
		var climb_pose := jump_apex_rising_frame # Neutral orange pose while holding.
		if _player.velocity.y < 0.0:
			climb_pose = jump_rise_frame
		elif _player.velocity.y > 0.0:
			climb_pose = jump_fall_frame
		_pose(&"jump", climb_pose, jump_offset)
		return
	if _player.is_jump_movement_paused():
		_pose(&"jump", jump_charge_pose_frame, jump_offset)
		return
	match _player.movement_state:
		Player.MovementState.DASH_CHARGING:
			_pose(&"dash", mini(3, int(_player.dash_charge_ratio * 4.0)), dash_offset)
			return
		Player.MovementState.DASHING:
			var progress := 1.0 - float(_player.dash_phase_frames_remaining) / maxi(1,_player.active_dash_duration_frames)
			_pose(&"dash", 4 + clampi(int(progress * 4.0),0,3), dash_offset)
			return
		Player.MovementState.RECOVERY:
			if _player.velocity.y >= 0.0:
				var progress := 1.0 - float(_player.dash_phase_frames_remaining) / maxi(1,_player.dash_recovery_frames)
				_pose(&"dash", 8 + clampi(int(progress * 4.0),0,3), dash_offset)
				return
	if not _player.is_on_floor() or _player.velocity.y < 0.0:
		update_jump_pose()
		return
	if Engine.get_physics_frames() < _landing_until_tick:
		_pose(&"jump", jump_land_frame, jump_offset)
		return
	var speed := absf(_player.velocity.x)
	var run_threshold := maxf(idle_speed_threshold, _player.run_speed * run_threshold_ratio)
	var next_animation: StringName = &"idle"
	if speed > idle_speed_threshold:
		next_animation = &"run" if speed >= run_threshold else &"walk"
	offset = run_offset if next_animation == &"run" else walk_offset if next_animation == &"walk" else idle_offset
	speed_scale = 1.0
	if animation != next_animation or not is_playing():
		play(next_animation)

func update_jump_pose() -> void:
	var vertical_speed := _player.velocity.y
	var pose_frame := jump_fall_frame
	if vertical_speed < -jump_apex_speed:
		pose_frame = jump_rise_frame
	elif vertical_speed < 0.0:
		pose_frame = jump_apex_rising_frame
	elif vertical_speed <= jump_apex_speed:
		pose_frame = jump_apex_falling_frame
	_pose(&"jump", pose_frame, jump_offset)

func is_attack_animation() -> bool:
	return animation == &"attack" or animation == &"attack_alt"

func play_attack(facing: int) -> void:
	flip_h = false # Both supplied Slash sheets face left.
	get_parent().scale.x = absf(get_parent().scale.x) * -facing
	offset = attack_offset
	speed_scale = 1.0
	var slash: StringName = &"attack" if _next_slash == 0 else &"attack_alt"
	_next_slash = 1 - _next_slash # Cosmetic variants; no queued combo/input changes.
	play(slash)
	set_frame_and_progress(0, 0.0)

func finish_attack() -> void:
	flip_h = true
	get_parent().scale.x = absf(get_parent().scale.x) * _player.facing_direction
	update_animation()
