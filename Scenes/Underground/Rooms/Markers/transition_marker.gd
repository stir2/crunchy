@tool
class_name TransitionMarker
extends RoomMarker
@export var destination: StringName
@export var logical_gate_id: StringName
func kind() -> StringName:
	return &"transition"
func make_request() -> RoomSpawnRequest:
	var request := TransitionSpawnRequest.new()
	request.destination = destination
	request.logical_gate_id = logical_gate_id
	return request
