class_name PlayerCombatController
extends Node
## Animation owns the attack clock. Player calls the two physics hooks in order.
enum AttackState { IDLE, WINDUP, ACTIVE, RECOVERY }
signal attack_started(swing_id: int)
signal attack_finished(interrupted: bool)
signal phase_changed(phase: AttackState)
signal hit_confirmed(target: CombatDamageable, hit: CombatHit)
signal hitstop_started(ticks: int)
signal breakable_hit_confirmed(dashing: bool)
signal swing_freeze_started(ticks: int)

@export var actions_enabled: bool = true
## Mouse aim and movement are independent; facing commits only at swing start.
@export var mouse_aim_attacks: bool = true
@export_group("Swing")
@export_range(0, 16, 1) var active_start_frame: int = 3
@export_range(0, 16, 1) var active_end_frame: int = 5
## Brief anticipation hold on the last windup pose, even when the swing misses.
@export_range(0, 15, 1) var swing_freeze_frames: int = 4
## Extra horizontal target speed after the swing freeze. Zero disables it.
@export_range(0.0, 500.0, 5.0) var swing_speed_boost: float = 80.0
@export_range(0, 60, 1) var swing_speed_boost_frames: int = 12
## One forward impulse as damage frames begin, only with matching direction held.
## Extra speed above the attack's movement target; zero disables the burst.
@export_range(0.0, 500.0, 5.0) var swing_burst_speed: float = 100.0
## Number of recovery anismation frames that must finish before dash-canceling.
## Zero allows immediate recovery cancellation. This does not count physics ticks.
@export_range(0, 17, 1) var dash_recovery_lock_frames: int = 2
@export var repeat_while_held: bool = true
## Earliest zero-indexed animation frame where a click/hold can restart a swing.
## Recovery is always required; 17 disables cancellation for a 17-frame slash.
@export_range(0, 17, 1) var attack_cancel_start_frame: int = 8
@export_range(0.0, 1.0, 0.05) var attack_movement_speed_multiplier: float = 0.25
## Scales jump takesoff velocity for jumps started during a swing.
@export_range(0.0, 1.0, 0.05) var attack_jump_multiplier: float = 0.75
@export_range(0, 100, 1) var attack_damage: int = 1
@export_group("Hitbox")
@export_range(1.0, 100.0, 1.0) var attack_reach: float = 40.0
@export_range(1.0, 100.0, 1.0) var hitbox_width: float = 48.0
@export_range(1.0, 100.0, 1.0) var hitbox_height: float = 42.0
@export_group("Impact")
@export var attack_knockback: Vector2 = Vector2(170, -70)
@export_range(0, 15, 1) var hitstop_frames: int = 8
@export_range(0, 100, 1) var dash_breakable_damage: int = 3
@export_range(0, 15, 1) var dash_breakable_hitstop_frames: int = 8
@export var dash_enemy_knockback: Vector2 = Vector2(850, -180)

var _breakable_rooms: Array[AbyssAuthoredRoom] = []
var _swing_breakable_hits: Dictionary = {}
var _dash_breakable_hits: Dictionary = {}
var _dash_enemy_hits: Dictionary[int, bool] = {}
var _motion_origin: Vector2

var attack_state: AttackState = AttackState.IDLE
var locked_facing: int = 1
var swing_id: int = 0
var buffered_dash: bool = false
var _hit_targets: Dictionary[int, bool] = {}
var _attack_requested: bool = false
var _ignore_attack_until_release: bool = false
var _hitstop_used: bool = false
var _hitstop_until_tick: int = -1
var _paused_for_freeze: bool = false
var _swing_freeze_used: bool = false
var _swing_freeze_ticks_left: int = 0
var _paused_for_swing: bool = false
var _swing_speed_boost_ticks_left: int = 0
var _swing_burst_used: bool = false
var _buffered_jump: bool = false
var _jump_released: bool = false
@onready var player: CharacterBody2D = get_parent() as CharacterBody2D
@onready var sprite: AnimatedSprite2D = player.get_node("Visuals/AnimatedSprite2D")
@onready var pivot: Node2D = player.get_node("AttackPivot")
@onready var hitbox: Area2D = pivot.get_node("AttackHitbox")
@onready var hit_shape: CollisionShape2D = hitbox.get_node("CollisionShape2D")

