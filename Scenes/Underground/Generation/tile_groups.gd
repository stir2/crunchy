class_name AbyssTileGroups
extends RefCounted
## One four-connected flood fill per layer during construction; never per frame.
static func components(layer: TileMapLayer) -> Array[Array]:
	var remaining: Dictionary = {}
	for cell in layer.get_used_cells():
		remaining[cell] = true
	var ordered := layer.get_used_cells()
	ordered.sort()
	var result: Array[Array] = []
	for origin in ordered:
		if not remaining.has(origin):
			continue
		var pending: Array[Vector2i] = [origin]
		var group: Array[Vector2i] = []
		while not pending.is_empty():
			var cell: Vector2i = pending.pop_back()
			if not remaining.has(cell):
				continue
			remaining.erase(cell)
			group.append(cell)
			for direction in AbyssRegionGenerator.DIRECTIONS:
				pending.append(cell + direction)
		group.sort()
		result.append(group)
	return result

static func describe(layer: TileMapLayer, template_id: StringName, overrides: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cells in components(layer):
		var canonical: Vector2i = cells[0]
		var bounds := Rect2i(canonical, Vector2i.ONE)
		var tiles: Array[Dictionary] = []
		for cell: Vector2i in cells:
			bounds = bounds.merge(Rect2i(cell,Vector2i.ONE))
			tiles.append({"cell": cell, "source": layer.get_cell_source_id(cell), "atlas": layer.get_cell_atlas_coords(cell), "alternative": layer.get_cell_alternative_tile(cell)})
		var identity := String(overrides.get(canonical, "%d:%d" % [canonical.x, canonical.y]))
		result.append({"id": "%s/%s/%s" % [template_id, layer.name, identity], "canonical": canonical, "cells": cells, "bounds": bounds, "tile_type": StringName(layer.name), "tiles": tiles})
	return result
