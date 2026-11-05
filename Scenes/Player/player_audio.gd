extends Node
## Sound follows combat and health signals without changing their timing.
var _low_health: bool = false
var _was_dead: bool = false
var _last_swing: int = -1
var _warning: AudioStreamPlayer
var _heartbeat: AudioStreamPlayer
@onready var player: Player = get_parent()
@onready var sounds: Node = get_node("/root/SoundManager")


func _ready() -> void:
	_warning = AudioStreamPlayer.new()
	_warning.stream = sounds.stream_for(&"low_health_initial")
	_warning.bus = &"SFX"
	_warning.volume_db = -16
	add_child(_warning)
	_heartbeat = AudioStreamPlayer.new()
	var loop := sounds.stream_for(&"low_health").duplicate() as AudioStreamWAV
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = roundi(loop.get_length() * loop.mix_rate)
	_heartbeat.stream = loop
	_heartbeat.bus = &"SFX"
	_heartbeat.volume_db = -20
	add_child(_heartbeat)
	_warning.finished.connect(func():
		if _low_health:
			_heartbeat.play())
	player.combat.phase_changed.connect(_on_attack_phase)
	player.combat.hit_confirmed.connect(_on_hit_confirmed)
	player.health.health_changed.connect(_on_health_changed)
	player.health.died.connect(func(_hit: CombatHit): _was_dead = true)
	player.health.health_reset.connect(_on_health_reset)
	_was_dead = player.health.is_dead()
	_on_health_changed(player.health.current_health, player.health.max_health)


func _on_attack_phase(phase: int) -> void:
	if phase == PlayerCombatController.AttackState.ACTIVE and _last_swing != player.combat.swing_id:
		_last_swing = player.combat.swing_id
		var sprite := player.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
		sounds.play_sfx(&"cleaver_swing_alt" if sprite.animation == &"attack_alt" else &"cleaver_swing", -12)


func _on_hit_confirmed(target: CombatDamageable, _hit: CombatHit) -> void:
	# Live enemies already play their own spatial impact sound.
	if not target.damage_owner().is_in_group("enemies"):
		sounds.play_sfx(&"cleaver_impact", -10)


func _on_health_changed(current: int, maximum: int) -> void:
	var low := current > 0 and current <= maxi(1, floori(maximum / 3.0))
	if low and not _low_health:
		_low_health = true
		_warning.play()
	elif not low:
		_low_health = false
		_warning.stop()
		_heartbeat.stop()


func _on_health_reset() -> void:
	if _was_dead and not player.health.is_dead():
		sounds.play_sfx(&"revive", -12)
	_was_dead = player.health.is_dead()
