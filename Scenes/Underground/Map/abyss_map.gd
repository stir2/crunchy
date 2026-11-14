class_name AbyssMapOverlay
extends CanvasLayer
## Owns only its own pause. Existing pause-menu state is never taken over.
@export_range(0.0,0.5,0.01) var fade_seconds: float = 0.12
@export_range(0,10,1) var nearby_gate_count: int = 3
@export_range(0,10,1) var nearby_fragment_count: int = 3
var runtime: AbyssRuntime
var model: AbyssMapModel
var opened: bool = false
var _owns_pause: bool = false
var _fade: Tween
var _dialogic_paused: bool = false
var _dirty: bool = false
var _minimap_dirty := true
var _minimap_room := Vector2i(2147483647, 2147483647)
var _minimap: AbyssMapView
@onready var _settings: Node = get_node("/root/GameSettings")
@onready var _dialogue: Node = get_node_or_null("/root/Dialogic")
@onready var panel: Control = $Panel
@onready var view: AbyssMapView = $Panel/View

func _ready() -> void:
	runtime = get_parent() as AbyssRuntime
	visible = false
	$Panel/Center.pressed.connect(view.recenter)
	_build_legend()
	$Panel/Legend.resized.connect(_fit_legend, CONNECT_DEFERRED)
	$Panel/Legend.minimum_size_changed.connect(_fit_legend, CONNECT_DEFERRED)
	get_viewport().size_changed.connect(_fit_legend)
	_fit_legend.call_deferred()
	# This layer belongs to gameplay HUD, independent of the paused full map.
	var hud := CanvasLayer.new()
	hud.layer = layer - 1
	add_child(hud)
	_minimap = AbyssMapView.new()
	hud.add_child(_minimap)
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_minimap.self_modulate.a = 0.55
	_minimap.marker_scale = 0.7
	get_viewport().size_changed.connect(_fit_minimap)
	_fit_minimap()
	_minimap.clip_contents = true
	_minimap.pin_gates = false
	_minimap.pin_grave = true
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.hide()

func _fit_minimap() -> void:
	if not _minimap.is_inside_tree():
		return
	var viewport_size := _minimap.get_viewport_rect().size
	var width := roundf(minf(viewport_size.x * 0.225, viewport_size.y * 0.40))
	var margin := roundf(viewport_size.y * 0.02)
	_minimap.offset_left = -margin - width
	_minimap.offset_right = -margin
	_minimap.offset_top = margin
	_minimap.offset_bottom = margin + roundf(width * 0.60)
	_minimap.room_spacing = width / 6.0
	_minimap.recenter()


func _build_legend() -> void:
	for entry in [["player", "You"], ["checkpoint", "Discovered checkpoint"], ["checkpoint", "Activated checkpoint"], ["gate", "Locked gate"], ["gate", "Unlocked gate"], ["fragment", "Uncollected fragment"], ["fragment", "Collected fragment"], ["grave", "Grave"]]:
		var label := Label.new()
		label.text = entry[1]
		label.set_meta("full_text", entry[1])
		label.set_meta("short_text", {"Discovered checkpoint": "Checkpoint", "Activated checkpoint": "Active", "Locked gate": "Gate", "Unlocked gate": "Open gate", "Uncollected fragment": "Fragment", "Collected fragment": "Collected"}.get(entry[1], entry[1]))
		label.add_theme_font_size_override("font_size", 16)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var item := HBoxContainer.new()
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon_space := Control.new()
		icon_space.custom_minimum_size = Vector2(16, 20)
		icon_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := view.marker_scene.instantiate() as Node2D
		icon.kind = entry[0]
		icon.active = entry[1] in ["Collected fragment", "Activated checkpoint", "Unlocked gate"]
		icon.position = Vector2(8, 18 if icon.kind == "fragment" else 10)
		icon_space.add_child(icon)
		item.add_child(icon_space)
		item.add_child(label)
		$Panel/Legend/Markers.add_child(item)

	var explanation := Label.new()
	explanation.name = "Explanation"
	explanation.text = "Faint dots: unexplored connections. Teal / gold / purple: current level 1 / 2 / 3; gray: other levels. Hollow gold circles: fragment hints, including nearby undiscovered rooms. Edge arrows point toward offscreen markers."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explanation.add_theme_font_size_override("font_size", 16)
	explanation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Panel/Legend.add_child(explanation)

