extends "res://Scenes/Underground/Rooms/authored_room.gd"
## Test fixture only: use exactly the authored-room Hazards/query pipeline.
func _ready() -> void:
	for x in range(5):
		$Hazards.set_cell(Vector2i(x, 0), 0, Vector2i(6, 0))
