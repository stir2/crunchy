extends Node2D
## Streaming/lifecycle adapter. Enemy scripts and their movement remain untouched.
const POOL = preload("res://Scenes/Underground/Enemies/default_enemy_pool.tres")
const DROP = preload("res://Scenes/Underground/Enemies/flesh_drop.tscn")
@export var enemy_pool: AbyssEnemyPool = POOL
@export_range(0, 20, 1) var max_enemies_per_room: int = 3
@export_range(0.0, 4.0, 0.25) var pursuit_rooms: float = 1.0
@export_range(0.0, 10.0, 0.25) var disengage_seconds: float = 2.0
@export_range(1.0, 4.0, 0.25) var active_radius_rooms: float = 1.5
var records: Dictionary = {}
var actors: Dictionary = {}
var drops: Dictionary = {}
var _homes: Dictionary = {}
var _away: Dictionary = {}
var _returning: Dictionary = {}
var _state: AbyssRoomState
var _world: String = ""
var _day: int = -1
var _snapshot_time: float = 0.0
var _projectiles: Array[Node2D] = []
@onready var runtime: AbyssRuntime = get_parent()
@onready var stream: AbyssRoomStreamer = get_parent().get_node("StreamingController")

func _ready() -> void:
	# Streamer (-100) settles/guards terrain first; suspend before AI takes a step.
	process_physics_priority = -50
	stream.room_loaded.connect(_room_ready)
	stream.room_unloaded.connect(_room_unloaded)
	child_entered_tree.connect(func(child: Node): _track_projectile.call_deferred(child))

func _track_projectile(child: Node) -> void:
	if is_instance_valid(child) and child.is_in_group("enemy_projectiles"):
		_projectiles.append(child)

func identity(coords: Vector2i, marker: StringName) -> String:
	return JSON.stringify(["abyss_enemy", _world, coords.x, coords.y, String(marker)])

func _bind() -> void:
	if _state == stream.mutations and _day == stream.mutations.current_day and _world == stream.specials.world: return
	clear_population()
	_state = stream.mutations
	_day = _state.current_day
	_world = stream.specials.world
	records.clear()
	# Use the existing string-valued marker store; its save validation is unchanged.
	for key: String in _state.markers.keys():
		if not key.begins_with('["abyss_enemy",'): continue
		var parts: Variant = JSON.parse_string(key)
		if not parts is Array or parts.size() != 5 or parts[0] != "abyss_enemy" or parts[1] != _world: continue
		var value: Variant = JSON.parse_string(_state.markers[key])
		if not value is Dictionary or int(value.get("day", -1)) != _day:
			_state.markers.erase(key) # This namespace alone resets with the day.
			continue
		records[key] = value

func _save(id: String) -> void:
	_state.markers[id] = JSON.stringify(records[id])

func _room_ready(coords: Vector2i) -> void:
	_bind()
	register_room(stream.rooms[coords])
	_restore_ready()

func register_room(room: AbyssAuthoredRoom) -> void:
	var level := stream.specials.level_at(room.construction_requirements.global_coords)
	var candidates: Array[EnemySpawnRequest] = []
	for request in room.spawn_requests:
		if request is EnemySpawnRequest and request.should_spawn(): candidates.append(request)
	candidates.sort_custom(func(a: EnemySpawnRequest, b: EnemySpawnRequest) -> bool:
		var ia := identity(a.room_coords, a.marker_id)
		var ib := identity(b.room_coords, b.marker_id)
		var ra := AbyssEnemyPool.roll(ia, "marker_subset")
		var rb := AbyssEnemyPool.roll(ib, "marker_subset")
		return ra < rb if ra != rb else ia < ib)
	for index in range(mini(max_enemies_per_room, candidates.size())):
		var request := candidates[index]
		var id := identity(request.room_coords, request.marker_id)
		if records.has(id): continue
		var selected := enemy_pool.select(level, id)
		if selected == null: continue
		var home := runtime.loaded_rooms.to_local(request.world_position)
		records[id] = {"day": _day, "type": String(selected.enemy_id), "level": level,
			"room_x": request.room_coords.x, "room_y": request.room_coords.y,
			"home_x": home.x, "home_y": home.y, "x": home.x, "y": home.y,
			"health": -1, "defeated": false, "reward": 0, "drop_collected": false}
		_save(id)