func _fit_legend() -> void:
	if not is_inside_tree():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var compact := viewport_size.y <= 480 or viewport_size.x < 800
	var legend: VBoxContainer = $Panel/Legend
	var controls: Label = $Panel/Legend/Controls
	controls.text = "M / Esc / B: close | Move: pan | Wheel / LB / RB: zoom" if compact else "M / Esc: close | Drag / movement keys: pan | Wheel: zoom | N: minimap\nController: View: map | B / Start: close | Left stick: pan | LB / RB: zoom | R3: center | L3: minimap"
	controls.add_theme_font_size_override("font_size", 12 if compact else 16)
	$Panel/Legend/Explanation.visible = not compact
	$Panel/Legend/Markers.add_theme_constant_override("h_separation", 8 if compact else 20)
	$Panel/Legend/Markers.add_theme_constant_override("v_separation", 2 if compact else 4)
	for item in $Panel/Legend/Markers.get_children():
		var label := item.get_child(1) as Label
		label.text = label.get_meta("short_text" if compact else "full_text")
		label.add_theme_font_size_override("font_size", 12 if compact else 16)
	legend.offset_top = -legend.get_combined_minimum_size().y - 8.0
	view.offset_top = 52.0
	view.offset_bottom = legend.offset_top - 8.0

func configure(service: AbyssSpecialRooms, state: AbyssExplorationState, size: Vector2i) -> void:
	close_map()
	if model != null:
		model.exploration.changed.disconnect(_mark_dirty)
		model.service.state.changed.disconnect(_mark_dirty)
	model = AbyssMapModel.new(service,state,size)
	state.changed.connect(_mark_dirty)
	service.state.changed.connect(_mark_dirty)
	_mark_dirty()

func open_map() -> bool:
	if opened or model == null or not runtime.is_active() or get_tree().paused: return false
	_owns_pause = true
	get_tree().paused = true
	if _dialogue != null:
		_dialogic_paused = bool(_dialogue.get("paused"))
		_dialogue.set("paused",true)
	opened = true
	visible = true
	view.map_zoom = 1.0
	_refresh_graph()
	view.recenter()
	panel.modulate.a = 0.0 if fade_seconds > 0 else 1.0
	if _fade != null: _fade.kill()
	_fade = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade.tween_property(panel,"modulate:a",1.0,fade_seconds)
	return true

func close_map() -> void:
	if _fade != null: _fade.kill()
	opened = false
	visible = false
	if _owns_pause:
		get_tree().paused = false
		if is_instance_valid(_dialogue): _dialogue.set("paused",_dialogic_paused)
		_owns_pause = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("Abyss Minimap") and not event.is_echo() and runtime.is_active() and not get_tree().paused:
		_settings.show_abyss_minimap = not _settings.show_abyss_minimap
		_settings.save()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("Abyss Map") and not event.is_echo():
		if opened: close_map()
		else: open_map()
		if runtime.is_active(): get_viewport().set_input_as_handled()
	elif opened and event.is_action_pressed("Map Recenter"):
		view.recenter()
		get_viewport().set_input_as_handled()
	elif opened and (event.is_action_pressed("Map Zoom In") or event.is_action_pressed("Map Zoom Out")):
		view.zoom_at(1.2 if event.is_action_pressed("Map Zoom In") else 1.0 / 1.2, view.size * 0.5)
		get_viewport().set_input_as_handled()
	elif opened and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("Controller Pause")):
		close_map()
		get_viewport().set_input_as_handled()

func _mark_dirty() -> void:
	_dirty = true
	_minimap_dirty = true

func _refresh_graph() -> void:
	var position := runtime.loaded_rooms.to_local(runtime.player.global_position)
	var level := runtime.stream.specials.level_at(runtime.stream.world_to_room(runtime.player.global_position))
	model.nearby_gate_count = nearby_gate_count
	model.nearby_fragment_count = nearby_fragment_count
	view.set_graph(model.snapshot(level,position),float(model.room_size.x*model.tile_pixels),position)
	_dirty = false

func _process(delta: float) -> void:
	_minimap.visible = _settings.show_abyss_minimap and model != null and runtime.is_active() and not get_tree().paused
	if _minimap.visible:
		var position := runtime.loaded_rooms.to_local(runtime.player.global_position)
		var room := runtime.stream.world_to_room(runtime.player.global_position)
		if _minimap_dirty or room != _minimap_room:
			var nearby := Rect2i(room - Vector2i(4, 3), Vector2i(9, 7))
			var graph := model.snapshot(model.service.level_at(room), position, nearby, false)
			_minimap.set_graph(graph, float(model.room_size.x * model.tile_pixels), position)
			_minimap_dirty = false
			_minimap_room = room
		if not position.is_equal_approx(_minimap.center):
			_minimap.player_position = position
			_minimap.recenter()
	if opened:
		if _dirty: _refresh_graph()
		var direction := Input.get_vector("Move Left","Move Right","Move Up","Move Down")
		if not direction.is_zero_approx():
			view.pan_screen(-direction*220.0*delta)

func _exit_tree() -> void:
	close_map()
