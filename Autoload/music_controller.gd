extends Node
## Persistent scene music. The abyss pair shares one sample-locked playback clock.
const MENU := "res://Assets/Audio/Music/theme_mainmenu.wav"
const ABYSS := "res://Assets/Audio/Music/theme_abyss.wav"
const VILLAGE := "res://Assets/Audio/Music/theme_village.wav"
const BOSS := "res://Assets/Audio/Music/theme_abyss_boss.wav"
const ABYSS_LOW := "res://Assets/Audio/Music/theme_abyss_lowhealth.wav"
const LOW_STEM_GAIN_DB := 14.0 # The supplied filtered stem is substantially quieter.
const CROSSFADE_SECONDS := 0.65
const LOW_HEALTH_DUCK_DB := 3.0
const BOSS_DOWNBEAT := 12.38
var _village_filter: AudioEffectLowPassFilter
var _boss_filter: AudioEffectLowPassFilter
var _boss_owner: Node
var _boss_cue := &""
var _pickup_started := false
const LANDING_HOLD_SECONDS := 1.25
const SUMMON_DUCK_SECONDS := 1.0
const SUMMON_DUCK_DB := 4.0
var _summon_duck_left := 0.0
const VOLLEY_PULSE_SECONDS := 0.18
const TOLL_PULSE_SECONDS := 0.28
var _release_left := 0.0
var _landing_left := 0.0
var _boss_was_reviving := false
var _voice: AudioStreamPlayer
var _pair: AudioStreamSynchronized
var _route := ""
var _player: Player
var _low_health := false
var _stem_amount := 0.0
var _target_gain := -80.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_voice = AudioStreamPlayer.new()
	_voice.name = "Music"
	_voice.bus = &"Music"
	_voice.volume_db = -80
	add_child(_voice)
	var bus := AudioServer.get_bus_index(&"BossMusic")
	if bus >= 0:
		_boss_filter = AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter

	var village_bus := AudioServer.get_bus_index(&"VillageMusic")
	if village_bus >= 0:
		_village_filter = AudioServer.get_bus_effect(village_bus, 0) as AudioEffectLowPassFilter

func _process(delta: float) -> void:
	var main := get_tree().current_scene
	var route := ""
	var actor: Player
	var reviving := false
	var boss_arena := false
	var boss: Node
	var village_room := &"desk"
	if is_instance_valid(main):
		var path := main.scene_file_path
		var active: Node = main
		var active_path: Variant = main.get("active_path")
		if active_path is String:
			path = active_path
		var child: Variant = main.get("active_scene")
		if child is Node: active = child
		if path == "res://Scenes/Menus/main_menu.tscn":
			route = "menu"
		elif path == "res://Scenes/Village/House/house.tscn":
			route = "village"
			village_room = active.music_room()
			if village_room == &"credits":
				route = "credits"
		elif path in ["res://Scenes/Underground/abyss_runtime.tscn", "res://Scenes/Boss/boss_arena.tscn"]:
			boss_arena = path == "res://Scenes/Boss/boss_arena.tscn"
			if boss_arena: boss = active
			actor = active.get("player") as Player
			reviving = active.get("_reviving") == true
			if is_instance_valid(actor) and (not actor.health.is_dead() or reviving) and active.get("_ending") != true:
				route = "boss" if boss_arena else "abyss"
	if route != _route: _set_route(route)
	_bind_player(actor)
	if boss != _boss_owner:
		_boss_owner = boss
		_boss_cue = &""
		_pickup_started = false
		_release_left = 0.0
		_landing_left = 0.0
		_summon_duck_left = 0.0
	if boss_arena:
		_voice.bus = &"BossMusic"
	elif route == "village":
		_voice.bus = &"VillageMusic"
	elif not route.is_empty():
		_voice.bus = &"Music"
	if _boss_was_reviving and not reviving:
		_boss_cue = &""
	_boss_was_reviving = reviving
	_release_left = maxf(0.0, _release_left - delta)
	_landing_left = maxf(0.0, _landing_left - delta)
	var cue := _boss_cue if route == "boss" and not reviving else &""
	var landing_mix := _landing_left > 0.0 or cue == &"pickup"
	var resting_cutoff := 8000.0 if boss_arena and _low_health and not landing_mix else 20000.0
	var cutoff := resting_cutoff
	var event_gain := 0.0
	match cue:
		&"fall":
			event_gain = -35.0
			cutoff = 1000.0
		&"pickup":
			var approach := smoothstep(BOSS_DOWNBEAT - 2.0, BOSS_DOWNBEAT - 0.12, _voice.get_playback_position())
			event_gain = lerpf(-28.0, 0.0, approach)
			cutoff = lerpf(1200.0, resting_cutoff, approach)
		&"last_toll":
			event_gain = -4.0
			cutoff = minf(resting_cutoff, 3500.0)
		&"toll_release":
			var pulse := _release_left / TOLL_PULSE_SECONDS
			cutoff = lerpf(resting_cutoff, 850.0, pulse)
		&"volley_release":
			var pulse := _release_left / VOLLEY_PULSE_SECONDS
			cutoff = lerpf(resting_cutoff, 1700.0, pulse)
	if route == "village":
		if _village_music_stopped():
			_voice.stop()
			return
		if not _voice.playing:
			_voice.volume_db = _target_gain
			_voice.play()
		var room_cutoff := 11500.0
		match village_room:
			&"window":
				room_cutoff = 18500.0
				event_gain = -2.0
			&"stairs":
				room_cutoff = 4600.0
				event_gain = -1.8
		if _village_filter != null:
			_village_filter.cutoff_hz = lerpf(_village_filter.cutoff_hz, room_cutoff, 1.0 - exp(-5.0 * delta))
	if _boss_filter != null:
		_boss_filter.cutoff_hz = lerpf(_boss_filter.cutoff_hz, cutoff, 1.0 - exp(-14.0 * delta))
	# Duck both stems so the warning cuts through during the crossfade too.
	var duck_db := (1.5 if boss_arena else LOW_HEALTH_DUCK_DB) if _route in ["abyss", "boss"] and _low_health and not landing_mix else 0.0
	_summon_duck_left = maxf(0.0, _summon_duck_left - delta)
	if route == "boss":
		duck_db += SUMMON_DUCK_DB * smoothstep(0.0, 0.25, _summon_duck_left)
	if reviving:
		duck_db = 70.0
	var fade_speed := 105.0 if reviving else 85.0
	if boss_arena and _boss_cue == &"victory":
		fade_speed = 16.0
	_voice.volume_db = move_toward(_voice.volume_db, _target_gain + event_gain - duck_db, delta * fade_speed)
	if _route.is_empty() and _voice.volume_db <= -80 and _voice.stream != null:
		_voice.stop()
		_voice.stream = null
		_pair = null
	if _pair != null:
		_stem_amount = move_toward(_stem_amount, 1.0 if _low_health else 0.0, delta / CROSSFADE_SECONDS)
		var normal_gain := linear_to_db(1.0 - _stem_amount) if _stem_amount < 1 else -80.0
		var filtered_gain := linear_to_db(_stem_amount) + LOW_STEM_GAIN_DB if _stem_amount > 0 else -80.0
		_pair.set_sync_stream_volume(0, normal_gain)
		_pair.set_sync_stream_volume(1, filtered_gain)

