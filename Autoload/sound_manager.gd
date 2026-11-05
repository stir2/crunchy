extends Node
## Shared one-shots survive panel changes. Player warning loops stay on the player.
const PLAYER_AUDIO = preload("res://Scenes/Player/player_audio.gd")
const ROOT := "res://Assets/Audio/SFX/"
var _streams: Dictionary = {}
var _last_hover_ms: int = -1000
var _rumble_index: int = 0
var _progression: AbyssProgressionState


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	_register_tree(get_tree().root)
	GameController.night_started.connect(func(_day: int, _flesh: int, _quota: int): play_sfx(&"night_bell", -12))
	_bind_progression()


func stream_for(sound: StringName) -> AudioStream:
	if not _streams.has(sound):
		_streams[sound] = load(ROOT + String(sound) + ".wav")
	return _streams[sound]


func play_sfx(sound: StringName, volume_db: float = -10.0, ui: bool = false) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.stream = stream_for(sound)
	audio.bus = &"SFX"
	audio.volume_db = volume_db
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
