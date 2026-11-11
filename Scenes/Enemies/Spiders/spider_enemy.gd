extends "res://Scenes/Enemies/Shared/enemy_base.gd"
## The web shooter holds its ground. The rusher follows surfaces and pounces.
const PROJECTILE = preload("res://Scenes/Enemies/Spiders/web_projectile.gd")
const RELEASE_FRAME: int = 8
const SURFACE_NAVIGATION = preload("res://Scenes/Enemies/Spiders/spider_surface_navigation.gd")
enum SpiderKind { WEB_SHOOTER, CHASER }
@export var spider_kind: SpiderKind = SpiderKind.WEB_SHOOTER
@export var projectile_speed: float = 180.0
@export var max_room_projectiles: int = 4
@export var max_own_projectiles: int = 2
@export var wall_crawl_speed: float = 85.0
var _navigator := SURFACE_NAVIGATION.new()
var _surface_path: Array[Dictionary] = []
var _surface_normal := Vector2.UP
var _route_timer: float = 0.0
var _attached: bool = false
var _jump_timer: float = 0.0
var _next_walk_ms: int = 0


func _ready() -> void:
	enemy_color = Color.WHITE
	attack_range = 420.0
	target_height_range = 160.0
	windup_time = 0.5
	recovery_time = 1.0
	track_during_windup = true
	base_health = 2
	chase_speed = 85.0
	if spider_kind == SpiderKind.CHASER:
		chase_speed = 145.0
		attack_range = 72.0
		target_height_range = 80.0
		windup_time = 0.2
		rush_time = 0.35
		rush_speed = 220.0
		recovery_time = 0.28
		track_during_windup = false
	super._ready()
	sprite.position = Vector2(0, -14)
	sprite.offset = Vector2.ZERO
	_health_bar.position.y = -42
	_health_label.position.y = -58
	sprite.animation_finished.connect(_on_spider_animation_finished)
	sprite.frame_changed.connect(_on_spider_frame_changed)
	_update_animation()
	if spider_kind == SpiderKind.CHASER:
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
		floor_snap_length = 0
		global_position.y -= SURFACE_NAVIGATION.BODY_RADIUS
		var body := $CollisionShape2D as CollisionShape2D
		var circle := CircleShape2D.new()
		circle.radius = SURFACE_NAVIGATION.BODY_RADIUS
		body.shape = circle
		body.position = Vector2.ZERO
		$Damageable.position = Vector2.ZERO
		$RushHitbox.position = Vector2.ZERO
		sprite.position = Vector2(0, -3)


func _physics_process(delta: float) -> void:
	if spider_kind == SpiderKind.WEB_SHOOTER:
		super._physics_process(delta)
		return
	if _dying or damageable.health <= 0:
		return
	if damageable.is_hitstopped():
		_pause_for_hitstop()
		return
	_resume_after_hitstop()
	_route_timer -= delta
	_jump_timer = maxf(0.0, _jump_timer - delta)
	_time_left = maxf(0, _time_left - delta)
	if _hurt_time > 0:
		_hurt_time = maxf(0, _hurt_time - delta)
		velocity += get_gravity() * delta
		move_and_slide()
		_update_surface_labels()
		return
	if not _attached:
		_move_in_air(delta)
		_update_animation()
		_update_surface_labels()
		return
	var nearby := _can_see_target()
	var goal := target.global_position + Vector2(0, -18) if nearby else global_position
	if state == State.WINDUP:
		velocity = Vector2.ZERO
		if not nearby or global_position.distance_to(goal) > 96.0 or not _terrain_ray(global_position, goal).is_empty():
			_recover()
		elif _time_left <= 0:
			_begin_attack()
	elif state == State.RUSH:
		var tangent := Vector2(-_surface_normal.y, _surface_normal.x) * _direction
		velocity = tangent * rush_speed * speed_multiplier
		if _time_left <= 0 or not _has_support(global_position + velocity * delta):
			_recover()
		elif move_and_collide(velocity * delta) != null:
			_recover()
	elif state == State.RECOVER and _time_left > 0:
		velocity = Vector2.ZERO
	else:
		state = State.CHASE if nearby else State.IDLE
		if nearby and global_position.distance_to(goal) <= attack_range and _terrain_ray(global_position, goal).is_empty():
			var tangent := Vector2(-_surface_normal.y, _surface_normal.x)
			_direction = 1 if (goal - global_position).dot(tangent) >= 0 else -1
			_start_windup()
		elif nearby:
			_crawl_toward(goal, delta)
		else:
			velocity = Vector2.ZERO
			_route_timer = 0
	if _attached:
		rotation = _surface_normal.angle() + PI * 0.5
	_update_animation()
	_update_surface_labels()


