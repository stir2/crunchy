extends Node
## Persistent scene music. The abyss pair shares one sample-locked playback clock.
const MENU := "res://Assets/Audio/Music/theme_mainmenu.wav"
const ABYSS := "res://Assets/Audio/Music/theme_abyss.wav"
const ABYSS_LOW := "res://Assets/Audio/Music/theme_abyss_lowhealth.wav"
const LOW_STEM_GAIN_DB := 14.0 # The supplied filtered stem is substantially quieter.
const CROSSFADE_SECONDS := 0.65
const LOW_HEALTH_DUCK_DB := 8.0
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

func _process(delta: float) -> void:
	var main := get_tree().current_scene
	var route := ""
	var actor: Player
	var reviving := false
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
		elif path in ["res://Scenes/Underground/abyss_runtime.tscn", "res://Scenes/Boss/boss_arena.tscn"]:
			actor = active.get("player") as Player
			reviving = active.get("_reviving") == true
			if is_instance_valid(actor) and (not actor.health.is_dead() or reviving) and active.get("_ending") != true:
				route = "abyss"
	if route != _route: _set_route(route)
	_bind_player(actor)
	# Duck both stems so the warning cuts through during the crossfade too.
	var duck_db := LOW_HEALTH_DUCK_DB if _route == "abyss" and _low_health else 0.0
	if reviving:
		duck_db = 18.0
	_voice.volume_db = move_toward(_voice.volume_db, _target_gain - duck_db, delta * (36.0 if reviving else 120.0))
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
	else:
		_pair = AudioStreamSynchronized.new()
		_pair.stream_count = 2
		_pair.set_sync_stream(0, _looping_stream(ABYSS))
		_pair.set_sync_stream(1, _looping_stream(ABYSS_LOW))
		_pair.set_sync_stream_volume(0, 0)
		_pair.set_sync_stream_volume(1, -80)
		_voice.stream = _pair
		_target_gain = -18
	_voice.volume_db = -80
	_voice.play()

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
