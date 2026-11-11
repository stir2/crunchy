class_name AbyssKeyFragmentArt
extends RefCounted
## Appearance follows the existing unspent per-level ledger, including old saves.
static func next_half(state: AbyssProgressionState, level_id: String) -> int:
	return state.collected_count(level_id) % 2

static func visible_halves(state: AbyssProgressionState, level_id: String) -> int:
	return mini(state.collected_count(level_id), 2)
