extends CombatDamageArea
## Temporary projectile art is the existing Godot icon.
const ICON = preload("res://icon.svg")
@export var lifetime: float = 2.4
@export var curve_gravity: float = 0.0
@export var passes_terrain: bool = false
@export var shot_color: Color = Color(1.0, 0.8, 0.3)
@export_range(0, 2) var max_bounces: int = 1
@export_range(0.1, 1.0) var bounce_speed_retention: float = 0.8
var travel_velocity: Vector2 = Vector2.ZERO
var source_actor: Node2D
var _bounces_left: int = 0
var reflected: bool = false
var _visual: Sprite2D


func _ready() -> void:
	add_to_group("enemy_projectiles")
	_bounces_left = max_bounces
	# Hits are swept below, so the player's overlap polling must not hit twice.
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	var visual := Sprite2D.new()
	visual.texture = ICON
	visual.modulate = shot_color
	visual.scale = Vector2.ONE * (14.0 / ICON.get_width())
	add_child(visual)
	_visual = visual


func reflect_from(defender: CharacterBody2D) -> bool:
	if reflected or not active:
		return false
	reflected = true
	source_actor = defender
	curve_gravity = 0.0
	var speed := clampf(maxf(travel_velocity.length(), absf(defender.velocity.x)), 200.0, 600.0)
	travel_velocity = Vector2(defender.dash_direction * speed, 0)
	# Move clear of the player; from now on this shot only tests enemy hurtboxes.
	global_position = defender.global_position + Vector2(defender.dash_direction * 18, -18)
	_visual.modulate = Color(0.4, 1.0, 1.0)
	return true


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	var destination := global_position + travel_velocity * delta + Vector2(0, 0.5 * curve_gravity * delta * delta)
	travel_velocity.y += curve_gravity * delta
	# Test the full step so a fast shot cannot skip a thin wall or hurtbox.
	var mask := 32 if reflected else 4
	if not passes_terrain:
		mask |= 1
	var ray := PhysicsRayQueryParameters2D.create(global_position, destination, mask)
	ray.collide_with_areas = true
	ray.hit_from_inside = true
	var contact := get_world_2d().direct_space_state.intersect_ray(ray)
	if not contact.is_empty():
		var hurtbox := contact.collider as CombatDamageable
		if hurtbox == null and _bounces_left > 0 and not passes_terrain:
			var normal: Vector2 = contact.normal
			if normal.length_squared() > 0.1:
				_bounces_left -= 1
				travel_velocity = travel_velocity.bounce(normal) * bounce_speed_retention
				global_position = contact.position + normal * 2.0
				return
		if hurtbox != null:
			var hit := create_hit(hurtbox.damage_owner())
			hit.source = source_actor if is_instance_valid(source_actor) else self
			if not reflected:
				var controller := hurtbox.damage_owner().get_node_or_null("DamageController") as PlayerDamageController
				if controller != null and controller.try_dash_parry(hit, self):
					return
			hurtbox.receive_hit(hit)
		active = false
		set_physics_process(false)
		queue_free()
		return
	global_position = destination
