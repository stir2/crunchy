class_name AbyssRoomRequirements
extends RefCounted
## Immutable-by-convention layout snapshot shared by both construction methods.
var room_id: String
var global_coords: Vector2i
var room_size: Vector2i
var tile_pixels: int = 16
var region: AbyssRoomData.Region
var transition: bool
var main_route: bool
var logical_neighbors: Array[Vector2i] = []
var boundary_mask: int
var opening_schema: StringName
var route_openings: Dictionary[StringName, Vector2i] = {}
var required_openings: Dictionary[StringName, Vector2i] = {}
var neighbor_open_sides: int = 0
var known_neighbor_sides: int = 0
var horizontal_offsets: Vector2i
var vertical_offsets: Vector2i


static func from_room(room: AbyssRoomData, config: AbyssRegionConfig, routes: AbyssRouteConfig, neighbors: Array[AbyssRoomData], world_tile_pixels: int = 16) -> AbyssRoomRequirements:
	var result := AbyssRoomRequirements.new()
	result.room_id = room.room_id
	result.global_coords = room.global_coords
	result.room_size = config.room_size
	result.tile_pixels = world_tile_pixels
	result.region = room.region
	result.transition = room.is_transition()
	result.main_route = room.is_main_route
	result.logical_neighbors = room.logical_neighbors()
	result.boundary_mask = room.boundary_mask
	result.opening_schema = routes.opening_schema
	result.horizontal_offsets = routes.horizontal_offsets
	result.vertical_offsets = routes.vertical_offsets
	result.required_openings = room.required_openings.duplicate()
	for edge in room.required_connections:
		result.route_openings[edge.opening_id] = edge.opening_tile
	for neighbor in neighbors:
		var side := AbyssRegionGenerator.DIRECTIONS.find(neighbor.global_coords - room.global_coords)
		if side >= 0:
			result.known_neighbor_sides |= 1 << side
			if neighbor.region == AbyssRoomData.Region.OPEN:
				result.neighbor_open_sides |= 1 << side
	return result


func opening_tile(id: StringName) -> Vector2i:
	var parts := String(id).split(":")
	if parts.size() != 2 or not parts[1] in ["0", "1"]:
		return Vector2i(-1, -1)
	var side := ["north", "east", "south", "west"].find(parts[0])
	if side < 0:
		return Vector2i(-1, -1)
	var slot := int(parts[1])
	match side:
		0: return Vector2i(horizontal_offsets[slot], 0)
		1: return Vector2i(room_size.x - 1, vertical_offsets[slot])
		2: return Vector2i(horizontal_offsets[slot], room_size.y - 1)
		_: return Vector2i(0, vertical_offsets[slot])
