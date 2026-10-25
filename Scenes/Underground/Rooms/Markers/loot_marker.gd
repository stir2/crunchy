@tool
class_name LootSpawnMarker
extends RoomMarker
@export var loot_type: StringName = &"placeholder"
@export var loot_table: Resource
@export var quantity_range: Vector2i = Vector2i(1,1)
@export var rarity: StringName = &"common"
@export var collection_id: StringName
func kind() -> StringName:
	return &"loot"
func make_request() -> RoomSpawnRequest:
	var request := LootSpawnRequest.new()
	request.loot_type = loot_type
	request.loot_table = loot_table
	request.quantity_range = quantity_range
	request.rarity = rarity
	request.collection_id = collection_id
	return request
func persistence_id() -> String:
	return String(collection_id if collection_id != &"" else marker_id)
