class_name AbyssChunkData
extends RefCounted
var route_config: AbyssRouteConfig
var coords: Vector2i
## Snapshot shared with the generator. Treat generated data/config as read-only.
var config: AbyssRegionConfig
## Row-major, local x + local y * chunk_size.x.
var rooms: Array[AbyssRoomData] = []


func get_room(local_coords: Vector2i) -> AbyssRoomData:
	if local_coords.x < 0 or local_coords.y < 0 or local_coords.x >= config.chunk_size.x or local_coords.y >= config.chunk_size.y:
		return null
	return rooms[local_coords.x + local_coords.y * config.chunk_size.x]