func _ready() -> void:
	_ignore_attack_until_release = Input.is_action_pressed("Attack")
	configure_hitbox()
	_discover_breakable_rooms(get_tree().root)
	get_tree().node_added.connect(_register_breakable_room)
	get_tree().node_removed.connect(_remove_breakable_room)
	sprite.frame_changed.connect(_sync_phase)
	sprite.animation_finished.connect(_on_animation_finished)
	player.movement_reset.connect(interrupt)
	player.movement_state_changed.connect(_on_movement_state_changed)

func is_attacking() -> bool:
	return attack_state != AttackState.IDLE

func movement_multiplier() -> float:
	return attack_movement_speed_multiplier if is_attacking() else 1.0

func jump_multiplier() -> float:
	return attack_jump_multiplier if is_attacking() else 1.0

func movement_speed_bonus() -> float:
	return swing_speed_boost if _swing_speed_boost_ticks_left > 0 else 0.0

func consume_swing_burst() -> float:
	if attack_state != AttackState.ACTIVE or _swing_burst_used or is_hitstopped() or is_swing_frozen():
		return 0.0
	_swing_burst_used = true
	var direction := Input.get_axis("Move Left","Move Right")
	return swing_burst_speed if direction*locked_facing > 0.0 else 0.0

func is_hitstopped() -> bool:
	return Engine.get_physics_frames() <= _hitstop_until_tick

func is_swing_frozen() -> bool:
	return _paused_for_swing

## Returns true when this whole player physics tick must remain frozen.
func begin_physics_tick() -> bool:
	_motion_origin = player.global_position
	if not Input.is_action_pressed("Attack"):
		_ignore_attack_until_release = false
	_attack_requested = Input.is_action_just_pressed("Attack") and not _ignore_attack_until_release
	if not actions_enabled:
		interrupt()
		return false
	if not Input.is_action_pressed("Action"):
		buffered_dash = false # Releasing cancels a charge still waiting on recovery.
	if is_attacking() and Input.is_action_just_pressed("Action"):
		buffered_dash = true
	# Repetition waits for recovery and gives a pending dash priority. Holding
	# Attack must not immediately cancel the dash it just buffered into.
	if repeat_while_held and Input.is_action_pressed("Attack") and not _ignore_attack_until_release:
		if player.movement_state == Player.MovementState.NORMAL and not buffered_dash:
			_attack_requested = true
	var swing_freeze_tick := _paused_for_swing and _swing_freeze_ticks_left > 0
	if swing_freeze_tick:
		_swing_freeze_ticks_left -= 1
	if is_hitstopped() or swing_freeze_tick:
		_buffered_jump = _buffered_jump or Input.is_action_just_pressed("Jump")
		_jump_released = _jump_released or Input.is_action_just_released("Jump")
		return true
	if _paused_for_swing and swing_speed_boost > 0.0:
		_swing_speed_boost_ticks_left = swing_speed_boost_frames
	_paused_for_swing = false
	if _paused_for_freeze:
		_paused_for_freeze = false
		sprite.play() # Native pause/play preserves frame_progress.
		_sync_phase()
		player.resume_combat_jump_input(_buffered_jump, _jump_released)
		_buffered_jump = false
		_jump_released = false
	return false

