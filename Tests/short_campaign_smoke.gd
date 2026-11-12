extends SceneTree

const MAIN := "res://Scenes/Main/main.tscn"
const HOUSE := "res://Scenes/Village/House/house.tscn"
const MENU := "res://Scenes/Menus/main_menu.tscn"
const BOSS := "res://Scenes/Boss/boss_arena.tscn"

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var game := root.get_node("GameController")
	var saves := root.get_node("SaveManager")
	if saves.has_save_file(5) or saves.has_save_file(10):
		push_error("Run this smoke test with an isolated Godot user directory.")
		quit(1)
		return
	change_scene_to_file(MAIN)
	while current_scene == null:
		await process_frame
	var host := current_scene
	var menu: Node = host.active_scene
	var short_button := menu.get_node("Buttons/CampaignPicker/Campaign5") as Button
	short_button.pressed.emit()
	menu.get_node("%NewGameButton").pressed.emit()
	_check(game.run_length == 5 and game.current_quota() == 12 and game.trips_left == 5, "Short campaign did not start")
	await create_timer(1.0).timeout
	host.change_scene(HOUSE)
	game.window_history["descend_first"] = true
	host.active_scene.descend_btn.pressed.emit()
	var abyss := host.active_scene as AbyssRuntime
	if abyss == null:
		_check(false, "The short campaign did not enter the Abyss")
		quit(1)
		return
	for frame in range(600):
		if abyss.is_active() or not abyss.last_error.is_empty():
			break
		await process_frame
	_check(abyss.is_active(), "Compact Abyss failed to stream")
	if not abyss.is_active():
		quit(1)
		return
	var planner := abyss.stream.specials
	var routes := abyss.stream.routes
	var entry := routes.entrance_room()
	for level in range(1, 4):
		var visited := _connected_rooms(planner, entry, level)
		for interval in range(2):
			var plan := planner.interval_definitions(level, interval)
			_check(not plan.fragment.is_empty() and visited.has(Vector2i(plan.fragment.x, plan.fragment.y)),
				"A required key fragment is unreachable in Level %d" % level)
			_check(visited.has(plan.checkpoint) and planner.has_checkpoint(plan.checkpoint),
				"A compact checkpoint is unreachable in Level %d" % level)
			if not plan.fragment.is_empty():
				planner.state.collect_fragment(plan.fragment)
		_check(planner.interval_definitions(level, 0).gate.is_empty()
			and planner.interval_definitions(level, 2).gate.is_empty(), "Compact Abyss contains an extra gate")
		var gate: Dictionary = planner.interval_definitions(level, 1).gate
		if level == 3:
			_check(gate.is_empty(), "A gate leads out of Level 3")
			break
		_check(not gate.is_empty() and visited.has(Vector2i(gate.x, gate.y)),
			"Gate from Level %d is unreachable" % level)
		if gate.is_empty():
			break
		var source := Vector2i(gate.x, gate.y)
		entry = source + Vector2i.RIGHT
		var west := _build_gate_side(abyss.stream, source, "LevelBoundaryEast")
		var east := _build_gate_side(abyss.stream, entry, "LevelBoundaryWest")
		_check(_gate_collision(west, true) and _gate_collision(east, true), "Locked gate collision was missing")
		_check(not planner.can_cross(source, entry), "Crossing was open without a key")
		_check(planner.unlock_gate(gate) and planner.can_cross(source, entry), "Two fragments did not unlock the crossing")
		_check(not routes.get_room(entry).required_connections.is_empty(), "Gate exit does not connect to the next level")
		_check(_gate_collision(west, false) and _gate_collision(east, false), "Unlock did not clear both gate barriers")
		for boundary in [west, east]:
			if boundary != null:
				boundary.get_parent().free()
	_check(planner.level_at(Vector2i(0, 16)) == 0 and planner.level_at(Vector2i(24, 0)) == 3
		and planner.level_at(Vector2i(40, 0)) == 0, "Compact layout exceeded its depth or level count")
	# Build the actual checkpoint rooms and query their collision geometry.
	abyss.stream.active = false
	for level in range(1, 4):
		for interval in range(2):
			var coords: Vector2i = planner.interval_definitions(level, interval).checkpoint
			if not abyss.stream.rooms.has(coords):
				abyss.stream._build_room(coords)
			await physics_frame
			await physics_frame
			var landing := {}
			for request in abyss.stream.rooms[coords].spawn_requests:
				if request.kind == &"checkpoint":
					landing = AbyssEntranceSpawn.find_checkpoint(abyss.player, abyss.stream,
						{"id": String(request.marker_id), "room_coords": coords})
					break
			_check(not landing.is_empty(), "Checkpoint lacks a safe landing in Level %d, band %d" % [level, interval])
	var checkpoint_coords: Vector2i = planner.interval_definitions(1, 0).checkpoint
	if not abyss.stream.rooms.has(checkpoint_coords):
		abyss.stream._build_room(checkpoint_coords)
	var checkpoint_id := ""
	for request in abyss.stream.rooms[checkpoint_coords].spawn_requests:
		if request.kind == &"checkpoint":
			_check(request.activate(), "Checkpoint could not activate")
			checkpoint_id = String(request.marker_id)
			break
	_check(not checkpoint_id.is_empty(), "Checkpoint room did not contain its marker")
	host.change_scene(HOUSE)
	game.day = 4
	game.trips_left = 5
	_check(game.current_quota() == 32, "Short Day 4 quota is wrong")
	_check(saves.save_game(), "Short save failed: " + saves.last_error)
	_check(saves.menu_preview(5).get("day", 0) == 4, "Short save preview lost the day")
	host.change_scene(MENU)
	_check(saves.menu_preview(10).is_empty(), "Short save appeared in the classic slot")
	_check(saves.load_game(5) and game.run_length == 5 and game.day == 4 and game.trips_left == 5, "Short save failed to restore")
	host.change_scene(HOUSE)
	var house: Node = host.active_scene
	house.descend_btn.pressed.emit()
	_check(house._descent_panel.visible and house._destination_list.get_child_count() == 2,
		"Stairs did not offer the entrance and saved checkpoint")
	var trips: int = game.trips_left
	if house._destination_list.get_child_count() == 2:
		var view: AbyssMapView = house._destination_map
		for marker: Dictionary in view.graph.markers:
			if marker.id != checkpoint_id:
				continue
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.position = view.world_to_screen(marker.position)
			click.pressed = true
			view._gui_input(click)
			click.pressed = false
			view._gui_input(click)
		_check(house._selected_destination == checkpoint_id and game.trips_left == trips,
			"Clicking a checkpoint should select it without starting a descent")
		await process_frame
		var pointer: Sprite2D = house.get_node("UI/ControllerPointer")
		pointer.position = house._destination_confirm.get_global_rect().get_center()
		pointer.show()
		var click := InputEventJoypadButton.new()
		click.button_index = JOY_BUTTON_RIGHT_SHOULDER
		click.pressed = true
		Input.parse_input_event(click)
		await process_frame
		_check(game.trips_left == trips, "Controller pointer click charged a trip before release")
		click = InputEventJoypadButton.new()
		click.button_index = JOY_BUTTON_RIGHT_SHOULDER
		Input.parse_input_event(click)
		await process_frame
		await process_frame
		_check(host.active_scene is AbyssRuntime, "Controller pointer did not confirm the descent")
		var resumed := host.active_scene as AbyssRuntime
		_check(game.trips_left == trips, "Checkpoint charged a trip before loading")
		if resumed != null:
			for frame in range(1200):
				if resumed.is_active() or not resumed.last_error.is_empty():
					break
				await process_frame
			_check(resumed.is_active() and resumed.destination.get("id") == checkpoint_id,
				"Checkpoint descent did not reach its saved destination: " + resumed.last_error)
			_check(game.trips_left == trips - 1, "Checkpoint descent did not charge exactly one trip")
			_check(resumed.entrance_return.global_position.distance_to(resumed.player.global_position) > 100.0,
				"Checkpoint descent moved the entrance extraction point")
	host.change_scene(HOUSE)
	game.night_in_progress = true
	game.finish_night(true)
	_check(game.day == 5 and game.is_final_day() and game.current_quota() == 0, "Short finale did not start on Day 5")
	host.change_scene(host.CUTSCENE_SCENE)
	_check(host.active_scene._is_infinity, "Short Day 5 did not display the infinity toll")
	game.monster_missing = true
	host.change_scene(HOUSE)
	host.active_scene._descend()
	_check(host.active_path == BOSS, "The short finale did not lead to the existing boss")
	await process_frame
	host.change_scene(MENU)
	await process_frame
	game.run_length = 10
	_check(not game.is_final_day() and game.quota_for_day(4) == 40 and game.quota_for_day(9) == 98,
		"Classic campaign quota or finale changed")
	DirAccess.remove_absolute(saves.SHORT_SAVE_PATH)
	await create_timer(2.0).timeout
	print("Short campaign smoke: failures=", failures)
	quit(int(failures > 0))


