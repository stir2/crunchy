extends Node
## Sound follows combat and health signals without changing their timing.
var _low_health: bool = false
var _was_dead: bool = false
var _death_voice: WeakRef
var _death_cue_played: bool = false
var _last_swing: int = -1
var _warning: AudioStreamPlayer
var _footsteps: Array[AudioStreamPlayer] = []
var _charge_audio: AudioStreamPlayer
var _dash_audio: AudioStreamPlayer
var _fall_audio: AudioStreamPlayer
var _fall_distance: float = 0.0
var _fall_started: bool = false
var _support_y: float = 0.0
var _airborne_peak_y: float = 0.0
var _damage_airborne: bool = false
var _landing_audio: AudioStreamPlayer
var _foot_index: int = 0
var _step_animation: StringName = &""
var _step_frame: int = -1
var _last_position := Vector2.ZERO
var _step_cooldown: float = 0.0
var _movement_duck_db: float = 0.0
var _movement_duck_hold: float = 0.0
@onready var player: Player = get_parent()
@onready var sprite: AnimatedSprite2D = player.get_node("Visuals/AnimatedSprite2D")
@onready var boss_death_mix: bool = player.has_meta(&"boss_death_mix")
@onready var sounds: Node = get_node("/root/SoundManager")


func _ready() -> void:
	_last_position = player.global_position
	_support_y = player.global_position.y
	_airborne_peak_y = _support_y
	for i in range(2):
		var foot := AudioStreamPlayer.new()
		foot.name = "Footstep%d" % i
		foot.bus = &"SFX"
		add_child(foot)
		_footsteps.append(foot)
	_fall_audio = AudioStreamPlayer.new()
	_fall_audio.name = "Freefall"
	_fall_audio.bus = &"SFX"
	_fall_audio.stream = sounds.stream_for(&"freefall")
	_fall_audio.volume_db = -22 + sounds.gain_for(&"freefall")
	add_child(_fall_audio)
	_charge_audio = _movement_voice(&"bull_rush_charge", -18)
	_dash_audio = _movement_voice(&"bull_rush", -15)
	player.movement_state_changed.connect(_on_movement_state)
	player.movement_reset.connect(_reset_steps)
	player.jumped.connect(_on_jumped)
	_landing_audio = _movement_voice(&"land_stone", -24)
	player.landed.connect(_on_landed)
	player.health.damage_received.connect(_on_player_hurt)
	_warning = AudioStreamPlayer.new()
	_warning.stream = sounds.stream_for(&"low_health_initial")
	_warning.bus = &"SFX"
	_warning.volume_db = -10 + sounds.gain_for(&"low_health_initial")
	add_child(_warning)
	player.combat.phase_changed.connect(_on_attack_phase)
	player.combat.hit_confirmed.connect(_on_hit_confirmed)
	player.health.health_changed.connect(_on_health_changed)
	player.health.died.connect(func(_hit: CombatHit):
		_was_dead = true)
	sprite.death_animation_started.connect(_on_death_animation_started)
	player.health.health_reset.connect(_on_health_reset)
	_was_dead = player.health.is_dead()
	_on_health_changed(player.health.current_health, player.health.max_health)


func _physics_process(delta: float) -> void:
	_update_movement_duck(delta)
	_update_fall(delta)
	if _charge_audio.playing and player.movement_state != Player.MovementState.DASH_CHARGING:
		_charge_audio.volume_db -= 300 * delta
		if _charge_audio.volume_db < -60:
			_charge_audio.stop()
	var distance := absf(player.global_position.x - _last_position.x)
	_last_position = player.global_position
	_step_cooldown = maxf(0, _step_cooldown - delta)
	var walking: bool = (player.is_physics_processing() and player.is_on_floor()
		and player.movement_state == Player.MovementState.NORMAL
		and absf(player.velocity.x) > 12 and player.velocity.y >= 0
		and not player.damage.is_action_locked() and not player.climbing.is_climbing()
		and not player.is_jump_movement_paused()
		and not player.combat.is_hitstopped() and not player.combat.is_swing_frozen())
	if not walking or distance > 64:
		_step_frame = -1
		_step_animation = &""
		return
	# Contacts in the supplied 21-frame walk and 15-frame run cycles.
	var frame := sprite.frame
	var animation := sprite.animation
	var changed := frame != _step_frame or animation != _step_animation
	_step_frame = frame
	_step_animation = animation
	var contact := (animation == &"walk" and frame in [0, 10]) or (animation == &"run" and frame in [0, 7])
	if changed and contact and sprite.is_playing() and _step_cooldown <= 0:
		_step_cooldown = 0.18
		var sound := _floor_sound()
		var audio := _footsteps[_foot_index % 2]
		audio.stream = sounds.stream_for(sound)
		audio.volume_db = -33 + sounds.gain_for(sound) + _movement_duck_db
		audio.pitch_scale = randf_range(0.98, 1.02)
		audio.volume_db += randf_range(-1.0, 0.0)
		audio.play(sounds.start_offset_for(sound))
		_foot_index += 1


