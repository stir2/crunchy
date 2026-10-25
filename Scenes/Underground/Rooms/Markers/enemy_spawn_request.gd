class_name EnemySpawnRequest
extends RoomSpawnRequest
var enemy_type: StringName = &"placeholder"
var enemy_pool: Resource
var difficulty_range: Vector2 = Vector2(0,100)
var depth_range: Vector2i = Vector2i(0,1000000)
var encounter_group: StringName
