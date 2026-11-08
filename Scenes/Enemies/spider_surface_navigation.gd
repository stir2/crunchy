extends RefCounted
## A small local graph of exposed terrain faces, sampled from actual collision.
const CELL := 16.0
const CLEARANCE := 13.0
const NORMALS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
var _space: PhysicsDirectSpaceState2D
var _shape := CircleShape2D.new()
var _nodes: Array[Dictionary] = []


func find_path(space: PhysicsDirectSpaceState2D, start: Vector2, target: Vector2) -> Array[Dictionary]:
	_space = space
	_shape.radius = 12.0
	_nodes.clear()
	var lo := Vector2i(floori(minf(start.x, target.x) / CELL) - 4, floori(minf(start.y, target.y) / CELL) - 4)
	var hi := Vector2i(ceili(maxf(start.x, target.x) / CELL) + 4, ceili(maxf(start.y, target.y) / CELL) + 4)
	var solid: Dictionary = {}
	for y in range(lo.y - 1, hi.y + 2):
		for x in range(lo.x - 1, hi.x + 2):
			var cell := Vector2i(x, y)
			var query := PhysicsPointQueryParameters2D.new()
			query.position = (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
			query.collision_mask = 1
			query.collide_with_areas = false
			if not _space.intersect_point(query, 1).is_empty():
				solid[cell] = true
	var buckets: Dictionary = {}
	for cell: Vector2i in solid:
		if cell.x < lo.x or cell.x > hi.x or cell.y < lo.y or cell.y > hi.y:
			continue
		for normal: Vector2 in NORMALS:
			if solid.has(cell + Vector2i(normal)):
				continue
			var point := (Vector2(cell) + Vector2(0.5, 0.5)) * CELL + normal * (CELL * 0.5 + CLEARANCE)
			if not _clear_at(point):
				continue
			var index := _nodes.size()
			_nodes.append({"position": point, "normal": normal, "links": []})
			var bucket := Vector2i(floori(point.x / 40), floori(point.y / 40))
			if not buckets.has(bucket):
				buckets[bucket] = []
			buckets[bucket].append(index)
	for i in range(_nodes.size()):
		var p: Vector2 = _nodes[i].position
		var bucket := Vector2i(floori(p.x / 40), floori(p.y / 40))
		for y in range(-1, 2):
			for x in range(-1, 2):
				for j: int in buckets.get(bucket + Vector2i(x, y), []):
					if j <= i:
						continue
					var q: Vector2 = _nodes[j].position
					if p.distance_squared_to(q) > 40.0 * 40.0:
						continue
					var a: Vector2 = _nodes[i].normal
					var b: Vector2 = _nodes[j].normal
					if a.dot(b) < -0.5:
						continue
					if a == b and (absf((q - p).dot(a)) > 0.1 or p.distance_to(q) > CELL + 0.1):
						continue
					var corner := q
					if a != b:
						corner = Vector2(q.x, p.y) if absf(a.y) > 0.5 else Vector2(p.x, q.y)
					if not _segment_clear(p, corner) or not _segment_clear(corner, q):
						continue
					var cost := p.distance_to(corner) + corner.distance_to(q)
					_nodes[i].links.append({"to": j, "corner": corner, "cost": cost})
					_nodes[j].links.append({"to": i, "corner": corner, "cost": cost})
	var first := -1
	var closest := 40.0 * 40.0
	for i in range(_nodes.size()):
		var distance := start.distance_squared_to(_nodes[i].position)
		if distance < closest and _segment_clear(start, _nodes[i].position):
			closest = distance
			first = i
	if first < 0:
		return []
	var distances: Dictionary = {first: 0.0}
	var previous: Dictionary = {}
	var open: Array[int] = [first]
	while not open.is_empty():
		var current: int = open[0]
		for candidate in open:
			if distances[candidate] < distances[current]:
				current = candidate
		open.erase(current)
		for link: Dictionary in _nodes[current].links:
			var cost: float = distances[current] + link.cost
			if not distances.has(link.to) or cost < distances[link.to]:
				distances[link.to] = cost
				previous[link.to] = {"from": current, "corner": link.corner}
				if not open.has(link.to):
					open.append(link.to)
	var last := first
	var best := INF
	for index: int in distances:
		var score: float = Vector2(_nodes[index].position).distance_to(target) + distances[index] * 0.025
		if score < best:
			best = score
			last = index
	var chain: Array[int] = [last]
	while previous.has(chain[0]):
		chain.push_front(previous[chain[0]].from)
	var result: Array[Dictionary] = [{"position": _nodes[first].position, "normal": _nodes[first].normal}]
	for i in range(1, chain.size()):
		var before: Dictionary = _nodes[chain[i - 1]]
		var node: Dictionary = _nodes[chain[i]]
		var corner: Vector2 = previous[chain[i]].corner
		if corner.distance_to(before.position) > 1 and corner.distance_to(node.position) > 1:
			result.append({"position": corner, "normal": before.normal})
		result.append({"position": node.position, "normal": node.normal})
	return result


func _clear_at(point: Vector2) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.transform = Transform2D(0, point)
	query.collision_mask = 1
	return _space.intersect_shape(query, 1).is_empty()


func _segment_clear(a: Vector2, b: Vector2) -> bool:
	if a.distance_squared_to(b) < 0.01:
		return true
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.transform = Transform2D(0, a)
	query.collision_mask = 1
	query.motion = b - a
	var fractions := _space.cast_motion(query)
	return fractions[0] >= 0.999