func _reset_steps() -> void:
	_movement_duck_db = 0
	_movement_duck_hold = 0
	for foot in _footsteps:
		foot.stop()
	_last_position = player.global_position
	_step_animation = &""
	_step_frame = -1
	_step_cooldown = 0
	_fall_distance = 0
	_fall_started = false
	_support_y = player.global_position.y
	_airborne_peak_y = _support_y
	_damage_airborne = false
	_fall_audio.stop()
	_charge_audio.stop()
	_dash_audio.stop()
	_landing_audio.stop()


func _update_fall(delta: float) -> void:
	if player.is_on_floor():
		_support_y = player.global_position.y
		_airborne_peak_y = _support_y
		_damage_airborne = false
	else:
		_airborne_peak_y = minf(_airborne_peak_y, player.global_position.y)
	if player.damage.is_reacting():
		_damage_airborne = true
	if player.climbing.is_climbing():
		_support_y = player.global_position.y
	var drop := player.global_position.y - _support_y
	var falling: bool = (player.is_physics_processing() and not player.is_on_floor()
		and player.velocity.y > 0 and drop > 48 and not _damage_airborne
		and not player.health.is_dead() and not player.damage.is_action_locked()
		and player.movement_state == Player.MovementState.NORMAL
		and not player.is_jump_movement_paused()
		and not player.climbing.is_climbing() and not player.combat.is_hitstopped())
	if falling:
		_fall_distance = drop - 48
		var strength := clampf(_fall_distance / 240.0, 0, 1)
		_fall_audio.volume_db = lerpf(-28, -16, strength) + sounds.gain_for(&"freefall") + _movement_duck_db
		if not _fall_started:
			_fall_started = true
			_fall_audio.play()
	else:
		_fall_distance = 0
		_fall_started = false
		if _fall_audio.playing:
			_fall_audio.volume_db -= 300 * delta
			if _fall_audio.volume_db <= -60:
				_fall_audio.stop()


func _floor_sound() -> StringName:
	for i in range(player.get_slide_collision_count()):
		var contact := player.get_slide_collision(i)
		if contact.get_normal().dot(Vector2.UP) < 0.6:
			continue
		var collider := contact.get_collider() as Node
		if collider == null:
			continue
		var surface := StringName(collider.get_meta("footstep_surface", &"stone"))
		if collider is TileMapLayer and collider.tile_set != null:
			if collider.tile_set.get_custom_data_layer_by_name("footstep_surface") >= 0:
				var point := contact.get_position() - contact.get_normal()
				var cell: Vector2i = collider.local_to_map(collider.to_local(point))
				var data: TileData = collider.get_cell_tile_data(cell)
				if data != null:
					surface = StringName(data.get_custom_data("footstep_surface"))
		return &"footstep_wood" if surface == &"wood" else &"footstep_stone"
	return &"footstep_stone"


func _on_attack_phase(phase: int) -> void:
	if phase == PlayerCombatController.AttackState.ACTIVE and _last_swing != player.combat.swing_id:
		_last_swing = player.combat.swing_id
		sounds.play_sfx(&"cleaver_swing_alt" if sprite.animation == &"attack_alt" else &"cleaver_swing", -13)


func _on_hit_confirmed(target: CombatDamageable, _hit: CombatHit) -> void:
	_duck_movement()
	# Live enemies already play their own spatial impact sound.
	if not target.damage_owner().is_in_group("enemies"):
		sounds.play_sfx(&"cleaver_impact", -7)


