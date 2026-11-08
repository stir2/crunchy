class_name AbyssAxisFollowCamera
extends "res://Scenes/Player/player_landing_camera.gd"
## Runtime-owned follow camera. No room-grid snapping or player movement ownership.
enum FollowAxis { HORIZONTAL, VERTICAL }
@export_group("Follow")
@export var follow_offset: Vector2 = Vector2(0,-64)
@export var deadzone: Vector2 = Vector2(24,24)
@export var visibility_margin: Vector2 = Vector2(80,56)
@export_range(1.0, 40.0, 0.5) var horizontal_tracking: float = 12.0
@export_range(1.0, 40.0, 0.5) var vertical_tracking: float = 15.0
@export_range(0.0, 1.0, 0.05) var secondary_axis_weight: float = 0.12
@export_range(0.0, 1000.0, 5.0) var vertical_enter_speed: float = 130.0
@export_range(0.0, 1000.0, 5.0) var vertical_exit_speed: float = 65.0
@export_range(0.0, 2.0, 0.05) var minimum_axis_hold: float = 0.22
var target: Player
var terrain: Node
var axis: FollowAxis = FollowAxis.HORIZONTAL
var axis_switches: int = 0
var _axis_time: float = 0.0
var _settled_time: float = 0.0

func _ready() -> void:
	super._ready()
	process_physics_priority = 100 # After the player's authoritative move.
	set_physics_process(false)

func world_view_size() -> Vector2:
	return get_viewport_rect().size / zoom

func view_rect(at: Vector2) -> Rect2:
	var extent := world_view_size()
	return Rect2(at+offset-extent*0.5,extent)

func activate(player: Player, coverage: Node) -> void:
	target = player
	bind_player(player)
	terrain = coverage
	global_position = target.global_position + follow_offset
	axis = FollowAxis.HORIZONTAL
	_axis_time = 0.0
	axis_switches = 0
	_settled_time = 0.0
	enabled = true
	make_current()
	reset_smoothing()
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	_axis_time += delta
	var desired := target.global_position + follow_offset
	var error := desired-global_position
	var vertical_speed := absf(target.velocity.y)
	var wants_vertical := vertical_speed >= vertical_enter_speed
	wants_vertical = wants_vertical or (target.climbing.is_climbing() and vertical_speed > 1.0)
	wants_vertical = wants_vertical or absf(error.y) > deadzone.y * 2.5
	var settled := vertical_speed <= vertical_exit_speed and absf(error.y) <= deadzone.y * 1.25
	_settled_time = _settled_time + delta if settled else 0.0
	if _axis_time >= minimum_axis_hold:
		if axis == FollowAxis.HORIZONTAL and wants_vertical:
			_switch_axis(FollowAxis.VERTICAL)
		elif axis == FollowAxis.VERTICAL and _settled_time >= minimum_axis_hold:
			_switch_axis(FollowAxis.HORIZONTAL)
	var weight := Vector2(1.0,secondary_axis_weight) if axis == FollowAxis.HORIZONTAL else Vector2(secondary_axis_weight,1.0)
	var movement := Vector2.ZERO
	for i in range(2):
		var outside := signf(error[i]) * maxf(0.0,absf(error[i])-deadzone[i])
		var rate := horizontal_tracking if i == 0 else vertical_tracking
		movement[i] = outside * (1.0-exp(-rate*weight[i]*delta))
	var next := global_position + movement
	# Visibility wins over axis preference during fast dashes/falls. This corrects
	# only excess screen lag, never crossing a room boundary by snapping to its grid.
	var half := world_view_size()*0.5
	var safe := Vector2(maxf(16,half.x-visibility_margin.x),maxf(24,half.y-visibility_margin.y))
	var body_center := target.global_position + Vector2(0,-18)
	next = next.clamp(body_center-safe,body_center+safe)
	# A camera move may reveal terrain only after its collision has settled.
	if terrain == null or terrain.is_rect_ready(view_rect(next).grow(16.0)):
		global_position = next

func _switch_axis(next: FollowAxis) -> void:
	axis = next
	_axis_time = 0.0
	_settled_time = 0.0
	axis_switches += 1
