extends Node
## Choose the existing public aiming mode from the Attack event's device.
## No new attack action, buffered input, or changes to combat timing/AI.
var _controllers: Dictionary = {}
var _keyboard_attack: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_register)
	get_tree().node_removed.connect(_unregister)
	_scan(get_tree().root)

func _scan(node: Node) -> void:
	_register(node)
	for child in node.get_children(): _scan(child)

func _register(node: Node) -> void:
	if not node is PlayerCombatController: return
	var id := node.get_instance_id()
	if _controllers.has(id): return
	_controllers[id] = {"controller": weakref(node), "mouse_aim": node.mouse_aim_attacks}
	_apply(_controllers[id])

func _unregister(node: Node) -> void:
	_controllers.erase(node.get_instance_id())

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("Attack") or event.is_echo(): return
	# A held keyboard attack keeps facing-based repeats until a mouse attack.
	if event is InputEventKey or event is InputEventJoypadButton:
		_keyboard_attack = true
	elif event is InputEventMouseButton:
		_keyboard_attack = false
	else:
		return
	for entry: Dictionary in _controllers.values(): _apply(entry)

func _apply(entry: Dictionary) -> void:
	var controller := entry.controller.get_ref() as PlayerCombatController
	if is_instance_valid(controller):
		controller.mouse_aim_attacks = bool(entry.mouse_aim) and not _keyboard_attack
