extends "res://Scenes/Enemies/red_enemy.gd"
## The web shooter holds its ground; the chaser stays close and bites.
const PROJECTILE = preload("res://Scenes/Enemies/enemy_projectile.gd")
const RELEASE_FRAME: int = 8
const SURFACE_NAVIGATION = preload("res://Scenes/Enemies/spider_surface_navigation.gd")
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
var _airborne: bool = false
var _jump_timer: float = 0.0


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
		attack_range = 26.0
		target_height_range = 40.0
		windup_time = 0.18
		rush_time = 0.12
		rush_speed = 80.0
		recovery_time = 0.28
		track_during_windup = false
	super._ready()
	sprite.position = Vector2(0, -14)
	sprite.offset = Vector2.ZERO
	_health_bar.position.y = -42
	_health_label.position.y = -58
	sprite.animation_finished.connect(_on_spider_animation_finished)
	_update_animation()
	if spider_kind == SpiderKind.CHASER:
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
		floor_snap_length = 0
		global_position.y -= 12
		var body := $CollisionShape2D as CollisionShape2D
		var circle := CircleShape2D.new()
		circle.radius = 12
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
		sprite.pause()
		return
	_route_timer -= delta
	_jump_timer = maxf(0.0, _jump_timer - delta)
	_time_left = maxf(0, _time_left - delta)
	if _hurt_time > 0:
		_hurt_time = maxf(0, _hurt_time - delta)
		velocity += Vector2(0, 980) * delta
		move_and_slide()
		_update_surface_labels()
		return
	if _airborne:
		_move_in_air(delta)
		_update_animation()
		_update_surface_labels()
		return
	if not _attached and state == State.RECOVER:
		_time_left = 0.0
	var goal := target.global_position + Vector2(0, -18) if is_instance_valid(target) else global_position
	var target_alive := is_instance_valid(target)
	if target_alive:
		var target_health := target.get_node_or_null("Health") as HealthComponent
		target_alive = target_health == null or not target_health.is_dead()
	var nearby := target_alive and global_position.distance_to(goal) < 640
	if state == State.WINDUP:
		velocity = Vector2.ZERO
		if not nearby or global_position.distance_to(goal) > 46:
			_recover()
		elif _time_left <= 0:
			_begin_attack()
	elif state == State.RUSH:
		velocity = Vector2.ZERO
		if _time_left <= 0:
			_recover()
	elif state == State.RECOVER and _time_left > 0:
		velocity = Vector2.ZERO
	else:
		state = State.CHASE if nearby else State.IDLE
		if _attached and nearby and global_position.distance_to(goal) <= 28 and _terrain_ray(global_position, goal).is_empty():
			var tangent := Vector2(-_surface_normal.y, _surface_normal.x)
			_direction = 1 if (goal - global_position).dot(tangent) >= 0 else -1
			_start_windup()
		else:
			_crawl_toward(goal, nearby, delta)
	if _attached:
		rotation = _surface_normal.angle() + PI * 0.5
	_update_animation()
	_update_surface_labels()


func _crawl_toward(goal: Vector2, chase: bool, delta: float) -> void:
	if _attached and chase and _try_direct_leap(goal):
		_move_in_air(delta)
		return
	if _route_timer <= 0 and chase:
		_surface_path = _navigator.find_path(get_world_2d().direct_space_state, global_position, goal)
		_route_timer = 0.6
		_attached = not _surface_path.is_empty()
	if not chase:
		_surface_path.clear()
	if _attached and _surface_normal.y > 0.5 and chase and goal.y > global_position.y + 48:
		# Let go of an underside when the player is below it.
		_attached = false
		_airborne = true
		_surface_path.clear()
		_route_timer = 0.4
		velocity = Vector2(clampf(goal.x - global_position.x, -120, 120), 30)
		_move_in_air(delta)
		return
	if _attached:
		while not _surface_path.is_empty() and global_position.distance_to(_surface_path[0].position) < 1.0:
			_surface_normal = _surface_path.pop_front().normal
		if _surface_path.is_empty():
			velocity = Vector2.ZERO
			return
		var next: Dictionary = _surface_path[0]
		var offset: Vector2 = next.position - global_position
		var speed := chase_speed if _surface_normal == Vector2.UP else wall_crawl_speed
		var motion := offset.limit_length(speed * speed_multiplier * delta)
		var tangent := Vector2(-_surface_normal.y, _surface_normal.x)
		if absf(motion.dot(tangent)) > 0.01:
			_direction = signf(motion.dot(tangent))
		velocity = motion / delta
		var collision := move_and_collide(motion)
		if collision != null:
			_route_timer = 0
			_surface_path.clear()
		rotation = _surface_normal.angle() + PI * 0.5
	else:
		velocity.y += 980 * delta
		velocity.x = move_toward(velocity.x, clampf(goal.x - global_position.x, -1, 1) * chase_speed if chase else 0.0, 400 * delta)
		var collision := move_and_collide(velocity * delta)
		if collision != null:
			_surface_normal = collision.get_normal()
			global_position += _surface_normal
			_attached = true
			velocity = Vector2.ZERO
			_route_timer = 0


