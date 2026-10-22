class_name AbyssRouteConfig
extends Resource
## Coordinate-derived contracts and bounded winding graph growth; no geometry.
@export var opening_schema: StringName = &"abyss_slots_v1"
@export var entrance_chunk_x: int = 0
## In chunk columns/rows. Zero wander reproduces a single-column descent.
@export_range(0.0, 32.0, 0.25) var main_route_horizontal_wander: float = 4.0
@export_range(1, 64) var main_route_wander_scale: int = 8
## Hard symmetric main-route envelope around the entrance (not level boundaries).
@export_range(0, 32) var main_route_max_horizontal_drift: int = 6
@export_range(0.0, 1.0) var branching_probability: float = 0.45
@export_range(0.0, 1.0) var reconnection_probability: float = 0.09
@export_range(1, 32) var branch_min_length: int = 3
@export_range(1, 32) var branch_max_length: int = 10
## Legacy API: branch_length remains an alias for the maximum growth budget.
@export_storage var branch_length: int:
	get: return branch_max_length
	set(value):
		branch_max_length = value
		branch_min_length = mini(branch_min_length, value)
@export_range(0.0, 1.0) var downward_preference: float = 0.95
@export_range(0.0, 1.0) var directional_persistence: float = 0.25
@export_range(0.1, 3.0) var turning_weight: float = 1.0
@export_range(1, 12) var max_straight_run: int = 3
@export_range(1.0, 3.0) var main_path_stretch: float = 1.5
@export_range(0.05, 0.8) var room_density: float = 0.50
@export_range(0.0, 1.0) var secondary_branch_probability: float = 0.35
@export_range(0.0, 1.0) var inter_chunk_loop_probability: float = 0.08
## Side chunks may attach vertically within these bands instead of forming rows.
@export_range(2, 12) var attachment_band_height: int = 4
## Tile indices along N/S edges and E/W edges respectively. Slot IDs stay stable.
@export var horizontal_offsets: Vector2i = Vector2i(3, 8)
@export var vertical_offsets: Vector2i = Vector2i(3, 8)


func is_valid(room_size: Vector2i) -> bool:
	return (
		main_route_horizontal_wander >= 0 and main_route_wander_scale >= 1
		and main_route_max_horizontal_drift >= 0
		and branch_min_length > 0 and branch_max_length >= branch_min_length
		and max_straight_run > 0 and main_path_stretch >= 1
		and downward_preference >= 0 and downward_preference <= 1
		and directional_persistence >= 0 and directional_persistence <= 1
		and turning_weight > 0 and room_density > 0 and room_density <= 1
		and secondary_branch_probability >= 0 and secondary_branch_probability <= 1
		and inter_chunk_loop_probability >= 0 and inter_chunk_loop_probability <= 1
		and attachment_band_height >= 2
		and branching_probability >= 0 and branching_probability <= 1
		and reconnection_probability >= 0 and reconnection_probability <= 1
		and horizontal_offsets.x >= 0 and horizontal_offsets.x < horizontal_offsets.y
		and horizontal_offsets.y < room_size.x
		and vertical_offsets.x >= 0 and vertical_offsets.x < vertical_offsets.y
		and vertical_offsets.y < room_size.y
	)


## Local tile index; matching rooms have identical tangential coordinates.
func opening_position(side: int, slot: int, size: Vector2i) -> Vector2i:
	var h := horizontal_offsets[slot]
	var v := vertical_offsets[slot]
	match side:
		0: return Vector2i(h, 0)
		1: return Vector2i(size.x - 1, v)
		2: return Vector2i(h, size.y - 1)
		_: return Vector2i(0, v)


static func opening_id(side: int, slot: int) -> StringName:
	return StringName(["north", "east", "south", "west"][side] + ":" + str(slot))