func _crawl_toward(goal: Vector2, delta: float) -> void:
	if _route_timer <= 0:
		_surface_path = _navigator.find_path(get_world_2d().direct_space_state, global_position, goal)
		_route_timer = 0.45
	var route_end: Vector2 = global_position if _surface_path.is_empty() else _surface_path.back().position
	if (_surface_normal == Vector2.DOWN or route_end.distance_to(goal) > attack_range * 0.75) and _try_surface_leap(goal):
		_move_in_air(delta)
		return
	while not _surface_path.is_empty() and global_position.distance_to(_surface_path[0].position) < 0.2:
		_surface_normal = _surface_path.pop_front().normal
	var speed := (chase_speed if _surface_normal == Vector2.UP else wall_crawl_speed) * speed_multiplier
	var tangent := Vector2(-_surface_normal.y, _surface_normal.x)
	var motion: Vector2
	if not _surface_path.is_empty():
		motion = (Vector2(_surface_path[0].position) - global_position).limit_length(speed * delta)
	else:
		var along_surface := (goal - global_position).dot(tangent)
		motion = tangent * clampf(along_surface, -speed * delta, speed * delta)
		if not _has_support(global_position + motion):
			motion = Vector2.ZERO
			if not _has_support(global_position):
				_attached = false
	if absf(motion.dot(tangent)) > 0.01:
		_direction = signf(motion.dot(tangent))
	velocity = motion / delta
	var collision := move_and_collide(motion) if motion != Vector2.ZERO else null
	if collision != null:
		_surface_normal = collision.get_normal()
		_surface_path.clear()
		_route_timer = 0.1


func _has_support(point: Vector2) -> bool:
	return not _terrain_ray(point, point - _surface_normal * 17.0).is_empty()


func _try_surface_leap(goal: Vector2) -> bool:
	if _jump_timer > 0:
		return false
	var offset := goal - global_position
	if offset.length() < 36.0 or offset.length() > 350.0:
		return false
	var direction := signf(offset.x)
	if _surface_normal == Vector2.UP and offset.y > -28.0 and _has_support(global_position + Vector2(direction * 20.0, 0)):
		return false
	_jump_timer = 0.2
	if _surface_normal == Vector2.DOWN:
		if offset.y > 24.0 and absf(offset.x) < 52.0 and _terrain_ray(global_position, goal).is_empty():
			_launch_leap(Vector2(clampf(offset.x * 2.0, -100.0, 100.0), 35.0))
			return true
		return false
	if offset.dot(_surface_normal) < -4.0 and _surface_normal != Vector2.UP:
		return false
	for x: float in [goal.x, global_position.x + direction * 112.0, global_position.x + direction * 64.0]:
		var hit := _terrain_ray(Vector2(x, goal.y - 12.0), Vector2(x, maxf(goal.y, global_position.y) + 90.0))
		if hit.is_empty() or Vector2(hit.normal).y > -0.5:
			continue
		var destination: Vector2 = hit.position + Vector2.UP * SURFACE_NAVIGATION.CLEARANCE
		if destination.distance_to(goal) + 16.0 >= offset.length():
			continue
		var launch := _plan_leap(destination, 320.0, 185.0)
		if launch != Vector2.ZERO:
			_launch_leap(launch)
			return true
	return false


