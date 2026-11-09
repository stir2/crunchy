class_name AbyssProgressionState
extends RefCounted
## Mutable progression only; no generated terrain/template definitions.
signal changed
signal fragment_collected
signal key_assembled
signal gate_unlocked
var checkpoints: Dictionary = {}
var fragments: Dictionary = {}
var gates: Dictionary = {}
var keys: Dictionary = {}
## Collection ledger is permanent; consumption never deletes a collected ID.
var consumed_fragments: Dictionary = {}
## Keys are destination world/level IDs, shared by every gate into that level.
var unlocked_levels: Dictionary = {}

func activate_checkpoint(definition: Dictionary) -> bool:
	if checkpoints.get(definition.id, {}).get("activated", false):
		return false
	discover_checkpoint(definition, true)
	return true

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
	fragment_collected.emit()
	return true
func collected_count(world_level_id: String) -> int:
	var count := 0
	for id in fragments:
		if fragments[id] == world_level_id and not consumed_fragments.get(id, false):
			count += 1
	return count
func can_assemble_key(world_level_id: String) -> bool:
	return collected_count(world_level_id) >= AbyssProgressionConfig.FRAGMENTS_PER_KEY
## Future blacksmith calls this AFTER crafting. No crafting/inventory here.
func record_assembled_key(world_level_id: String) -> void:
	var first_assembly: bool = not keys.get(world_level_id, false)
	keys[world_level_id] = true
	changed.emit()
	if first_assembly:
		key_assembled.emit()
func unlock_gate(id: String, world_level_id: String) -> bool:
	if not keys.get(world_level_id, false):
		return false
	var was_unlocked := is_gate_unlocked(id)
	gates[id] = true
	var destination := destination_for_gate_id(id)
	if not destination.is_empty():
		unlocked_levels[destination] = true
	changed.emit()
	if not was_unlocked:
		gate_unlocked.emit()
	return true
func destination_for_gate_id(id: String) -> String:
	# Existing IDs are <world>/level/<source>/gate/<room-x>:<room-y>.
	var separator := id.rfind("/level/")
	if separator < 0:
		return ""
	var suffix := id.substr(separator+7).split("/")
	if suffix.size() != 3 or suffix[1] != "gate" or not suffix[0].is_valid_int():
		return ""
	return id.left(separator) + "/level/" + str(int(suffix[0])+1)

func is_gate_unlocked(id: String) -> bool:
	return gates.get(id, false) or unlocked_levels.get(destination_for_gate_id(id), false)

## Synchronous transaction: spend before emitting once, with no await/reentrancy gap.
func unlock_level(destination_id: String, fragment_level_id: String, required: int) -> bool:
	if destination_id.is_empty() or unlocked_levels.get(destination_id, false) or required <= 0:
		return false
	var available: Array[String] = []
	for id: String in fragments:
		if fragments[id] == fragment_level_id and not consumed_fragments.get(id, false):
			available.append(id)
	if available.size() < required:
		return false
	available.sort()
	for index in range(required):
		consumed_fragments[available[index]] = true
	unlocked_levels[destination_id] = true
	changed.emit()
	gate_unlocked.emit()
	return true
func serialize() -> String:
	return JSON.stringify({"version":2,"checkpoints":checkpoints,"fragments":fragments,"gates":gates,"keys":keys,"consumed_fragments":consumed_fragments,"unlocked_levels":unlocked_levels})
func restore(json: String) -> Error:
	var data: Variant = JSON.parse_string(json)
	if not data is Dictionary or (data.get("version") != 1 and data.get("version") != 2):
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
		if not id is String or not data.fragments[id] is String:
			return ERR_INVALID_DATA
	for name in ["gates","keys"]:
		for id in data[name]:
			if not id is String or not data[name][id] is bool:
				return ERR_INVALID_DATA
	var consumed: Variant = data.get("consumed_fragments", {})
	var unlocked: Variant = data.get("unlocked_levels", {})
	if not consumed is Dictionary or not unlocked is Dictionary:
		return ERR_INVALID_DATA
	if data.version == 2 and (not data.has("consumed_fragments") or not data.has("unlocked_levels")):
		return ERR_INVALID_DATA
	for id in consumed:
		if not id is String or not consumed[id] is bool or not data.fragments.has(id):
			return ERR_INVALID_DATA
	for id in unlocked:
		if not id is String or not unlocked[id] is bool:
			return ERR_INVALID_DATA
	# Old purchased gates promote the whole destination; never relock old progress.
	unlocked = unlocked.duplicate(true)
	for id: String in data.gates:
		var destination := destination_for_gate_id(id)
		if data.gates[id] and not destination.is_empty():
			unlocked[destination] = true
	consumed_fragments = consumed.duplicate(true)
	unlocked_levels = unlocked
	checkpoints = data.checkpoints.duplicate(true)
	fragments = data.fragments.duplicate(true)
	gates = data.gates.duplicate(true)
	keys = data.keys.duplicate(true)
	changed.emit()
	return OK
