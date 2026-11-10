extends Node2D
## Day 10 arm encounter; also runnable directly with F6 for tuning.
const ARENA := "res://Scenes/Boss/boss_arena.tscn"
const HOUSE := "res://Scenes/Village/House/house.tscn"
const MOVEMENT_FX = preload("res://Scenes/Player/movement_effect_frames.tres")
const TILES = preload("res://Assets/Tiles/room_placeholders.tres")
const HEARTS = preload("res://Scenes/Player/Health/heart_hud.tscn")
var active_path := ARENA
var _pause_menu: CanvasLayer
var _ending := false
var _shake := 0.0
var _shake_time := 0.0
var _pause_tick := -1
var _entry_health := 6
var _entry_stamina := 100.0
var _result: PanelContainer
var _result_title: Label
var _retry_button: Button
var _boss_bar: ProgressBar
var _hud: Control
@onready var player: Player = $Player
@onready var monster: Node2D = $Monster
@onready var camera: Camera2D = $Camera2D

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_floor()
	_build_hud()
	var game := get_node("/root/GameController")
	player.health.base_max_health = int(game.stats.get("max_health", 6))
	_entry_health = clampi(game.health, 1, player.health.max_health)
	player.health.reset_health(_entry_health)
	player.combat.attack_damage = int(game.stats.get("damage", 10))
	player.run_speed *= 1.0 + float(game.stats.get("speed", 0)) / 100.0
	player.stamina.max_stamina = float(game.stats.get("max_stamina", 100))
	_entry_stamina = clampf(game.stamina, 0, player.stamina.max_stamina)
	player.stamina.reset_stamina(_entry_stamina)
	player.stamina.regeneration_per_second *= 1.0 + get_node("/root/VillageManager").get_effect("stamina_regen_pct") / 100.0
	player.get_node("InteractionController").set_enabled(false)
	player.reset_movement()
	$Waves.completed.connect(monster.finish_waves)
	$Waves.spawn_warning.connect(func(point: Vector2): _ground_impact(point, false))
	monster.waves_requested.connect(func(): $Waves.start(player))
	monster.set_target(player)
	monster.ground_impact.connect(_ground_impact)
	monster.health.health_changed.connect(_boss_health_changed)
	monster.defeated.connect(_boss_defeated)
	monster.defeat_finished.connect(func(): _show_result("The monster falls"))
	player.health.died.connect(_player_died)
	player.get_node("Visuals/AnimatedSprite2D").death_animation_finished.connect(_player_death_finished)
	_boss_health_changed(monster.health.current_health, monster.health.max_health)
	get_viewport().size_changed.connect(_fit_view)
	_fit_view()
	if get_parent() == get_tree().root:
		_pause_menu = preload("res://Scenes/Menus/pause_menu.tscn").instantiate()
		add_child(_pause_menu)
	monster.modulate.a = 0.0
	create_tween().tween_property(monster, "modulate:a", 1.0, 1.1)

func _build_floor() -> void:
	var tiles: TileMapLayer = $Terrain
	tiles.tile_set = TILES
	for x in range(-1, 41):
		for y in range(19, 24):
			tiles.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	for y in range(-1, 19):
		tiles.set_cell(Vector2i(-1, y), 0, Vector2i.ZERO)
		tiles.set_cell(Vector2i(40, y), 0, Vector2i.ZERO)