func _connected_rooms(planner: AbyssSpecialRooms, entry: Vector2i, level: int) -> Dictionary:
	var visited := {entry: true}
	var frontier: Array[Vector2i] = [entry]
	while not frontier.is_empty():
		var coords: Vector2i = frontier.pop_back()
		_check(planner.level_at(coords) == level, "The route bypassed a gate or finite bounds")
		for connection in planner.routes.get_room(coords).required_connections:
			if not visited.has(connection.neighbor):
				visited[connection.neighbor] = true
				frontier.append(connection.neighbor)
	return visited

func _build_gate_side(stream: AbyssRoomStreamer, coords: Vector2i, side: String) -> AbyssLevelBoundary:
	var request := stream.selector.select_room(stream.routes, coords)
	var room := AbyssRoomTerrainBuilder.build(request, stream.terrain_config, stream.boundary, stream.mutations, stream.specials)
	if room == null:
		return null
	var boundary := room.get_node_or_null(side) as AbyssLevelBoundary
	if boundary == null:
		room.free()
	return boundary


func _gate_collision(boundary: AbyssLevelBoundary, locked: bool) -> bool:
	if boundary == null or boundary.gate_cells.is_empty():
		return false
	for cell in boundary.gate_cells:
		if (boundary.get_cell_source_id(cell) >= 0) != locked:
			return false
	return true
