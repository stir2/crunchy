extends Node2D
## Finite editor-friendly demonstration. No procedural geometry is built.
@export var registry: AbyssRoomTemplateRegistry


func _ready() -> void:
	var selector := AbyssRoomTemplateSelector.new(registry, 12345)
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
		var origin := Vector2(60 + (index % 3) * 440, 135 + (index / 3) * 450)
		var label := Label.new()
		label.position = origin - Vector2(0, 55)
		label.text = metadata.display_name + "\n" + String(request.template_id)
		add_child(label)
		var instance := AbyssRoomSceneInstantiator.instantiate_authored(request)
		if instance != null:
			instance.position = origin
			instance.scale = Vector2(2, 2)
			add_child(instance)
		index += 1
	var label := Label.new()
	label.position = Vector2(940, 530)
	label.text = "PROCEDURAL FALLBACK\nUnmatched connections return a request.\nGeometry is deferred to Milestone 3B."
	add_child(label)
