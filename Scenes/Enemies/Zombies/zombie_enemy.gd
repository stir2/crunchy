extends "res://Scenes/Enemies/Shared/enemy_base.gd"
## Shared zombie movement; variants change their pace and willingness to commit.
enum ZombieKind { SHAMBLER, RUNNER, STALKER }
@export var zombie_kind: ZombieKind = ZombieKind.SHAMBLER
var _last_seen := Vector2.ZERO
var _memory_left: float = 0.0
var _jump_timer: float = 0.0
var _bait_left: float = 0.0
var _in_jump: bool = false
var _jump_delay: float = 0.0
var _jump_horizontal: float = 0.0


func _ready() -> void:
	detection_range = 1200
	base_health = 2
	chase_speed = 90
	rush_speed = 95
	attack_range = 42
	windup_time = 0.34
	rush_time = 3.0 / 24.0
	recovery_time = 0.5
	enemy_color = Color.WHITE
	if zombie_kind == ZombieKind.RUNNER:
		base_health = 1
		chase_speed = 150
		rush_speed = 150
		windup_time = 0.24
		recovery_time = 0.35
		enemy_color = Color(1.0, 0.5, 0.5)
	elif zombie_kind == ZombieKind.STALKER:
		base_health = 3
		chase_speed = 110
		windup_time = 0.3
		enemy_color = Color(0.6, 1.0, 0.65)
	super._ready()
	sprite.position = Vector2(0, -14)
	sprite.offset = Vector2.ZERO
	sprite.animation_finished.connect(_on_animation_finished)
	if target == null:
		var host := get_parent()
		while host != null:
			if host is AbyssRuntime:
				target = host.player
				target.health.damage_received.connect(_on_target_damaged)
				target.damage.attack_parried.connect(_on_attack_parried)
				break
			host = host.get_parent()
	_update_animation()


func _physics_process(delta: float) -> void:
	if _dying or damageable.health <= 0:
		return
	if damageable.is_hitstopped():
		_pause_for_hitstop()
		return
	_resume_after_hitstop()
	_jump_timer = maxf(0, _jump_timer - delta)
	_bait_left = maxf(0, _bait_left - delta)
	_time_left = maxf(0, _time_left - delta)
	_memory_left = maxf(0, _memory_left - delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	var sees := _sees_player()
	if sees:
		_last_seen = target.global_position
		_memory_left = 4.0
	if _hurt_time > 0:
		_hurt_time = maxf(0, _hurt_time - delta)
		velocity.x = move_toward(velocity.x, 0, 900 * delta)
		move_and_slide()
		sprite.modulate = enemy_color.lightened(0.5)
		return
	if _in_jump:
		_jump_delay = maxf(0, _jump_delay - delta)
		velocity.x = 0 if _jump_delay > 0 else _jump_horizontal
		move_and_slide()
		if is_on_floor() or is_on_wall():
			_in_jump = false
		_update_animation()
		return
	match state:
		State.WINDUP:
			velocity.x = 0
			if _time_left <= 0:
				_begin_attack()
		State.RUSH:
			velocity.x = _direction * rush_speed * speed_multiplier
			if _time_left <= 0:
				_recover()
		State.RECOVER:
			velocity.x = move_toward(velocity.x, 0, 1200 * delta)
			if _time_left <= 0:
				state = State.IDLE
		_:
			velocity.x = 0
			state = State.CHASE if _memory_left > 0 else State.IDLE
			if _memory_left > 0:
				var offset := _last_seen - global_position
				if absf(offset.x) > 3:
					_direction = signf(offset.x)
				var bait := _should_bait(sees, offset)
				if sees and not bait and absf(offset.x) <= attack_range and absf(offset.y) < 32 and is_on_floor():
					_start_windup()
				else:
					velocity.x = _direction * chase_speed * speed_multiplier * (-0.6 if bait else 1.0)
					if absf(offset.x) < 6 and not sees:
						velocity.x = 0
					if is_on_floor() and not bait:
						_try_jump(_last_seen)
	# An attack stays committed. Neither running nor lunging blindly crosses a ledge.
	if is_on_floor() and absf(velocity.x) > 1 and velocity.y >= 0 and not _floor_in_direction(signf(velocity.x), delta):
		velocity.x = 0
	move_and_slide()
	if state == State.RUSH and is_on_wall():
		_recover()
	_update_animation()


func _sees_player() -> bool:
	if not is_instance_valid(target):
		return false
	var health_node := target.get_node_or_null("Health") as HealthComponent
	if health_node != null and health_node.is_dead():
		_memory_left = 0
		return false
	if global_position.distance_to(target.global_position) > detection_range:
		return false
	# A platform may hide the player's feet while their head is still in view.
	for height in [-18.0, -38.0]:
		var ray := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -38), target.global_position + Vector2(0, height), 1)
		if get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			return true
	return false