func try_start_attack() -> bool:
	if not _attack_requested or not actions_enabled or player.damage.is_action_locked():
		return false
	if player.is_jump_charging():
		return false
	if is_attacking():
		if not can_attack_cancel():
			return false
		_finish(true)
	if player.movement_state == Player.MovementState.DASH_CHARGING or player.movement_state == Player.MovementState.DASHING:
		player.cancel_dash_for_attack()
	elif player.movement_state != Player.MovementState.NORMAL:
		return false
	_attack_requested = false
	_ignore_attack_until_release = not repeat_while_held
	locked_facing = attack_facing()
	swing_id += 1
	_hit_targets.clear()
	_swing_breakable_hits.clear()
	_hitstop_used = false
	_swing_freeze_used = false
	_swing_freeze_ticks_left = 0
	_paused_for_swing = false
	_swing_speed_boost_ticks_left = 0
	_swing_burst_used = false
	buffered_dash = false
	configure_hitbox()
	pivot.scale.x = absf(pivot.scale.x) * locked_facing
	_set_phase(AttackState.WINDUP)
	sprite.play_attack(locked_facing)
	_sync_phase()
	attack_started.emit(swing_id)
	return true

func attack_facing() -> int:
	if mouse_aim_attacks:
		var offset_x := player.get_global_mouse_position().x - player.global_position.x
		if absf(offset_x) > 8.0:
			return 1 if offset_x > 0.0 else -1
	return player.facing_direction

func consume_buffered_dash() -> bool:
	if is_attacking() and not can_dash_cancel():
		return false
	var request := buffered_dash and actions_enabled and Input.is_action_pressed("Action")
	buffered_dash = false # Eligible or not, it gets exactly one attempt.
	if request and is_attacking():
		if not player.can_start_dash(true):
			if player.can_start_dash(true, true):
				player.stamina.spend(player.stamina.dash_cost) # Rejected cost signals HUD feedback.
			return false # An ineligible dash must not cut off recovery.
		_finish(true)
	return request

func can_dash_cancel() -> bool:
	if attack_state != AttackState.RECOVERY or not sprite.is_attack_animation():
		return false
	var count := sprite.sprite_frames.get_frame_count(sprite.animation)
	var first_active := clampi(active_start_frame,0,count-1)
	var first_recovery := clampi(active_end_frame,first_active,count-1)+1
	return (
		sprite.frame-first_recovery >= dash_recovery_lock_frames
		and not is_hitstopped() and not is_swing_frozen()
	)

func can_attack_cancel() -> bool:
	return (
		attack_state == AttackState.RECOVERY and sprite.frame >= attack_cancel_start_frame
		and not is_hitstopped() and not is_swing_frozen()
	)

func configure_hitbox() -> void:
	var rectangle := hit_shape.shape as RectangleShape2D
	if rectangle == null:
		rectangle = RectangleShape2D.new()
		hit_shape.shape = rectangle
	rectangle.size = Vector2(hitbox_width, hitbox_height)
	# Body forward edge is 15px from the feet origin. Rectangle overlaps it 8px.
	hitbox.position = Vector2(15.0 + attack_reach - hitbox_width * 0.5, 0.0)

func _sync_phase() -> void:
	if not is_attacking() or not sprite.is_attack_animation():
		return
	var count := sprite.sprite_frames.get_frame_count(sprite.animation)
	var first := clampi(active_start_frame, 0, count - 1)
	var last := clampi(active_end_frame, first, count - 1)
	if not _swing_freeze_used and sprite.frame >= maxi(0, first - 1):
		_swing_freeze_used = true
		if swing_freeze_frames > 0:
			_swing_freeze_ticks_left = swing_freeze_frames
			_paused_for_swing = true
			_paused_for_freeze = true
			sprite.pause()
			swing_freeze_started.emit(swing_freeze_frames)
	if is_swing_frozen():
		_set_phase(AttackState.WINDUP) # No damage during the anticipation hold.
		return
	_set_phase(AttackState.WINDUP if sprite.frame < first else AttackState.ACTIVE if sprite.frame <= last else AttackState.RECOVERY)

