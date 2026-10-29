extends Node2D
## Placeholder feedback only; state changes never touch physics transforms.
@export_range(0.0, 4.0, 1.0) var charge_shake_pixels: float = 1.0
@export_range(1.0, 60.0, 1.0) var charge_shake_frequency: float = 24.0
var _player: Player
var _normal_color: Color
var _rest_position: Vector2
var _charge_time: float = 0.0


func _ready() -> void:
	_normal_color = modulate
	_rest_position = position
	_player = get_parent() as Player
	_player.movement_state_changed.connect(_on_state_changed)
	_player.jump_charge_changed.connect(_on_jump_charge_changed)
	_on_state_changed(_player.movement_state)


func _on_state_changed(state: Player.MovementState) -> void:
	_charge_time = 0.0
	position = _rest_position
	set_process(state == Player.MovementState.DASH_CHARGING)
	match state:
		Player.MovementState.DASH_CHARGING:
			modulate = Color(1.5, 1.1, 0.35)
		Player.MovementState.DASHING:
			modulate = Color(0.4, 1.7, 2.0)
		_:
			modulate = Color(1.25, 1.05, 0.75) if _player.is_jump_charging() else _normal_color


func _on_jump_charge_changed(_charging: bool) -> void:
	_on_state_changed(_player.movement_state)


func _process(delta: float) -> void:
	_charge_time += delta
	var phase: float = _charge_time * TAU * charge_shake_frequency
	# Pixel-sized offsets only. This node is a sibling of every physics shape.
	var offset := Vector2(sin(phase), cos(phase * 0.83)).round() * charge_shake_pixels
	position = _rest_position + offset
