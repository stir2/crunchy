class_name AbyssRoomRandom
extends RefCounted
## New feature domains are independent of the established conditional-wall hash.
static func roll(request: AbyssRoomConstructionRequest, domain: String, identity: String) -> float:
	var value := posmod(request.global_seed, 2147483647)
	for number in [request.requirements.global_coords.x, request.requirements.global_coords.y]:
		value = AbyssConditionalWallGroups._mix(value, number)
	for byte in (String(request.template_id) + "\u001f" + domain + "\u001f" + identity).to_utf8_buffer():
		value = AbyssConditionalWallGroups._mix(value, byte)
	for salt in [1009,1013,1019,1021]:
		value = AbyssConditionalWallGroups._mix(value, salt)
	return float(value) / 2147483647.0
