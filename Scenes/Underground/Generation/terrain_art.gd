class_name AbyssTerrainArt
extends RefCounted
## Appearance only: occupancy and collision footprints never change.
const SOURCE: int = 2
const OFFSETS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT,
	Vector2i(1,-1), Vector2i(1,1), Vector2i(-1,1), Vector2i(-1,-1)]
const ATLAS: Dictionary = {
	0: Vector2i(0, 3),
	1: Vector2i(0, 2),
	2: Vector2i(1, 3),
	3: Vector2i(1, 2),
	4: Vector2i(0, 0),
	5: Vector2i(0, 1),
	6: Vector2i(1, 0),
	7: Vector2i(1, 1),
	8: Vector2i(3, 3),
	9: Vector2i(3, 2),
	10: Vector2i(2, 3),
	11: Vector2i(2, 2),
	12: Vector2i(3, 0),
	13: Vector2i(3, 1),
	14: Vector2i(2, 0),
	15: Vector2i(2, 1),
	19: Vector2i(8, 3),
	23: Vector2i(4, 2),
	27: Vector2i(5, 3),
	31: Vector2i(7, 0),
	38: Vector2i(8, 0),
	39: Vector2i(4, 1),
	46: Vector2i(5, 0),
	47: Vector2i(7, 3),
	55: Vector2i(8, 1),
	63: Vector2i(8, 2),
	76: Vector2i(11, 0),
	77: Vector2i(7, 1),
	78: Vector2i(6, 0),
	79: Vector2i(4, 3),
	95: Vector2i(9, 1),
	110: Vector2i(10, 0),
	111: Vector2i(9, 0),
	127: Vector2i(5, 1),
	137: Vector2i(11, 3),
	139: Vector2i(6, 3),
	141: Vector2i(7, 2),
	143: Vector2i(4, 0),
	155: Vector2i(9, 3),
	159: Vector2i(10, 3),
	175: Vector2i(10, 2),
	191: Vector2i(5, 2),
	205: Vector2i(11, 2),
	207: Vector2i(11, 1),
	223: Vector2i(6, 2),
	239: Vector2i(6, 1),
	255: Vector2i(9, 2),
}

static func setup(room: AbyssAuthoredRoom, boundary: AbyssCavernBoundaryField) -> void:
	refresh(room, boundary)
	var room_ref: WeakRef = weakref(room)
	room.breakable_destroyed.connect(func(_id: String, cells: Array, _point: Vector2) -> void:
		var current := room_ref.get_ref() as AbyssAuthoredRoom
		if current != null: refresh(current, boundary, cells))

static func refresh(room: AbyssAuthoredRoom, boundary: AbyssCavernBoundaryField, changed: Array = []) -> void:
	var occupied: Dictionary = {}
	for name_value in ["Solid", "ConditionalWalls", "BreakableWalls"]:
		var layer := room.get_node_or_null(NodePath(name_value)) as TileMapLayer
		if layer == null: continue
		for cell in layer.get_used_cells():
			if AbyssRoomTemplateValidator._has_solid_collision(layer, cell): occupied[cell] = true
	var affected: Dictionary = {}
	for cell: Vector2i in changed:
		for y in range(-1,2):
			for x in range(-1,2): affected[cell + Vector2i(x,y)] = true
	for name_value in ["Solid", "ConditionalWalls"]:
		var layer := room.get_node_or_null(NodePath(name_value)) as TileMapLayer
		if layer == null or layer.tile_set == null or not layer.tile_set.has_source(SOURCE): continue
		var cells: Array = layer.get_used_cells() if changed.is_empty() else affected.keys()
		for cell: Vector2i in cells:
			var source := layer.get_cell_source_id(cell)
			# Only rock changes atlas coordinates; feature tiles keep their artwork.
			if not (source == SOURCE or (source == 0 and layer.get_cell_atlas_coords(cell) == Vector2i.ZERO)): continue
			var mask := 0
			for index in range(OFFSETS.size()):
				if _filled(cell + OFFSETS[index], occupied, room, boundary): mask |= 1 << index
			layer.set_cell(cell, SOURCE, atlas_for_mask(mask))

static func refresh_layer(layer: TileMapLayer, changed: Array = []) -> void:
	if layer == null or layer.tile_set == null or not layer.tile_set.has_source(SOURCE):
		return
	var occupied: Dictionary = {}
	for cell in layer.get_used_cells():
		if AbyssRoomTemplateValidator._has_solid_collision(layer, cell):
			occupied[cell] = true
	var affected: Dictionary = {}
	for cell: Vector2i in changed:
		for y in range(-1, 2):
			for x in range(-1, 2):
				affected[cell + Vector2i(x, y)] = true
	var cells: Array = layer.get_used_cells() if changed.is_empty() else affected.keys()
	for cell: Vector2i in cells:
		var source := layer.get_cell_source_id(cell)
		if not (source == SOURCE or (source == 0 and layer.get_cell_atlas_coords(cell) == Vector2i.ZERO)):
			continue
		var mask := 0
		for index in range(OFFSETS.size()):
			if occupied.has(cell + OFFSETS[index]):
				mask |= 1 << index
		layer.set_cell(cell, SOURCE, atlas_for_mask(mask))

static func atlas_for_mask(mask: int) -> Vector2i:
	# Diagonals matter only when both adjoining cardinal neighbors exist.
	for corner in [[16,1,2], [32,2,4], [64,4,8], [128,8,1]]:
		if not (mask & corner[1]) or not (mask & corner[2]): mask &= ~int(corner[0])
	return ATLAS[mask]

static func _filled(cell: Vector2i, occupied: Dictionary, room: AbyssAuthoredRoom, boundary: AbyssCavernBoundaryField) -> bool:
	if Rect2i(Vector2i.ZERO, room.room_size).has_point(cell): return occupied.has(cell)
	if boundary != null and room.construction_requirements != null:
		return boundary.is_solid(room.construction_requirements.global_coords * room.room_size + cell)
	# A packed room border continues into its neighbor rather than drawing a seam.
	return occupied.has(cell.clamp(Vector2i.ZERO, room.room_size - Vector2i.ONE))
