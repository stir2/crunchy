extends Camera2D
## Small, damped impact shake; camera offset alone changes, never player physics.
@export_range(0.0, 2000.0, 10.0) var landing_shake_min_speed: float = 550.0
@export_range(0.0, 3000.0, 10.0) var landing_shake_full_speed: float = 1000.0
@export_range(0.0, 10.0, 0.25) var landing_shake_pixels: float = 3.0
@export_range(0.01, 1.0, 0.01) var landing_shake_duration: float = 0.14
var _base_offset: Vector2
var _shake_elapsed: float = 0.0
var _shake_strength: float = 0.0

func _ready() -> void:
	_base_offset = offset
	var player := get_parent() as Player
	player.landed.connect(_on_landed)
	player.movement_reset.connect(reset_shake)
	set_process(false)

func _on_landed(impact_speed: float) -> void:
	if impact_speed <= landing_shake_min_speed or landing_shake_pixels <= 0.0:
		return
	_base_offset = offset if _shake_strength == 0.0 else _base_offset
	var strength := clampf((impact_speed - landing_shake_min_speed) / maxf(1.0, landing_shake_full_speed - landing_shake_min_speed), 0.0, 1.0)
	_shake_strength = maxf(_shake_strength, lerpf(0.35, 1.0, strength) * landing_shake_pixels)
	_shake_elapsed = 0.0
	_apply_shake()
	set_process(true)

func _process(delta: float) -> void:
	_shake_elapsed += delta
	if _shake_elapsed >= landing_shake_duration:
		reset_shake()
	else:
		_apply_shake()

func _apply_shake() -> void:
	var progress := clampf(_shake_elapsed / landing_shake_duration, 0.0, 1.0)
	var envelope := (1.0 - progress) * (1.0 - progress)
	var wave := Vector2(sin(progress * TAU * 3.0) * 0.35, cos(progress * TAU * 4.0))
	offset = _base_offset + wave * _shake_strength * envelope

func reset_shake() -> void:
	offset = _base_offset
	_shake_elapsed = 0.0
	_shake_strength = 0.0
	set_process(false)
