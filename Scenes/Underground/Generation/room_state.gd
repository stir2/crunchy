class_name AbyssRoomState
extends RefCounted
## Mutable state only. Retain this store across chunk/descent reconstruction.
var groups: Dictionary = {}
var markers: Dictionary = {}
static func key(request: AbyssRoomConstructionRequest, kind: String, identity: String) -> String:
	var world := request.world_id if not request.world_id.is_empty() else str(request.global_seed)
	return JSON.stringify([world, request.requirements.global_coords.x, request.requirements.global_coords.y, String(request.template_id), kind, identity])
func serialize() -> String:
	return JSON.stringify({"version":1, "groups":groups, "markers":markers})
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
	groups = value.groups.duplicate(true)
	markers = value.markers.duplicate(true)
	return OK
