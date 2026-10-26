@tool
class_name LevelGateMarker
extends RoomMarker
## Placement hint only. The progression planner authorizes room/type/ID.
func kind() -> StringName:
	return &"gate"
func make_request() -> RoomSpawnRequest:
	return AbyssSpecialSpawnRequest.new()
