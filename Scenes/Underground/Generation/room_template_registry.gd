class_name AbyssRoomTemplateRegistry
extends Resource
## Add metadata resources here using the Inspector; the route generator is unaware.
## Shared world tile scale; every registered room must agree.
@export var tile_pixels: int = 16
@export var templates: Array[AbyssRoomTemplateMetadata] = []
