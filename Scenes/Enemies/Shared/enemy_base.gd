extends CharacterBody2D
## Shared damage, rewards, attack states and health UI for zombies and spiders.
signal health_changed(current: int, maximum: int)
signal died
signal rush_hit(player: Node2D, damage: int)

enum State { IDLE, CHASE, WINDUP, RUSH, RECOVER }
const IMPACT_SOUND = preload("res://Assets/Audio/SFX/Combat/cleaver_impact.wav")
const SPACING = preload("res://Scenes/Enemies/Shared/enemy_spacing.gd")

@export var target: Node2D
@export_range(1, 3) var abyss_level: int = 1
@export var base_health: int = 2
@export var base_damage: int = 1
@export var chase_speed: float = 105.0
@export var rush_speed: float = 260.0
@export var detection_range: float = 420.0
@export var target_height_range: float = 48.0
@export var attack_range: float = 120.0
@export var windup_time: float = 0.3
@export var rush_time: float = 0.4
@export var recovery_time: float = 0.45
@export var flesh_reward: int = 1
@export_range(0.0, 1.0) var knockback_multiplier: float = 0.4
@export var track_during_windup: bool = false
@export var enemy_color: Color = Color(1.0, 0.35, 0.35)

var max_health: int
var health: int
var attack_damage: int
var speed_multiplier: float
var state: State = State.IDLE
var _time_left: float = 0.0
var _direction: float = 1.0
var _hit_this_rush: bool = false
var _hurt_time: float = 0.0
var _health_bar: ProgressBar
var _health_label: Label
var _dying: bool = false
var _resume_animation: bool = false
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: CombatDamageArea = $RushHitbox
@onready var damageable: CombatDamageable = $Damageable


func _ready() -> void:
	add_to_group("enemies")
	_create_health_bar()
	health_changed.connect(_update_health_bar)
	damageable.damaged.connect(_on_damaged)
	damageable.died.connect(_on_died)
	set_abyss_level(abyss_level)
	if target == null:
		target = get_parent().get_node_or_null("Player") as Node2D
	if target == null:
		var host := get_parent()
		while host != null:
			if host is AbyssRuntime:
				target = host.player
				break
			host = host.get_parent()
	if is_instance_valid(target):
		var target_health := target.get_node_or_null("Health") as HealthComponent
		if target_health != null:
			target_health.damage_received.connect(_on_target_damaged)
		var target_damage := target.get_node_or_null("DamageController") as PlayerDamageController
		if target_damage != null:
			target_damage.attack_parried.connect(_on_attack_parried)
	var spacing := SPACING.new()
	spacing.name = "EnemySpacing"
	add_child(spacing)


func _spacing_axis() -> Vector2:
	return Vector2.RIGHT


func _can_space() -> bool:
	return is_on_floor() and velocity.y >= 0


func set_abyss_level(level: int) -> void:
	abyss_level = clampi(level, 1, 3)
	max_health = roundi(base_health * (1.0 + 0.5 * (abyss_level - 1)))
	health = max_health
	attack_damage = base_damage + abyss_level - 1
	speed_multiplier = 1.0 + 0.1 * (abyss_level - 1)
	if is_instance_valid(damageable):
		damageable.max_health = max_health
		damageable.reset_damageable()
		hitbox.damage = attack_damage
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	if damageable.health <= 0:
		hitbox.active = false
		return
	if damageable.is_hitstopped():
		_pause_for_hitstop()
		return
	_resume_after_hitstop()
	if not is_on_floor():
		velocity += get_gravity() * delta
	if _hurt_time > 0.0:
		_hurt_time = maxf(0.0, _hurt_time - delta)
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
		move_and_slide()
		sprite.modulate = Color.WHITE
		return
	_time_left = maxf(0.0, _time_left - delta)
	var sees_player := _can_see_target()
	match state:
		State.IDLE, State.CHASE:
			velocity.x = 0.0
			state = State.CHASE if sees_player else State.IDLE
			if sees_player:
				_face_target()
				if absf(target.global_position.x - global_position.x) <= attack_range and is_on_floor():
					_start_windup()
				else:
					velocity.x = _chase_velocity()
		State.WINDUP:
			velocity.x = 0.0
			if track_during_windup and sees_player:
				_face_target()
			if not sees_player:
				_recover()
			elif _time_left <= 0.0:
				_begin_attack()
		State.RUSH:
			velocity.x = _direction * rush_speed * speed_multiplier
			if _time_left <= 0.0:
				_recover()
		State.RECOVER:
			velocity.x = 0.0
			if _time_left <= 0.0:
				state = State.IDLE
	if not is_zero_approx(velocity.x) and is_on_floor() and not _has_floor_ahead(delta):
		velocity.x = 0.0
		if state == State.RUSH:
			_recover()
	move_and_slide()
	if state == State.RUSH:
		if is_on_wall():
			_recover()
	_update_animation()


