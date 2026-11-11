extends AnimatedSprite2D
## Green healing overlay; Health owns healing, movement/combat keep their animations.
@onready var player: Player = get_parent()

func _ready() -> void:
	hide()
	player.get_node("Health").healed.connect(_on_healed)
	player.get_node("Health").died.connect(_on_died)
	player.movement_reset.connect(_clear)
	animation_finished.connect(_clear)

func _process(_delta: float) -> void:
	if visible and is_instance_valid(player):
		flip_h = player.facing_direction < 0

func _on_healed(amount: int) -> void:
	if amount <= 0 or player.get_node("Health").is_dead(): return
	flip_h = player.facing_direction < 0
	show()
	play(&"heal")
	set_frame_and_progress(0,0.0)

func _on_died(_hit: CombatHit) -> void:
	_clear()

func _clear() -> void:
	stop()
	hide()