func _on_health_changed(current: int, maximum: int) -> void:
	var low := current > 0 and current <= maxi(1, floori(maximum / 3.0))
	if low and not _low_health:
		_low_health = true
		_warning.play()
	elif not low:
		_low_health = false
		_warning.stop()


func _on_health_reset() -> void:
	if not player.health.is_dead():
		_death_cue_played = false
	if _was_dead and not player.health.is_dead() and not boss_death_mix:
		sounds.play_sfx(&"revive", -12)
	_was_dead = player.health.is_dead()


func _movement_voice(sound: StringName, volume_db: float) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.stream = sounds.stream_for(sound)
	audio.bus = &"SFX"
	audio.volume_db = volume_db + sounds.gain_for(sound)
	add_child(audio)
	return audio


func _on_movement_state(state: int) -> void:
	if state == Player.MovementState.DASH_CHARGING:
		_charge_audio.volume_db = -16 + sounds.gain_for(&"bull_rush_charge") + sounds.repetition_gain_for(&"bull_rush_charge")
		_charge_audio.pitch_scale = randf_range(0.94, 0.98)
		_charge_audio.play(sounds.start_offset_for(&"bull_rush_charge"))
	elif state == Player.MovementState.DASHING:
		_dash_audio.volume_db = -14 + sounds.gain_for(&"bull_rush") + sounds.repetition_gain_for(&"bull_rush")
		_dash_audio.pitch_scale = 1.0
		_dash_audio.play()


func _on_jumped() -> void:
	_support_y = player.global_position.y
	_airborne_peak_y = _support_y
	_damage_airborne = false
	sounds.play_sfx(&"jump", -17)


func _on_player_hurt(_hit: CombatHit, _amount: int) -> void:
	if not player.health.is_dead():
		sounds.play_limited(&"player_hurt", -14 if player.health.current_health <= 2 else -17, 0.25)
	_duck_movement()
	# A spike/hit reaction is not a voluntary fall, even after hit-stun expires.
	_damage_airborne = true
	_fall_started = false
	_fall_audio.stop()


func _on_landed(impact_speed: float) -> void:
	if impact_speed < 180 or player.health.is_dead():
		return
	_duck_movement()
	var height := maxf(0, player.global_position.y - _airborne_peak_y)
	var strength := clampf(height / 256.0, 0, 1)
	var wood := _floor_sound() == &"footstep_wood"
	var hard := height >= 160.0 or impact_speed >= 650.0
	var surface: StringName
	if hard:
		surface = &"hard_land_wood" if wood else &"hard_land_stone"
	else:
		surface = &"land_wood" if wood else &"land_stone"
	_landing_audio.stream = sounds.stream_for(surface)
	_landing_audio.pitch_scale = lerpf(1.0, 0.86, strength) * randf_range(0.98, 1.02)
	_landing_audio.volume_db = lerpf(-25, -13, strength) + sounds.gain_for(surface)
	_landing_audio.play()
	_step_cooldown = 0.2


func _duck_movement() -> void:
	# Repeated impacts extend the brief hold; they never deepen the dip.
	_movement_duck_hold = 0.1


func _update_movement_duck(delta: float) -> void:
	_movement_duck_hold = maxf(0, _movement_duck_hold - delta)
	var previous := _movement_duck_db
	var target := -1.5 if _movement_duck_hold > 0 else 0.0
	_movement_duck_db = move_toward(previous, target, (30.0 if target < previous else 6.0) * delta)
	for foot in _footsteps:
		if foot.playing:
			foot.volume_db += _movement_duck_db - previous


func death_playback_position() -> float:
	var voice: AudioStreamPlayer = _death_voice.get_ref() if _death_voice != null else null
	if not is_instance_valid(voice): return -1.0
	if not voice.playing: return voice.stream.get_length()
	return voice.get_playback_position() + AudioServer.get_time_since_last_mix()


func _on_death_animation_started() -> void:
	if _death_cue_played or not player.health.is_dead(): return
	_death_cue_played = true
	var voice: AudioStreamPlayer = sounds.play_sfx(&"death", -12)
	_death_voice = weakref(voice)
	if boss_death_mix:
		var level := voice.volume_db
		voice.volume_db = level - 24.0
		voice.create_tween().tween_property(voice, "volume_db", level, 0.45)
