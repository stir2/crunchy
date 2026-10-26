class_name AbyssProgressionState
extends RefCounted
## Mutable progression only; no generated terrain/template definitions.
signal changed
var checkpoints: Dictionary = {}
var fragments: Dictionary = {}
var gates: Dictionary = {}
var keys: Dictionary = {}
func discover_checkpoint(definition: Dictionary, activate: bool = false) -> void:
	var entry: Dictionary = definition.duplicate(true)
	entry["discovered"] = true
	entry["activated"] = activate or checkpoints.get(definition.id, {}).get("activated", false)
	checkpoints[definition.id] = entry
	changed.emit()
func activated_checkpoints() -> Array:
	var result := checkpoints.values().filter(func(entry: Dictionary) -> bool: return entry.get("activated", false)).duplicate(true)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return result
func collect_fragment(definition: Dictionary) -> bool:
	if fragments.has(definition.id):
		return false
	fragments[definition.id] = definition.world_level
	changed.emit()
	return true
func collected_count(world_level_id: String) -> int:
	return fragments.values().count(world_level_id)
func can_assemble_key(world_level_id: String) -> bool:
	return collected_count(world_level_id) >= AbyssProgressionConfig.FRAGMENTS_PER_KEY
## Future blacksmith calls this AFTER crafting. No crafting/inventory here.
func record_assembled_key(world_level_id: String) -> void:
	keys[world_level_id] = true
	changed.emit()
func unlock_gate(id: String, world_level_id: String) -> bool:
	if not keys.get(world_level_id, false):
		return false
	gates[id] = true
	changed.emit()
	return true
func is_gate_unlocked(id: String) -> bool:
	return gates.get(id, false)
func serialize() -> String:
	return JSON.stringify({"version":1,"checkpoints":checkpoints,"fragments":fragments,"gates":gates,"keys":keys})
func restore(json: String) -> Error:
	var data: Variant = JSON.parse_string(json)
	if not data is Dictionary or data.get("version") != 1:
		return ERR_INVALID_DATA
	for name in ["checkpoints","fragments","gates","keys"]:
		if not data.get(name) is Dictionary:
			return ERR_INVALID_DATA
	for id in data.checkpoints:
		if not id is String or not data.checkpoints[id] is Dictionary:
			return ERR_INVALID_DATA
		var entry: Dictionary = data.checkpoints[id]
		for field in ["x","y","level","spawn_x","spawn_y"]:
			if not (entry.get(field) is float or entry.get(field) is int) or not is_finite(float(entry[field])):
				return ERR_INVALID_DATA
		for field in ["activated","discovered"]:
			if not entry.get(field) is bool:
				return ERR_INVALID_DATA
		for field in ["id","kind","world_level"]:
			if not entry.get(field) is String:
				return ERR_INVALID_DATA
		for field in ["x","y","level"]:
			entry[field] = int(entry[field])
	for id in data.fragments:
		if not data.fragments[id] is String:
			return ERR_INVALID_DATA
	for name in ["gates","keys"]:
		for id in data[name]:
			if not data[name][id] is bool:
				return ERR_INVALID_DATA
	checkpoints = data.checkpoints.duplicate(true)
	fragments = data.fragments.duplicate(true)
	gates = data.gates.duplicate(true)
	keys = data.keys.duplicate(true)
	changed.emit()
	return OK
