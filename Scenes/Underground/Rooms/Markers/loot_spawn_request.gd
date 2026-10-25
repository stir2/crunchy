class_name LootSpawnRequest
extends RoomSpawnRequest
var loot_type: StringName = &"placeholder"
var loot_table: Resource
var quantity_range: Vector2i = Vector2i(1,1)
var rarity: StringName = &"common"
var collection_id: StringName
var quantity: int = 1
