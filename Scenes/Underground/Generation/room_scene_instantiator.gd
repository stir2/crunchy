class_name AbyssRoomSceneInstantiator
extends RefCounted
## Explicit geometry boundary; selection itself never instantiates anything.
static func instantiate_authored(request: AbyssRoomConstructionRequest) -> AbyssAuthoredRoom:
	if request.method != AbyssRoomConstructionRequest.Method.AUTHORED or request.scene == null:
		return null
	var instance := request.scene.instantiate()
	if not instance is AbyssAuthoredRoom:
		instance.free()
		return null
	var room := instance as AbyssAuthoredRoom
	if room.room_size != request.requirements.room_size or room.tile_pixels != request.requirements.tile_pixels:
		room.free()
		return null
	room.construction_requirements = request.requirements
	room.position = Vector2(request.requirements.global_coords * room.room_size * room.tile_pixels)
	return room
