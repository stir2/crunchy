class_name StaminaComponent
extends Node
## Reusable resource pool. Its host advances time and supplies regeneration policy.
signal stamina_changed(current: float, maximum: float)
signal exhausted
signal spend_failed(requested: float)

@export_range(1.0, 10000.0, 1.0) var max_stamina: float = 100.0:
	set(value):
		max_stamina = maxf(1.0, value)
		if _initialized:
			current_stamina = minf(current_stamina, max_stamina)
			stamina_changed.emit(current_stamina, max_stamina)
@export_range(-1.0, 10000.0, 1.0) var starting_stamina: float = -1.0
@export_range(0.0, 1000.0, 1.0) var dash_cost: float = 5.0
@export_range(0.0, 1000.0, 0.1) var regeneration_per_second: float = 3.0
@export_range(0.0, 60.0, 0.05) var regeneration_delay: float = 0.75
var current_stamina: float = 0.0
var regeneration_delay_remaining: float = 0.0
var _initialized: bool = false

func _ready() -> void:
	_initialized = true
	reset_stamina(starting_stamina)

func can_spend(amount: float) -> bool:
	return amount >= 0.0 and current_stamina >= amount

func spend(amount: float) -> bool:
	if not can_spend(amount):
		spend_failed.emit(amount)
		return false
	if amount > 0.0:
		var was_positive := current_stamina > 0.0
		current_stamina = maxf(0.0, current_stamina - amount)
		if is_zero_approx(current_stamina):
			current_stamina = 0.0
		regeneration_delay_remaining = regeneration_delay
		stamina_changed.emit(current_stamina, max_stamina)
		if was_positive and current_stamina == 0.0:
			exhausted.emit()
	return true

## Continuous costs may consume the last partial unit, unlike an atomic dash cost.
func drain(amount: float) -> float:
	var consumed := minf(current_stamina, maxf(0.0, amount))
	spend(consumed)
	return consumed

func restore(amount: float) -> float:
	var restored := minf(maxf(0.0, amount), max_stamina - current_stamina)
	if restored > 0.0:
		current_stamina += restored
		stamina_changed.emit(current_stamina, max_stamina)
	return restored

## Full restoration hook for future sleeping. Movement/death never call it.
func reset_stamina(amount: float = -1.0) -> void:
	current_stamina = max_stamina if amount < 0.0 else clampf(amount, 0.0, max_stamina)
	regeneration_delay_remaining = 0.0
	stamina_changed.emit(current_stamina, max_stamina)

func advance(delta: float, regeneration_blocked: bool = false) -> void:
	var elapsed := maxf(0.0, delta)
	var regenerating_time := maxf(0.0, elapsed - regeneration_delay_remaining)
	regeneration_delay_remaining = maxf(0.0, regeneration_delay_remaining - elapsed)
	if not regeneration_blocked:
		restore(regeneration_per_second * regenerating_time)
