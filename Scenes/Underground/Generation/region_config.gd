class_name AbyssRegionConfig
extends Resource
## Generation inputs only. Generators snapshot this resource on construction.
@export var global_seed: int = 85763282349
@export var room_size: Vector2i = Vector2i(12, 12)
@export var chunk_size: Vector2i = Vector2i(8, 8)
## Sampled in room coordinates: higher frequency produces smaller cavern blobs.
@export_range(0.001, 0.2, 0.001) var noise_frequency: float = 0.16
## OPEN when raw noise exceeds this threshold. Lower values produce more OPEN.
@export_range(-1.0, 1.0, 0.01) var open_threshold: float = 0.40
## Majority-filter radius in rooms. Large radii erase small caverns.
@export_range(0, 5, 1) var smoothing_radius: int = 1
@export_range(0, 5, 1) var smoothing_iterations: int = 2

func is_valid() -> bool:
	return room_size.x > 0 and room_size.y > 0 and chunk_size.x > 0 and chunk_size.y > 0 and noise_frequency > 0.0 and smoothing_radius >= 0 and smoothing_iterations >= 0
