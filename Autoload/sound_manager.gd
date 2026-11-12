extends Node
## Shared one-shots survive panel changes. Player warning loops stay on the player.
const MUSIC_CONTROLLER = preload("res://Autoload/music_controller.gd")
const PLAYER_AUDIO = preload("res://Scenes/Player/player_audio.gd")
const ROOT := "res://Assets/Audio/SFX/"
const SOUND_PATHS := {
	&"spider_death": "Enemies/spider_death.wav",
	&"spider_hiss": "Enemies/spider_hiss.wav",
	&"spider_hit": "Enemies/spider_hit.wav",
	&"spider_spit": "Enemies/spider_spit.wav",
	&"spider_walk": "Enemies/spider_walk.wav",
	&"web_hit": "Enemies/web_hit.wav",
	&"zombie_atk": "Enemies/zombie_atk.wav",
	&"zombie_atk_windup": "Enemies/zombie_atk_windup.wav",
	&"zombie_death": "Enemies/zombie_death.wav",
	&"zombie_hit": "Enemies/zombie_hit.wav",
	&"zombie_step_stone": "Movement/footstep_stone.wav",
	&"zombie_step_wood": "Movement/footstep_wood.wav",
	&"zombie_drag_stone": "Movement/land_stone.wav",
	&"zombie_drag_wood": "Movement/land_wood.wav",
	&"boss_death": "Monster/boss_death.wav",
	&"boss_hand_drag": "Monster/boss_hand_drag.wav",
	&"boss_hurt": "Monster/boss_hurt.wav",
	&"boss_slam": "Monster/boss_slam.wav",
	&"boss_spit": "Monster/boss_spit.wav",
	&"boss_stab_creak": "Monster/boss_stab_creak.wav",
	&"boss_stab_warning": "Monster/boss_stab_warning.wav",
	&"boss_summon": "Monster/boss_summon.wav",
	&"checkpoint": "Progression/checkpoint.wav",
	&"parry": "Combat/parry.wav",
	&"flesh_collect": "Progression/flesh_collect.wav",
	&"flesh_bank": "Progression/flesh_bank.wav",
	&"collect_grave": "Progression/collect_grave.wav",
	&"error": "UI/error.wav",
	&"player_hurt": "Player/player_hurt.wav",
	&"button_click": "UI/button_click.wav",
	&"button_hover": "UI/button_hover.wav",
	&"open_ledger": "UI/open_ledger.wav",
	&"close_ledger": "UI/close_ledger.wav",
	&"panel_transition": "UI/panel_transition.wav",
	&"play_button": "UI/play_button.wav",
	&"purchase": "UI/purchase.wav",
	&"cleaver_swing": "Combat/cleaver_swing.wav",
	&"cleaver_swing_alt": "Combat/cleaver_swing_alt.wav",
	&"cleaver_impact": "Combat/cleaver_impact.wav",
	&"footstep_stone": "Movement/footstep_stone-1.wav",
	&"footstep_wood": "Movement/footstep_wood-1.wav",
	&"jump": "Movement/jump.wav",
	&"land_stone": "Movement/land_stone-1.wav",
	&"land_wood": "Movement/land_wood-1.wav",
	&"hard_land_stone": "Movement/hard_land_stone.wav",
	&"hard_land_wood": "Movement/hard_land_wood.wav",
	&"freefall": "Movement/freefall-1.wav",
	&"bull_rush_charge": "Movement/bull_rush_charge.wav",
	&"bull_rush": "Movement/bull_rush.wav",
	&"low_health_initial": "Player/low_health_initial.wav",
	&"low_health": "Player/low_health.wav",
	&"death": "Player/death.wav",
	&"revive": "Player/revive.wav",
	&"key_fragment_pickup": "Progression/key_fragment_pickup.wav",
	&"key_merge": "Progression/key_merge.wav",
	&"gate_unlock": "Progression/gate_unlock.wav",
	&"geiger_counter_tick": "Quota/geiger_counter_tick.wav",
	&"toll_impact": "Quota/toll_impact.wav",
	&"monster_rumbling_1": "Monster/monster_rumbling_1.wav",
	&"monster_rumbling_2": "Monster/monster_rumbling_2.wav",
	&"monster_rumbling_3": "Monster/monster_rumbling_3.wav",
	&"Scream1": "Village/Screams/scream_01.wav",
	&"Scream2": "Village/Screams/scream_02.wav",
	&"Scream3": "Village/Screams/scream_03.wav",
	&"Scream4": "Village/Screams/scream_04.wav",
	&"Scream5": "Village/Screams/scream_05.wav",
	&"Scream6": "Village/Screams/scream_06.wav",
	&"Scream7": "Village/Screams/scream_07.wav",
	&"Scream8": "Village/Screams/scream_08.wav",
	&"Scream9": "Village/Screams/scream_09.wav",
	&"Scream10": "Village/Screams/scream_10.wav",
	&"Scream11": "Village/Screams/scream_11.wav",
	&"Scream12": "Village/Screams/scream_12.wav",
	&"Refugee1": "Village/Refugees/refugee_01.wav",
	&"Refugee2": "Village/Refugees/refugee_02.wav",
	&"Refugee3": "Village/Refugees/refugee_03.wav",
	&"Refugee4": "Village/Refugees/refugee_04.wav",
	&"Refugee5": "Village/Refugees/refugee_05.wav",
	&"night_bell-1": "Village/Bells/night_bell.wav",
	&"night_bell": "Unused/night_bell_original.wav",
}
## Measured source peaks, before playback gain. Keep the supplied WAVs untouched.
const SOURCE_PEAK_DB := {
	&"spider_death": -21.78, &"spider_hiss": -15.38, &"spider_hit": -13.24, &"spider_spit": -9.28, &"spider_walk": -26.25,
	&"web_hit": -12.12, &"zombie_atk": -18.52, &"zombie_atk_windup": -14.76, &"zombie_death": -16.04, &"zombie_hit": -7.17,
	&"zombie_step_stone": -14.85, &"zombie_step_wood": -14.08, &"zombie_drag_stone": -4.31, &"zombie_drag_wood": -9.07,
	&"boss_death": 2.24, &"boss_hand_drag": -0.33, &"boss_hurt": -23.82, &"boss_slam": 1.28,
	&"boss_spit": -12.50, &"boss_stab_creak": -12.58, &"boss_stab_warning": -19.79, &"boss_summon": -21.35,
	&"checkpoint": -11.98, &"parry": 0.82, &"flesh_collect": -11.14,
	&"flesh_bank": -7.19, &"collect_grave": -15.55, &"error": -18.39, &"player_hurt": -2.22,
	&"bull_rush_charge": -20.61, &"bull_rush": 0.34, &"freefall": -18.55, &"jump": -12.91, &"gate_unlock": -9.23,
	&"land_stone": -6.59, &"land_wood": -12.13,
	&"hard_land_stone": 2.54, &"hard_land_wood": 0.54,
	&"footstep_stone": -19.24, &"footstep_wood": -17.81,
	&"button_click": -8.9, &"button_hover": -5.8,
	&"cleaver_impact": -0.3, &"cleaver_swing": -4.95, &"cleaver_swing_alt": -6.78,
	&"open_ledger": -14.8, &"close_ledger": -27.6, &"panel_transition": -24.3,
	&"purchase": -17.9, &"revive": -17.4,
	&"low_health": -16.0, &"low_health_initial": 0.0,
	&"key_fragment_pickup": -11.7, &"key_merge": -3.6,
	&"geiger_counter_tick": -7.7, &"toll_impact": -2.5,
	&"night_bell": -11.2, &"night_bell-1": -0.8, &"play_button": -0.9, &"death": 0.0,
	&"monster_rumbling_1": -32.5, &"monster_rumbling_2": -15.7, &"monster_rumbling_3": -8.0,
	&"Refugee1": -8.5, &"Refugee2": -1.9, &"Refugee3": -9.3, &"Refugee4": -3.2, &"Refugee5": -2.2,
	&"Scream1": -2.5, &"Scream2": 0.0, &"Scream3": -5.3, &"Scream4": -14.1,
	&"Scream5": -6.1, &"Scream6": -1.2, &"Scream7": -6.1, &"Scream8": 0.0,
	&"Scream9": -10.0, &"Scream10": -4.3, &"Scream11": -2.9, &"Scream12": 0.0,
}
# Skip quiet source padding without editing the supplied recordings.
const START_OFFSETS := {
	&"checkpoint": 0.16, &"flesh_collect": 0.04, &"collect_grave": 0.025,
	&"open_ledger": 0.32,
	&"gate_unlock": 0.46, &"key_fragment_pickup": 0.38, &"key_merge": 0.17,
	&"bull_rush_charge": 0.03, &"purchase": 0.10, &"geiger_counter_tick": 0.055, &"jump": 0.015,
	&"boss_stab_creak": 0.13, &"boss_summon": 0.22,
}
const CUE_ENDS := {
	&"play_button": 1.8, &"night_bell-1": 4.6,
}
var transition_cues: Array[StringName] = []
var _transition_losses: Array[Dictionary] = []
var _last_motion_ms: int = -1000
var _repeat_history: Dictionary = {}
var _limited_times: Dictionary = {}
var _greeting: AudioStreamPlayer
var _ui_voices: Dictionary = {}
var _streams: Dictionary = {}
var _last_hover_ms: int = -1000
var _rumble_index: int = 0
var _progression: AbyssProgressionState
var _scream_index: int = 0
var _refugee_index: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	_register_tree(get_tree().root)
	# Simulation queues night cues; the black-screen presentation owns playback.
	GameController.night_started.connect(func(_day: int, _flesh: int, _quota: int):
		transition_cues.push_front(&"night_bell-1"))
	VillageManager.villager_left.connect(func(villager_name: String, cause: StringName):
		_transition_losses.append({"name": villager_name, "cause": cause})
		transition_cues.append(StringName("Scream%d" % (_scream_index + 1)))
		_scream_index = (_scream_index + 1) % 12)
	for sound in [&"button_click", &"button_hover", &"panel_transition", &"open_ledger", &"close_ledger"]:
		stream_for(sound)
	_bind_progression()
	var music := MUSIC_CONTROLLER.new()
	music.name = "MusicController"
	add_child(music)


