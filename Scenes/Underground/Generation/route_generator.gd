class_name AbyssRouteGenerator
extends RefCounted
## Independent logical pass. Layout version 3 changes routes, never region noise.
var regions: AbyssRegionGenerator
var _config: AbyssRegionConfig
var _routes: AbyssRouteConfig
var _chunks: Dictionary[Vector2i, AbyssChunkData] = {}
var _diagnostics: Dictionary = {}
const DIRS = AbyssRegionGenerator.DIRECTIONS


func _init(config: AbyssRegionConfig, routes: AbyssRouteConfig) -> void:
	assert(config.is_valid() and routes.is_valid(config.room_size))
	_config = config.duplicate() as AbyssRegionConfig
	_routes = routes.duplicate() as AbyssRouteConfig
	regions = AbyssRegionGenerator.new(_config)


func _hash(pos: Vector2i, salt: int) -> int:
	var h := posmod(_config.global_seed, 2147483647)
	for value in [pos.x, pos.y, salt]:
		h = (h * 48271 + posmod(value, 2147483647) + 1) % 2147483647
		# Mix high bits back into low bits: adjacent coordinates must not simply
		# translate every boundary anchor by the same modular offset.
		h = ((h ^ (h >> 13)) * 40699) % 2147483647
	return h


## Random-access macro planner. Only two nearby waypoint hashes are needed.
## Knot zero is anchored at the entrance; no summation over previous depths.
func main_column(band: int) -> int:
	var scale := _routes.main_route_wander_scale
	var knot := floori(float(band) / scale)
	var t := float(posmod(band, scale)) / scale
	t = t * t * (3.0 - 2.0 * t)
	var amplitude := minf(_routes.main_route_horizontal_wander, _routes.main_route_max_horizontal_drift)
	var a := 0.0 if knot == 0 else (float(_hash(Vector2i(0, knot), 503)) / 2147483647.0 * 2.0 - 1.0) * amplitude
	var b := 0.0 if knot + 1 == 0 else (float(_hash(Vector2i(0, knot + 1), 503)) / 2147483647.0 * 2.0 - 1.0) * amplitude
	return _routes.entrance_chunk_x + clampi(roundi(lerpf(a, b, t)), -_routes.main_route_max_horizontal_drift, _routes.main_route_max_horizontal_drift)


