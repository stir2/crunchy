@tool
class_name DecorationMarker
extends RoomMarker
@export var decoration_pool: Resource
@export var variation_range: Vector2i = Vector2i(0,3)
func kind() -> StringName:
	return &"decoration"
func make_request() -> RoomSpawnRequest:
	var request := DecorationSpawnRequest.new()
	request.decoration_pool = decoration_pool
	request.variation_range = variation_range
	return request
