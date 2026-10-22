class_name AbyssRoomTemplateSelector
extends RefCounted
var _templates: Array[AbyssRoomTemplateMetadata] = []
var _seed: int
var _tile_pixels: int
var registration_errors: PackedStringArray = []


func _init(registry: AbyssRoomTemplateRegistry, global_seed: int) -> void:
	_seed = global_seed
	_tile_pixels = registry.tile_pixels
	# Snapshot registry inputs. Invalid/duplicate stable IDs are excluded entirely,
	# rather than choosing whichever definition happens to be registered first.
	var counts: Dictionary = {}
	for metadata in registry.templates:
		if metadata != null:
			counts[metadata.template_id] = int(counts.get(metadata.template_id, 0)) + 1
	for metadata in registry.templates:
		if metadata == null:
			registration_errors.append("Null template")
		elif metadata.template_id == &"" or counts[metadata.template_id] != 1:
			registration_errors.append("Missing/duplicate template ID: %s" % metadata.template_id)
		elif _tile_pixels <= 0 or metadata.tile_pixels != _tile_pixels:
			registration_errors.append("World tile size mismatch: %s" % metadata.template_id)
		elif not is_finite(metadata.selection_weight) or metadata.selection_weight < 0:
			registration_errors.append("Invalid weight: %s" % metadata.template_id)
		else:
			var errors := AbyssRoomTemplateValidator.validate(metadata)
			if not errors.is_empty():
				registration_errors.append("%s: %s" % [metadata.template_id, "; ".join(errors)])
			else:
				_templates.append(metadata.duplicate(true) as AbyssRoomTemplateMetadata)
	_templates.sort_custom(func(a: AbyssRoomTemplateMetadata, b: AbyssRoomTemplateMetadata) -> bool: return String(a.template_id) < String(b.template_id))


static func compatible(metadata: AbyssRoomTemplateMetadata, profile: AbyssRoomOpeningProfile, request: AbyssRoomRequirements) -> bool:
	if metadata.tile_pixels != request.tile_pixels or metadata.room_size != request.room_size or metadata.opening_schema != request.opening_schema:
		return false
	if metadata.region == AbyssRoomTemplateMetadata.Compatibility.TRANSITION:
		if not request.transition or int(metadata.transition_base_region) != int(request.region):
			return false
	elif int(metadata.region) != int(request.region):
		return false
	if profile.variant_id == &"" or (profile.scene == null and metadata.scene == null) or profile.open_sides < 0 or profile.open_sides > 15:
		return false
	if profile.openings.size() != profile.opening_tiles.size():
		return false
	var seen: Dictionary = {}
	for id in profile.openings:
		var tile := request.opening_tile(id)
		if tile == Vector2i(-1, -1) or seen.has(id) or profile.opening_tiles.get(id, Vector2i(-1, -1)) != tile:
			return false
		seen[id] = true
	for id in request.route_openings:
		if request.opening_tile(id) != request.route_openings[id]:
			return false
	if request.region == AbyssRoomData.Region.PACKED and request.required_openings != request.route_openings:
		return false
	if request.region == AbyssRoomData.Region.OPEN:
		# OPEN geometry must have no enclosing boundary. Route absence never seals it.
		return profile.open_sides == 15 and profile.openings.is_empty() and request.required_openings.is_empty()
	# Full open faces are safe only against known OPEN neighbors.
	if profile.open_sides & ~request.neighbor_open_sides:
		return false
	var required: Dictionary = {}
	for id in request.required_openings:
		var side := ["north", "east", "south", "west"].find(String(id).get_slice(":", 0))
		if side < 0 or request.opening_tile(id) != request.required_openings[id]:
			return false
		if not (profile.open_sides & (1 << side)):
			required[id] = request.required_openings[id]
	# Exact combinations prevent unused authored holes from leaking into PACKED.
	return profile.opening_tiles == required


func select(request: AbyssRoomRequirements) -> AbyssRoomConstructionRequest:
	var result := AbyssRoomConstructionRequest.new()
	result.requirements = request
	result.global_seed = _seed
	result.room_seed = _room_seed(request.global_coords)
	if request.tile_pixels != _tile_pixels:
		result.reason = "Registry/world tile size mismatch"
		return result
	var candidates: Array = []
	var total := 0.0
	for metadata in _templates:
		if metadata.selection_weight <= 0:
			continue
		var variants: Array[AbyssRoomOpeningProfile] = []
		var ids: Dictionary = {}
		for profile in metadata.opening_combinations:
			if profile != null:
				ids[profile.variant_id] = int(ids.get(profile.variant_id, 0)) + 1
		for profile in metadata.opening_combinations:
			if profile != null and ids[profile.variant_id] == 1 and compatible(metadata, profile, request):
				variants.append(profile)
		variants.sort_custom(func(a: AbyssRoomOpeningProfile, b: AbyssRoomOpeningProfile) -> bool: return String(a.variant_id) < String(b.variant_id))
		# Template weight is shared among its compatible variants, so adding a
		# cosmetic combination does not multiply the template's overall weight.
		for profile in variants:
			var weight := metadata.selection_weight / variants.size()
			candidates.append([metadata, profile, weight])
			total += weight
	if candidates.is_empty() or not is_finite(total) or total <= 0:
		return result
	var pick := float(result.room_seed) / 2147483647.0 * total
	var chosen: Array = candidates.back()
	for candidate in candidates:
		pick -= candidate[2]
		if pick < 0:
			chosen = candidate
			break
	var metadata: AbyssRoomTemplateMetadata = chosen[0]
	var profile: AbyssRoomOpeningProfile = chosen[1]
	result.method = AbyssRoomConstructionRequest.Method.AUTHORED
	result.template_id = metadata.template_id
	result.variant_id = profile.variant_id
	result.scene = profile.scene if profile.scene != null else metadata.scene
	result.reason = "Compatible authored opening combination"
	return result


func _room_seed(coords: Vector2i) -> int:
	var h := posmod(_seed, 2147483647)
	for value in [coords.x, coords.y, 701]:
		h = (h * 48271 + posmod(value, 2147483647) + 1) % 2147483647
		h = ((h ^ (h >> 13)) * 40699) % 2147483647
	return h


func select_room(generator: AbyssRouteGenerator, coords: Vector2i) -> AbyssRoomConstructionRequest:
	var room := generator.get_room(coords)
	var chunk := generator.get_chunk(generator.regions.room_to_chunk(coords))
	var neighbors: Array[AbyssRoomData] = []
	for direction in AbyssRegionGenerator.DIRECTIONS:
		neighbors.append(generator.get_room(coords + direction))
	return select(AbyssRoomRequirements.from_room(room, chunk.config, chunk.route_config, neighbors, _tile_pixels))
