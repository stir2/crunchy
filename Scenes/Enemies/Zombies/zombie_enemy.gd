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
var _next_step_ms: int = 0
var _step_parity: int = 0


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
	sprite.frame_changed.connect(_on_zombie_frame_changed)
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
	if not _in_jump and not is_on_floor():
		velocity += get_gravity() * delta
	var sees := _sees_player()
	if sees or _senses_nearby_player():
		_last_seen = target.global_position
		_memory_left = 4.0
	if _hurt_time > 0:
		_hurt_time = maxf(0, _hurt_time - delta)
		velocity.x = move_toward(velocity.x, 0, 900 * delta)
		move_and_slide()
		sprite.modulate = enemy_color.lightened(0.5)
		return
	if _in_jump:
		_move_jump(delta)
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
					if absf(offset.x) < 6:
						velocity.x = 0
					if is_on_floor() and not bait:
						_try_jump(_last_seen, delta)
	# An attack stays committed. Neither running nor lunging blindly crosses a ledge.
	if not _in_jump and is_on_floor() and absf(velocity.x) > 1 and velocity.y >= 0 and not _floor_in_direction(signf(velocity.x), delta):
		velocity.x = 0
	if _in_jump:
		_move_jump(delta)
	else:
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


func _senses_nearby_player() -> bool:
	if not is_instance_valid(target) or global_position.distance_to(target.global_position) > 240:
		return false
	var target_health := target.get_node_or_null("Health") as HealthComponent
	return target_health == null or not target_health.is_dead()


func _try_jump(goal: Vector2, delta: float) -> void:
	if _jump_timer > 0 or not is_on_floor():
		return
	var difference := goal - global_position
	var gap := not _floor_in_direction(_direction, delta)
	var obstacle := test_move(global_transform, Vector2(_direction * 16, 0))
	if not gap and not obstacle and difference.y > -24.0:
		return
	_jump_timer = 0.18

	var runner := zombie_kind == ZombieKind.RUNNER
	var max_reach := 240.0 if runner else 190.0
	var max_speed := 280.0 if runner else 220.0
	var delay := 0.1 if obstacle else 0.0
	var best_score := INF
	var best_launch := Vector2.ZERO
	var candidates := [clampf(difference.x, -max_reach, max_reach)]
	for distance in [32.0, 56.0, 80.0, 112.0, 152.0, max_reach]:
		candidates.append(_direction * distance)
	var space := get_world_2d().direct_space_state
	for dx: float in candidates:
		var x := global_position.x + dx
		# Sample the player's level and the intervening levels. An overhead floor
		# can hide a lower landing when using just one ray from above.
		var ray_top := maxf(global_position.y - 200.0, minf(goal.y - 8.0, global_position.y - 8.0))
		var landings: Array[Vector2] = []
		for y in range(floori(ray_top), ceili(global_position.y + 120.0), 16):
			var ray := PhysicsRayQueryParameters2D.create(Vector2(x, y), Vector2(x, global_position.y + 120.0), collision_mask)
			var landing := space.intersect_ray(ray)
			if landing.is_empty() or Vector2(landing.normal).y > -0.5:
				continue
			var destination: Vector2 = landing.position + Vector2(0, -2)
			if landings.has(destination):
				continue
			landings.append(destination)
			var rise := global_position.y - destination.y
			if rise < 24.0 and not gap and not obstacle:
				continue
			if absf(dx) < 24.0 and absf(rise) < 24.0:
				continue
			var score := destination.distance_to(goal) + absf(dx) * 0.05
			if score >= best_score or destination.distance_to(goal) + 8.0 >= difference.length():
				continue
			var launch := _plan_leap(destination, max_speed, 220.0, delay)
			if launch != Vector2.ZERO:
				best_score = score
				best_launch = launch
	if best_launch == Vector2.ZERO:
		return
	_jump_horizontal = best_launch.x
	_jump_delay = delay
	velocity = best_launch
	_in_jump = true
	_jump_timer = 0.25


func _move_jump(delta: float) -> void:
	var gravity_step := get_gravity().y * delta
	velocity.x = _jump_horizontal * (1.0 - clampf(_jump_delay / delta, 0.0, 1.0))
	_jump_delay = maxf(0.0, _jump_delay - delta)
	velocity.y += gravity_step * 0.5
	move_and_slide()
	if is_on_floor() or is_on_wall() or is_on_ceiling():
		_in_jump = false
	else:
		velocity.y += gravity_step * 0.5


func _start_windup() -> void:
	super._start_windup()
	SoundManager.play_limited(&"zombie_atk_windup", -11.5, 0.2)


func _play_impact() -> void:
	SoundManager.play_limited(&"zombie_hit", -10.5, 0.08)


func _begin_attack() -> void:
	super._begin_attack()
	SoundManager.play_limited(&"zombie_atk", -10.5, 0.12)
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
	SoundManager.play_limited(&"zombie_death", -10.5, 0.15)
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


func _zombie_floor_surface() -> String:
	for i in range(get_slide_collision_count()):
		var contact := get_slide_collision(i)
		if contact.get_normal().dot(Vector2.UP) < 0.6:
			continue
		var collider := contact.get_collider() as Node
		if collider == null:
			continue
		var surface := String(collider.get_meta("footstep_surface", &"stone"))
		if collider is TileMapLayer and collider.tile_set != null:
			if collider.tile_set.get_custom_data_layer_by_name("footstep_surface") >= 0:
				var point := contact.get_position() - contact.get_normal()
				var cell: Vector2i = collider.local_to_map(collider.to_local(point))
				var data: TileData = collider.get_cell_tile_data(cell)
				if data != null:
					surface = String(data.get_custom_data("footstep_surface"))
		return "wood" if surface == "wood" else "stone"
	return "stone"


func _on_zombie_frame_changed() -> void:
	if _dying or _in_jump or sprite.animation != &"walk" or sprite.frame not in [0, 9]:
		return
	if not is_on_floor() or absf(velocity.x) <= 12.0:
		return
	var now := Time.get_ticks_msec()
	if now < _next_step_ms:
		return
	var distance_gain := _step_distance_gain(540.0)
	if distance_gain == -INF:
		return
	var runner := zombie_kind == ZombieKind.RUNNER
	_next_step_ms = now + (randi_range(180, 300) if runner else randi_range(260, 440))
	var surface := _zombie_floor_surface()
	var drag := (_step_parity == 1 and randf() < 0.72) or (_step_parity == 0 and randf() < 0.35)
	var cue := StringName(("zombie_drag_" if drag else "zombie_step_") + surface)
	var pitch_min := (0.68 if _step_parity == 0 else 0.80) if runner else (0.54 if _step_parity == 0 else 0.68)
	var pitch_max := (0.94 if _step_parity == 0 else 1.16) if runner else (0.76 if _step_parity == 0 else 1.05)
	var offset := randf_range(0.0, 0.04) if _step_parity == 0 else randf_range(0.03, 0.11)
	var base_vol := -14.5 + randf_range(-2.0, 1.0) if _step_parity == 0 else -17.0 + randf_range(-2.5, 0.5)
	_step_parity = 1 - _step_parity
	SoundManager.play_varied(cue, base_vol + distance_gain, pitch_min, pitch_max, offset, &"ZombieSteps")