func _try_direct_leap(goal: Vector2) -> bool:
	if _jump_timer > 0:
		return false
	_jump_timer = 0.25
	var offset := goal - global_position
	# Don't hop around a player who is already in biting range.
	if offset.length() < 42 or absf(offset.x) > 220:
		return false
	var landing := _terrain_ray(goal + Vector2(0, -8), goal + Vector2(0, 160))
	if landing.is_empty() or Vector2(landing.normal).y > -0.5:
		return false
	var destination: Vector2 = landing.position + Vector2(0, -13)
	var difference := destination - global_position
	if difference.y < -105 or difference.y > 300:
		return false
	if absf(difference.y) < 24 and absf(difference.x) < 50:
		return false
	# On level ground, run normally unless there is a gap in the way.
	if _surface_normal == Vector2.UP and absf(difference.y) < 24:
		var floor_between := _terrain_ray((global_position + destination) * 0.5, (global_position + destination) * 0.5 + Vector2(0, 20))
		if not floor_between.is_empty():
			return false
	var vertical_speed := -480.0 if difference.y < -24 else -60.0 if difference.y > 40 else -360.0
	var discriminant := vertical_speed * vertical_speed + 2.0 * 980.0 * difference.y
	if discriminant <= 0:
		return false
	var flight_time := (-vertical_speed + sqrt(discriminant)) / 980.0
	var launch := Vector2(difference.x / flight_time, vertical_speed)
	if absf(launch.x) > 220:
		return false
	var shape := $CollisionShape2D as CollisionShape2D
	var previous := global_position
	var steps := maxi(4, ceili(flight_time * 40))
	for step in range(1, steps + 1):
		var time := flight_time * step / steps
		var point := global_position + launch * time + Vector2(0, 490 * time * time)
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape.shape
		query.transform = Transform2D(0, previous)
		query.motion = point - previous
		query.collision_mask = 1
		if get_world_2d().direct_space_state.cast_motion(query)[0] < 0.999:
			return false
		previous = point
	_attached = false
	_airborne = true
	_surface_path.clear()
	_jump_timer = 0.9
	velocity = launch
	if absf(launch.x) > 1:
		_direction = signf(launch.x)
	return true


func _move_in_air(delta: float) -> void:
	var motion := velocity * delta + Vector2(0, 490 * delta * delta)
	velocity.y += 980 * delta
	rotation = lerp_angle(rotation, 0.0, minf(1, delta * 12))
	var collision := move_and_collide(motion)
	if collision != null:
		_surface_normal = collision.get_normal()
		global_position += _surface_normal
		_attached = true
		_airborne = false
		velocity = Vector2.ZERO
		_route_timer = 0
		rotation = _surface_normal.angle() + PI * 0.5


func _update_surface_labels() -> void:
	_health_bar.rotation = -rotation
	_health_label.rotation = -rotation
	_health_bar.global_position = global_position + Vector2(-16, -35)
	_health_label.global_position = global_position + Vector2(-25, -51)


func _terrain_ray(from: Vector2, to: Vector2) -> Dictionary:
	return get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(from, to, 1))


func _can_see_target() -> bool:
	if spider_kind == SpiderKind.CHASER:
		return is_instance_valid(target) and global_position.distance_to(target.global_position) < 640
	if not is_instance_valid(target):
		return false
	var target_health := target.get_node_or_null("Health") as HealthComponent
	if target_health != null and target_health.is_dead():
		return false
	var goal := target.global_position + Vector2(0, -18)
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


func _chase_velocity() -> float:
	return 0.0 if spider_kind == SpiderKind.WEB_SHOOTER else super._chase_velocity()


func _begin_attack() -> void:
	if spider_kind == SpiderKind.CHASER:
		super._begin_attack()
		_play_attack_release()
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
	sprite.play(&"walk" if _airborne or absf(velocity.x) > 1.0 else &"idle")


func _on_damaged(hit: CombatHit, remaining_health: int) -> void:
	super._on_damaged(hit, remaining_health)
	if spider_kind == SpiderKind.CHASER:
		_attached = false
		_airborne = true
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


func _on_spider_animation_finished() -> void:
	if _dying and sprite.animation == &"death":
		queue_free()
