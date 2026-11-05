class_name HealthComponent
extends Node
## Actor-independent HP, healing, immunity and death; no movement/collision policy.
## Player HUD uses two HP per heart. Enemies can use the same integer HP units.
## CombatDamageable adapts this to hurtbox collisions; AI owns knockback/flash.
## Runtime changes use take_damage(), heal() and reset_health(), not direct writes.
signal health_changed(current: int, maximum: int)
signal damage_received(hit: CombatHit, amount: int)
signal healed(amount: int)
signal died(hit: CombatHit)
signal health_reset

@export_range(1, 1000) var base_max_health: int = 6:
	set(value):
		base_max_health = maxi(1, value)
		_refresh_maximum()
@export_range(0, 1000) var temporary_max_health_bonus: int = 0:
	set(value):
		temporary_max_health_bonus = maxi(0, value)
		_refresh_maximum()
## -1 starts full; zero starts dead. Runtime changes should use the APIs below.
@export_range(-1, 1000) var starting_health: int = -1
## Physics ticks, independent of combat freezes. Zero disables timed immunity.
@export_range(0, 600) var invulnerability_frames: int = 0
var current_health: int = 0
var max_health: int:
	get:
		return base_max_health + temporary_max_health_bonus
var _invulnerable_until: int = -1
var _initialized: bool = false

func _ready() -> void:
	current_health = max_health if starting_health < 0 else clampi(starting_health, 0, max_health)
	_initialized = true
	health_changed.emit(current_health, max_health)

func is_dead() -> bool:
	return current_health <= 0

func is_invulnerable() -> bool:
	return Engine.get_physics_frames() < _invulnerable_until

func take_damage(hit: CombatHit) -> bool:
	if hit == null or hit.amount <= 0 or is_dead() or is_invulnerable():
		return false
	var amount := mini(current_health, maxi(1, hit.amount))
	current_health -= amount
	_invulnerable_until = Engine.get_physics_frames() + invulnerability_frames
	health_changed.emit(current_health, max_health)
	damage_received.emit(hit, amount)
	if is_dead():
		died.emit(hit)
	return true

func heal(amount: int) -> int:
	if amount <= 0 or is_dead():
		return 0 # Healing is not resurrection.
	var restored := mini(amount, max_health - current_health)
	if restored > 0:
		current_health += restored
		health_changed.emit(current_health, max_health)
		healed.emit(restored)
	return restored

## Explicit reset/revival hook for future expedition code and the movement lab.
func reset_health(amount: int = -1, clear_temporary_bonus: bool = false) -> void:
	if clear_temporary_bonus:
		temporary_max_health_bonus = 0
	current_health = max_health if amount < 0 else clampi(amount, 0, max_health)
	_invulnerable_until = -1
	health_changed.emit(current_health, max_health)
	health_reset.emit()

func _refresh_maximum() -> void:
	if _initialized:
		current_health = mini(current_health, max_health)
		health_changed.emit(current_health, max_health)
