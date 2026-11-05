extends Node2D
## Lab-only tile fixture. Same provider API and shared tiles as authored rooms.
func _ready() -> void:
	for y in range(-16, 0):
		$Climbables.set_cell(Vector2i(4,y),0,Vector2i(3,0))
	for y in range(-50, 0):
		$Climbables.set_cell(Vector2i(20,y),0,Vector2i(4,0))
	for x in range(1,12):
		$Platforms.set_cell(Vector2i(x,-15),0,Vector2i(1,0))
	for x in range(18,25):
		$Platforms.set_cell(Vector2i(x,-49),0,Vector2i(1,0))

func climbable_layers() -> Array[TileMapLayer]:
	return [$Climbables as TileMapLayer]
