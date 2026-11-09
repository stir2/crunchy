class_name AbyssRoomState
extends RefCounted
## Mutable state only. Retain this store across chunk/descent reconstruction.
var groups: Dictionary = {}
var markers: Dictionary = {}
## Saved world definition and actor handoff; independent of room load order.
var world_settings: Dictionary = {}
var player_vitals: Dictionary = {}
var current_day: int = -1
var exploration := AbyssExplorationState.new()

## Only daily breakable mutations reset. Marker/progression state stays permanent.
func begin_day(day_number: int) -> bool:
	if day_number < 1 or day_number == current_day:
		return false
	var changed_day := current_day >= 1
	if changed_day:
		exploration.graves.clear()
		exploration.descent_souls.clear()
		exploration.active_descents.clear()
		exploration.checkpoint_heals.clear()
		player_vitals.clear()
		exploration.changed.emit()
		for identity in groups.keys():
			if not String(identity).begins_with("["):
				continue
			var parts: Variant = JSON.parse_string(identity)
			if parts is Array and parts.size() == 6 and parts[4] == "breakable":
				groups.erase(identity)
	current_day = day_number
	return changed_day
static func key(request: AbyssRoomConstructionRequest, kind: String, identity: String) -> String:
	var world := request.world_id if not request.world_id.is_empty() else str(request.global_seed)
	return JSON.stringify([world, request.requirements.global_coords.x, request.requirements.global_coords.y, String(request.template_id), kind, identity])
func serialize() -> String:
	return JSON.stringify({"version":1, "groups":groups, "markers":markers,
		"world_settings":world_settings, "player_vitals":player_vitals, "current_day":current_day,"exploration":exploration.serialize()})
func restore(json: String) -> Error:
	var value: Variant = JSON.parse_string(json)
	if not value is Dictionary or value.get("version") != 1 or not value.get("groups") is Dictionary or not value.get("markers") is Dictionary:
		return ERR_INVALID_DATA
	for key_value in value.groups:
		var health: Variant = value.groups[key_value]
		if not key_value is String or not (health is int or health is float) or not is_finite(float(health)) or health < 0:
			return ERR_INVALID_DATA
	for key_value in value.markers:
		if not key_value is String or not value.markers[key_value] is String:
			return ERR_INVALID_DATA
	if not value.get("world_settings", {}) is Dictionary or not value.get("player_vitals", {}) is Dictionary:
		return ERR_INVALID_DATA
	var saved_day: Variant = value.get("current_day", -1)
	if not (saved_day is int or saved_day is float) or not is_finite(float(saved_day)) or saved_day != int(saved_day) or saved_day < -1:
		return ERR_INVALID_DATA
	var vitals: Dictionary = value.get("player_vitals", {})
	if not vitals.is_empty() and (not vitals.has("health") or not vitals.has("stamina")):
		return ERR_INVALID_DATA
	for number in vitals.values():
		if not (number is int or number is float) or not is_finite(float(number)) or number < 0:
			return ERR_INVALID_DATA
	if not value.get("exploration",{}) is Dictionary:
		return ERR_INVALID_DATA
	var explored := AbyssExplorationState.new()
	if explored.restore(value.get("exploration",{})) != OK:
		return ERR_INVALID_DATA
	exploration = explored
	groups = value.groups.duplicate(true)
	markers = value.markers.duplicate(true)
	world_settings = value.get("world_settings", {}).duplicate(true)
	player_vitals = value.get("player_vitals", {}).duplicate(true)
	current_day = int(saved_day)
	return OK
