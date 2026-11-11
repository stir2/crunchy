extends CombatDamageArea
## Animated web shot. Movement and dash reflection stay separate from the art.
const WEB_FRAMES = preload("res://Scenes/Enemies/Spiders/spider_projectile_frames.tres")
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
var support_exit_distance: float = 0.0
var radius: float = 0.0
var visual_scale: float = 0.5
var _visual: AnimatedSprite2D


func _ready() -> void:
	add_to_group("enemy_projectiles")
	_bounces_left = max_bounces
	# Hits are swept below, so the player's overlap polling must not hit twice.
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	var visual := AnimatedSprite2D.new()
	visual.sprite_frames = WEB_FRAMES
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual.modulate = shot_color
	visual.scale = Vector2.ONE * visual_scale
	visual.offset = Vector2(1, -3)
	visual.rotation = travel_velocity.angle()
	visual.play(&"fly")
	add_child(visual)
	_visual = visual


func reflect_from(defender: CharacterBody2D) -> bool:
	if reflected or not active:
		return false
	reflected = true
	support_exit_distance = 0.0
	source_actor = defender
	curve_gravity = 0.0
	var speed := clampf(maxf(travel_velocity.length(), absf(defender.velocity.x)), 200.0, 600.0)
	travel_velocity = Vector2(defender.dash_direction * speed, 0)
	# Move clear of the player; from now on this shot only tests enemy hurtboxes.
	global_position = defender.global_position + Vector2(defender.dash_direction * 18, -18)
	_visual.modulate = Color(0.4, 1.0, 1.0)
	_visual.rotation = travel_velocity.angle()
	return true


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	var destination := global_position + travel_velocity * delta + Vector2(0, 0.5 * curve_gravity * delta * delta)
	travel_velocity.y += curve_gravity * delta
	_visual.rotation = travel_velocity.angle()
	# Test the full step so a fast shot cannot skip a thin wall or hurtbox.
	var mask := 32 if reflected else 4
	if not passes_terrain:
		mask |= 1
	var ray_start := global_position
	var contact: Dictionary = {}
	if support_exit_distance > 0:
		var distance := minf(support_exit_distance, global_position.distance_to(destination))
		var exit := global_position.move_toward(destination, distance)
		var support_ray := PhysicsRayQueryParameters2D.create(global_position, exit, 32 if reflected else 4)
		support_ray.collide_with_areas = true
		support_ray.hit_from_inside = true
		contact = get_world_2d().direct_space_state.intersect_ray(support_ray)
		ray_start = exit
		support_exit_distance = maxf(0, support_exit_distance - distance)
	var ray := PhysicsRayQueryParameters2D.create(ray_start, destination, mask)
	ray.collide_with_areas = true
	ray.hit_from_inside = true
	if contact.is_empty() and ray_start.distance_squared_to(destination) > 0.001:
		contact = get_world_2d().direct_space_state.intersect_ray(ray)
		if radius > 0.0:
			var normal := (destination - ray_start).normalized().orthogonal()
			var best := INF if contact.is_empty() else ray_start.distance_squared_to(contact.position)
			for side in [-1, 1]:
				var offset: Vector2 = normal * radius * side
				ray.from = ray_start + offset
				ray.to = destination + offset
				var edge := get_world_2d().direct_space_state.intersect_ray(ray)
				if not edge.is_empty():
					var distance := ray.from.distance_squared_to(edge.position)
					if distance < best:
						best = distance
						contact = edge
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
				if controller != null:
					if radius > 0.0:
						hit.direction = travel_velocity.normalized()
					if controller.try_dash_parry(hit, self):
						return
					controller.receive_hit(hit, false)
				else:
					hurtbox.receive_hit(hit)
			elif hurtbox.receive_hit(hit) and radius > 0.0 and hurtbox.damage_owner().has_method("extend_recovery_from_web"):
				hurtbox.damage_owner().extend_recovery_from_web()
		SoundManager.play_limited(&"web_hit", -11.5, 0.12)
		active = false
		set_physics_process(false)
		queue_free()
		return
	global_position = destination
