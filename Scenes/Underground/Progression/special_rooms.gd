class_name AbyssSpecialRooms
extends RefCounted
## Random-access placement. Finite per-level/per-50-row searches, never a
## first-generated-room decision. No mutation of region classes or templates.
signal chunk_load_requested(chunk_coords: Vector2i, destination: Dictionary)
var routes: AbyssRouteGenerator
var config: AbyssProgressionConfig
var state: AbyssProgressionState
var world: String
var _bands: Dictionary = {}
var _checkpoint_scores: Dictionary[Vector2i, float] = {}
func _init(generator: AbyssRouteGenerator, settings: AbyssProgressionConfig, mutations: AbyssProgressionState, world_id: String = "") -> void:
	assert(generator.progression != null and settings.is_valid(), "Progression requires boundary-aware routes")
	assert(generator.progression.first_chunk_x == settings.first_chunk_x and generator.progression.level_width_chunks == settings.level_width_chunks, "Route and progression boundaries must match")
	routes = generator
	config = settings.duplicate() as AbyssProgressionConfig
	state = mutations
	world = world_id if not world_id.is_empty() else str(routes.get_chunk(Vector2i.ZERO).config.global_seed)
func _settings() -> AbyssRegionConfig:
	return routes.get_chunk(Vector2i.ZERO).config
func level_at(room: Vector2i) -> int:
	return config.level_at_chunk(routes.regions.room_to_chunk(room).x)
func level_key(level: int) -> String:
	return "%s/level/%d" % [world,level]
func _id(kind: String, level: int, room: Vector2i) -> String:
	return "%s/%s/%d:%d" % [level_key(level),kind,room.x,room.y]
func _roll(room: Vector2i, kind: String) -> float:
	var request := AbyssRoomConstructionRequest.new()
	request.global_seed = _settings().global_seed
	request.requirements = AbyssRoomRequirements.new()
	request.requirements.global_coords = room
	return AbyssRoomRandom.roll(request,"progression",kind)
func _definition(kind: String, level: int, room: Vector2i) -> Dictionary:
	return {"id":_id(kind,level,room),"world_level":level_key(level),"kind":kind,"level":level,"x":room.x,"y":room.y}
func _band(level: int, band: int) -> Dictionary:
	var key := Vector2i(level,band)
	if _bands.has(key):
		return _bands[key]
	var bounds := config.room_bounds(level,_settings().chunk_size.x)
	var best := INF
	var guaranteed: Dictionary = {}
	var gate_best := INF
	var gate: Dictionary = {}
	for y in range(band * config.FRAGMENT_INTERVAL, (band + 1) * config.FRAGMENT_INTERVAL):
		for x in range(bounds.x,bounds.y):
			var coords := Vector2i(x,y)
			var room := routes.regions.get_room(coords)
			# Eligible fragments are on the existing connected logical network.
			if room.region == AbyssRoomData.Region.PACKED:
				var rank := _roll(coords,"guaranteed_fragment")
				if rank < best and not routes.get_room(coords).required_connections.is_empty():
					best = rank
					guaranteed = _definition("fragment",level,coords)
		if level < config.LEVEL_COUNT:
			var left := Vector2i(bounds.y - 1,y)
			if routes.regions.get_room(left).region == AbyssRoomData.Region.OPEN and routes.regions.get_room(left + Vector2i.RIGHT).region == AbyssRoomData.Region.OPEN:
				var rank := _roll(left,"gate")
				if rank < gate_best:
					gate_best = rank
					gate = _definition("gate",level,left)
					gate["destination_level"] = level+1
					gate["fragments_per_key"] = config.FRAGMENTS_PER_KEY
	var result := {"fragment":guaranteed,"gate":gate}
	if guaranteed.is_empty():
		push_error("No eligible PACKED fragment room in level %d interval %d; configuration cannot satisfy progression" % [level,band])
	_bands[key] = result
	return result
