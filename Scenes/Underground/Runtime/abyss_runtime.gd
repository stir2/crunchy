class_name AbyssRuntime
extends Node2D
## Instantiate below persistent Main (or F6). Entry/leave never changes SceneTree scenes.
signal ready_for_play(destination: Dictionary)
signal startup_failed(message: String)
signal streaming_hold_changed(holding: bool)
signal returned_to_village(flesh_banked: int)
@export var auto_start: bool = true
@export var configuration: AbyssRegionConfig = AbyssRegionConfig.new()
@export var route_configuration: AbyssRouteConfig = AbyssRouteConfig.new()
@export var terrain_configuration: AbyssTerrainConfig = AbyssTerrainConfig.new()
@export var progression_configuration: AbyssProgressionConfig = AbyssProgressionConfig.new()
@export var template_registry: AbyssRoomTemplateRegistry = preload("res://Scenes/Underground/Rooms/authored_registry.tres")
@export_group("Local Presentation")
@export var apply_pixel_presentation: bool = true
@export var viewport_pixels: Vector2i = Vector2i(640,360)
@export var standalone_window_pixels: Vector2i = Vector2i(1280,720)
var destination: Dictionary = {}
var last_error: String = ""
var _active: bool = false
var _starting: bool = false
var _holding: bool = false
var _resume_sprite: bool = false
var _vitals_initialized: bool = false
var _serial: int = 0
var _jump_pressed: bool = false
var _jump_released: bool = false
var _dash_pressed: bool = false
var _saved_window: Dictionary = {}
var _day: int = -1
var _return_pending: bool = false
var _state: AbyssRoomState
@onready var entrance_return: InteractionTarget = $EntranceReturn
@onready var flesh_hud: AbyssFleshHUD = $FleshHUD
@onready var exploration: AbyssExplorationTracker = $ExplorationTracker
@onready var abyss_map: AbyssMapOverlay = $AbyssMap
@onready var interactions: PlayerInteractionController = $Player/InteractionController
@onready var game: Node = get_node("/root/GameController")
@onready var player: Player = $Player
@onready var stream: AbyssRoomStreamer = $StreamingController
@onready var camera: AbyssAxisFollowCamera = $Camera2D
@onready var loaded_rooms: Node2D = $LoadedRooms
@onready var sprite: AnimatedSprite2D = $Player/Visuals/AnimatedSprite2D

func _ready() -> void:
	_set_visibility(false)
	interactions.set_enabled(false)
	player.set_physics_process(false)
	stream.player = player
	stream.camera = camera
	stream.container = loaded_rooms
	stream.runtime = self
	if auto_start:
		await enter_entrance()

func is_starting() -> bool:
	return _starting

func is_active() -> bool:
	return _active and not _starting

## Only entrance spawning is implemented. Future checkpoint APIs can supply a
## destination dictionary with room_coords/spawn_position after loading its area.
func enter_entrance() -> bool:
	if _starting:
		return false
	if _active:
		leave()
	_serial += 1
	var token := _serial
	_starting = true
	_return_pending = false
	last_error = ""
	$StartupStatusCanvas.visible = false
	_set_visibility(false)
	interactions.set_enabled(false)
	player.set_physics_process(false)
	_apply_presentation()
	var state: AbyssRoomState = game.abyss_room_state
	if _state != state:
		_vitals_initialized = false
	_state = state
	if not _configure_world(state):
		return false
	state.begin_day(game.day)
	_day = state.current_day
	_restore_vitals(state)
	if not player.damage.is_dead(): state.exploration.begin_descent(stream.specials.world)
	var entrance := stream.routes.entrance_room()
	if stream.specials.level_at(entrance) != 1:
		fail_startup("Configured route entrance is outside Level 1")
		return false
	stream.active = true
	stream.current_room = entrance
	stream.request_neighborhood(entrance)
	while not stream.neighborhood_ready(entrance):
		await get_tree().process_frame
		if token != _serial or not is_inside_tree():
			return false
	# Direct-space queries run from a physics frame after tile collisions settle.
	await get_tree().physics_frame
	if token != _serial:
		return false
	destination = AbyssEntranceSpawn.find(player,stream,entrance)
	if destination.is_empty():
		fail_startup("No safe 30x36 entrance landing in the existing Level 1 terrain")
		return false
	player.global_position = destination.spawn_position
	entrance_return.global_position = destination.spawn_position+Vector2(0,-18)
	player.reset_movement() # Temporary abilities only; never heal/reset stamina.
	_starting = false
	_active = true
	_set_visibility(true)
	camera.activate(player,stream)
	player.set_physics_process(true)
	interactions.set_enabled(true)
	ready_for_play.emit(destination.duplicate(true))
	return true