func _point(record: Dictionary) -> Vector2:
	return runtime.loaded_rooms.to_global(Vector2(record.x, record.y))

func _restore_ready() -> void:
	for id: String in records:
		var entry: Dictionary = records[id]
		if not stream.room_ready(stream.world_to_room(_point(entry))): continue
		if entry.defeated:
			if not entry.drop_collected and int(entry.reward) > 0: _spawn_drop(id)
		elif not actors.has(id):
			_spawn_actor(id)

func _spawn_actor(id: String) -> void:
	var entry: Dictionary = records[id]
	var selected := enemy_pool.find(entry.type)
	if selected == null: return # Keep state if a type is temporarily removed.
	var actor := selected.scene.instantiate() as CharacterBody2D
	actor.set("target", runtime.player)
	actor.set("abyss_level", int(entry.level))
	# Both enemy families gate automatic awards on this existing public setting.
	var reward := int(actor.get("flesh_reward"))
	actor.set("flesh_reward", 0)
	actor.set("flesh_pickup_id", drop_id(id))
	actor.position = to_local(_point(entry))
	add_child(actor)
	# Some AI ready methods offset the body; persisted positions are post-ready.
	if int(entry.health) >= 0: actor.global_position = _point(entry)
	var hurtbox := actor.get_node("Damageable") as CombatDamageable
	if int(entry.health) >= 0:
		hurtbox.health_component.reset_health(int(entry.health))
		actor.set("health", hurtbox.health)
		actor.emit_signal("health_changed", hurtbox.health, hurtbox.max_health)
	else:
		entry.reward = reward
	actors[id] = actor
	var home := Node2D.new()
	home.position = to_local(runtime.loaded_rooms.to_global(Vector2(entry.home_x, entry.home_y)))
	add_child(home)
	_homes[id] = home
	actor.connect("died", _enemy_died.bind(id))
	actor.connect("health_changed", _health_changed.bind(id))
	_snapshot(id)
	_set_simulation(actor, false)

func drop_id(id: String) -> String:
	return "%s/day/%d/flesh" % [id, _day]

func _health_changed(_health: int, _maximum: int, id: String) -> void:
	_snapshot(id)

func _snapshot(id: String) -> void:
	if not actors.has(id) or not is_instance_valid(actors[id]): return
	var actor: CharacterBody2D = actors[id]
	var point := runtime.loaded_rooms.to_local(actor.global_position)
	var entry: Dictionary = records[id]
	entry.x = point.x
	entry.y = point.y
	entry.health = actor.get_node("Damageable").health
	_save(id)

func _enemy_died(id: String) -> void:
	if not records.has(id) or records[id].defeated: return
	_snapshot(id)
	records[id].defeated = true
	records[id].health = 0
	_save(id) # Commit death/drop before any collection signal can run.
	actors.erase(id) # Keep the enemy's own death animation alive until it frees itself.
	_release_home(id)
	if int(records[id].reward) > 0: _spawn_drop(id)

func _spawn_drop(id: String) -> void:
	if drops.has(id): return
	var drop := DROP.instantiate() as Area2D
	drop.position = to_local(_point(records[id]))
	add_child(drop)
	drops[id] = drop
	drop.touched.connect(_touch_drop.bind(id))

func _touch_drop(id: String) -> void:
	if not collect_drop(id) and drops.has(id): drops[id].set("_collecting", false)

func collect_drop(id: String) -> bool:
	if not records.has(id) or not records[id].defeated or records[id].drop_collected: return false
	if runtime.player.damage.is_dead() or not runtime.is_active() or not runtime.player.is_physics_processing(): return false
	var entry: Dictionary = records[id]
	# Mark first, then emit currency/HUD signals; reentrant calls cannot pay twice.
	entry.drop_collected = true
	_save(id)
	var collected: bool = runtime.game.collect_descent_flesh(_world, int(entry.reward), _point(entry), drop_id(id))
	if drops.has(id):
		drops[id].queue_free()
		drops.erase(id)
	return collected

