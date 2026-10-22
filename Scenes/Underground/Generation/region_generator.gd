class_name AbyssRegionGenerator
extends RefCounted
## No RNG state, scene dependencies, streaming, or mutable gameplay state.
var _config: AbyssRegionConfig
var _noise: FastNoiseLite
var _chunks: Dictionary[Vector2i, AbyssChunkData] = {}
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


func _init(settings: AbyssRegionConfig) -> void:
	assert(settings != null and settings.is_valid(), "Invalid abyss generation configuration")
	_config = settings.duplicate() as AbyssRegionConfig
	_noise = FastNoiseLite.new()
	_noise.seed = _config.global_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	_noise.frequency = _config.noise_frequency


func room_to_chunk(coords: Vector2i) -> Vector2i:
	return Vector2i(floori(float(coords.x) / _config.chunk_size.x), floori(float(coords.y) / _config.chunk_size.y))


func get_chunk(coords: Vector2i) -> AbyssChunkData:
	if _chunks.has(coords):
		return _chunks[coords]
	var chunk := AbyssChunkData.new()
	chunk.coords = coords
	chunk.config = _config
	var origin := coords * _config.chunk_size
	# One extra final cell for boundary metadata, plus the complete dependency
	# halo of every smoothing iteration. Never clamp at chunk edges.
	var final_rect := Rect2i(origin - Vector2i.ONE, _config.chunk_size + Vector2i(2, 2))
	var rect := final_rect.grow(_config.smoothing_radius * _config.smoothing_iterations)
	var classifications: Dictionary[Vector2i, bool] = {}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var pos := Vector2i(x, y)
			classifications[pos] = _noise.get_noise_2d(x, y) > _config.open_threshold
	for iteration in range(_config.smoothing_iterations):
		var next: Dictionary[Vector2i, bool] = {}
		rect = rect.grow(-_config.smoothing_radius)
		var radius := _config.smoothing_radius
		var count := (radius * 2 + 1) * (radius * 2 + 1)
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var open_count := 0
				for dy in range(-radius, radius + 1):
					for dx in range(-radius, radius + 1):
						if classifications[Vector2i(x + dx, y + dy)]:
							open_count += 1
				next[Vector2i(x, y)] = open_count * 2 > count
		classifications = next
	for y in range(_config.chunk_size.y):
		for x in range(_config.chunk_size.x):
			var room := AbyssRoomData.new()
			room.global_coords = origin + Vector2i(x, y)
			room.chunk_coords = coords
			room.raw_openness = _noise.get_noise_2d(room.global_coords.x, room.global_coords.y)
			var is_open: bool = classifications[room.global_coords]
			room.region = AbyssRoomData.Region.OPEN if is_open else AbyssRoomData.Region.PACKED
			for direction in range(DIRECTIONS.size()):
				if classifications[room.global_coords + DIRECTIONS[direction]] != is_open:
					room.boundary_mask |= 1 << direction
			chunk.rooms.append(room)
	_chunks[coords] = chunk
	return chunk


func get_room(coords: Vector2i) -> AbyssRoomData:
	var chunk_coords := room_to_chunk(coords)
	return get_chunk(chunk_coords).get_room(coords - chunk_coords * _config.chunk_size)
