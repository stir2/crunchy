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
@onready var _dialogue: Node = get_node_or_null("/root/Dialogic")
@onready var panel: Control = $Panel
@onready var view: AbyssMapView = $Panel/View

func _ready() -> void:
	runtime = get_parent() as AbyssRuntime
	visible = false
	$Panel/Center.pressed.connect(view.recenter)

func configure(service: AbyssSpecialRooms, state: AbyssExplorationState, size: Vector2i) -> void:
	close_map()
	if model != null:
		model.exploration.changed.disconnect(_mark_dirty)
		model.service.state.changed.disconnect(_mark_dirty)
	model = AbyssMapModel.new(service,state,size)
	state.changed.connect(_mark_dirty)
	service.state.changed.connect(_mark_dirty)

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
	if event.is_action_pressed("Abyss Map") and not event.is_echo():
		if opened: close_map()
		else: open_map()
		if runtime.is_active(): get_viewport().set_input_as_handled()
	elif opened and event.is_action_pressed("ui_cancel"):
		close_map()
		get_viewport().set_input_as_handled()

func _mark_dirty() -> void:
	_dirty = true

func _refresh_graph() -> void:
	var position := runtime.loaded_rooms.to_local(runtime.player.global_position)
	var level := runtime.stream.specials.level_at(runtime.stream.world_to_room(runtime.player.global_position))
	model.nearby_gate_count = nearby_gate_count
	model.nearby_fragment_count = nearby_fragment_count
	view.set_graph(model.snapshot(level,position),float(model.room_size.x*model.tile_pixels),position)
	_dirty = false

func _process(delta: float) -> void:
	if opened:
		if _dirty: _refresh_graph()
		var direction := Input.get_vector("Move Left","Move Right","Move Up","Move Down")
		if not direction.is_zero_approx(): view.pan_screen(-direction*220.0*delta)

func _exit_tree() -> void:
	close_map()
