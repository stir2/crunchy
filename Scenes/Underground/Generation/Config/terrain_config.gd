class_name AbyssTerrainConfig
extends Resource
## Boundary apertures remain the exact single-tile slots of abyss_slots_v1.
@export_range(2, 5) var tunnel_width: int = 3
@export_range(0, 3) var shape_variation: int = 2
@export_range(0.0, 1.0) var internal_openness: float = 0.35
@export_range(0.0, 1.0) var platform_probability: float = 0.65
@export_range(0, 4) var max_platforms: int = 3
## Legacy local-only fallback when build() has no world boundary sampler.
## The preview uses Transition Blend Width instead.
@export_range(1, 4) var transition_depth: int = 3

@export_group("Cavern Boundaries")
## Broad signed boundary displacement, in tiles. Independent of room size.
@export_range(0.0, 24.0, 0.5) var boundary_warp_amplitude: float = 8.0
@export_range(0.005, 0.2, 0.005) var boundary_warp_frequency: float = 0.035
## Erosion/blending band; also sets broad corner-rounding radius.
## Half this width biases the boundary into packed rock.
@export_range(0.0, 24.0, 0.5) var transition_blend_width: float = 6.5
@export_range(0.0, 6.0, 0.25) var boundary_detail_strength: float = 1.5
## One global 3x3 majority pass, including samples outside room/chunk bounds.
@export var boundary_smoothing: bool = true
