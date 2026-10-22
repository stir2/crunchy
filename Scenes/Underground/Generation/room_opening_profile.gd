class_name AbyssRoomOpeningProfile
extends Resource
## One fixed, realizable opening combination. Different geometry needs a different scene.
@export var variant_id: StringName = &"default"
## Optional scene override for this combination; otherwise use metadata.scene.
@export var scene: PackedScene
@export var openings: Array[StringName] = []
## Exact local tile indices, keyed by the existing side:slot IDs.
@export var opening_tiles: Dictionary[StringName, Vector2i] = {}
## Full open faces (N/E/S/W = 1/2/4/8). PACKED corners remain capped.
@export_flags("North", "East", "South", "West") var open_sides: int = 0
