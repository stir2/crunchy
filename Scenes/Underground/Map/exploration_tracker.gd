class_name AbyssExplorationTracker
extends Node
@export_range(0.0,5.0,0.05) var visit_dwell_seconds: float = 0.35
var runtime: AbyssRuntime
var state: AbyssExplorationState
var world: String
var _room := Vector2i(2147483647,2147483647)
var _dwell: float = 0.0
var _death_recorded: bool = false
var _settling_grave_id: String = ""
var _grave: InteractionTarget
const GRAVE = preload("res://Scenes/Underground/Map/grave_interactable.gd")

func _ready() -> void:
	process_physics_priority = 50 # Observe the authoritative player position after motion.
	runtime = get_parent() as AbyssRuntime
	var player := runtime.get_node("Player") as Player
	var stream := runtime.get_node("StreamingController") as AbyssRoomStreamer
	player.damage.died.connect(_on_death)
	player.health.health_reset.connect(func() -> void: _death_recorded = false)
	runtime.ready_for_play.connect(func(_destination: Dictionary) -> void: refresh_grave())
	stream.room_loaded.connect(func(_coords: Vector2i) -> void: refresh_grave())
	stream.room_unloaded.connect(func(_coords: Vector2i) -> void: refresh_grave())

func configure(value: AbyssExplorationState, world_id: String) -> void:
	if state != null and state.changed.is_connected(refresh_grave): state.changed.disconnect(refresh_grave)
	state = value
	world = world_id
	state.changed.connect(refresh_grave)
	leave()
	_death_recorded = runtime.player.damage.is_dead()

func leave() -> void:
	_room = Vector2i(2147483647,2147483647)
	_dwell = 0.0
	if is_instance_valid(_grave): _grave.queue_free()
	_grave = null

func _physics_process(delta: float) -> void:
	if state != null and runtime.is_active() and runtime.player.damage.is_dead() and runtime.player.is_on_floor() and not _settling_grave_id.is_empty():
		var entry: Dictionary = state.graves.get(world,{})
		if entry.get("id", "") == _settling_grave_id:
			var feet := runtime.loaded_rooms.to_local(runtime.player.global_position)
			var coords := runtime.stream.world_to_room(runtime.player.global_position)
			entry.position_x = feet.x
			entry.position_y = feet.y
			entry.x = coords.x
			entry.y = coords.y
			state.changed.emit()
		_settling_grave_id = ""
	if state == null or not runtime.is_active() or runtime._holding or runtime.player.damage.is_dead() or not runtime.player.is_physics_processing():
		_dwell = 0.0
		return
	var coords := runtime.stream.world_to_room(runtime.player.global_position)
	if coords != _room:
		_room = coords
		_dwell = 0.0
	if runtime.stream.specials.level_at(coords) <= 0: return
	_dwell += delta
	if _dwell >= visit_dwell_seconds: state.visit(world,coords)

func _on_death(_hit: CombatHit) -> void:
	if state == null or not runtime.is_active() or _death_recorded: return
	_death_recorded = true
	var position := runtime.loaded_rooms.to_local(runtime.player.global_position)
	var carried := state.current_flesh(world)
	var game := runtime.game
	var dropped := floori(carried * game.death_loss_fraction())
	var previous: Dictionary = state.graves.get(world, {}).duplicate(true)
	state.record_death(world,runtime.stream.world_to_room(runtime.player.global_position),position,game.death_loss_fraction())
	_settling_grave_id = str(state.graves[world].id) if previous.is_empty() else ""
	if not previous.is_empty():
		previous.souls = int(previous.souls) + dropped
		state.graves[world] = previous
		state.changed.emit()
	game.add_flesh(carried-dropped)

func refresh_grave() -> void:
	if state == null: return
	var entry: Dictionary = state.graves.get(world,{})
	var show_grave := runtime.is_active() and not runtime.player.damage.is_dead() and not entry.is_empty()
	if show_grave: show_grave = runtime.stream.room_ready(Vector2i(int(entry.x),int(entry.y)))
	if is_instance_valid(_grave):
		if show_grave and _grave.grave_id == entry.id: return
		_grave.queue_free()
		_grave = null
	if not show_grave: return
	_grave = GRAVE.new()
	_grave.state = state
	_grave.world = world
	_grave.grave_id = entry.id
	_grave.position = Vector2(entry.position_x,entry.position_y)
	runtime.loaded_rooms.add_child(_grave)
