extends Control
## The portraits and heart display are reused from the village and Chief HUD.
const PORTRAITS = preload("res://Scenes/Village/villager_portraits.gd")
const HEARTS = preload("res://Scenes/Player/Health/heart_hud.tscn")
const CENTER := Vector2(320, 180)
var _repeat_bell := true
var _ritual := Control.new()
var _portraits: Array[TextureRect] = []

func play(max_hp: int, restored_hp: int, cue: Callable) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dark := ColorRect.new()
	dark.size = Vector2(640, 360)
	dark.color = Color(0.025, 0.022, 0.035, 0.0)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dark)
	_ritual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ritual.modulate.a = 0.0
	add_child(_ritual)
	var village := get_node("/root/VillageManager")
	for villager: Villager in village.get_villagers():
		_add_portrait(villager.display_name, false)
	for loss: Dictionary in village.get_fallen():
		_add_portrait(String(loss.name), true)

	var refill := HealthComponent.new()
	refill.base_max_health = max_hp
	refill.starting_health = 0
	add_child(refill)
	var hearts := HEARTS.instantiate() as HeartHUD
	hearts.pixel_scale = 3
	hearts.position = CENTER - Vector2(hearts.pixel_scale * 4.5 * ceili(max_hp / 2.0), 9)
	_ritual.add_child(hearts)
	hearts.bind_health(refill)
	hearts.show()
	_place_portraits(0.0)
	var curtain := create_tween().set_trans(Tween.TRANS_SINE)
	curtain.tween_property(dark, "color:a", 1.0, 0.60)
	await curtain.finished
	var sequence := create_tween().set_parallel()
	sequence.tween_property(_ritual, "modulate:a", 1.0, 0.48)
	sequence.tween_method(_place_portraits, 0.0, 1.0, 2.5)
	_play_bell(cue, -19.0)
	await sequence.finished
	if not DialogueManager.is_busy():
		DialogueManager.play("boss_revival", "Boss/revival")
		await DialogueManager.conversation_finished
	var heart_fill := create_tween()
	heart_fill.tween_interval(0.75)
	for hp in range(2, restored_hp + 2, 2):
		heart_fill.tween_callback(func():
			refill.reset_health(mini(hp, restored_hp))
			cue.call(&"geiger_counter_tick", -19.0))
		heart_fill.tween_interval(0.15)
	if heart_fill.is_running():
		await heart_fill.finished

func _play_bell(cue: Callable, volume: float) -> void:
	if not _repeat_bell:
		return
	var bell := cue.call(&"night_bell-1", volume, 0.0, true) as AudioStreamPlayer
	if bell != null:
		bell.finished.connect(_play_bell.bind(cue, -30.0), CONNECT_ONE_SHOT)

func reveal_arena() -> void:
	_repeat_bell = false
	var reveal := create_tween()
	reveal.tween_property(_ritual, "modulate:a", 0.0, 0.24)
	reveal.parallel().tween_property(self, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_SINE)
	await reveal.finished

func _add_portrait(villager_name: String, fallen: bool) -> void:
	var portrait := TextureRect.new()
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.texture = PORTRAITS.texture_for(villager_name)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.size = Vector2(29, 31)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.modulate = Color(0.55, 0.73, 0.9, 0.64) if fallen else Color.WHITE
	_ritual.add_child(portrait)
	_portraits.append(portrait)

func _place_portraits(progress: float) -> void:
	var rings := 2 if _portraits.size() > 15 else 1
	for i in _portraits.size():
		var ring := i % rings
		var count := ceili(float(_portraits.size() - ring) / rings)
		var angle := TAU * (float(i / rings) / count + progress) * (1.0 if ring == 0 else -1.0)
		var radius := lerpf(134.0, 80.0, progress) + ring * 37.0
		_portraits[i].position = CENTER + Vector2.from_angle(angle) * Vector2(radius, radius * 0.70) - _portraits[i].size * 0.5
