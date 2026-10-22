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
@export var room_size: Vector2i = Vector2i(12, 12)
## Version the physical opening convention independently of template IDs.
@export var opening_schema: StringName = &"abyss_slots_v1"
## Legacy union of supported side:slot IDs. Profiles are the authoritative
## combinations; this union alone never implies that arbitrary subsets are safe.
@export var supported_openings: Array[StringName] = []
@export var opening_combinations: Array[AbyssRoomOpeningProfile] = []
@export_range(0.0, 1000.0, 0.1) var selection_weight: float = 1.0
@export var compatibility_tags: Array[StringName] = []