func _should_bait(sees: bool, offset: Vector2) -> bool:
	if zombie_kind != ZombieKind.STALKER or not sees or absf(offset.x) > 80 or absf(offset.y) > 32:
		return false
	var combat := target.get_node_or_null("CombatController") as PlayerCombatController
	if combat != null and combat.attack_state in [PlayerCombatController.AttackState.WINDUP, PlayerCombatController.AttackState.ACTIVE]:
		_bait_left = 0.16
	return _bait_left > 0


func _floor_in_direction(direction: float, delta: float) -> bool:
	var start := global_position + Vector2(direction * (13 + absf(velocity.x) * delta), -8)
	return not get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(start, start + Vector2(0, 24), 1)).is_empty()


func _try_jump(goal: Vector2) -> bool:
	if _jump_timer > 0 or not is_on_floor():
		return false
	var difference := goal - global_position
	var gap := not _floor_in_direction(_direction, 0.1)
	var obstacle := test_move(global_transform, Vector2(_direction * 20, 0))
	if not gap and not obstacle and difference.y > -28:
		return false
	_jump_timer = 0.15
	# Choose a reachable local landing, rather than aiming a jump all the way
	# to a distant player. This also lets us hop low obstacles on level ground.
	var reach := 64.0 if difference.y > 24 else 120.0
	var next_x := global_position.x + clampf(difference.x, -reach, reach)
	var landing := get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(
		Vector2(next_x, global_position.y - 96), Vector2(next_x, global_position.y + 220), 1))
	if landing.is_empty() or Vector2(landing.normal).y > -0.5:
		return false
	var destination: Vector2 = landing.position + Vector2(0, -1)
	var dy := destination.y - global_position.y
	if dy < -90 or dy > 220:
		return false
	var vertical := -440.0 if dy < -24 or obstacle else -360.0 if dy < 40 else -200.0
	var discriminant := vertical * vertical + 1960 * dy
	if discriminant <= 0:
		return false
	var duration := (-vertical + sqrt(discriminant)) / 980
	var delay := 0.14 if obstacle else 0.0
	var launch := Vector2((destination.x - global_position.x) / maxf(0.1, duration - delay), vertical)
	if absf(launch.x) > 210:
		return false
	var body := $CollisionShape2D as CollisionShape2D
	var previous := global_position
	var steps := maxi(5, ceili(duration * 40))
	for step in range(1, steps + 1):
		var time := duration * step / steps
		var point := global_position + Vector2(launch.x * maxf(0, time - delay), launch.y * time + 490 * time * time)
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = body.shape
		query.transform = Transform2D(0, previous + body.position)
		query.motion = point - previous
		query.collision_mask = 1
		if get_world_2d().direct_space_state.cast_motion(query)[0] < 0.999:
			return false
		previous = point
	velocity = Vector2(0 if delay > 0 else launch.x, launch.y)
	_jump_delay = delay
	_jump_horizontal = launch.x
	_in_jump = true
	_jump_timer = 0.9
	return true


func _begin_attack() -> void:
	super._begin_attack()
	hitbox.position.x = _direction * 22
	sprite.play(&"attack")
	sprite.set_frame_and_progress(8, 0)


func _update_animation() -> void:
	sprite.flip_h = _direction < 0
	sprite.offset = Vector2.ZERO
	sprite.modulate = enemy_color
	if state == State.WINDUP:
		sprite.animation = &"attack"
		sprite.frame = clampi(floori((1.0 - _time_left / maxf(0.01, windup_time)) * 8), 0, 7)
		sprite.pause()
		return
	if state in [State.RUSH, State.RECOVER] and sprite.animation == &"attack" and sprite.is_playing():
		return
	sprite.play(&"walk" if absf(velocity.x) > 1 or not is_on_floor() else &"idle")


func _on_damaged(hit: CombatHit, remaining_health: int) -> void:
	_in_jump = false
	_bait_left = 0
	super._on_damaged(hit, remaining_health)
	velocity.x = 0
	_hurt_time = 0.22
	if remaining_health > 0:
		sprite.animation = &"death"
		sprite.frame = 0
		sprite.pause()


func _on_died(_hit: CombatHit) -> void:
	if _dying:
		return
	_dying = true
	velocity = Vector2.ZERO
	_bait_left = 0
	_resume_animation = false
	hitbox.active = false
	set_physics_process(false)
	_health_bar.hide()
	_health_label.hide()
	_award_flesh()
	died.emit()
	sprite.modulate = enemy_color
	sprite.play(&"death")
	sprite.set_frame_and_progress(0, 0)


func _on_animation_finished() -> void:
	if _dying and sprite.animation == &"death":
		queue_free()

