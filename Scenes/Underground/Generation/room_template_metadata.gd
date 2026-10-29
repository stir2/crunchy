@tool
class_name AbyssRoomTemplateMetadata
extends Resource
## Authored construction definitions; never stored on logical rooms.
enum Compatibility { OPEN, PACKED, TRANSITION }
@export var template_id: StringName
@export var display_name: String = ""
@export var scene: PackedScene
@export var region: Compatibility = Compatibility.PACKED
## TRANSITION preserves the original OPEN/PACKED type; it is not a third noise type.
@export var transition_base_region: AbyssRoomData.Region = AbyssRoomData.Region.PACKED
@export var tile_pixels: int = 16
@export var room_size: Vector2i = AbyssRegionConfig.DEFAULT_ROOM_SIZE
## Version the physical opening convention independently of template IDs.
@export var opening_schema: StringName = &"abyss_slots_v1"
## Legacy union of supported side:slot IDs. Profiles are the authoritative
## combinations; this union alone never implies that arbitrary subsets are safe.
@export_storage var supported_openings: Array[StringName] = []
## Advanced: additional fixed combinations with optional scene overrides.
@export var opening_combinations: Array[AbyssRoomOpeningProfile] = [AbyssRoomOpeningProfile.new()]
@export_range(0.0, 1000.0, 0.1) var selection_weight: float = 1.0
@export var compatibility_tags: Array[StringName] = []

@export_group("Conditional Walls")
## Independent inclusion probability for each painted four-connected group.
@export_range(0.0, 1.0, 0.01) var conditional_wall_probability: float = 0.5
@export var debug_conditional_walls: bool = false

@export_group("Room Features")
@export_range(0.0,1.0,0.01) var conditional_platform_probability: float = 0.5
@export_range(0.1,1000.0,0.1) var breakable_health: float = 3.0


# The common single-scene workflow edits the first profile directly here.
# Additional profiles remain available for separately authored scene variants.
func _get_property_list() -> Array[Dictionary]:
	return AbyssRoomOpeningProfile.checkbox_properties()


func _get(property: StringName) -> Variant:
	if String(property).begins_with("Connections/"):
		if opening_combinations.is_empty() or opening_combinations[0] == null:
			return false
		return opening_combinations[0].openings.has(StringName(String(property).trim_prefix("Connections/")))
	return null


func _set(property: StringName, value: Variant) -> bool:
	if not String(property).begins_with("Connections/"):
		return false
	if opening_combinations.is_empty():
		opening_combinations.append(AbyssRoomOpeningProfile.new())
	elif opening_combinations[0] == null:
		opening_combinations[0] = AbyssRoomOpeningProfile.new()
	opening_combinations[0].set_connection(
		StringName(String(property).trim_prefix("Connections/")), bool(value), room_size)
	emit_changed()
	return true
