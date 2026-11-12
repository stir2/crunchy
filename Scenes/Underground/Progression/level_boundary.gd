class_name AbyssLevelBoundary
extends TileMapLayer
## Separate indestructible collision, leaving authored source layers untouched.
var progression: AbyssSpecialRooms
var gate: Dictionary = {}
var gate_cells: Array[Vector2i] = []
func configure(service: AbyssSpecialRooms, definition: Dictionary) -> void:
	# The gate actor supplies the visible art. Keep the placeholder cells collision-only.
	self_modulate.a = 0.0
	progression = service
	gate = definition
	service.state.changed.connect(_refresh)
	_refresh()
func _refresh() -> void:
	for cell in gate_cells:
		if progression.is_gate_unlocked(gate):
			erase_cell(cell)
		else:
			set_cell(cell,0,Vector2i.ZERO)