func _configure_world(state: AbyssRoomState) -> bool:
	configuration = configuration.duplicate() as AbyssRegionConfig
	route_configuration = route_configuration.duplicate() as AbyssRouteConfig
	terrain_configuration = terrain_configuration.duplicate() as AbyssTerrainConfig
	progression_configuration = progression_configuration.duplicate() as AbyssProgressionConfig
	var configs: Array[Resource] = [configuration,route_configuration,terrain_configuration,progression_configuration]
	var settings := state.world_settings
	if settings.is_empty():
		var progression: AbyssProgressionState = game.abyss_progression_state
		if not state.groups.is_empty() or not state.markers.is_empty() or not progression.checkpoints.is_empty() or not progression.fragments.is_empty() or not progression.gates.is_empty() or not progression.keys.is_empty() or not progression.unlocked_levels.is_empty() or not state.exploration.visited.is_empty() or not state.exploration.graves.is_empty() or not state.exploration.descent_souls.is_empty():
			fail_startup("Existing abyss progress has no layout version. It was preserved; start a separate new run for the 40x40 layout.")
			return false
		if template_registry.resource_path.is_empty():
			fail_startup("Save the runtime template registry as a .tres resource first")
			return false
		settings = AbyssRuntimeWorldSettings.capture(configs,template_registry)
	else:
		var mismatch := AbyssRuntimeWorldSettings.compatibility_error(settings,configuration,route_configuration)
		if not mismatch.is_empty():
			fail_startup(mismatch)
			return false
		if not AbyssRuntimeWorldSettings.apply(settings,configs):
			fail_startup("Saved abyss world settings are invalid or incompatible; no progress was changed")
			return false
	template_registry = load(settings.registry) as AbyssRoomTemplateRegistry
	if template_registry == null or not configuration.is_valid() or not route_configuration.is_valid(configuration.room_size) or not progression_configuration.is_valid():
		fail_startup("Invalid abyss runtime configuration")
		return false
	if configuration.chunk_size != Vector2i(8,8) or template_registry.tile_pixels != 16:
		fail_startup("Runtime requires the existing 8x8-room chunks and 16px tile grid")
		return false
	if not stream.configure(configuration,route_configuration,terrain_configuration,progression_configuration,template_registry,state,game.abyss_progression_state):
		fail_startup("Room template registration failed:\n" + "\n".join(stream.selector.registration_errors))
		return false
	if not stream.deferred_templates.is_empty():
		print("Abyss: ",stream.deferred_templates.size()," authored templates remain registered at their original layout; using procedural fallback until remade for ",configuration.room_size," / ",route_configuration.opening_schema)
	state.world_settings = AbyssRuntimeWorldSettings.capture(configs,template_registry)
	exploration.configure(state.exploration,stream.specials.world)
	abyss_map.configure(stream.specials,state.exploration,configuration.room_size)
	flesh_hud.bind_state(game,state.exploration,stream.specials.world,player)
	return true

func set_streaming_hold(holding: bool) -> void:
	if _holding == holding or not is_active():
		return
	_holding = holding
	player.set_physics_process(not holding)
	interactions.set_enabled(not holding)
	if holding:
		_resume_sprite = sprite.is_playing()
		sprite.pause()
	else:
		if _resume_sprite and not player.combat.is_hitstopped() and not player.combat.is_swing_frozen():
			sprite.play()
		player.resume_combat_jump_input(_jump_pressed,_jump_released)
		if _dash_pressed:
			if player.combat.is_attacking():
				player.combat.buffered_dash = true
			else:
				player.try_start_dash(true)
		_jump_pressed = false
		_jump_released = false
		_dash_pressed = false
	streaming_hold_changed.emit(holding)

func _physics_process(_delta: float) -> void:
	if is_active() and (game.abyss_room_state != _state or _state.current_day != _day):
		# Day transitions belong to the future host flow; safely rebuild before
		# allowing the player into restored breakables, without granting vitals.
		leave()
		enter_entrance()
	if _holding:
		_jump_pressed = _jump_pressed or Input.is_action_just_pressed("Jump")
		_jump_released = _jump_released or Input.is_action_just_released("Jump")
		_dash_pressed = _dash_pressed or Input.is_action_just_pressed("Action")

func _process(_delta: float) -> void:
	# Keep the existing SaveManager payload current during an active descent too.
	if is_active() and game.abyss_room_state == _state:
		_capture_vitals()

## Future host calls this on leaving. It can keep this node or free it afterward.
func leave() -> void:
	_return_pending = false
	flesh_hud.unbind()
	abyss_map.close_map()
	exploration.leave()
	_serial += 1
	_capture_vitals()
	_active = false
	_starting = false
	_holding = false
	_jump_pressed = false
	_jump_released = false
	_dash_pressed = false
	interactions.set_enabled(false)
	player.set_physics_process(false)
	player.reset_movement()
	camera.set_physics_process(false)
	camera.enabled = false
	stream.active = false
	stream.clear_rooms()
	_set_visibility(false)
	_restore_presentation()

func _set_visibility(show_runtime: bool) -> void:
	visible = show_runtime
	$BackgroundCanvas.visible = show_runtime
	$HealthCanvas.visible = show_runtime
	flesh_hud.visible = show_runtime

func fail_startup(message: String) -> void:
	last_error = message
	leave()
	$StartupStatusCanvas/Panel/Message.text = "Unable to enter the abyss\n\n" + message
	$StartupStatusCanvas.visible = true
	push_error(message)
	startup_failed.emit(message)

