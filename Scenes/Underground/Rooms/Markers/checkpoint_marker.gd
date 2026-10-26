@tool
class_name CheckpointMarker
extends RoomMarker
## Placement hint only. The progression planner authorizes room/type/ID.
func kind() -> StringName:
	return &"checkpoint"
func make_request() -> RoomSpawnRequest:
	return AbyssSpecialSpawnRequest.new()
