extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func build_service(seed_value: int, mutations: AbyssProgressionState = null) -> AbyssSpecialRooms:
	var config := AbyssRegionConfig.new()
	config.global_seed = seed_value
	var special := AbyssProgressionConfig.new()
	return AbyssSpecialRooms.new(AbyssRouteGenerator.new(config,AbyssRouteConfig.new(),special),special,mutations if mutations != null else AbyssProgressionState.new())
func snapshot(service: AbyssSpecialRooms, reverse: bool) -> Array:
	var result: Array = []
	var levels := [3,2,1] if reverse else [1,2,3]
	var intervals := [1,0] if reverse else [0,1]
	for level in levels:
		for interval in intervals:
			var data := service.interval_definitions(level,interval)
			for kind in ["fragment","gate"]:
				if not data[kind].is_empty():
					result.append(data[kind].id)
	result.sort()
	return result
func gate_hit(room: AbyssAuthoredRoom, x: int) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = room.to_global((Vector2(x,12)+Vector2(0.5,0.5))*16)
	return not root.world_2d.direct_space_state.intersect_point(query).is_empty()
func run() -> void:
	var source := "res://Scenes/Underground/Rooms/Examples/open_cavern.tscn"
	var bytes := FileAccess.get_file_as_bytes(source)
	var service := build_service(857632823493672366)
	var opposite := build_service(857632823493672366)
	check(snapshot(service,false) == snapshot(opposite,true),"Special placement depends on request order")
	check(snapshot(service,false) != snapshot(build_service(12345),false),"Different seeds must change placement")
	var registry: AbyssRoomTemplateRegistry = load("res://Scenes/Underground/Rooms/example_registry.tres")
	var selector := AbyssRoomTemplateSelector.new(registry,857632823493672366)
	var built: Array[AbyssAuthoredRoom] = []
	var total_gates := 0
	for level in range(1,4):
		for interval in range(2):
			var data := service.interval_definitions(level,interval)
			check(not data.fragment.is_empty(),"Missing guaranteed fragment")
			var fragment: Dictionary = data.fragment
			var coords := Vector2i(fragment.x,fragment.y)
			check(service.routes.get_room(coords).region == AbyssRoomData.Region.PACKED and service.level_at(coords) == level,"Fragment region/level invalid")
			check(coords.y >= interval*50 and coords.y < (interval+1)*50,"Fragment outside interval")
			var request := selector.select_room(service.routes,coords)
			var room := AbyssRoomTerrainBuilder.build(request,AbyssTerrainConfig.new(),null,null,service)
			built.append(room)
			var fragments := room.spawn_requests.filter(func(spawn: RoomSpawnRequest) -> bool: return spawn is AbyssSpecialSpawnRequest and spawn.kind == &"fragment" and spawn.selected)
			check(fragments.size() == 1,"Guaranteed fragment missing from constructed room")
			if not fragments.is_empty():
				check(fragments[0].collect() and not fragments[0].collect(),"Collection must be idempotent")
				var rebuilt := AbyssRoomTerrainBuilder.build(request,AbyssTerrainConfig.new(),null,null,service)
				for spawn in rebuilt.spawn_requests:
					if spawn is AbyssSpecialSpawnRequest and spawn.kind == &"fragment":
						check(not spawn.should_spawn(),"Collected fragment respawned")
				built.append(rebuilt)
			if data.gate.is_empty():
				continue
			total_gates += 1
			var gate: Dictionary = data.gate
			var left := Vector2i(gate.x,gate.y)
			var right := left+Vector2i.RIGHT
			check(service.routes.get_room(left).region == AbyssRoomData.Region.OPEN and service.routes.get_room(right).region == AbyssRoomData.Region.OPEN,"Gate not on valid open border")
			check(not service.routes.get_room(left).allows_open_adjacency(service.routes.get_room(right)),"Natural cavern adjacency bypasses border")
			service.state.keys.erase(service.level_key(level))
			check(not service.can_cross(left,right) and not service.unlock_gate(gate),"Gate unlocked without key")
			var gate_rooms: Array[AbyssAuthoredRoom] = []
			for pos in [left,right]:
				var gate_room := AbyssRoomTerrainBuilder.build(selector.select_room(service.routes,pos),AbyssTerrainConfig.new(),null,null,service)
				root.add_child(gate_room)
				gate_rooms.append(gate_room)
				built.append(gate_room)
				var layer := gate_room.get_node("LevelBoundaryEast" if pos == left else "LevelBoundaryWest") as TileMapLayer
				check(layer.collision_enabled and layer.get_used_cells().size() == 24,"Locked boundary collision incomplete")
				layer.update_internals()
				var tile := layer.get_cell_tile_data(Vector2i(23 if pos == left else 0,12))
				check(tile != null and tile.get_collision_polygons_count(0)>0,"Gate tile lacks solid collision")
			await physics_frame
			await process_frame
			check(gate_hit(gate_rooms[0],23) and gate_hit(gate_rooms[1],0),"Locked gates missing actual physics bodies")
			service.state.record_assembled_key(service.level_key(level))
			check(service.unlock_gate(gate) and service.can_cross(left,right),"Key did not unlock gate")
			check(not service.can_cross(left+Vector2i.DOWN,right+Vector2i.DOWN),"Unlocked gate allows crossing elsewhere")
			for index in range(2):
				var layer := gate_rooms[index].get_node("LevelBoundaryEast" if index == 0 else "LevelBoundaryWest") as TileMapLayer
				check(layer.get_used_cells().size() == 21,"Unlock did not remove exactly three aperture tiles")
				layer.update_internals()
				check(layer.get_cell_source_id(Vector2i(23 if index == 0 else 0,12)) == -1,"Unlocked aperture still collides")
			await physics_frame
			await process_frame
			check(not gate_hit(gate_rooms[0],23) and not gate_hit(gate_rooms[1],0),"Unlocked gate retained physics collision")
	check(total_gates > 0,"Representative seed has no gates")
	# All border rows (including negative depth) reject ordinary route contracts.
	for border in [-4,4,12,20]:
		for cy in [-1,0,1,6]:
			for cx in [border-1,border]:
				var chunk := service.routes.get_chunk(Vector2i(cx,cy))
				check(service.routes.validate_chunk_layout(chunk.coords),"Boundary clipping disconnected chunk network")
				for room in chunk.rooms:
					for edge in room.required_connections:
						check(service.config.same_level(cx,service.routes.regions.room_to_chunk(edge.neighbor).x),"Ordinary route bypasses level border")
	# Checkpoints are OPEN, collision free, stable destinations, and queryable.
	var checkpoint_count := 0
	var checkpoint_coords: Array[Vector2i] = []
	for y in range(50):
		for x in range(-32,32):
			var coords := Vector2i(x,y)
			for definition in service.definitions_at(coords):
				if definition.kind != "checkpoint":
					continue
				checkpoint_count += 1
				checkpoint_coords.append(coords)
				check(service.routes.get_room(coords).region == AbyssRoomData.Region.OPEN,"Checkpoint in packed room")
				var room := AbyssRoomTerrainBuilder.build(selector.select_room(service.routes,coords),AbyssTerrainConfig.new(),null,null,service)
				built.append(room)
				for spawn in room.spawn_requests:
					if spawn is AbyssSpecialSpawnRequest and spawn.kind == &"checkpoint" and spawn.selected:
						check(AbyssSpecialRoomConstruction.spawn_area_clear(room,spawn.local_position),"Checkpoint spawn area obstructed")
						spawn.discover()
						check(service.checkpoint_destination(spawn.definition.id).is_empty(),"Undiscovered activation available as destination")
						check(spawn.activate(),"Checkpoint activation failed")
						var destination := service.checkpoint_destination(spawn.definition.id)
						check(destination.room_coords == coords and destination.spawn_position == room.position+spawn.local_position,"Checkpoint destination transform wrong")
						check(service.request_checkpoint_chunk(spawn.definition.id),"Chunk request failed")
	for coords in checkpoint_coords:
		check(opposite.has_checkpoint(coords),"Checkpoint spacing depends on generation order")
		var radius := service.config.checkpoint_min_spacing_rooms
		for dy in range(-radius+1,radius):
			for dx in range(-radius+1,radius):
				if (dx != 0 or dy != 0) and dx*dx+dy*dy < radius*radius:
					check(not opposite.has_checkpoint(coords+Vector2i(dx,dy)),"Checkpoints violate spacing across neighborhood/chunk halo")
	check(checkpoint_count > 0 and not service.state.activated_checkpoints().is_empty(),"No activated checkpoints")
	service.state.collect_fragment(service.interval_definitions(1,2).fragment)
	check(service.state.can_assemble_key(service.level_key(1)),"Three fragments did not expose key eligibility")
	var saved := service.state.serialize()
	var restored := AbyssProgressionState.new()
	check(restored.restore(saved) == OK and restored.serialize() == saved,"Progression serialization roundtrip failed")
	check(restored.restore("{\"version\":2}") == ERR_INVALID_DATA and restored.serialize() == saved,"Invalid restore modified state")
	var reconstructed := build_service(857632823493672366,restored)
	check(snapshot(reconstructed,true) == snapshot(service,false),"Persistent state changed deterministic definitions")
	check(reconstructed.state.activated_checkpoints() == service.state.activated_checkpoints(),"Activated checkpoints lost on reconstruction")
	var other_world := AbyssSpecialRooms.new(service.routes,service.config,restored,"other-world")
	check(other_world.activated_checkpoints().is_empty(),"Checkpoint query leaked other worlds")
	for entry in restored.activated_checkpoints():
		check(other_world.checkpoint_destination(entry.id).is_empty(),"Other-world checkpoint destination accepted")
	check(not service.state.can_assemble_key("other-world/level/1"),"Fragments leaked across worlds")
	# Authored source data stays byte-identical, and new markers are reusable.
	for kind in ["checkpoint","fragment","gate"]:
		var marker := load("res://Scenes/Underground/Rooms/Markers/%s_marker.tscn" % kind).instantiate() as RoomMarker
		check(marker.make_request() is AbyssSpecialSpawnRequest,"Special marker request type incorrect")
		marker.free()
	for room in built:
		room.free()
	check(bytes == FileAccess.get_file_as_bytes(source),"Authored source changed")
	print("Progression checks: gates=",total_gates," checkpoints=",checkpoint_count," failures=",failures)
	quit(1 if failures else 0)