func get_player_vitals() -> Dictionary:
	return {"health":player.health.current_health,"base_max_health":player.health.base_max_health,
		"temporary_max_health_bonus":player.health.temporary_max_health_bonus,
		"stamina":player.stamina.current_stamina,"max_stamina":player.stamina.max_stamina,
		"stamina_delay":player.stamina.regeneration_delay_remaining}

func _capture_vitals() -> void:
	if _vitals_initialized and _state != null and is_instance_valid(player) and is_instance_valid(player.health):
		_state.player_vitals = get_player_vitals()

func _restore_vitals(state: AbyssRoomState) -> void:
	if _vitals_initialized:
		return
	var values := state.player_vitals
	if values.is_empty():
		values = {"health":game.health,"stamina":game.stamina}
	player.health.base_max_health = int(values.get("base_max_health",player.health.base_max_health))
	player.health.temporary_max_health_bonus = int(values.get("temporary_max_health_bonus",0))
	player.health.current_health = clampi(int(values.health),0,player.health.max_health)
	player.health.health_changed.emit(player.health.current_health,player.health.max_health)
	player.stamina.max_stamina = float(values.get("max_stamina",player.stamina.max_stamina))
	player.stamina.current_stamina = clampf(float(values.stamina),0.0,player.stamina.max_stamina)
	player.stamina.regeneration_delay_remaining = float(values.get("stamina_delay",0.0))
	player.stamina.stamina_changed.emit(player.stamina.current_stamina,player.stamina.max_stamina)
	_vitals_initialized = true

func _apply_presentation() -> void:
	if not apply_pixel_presentation or not _saved_window.is_empty():
		return
	var window := get_window()
	for key in ["content_scale_size","content_scale_mode","content_scale_aspect","content_scale_stretch","size","canvas_item_default_texture_filter"]:
		_saved_window[key] = window.get(key)
	window.content_scale_size = viewport_pixels
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	window.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if get_tree().current_scene == self:
		window.size = standalone_window_pixels

func _restore_presentation() -> void:
	if not _saved_window.is_empty():
		var window := get_window()
		for key in _saved_window:
			window.set(key,_saved_window[key])
		_saved_window.clear()

func _exit_tree() -> void:
	_serial += 1
	_capture_vitals()
	_restore_presentation()

func checkpoint_primary_available(request: AbyssSpecialSpawnRequest) -> bool:
	if request == null or request.progression != stream.specials or request.kind != &"checkpoint": return false
	var active: bool = stream.specials.state.checkpoints.get(request.definition.id,{}).get("activated",false)
	return not active or (player.health.current_health < player.health.max_health and _state.exploration.checkpoint_heal_available(stream.specials.world,request.definition.id))

func activate_or_heal_checkpoint(request: AbyssSpecialSpawnRequest) -> String:
	if not interactions.actions_allowed() or not checkpoint_primary_available(request): return ""
	var activated := request.activate()
	var healed := 0
	if player.health.current_health < player.health.max_health and _state.exploration.use_checkpoint_heal(stream.specials.world,request.definition.id):
		healed = player.health.heal(2)
	if activated: return "Checkpoint activated — restored %d HP" % healed
	return "Restored %d HP" % healed if healed > 0 else ""

func can_safe_return() -> bool:
	return is_active() and not _return_pending and not _holding and not get_tree().paused 		and game.abyss_room_state == _state and interactions.actions_allowed()

func request_safe_return(source: InteractionTarget) -> bool:
	if not can_safe_return() or not source.can_interact_for_action(player,InteractionTarget.Channel.TRAVEL): return false
	var origin := player.get_node("CollisionShape2D") as Node2D
	if origin.global_position.distance_to(source.global_position) > interactions.interaction_radius: return false
	_return_pending = true # Claim before deferring: two sources cannot extract twice.
	interactions.set_enabled(false)
	player.set_physics_process(false)
	_complete_safe_return.call_deferred(_serial)
	return true

func _complete_safe_return(token: int) -> void:
	if token != _serial or not is_active() or not _return_pending: return
	if game.abyss_room_state != _state or player.damage.is_action_locked():
		_return_pending = false
		interactions.set_enabled(not _holding)
		player.set_physics_process(not _holding)
		return
	var tree := get_tree()
	var host := get_parent()
	var standalone := not host.has_method("change_scene")
	var host_scene: PackedScene
	if standalone: host_scene = load("res://Scenes/Main/main.tscn") as PackedScene
	var amount: int = game.return_abyss_descent(stream.specials.world)
	game.health = player.health.current_health
	game.stamina = int(player.stamina.current_stamina)
	game.return_to_stairs = true
	leave() # Capture exact vitals and restore local presentation before showing village.
	returned_to_village.emit(amount)
	if standalone:
		host = host_scene.instantiate()
		tree.root.add_child(host)
		tree.current_scene = host
		host.change_scene("res://Scenes/Village/House/house.tscn")
		queue_free()
	else:
		host.change_scene("res://Scenes/Village/House/house.tscn")
