@tool
class_name HazardSpawnMarker
extends RoomMarker
@export var hazard_type: StringName = &"placeholder"
@export var hazard_scene: PackedScene
@export var orientation_degrees: float = 0.0
@export var avoidance_radius_tiles: int = 1
func kind() -> StringName:
	return &"hazard"
func make_request() -> RoomSpawnRequest:
	var request := HazardSpawnRequest.new()
	request.hazard_type = hazard_type
	request.hazard_scene = hazard_scene
	request.orientation_degrees = orientation_degrees
	request.avoidance_radius_tiles = avoidance_radius_tiles
	return request
