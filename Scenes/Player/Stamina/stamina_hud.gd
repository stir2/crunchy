class_name StaminaHUD
extends Control
## Thin world-space resource bar; bind any stamina component without movement logic.
@export var bar_size: Vector2 = Vector2(32, 2)
@export var stamina_path: NodePath
@export_range(0.05, 1.0, 0.01) var failure_flash_seconds: float = 0.18
@export_range(0.05, 0.5, 0.01) var regeneration_indicator_seconds: float = 0.15
@export_range(0.1, 3.0, 0.05) var regeneration_blink_period: float = 0.8
@export_range(1, 8, 1) var regeneration_block_width: int = 2
@export_range(0.05, 1.0, 0.01) var drain_indicator_seconds: float = 0.22
## Minimum time between depletion pulses, including continuous climbing drain.
@export_range(0.1, 3.0, 0.05) var drain_pulse_interval: float = 0.4
var stamina: StaminaComponent
var _flash_remaining: float = 0.0
var _regen_remaining: float = 0.0
var _drain_remaining: float = 0.0
var _drain_pulse_wait: float = 0.0
var _previous_stamina: float = 0.0
var _previous_maximum: float = 0.0
var _drain_from_ratio: float = 0.0
var _effect_time: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)
	var actor_health := get_parent().get_node_or_null("Health") as HealthComponent
	if actor_health != null:
		actor_health.health_changed.connect(_on_owner_health_changed)
		visible = not actor_health.is_dead()
	if not stamina_path.is_empty():
		bind_stamina(get_node_or_null(stamina_path) as StaminaComponent)

func bind_stamina(component: StaminaComponent) -> void:
	if is_instance_valid(stamina):
		stamina.stamina_changed.disconnect(_on_changed)
		stamina.spend_failed.disconnect(_on_spend_failed)
	stamina = component
	_flash_remaining = 0.0
	_regen_remaining = 0.0
	_drain_remaining = 0.0
	_drain_pulse_wait = 0.0
	set_process(false)
	if stamina != null:
		_previous_stamina = stamina.current_stamina
		_previous_maximum = stamina.max_stamina
		stamina.stamina_changed.connect(_on_changed)
		stamina.spend_failed.connect(_on_spend_failed)
	queue_redraw()

func fill_ratio() -> float:
	return stamina.current_stamina / stamina.max_stamina if is_instance_valid(stamina) else 0.0

func _on_changed(current: float, maximum: float) -> void:
	# React to actual pool changes, independently of movement/ability states.
	if not is_equal_approx(maximum, _previous_maximum) or current >= maximum:
		_regen_remaining = 0.0
		_drain_remaining = 0.0
		_drain_pulse_wait = 0.0
	elif current < _previous_stamina:
		if _drain_pulse_wait <= 0.0:
			_effect_time = 0.0
			_drain_from_ratio = _previous_stamina / maximum
			_drain_remaining = drain_indicator_seconds
			_drain_pulse_wait = drain_pulse_interval
		_regen_remaining = 0.0
	elif current > _previous_stamina:
		if _regen_remaining <= 0.0:
			_effect_time = 0.0
		_regen_remaining = regeneration_indicator_seconds
		_drain_remaining = 0.0
		_drain_pulse_wait = 0.0
	_previous_stamina = current
	_previous_maximum = maximum
	_update_processing()
	queue_redraw()

func _on_spend_failed(_requested: float) -> void:
	_flash_remaining = failure_flash_seconds
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_effect_time += delta
	_flash_remaining = maxf(0.0, _flash_remaining - delta)
	_regen_remaining = maxf(0.0, _regen_remaining - delta)
	_drain_remaining = maxf(0.0, _drain_remaining - delta)
	_drain_pulse_wait = maxf(0.0, _drain_pulse_wait - delta)
	queue_redraw()
	_update_processing()

func _update_processing() -> void:
	set_process(_flash_remaining > 0.0 or _regen_remaining > 0.0 or _drain_remaining > 0.0 or _drain_pulse_wait > 0.0)

func _draw() -> void:
	var extent := Vector2(maxf(1.0,bar_size.x),maxf(1.0,bar_size.y))
	var bounds := Rect2(Vector2.ZERO,extent)
	draw_rect(bounds,Color(0,0,0,0.5))
	var width := floorf(extent.x * clampf(fill_ratio(),0.0,1.0))
	var fill := Color.WHITE
	if _drain_remaining > 0.0:
		var progress := 1.0 - _drain_remaining / drain_indicator_seconds
		fill.a = 1.0 - 0.45 * sin(progress * PI) # One gentle dip per pulse.
	if width > 0.0:
		draw_rect(Rect2(0,0,width,extent.y),fill)
	if _regen_remaining > 0.0:
		_draw_refill_block(extent, width)
	elif _drain_remaining > 0.0:
		var trail_end := minf(extent.x, ceilf(extent.x * _drain_from_ratio))
		var alpha := 0.65 * _drain_remaining / drain_indicator_seconds
		if trail_end > width:
			draw_rect(Rect2(width,0,trail_end-width,extent.y),Color(1,1,1,alpha))
	if _flash_remaining > 0.0:
		draw_rect(bounds,Color(1,1,1,0.65)) # White pulse on an unaffordable dash.

func _draw_refill_block(extent: Vector2, filled_width: float) -> void:
	# Blink only the next empty block; existing stamina stays solid white.
	var phase := fposmod(_effect_time, regeneration_blink_period)
	var width := minf(float(regeneration_block_width), extent.x - filled_width)
	if phase < regeneration_blink_period * 0.5 and width > 0.0:
		draw_rect(Rect2(filled_width,0,width,extent.y),Color(1,1,1,0.65))


func _on_owner_health_changed(current: int, _maximum: int) -> void:
	visible = current > 0