func definitions_at(coords: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var level := level_at(coords)
	if level == 0 or coords.y < 0:
		return result
	var band := floori(float(coords.y) / config.FRAGMENT_INTERVAL)
	var choices := _band(level,band)
	var room := routes.get_room(coords)
	if has_checkpoint(coords):
		result.append(_definition("checkpoint",level,coords))
	if room.region == AbyssRoomData.Region.PACKED and not room.required_connections.is_empty():
		var required: Dictionary = choices.fragment
		if (not required.is_empty() and Vector2i(required.x,required.y) == coords) or _roll(coords,"extra_fragment") < config.EXTRA_FRAGMENT_PROBABILITY:
			result.append(_definition("fragment",level,coords))
	var gate: Dictionary = choices.gate
	if not gate.is_empty() and Vector2i(gate.x,gate.y) == coords:
		result.append(gate.duplicate(true))
	return result
func interval_definitions(level: int, interval: int) -> Dictionary:
	if level < 1 or level > config.LEVEL_COUNT or interval < 0:
		return {"fragment":{},"gate":{}}
	return _band(level,interval).duplicate(true)
func checkpoint_destination(id: String) -> Dictionary:
	var entry: Dictionary = state.checkpoints.get(id,{})
	if not entry.get("activated",false) or entry.get("world_level", "") != level_key(int(entry.get("level",0))):
		return {}
	var coords := Vector2i(int(entry.x),int(entry.y))
	return {"id":id,"world_id":world,"level":int(entry.level),"room_coords":coords,"chunk_coords":routes.regions.room_to_chunk(coords),"spawn_position":Vector2(entry.spawn_x,entry.spawn_y)}
func request_checkpoint_chunk(id: String) -> bool:
	var destination := checkpoint_destination(id)
	if destination.is_empty():
		return false
	chunk_load_requested.emit(destination.chunk_coords,destination)
	return true
func gate_at(coords: Vector2i) -> Dictionary:
	if coords.y < 0 or level_at(coords) == 0:
		return {}
	var gate: Dictionary = _band(level_at(coords),floori(float(coords.y) / config.FRAGMENT_INTERVAL)).gate
	return gate if not gate.is_empty() and Vector2i(gate.x,gate.y) == coords else {}
func can_cross(a: Vector2i, b: Vector2i) -> bool:
	if absi(a.x-b.x) + absi(a.y-b.y) != 1:
		return false
	if level_at(a) == level_at(b):
		return level_at(a) != 0
	var gate := gate_at(a if a.x < b.x else b)
	return not gate.is_empty() and state.is_gate_unlocked(gate.id)

func unlock_gate(definition: Dictionary) -> bool:
	if definition.get("kind") != "gate":
		return false
	var actual := gate_at(Vector2i(int(definition.get("x",0)),int(definition.get("y",-1))))
	if actual.is_empty() or actual.id != definition.get("id"):
		return false
	return state.unlock_gate(actual.id,level_key(actual.level))
func gate_status(coords: Vector2i) -> Dictionary:
	var definition := gate_at(coords).duplicate(true)
	if not definition.is_empty():
		definition["unlocked"] = state.is_gate_unlocked(definition.id)
	return definition

func activated_checkpoints() -> Array:
	return state.activated_checkpoints().filter(func(entry: Dictionary) -> bool: return entry.get("world_level", "") == level_key(int(entry.get("level",0))))

func _checkpoint_score(coords: Vector2i) -> float:
	if not _checkpoint_scores.has(coords):
		var valid := coords.y >= 0 and level_at(coords) != 0
		valid = valid and routes.regions.get_room(coords).region == AbyssRoomData.Region.OPEN
		_checkpoint_scores[coords] = _roll(coords,"checkpoint") if valid else -1.0
	return _checkpoint_scores[coords]

func has_checkpoint(coords: Vector2i) -> bool:
	var score := _checkpoint_score(coords)
	if score < 0 or score >= config.checkpoint_probability:
		return false
	var radius := config.checkpoint_min_spacing_rooms
	# Local priority thinning, including a full halo across chunk/interval/level
	# boundaries. Never depend on which neighbor was generated first.
	for dy in range(-radius+1,radius):
		for dx in range(-radius+1,radius):
			if (dx == 0 and dy == 0) or dx*dx+dy*dy >= radius*radius:
				continue
			var neighbor := coords+Vector2i(dx,dy)
			var other := _checkpoint_score(neighbor)
			if other >= 0 and (other < score or (other == score and (neighbor.y < coords.y or (neighbor.y == coords.y and neighbor.x < coords.x)))):
				return false
	return true