func _build_hud() -> void:
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.size = Vector2(640, 360)
	$HUD.add_child(_hud)
	var hearts := HEARTS.instantiate()
	hearts.position = Vector2(12, 12)
	hearts.health_path = NodePath("")
	_hud.add_child(hearts)
	hearts.bind_health(player.health)
	_boss_bar = ProgressBar.new()
	_boss_bar.position = Vector2(180, 12)
	_boss_bar.show_percentage = false
	for key in ["background", "fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("922e54") if key == "fill" else Color("261d2b")
		_boss_bar.add_theme_stylebox_override(key, style)
	_hud.add_child(_boss_bar)
	_boss_bar.size = Vector2(280, 5)
	_result = PanelContainer.new()
	_result.position = Vector2(16, 208)
	_result.custom_minimum_size = Vector2(216, 0)
	_result.theme = preload("res://Scenes/Menus/menu_style.gd").make_theme(0.67)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	_result.add_child(column)
	_result_title = Label.new()
	_result_title.add_theme_font_size_override("font_size", 15)
	column.add_child(_result_title)
	column.add_child(HSeparator.new())
	for spec in [["Fight again", _retry], ["Return home", _return_home]]:
		var button := Button.new()
		button.text = spec[0]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(spec[1])
		if spec[1] == _retry:
			_retry_button = button
		column.add_child(button)
	_hud.add_child(_result)
	_result.hide()

func _fit_view() -> void:
	if not is_inside_tree() or not is_instance_valid(_hud): return
	var viewport_size := get_viewport_rect().size
	var factor := minf(viewport_size.x / 640.0, viewport_size.y / 360.0)
	camera.zoom = Vector2.ONE * factor
	_hud.scale = Vector2.ONE * factor
	_hud.position = (viewport_size - Vector2(640, 360) * factor) * 0.5

func _process(delta: float) -> void:
	_shake_time += delta
	_shake = move_toward(_shake, 0, delta * 10)
	camera.offset = Vector2(sin(_shake_time * 53), cos(_shake_time * 71)) * _shake

func _ground_impact(point: Vector2, heavy: bool) -> void:
	var dust := AnimatedSprite2D.new()
	dust.sprite_frames = MOVEMENT_FX
	dust.position = point
	dust.offset = Vector2(-2, -15)
	dust.scale = Vector2.ONE * (1.5 if heavy else 0.8)
	dust.modulate = Color(0.7, 0.65, 0.75, 0.7)
	$Effects.add_child(dust)
	dust.animation_finished.connect(dust.queue_free)
	dust.play(&"land")
	if heavy:
		_shake = 2.2
		get_node("/root/SoundManager").play_limited(&"land_stone", -14, 0.15)

func _boss_health_changed(current: int, maximum: int) -> void:
	_boss_bar.max_value = maximum
	_boss_bar.value = current

func _boss_defeated() -> void:
	if _ending: return
	_ending = true
	if get_tree().current_scene != self:
		get_node("/root/GameController").boss_defeated = true
	_retry_button.hide()
	_boss_bar.hide()
	$Waves.stop()
	player.combat.actions_enabled = false
	player.combat.interrupt()
	player.get_node("Hurtbox").invulnerable = true
	_shake = 2.5

func _player_died(_hit: CombatHit) -> void:
	if _ending: return
	_ending = true
	$Waves.stop()
	monster.stop_attacks()

func _player_death_finished() -> void:
	if player.health.is_dead():
		_show_result("The Chief has fallen")

func _show_result(title: String) -> void:
	player.set_physics_process(false)
	_result_title.text = title
	_result.modulate.a = 0
	_result.show()
	for child in _result_title.get_parent().get_children():
		if child is Button and child.visible:
			child.grab_focus()
			break
	create_tween().tween_property(_result, "modulate:a", 1.0, 0.45)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _retry() -> void:
	get_node("/root/GameController").health = _entry_health
	get_node("/root/GameController").stamina = int(_entry_stamina)
	_change_scene(ARENA)

func _return_home() -> void:
	var game := get_node("/root/GameController")
	game.health = player.health.current_health
	if player.health.is_dead(): game.recover_from_death()
	game.stamina = int(player.stamina.current_stamina)
	game.return_to_stairs = true
	_change_scene(HOUSE)

func _change_scene(path: String) -> void:
	get_tree().paused = false
	var main := get_tree().current_scene
	if main != self and main.has_method("change_scene"):
		main.change_scene(path)
	elif path == ARENA:
		get_tree().change_scene_to_file(path)
	else:
		var host: Node = load("res://Scenes/Main/main.tscn").instantiate()
		get_tree().root.add_child(host)
		get_tree().current_scene = host
		if host.active_path != path:
			host.call_deferred("change_scene", path)
		queue_free()

func _notification(what: int) -> void:
	if not is_node_ready(): return
	if what == NOTIFICATION_PAUSED:
		_pause_tick = Engine.get_physics_frames()
	elif what == NOTIFICATION_UNPAUSED and _pause_tick >= 0:
		var ticks := Engine.get_physics_frames() - _pause_tick
		player.health.compensate_paused_ticks(_pause_tick, ticks)
		player.damage.compensate_paused_ticks(_pause_tick, ticks)
		player.combat.compensate_paused_ticks(_pause_tick, ticks)
		for hand: CombatDamageable in [monster.left_hurt, monster.right_hurt]:
			if hand._hitstop_until_tick >= _pause_tick:
				hand._hitstop_until_tick += ticks
		_pause_tick = -1

func _unhandled_input(event: InputEvent) -> void:
	if _pause_menu != null and event.is_action_pressed("ui_cancel"):
		_pause_menu.toggle()
		get_viewport().set_input_as_handled()

func change_scene(path: String) -> void:
	_change_scene(path)
