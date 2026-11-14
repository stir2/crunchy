extends Control
## The portraits and heart display are reused from the village and Chief HUD.
const PORTRAITS = preload("res://Scenes/Village/villager_portraits.gd")
const HEARTS = preload("res://Scenes/Player/Health/heart_hud.tscn")
const CENTER := Vector2(320, 180)
var _repeat_bell := true
var _dark: ColorRect
var _ritual := Control.new()
var _portraits: Array[TextureRect] = []

func play(max_hp: int, restored_hp: int, cue: Callable) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dark = ColorRect.new()
	_dark.color = Color(0, 0, 0, 0)
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dark)
	get_viewport().size_changed.connect(_fit_backdrop, CONNECT_DEFERRED)
	_fit_backdrop()
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
	hearts.position = CENTER - Vector2(hearts.pixel_scale * (9 * ceili(max_hp / 2.0) - 2) * 0.5, 9)
	_ritual.add_child(hearts)
	hearts.bind_health(refill)
	hearts.show()
	_place_portraits(0.0)
	var curtain := create_tween().set_trans(Tween.TRANS_SINE)
	curtain.tween_property(_dark, "color:a", 1.0, 0.60)
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
	var total := _portraits.size()
	var columns := 8
	var rows := ceili(float(total) / columns)
	var rows_per_side := ceili(rows / 2.0)
	var scale_factor := minf(1.0, 2.0 / maxf(1.0, rows_per_side))
	var portrait_size := Vector2(29, 31) * scale_factor
	var spacing := (Vector2(29, 31) + Vector2(7, 6)) * scale_factor
	for i in total:
		var row := floori(float(i) / columns)
		var column := i % columns
		var count := mini(columns, total - row * columns)
		var side := -1.0 if row % 2 == 0 else 1.0
		var x := (column - (count - 1) * 0.5) * spacing.x
		var y := side * (lerpf(52.0, 33.0, progress) + floori(row / 2.0) * spacing.y)
		_portraits[i].size = portrait_size
		_portraits[i].position = CENTER + Vector2(x, y) - portrait_size * 0.5


func _fit_backdrop() -> void:
	if not is_inside_tree() or _dark == null:
		return
	# The ritual lives under a centered 640x360 HUD, but darkness covers the viewport.
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var viewport_rect := get_viewport_rect()
	_dark.position = inverse * viewport_rect.position
	_dark.size = inverse * viewport_rect.end - _dark.position
