class_name AbyssClimbableTiles
extends RefCounted
## Use the same interface for authored and future procedural TileMapLayers.
static func is_climbable(layer: TileMapLayer, cell: Vector2i) -> bool:
	if layer == null or not layer.enabled or layer.tile_set == null or layer.tile_set.get_custom_data_layer_by_name("climbable") < 0:
		return false
	var data := layer.get_cell_tile_data(cell)
	return data != null and bool(data.get_custom_data("climbable"))
static func sample(layers: Array[TileMapLayer], world_position: Vector2) -> Dictionary:
	for layer in layers:
		var cell := layer.local_to_map(layer.to_local(world_position))
		if is_climbable(layer, cell):
			return {"climbable":true, "layer":layer, "cell":cell, "world_position":layer.to_global(layer.map_to_local(cell))}
	return {"climbable":false}
static func vertical_path(layers: Array[TileMapLayer], start: Vector2, end: Vector2, step_pixels: float = 4.0) -> bool:
	if not is_equal_approx(start.x, end.x) or step_pixels <= 0:
		return false
	var steps := maxi(1, ceili(start.distance_to(end) / step_pixels))
	for i in range(steps + 1):
		if not sample(layers, start.lerp(end, float(i) / steps)).climbable:
			return false
	return true
