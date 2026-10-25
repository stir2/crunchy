@tool
class_name EnemySpawnMarker
extends RoomMarker
@export var enemy_type: StringName = &"placeholder"
@export var enemy_pool: Resource
@export var difficulty_range: Vector2 = Vector2(0,100)
@export var depth_range: Vector2i = Vector2i(0,1000000)
@export var encounter_group: StringName
func kind() -> StringName:
	return &"enemy"
func make_request() -> RoomSpawnRequest:
	var request := EnemySpawnRequest.new()
	request.enemy_type = enemy_type
	request.enemy_pool = enemy_pool
	request.difficulty_range = difficulty_range
	request.depth_range = depth_range
	request.encounter_group = encounter_group
	return request
