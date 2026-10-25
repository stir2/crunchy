@tool
class_name AbyssAuthoredRoom
extends Node2D
## Geometry container only. Metadata and mutable gameplay state live elsewhere.
@export var room_size: Vector2i = AbyssRegionConfig.DEFAULT_ROOM_SIZE
@export var tile_pixels: int = 16
@export var show_editor_guides: bool = true:
	set(value):
		show_editor_guides = value
		queue_redraw()
## Optional tile-space rectangles reserved for navigation. Editor guides are cyan.
@export var reserved_route_rects: Array[Rect2i] = []:
	set(value):
		reserved_route_rects = value
		queue_redraw()
signal breakable_damaged(group_id: String, remaining_health: float, world_position: Vector2)
signal breakable_destroyed(group_id: String, cells: Array, world_position: Vector2)
signal terrain_changed
## Required platform supports must be permanent, never conditional.
@export var required_support_rects: Array[Rect2i] = []
## Canonical coordinate -> explicit persistence ID for breakable groups.
@export var breakable_group_ids: Dictionary[Vector2i, String] = {}
var tile_groups: Dictionary = {}
var protected_route_cells: Dictionary = {}
var conditional_platform_groups: Array[Dictionary] = []
var climbable_cells: Array[Vector2i] = []
var climbable_regions: Array[Dictionary] = []
var spawn_requests: Array[RoomSpawnRequest] = []
var content_warnings: PackedStringArray = []
var persistent_state: AbyssRoomState
var breakables: AbyssBreakableTerrain
var conditional_wall_groups: Array[Dictionary] = []
var construction_requirements: AbyssRoomRequirements


func _draw() -> void:
	if Engine.is_editor_hint() and show_editor_guides:
		draw_rect(Rect2(Vector2.ZERO, Vector2(room_size * tile_pixels)), Color(0.9, 0.75, 0.25, 0.8), false, 1.0)

		for rect in reserved_route_rects:
			draw_rect(Rect2(Vector2(rect.position * tile_pixels), Vector2(rect.size * tile_pixels)), Color(0.2, 0.9, 1.0, 0.7), false, 1.0)


func damage_breakable_at(world_position: Vector2, amount: float) -> bool:
	return breakables != null and breakables.damage_at(world_position, amount)

func climbable_layers() -> Array[TileMapLayer]:
	var result: Array[TileMapLayer] = []
	var layer := get_node_or_null("Climbables") as TileMapLayer
	if layer != null:
		result.append(layer)
	return result


func destroy_breakable_group(identity: String) -> bool:
	return breakables != null and breakables.destroy_group(identity)
