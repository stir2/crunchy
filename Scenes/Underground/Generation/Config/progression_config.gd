class_name AbyssProgressionConfig
extends Resource
## Three finite horizontal strips, aligned to chunk boundaries. Changing these
## values changes progression IDs/placement and requires a new world namespace.
const LEVEL_COUNT := 3
@export var first_chunk_x: int = -4
@export_range(2, 32) var level_width_chunks: int = 8
@export_range(0.0, 1.0) var checkpoint_probability: float = 0.08
## Minimum Euclidean distance between checkpoint room centers, in rooms.
@export_range(1, 16) var checkpoint_min_spacing_rooms: int = 4
const FRAGMENT_INTERVAL := 50
const EXTRA_FRAGMENT_PROBABILITY := 1.0 / 200.0
const FRAGMENTS_PER_KEY := 3
func level_at_chunk(x: int) -> int:
	var index := floori(float(x - first_chunk_x) / level_width_chunks)
	return index + 1 if index >= 0 and index < LEVEL_COUNT else 0
func room_bounds(level: int, chunk_width: int) -> Vector2i:
	var start := (first_chunk_x + (level - 1) * level_width_chunks) * chunk_width
	return Vector2i(start, start + level_width_chunks * chunk_width)
func same_level(a: int, b: int) -> bool:
	return floori(float(a - first_chunk_x) / level_width_chunks) == floori(float(b - first_chunk_x) / level_width_chunks)

func is_valid() -> bool:
	return checkpoint_min_spacing_rooms >= 1 and level_width_chunks >= 2 and is_finite(checkpoint_probability) and checkpoint_probability >= 0 and checkpoint_probability <= 1
