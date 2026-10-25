class_name RoomSpawnRequest
extends RefCounted
var marker_id: StringName
var kind: StringName
var room_coords: Vector2i
var local_position: Vector2
var tags: Array[StringName] = []
var configuration: Resource
var roll: float
var selected := false
var eligible := true
var protected_route := false
var reason := ""
var state_key: String
var persistent := true
var _state: AbyssRoomState
var _room: WeakRef
var _initial_world_position: Vector2
var world_position: Vector2:
	get:
		var room := _room.get_ref() as Node2D if _room != null else null
		return room.to_global(local_position) if room != null else _initial_world_position
func should_spawn() -> bool:
	return selected and eligible and (not persistent or not _state.markers.has(state_key))
func record_status(status: String = "consumed") -> void:
	if persistent:
		_state.markers[state_key] = status
func status() -> String:
	return _state.markers.get(state_key, "") if persistent else "respawn"
