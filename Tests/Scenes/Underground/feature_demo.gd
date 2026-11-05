extends Node2D
## Standalone detection/damage probe, deliberately not a player controller.
@export var preview_seed: int = 12345
var state := AbyssRoomState.new()
var room: AbyssAuthoredRoom
var probe: Polygon2D
var _label: Label
var _message := ""
var _inside := false
func _ready() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_label = Label.new()
	_label.position = Vector2(920,60)
	_label.add_theme_font_size_override("font_size",18)
	canvas.add_child(_label)
	_rebuild()
func _rebuild() -> void:
	if is_instance_valid(room):
		room.free()
	var registry := AbyssRoomTemplateRegistry.new()
	registry.templates = [load("res://Scenes/Underground/Rooms/Metadata/feature_room.tres")]
	var selector := AbyssRoomTemplateSelector.new(registry,preview_seed)
	for error in selector.registration_errors:
		push_error(error)
	var req := AbyssRoomRequirements.new()
	req.global_coords = Vector2i(0,1)
	req.region = AbyssRoomData.Region.OPEN
	req.room_size = AbyssRegionConfig.DEFAULT_ROOM_SIZE
	req.opening_schema = &"abyss_slots_v1"
	room = AbyssRoomSceneInstantiator.instantiate_authored(selector.select(req),state)
	if room == null:
		return
	add_child(room)
	room.position = Vector2(70,100)
	room.scale = Vector2(2,2)
	room.breakable_destroyed.connect(_destroyed)
	for marker in AbyssRoomContent.markers(room):
		marker.show_debug = true
	probe = Polygon2D.new()
	probe.polygon = PackedVector2Array([Vector2(-4,-4),Vector2(4,-4),Vector2(4,4),Vector2(-4,4)])
	probe.position = Vector2(10.5,19.5) * 16
	room.add_child(probe)
	_refresh()
func _refresh() -> void:
	if not is_instance_valid(room):
		return
	var rows := PackedStringArray(["ROOM FEATURE LAB — detection probe, no player physics", "Seed: %d | Climbable: %s" % [preview_seed,_inside], "Arrows: free probe | right click: place probe", "Left click cracked wall: 1 damage (group health = 3)", "N: next world seed | R: rebuild same seed (retain state)", "L: collect selected loot | I: activate selected interaction", "F5: save state | F9: load state | K: clear state", "", "GROUPS"])
	for group in room.conditional_wall_groups:
		rows.append("Wall %s: %s" % [group.id,group.included])
	for group in room.conditional_platform_groups:
		rows.append("Platform %s: %s" % [group.id,group.included])
	for group in room.breakables.groups():
		rows.append("Breakable %s health %.1f" % [group.id,group.health])
	rows.append("\nMARKER REQUESTS (no AI, inventory or hazards spawned)")
	for spawn in room.spawn_requests:
		rows.append("%s:%s -> %s [%s]" % [spawn.kind,spawn.marker_id,"SPAWN" if spawn.should_spawn() else "skip",spawn.status()])
	rows.append("\n" + _message)
	_label.text = "\n".join(rows)
func _process(delta: float) -> void:
	if not is_instance_valid(room):
		return
	var axis := Vector2(Input.get_axis("Move Left", "Move Right"), Input.get_axis("Move Up", "Move Down"))
	probe.position += axis * 120 * delta
	var detected: bool = AbyssClimbableTiles.sample(room.climbable_layers(),probe.global_position).climbable
	probe.color = Color.LIME_GREEN if detected else Color.CORAL
	if detected != _inside:
		_inside = detected
		_message = "Entered climbable region" if detected else "Exited climbable region"
		_refresh()
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Preview Damage"):
		room.damage_breakable_at(get_global_mouse_position(),1)
		_refresh()
	elif event.is_action_pressed("Preview Place Probe"):
		probe.global_position = get_global_mouse_position()
	elif event.is_action_pressed("Preview Next Seed"):
		preview_seed += 1
		_rebuild()
	elif event.is_action_pressed("Preview Regenerate"):
		_rebuild()
	elif event.is_action_pressed("Preview Clear State"):
		state = AbyssRoomState.new()
		_rebuild()
	elif event.is_action_pressed("Preview Collect Loot") or event.is_action_pressed("Preview Activate Interaction"):
		var collecting: bool = event.is_action_pressed("Preview Collect Loot")
		var kind: StringName = &"loot" if collecting else &"interaction"
		for spawn in room.spawn_requests:
			if spawn.should_spawn() and spawn.kind == kind:
				spawn.record_status("collected" if collecting else "activated")
		_refresh()
	elif event.is_action_pressed("Preview Save State"):
		var file := FileAccess.open("user://room_feature_state.json",FileAccess.WRITE)
		if file != null:
			file.store_string(state.serialize())
			_message = "Saved user://room_feature_state.json"
		_refresh()
	elif event.is_action_pressed("Preview Load State"):
		if FileAccess.file_exists("user://room_feature_state.json"):
			_message = "State restore result: %s" % state.restore(FileAccess.get_file_as_string("user://room_feature_state.json"))
			_rebuild()
func _destroyed(_id: String, _cells: Array, point: Vector2) -> void:
	var flash := Polygon2D.new()
	flash.polygon = PackedVector2Array([Vector2(-12,0),Vector2(0,-12),Vector2(12,0),Vector2(0,12)])
	flash.color = Color.GOLD
	flash.position = to_local(point)
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash,"modulate:a",0.0,0.4)
	tween.tween_callback(flash.queue_free)
	_message = "Destroyed group; state survives R / F5-F9."
