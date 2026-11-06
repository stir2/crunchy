extends Camera2D
## Shared feedback for lab/runtime cameras. Only camera offset changes.
@export_group("Landing Shake")
@export_range(0.0, 2000.0, 10.0) var landing_shake_min_speed: float = 525.0
@export_range(0.0, 3000.0, 10.0) var landing_shake_full_speed: float = 1000.0
@export_range(0.0, 40.0, 0.25) var landing_shake_pixels: float = 12.0
@export_range(0.01, 1.0, 0.01) var landing_shake_duration: float = 0.30
@export_group("Dash Shake")
@export_range(0.0, 40.0, 0.25) var dash_shake_pixels: float = 8.0
@export_range(0.01, 1.0, 0.01) var dash_shake_duration: float = 0.2
@export_group("Hurt Shake")
@export_range(0.0, 40.0, 0.25) var hurt_shake_pixels: float = 4.0
@export_range(0.01, 1.0, 0.01) var hurt_shake_duration: float = 0.3
var _base_offset: Vector2
var _shake_elapsed: float = 0.0
var _shake_strength: float = 0.0
var _shake_duration: float = 0.14
var _shake_axis: Vector2 = Vector2(0.35,1.0)
var _feedback_player: Player

func _ready() -> void:
	_base_offset = offset
	set_process(false)
	bind_player(get_parent() as Player)

func bind_player(player: Player) -> void:
	if is_instance_valid(_feedback_player):
		_feedback_player.landed.disconnect(_on_landed)
		_feedback_player.movement_state_changed.disconnect(_on_movement_state_changed)
		_feedback_player.get_node("DamageController").damage_reaction.disconnect(_on_hurt)
		_feedback_player.movement_reset.disconnect(reset_shake)
	reset_shake()
	_feedback_player = player
	if player == null:
		return
	player.landed.connect(_on_landed)
	player.movement_state_changed.connect(_on_movement_state_changed)
	player.get_node("DamageController").damage_reaction.connect(_on_hurt)
	player.movement_reset.connect(reset_shake)

func _on_movement_state_changed(state: Player.MovementState) -> void:
	if state == Player.MovementState.DASHING:
		start_shake(dash_shake_pixels,dash_shake_duration,Vector2(1.0,0.35))

func _on_hurt(_hit: CombatHit, _amount: int) -> void:
	start_shake(hurt_shake_pixels,hurt_shake_duration,Vector2.ONE)

func _on_landed(impact_speed: float) -> void:
	if impact_speed <= landing_shake_min_speed or landing_shake_pixels <= 0.0:
		return
	var strength := clampf((impact_speed - landing_shake_min_speed) / maxf(1.0, landing_shake_full_speed - landing_shake_min_speed), 0.0, 1.0)
	start_shake(lerpf(0.35,1.0,strength)*landing_shake_pixels,landing_shake_duration,Vector2(0.35,1.0))

func start_shake(pixels: float, duration: float, axes: Vector2) -> void:
	if pixels <= 0.0:
		return
	# A weaker event must not restart or shorten an ongoing stronger impact.
	var remaining := 1.0-clampf(_shake_elapsed/_shake_duration,0.0,1.0)
	if pixels < _shake_strength*remaining*remaining:
		return
	_base_offset = offset if _shake_strength == 0.0 else _base_offset
	_shake_strength = pixels
	_shake_duration = maxf(0.01,duration)
	_shake_axis = axes
	_shake_elapsed = 0.0
	_apply_shake()
	set_process(true)

func _process(delta: float) -> void:
	_shake_elapsed += delta
	if _shake_elapsed >= _shake_duration:
		reset_shake()
	else:
		_apply_shake()

func _apply_shake() -> void:
	var progress := clampf(_shake_elapsed / _shake_duration, 0.0, 1.0)
	var envelope := (1.0 - progress) * (1.0 - progress)
	# Frequency is independent of duration. Three cycles in a 0.1-second dash
	# landed on sine zeroes at 60 FPS, erasing the horizontal shake entirely.
	var wave := Vector2(cos(_shake_elapsed * TAU * 17.0), cos(_shake_elapsed * TAU * 23.0)) * _shake_axis
	offset = _base_offset + wave.limit_length(1.0) * _shake_strength * envelope

func reset_shake() -> void:
	offset = _base_offset
	_shake_elapsed = 0.0
	_shake_strength = 0.0
	set_process(false)
