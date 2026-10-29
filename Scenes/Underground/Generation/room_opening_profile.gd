@tool
class_name AbyssRoomOpeningProfile
extends Resource
## One fixed, realizable opening combination. Different geometry needs a different scene.
@export var variant_id: StringName = &"default"
## Optional scene override for this combination; otherwise use metadata.scene.
@export var scene: PackedScene
@export_storage var openings: Array[StringName] = []
## Exact local tile indices, keyed by the existing side:slot IDs.
@export_storage var opening_tiles: Dictionary[StringName, Vector2i] = {}
## Full open faces (N/E/S/W = 1/2/4/8). PACKED corners remain capped.
@export_flags("North", "East", "South", "West") var open_sides: int = 0


const OPENING_IDS: Array[StringName] = [
	&"north:0", &"north:1", &"east:0", &"east:1",
	&"south:0", &"south:1", &"west:0", &"west:1",
]


static func checkbox_properties() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	for id in OPENING_IDS:
		properties.append({"name": "Connections/" + String(id), "type": TYPE_BOOL,
			"usage": PROPERTY_USAGE_EDITOR})
	return properties


func _get_property_list() -> Array[Dictionary]:
	return checkbox_properties()


func _get(property: StringName) -> Variant:
	if String(property).begins_with("Connections/"):
		return openings.has(StringName(String(property).trim_prefix("Connections/")))
	return null


func _set(property: StringName, value: Variant) -> bool:
	if not String(property).begins_with("Connections/"):
		return false
	set_connection(StringName(String(property).trim_prefix("Connections/")), bool(value), AbyssRegionConfig.DEFAULT_ROOM_SIZE)
	return true


func set_connection(id: StringName, enabled: bool, size: Vector2i) -> void:
	var index := OPENING_IDS.find(id)
	if index < 0:
		return
	if enabled:
		if not openings.has(id):
			openings.append(id)
		# Read the central route defaults; designers never enter tile coordinates.
		var config := AbyssRouteConfig.new()
		var side: int = index >> 1
		var slot := index % 2
		var offset: int = config.horizontal_offsets[slot] if side % 2 == 0 else config.vertical_offsets[slot]
		match side:
			0: opening_tiles[id] = Vector2i(offset, 0)
			1: opening_tiles[id] = Vector2i(size.x - 1, offset)
			2: opening_tiles[id] = Vector2i(offset, size.y - 1)
			3: opening_tiles[id] = Vector2i(0, offset)
	else:
		openings.erase(id)
		opening_tiles.erase(id)
	emit_changed()
