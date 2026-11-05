extends "res://Scenes/Enemies/red_enemy.gd"
## Charge, aim at the player, then fire one straight shot.
const PROJECTILE = preload("res://Scenes/Enemies/enemy_projectile.gd")
@export var projectile_speed: float = 180.0
@export var max_room_projectiles: int = 4
@export var max_own_projectiles: int = 2


func _ready() -> void:
	enemy_color = Color(0.4, 1.0, 0.4)
	attack_range = 280.0
	target_height_range = 160.0
	windup_time = 0.5
	recovery_time = 1.0
	track_during_windup = true
	base_health = 2
	chase_speed = 85.0
	super._ready()


func _start_windup() -> void:
	if not _can_fire():
		_recover()
		return
	super._start_windup()


func _begin_attack() -> void:
	if not is_instance_valid(target) or not _can_fire():
		_recover()
		return
	var projectile := PROJECTILE.new()
	projectile.damage = attack_damage
	projectile.source_actor = self
	projectile.max_bounces = 0
	var origin := global_position + Vector2(0, -18)
	var aim := target.global_position + Vector2(0, -18) - origin
	if aim.length_squared() < 1.0:
		aim = Vector2(_direction, 0)
	projectile.travel_velocity = aim.normalized() * projectile_speed * speed_multiplier
	get_parent().add_child(projectile)
	projectile.global_position = origin
	_recover()


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
	super._update_animation()
	if state == State.WINDUP:
		sprite.modulate = Color(1.0, 0.8, 0.3)
