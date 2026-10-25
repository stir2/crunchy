class_name AbyssConditionalWallGroups
extends RefCounted
## Group-local hashing: adding/reordering another group never consumes this roll.
static func components(layer: TileMapLayer) -> Array[Array]:
	return AbyssTileGroups.components(layer)

static func _mix(value: int, next: int) -> int:
	value = (value * 48271 + posmod(next, 2147483647) + 1) % 2147483647
	return ((value ^ (value >> 13)) * 40699) % 2147483647

static func roll(request: AbyssRoomConstructionRequest, canonical: Vector2i) -> float:
	var value := posmod(request.global_seed, 2147483647)
	for number in [request.requirements.global_coords.x, request.requirements.global_coords.y, 991]:
		value = _mix(value, number)
	for byte in String(request.template_id).to_utf8_buffer():
		value = _mix(value, byte)
	value = _mix(value, 997)
	for number in [canonical.x, canonical.y]:
		value = _mix(value, number)
	# Avalanche the final coordinate; nearby group IDs must not yield nearby
	# rolls (which would correlate their 50-percent inclusion decisions).
	for salt in [1009, 1013, 1019, 1021]:
		value = _mix(value, salt)
	return float(value) / 2147483647.0

static func reserved_cells(room: AbyssAuthoredRoom, req: AbyssRoomRequirements) -> Dictionary:
	var reserved: Dictionary = {}
	for rect in room.reserved_route_rects:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				reserved[Vector2i(x,y)] = true
	# Always preserve an entrance throat, including dead ends and OPEN ports.
	var ports: Array[Vector2i] = []
	var openings := req.route_openings.duplicate()
	openings.merge(req.required_openings, false)
	var ids: Array = openings.keys()
	ids.sort()
	for id in ids:
		var point: Vector2i = openings[id]
		ports.append(point)
		var side := ["north", "east", "south", "west"].find(String(id).get_slice(":", 0))
		if side < 0:
			continue
		for depth in range(3):
			_reserve_neighborhood(reserved, point - AbyssRegionGenerator.DIRECTIONS[side] * depth)
	# Reserve a deterministic tree of existing empty paths between ports. This
	# protects baseline tile connectivity, not movement-aware traversal validity.
	if not ports.is_empty():
		var previous: Dictionary = {ports[0]: ports[0]}
		var pending: Array[Vector2i] = [ports[0]]
		var index := 0
		while index < pending.size():
			var cell := pending[index]
			index += 1
			for direction in AbyssRegionGenerator.DIRECTIONS:
				var next := cell + direction
				if previous.has(next) or not Rect2i(Vector2i.ZERO, req.room_size).has_point(next) or _blocked(room, next):
					continue
				previous[next] = cell
				pending.append(next)
		# A dead end still needs an interior approach, not just a clear port.
		var targets := ports.duplicate()
		var center := Vector2(req.room_size) * 0.5
		var nearest := ports[0]
		var best := INF
		for cell: Vector2i in previous:
			var distance := Vector2(cell).distance_squared_to(center)
			if distance < best:
				nearest = cell
				best = distance
		targets.append(nearest)
		for port in targets:
			if not previous.has(port):
				continue
			var cell: Vector2i = port
			while cell != ports[0]:
				_reserve_neighborhood(reserved, cell)
				cell = previous[cell]
			_reserve_neighborhood(reserved, cell)
	return reserved

static func _reserve_neighborhood(reserved: Dictionary, center: Vector2i) -> void:
	for y in range(-1, 2):
		for x in range(-1, 2):
			reserved[center + Vector2i(x,y)] = true

static func _blocked(room: AbyssAuthoredRoom, cell: Vector2i) -> bool:
	for key in ["Solid", "Platforms", "Climbables"]:
		var layer := room.get_node_or_null(NodePath(key)) as TileMapLayer
		if layer != null:
			var data := layer.get_cell_tile_data(cell)
			if data != null:
				for physics in range(layer.tile_set.get_physics_layers_count()):
					if data.get_collision_polygons_count(physics) > 0:
						return true
	return false

static func apply(room: AbyssAuthoredRoom, request: AbyssRoomConstructionRequest) -> void:
	var layer := room.get_node_or_null("ConditionalWalls") as TileMapLayer
	if layer == null or layer.get_used_cells().is_empty():
		return # Older registered scenes remain compatible, with no groups.
	layer.visible = true
	var reserved := reserved_cells(room, request.requirements)
	var groups: Array[Array] = []
	if room.tile_groups.has("ConditionalWalls"):
		for definition in room.tile_groups["ConditionalWalls"]:
			groups.append(definition.cells)
	else:
		groups = components(layer)
	for group in groups:
		var canonical: Vector2i = group[0]
		var value := roll(request, canonical)
		var reason := "selected" if value < request.conditional_wall_probability else "probability"
		for cell: Vector2i in group:
			if cell.x <= 0 or cell.y <= 0 or cell.x >= room.room_size.x - 1 or cell.y >= room.room_size.y - 1 or reserved.has(cell):
				reason = "protected boundary/route"
				break
		var included := reason == "selected"
		if not included:
			for cell: Vector2i in group:
				layer.erase_cell(cell)
		room.conditional_wall_groups.append({"id": canonical, "cells": group.duplicate(), "roll": value, "included": included, "reason": reason})
		if request.debug_conditional_walls:
			print("Conditional walls: template=%s room=%s group=%s tiles=%d roll=%.4f included=%s (%s)" % [request.template_id, request.requirements.global_coords, canonical, group.size(), value, included, reason])