func stream_for(sound: StringName) -> AudioStream:
	if not SOUND_PATHS.has(sound):
		push_error("Unknown sound: %s" % sound)
		return null
	if not _streams.has(sound):
		_streams[sound] = load(ROOT + String(SOUND_PATHS[sound]))
	return _streams[sound]


func gain_for(sound: StringName) -> float:
	return -6.0 - float(SOURCE_PEAK_DB.get(sound, -3.0))


func play_sfx(sound: StringName, volume_db: float = -10.0, ui: bool = false) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.stream = stream_for(sound)
	audio.bus = &"SFX"
	audio.volume_db = volume_db + gain_for(sound) + repetition_gain_for(sound)
	audio.pitch_scale = pitch_for(sound)
	audio.process_mode = Node.PROCESS_MODE_ALWAYS if ui else Node.PROCESS_MODE_PAUSABLE
	add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play(start_offset_for(sound))
	return audio


func next_rumble() -> AudioStream:
	var sound := StringName("monster_rumbling_%d" % (_rumble_index + 1))
	_rumble_index = (_rumble_index + 1) % 3
	return stream_for(sound)


func _on_node_added(node: Node) -> void:
	if node is BaseButton or node is Player:
		_register_pending.call_deferred(weakref(node))


func _register_pending(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node
	if node != null:
		_register(node)


func _register_tree(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_register_tree(child)


func _register(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or node.has_meta("sfx_registered"):
		return
	node.set_meta("sfx_registered", true)
	if node is BaseButton:
		node.button_down.connect(func():
			if not node.disabled and node.is_visible_in_tree() and not node.get_meta("own_click_sound", false):
				play_ui(&"button_click", -24))
		node.mouse_entered.connect(func():
			var now := Time.get_ticks_msec()
			if not node.disabled and node.is_visible_in_tree() and now - _last_hover_ms >= 160 and now - _last_motion_ms < 120:
				_last_hover_ms = now
				play_ui(&"button_hover", -31))
	elif node is Player:
		var audio := PLAYER_AUDIO.new()
		audio.name = "PlayerAudio"
		node.add_child(audio)


func _process(_delta: float) -> void:
	# New runs and Continue replace the state object; loading itself stays silent.
	if _progression != GameController.abyss_progression_state:
		_bind_progression()


func _bind_progression() -> void:
	_progression = GameController.abyss_progression_state
	_progression.fragment_collected.connect(func(): play_sfx(&"key_fragment_pickup", -10))
	_progression.key_assembled.connect(func(): play_sfx(&"key_merge", -10))
	_progression.gate_unlocked.connect(func(): play_sfx(&"gate_unlock", -10))


func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null


func start_offset_for(sound: StringName) -> float:
	return float(START_OFFSETS.get(sound, 0.0))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_last_motion_ms = Time.get_ticks_msec()


func play_ui(sound: StringName, volume_db: float) -> void:
	# Repeated navigation replaces its own tail instead of layering more noise.
	var reference := _ui_voices.get(sound) as WeakRef
	var previous: AudioStreamPlayer = reference.get_ref() if reference != null else null
	if is_instance_valid(previous):
		previous.stop()
		previous.queue_free()
	_ui_voices[sound] = weakref(play_sfx(sound, volume_db, true))


func greet_refugee() -> void:
	if is_instance_valid(_greeting):
		_greeting.stop()
		_greeting.queue_free()
	_greeting = play_sfx(StringName("Refugee%d" % (_refugee_index + 1)), -22, true)
	_refugee_index = (_refugee_index + 1) % 5


func queue_start_cue() -> void:
	_transition_losses.clear()
	transition_cues.assign([&"play_button"])


func play_transition_cues(host: Node) -> void:
	if is_instance_valid(_greeting):
		_greeting.stop()
		_greeting.queue_free()
	for reference: WeakRef in _ui_voices.values():
		var voice: AudioStreamPlayer = reference.get_ref()
		if is_instance_valid(voice):
			voice.stop()
			voice.queue_free()
	_ui_voices.clear()
	var notice: Control
	var losses := take_transition_losses()
	var cues := transition_cues.duplicate()
	transition_cues.clear()
	for sound: StringName in cues:
		if not is_instance_valid(host) or not host.is_inside_tree():
			return
		if String(sound).begins_with("Scream") and notice == null and not losses.is_empty():
			notice = preload("res://Scenes/Cutscene/villager_loss_notice.gd").new()
			notice.losses = losses
			host.add_child(notice)
		var audio := AudioStreamPlayer.new()
		audio.stream = stream_for(sound)
		audio.bus = &"SFX"
		audio.volume_db = (-14 if sound in [&"play_button", &"night_bell-1"] else -16) + gain_for(sound)
		host.add_child(audio)
		audio.play()
		var duration: float = audio.stream.get_length() if String(sound).begins_with("Scream") else minf(audio.stream.get_length(), CUE_ENDS.get(sound, audio.stream.get_length()))
		var cue := host.create_tween()
		cue.tween_interval(maxf(0.01, duration - 0.15))
		cue.tween_property(audio, "volume_db", -70.0, 0.15)
		await cue.finished
		audio.queue_free()
		if sound != &"play_button" and not String(sound).begins_with("Scream"):
			await host.get_tree().create_timer(0.35, false).timeout
	if is_instance_valid(notice):
		await host.get_tree().create_timer(0.6, false).timeout
		await notice.fade_out()
		notice.queue_free()


func take_transition_losses() -> Array[Dictionary]:
	var losses := _transition_losses.duplicate()
	_transition_losses.clear()
	return losses


func pitch_for(sound: StringName) -> float:
	if sound in [&"jump", &"cleaver_swing", &"cleaver_swing_alt", &"cleaver_impact"]:
		return randf_range(0.97, 1.03)
	if sound in [&"button_click", &"button_hover", &"panel_transition", &"purchase"]:
		return randf_range(0.98, 1.02)
	return 1.0


func repetition_gain_for(sound: StringName) -> float:
	if sound not in [&"jump", &"bull_rush", &"bull_rush_charge"]:
		return 0.0
	var now := Time.get_ticks_msec()
	var recent: Dictionary = _repeat_history.get(sound, {"time": -10000, "count": 0})
	var count: int = mini(4, int(recent.count) + 1) if now - int(recent.time) < 1100 else 0
	_repeat_history[sound] = {"time": now, "count": count}
	return -float(count)


func play_limited(sound: StringName, volume_db: float, interval: float = 0.12) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_limited_times.get(sound, -10000)) < interval * 1000:
		return
	_limited_times[sound] = now
	play_sfx(sound, volume_db)


func play_varied(sound: StringName, volume_db: float, pitch_min: float, pitch_max: float, start_offset: float = 0.0, bus: StringName = &"SFX") -> AudioStreamPlayer:
	var stream := stream_for(sound)
	if stream == null:
		return null
	var audio := AudioStreamPlayer.new()
	audio.stream = stream
	audio.bus = bus
	audio.volume_db = volume_db + gain_for(sound)
	audio.pitch_scale = randf_range(pitch_min, pitch_max)
	audio.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play(clampf(start_offset, 0.0, maxf(0.0, stream.get_length() - 0.02)))
	return audio
