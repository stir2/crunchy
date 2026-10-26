@tool
class_name KeyFragmentMarker
extends RoomMarker
## Placement hint only. The progression planner authorizes room/type/ID.
func kind() -> StringName:
	return &"fragment"
func make_request() -> RoomSpawnRequest:
	return AbyssSpecialSpawnRequest.new()
