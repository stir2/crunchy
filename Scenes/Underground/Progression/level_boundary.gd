class_name AbyssLevelBoundary
extends TileMapLayer
## Separate indestructible collision, leaving authored source layers untouched.
var progression: AbyssSpecialRooms
var gate: Dictionary = {}
var gate_cells: Array[Vector2i] = []
func configure(service: AbyssSpecialRooms, definition: Dictionary) -> void:
	progression = service
	gate = definition
	service.state.changed.connect(_refresh)
	_refresh()
func _refresh() -> void:
	for cell in gate_cells:
		if progression.state.is_gate_unlocked(gate.get("id","")):
			erase_cell(cell)
		else:
			set_cell(cell,0,Vector2i.ZERO)