func boss_music_cue(arena: Node, cue: StringName, time_until_impact := 0.0) -> void:
	if arena != _boss_owner or _route != "boss":
		return
	if cue == &"summon":
		_summon_duck_left = SUMMON_DUCK_SECONDS
		return
	if cue == &"pickup":
		if _pickup_started:
			return
		_pickup_started = true
		_voice.volume_db = -55.0
		var output_latency := AudioServer.get_output_latency() + AudioServer.get_time_to_next_mix()
		_voice.play(maxf(0.0, BOSS_DOWNBEAT - time_until_impact + output_latency))
	match cue:
		&"landing": _landing_left = LANDING_HOLD_SECONDS
		&"toll_release": _release_left = TOLL_PULSE_SECONDS
		&"volley_release": _release_left = VOLLEY_PULSE_SECONDS
	_boss_cue = cue

func _set_route(route: String) -> void:
	_route = route
	if route.is_empty():
		_target_gain = -80
		return
	_voice.stop()
	_pair = null
	_stem_amount = 0
	if route == "menu":
		_voice.stream = _looping_stream(MENU)
		_target_gain = 6
	elif route == "village":
		_voice.stream = _looping_stream(VILLAGE)
		_target_gain = -12.0
	elif route == "boss":
		_voice.stream = _looping_stream(BOSS)
		_target_gain = -10
	elif route == "credits":
		_voice.stream = _looping_stream(ABYSS)
		_target_gain = -14
	else:
		_pair = AudioStreamSynchronized.new()
		_pair.stream_count = 2
		_pair.set_sync_stream(0, _looping_stream(ABYSS))
		_pair.set_sync_stream(1, _looping_stream(ABYSS_LOW))
		_pair.set_sync_stream_volume(0, 0)
		_pair.set_sync_stream_volume(1, -80)
		_voice.stream = _pair
		_target_gain = -14
	_voice.volume_db = _target_gain if route == "village" else -80
	if route != "village" or not _village_music_stopped():
		_voice.play()


func _village_music_stopped() -> bool:
	return GameController.is_final_day() and not GameController.boss_defeated


func _looping_stream(path: String) -> AudioStreamWAV:
	var stream := (load(path) as AudioStreamWAV).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	return stream

func _bind_player(actor: Player) -> void:
	if actor == _player: return
	if is_instance_valid(_player) and _player.health.health_changed.is_connected(_health_changed):
		_player.health.health_changed.disconnect(_health_changed)
	_player = actor
	_low_health = false
	if is_instance_valid(_player):
		_player.health.health_changed.connect(_health_changed)
		_health_changed(_player.health.current_health, _player.health.max_health)

func _health_changed(current: int, maximum: int) -> void:
	_low_health = current > 0 and current <= maxi(1, floori(maximum / 3.0))

func _exit_tree() -> void:
	if is_instance_valid(_voice):
		_voice.stop()
		_voice.stream = null
