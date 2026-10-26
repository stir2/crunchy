class_name AbyssSpecialSpawnRequest
extends RoomSpawnRequest
## Typed progression request; deterministic definition and mutable state separate.
var definition: Dictionary = {}
var progression: AbyssSpecialRooms
func activate() -> bool:
	if progression == null or definition.is_empty() or kind != &"checkpoint":
		return false
	progression.state.discover_checkpoint(definition,true)
	return true
func discover() -> void:
	if progression != null and kind == &"checkpoint":
		progression.state.discover_checkpoint(definition)
func collect() -> bool:
	return progression != null and kind == &"fragment" and progression.state.collect_fragment(definition)
func unlock() -> bool:
	return progression != null and kind == &"gate" and progression.unlock_gate(definition)
func is_available() -> bool:
	return selected and eligible and (kind != &"fragment" or not progression.state.fragments.has(definition.id))
func should_spawn() -> bool:
	return is_available()
