class_name AbyssTerrainConfig
extends Resource
## Boundary apertures remain the exact single-tile slots of abyss_slots_v1.
@export_range(2, 5) var tunnel_width: int = 3
@export_range(0, 3) var shape_variation: int = 2
@export_range(0.0, 1.0) var internal_openness: float = 0.35
@export_range(0.0, 1.0) var platform_probability: float = 0.65
@export_range(0, 4) var max_platforms: int = 3
@export_range(1, 4) var transition_depth: int = 3