func _can_see_target() -> bool:
	if not is_instance_valid(target):
		return false
	var target_health := target.get_node_or_null("Health") as HealthComponent
	if target_health != null and target_health.is_dead():
		return false
	var offset := target.global_position - global_position
	if absf(offset.x) > detection_range or absf(offset.y) > target_height_range:
		return false
	var ray := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -18), target.global_position + Vector2(0, -18), 1)
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func _face_target() -> void:
	var distance: float = target.global_position.x - global_position.x
	if not is_zero_approx(distance):
		_direction = signf(distance)


func _start_windup() -> void:
	state = State.WINDUP
	_time_left = windup_time
	velocity.x = 0.0


func _chase_velocity() -> float:
	return _direction * chase_speed * speed_multiplier


func _begin_attack() -> void:
	state = State.RUSH
	_time_left = rush_time
	_hit_this_rush = false
	hitbox.active = true


func _recover() -> void:
	hitbox.active = false
	state = State.RECOVER
	_time_left = recovery_time
	velocity.x = 0.0


func _has_floor_ahead(delta: float) -> bool:
	# Look past the body's leading edge, including this tick's movement.
	var ahead := Vector2(signf(velocity.x) * (16.0 + absf(velocity.x) * delta), -8)
	var ray := PhysicsRayQueryParameters2D.create(global_position + ahead, global_position + ahead + Vector2(0, 20), 1)
	return not get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func _on_target_damaged(hit: CombatHit, _amount: int) -> void:
	if hit.source == self and not _hit_this_rush:
		_hit_this_rush = true
		hitbox.active = false
		rush_hit.emit(target, attack_damage)


func _on_attack_parried(hit: CombatHit, projectile: bool) -> void:
	if not projectile and hit.source == self:
		_recover()


func take_damage(amount: int) -> void:
	if amount <= 0 or health <= 0:
		return
	var hit := CombatHit.new()
	hit.amount = amount
	damageable.receive_hit(hit)


func _on_damaged(hit: CombatHit, remaining_health: int) -> void:
	_resume_animation = false
	health = remaining_health
	_recover()
	velocity = hit.knockback * knockback_multiplier
	_hurt_time = 0.12
	_play_impact()
	health_changed.emit(health, max_health)


func _on_died(_hit: CombatHit) -> void:
	if _dying:
		return
	_dying = true
	hitbox.active = false
	set_physics_process(false)
	_health_bar.hide()
	_health_label.hide()
	sprite.modulate = Color.WHITE
	sprite.pause()
	_award_flesh()
	died.emit()
	var death := create_tween().set_parallel(true)
	death.tween_property(sprite, "modulate:a", 0.0, 0.16)
	death.tween_property(sprite, "position:y", sprite.position.y - 8.0, 0.16)
	death.chain().tween_callback(queue_free)


func _play_impact() -> void:
	# Leave the sound in the room so the final hit can finish after death.
	var sound := AudioStreamPlayer2D.new()
	sound.stream = IMPACT_SOUND
	sound.bus = &"SFX"
	sound.volume_db = -10.0 + SoundManager.gain_for(&"cleaver_impact")
	sound.pitch_scale = 1.1 if health <= 0 else 1.0
	get_parent().add_child(sound)
	sound.global_position = global_position
	sound.finished.connect(sound.queue_free)
	sound.play()


func _award_flesh() -> void:
	if flesh_reward <= 0:
		return
	var host := get_parent()
	while host != null:
		if host is AbyssRuntime:
			if host.is_active() and host.stream.specials != null:
				GameController.collect_descent_flesh(host.stream.specials.world, flesh_reward, global_position)
			return
		host = host.get_parent()
	# Standalone enemy labs do not have an expedition balance.
	GameController.add_flesh(flesh_reward)


func _update_animation() -> void:
	sprite.flip_h = _direction > 0.0
	sprite.modulate = enemy_color.lightened(0.35) if state == State.WINDUP else enemy_color
	var animation_name: StringName = &"idle"
	if state == State.RUSH:
		animation_name = &"run"
	elif absf(velocity.x) > 1.0:
		animation_name = &"walk"
	sprite.offset = Vector2(0, 3) if animation_name == &"run" else Vector2(0, -4)
	sprite.play(animation_name)


func _create_health_bar() -> void:
	_health_bar = ProgressBar.new()
	_health_bar.name = "HealthBar"
	_health_bar.position = Vector2(-16, -62)
	_health_bar.show_percentage = false
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_bar.z_index = 1
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.08, 0.08, 0.1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.85, 0.35)
	_health_bar.add_theme_stylebox_override("background", background)
	_health_bar.add_theme_stylebox_override("fill", fill)
	add_child(_health_bar)
	_health_bar.size = Vector2(32, 2)
	_health_label = Label.new()
	_health_label.name = "HealthLabel"
	_health_label.position = Vector2(-25, -80)
	_health_label.size = Vector2(50, 14)
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_label.add_theme_font_size_override("font_size", 10)
	_health_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_health_label.add_theme_constant_override("outline_size", 3)
	_health_label.z_index = 1
	add_child(_health_label)


func _update_health_bar(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "%d / %d" % [current, maximum]


func _pause_for_hitstop() -> void:
	_resume_animation = _resume_animation or sprite.is_playing()
	sprite.pause()


func _resume_after_hitstop() -> void:
	if _resume_animation:
		_resume_animation = false
		sprite.play()
