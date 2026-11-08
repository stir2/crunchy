class_name PlayerInteractionController
extends Node
## Cached targets and one prompt; independent of movement, grounding and camera.
@export_range(1.0, 256.0, 1.0) var interaction_radius: float = 48.0
@export var enabled: bool = true
@export var origin_path: NodePath = ^"../CollisionShape2D"
@export_range(0.1, 10.0, 0.1) var message_seconds: float = 2.5
var current_target: InteractionTarget
var _targets: Array[InteractionTarget] = []
var _press_armed: bool = false
var _message_time: float = 0.0
@onready var player: Player = get_parent() as Player
@onready var origin: Node2D = get_node(origin_path) as Node2D
@onready var prompt: Label = $Canvas/Panel/Prompt
@onready var message: Label = $Canvas/Panel/Message

func _ready() -> void:
	process_physics_priority = 100 # After movement/ability transitions this tick.
	_press_armed = not Input.is_action_pressed("Interact")
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

func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		current_target = null
		prompt.text = ""
		message.text = ""
		_message_time = 0.0
		_press_armed = not Input.is_action_pressed("Interact")

func actions_allowed() -> bool:
	return enabled and player.is_physics_processing() and not player.damage.is_action_locked() \
		and player.movement_state == Player.MovementState.NORMAL \
		and not player.combat.is_attacking() and not player.combat.is_hitstopped() \
		and not player.combat.is_swing_frozen()

func nearest_target() -> InteractionTarget:
	var nearest: InteractionTarget
	var distance := interaction_radius * interaction_radius
	for target in _targets:
		if not target.is_available(player):
			continue
		var candidate := origin.global_position.distance_squared_to(target.global_position)
		if candidate <= distance:
			# Scene-tree order breaks exact ties; never show more than one prompt.
			if nearest == null or candidate < distance:
				nearest = target
				distance = candidate
	return nearest

func _binding_text() -> String:
	for event in InputMap.action_get_events("Interact"):
		if event is InputEventKey:
			return OS.get_keycode_string(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	return "Interact"

func _update_prompt() -> void:
	current_target = nearest_target() if actions_allowed() else null
	prompt.text = ""
	if current_target != null:
		var text := current_target.get_prompt(player)
		prompt.text = "%s — %s" % [_binding_text(), text] if current_target.can_interact(player) else text

func _physics_process(delta: float) -> void:
	_message_time = maxf(0.0, _message_time-delta)
	if _message_time == 0.0:
		message.text = ""
	var pressed := Input.is_action_pressed("Interact")
	var fresh := _press_armed and Input.is_action_just_pressed("Interact")
	_press_armed = not pressed # Blocked presses are consumed, never buffered.
	_update_prompt()
	if not fresh or current_target == null or not current_target.can_interact(player):
		return
	var result := current_target.interact(player)
	if not result.is_empty():
		message.text = result
		_message_time = message_seconds
	_update_prompt()