func _launch_leap(launch: Vector2) -> void:
	_attached = false
	_surface_path.clear()
	_jump_timer = 0.45
	velocity = launch
	if absf(launch.x) > 1.0:
		_direction = signf(launch.x)


func _move_in_air(delta: float) -> void:
	var gravity := get_gravity()
	var motion := (velocity + gravity * delta * 0.5) * delta
	velocity += gravity * delta
	if state == State.RUSH and _time_left <= 0:
		var flight_velocity := velocity
		_recover()
		velocity = flight_velocity
	rotation = lerp_angle(rotation, 0.0, minf(1, delta * 12))
	var collision := move_and_collide(motion)
	if collision != null:
		_surface_normal = collision.get_normal()
		_attached = true
		velocity = Vector2.ZERO
		_route_timer = 0
		rotation = _surface_normal.angle() + PI * 0.5
		if state == State.RUSH:
			_recover()


func _update_surface_labels() -> void:
	_health_bar.rotation = -rotation
	_health_label.rotation = -rotation
	_health_bar.global_position = global_position + Vector2(-16, -35)
	_health_label.global_position = global_position + Vector2(-25, -51)


func _spacing_axis() -> Vector2:
	return Vector2(-_surface_normal.y, _surface_normal.x) if spider_kind == SpiderKind.CHASER else Vector2.RIGHT


func _can_space() -> bool:
	return _attached if spider_kind == SpiderKind.CHASER else super._can_space()


func _terrain_ray(from: Vector2, to: Vector2) -> Dictionary:
	return get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(from, to, 1))


func _can_see_target() -> bool:
	if not is_instance_valid(target):
		return false
	var target_health := target.get_node_or_null("Health") as HealthComponent
	if target_health != null and target_health.is_dead():
		return false
	var goal := target.global_position + Vector2(0, -18)
	if spider_kind == SpiderKind.CHASER:
		return global_position.distance_to(goal) < 1200.0
	return global_position.distance_to(goal) <= detection_range and _support_exit_distance(goal) >= 0


func _support_exit_distance(goal: Vector2) -> float:
	var origin := global_position + Vector2(0, -18)
	var first := _terrain_ray(origin, goal)
	if first.is_empty():
		return 0.0
	var support := _terrain_ray(global_position + Vector2(0, -2), global_position + Vector2(0, 6))
	if support.is_empty() or support.rid != first.rid or Vector2(first.position).distance_to(global_position) > 40:
		return -1.0
	if Vector2(first.normal).dot(Vector2.UP) < 0.5 or Vector2(first.position).y < global_position.y - 2:
		return -1.0
	var direction := (goal - origin).normalized()
	for distance in range(2, 66, 2):
		var point: Vector2 = first.position + direction * distance
		var query := PhysicsPointQueryParameters2D.new()
		query.position = point
		query.collision_mask = 1
		if get_world_2d().direct_space_state.intersect_point(query, 1).is_empty():
			if _terrain_ray(point, goal).is_empty():
				return origin.distance_to(point)
			return -1.0
	return -1.0


func _start_windup() -> void:
	if spider_kind == SpiderKind.WEB_SHOOTER and not _can_fire():
		_recover()
		return
	super._start_windup()
	SoundManager.play_limited(&"spider_hiss", -11.5, 0.2)


func _chase_velocity() -> float:
	return 0.0 if spider_kind == SpiderKind.WEB_SHOOTER else super._chase_velocity()


