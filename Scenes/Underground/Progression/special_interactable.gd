extends InteractionTarget
## Progression adapter only. Replace the Visuals child without changing state logic.
signal activated
signal collected
signal unlocked
var request: AbyssSpecialSpawnRequest
var _collecting: bool = false
@onready var visuals: Node2D = $Visuals

func _ready() -> void:
	if request == null or request.progression == null:
		enabled = false
		return
	request.progression.state.changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	match request.kind:
		&"checkpoint":
			visuals.set_state(request.progression.state.checkpoints.get(request.definition.id, {}).get("activated", false))
		&"fragment":
			var taken := request.progression.state.fragments.has(request.definition.id)
			visible = not taken or _collecting
			visuals.set_state(taken)
		&"gate":
			visuals.set_state(request.progression.is_gate_unlocked(request.definition))

func is_available(actor: Node2D) -> bool:
	if not super.is_available(actor) or request == null or not request.is_available():
		return false
	match request.kind:
		&"checkpoint":
			var runtime := _runtime(actor)
			return runtime != null and runtime.checkpoint_primary_available(request)
		&"gate": return not request.progression.is_gate_unlocked(request.definition)
		&"fragment": return true
	return false

func can_interact(actor: Node2D) -> bool:
	if not is_available(actor):
		return false
	if request.kind == &"gate":
		return request.progression.state.collected_count(request.definition.world_level) >= int(request.definition.fragments_per_key)
	return true

func get_prompt(actor: Node2D) -> String:
	match request.kind:
		&"checkpoint":
			return "Heal 1 Heart" if request.progression.state.checkpoints.get(request.definition.id,{}).get("activated",false) else "Activate Checkpoint (+1 Heart)"
		&"fragment": return "Collect Key Fragment"
		&"gate":
			var count := request.progression.state.collected_count(request.definition.world_level)
			var required := int(request.definition.fragments_per_key)
			if can_interact(actor):
				return "Unlock Level %d — Fragments %d/%d" % [request.definition.destination_level,count,required]
			return "Level %d locked — Fragments %d/%d" % [request.definition.destination_level,count,required]
	return ""

func _perform_interaction(actor: Node2D) -> String:
	match request.kind:
		&"checkpoint":
			var runtime := _runtime(actor)
			if runtime != null:
				var was_active: bool = request.progression.state.checkpoints.get(request.definition.id,{}).get("activated",false)
				var result := runtime.activate_or_heal_checkpoint(request)
				if not was_active and not result.is_empty(): activated.emit()
				return result
		&"fragment":
			_collecting = true
			if request.collect():
				collected.emit()
				visuals.play_collected()
				return "Key fragment — Level %d: %d/%d" % [request.definition.level,request.progression.state.collected_count(request.definition.world_level),request.progression.config.FRAGMENTS_PER_KEY]
			_collecting = false
		&"gate":
			if request.unlock():
				unlocked.emit()
				return "Level %d unlocked" % request.definition.destination_level
	return ""

func _runtime(actor: Node2D) -> AbyssRuntime:
	var node: Node = actor
	while node != null:
		if node is AbyssRuntime: return node
		node = node.get_parent()
	return null

func is_available_for_action(actor: Node2D, channel: Channel) -> bool:
	if channel == Channel.PRIMARY: return is_available(actor)
	return enabled and is_visible_in_tree() and request != null and request.kind == &"checkpoint" 		and request.is_available() and request.progression.state.checkpoints.get(request.definition.id,{}).get("activated",false)

func can_interact_for_action(actor: Node2D, channel: Channel) -> bool:
	if channel == Channel.PRIMARY: return can_interact(actor)
	var runtime := _runtime(actor)
	return is_available_for_action(actor,channel) and runtime != null and runtime.can_safe_return()

func get_prompt_for_action(actor: Node2D, channel: Channel) -> String:
	return get_prompt(actor) if channel == Channel.PRIMARY else "Return to Village"

func interact_for_action(actor: Node2D, channel: Channel) -> String:
	if channel == Channel.PRIMARY: return interact(actor)
	if not can_interact_for_action(actor,channel): return ""
	var runtime := _runtime(actor)
	if runtime.request_safe_return(self):
		interacted.emit(actor)
		return "Returning to village"
	return ""
