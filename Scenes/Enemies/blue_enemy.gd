extends "res://Scenes/Enemies/red_enemy.gd"
## Heavy: slow approach, a big tell, and a hard hit if the charge connects.


func _ready() -> void:
	enemy_color = Color(0.35, 0.55, 1.0)
	attack_range = 105.0
	windup_time = 0.65
	rush_time = 0.5
	recovery_time = 0.9
	base_health = 4
	base_damage = 2
	chase_speed = 70.0
	rush_speed = 210.0
	knockback_multiplier = 0.2
	flesh_reward = 2
	super._ready()
