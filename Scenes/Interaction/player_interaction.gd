class_name PlayerInteractionController
extends Node
## Independent collection/travel channels; no movement or camera ownership.
@export_range(1.0, 256.0, 1.0) var interaction_radius: float = 48.0
@export var enabled: bool = true
@export var primary_action: StringName = &"Interact 1"
@export var travel_action: StringName = &"Interact 2"
@export var origin_path: NodePath = ^"../CollisionShape2D"
@export_range(0.1, 10.0, 0.1) var message_seconds: float = 2.5
var current_target: InteractionTarget
var travel_target: InteractionTarget
var _targets: Array[InteractionTarget] = []
var _press_armed: bool = false
var _travel_armed: bool = false
var _message_time: float = 0.0
@onready var player: Player = get_parent() as Player
@onready var origin: Node2D = get_node(origin_path) as Node2D
@onready var prompt: Label = $Canvas/Panel/Prompt
@onready var travel_prompt: Label = $Canvas/Panel/TravelPrompt
@onready var message: Label = $Canvas/Panel/Message

func _ready() -> void:
	process_physics_priority = 100 # After movement/ability transitions this tick.
	_press_armed = not Input.is_action_pressed(primary_action)
	_travel_armed = not Input.is_action_pressed(travel_action)
	_discover(get_tree().root)
	get_tree().node_added.connect(_register)
	get_tree().node_removed.connect(_unregister)

func _discover(node: Node) -> void:
	_register(node)
	for child in node.get_children():
		_discover(child)

func _register(node: Node) -> void:
	if node is InteractionTarget and not _targets.has(node):
		_targets.append(node)

func _unregister(node: Node) -> void:
	if node is InteractionTarget:
		_targets.erase(node)
		if current_target == node:
			current_target = null
			prompt.text = ""
		if travel_target == node:
			travel_target = null
			travel_prompt.text = ""

func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		current_target = null
		travel_target = null
		prompt.text = ""
		travel_prompt.text = ""
		message.text = ""
		_message_time = 0.0
		_press_armed = not Input.is_action_pressed(primary_action)
		_travel_armed = not Input.is_action_pressed(travel_action)

func actions_allowed() -> bool:
	return enabled and player.is_physics_processing() and not player.damage.is_action_locked() \
		and player.movement_state == Player.MovementState.NORMAL \
		and not player.combat.is_attacking() and not player.combat.is_hitstopped() \
		and not player.combat.is_swing_frozen()

func nearest_target(channel: InteractionTarget.Channel = InteractionTarget.Channel.PRIMARY) -> InteractionTarget:
	var nearest: InteractionTarget
	var fallback: InteractionTarget
	var distance := interaction_radius * interaction_radius
	var fallback_distance := distance
	for target in _targets:
		if not target.is_available_for_action(player,channel): continue
		var candidate := origin.global_position.distance_squared_to(target.global_position)
		if channel == InteractionTarget.Channel.TRAVEL and (candidate > distance or not can_reach_travel_target(target)):
			continue
		if target.can_interact_for_action(player,channel):
			if candidate <= distance and (nearest == null or candidate < distance):
				nearest = target
				distance = candidate
		elif candidate <= fallback_distance and (fallback == null or candidate < fallback_distance):
			fallback = target # e.g. insufficient-fragment information, without an action prompt.
			fallback_distance = candidate
	return nearest if nearest != null else fallback

func can_reach_travel_target(target: InteractionTarget) -> bool:
	var start := origin.global_position
	var end := target.global_position
	if start.distance_squared_to(end) > interaction_radius * interaction_radius:
		return false
	if start.is_equal_approx(end):
		return true
	var ray := PhysicsRayQueryParameters2D.create(start, end, 1)
	ray.hit_from_inside = true
	return player.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func _binding_text(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var keyboard := OS.get_keycode_string(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
			if not Input.get_connected_joypads().is_empty():
				if action == &"Interact 1": return keyboard + " / Y"
				if action == &"Interact 2": return keyboard + " / RT"
			return keyboard
	return String(action)

func _prompt_for(target: InteractionTarget, channel: InteractionTarget.Channel, action: StringName) -> String:
	if target == null: return ""
	var text := target.get_prompt_for_action(player,channel)
	return "%s â€” %s" % [_binding_text(action),text] if target.can_interact_for_action(player,channel) else text

func _update_prompt() -> void:
	var allowed := actions_allowed()
	current_target = nearest_target() if allowed else null
	travel_target = nearest_target(InteractionTarget.Channel.TRAVEL) if allowed else null
	prompt.text = _prompt_for(current_target,InteractionTarget.Channel.PRIMARY,primary_action)
	travel_prompt.text = _prompt_for(travel_target,InteractionTarget.Channel.TRAVEL,travel_action)

func _perform(target: InteractionTarget, channel: InteractionTarget.Channel) -> void:
	if not is_instance_valid(target) or not actions_allowed(): return
	if not target.can_interact_for_action(player,channel):
		get_node("/root/SoundManager").play_limited(&"error", -23, 0.25)
		return
	var result := target.interact_for_action(player,channel)
	if not result.is_empty():
		message.text = result
		_message_time = message_seconds

func _physics_process(delta: float) -> void:
	_message_time = maxf(0.0, _message_time-delta)
	if _message_time == 0.0: message.text = ""
	var primary_fresh := _press_armed and Input.is_action_just_pressed(primary_action)
	var travel_fresh := _travel_armed and Input.is_action_just_pressed(travel_action)
	_press_armed = not Input.is_action_pressed(primary_action)
	_travel_armed = not Input.is_action_pressed(travel_action)
	_update_prompt()
	# Snapshot both targets first: simultaneous E/X cannot activate then extract
	# at a checkpoint whose travel action was unavailable at the start of the tick.
	var primary := current_target
	var travel := travel_target
	if primary_fresh: _perform(primary,InteractionTarget.Channel.PRIMARY)
	if travel_fresh: _perform(travel,InteractionTarget.Channel.TRAVEL)
	_update_prompt()