func _set_simulation(actor: CharacterBody2D, enabled: bool) -> void:
	actor.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	actor.visible = enabled or stream.room_ready(stream.world_to_room(actor.global_position))
	if not enabled: actor.get_node("RushHitbox").active = false

func _physics_process(delta: float) -> void:
	if _state == null: return
	if not stream.active:
		clear_population()
		return
	for projectile in _projectiles.duplicate():
		if not is_instance_valid(projectile):
			_projectiles.erase(projectile)
			continue
		var destination: Vector2 = projectile.global_position + projectile.get("travel_velocity") * delta
		projectile.set_physics_process(runtime.is_active() and runtime.player.is_physics_processing() and stream.is_rect_ready(Rect2(projectile.global_position, Vector2.ONE).expand(destination).grow(16)))
	_snapshot_time += delta
	var save_positions := _snapshot_time >= 0.25
	if save_positions: _snapshot_time = 0.0
	for id: String in actors.keys():
		var actor: CharacterBody2D = actors[id]
		if not is_instance_valid(actor):
			actors.erase(id)
			_release_home(id)
			continue
		var ready := stream.is_rect_ready(Rect2(actor.global_position - Vector2(32, 56), Vector2(64, 80)).expand(actor.global_position + actor.velocity * delta).grow(32))
		var distance := (actor.global_position - runtime.player.global_position) / stream.room_pixels
		var active := runtime.is_active() and runtime.player.is_physics_processing() and ready and distance.length() <= active_radius_rooms
		_set_simulation(actor, active)
		if active: _update_pursuit(id, actor, delta)
		if save_positions: _snapshot(id)
		if not ready and distance.length() > active_radius_rooms: _retire(id)
	for id: String in drops.keys():
		var drop: Area2D = drops[id]
		if not stream.room_ready(stream.world_to_room(drop.global_position)):
			drop.queue_free()
			drops.erase(id)
		else:
			drop.set_physics_process(runtime.is_active() and runtime.player.is_physics_processing())

func _update_pursuit(id: String, actor: CharacterBody2D, delta: float) -> void:
	var home: Node2D = _homes[id]
	var player_distance := ((runtime.player.global_position - home.global_position) / stream.room_pixels).length()
	var actor_distance := ((actor.global_position - home.global_position) / stream.room_pixels).length()
	_away[id] = float(_away.get(id, 0.0)) + delta if player_distance > pursuit_rooms + 0.5 else 0.0
	if actor_distance > pursuit_rooms + 0.5 or float(_away[id]) >= disengage_seconds:
		_returning[id] = true
	if _returning.get(id, false):
		# Retarget only: the teammate's navigation still decides how to get home.
		actor.set("target", home if actor.global_position.distance_to(home.global_position) > 40.0 else null)
		actor.get_node("RushHitbox").active = false
		if actor_distance < 0.15 and player_distance < pursuit_rooms:
			_returning.erase(id)
			_away[id] = 0.0
			actor.set("target", runtime.player)

func _room_unloaded(_coords: Vector2i) -> void:
	# Actor lifetime follows its current position, never its origin room node.
	for id: String in actors: _snapshot(id)

func _release_home(id: String) -> void:
	if _homes.has(id):
		_homes[id].queue_free()
		_homes.erase(id)
	_away.erase(id)
	_returning.erase(id)

func _retire(id: String) -> void:
	_snapshot(id)
	actors[id].queue_free()
	actors.erase(id)
	_release_home(id)

func clear_population() -> void:
	for id: String in actors.keys(): _retire(id)
	for drop: Node in drops.values(): drop.queue_free()
	drops.clear()
	# Includes death animations/projectiles left by actors outside the live table.
	for child in get_children():
		if not child.is_queued_for_deletion(): child.queue_free()

func _exit_tree() -> void:
	for id: String in actors: _snapshot(id)
