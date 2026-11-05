extends Node2D
## Finite editor-friendly demonstration. No procedural geometry is built.
@export var preview_seed: int = 12345
var _cards: Node2D
@export var registry: AbyssRoomTemplateRegistry


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if is_instance_valid(_cards):
		remove_child(_cards)
		_cards.free()
	_cards = Node2D.new()
	add_child(_cards)
	var selector := AbyssRoomTemplateSelector.new(registry, preview_seed)
	var config := AbyssRegionConfig.new()
	var routes := AbyssRouteConfig.new()
	var index := 0
	for metadata in registry.templates:
		var profile := metadata.opening_combinations[0]
		var room := AbyssRoomData.new()
		room.global_coords = Vector2i(index, 0)
		room.region = metadata.transition_base_region if metadata.region == AbyssRoomTemplateMetadata.Compatibility.TRANSITION else int(metadata.region)
		room.boundary_mask = profile.open_sides if metadata.region == AbyssRoomTemplateMetadata.Compatibility.TRANSITION else 0
		room.required_openings = profile.opening_tiles.duplicate()
		# Full transition faces also satisfy route openings on that face.
		if metadata.region == AbyssRoomTemplateMetadata.Compatibility.TRANSITION:
			room.required_openings[&"west:0"] = routes.opening_position(3, 0, config.room_size)
		for id in room.required_openings:
			var edge := AbyssRouteConnection.new()
			edge.opening_id = id
			edge.opening_tile = room.required_openings[id]
			room.required_connections.append(edge)
		var neighbors: Array[AbyssRoomData] = []
		for side in range(4):
			var neighbor := AbyssRoomData.new()
			neighbor.global_coords = room.global_coords + AbyssRegionGenerator.DIRECTIONS[side]
			neighbor.region = AbyssRoomData.Region.OPEN if profile.open_sides & (1 << side) else AbyssRoomData.Region.PACKED
			neighbors.append(neighbor)
		var requirements := AbyssRoomRequirements.from_room(room, config, routes, neighbors)
		var request := selector.select(requirements)
		var footprint := Vector2(config.room_size * registry.tile_pixels)
		var spacing := footprint + Vector2(56, 66)
		var origin := Vector2(60, 135) + Vector2(index % 3, index / 3) * spacing
		var label := Label.new()
		label.position = origin - Vector2(0, 55)
		label.text = metadata.display_name + "\n" + String(request.template_id)
		_cards.add_child(label)
		var instance := AbyssRoomSceneInstantiator.instantiate_authored(request)
		if instance != null:
			instance.position = origin
			_cards.add_child(instance)
			if not instance.conditional_wall_groups.is_empty():
				var included := 0
				for group in instance.conditional_wall_groups:
					included += int(group.included)
				label.text += " • walls %d/%d" % [included, instance.conditional_wall_groups.size()]
		index += 1
	var label := Label.new()
	label.position = Vector2(60, 135) + Vector2(2, 1) * (Vector2(config.room_size * registry.tile_pixels) + Vector2(56, 66))
	label.text = "CONDITIONAL WALLS\nSeed: %d (N: next seed)\nOrange tiles: selected groups\nEnable metadata debug log for group IDs." % preview_seed
	_cards.add_child(label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Preview Next Seed"):
		preview_seed += 1
		_rebuild()
