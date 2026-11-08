class_name AbyssMapModel
extends RefCounted
## Derived graph only. Never reads streamed-room membership for discovery.
const LEVEL_COLORS := [Color(0.34,0.61,0.58),Color(0.70,0.55,0.31),Color(0.57,0.46,0.68)]
const OTHER_LEVEL := Color(0.60,0.63,0.67,0.35)
var service: AbyssSpecialRooms
var exploration: AbyssExplorationState
var room_size: Vector2i
var tile_pixels: int = 16

func _init(specials: AbyssSpecialRooms, state: AbyssExplorationState, size: Vector2i) -> void:
	service = specials
	exploration = state
	room_size = size

func room_center(coords: Vector2i) -> Vector2:
	return (Vector2(coords)+Vector2(0.5,0.5))*Vector2(room_size*tile_pixels)

func color_for(level: int, current_level: int, visited: bool = true) -> Color:
	var color: Color = LEVEL_COLORS[level-1] if level == current_level and level >= 1 and level <= LEVEL_COLORS.size() else OTHER_LEVEL
	if not visited: color.a *= 0.22
	return color

func connections(coords: Vector2i) -> Array[Dictionary]:
	var room := service.routes.get_room(coords)
	var result: Array[Dictionary] = []
	var explicit_neighbors: Dictionary = {}
	for edge in room.required_connections:
		var neighbor := service.routes.get_room(edge.neighbor)
		var opposite := service.routes.get_chunk(neighbor.chunk_coords).route_config.opening_position((edge.side+2)%4,edge.slot,room_size)
		for reverse in neighbor.required_connections:
			if reverse.edge_id == edge.edge_id:
				opposite = reverse.opening_tile
				break
		result.append({"id":edge.edge_id,"neighbor":edge.neighbor,
			"a":(Vector2(coords*room_size+edge.opening_tile)+Vector2(0.5,0.5))*tile_pixels,
			"b":(Vector2(edge.neighbor*room_size+opposite)+Vector2(0.5,0.5))*tile_pixels,"gate":{}})
		explicit_neighbors[edge.neighbor] = true
	for side in range(4):
		var adjacent := coords+AbyssRegionGenerator.DIRECTIONS[side]
		if explicit_neighbors.has(adjacent) or service.level_at(adjacent) <= 0: continue
		var neighbor := service.routes.get_room(adjacent)
		var gate: Dictionary = {}
		if side in [1,3] and service.level_at(coords) != service.level_at(adjacent):
			gate = service.gate_at(coords if side == 1 else adjacent)
		if not room.allows_open_adjacency(neighbor) and gate.is_empty(): continue
		var tangent := room_size.y*0.5 if side%2 == 1 else room_size.x*0.5
		var a := Vector2(room_size.x-0.5 if side == 1 else 0.5,tangent) if side%2 == 1 else Vector2(tangent,0.5 if side == 0 else room_size.y-0.5)
		var b := Vector2(0.5 if side == 1 else room_size.x-0.5,tangent) if side%2 == 1 else Vector2(tangent,room_size.y-0.5 if side == 0 else 0.5)
		var ordered := coords.y < adjacent.y or (coords.y == adjacent.y and coords.x < adjacent.x)
		var id := "%s/%s" % [AbyssExplorationState.room_key(coords if ordered else adjacent),AbyssExplorationState.room_key(adjacent if ordered else coords)]
		result.append({"id":id,"neighbor":adjacent,"a":(Vector2(coords*room_size)+a)*tile_pixels,
			"b":(Vector2(adjacent*room_size)+b)*tile_pixels,"gate":gate})
	return result

func snapshot(current_level: int) -> Dictionary:
	var nodes: Dictionary = {}
	var edges: Array[Dictionary] = []
	var markers: Array[Dictionary] = []
	var rooms := exploration.visited_rooms(service.world)
	var seen_edges: Dictionary = {}
	for coords in rooms:
		nodes[coords] = {"coords":coords,"position":room_center(coords),"visited":true,
			"color":color_for(service.level_at(coords),current_level)}
	for coords in rooms:
		for connection in connections(coords):
			var adjacent: Vector2i = connection.neighbor
			if not nodes.has(adjacent):
				nodes[adjacent] = {"coords":adjacent,"position":room_center(adjacent),"visited":false,
					"color":color_for(service.level_at(adjacent),current_level,false)}
			if not nodes[adjacent].visited or seen_edges.has(connection.id): continue
			seen_edges[connection.id] = true
			edges.append({"id":connection.id,"from":coords,"to":adjacent,
				"points":PackedVector2Array([room_center(coords),connection.a,connection.b,room_center(adjacent)]),
				"from_color":color_for(service.level_at(coords),current_level),
				"to_color":color_for(service.level_at(adjacent),current_level),
				"unlocked_gate":not connection.gate.is_empty() and service.is_gate_unlocked(connection.gate)})
		for definition in service.definitions_at(coords):
			var active := false
			var position := room_center(coords)
			match definition.kind:
				"checkpoint": active = service.state.checkpoints.get(definition.id,{}).get("activated",false)
				"gate":
					active = service.is_gate_unlocked(definition)
					position = (Vector2(coords*room_size)+Vector2(room_size.x-0.5,room_size.y*0.5))*tile_pixels
				"fragment":
					if not service.state.fragments.has(definition.id): continue
					active = true # Collection memory survives consumption.
			markers.append({"kind":definition.kind,"id":definition.id,"position":position,"active":active})
	# Collection can happen before the dwell threshold. Keep the memory dot even
	# then, without upgrading that room to visited or revealing any of its edges.
	var marker_ids: Dictionary = {}
	for marker in markers: marker_ids[marker.id] = true
	for id: String in service.state.fragments:
		if marker_ids.has(id) or not id.begins_with(service.world+"/level/") or not id.contains("/fragment/"): continue
		var last := id.get_slice("/",id.get_slice_count("/")-1).split(":")
		if last.size() != 2 or not last[0].is_valid_int() or not last[1].is_valid_int(): continue
		markers.append({"kind":"fragment","id":id,"position":room_center(Vector2i(int(last[0]),int(last[1]))),"active":true})
	var grave: Dictionary = exploration.graves.get(service.world,{})
	if not grave.is_empty():
		markers.append({"kind":"grave","id":grave.id,"position":Vector2(grave.position_x,grave.position_y),"active":true})
	return {"nodes":nodes,"edges":edges,"markers":markers}
