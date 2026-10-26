class_name AbyssRoomData
extends RefCounted
## Generated layout only; future mutable gameplay state belongs elsewhere.
enum Region { OPEN, PACKED }
enum Boundary { NORTH = 1, EAST = 2, SOUTH = 4, WEST = 8 }
## Zero denotes legacy/unbounded generation.
var level_number: int = 0
var global_coords: Vector2i
var chunk_coords: Vector2i
var raw_openness: float
var region: Region = Region.PACKED
## Cardinal neighbors whose final classification differs from this room.
var boundary_mask: int = 0
var room_id: String:
	get: return "%d:%d" % [global_coords.x, global_coords.y]
var is_main_route: bool = false
var required_connections: Array[AbyssRouteConnection] = []
## Only PACKED endpoints require explicit openings. IDs are side:slot.
var required_openings: Dictionary[StringName, Vector2i] = {}


func logical_neighbors() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for connection in required_connections:
		result.append(connection.neighbor)
	return result


## The required graph is a lower bound on connectivity, not a wall specification.
func allows_open_adjacency(other: AbyssRoomData) -> bool:
	var delta := other.global_coords - global_coords
	return level_number == other.level_number and region == Region.OPEN and other.region == Region.OPEN and absi(delta.x) + absi(delta.y) == 1


func is_transition() -> bool:
	return boundary_mask != 0