func _begin_attack() -> void:
	if spider_kind == SpiderKind.CHASER:
		super._begin_attack()
		_play_attack_release()
		if is_instance_valid(target):
			var offset := (target.global_position + Vector2(0, -18)) - global_position
			var tangent := Vector2(-_surface_normal.y, _surface_normal.x) * _direction
			var crosses_edge := not _has_support(global_position + tangent * minf(offset.length(), 24.0))
			if offset.dot(_surface_normal) > 12.0 or crosses_edge:
				var flight_time := 0.24
				var launch := offset / flight_time - get_gravity() * flight_time * 0.5
				if launch.dot(_surface_normal) > 0.0:
					_launch_leap(launch)
		return
	if not is_instance_valid(target) or not _can_fire():
		_recover()
		return
	var projectile := PROJECTILE.new()
	projectile.damage = attack_damage
	projectile.source_actor = self
	projectile.shot_color = Color.WHITE
	projectile.max_bounces = 0
	var origin := global_position + Vector2(0, -18)
	var goal := target.global_position + Vector2(0, -18)
	var exit_distance := _support_exit_distance(goal)
	if exit_distance < 0:
		projectile.free()
		_recover()
		return
	projectile.support_exit_distance = exit_distance
	var aim := target.global_position + Vector2(0, -18) - origin
	if aim.length_squared() < 1.0:
		aim = Vector2(_direction, 0)
	projectile.travel_velocity = aim.normalized() * projectile_speed * speed_multiplier
	get_parent().add_child(projectile)
	projectile.global_position = origin
	SoundManager.play_limited(&"spider_spit", -11.5, 0.12)
	_recover()
	_play_attack_release()


func _play_attack_release() -> void:
	sprite.speed_scale = 1.0
	sprite.play(&"attack")
	sprite.set_frame_and_progress(RELEASE_FRAME, 0.0)


func _can_fire() -> bool:
	var shots := get_tree().get_nodes_in_group("enemy_projectiles")
	if shots.size() >= max_room_projectiles:
		return false
	var own_shots := 0
	for shot in shots:
		if shot.source_actor == self:
			own_shots += 1
	return own_shots < max_own_projectiles


func _update_animation() -> void:
	sprite.flip_h = _direction < 0.0
	sprite.offset = Vector2.ZERO
	sprite.modulate = Color.WHITE
	if state == State.WINDUP:
		# Stretch the anticipation frames over the charge, then play the spit/recovery.
		sprite.animation = &"attack"
		var progress := 1.0 - _time_left / maxf(windup_time, 0.01)
		sprite.frame = clampi(floori(progress * RELEASE_FRAME), 0, RELEASE_FRAME - 1)
		sprite.pause()
		return
	if state in [State.RUSH, State.RECOVER] and sprite.animation == &"attack" and sprite.is_playing():
		return
	sprite.speed_scale = 1.0
	sprite.play(&"walk" if velocity.length() > 1.0 else &"idle")


func _on_damaged(hit: CombatHit, remaining_health: int) -> void:
	super._on_damaged(hit, remaining_health)
	if spider_kind == SpiderKind.CHASER:
		_attached = false
		_surface_path.clear()
		_route_timer = 0
	if remaining_health > 0:
		# JV marked the first death frame as the hit-stun pose.
		sprite.animation = &"death"
		sprite.frame = 0
		sprite.pause()


func _on_died(_hit: CombatHit) -> void:
	if _dying:
		return
	_dying = true
	SoundManager.play_limited(&"spider_death", -10.5, 0.15)
	hitbox.active = false
	set_physics_process(false)
	_health_bar.hide()
	_health_label.hide()
	_award_flesh()
	died.emit()
	sprite.modulate = Color.WHITE
	sprite.speed_scale = 1.0
	sprite.play(&"death")
	sprite.set_frame_and_progress(0, 0.0)


func _play_impact() -> void:
	SoundManager.play_limited(&"spider_hit", -10.5, 0.08)


func _on_spider_frame_changed() -> void:
	if _dying or sprite.animation != &"walk" or sprite.frame != 0:
		return
	if not (_attached or is_on_floor()) or velocity.length_squared() <= 144.0:
		return
	var now := Time.get_ticks_msec()
	if now < _next_walk_ms:
		return
	var distance_gain := _step_distance_gain(520.0)
	if distance_gain == -INF:
		return
	_next_walk_ms = now + randi_range(440, 760)
	if randf() < 0.15:
		return
	SoundManager.play_varied(&"spider_walk", -15.5 + randf_range(-2.0, 1.0) + distance_gain, 0.74, 1.30, randf_range(0.0, 0.16))


func _on_spider_animation_finished() -> void:
	if _dying and sprite.animation == &"death":
		queue_free()
