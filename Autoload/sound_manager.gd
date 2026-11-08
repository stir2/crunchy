extends Node
## Shared one-shots survive panel changes. Player warning loops stay on the player.
const PLAYER_AUDIO = preload("res://Scenes/Player/player_audio.gd")
const ROOT := "res://Assets/Audio/SFX/"
## Measured source peaks, before playback gain. Keep the supplied WAVs untouched.
const SOURCE_PEAK_DB := {
	&"button_click": -8.9, &"button_hover": -5.8,
	&"cleaver_impact": -0.3, &"cleaver_swing": -5.0, &"cleaver_swing_alt": -6.9,
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
	GameController.night_started.connect(func(_day: int, _flesh: int, _quota: int): play_sfx(&"night_bell-1", -12))
	VillageManager.villager_left.connect(func(_name: String, _cause: StringName):
		play_sfx(StringName("Scream%d" % (_scream_index + 1)), -14)
		_scream_index = (_scream_index + 1) % 12)
	VillageManager.refugee_waiting.connect(func(_candidate: Dictionary):
		play_sfx(StringName("Refugee%d" % (_refugee_index + 1)), -16)
		_refugee_index = (_refugee_index + 1) % 5)
	_bind_progression()


func stream_for(sound: StringName) -> AudioStream:
	if not _streams.has(sound):
		_streams[sound] = load(ROOT + String(sound) + ".wav")
	return _streams[sound]


func gain_for(sound: StringName) -> float:
	return -3.0 - float(SOURCE_PEAK_DB.get(sound, -3.0))


func play_sfx(sound: StringName, volume_db: float = -10.0, ui: bool = false) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.stream = stream_for(sound)
	audio.bus = &"SFX"
	audio.volume_db = volume_db + gain_for(sound)
	audio.process_mode = Node.PROCESS_MODE_ALWAYS if ui else Node.PROCESS_MODE_PAUSABLE
	add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()
	return audio


func next_rumble() -> AudioStream:
	var sound := StringName("monster_rumbling_%d" % (_rumble_index + 1))
	_rumble_index = (_rumble_index + 1) % 3
	return stream_for(sound)


func _on_node_added(node: Node) -> void:
	if node is BaseButton or node is Player:
		_register.call_deferred(node)


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
			if not node.disabled and node.is_visible_in_tree():
				play_sfx(&"button_click", -16, true))
		node.mouse_entered.connect(func():
			if not node.disabled and node.is_visible_in_tree() and Time.get_ticks_msec() - _last_hover_ms >= 80:
				_last_hover_ms = Time.get_ticks_msec()
				play_sfx(&"button_hover", -23, true))
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


func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
