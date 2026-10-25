@tool
class_name InteractionMarker
extends RoomMarker
@export var interaction_type: StringName = &"switch"
@export var interaction_scene: PackedScene
func kind() -> StringName:
	return &"interaction"
func make_request() -> RoomSpawnRequest:
	var request := InteractionSpawnRequest.new()
	request.interaction_type = interaction_type
	request.interaction_scene = interaction_scene
	return request