## Ordered, adjacent chunk visits within one row, followed by a downward step.
## Interpolation keeps default migration gradual; broad/fast settings may visit
## several adjacent columns in a row, but always finish with a downward contract.
func main_chunks_for_band(band: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var start := main_column(band)
	var finish := main_column(band + 1)
	var direction := 1 if finish >= start else -1
	for x in range(start, finish + direction, direction):
		result.append(Vector2i(x, band))
	return result


func is_main_chunk(coords: Vector2i) -> bool:
	return coords.x >= mini(main_column(coords.y), main_column(coords.y + 1)) and coords.x <= maxi(main_column(coords.y), main_column(coords.y + 1))


func entrance_for_band(band: int) -> Vector2i:
	return Vector2i(main_column(band) * _config.chunk_size.x + _hash(Vector2i(0, band), 101) % _config.chunk_size.x, band * _config.chunk_size.y)


func entrance_room() -> Vector2i:
	return entrance_for_band(0)


## Side parents approach a fixed hub-column/row within each attachment band.
## Main chunks instead follow the ordered descent, never pointing to side chunks.
## Side potential (|x-hub_x|, |y-hub_y|) decreases lexicographically, so it
## reaches a main chunk without cycles even when the main corridor is moving.
func parent_chunk(coords: Vector2i) -> Vector2i:
	if is_main_chunk(coords):
		var finish := main_column(coords.y + 1)
		return coords + (Vector2i(signi(finish - coords.x), 0) if coords.x != finish else Vector2i.DOWN)
	var band := floori(float(coords.y) / _routes.attachment_band_height)
	var hub_y := band * _routes.attachment_band_height + _hash(Vector2i(0, band), 191) % _routes.attachment_band_height
	var hub_x := main_column(hub_y)
	if coords.y != hub_y and (coords.x == hub_x or _hash(coords, 197) % 100 < 48):
		return coords + Vector2i(0, signi(hub_y - coords.y))
	return coords + Vector2i(signi(hub_x - coords.x), 0)


func _is_main_transition(a: Vector2i, b: Vector2i) -> bool:
	return (is_main_chunk(a) and parent_chunk(a) == b) or (is_main_chunk(b) and parent_chunk(b) == a)


static func _edge_id(a: Vector2i, b: Vector2i) -> String:
	if a.y > b.y or (a.y == b.y and a.x > b.x):
		return _edge_id(b, a)
	return "%d:%d/%d:%d" % [a.x, a.y, b.x, b.y]


## Canonical port per neighboring chunk pair. The returned a endpoint belongs
## to coords, b to its neighbor. Contract existence never depends on caches.
func boundary_contracts(coords: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var origin := coords * _config.chunk_size
	for side in range(4):
		var neighbor: Vector2i = coords + DIRS[side]
		var canonical := coords if side == 1 or side == 2 else neighbor
		var spine := _is_main_transition(coords, neighbor)
		var tree := parent_chunk(coords) == neighbor or parent_chunk(neighbor) == coords
		var optional := float(_hash(canonical, 229 + side % 2)) / 2147483647.0 < _routes.inter_chunk_loop_probability and _routes.reconnection_probability > 0 and _routes.branching_probability > 0
		if not spine and not tree and not optional:
			continue
		var a: Vector2i
		if side % 2 == 0:
			var column := entrance_for_band(maxi(coords.y, neighbor.y)).x - origin.x if spine else _hash(canonical, 233) % _config.chunk_size.x
			a = origin + Vector2i(column, 0 if side == 0 else _config.chunk_size.y - 1)
		else:
			a = origin + Vector2i(_config.chunk_size.x - 1 if side == 1 else 0, _hash(canonical, 239) % _config.chunk_size.y)
		var kind := AbyssRouteConnection.Kind.MAIN if spine else (AbyssRouteConnection.Kind.ACCESS if tree else AbyssRouteConnection.Kind.RECONNECTION)
		result.append({"a": a, "b": a + DIRS[side], "kind": kind, "side": side})
	return result


func _add(edges: Dictionary, a: Vector2i, b: Vector2i, kind: int) -> void:
	var id := _edge_id(a, b)
	if not edges.has(id):
		edges[id] = [a, b, kind]


func _direction_choices(pos: Vector2i, rect: Rect2i, used: Dictionary, previous: Vector2i, run: int, goal: Vector2i, rng: RandomNumberGenerator, downward: bool) -> Array[Vector2i]:
	var ranked: Array = []
	for direction in DIRS:
		var next: Vector2i = pos + direction
		if not rect.has_point(next) or used.has(next):
			continue
		var weight := 1.0
		if downward:
			weight = _routes.downward_preference if direction == Vector2i.DOWN else (1.0 - _routes.downward_preference) / 3.0
		elif (goal - next).length_squared() < (goal - pos).length_squared():
			weight *= 1.6
		if direction == previous:
			weight *= 1.0 + _routes.directional_persistence * 4.0
		else:
			weight *= _routes.turning_weight
		if direction == previous and run >= _routes.max_straight_run and rect.size.x > 1 and rect.size.y > 1:
			continue
		# Weighted random permutation; search tries alternate directions instead
		# of aborting at the first invalid or occupied candidate.
		ranked.append([ -log(maxf(rng.randf(), 0.000001)) / maxf(weight, 0.000001), direction])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var result: Array[Vector2i] = []
	for pair in ranked:
		result.append(pair[1])
	return result


## Bounded randomized self-avoiding DFS. Retains a valid shorter solution if
## the preferred stretch cannot be met; exhaustive retries never block runtime.
func _path(rect: Rect2i, start: Vector2i, goal: Vector2i, rng: RandomNumberGenerator, preferred_steps: int = 0, retry: int = 0) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	if start == goal:
		return path
	var used: Dictionary = {start: true}
	var choices: Array = []
	var exhausted: Dictionary = {}
	var best: Array[Vector2i] = []
	for attempt in range(maxi(64, rect.get_area() * 60)):
		if path.is_empty():
			break
		var current: Vector2i = path.back()
		if current == goal:
			if path.size() > best.size():
				best = path.duplicate()
			if path.size() - 1 >= preferred_steps:
				return path
			used.erase(path.pop_back())
			continue
		if choices.size() < path.size():
			var previous: Vector2i = Vector2i.ZERO if path.size() < 2 else current - path[-2]
			var run := 0
			for i in range(path.size() - 1, 0, -1):
				if path[i] - path[i - 1] != previous:
					break
				run += 1
			choices.append(_direction_choices(current, rect, used, previous, run, goal, rng, preferred_steps > 0))
		if choices.back().is_empty():
			choices.pop_back()
			exhausted[current] = true
			used.erase(path.pop_back())
			continue
		var next: Vector2i = current + choices.back().pop_front()
		if used.has(next) or exhausted.has(next):
			continue
		used[next] = true
		path.append(next)
	if not best.is_empty():
		return best
	if retry < 5:
		return _path(rect, start, goal, rng, preferred_steps, retry + 1)
	# Guaranteed finite Manhattan fallback on an obstacle-free logical room grid.
	path = [start]
	while path.back() != goal:
		var pos: Vector2i = path.back()
		path.append(pos + (Vector2i(signi(goal.x - pos.x), 0) if pos.x != goal.x else Vector2i(0, signi(goal.y - pos.y))))
	return path


func _append_path(edges: Dictionary, path: Array[Vector2i], kind: int) -> void:
	for i in range(1, path.size()):
		_add(edges, path[i - 1], path[i], kind)


func _occupied(edges: Dictionary, rect: Rect2i) -> Dictionary:
	var result: Dictionary = {}
	for edge in edges.values():
		for pos in [edge[0], edge[1]]:
			if rect.has_point(pos):
				result[pos] = true
	return result


func _grow_branches(edges: Dictionary, rect: Rect2i, rng: RandomNumberGenerator) -> Array:
	var occupied := _occupied(edges, rect)
	var depth: Dictionary = {}
	var roots: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var pos := Vector2i(x, y)
			if occupied.has(pos):
				depth[pos] = 0
				roots.append(pos)
	# Shuffle with this chunk's RNG; never depend on dictionary iteration order.
	for i in range(roots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp := roots[i]
		roots[i] = roots[j]
		roots[j] = temp
	var branches: Array = []
	var index := 0
	var density_limit := maxi(occupied.size(), ceili(rect.get_area() * _routes.room_density))
	while index < roots.size() and occupied.size() < density_limit:
		var root := roots[index]
		index += 1
		var chance := _routes.branching_probability * (1.0 if depth[root] == 0 else _routes.secondary_branch_probability)
		if rng.randf() >= chance:
			continue
		var budget := mini(rng.randi_range(_routes.branch_min_length, _routes.branch_max_length), _routes.branch_max_length - int(depth[root]))
		var path: Array[Vector2i] = [root]
		var current := root
		var previous := Vector2i.ZERO
		var run := 0
		for step in range(budget):
			if occupied.size() >= density_limit:
				break
			var choices := _direction_choices(current, rect, occupied, previous, run, current, rng, false)
			if choices.is_empty():
				break
			var direction: Vector2i = choices.front()
			var next := current + direction
			_add(edges, current, next, AbyssRouteConnection.Kind.BRANCH)
			occupied[next] = true
			depth[next] = int(depth[current]) + 1
			path.append(next)
			run = run + 1 if direction == previous else 1
			previous = direction
			current = next
		if path.size() > 1:
			branches.append(path)
			# Interior branch points can grow branches of their own. Total depth
			# is bounded by the legacy maximum growth budget, not recursion order.
			for i in range(1, path.size()):
				if depth[path[i]] < _routes.branch_max_length:
					roots.append(path[i])
	return branches


func _add_loops(edges: Dictionary, rect: Rect2i, rng: RandomNumberGenerator) -> void:
	var occupied := _occupied(edges, rect)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var pos := Vector2i(x, y)
			if not occupied.has(pos):
				continue
			for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
				var next: Vector2i = pos + direction
				if occupied.has(next) and not edges.has(_edge_id(pos, next)) and rng.randf() < _routes.reconnection_probability:
					_add(edges, pos, next, AbyssRouteConnection.Kind.RECONNECTION)


func get_chunk(coords: Vector2i) -> AbyssChunkData:
	if _chunks.has(coords):
		return _chunks[coords]
	var chunk := regions.get_chunk(coords)
	chunk.route_config = _routes
	var rect := Rect2i(coords * _config.chunk_size, _config.chunk_size)
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash(coords, 307)
	var edges: Dictionary = {}
	var contracts := boundary_contracts(coords)
	var main_path: Array[Vector2i] = []
	# Stage 1: immutable boundary contracts. Stage 2: winding primary path.
	if is_main_chunk(coords):
		var entry := Vector2i.ZERO
		var exit := Vector2i.ZERO
		for contract in contracts:
			if contract.kind == AbyssRouteConnection.Kind.MAIN:
				if regions.room_to_chunk(contract.b) == parent_chunk(coords):
					exit = contract.a
				else:
					entry = contract.a
		var preferred := mini(ceili((entry - exit).length() * _routes.main_path_stretch), floori(rect.get_area() * 0.65))
		main_path = _path(rect, entry, exit, rng, maxi(1, preferred))
		_append_path(edges, main_path, AbyssRouteConnection.Kind.MAIN)
	# Every port connects to an existing interior network. A side chunk starts
	# at its parent port; child and optional ports need no full-width highway.
	var root: Vector2i = main_path[0] if not main_path.is_empty() else contracts[0].a
	if not is_main_chunk(coords):
		for contract in contracts:
			if regions.room_to_chunk(contract.b) == parent_chunk(coords):
				root = contract.a
	var network: Dictionary = _occupied(edges, rect)
	network[root] = true
	for contract in contracts:
		var start: Vector2i = contract.a
		if not network.has(start):
			var target := root
			var distance := 2147483647
			# Stable order for nearest network attachment (tie is row-major).
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					var pos := Vector2i(x, y)
					var d := absi(pos.x - start.x) + absi(pos.y - start.y)
					if network.has(pos) and d < distance:
						target = pos
						distance = d
			var path := _path(rect, start, target, rng)
			# Attach only once. Touching the existing network earlier ends the
			# connector; cycles belong to the explicit reconnection stage.
			for i in range(path.size()):
				if network.has(path[i]):
					path.resize(i + 1)
					break
			_append_path(edges, path, AbyssRouteConnection.Kind.ACCESS)
			for pos in path:
				network[pos] = true
		_add(edges, contract.a, contract.b, contract.kind)
	# Stages 3 and 4: bounded branch trees, then deliberate loop edges.
	var branches := _grow_branches(edges, rect, rng)
	if _routes.branching_probability > 0:
		_add_loops(edges, rect, rng)
	_diagnostics[coords] = {"main_path": main_path, "branches": branches, "contracts": contracts, "edges": edges}
	# Stage 5: validate the finite interior network (external contracts excluded).
	assert(validate_chunk_layout(coords), "Disconnected chunk route network")
	for room in chunk.rooms:
		for direction in range(4):
			var next := room.global_coords + DIRS[direction]
			var id := _edge_id(room.global_coords, next)
			if not edges.has(id):
				continue
			var connection := AbyssRouteConnection.new()
			connection.edge_id = id
			connection.neighbor = next
			connection.kind = edges[id][2]
			connection.side = direction
			# Canonical global endpoint gives the same slot from either side.
			var canonical := room.global_coords if direction == 1 or direction == 2 else next
			connection.slot = _hash(canonical, 401 if direction % 2 == 0 else 409) % 2
			connection.opening_id = _routes.opening_id(direction, connection.slot)
			connection.opening_tile = _routes.opening_position(direction, connection.slot, _config.room_size)
			room.required_connections.append(connection)
			if room.region == AbyssRoomData.Region.PACKED:
				room.required_openings[connection.opening_id] = connection.opening_tile
			if connection.kind == AbyssRouteConnection.Kind.MAIN:
				room.is_main_route = true
	_chunks[coords] = chunk
	return chunk


func get_room(coords: Vector2i) -> AbyssRoomData:
	var chunk_coords := regions.room_to_chunk(coords)
	return get_chunk(chunk_coords).get_room(coords - chunk_coords * _config.chunk_size)


## Callable without scene rendering. Does not recursively generate neighbors.
func validate_chunk_layout(coords: Vector2i) -> bool:
	var data: Dictionary = _diagnostics[coords]
	var rect := Rect2i(coords * _config.chunk_size, _config.chunk_size)
	var occupied := _occupied(data.edges, rect)
	if occupied.is_empty():
		return false
	var queue: Array = [occupied.keys()[0]]
	var visited: Dictionary = {queue[0]: true}
	var index := 0
	while index < queue.size():
		var pos: Vector2i = queue[index]
		index += 1
		for direction in DIRS:
			var next: Vector2i = pos + direction
			if rect.has_point(next) and not visited.has(next) and data.edges.has(_edge_id(pos, next)):
				visited[next] = true
				queue.append(next)
	return visited.size() == occupied.size()


func debug_layout(coords: Vector2i) -> Dictionary:
	get_chunk(coords)
	return _diagnostics[coords]