func _set_phase(next: AttackState) -> void:
	if attack_state == next:
		return
	attack_state = next
	var active := next == AttackState.ACTIVE
	# Callbacks may run during a physics signal: defer server mutations safely.
	hit_shape.set_deferred("disabled", not active)
	hitbox.set_deferred("monitoring", active)
	hitbox.set_deferred("collision_layer", 16 if active else 0)
	hitbox.set_deferred("collision_mask", 32 if active else 0)
	phase_changed.emit(next)

func end_physics_tick() -> void:
	_swing_speed_boost_ticks_left = maxi(0, _swing_speed_boost_ticks_left - 1)
	if attack_state != AttackState.ACTIVE or is_hitstopped() or is_swing_frozen():
		return
	# Query the configured shape directly: activation catches pre-existing overlaps,
	# without depending on Area2D's delayed overlap list or spawning damage nodes.
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = hit_shape.shape
	query.transform = hitbox.global_transform * hit_shape.transform
	_damage_swing_breakables(query.transform)
	query.collision_mask = 32
	query.collide_with_bodies = false
	query.collide_with_areas = true
	for overlap in player.get_world_2d().direct_space_state.intersect_shape(query, 64):
		var target := overlap.collider as CombatDamageable
		if target == null or not is_instance_valid(target.damage_owner()) or target.damage_owner() == player:
			continue
		var identity := target.damage_owner().get_instance_id()
		if _hit_targets.has(identity):
			continue
		_hit_targets[identity] = true
		var hit := CombatHit.new()
		hit.amount = attack_damage
		hit.source = player
		hit.direction = Vector2(locked_facing, 0)
		hit.knockback = Vector2(absf(attack_knockback.x) * locked_facing, attack_knockback.y)
		hit.world_position = hitbox.global_position
		hit.swing_id = swing_id
		if not target.receive_hit(hit):
			_hit_targets.erase(identity)
			continue
		if not _hitstop_used:
			_start_hitstop()
		if is_hitstopped():
			target.begin_hitstop(maxi(0, _hitstop_until_tick - Engine.get_physics_frames()))
		hit_confirmed.emit(target, hit) # Hook for future sounds and impact particles.

func _start_hitstop(frames: int = -1) -> void:
	_hitstop_used = true
	var duration := hitstop_frames if frames < 0 else frames
	if duration <= 0:
		return
	_hitstop_until_tick = Engine.get_physics_frames() + duration
	_paused_for_freeze = true
	sprite.pause()
	hitstop_started.emit(duration)

func _on_animation_finished() -> void:
	if is_attacking() and sprite.is_attack_animation():
		_finish(false)

func _on_movement_state_changed(state: int) -> void:
	if state != Player.MovementState.NORMAL:
		_swing_speed_boost_ticks_left = 0 # Never alter dash speed or recovery.
	if is_attacking() and state != Player.MovementState.NORMAL:
		interrupt() # Defensive hook for future forced state changes.

## Damage/death code can call this; movement_reset already does so automatically.
func interrupt() -> void:
	_swing_burst_used = false
	buffered_dash = false
	_attack_requested = false
	_buffered_jump = false
	_jump_released = false
	_hitstop_until_tick = -1
	_paused_for_freeze = false
	_swing_freeze_ticks_left = 0
	_paused_for_swing = false
	_swing_freeze_used = false
	_swing_speed_boost_ticks_left = 0
	_ignore_attack_until_release = Input.is_action_pressed("Attack")
	_hit_targets.clear()
	if is_attacking():
		_finish(true)

func _finish(interrupted: bool) -> void:
	_set_phase(AttackState.IDLE)
	player.update_facing_direction()
	sprite.finish_attack()
	attack_finished.emit(interrupted)

func _discover_breakable_rooms(node: Node) -> void:
	_register_breakable_room(node)
	for child in node.get_children():
		_discover_breakable_rooms(child)

func _register_breakable_room(node: Node) -> void:
	if node is AbyssAuthoredRoom and not _breakable_rooms.has(node):
		_breakable_rooms.append(node)

