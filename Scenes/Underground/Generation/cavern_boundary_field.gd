class_name AbyssCavernBoundaryField
extends RefCounted
## Finite-lifetime world sampler. No scene order or shared RNG participates.
var _generator: AbyssRouteGenerator
var _selector: AbyssRoomTemplateSelector
var _config: AbyssTerrainConfig
var _size: Vector2i
var _broad := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _requests: Dictionary = {}
var _authored: Dictionary = {}
var _raw: Dictionary = {}
var _distance: Dictionary = {}
var _open: Dictionary = {}
var _opposite_rects: Dictionary = {}
var _final: Dictionary = {}

func _init(generator: AbyssRouteGenerator, selector: AbyssRoomTemplateSelector, config: AbyssTerrainConfig) -> void:
	_generator = generator
	_selector = selector
	_config = config.duplicate() as AbyssTerrainConfig
	var chunk := generator.get_chunk(Vector2i.ZERO)
	_size = chunk.config.room_size
	_broad.seed = int(chunk.config.global_seed ^ 0x43ab17)
	_broad.frequency = config.boundary_warp_frequency
	_broad.fractal_type = FastNoiseLite.FRACTAL_NONE
	_detail.seed = int(chunk.config.global_seed ^ 0x731c91)
	_detail.frequency = config.boundary_warp_frequency * 4.0
	_detail.fractal_type = FastNoiseLite.FRACTAL_NONE

func request(coords: Vector2i) -> AbyssRoomConstructionRequest:
	if not _requests.has(coords):
		_requests[coords] = _selector.select_room(_generator, coords)
	return _requests[coords]

func room_coords(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / _size.x), floori(float(tile.y) / _size.y))

func _is_open(coords: Vector2i) -> bool:
	if not _open.has(coords):
		_open[coords] = _generator.get_room(coords).region == AbyssRoomData.Region.OPEN
	return _open[coords]

func _authored_solid(coords: Vector2i, local: Vector2i) -> bool:
	if not _authored.has(coords):
		var room := AbyssRoomSceneInstantiator.instantiate_authored(request(coords))
		var cells: Dictionary = {}
		for key in ["Solid", "ConditionalWalls", "BreakableWalls"]:
			var layer := room.get_node_or_null(NodePath(key)) as TileMapLayer
			if layer != null:
				for cell in layer.get_used_cells():
					cells[cell] = true
		_authored[coords] = cells
		room.free()
	return _authored[coords].has(local)

func is_solid(tile: Vector2i) -> bool:
	if _final.has(tile):
		return _final[tile]
	var coords := room_coords(tile)
	var local := tile - coords * _size
	if request(coords).method == AbyssRoomConstructionRequest.Method.AUTHORED:
		return _authored_solid(coords, local)
	var result := _raw_solid(tile)
	if _config.boundary_smoothing:
		var count := 0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				count += int(_raw_solid(tile + Vector2i(dx, dy)))
		result = count >= 5
	# Pin only the interface cell to authored geometry. The interior blends
	# continuously in _raw_solid instead of copying a flat two-tile strip.
	for side in range(4):
		var distance: int = [local.y, _size.x - 1 - local.x, _size.y - 1 - local.y, local.x][side]
		if distance != 0:
			continue
		var neighbor: Vector2i = coords + AbyssRegionGenerator.DIRECTIONS[side]
		if request(neighbor).method == AbyssRoomConstructionRequest.Method.AUTHORED:
			var opposite := local
			if side % 2 == 0:
				opposite.y = _size.y - 1 if side == 0 else 0
			else:
				opposite.x = 0 if side == 1 else _size.x - 1
			result = _authored_solid(neighbor, opposite)
	# Interface contracts supersede the field. Both endpoints apply the same rule.
	for side in range(4):
		var on_edge: bool = [local.y == 0, local.x == _size.x - 1, local.y == _size.y - 1, local.x == 0][side]
		if not on_edge:
			continue
		var neighbor := coords + AbyssRegionGenerator.DIRECTIONS[side]
		if _is_open(coords) and _is_open(neighbor):
			result = false
		elif not _is_open(coords) and not _is_open(neighbor):
			result = not request(coords).requirements.required_openings.values().has(local)
	_final[tile] = result
	return result

