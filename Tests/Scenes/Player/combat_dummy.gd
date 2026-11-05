extends CharacterBody2D
## Minimal enemy damage-wiring example: Damageable is a direct child of this body.
## damaged applies knockback/flash; physics respects hitstop and zero HP.
## Auto-reset/drawn health bar are lab conveniences, not enemy AI requirements.
@export var body_color: Color = Color(0.45, 0.65, 0.65)
@export_range(0.0, 5000.0, 10.0) var knockback_friction: float = 600.0
@export_range(0.0, 1.0, 0.01) var hit_flash_seconds: float = 0.12
@export_range(0.0, 10.0, 0.25) var auto_reset_seconds: float = 2.5
@export var show_health_bar: bool = true
@export var print_damage: bool = false
var _spawn: Vector2
var _flash_left: float = 0.0
var _dead_time: float = 0.0
@onready var damageable: CombatDamageable = $Damageable

func _ready() -> void:
	_spawn = global_position
	damageable.damaged.connect(_on_damaged)
	damageable.health_reset.connect(queue_redraw)

func _physics_process(delta: float) -> void:
	if damageable.is_hitstopped() or damageable.health <= 0:
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	velocity.x = move_toward(velocity.x, 0.0, knockback_friction * delta)
	move_and_slide()

func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
		queue_redraw()
	if damageable.health <= 0 and auto_reset_seconds > 0.0:
		_dead_time += delta
		if _dead_time >= auto_reset_seconds:
			reset_dummy()

func _on_damaged(hit: CombatHit, _health: int) -> void:
	velocity = hit.knockback
	_flash_left = hit_flash_seconds
	if print_damage:
		print(name, " hit for ", hit.amount, "; health ", damageable.health, "/", damageable.max_health)
	queue_redraw()

func reset_dummy() -> void:
	global_position = _spawn
	velocity = Vector2.ZERO
	_flash_left = 0.0
	_dead_time = 0.0
	damageable.reset_damageable()
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(damageable):
		return
	var color := Color.WHITE if _flash_left > 0.0 else body_color
	if damageable.health <= 0:
		color = Color(0.25, 0.27, 0.3)
	draw_rect(Rect2(-11,-32,22,32),color)
	draw_line(Vector2(-6,-24), Vector2(6,-24), Color(0.15,0.2,0.23), 2)
	if show_health_bar:
		draw_rect(Rect2(-12,-40,24,3),Color(0.18,0.2,0.23))
		draw_rect(Rect2(-12,-40,24.0 * damageable.health / damageable.max_health,3),Color(0.75,0.4,0.35))