func _remove_breakable_room(node: Node) -> void:
	if node is AbyssAuthoredRoom:
		_breakable_rooms.erase(node)

func _damage_swing_breakables(hit_transform: Transform2D) -> void:
	var rectangle := hit_shape.shape as RectangleShape2D
	if rectangle == null:
		return
	# Cover the whole swing from its origin to the existing outer edge. A narrow
	# attack rectangle alone can overshoot thin walls when standing against them.
	# This changes only breakable detection, not enemy hitboxes or maximum reach.
	var half := rectangle.size*0.5
	var origin := hit_transform.affine_inverse()*pivot.global_position
	var near_x := minf(-half.x,origin.x)
	var polygon := PackedVector2Array()
	for corner in [Vector2(near_x,-half.y),Vector2(half.x,-half.y),Vector2(half.x,half.y),Vector2(near_x,half.y)]:
		polygon.append(hit_transform*corner)
	for room in _breakable_rooms:
		if room.breakables != null and room.breakables.damage_in_polygon(polygon,attack_damage,_swing_breakable_hits):
			breakable_hit_confirmed.emit(false)
			if not _hitstop_used:
				_start_hitstop()

func begin_breakable_dash() -> void:
	_dash_breakable_hits.clear()
	_dash_enemy_hits.clear()
	_motion_origin = player.global_position

func connect_enemy_dash() -> void:
	var body := player.get_node("CollisionShape2D") as CollisionShape2D
	var rectangle := body.shape as RectangleShape2D
	if rectangle == null or dash_enemy_knockback == Vector2.ZERO: return
	# Sweep the actual body footprint across this tick's completed movement.
	var travel := player.global_position - _motion_origin
	var shape := RectangleShape2D.new()
	shape.size = rectangle.size + travel.abs()
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, (_motion_origin + player.global_position)*0.5 + body.position)
	query.collision_mask = 32
	query.collide_with_bodies = false
	query.collide_with_areas = true
	var connected := false
	for overlap in player.get_world_2d().direct_space_state.intersect_shape(query,64):
		var target := overlap.collider as CombatDamageable
		if target == null: continue
		var enemy := target.damage_owner()
		if not is_instance_valid(enemy) or not enemy.is_in_group("enemies"): continue
		var identity := enemy.get_instance_id()
		if _dash_enemy_hits.has(identity): continue
		var hit := CombatHit.new()
		hit.amount = 0
		hit.source = player
		hit.direction = Vector2(player.dash_direction,0)
		hit.knockback = Vector2(absf(dash_enemy_knockback.x)*player.dash_direction,dash_enemy_knockback.y)
		hit.world_position = body.global_position
		if not target.receive_knockback(hit): continue
		_dash_enemy_hits[identity] = true
		if not connected:
			_start_hitstop()
			connected = true
		target.begin_hitstop(maxi(0,_hitstop_until_tick - Engine.get_physics_frames()))
		hit_confirmed.emit(target,hit)

func connect_breakable_dash() -> bool:
	var connected := false
	for index in range(player.get_slide_collision_count()):
		var collision := player.get_slide_collision(index)
		var layer := collision.get_collider() as TileMapLayer
		if layer == null or layer.name != &"BreakableWalls":
			continue
		var room := layer.get_parent() as AbyssAuthoredRoom
		if room == null or room.breakables == null:
			continue
		var point := collision.get_position() - collision.get_normal()*2.0
		connected = room.breakables.damage_at_once(point,dash_breakable_damage,_dash_breakable_hits) or connected
	if connected:
		_start_hitstop(dash_breakable_hitstop_frames)
		breakable_hit_confirmed.emit(true)
	return connected

## Preserve frame-based deadlines across an explicit gameplay pause.
func compensate_paused_ticks(start_tick: int, ticks: int) -> void:
	if _hitstop_until_tick >= start_tick:
		_hitstop_until_tick += ticks