func _raw_solid(tile: Vector2i) -> bool:
	if _raw.has(tile):
		return _raw[tile]
	var coords := room_coords(tile)
	var local := tile - coords * _size
	if request(coords).method == AbyssRoomConstructionRequest.Method.AUTHORED:
		var authored := _authored_solid(coords, local)
		_raw[tile] = authored
		return authored
	# Smooth the signed field, not just the final binary silhouette. A global
	# Gaussian stencil rounds mask corners at the scale of the transition band.
	var radius := maxi(1, roundi(_config.transition_blend_width * 0.5))
	var signed_distance := 0.0
	for y in range(-1, 2):
		for x in range(-1, 2):
			var weight := (2.0 if x == 0 else 1.0) * (2.0 if y == 0 else 1.0)
			signed_distance += _signed_distance(tile + Vector2i(x, y) * radius) * weight / 16.0
	var point := Vector2(tile) + Vector2(0.5, 0.5)
	var displacement := _config.transition_blend_width * 0.5 + _broad.get_noise_2dv(point) * _config.boundary_warp_amplitude + _detail.get_noise_2dv(point) * _config.boundary_detail_strength
	var score := signed_distance - displacement
	var seal_support := _seal_support_score(tile, coords)
	# Blend towards the neighboring edited boundary with a smooth falloff.
	# This adapts our side only; the authored instance is never rewritten.
	var width := maxf(2.0, _config.transition_blend_width)
	var weighted_score := score
	var total_weight := 1.0
	for side in range(4):
		var distance: int = [local.y, _size.x - 1 - local.x, _size.y - 1 - local.y, local.x][side]
		if distance >= width:
			continue
		var neighbor := coords + AbyssRegionGenerator.DIRECTIONS[side]
		if request(neighbor).method != AbyssRoomConstructionRequest.Method.AUTHORED:
			continue
		var opposite := local
		if side % 2 == 0:
			opposite.y = _size.y - 1 if side == 0 else 0
		else:
			opposite.x = 0 if side == 1 else _size.x - 1
		var influence := 1.0 - smoothstep(0.0, width, distance + 0.5)
		var target := width * 0.5 if _authored_solid(neighbor, opposite) else -width * 0.5
		# Odds weighting approaches an exact edge constraint without a step.
		var weight := influence / maxf(0.01, 1.0 - influence)
		weighted_score += target * weight
		total_weight += weight
	# Keep the rounded support after authored blending as well: otherwise an
	# empty authored OPEN face can shave its root back into the same thin fin.
	var result := maxf(weighted_score / total_weight, seal_support) > 0.0
	_raw[tile] = result
	return result

func _seal_support_score(tile: Vector2i, coords: Vector2i) -> float:
	# Two adjacent forced edge rows otherwise survive erosion as a two-tile
	# fin. Give the mandatory seal a continuous rounded cross-section before
	# binary cleanup, rather than adding an infinitely thin wall afterward.
	if _is_open(coords):
		return -INF
	var radius := clampf(_config.transition_blend_width * 0.5, 2.0, minf(_size.x, _size.y) / 3.0)
	var point := Vector2(tile) + Vector2(0.5, 0.5)
	var origin := Vector2(coords * _size)
	var score := -INF
	for side in range(4):
		var neighbor := coords + AbyssRegionGenerator.DIRECTIONS[side]
		if _is_open(neighbor):
			continue
		var horizontal := side % 2 == 0
		var tangent := Vector2i.RIGHT if horizontal else Vector2i.DOWN
		var start := origin
		if side == 1:
			start.x += _size.x
		elif side == 2:
			start.y += _size.y
		var length := float(_size.x if horizontal else _size.y)
		var end := start + Vector2(tangent) * length
		# Round only exposed ends; uninterrupted packed seams extend through
		# corners. Each endpoint pair computes the identical global capsule.
		if _is_open(coords - tangent) or _is_open(neighbor - tangent):
			start += Vector2(tangent) * radius
		else:
			start -= Vector2(tangent) * radius
		if _is_open(coords + tangent) or _is_open(neighbor + tangent):
			end -= Vector2(tangent) * radius
		else:
			end += Vector2(tangent) * radius
		var delta := point - point.clamp(start, end)
		score = maxf(score, radius - delta.length())
	return score

func _signed_distance(tile: Vector2i) -> float:
	if _distance.has(tile):
		return _distance[tile]
	var coords := room_coords(tile)
	var open := _is_open(coords)
	# Includes broad-field smoothing and fine cleanup beyond every room edge.
	var reach := _config.transition_blend_width * 1.5 + _config.boundary_warp_amplitude + _config.boundary_detail_strength + 2.0
	var halo := Vector2i(ceili(reach / _size.x) + 1, ceili(reach / _size.y) + 1)
	var point := Vector2(tile) + Vector2(0.5, 0.5)
	var nearest := reach
	if not _opposite_rects.has(coords):
		var rectangles: Array[Rect2] = []
		for y in range(coords.y - halo.y, coords.y + halo.y + 1):
			for x in range(coords.x - halo.x, coords.x + halo.x + 1):
				var other := Vector2i(x, y)
				if _is_open(other) != open:
					rectangles.append(Rect2(Vector2(other * _size), Vector2(_size)))
		_opposite_rects[coords] = rectangles
	for rect: Rect2 in _opposite_rects[coords]:
		var delta := point - point.clamp(rect.position, rect.end)
		nearest = minf(nearest, delta.length())
	var result := -nearest if open else nearest
	_distance[tile] = result
	return result
