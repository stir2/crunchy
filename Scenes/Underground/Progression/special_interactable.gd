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
		&"checkpoint": return not request.progression.state.checkpoints.get(request.definition.id, {}).get("activated", false)
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
		&"checkpoint": return "Activate Checkpoint"
		&"fragment": return "Collect Key Fragment"
		&"gate":
			var count := request.progression.state.collected_count(request.definition.world_level)
			var required := int(request.definition.fragments_per_key)
			if can_interact(actor):
				return "Unlock Level %d — Fragments %d/%d" % [request.definition.destination_level,count,required]
			return "Level %d locked — Fragments %d/%d" % [request.definition.destination_level,count,required]
	return ""

func _perform_interaction(_actor: Node2D) -> String:
	match request.kind:
		&"checkpoint":
			if request.activate():
				activated.emit()
				return "Checkpoint activated"
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
