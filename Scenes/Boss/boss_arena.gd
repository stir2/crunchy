extends Node2D
## Day 10 arm encounter; also runnable directly with F6 for tuning.
const ARENA := "res://Scenes/Boss/boss_arena.tscn"
const HOUSE := "res://Scenes/Village/House/house.tscn"
const MOVEMENT_FX = preload("res://Scenes/Player/movement_effect_frames.tres")
const TILES = preload("res://Assets/Tiles/room_placeholders.tres")
const HEARTS = preload("res://Scenes/Player/Health/heart_hud.tscn")
const WEB = preload("res://Scenes/Enemies/Spiders/web_projectile.gd")
const REVIVAL = preload("res://Scenes/Boss/boss_village_revival.gd")
const PORTRAITS = preload("res://Scenes/Village/villager_portraits.gd")
const SWEEP_DUST = preload("res://BossSprites/Sweep Attack/bossSweepFxDust_160x152_24fps.png")
const STRIKE_WARNING = preload("res://BossSprites/Strike Attack/bossFxWarningStrike.png")
const STRIKE_FX = preload("res://BossSprites/Strike Attack/bossFxRedStrike.png")
const LOWER_OFFSET := 1952.0
const DROP_SECONDS := 5.8
const BOSS_FALL_DELAY := 1.15
const BOSS_FALL_DURATION := DROP_SECONDS - 0.80
const PICKUP_DELAY := 0.55
var active_path := ARENA
var _lower := false
var _dropping := false
var _reviving := false
var _revival_used := false
var _slab_intact := true
var _volley_aim := Vector2.ZERO
var _fan_next := true
var _taken_name := ""
var _pause_menu: CanvasLayer
var _ending := false
var _shake := 0.0
var _shake_time := 0.0
var _pause_tick := -1
var _entry_health := 6
var _entry_stamina := 100.0
var _result: PanelContainer
var _result_layer: Control
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
	player.set_meta(&"boss_death_mix", true)
	$Waves.completed.connect(_finish_taken)
	$Waves.spawn_warning.connect(func(point: Vector2): _ground_impact(point, false))
	monster.waves_requested.connect(_start_taken)
	monster.set_target(player)
	monster.ground_impact.connect(_ground_impact)
	monster.attack_tell.connect(_attack_tell)
	monster.arm_impact.connect(_arm_impact)
	monster.floor_break_requested.connect(_drop_to_lower_arena)
	monster.volley_started.connect(_start_volley)
	monster.volley_burst.connect(_fire_burst)
	monster.last_toll_interrupted.connect(_interrupt_last_toll)
	monster.sweep_floor = _sweep_floor_y
	monster.slab_broken.connect(_break_slab)
	$Waves.wave_started.connect(func(): _cue(&"boss_summon", -16))
	monster.health.health_changed.connect(_boss_health_changed)
	monster.defeated.connect(_boss_defeated)
	monster.defeat_finished.connect(func(): _show_result("No more tribute."))
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

func _start_taken() -> void:
	var losses: Array[Dictionary] = get_node("/root/VillageManager").get_fallen()
	for index in range(losses.size() - 1, -1, -1):
		if losses[index].cause == "taken":
			_taken_name = String(losses[index].name)
			break
	if not _taken_name.is_empty() and not DialogueManager.is_busy():
		player.combat.actions_enabled = false
		player.set_physics_process(false)
		DialogueManager.play("boss_taken", "Boss/taken", _taken_name)
		await DialogueManager.conversation_finished
		player.set_physics_process(true)
		player.combat.actions_enabled = true
	$Waves.start(player, _taken_name)

func _finish_taken() -> void:
	if not _taken_name.is_empty():
		player.combat.actions_enabled = false
		player.set_physics_process(false)
		DialogueManager.play("boss_taken_after", "Boss/taken_after")
		await DialogueManager.conversation_finished
		player.set_physics_process(true)
		player.combat.actions_enabled = true
	monster.finish_waves()

func _build_floor() -> void:
	var tiles: TileMapLayer = $Terrain
	tiles.tile_set = TILES
	for x in range(-1, 41):
		for y in range(19, 24):
			tiles.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	for y in range(-1, 147):
		tiles.set_cell(Vector2i(-1, y), 0, Vector2i.ZERO)
		tiles.set_cell(Vector2i(40, y), 0, Vector2i.ZERO)

func _build_lower_floor() -> void:
	var tiles: TileMapLayer = $Terrain
	for x in range(40):
		var top := _lower_floor_row(x)
		for y in range(top, 147):
			tiles.set_cell(Vector2i(x, y), 0, Vector2i(5, 0) if y == top and x in range(28, 33) else Vector2i.ZERO)
	for x in range(5, 12):
		tiles.set_cell(Vector2i(x, 138), 0, Vector2i.RIGHT)


func _lower_floor_row(column: int) -> int:
	if column in range(15, 25):
		return 143
	if column in [14, 25] or (not _slab_intact and column in range(28, 33)):
		return 142
	return 141


func _sweep_floor_y(x: float) -> float:
	return _lower_floor_row(clampi(floori(x / 16.0), 0, 39)) * 16.0 - LOWER_OFFSET


func _lower_landing_y(x: float) -> float:
	if x >= 80 and x <= 192:
		return 138.0 * 16.0
	return _lower_floor_row(clampi(floori(x / 16.0), 1, 38)) * 16.0


func _music_cue(cue: StringName, time_until_impact := 0.0) -> void:
	var music := get_node_or_null("/root/SoundManager/MusicController")
	if music != null:
		music.boss_music_cue(self, cue, time_until_impact)

func _drop_to_lower_arena() -> void:
	_dropping = true
	_music_cue(&"fall")
	_clear_volley()
	monster.set_physics_process(false)
	player.set_physics_process(false)
	player.combat.interrupt()
	player.get_node("Hurtbox").invulnerable = true
	var sprite: AnimatedSprite2D = player.get_node("Visuals/AnimatedSprite2D")
	sprite.set_process(false)
	sprite._pose(&"jump", sprite.jump_fall_frame, sprite.jump_offset)
	_cue(&"monster_rumbling_3", -13, 1.55)
	_shake = 5.0
	for x in range(40, 640, 72):
		_ground_impact(Vector2(x, 304), false)
	await get_tree().create_timer(0.75, false).timeout
	_cue(&"toll_impact", -13)
	_build_lower_floor()
	var tiles: TileMapLayer = $Terrain
	for x in range(40):
		for y in range(19, 24):
			tiles.erase_cell(Vector2i(x, y))
	tiles.update_internals()
	for x in range(40, 640, 72):
		_ground_impact(Vector2(x, 304), false)
	_floor_debris()
	_shake = 8.0
	var landing := _lower_landing_y(player.position.x)
	_fall_streaks()
	var sounds := get_node("/root/SoundManager")
	var freefall_gain: float = sounds.gain_for(&"freefall")
	var freefall_voice := AudioStreamPlayer.new()
	freefall_voice.name = "Cue_freefall"
	freefall_voice.stream = sounds.stream_for(&"freefall")
	freefall_voice.bus = &"SFX"
	freefall_voice.volume_db = -38.0 + freefall_gain
	freefall_voice.pitch_scale = 0.94
	add_child(freefall_voice)
	if freefall_voice.stream != null:
		freefall_voice.play(0.45)
		var wind := freefall_voice.create_tween()
		wind.tween_property(freefall_voice, "volume_db", -24.0 + freefall_gain, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		wind.tween_property(freefall_voice, "volume_db", -15.0 + freefall_gain, DROP_SECONDS - 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		wind.parallel().tween_property(freefall_voice, "pitch_scale", 1.08, DROP_SECONDS - 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var fall := create_tween().set_parallel(true)
	fall.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(player, "position:y", landing - 0.5, DROP_SECONDS)
	var monster_fall := monster.create_tween()
	monster.begin_fall()
	monster_fall.tween_interval(BOSS_FALL_DELAY)
	var pickup := create_tween()
	pickup.tween_interval(PICKUP_DELAY)
	pickup.tween_callback(func(): _music_cue(&"pickup", BOSS_FALL_DELAY + BOSS_FALL_DURATION - PICKUP_DELAY))
	monster_fall.tween_property(monster, "position:y", LOWER_OFFSET, BOSS_FALL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	monster_fall.parallel().tween_method(monster.pose_fall, 0.0, 1.0, BOSS_FALL_DURATION).set_trans(Tween.TRANS_LINEAR)
	fall.tween_property(camera, "position:y", 180.0 + LOWER_OFFSET, DROP_SECONDS)
	fall.tween_property($BackgroundCanvas/Background, "color", Color("271420"), DROP_SECONDS)
	await fall.finished
	if is_instance_valid(freefall_voice):
		var stop_wind := freefall_voice.create_tween()
		stop_wind.tween_property(freefall_voice, "volume_db", -60.0, 0.06)
		stop_wind.tween_callback(freefall_voice.queue_free)
	_lower = true
	sprite.set_process(true)
	player.reset_movement()
	player.set_physics_process(true)
	for offset: float in [-28.0, 0.0, 28.0]:
		var x := clampf(player.position.x + offset, 8.0, 632.0)
		_ground_impact(Vector2(x, _lower_landing_y(x)), offset == 0.0)
	_cue(&"hard_land_stone", -7)
	_shake = 4.2
	# The Chief lands first; the pursuing mass hits on a separate beat.
	if monster_fall.is_running():
		await monster_fall.finished
	_music_cue(&"landing")
	_ground_impact(monster.to_global(Vector2(486, 304)), true)
	_shake = 8.0
	_cue(&"toll_impact", -12)
	# Hands brace first. The suspended head follows a beat later and rebounds.
	var settle := monster.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	settle.tween_interval(0.06)
	settle.tween_method(monster.pose_landing_head, 0.0, 14.0, 0.14)
	settle.tween_method(monster.pose_landing_head, 14.0, -7.0, 0.22)
	settle.tween_method(monster.pose_landing_head, -7.0, 2.5, 0.18)
	settle.tween_method(monster.pose_landing_head, 2.5, 0.0, 0.20)
	await get_tree().create_timer(1.05, false).timeout
	_dropping = false
	player.get_node("Hurtbox").invulnerable = false
	monster.finish_floor_break()
	monster.set_physics_process(true)


func _fall_streaks() -> void:
	for i in range(44):
		var streak := Line2D.new()
		var x := 18.0 + fmod(float(i) * 97.0, 604.0)
		var y := 380.0 + float(i % 6) * 21.0
		streak.add_point(Vector2(x, y))
		streak.add_point(Vector2(x, y + 16.0 + float(i % 4) * 11.0))
		streak.width = 1.0
		streak.default_color = Color(0.62, 0.53, 0.66, 0.0)
		_hud.add_child(streak)
		var delay := 0.20 + float(i) * 0.105
		var motion := streak.create_tween()
		motion.tween_interval(delay)
		motion.tween_property(streak, "modulate:a", 1.0, 0.01)
		streak.default_color.a = 0.20
		streak.modulate.a = 0.0
		motion.parallel().tween_property(streak, "position:y", -540.0, 0.60)
		motion.tween_callback(streak.queue_free)


func _floor_debris() -> void:
	var atlas := TILES.get_source(0) as TileSetAtlasSource
	var stone := AtlasTexture.new()
	stone.atlas = atlas.texture
	stone.region = atlas.get_tile_texture_region(Vector2i.ZERO)
	for i in range(9):
		var chunk := Sprite2D.new()
		chunk.texture = stone
		chunk.position = Vector2(32 + i * 72, 312 - (i % 3) * 5)
		chunk.scale = Vector2.ONE * (0.50 + (i % 4) * 0.15)
		chunk.modulate = Color(0.72, 0.68, 0.78)
		$Effects.add_child(chunk)
		var lifetime := 0.84 + (i % 4) * 0.08
		var drop := chunk.create_tween().set_parallel()
		drop.tween_property(chunk, "position:y", 570.0 + (i % 3) * 35, lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		drop.tween_property(chunk, "position:x", chunk.position.x + ((i % 3) - 1) * 48, lifetime)
		drop.tween_property(chunk, "rotation", (i % 2 * 2 - 1) * 1.8, lifetime)
		drop.tween_property(chunk, "modulate:a", 0.0, 0.30).set_delay(lifetime - 0.30)
		drop.chain().tween_callback(chunk.queue_free)


func _break_slab() -> void:
	_slab_intact = false
	var tiles: TileMapLayer = $Terrain
	for x in range(28, 33):
		tiles.erase_cell(Vector2i(x, 141))
		_ground_impact(tiles.map_to_local(Vector2i(x, 141)) - Vector2(0, 8), false)
	tiles.update_internals()
	_shake = 4.8
	_cue(&"toll_impact", -15)


func _attack_tell(strike: bool, seconds: float) -> void:
	if strike:
		_cue(&"boss_stab_warning", -14, seconds)
		_cue(&"boss_stab_creak", -14, seconds)
		var y: float = _sweep_floor_y(monster.SLAM_X) if _lower else monster.floor_y
		var point := monster.to_global(Vector2(monster.SLAM_X, y))
		_show_strike_warning(point, seconds - monster.SLAM_FALL_TIME)
	else:
		_cue(&"monster_rumbling_1", -2, seconds)


func _show_strike_warning(point: Vector2, hold_until: float) -> void:
	var warning := Sprite2D.new()
	warning.texture = STRIKE_WARNING
	warning.hframes = 6
	warning.position = point
	warning.offset.y = -STRIKE_WARNING.get_height() / 2.0
	warning.scale = Vector2.ONE * 0.85
	warning.add_to_group("boss_attack_warning")
	$Effects.add_child(warning)
	var timing := warning.create_tween()
	# Play JV's flash, block, and exclamation frames at their authored cadence.
	var frame_seconds := 1.0 / 24.0
	for index in range(1, warning.hframes):
		timing.tween_interval(frame_seconds)
		timing.tween_callback(warning.set_frame.bind(index))
	var hold := maxf(0.0, hold_until - frame_seconds * (warning.hframes - 1))
	timing.tween_method(func(progress: float):
		warning.modulate.a = 1.0 - 0.12 * sin(TAU * progress) ** 2,
		0.0, 1.0, hold)
	timing.tween_property(warning, "modulate:a", 0.0, 0.08)
	timing.tween_callback(warning.queue_free)

func _arm_impact(strike: bool, point: Vector2) -> void:
	if strike:
		var flash := _fx(STRIKE_FX, 184, point + Vector2(14, -3), 0.62, 0.72)
		flash.offset.y = -74.0
		_shake = 3.7
		_cue(&"boss_slam", -14)
	else:
		_shake = 1.5
		_cue(&"boss_hand_drag", -14)


func _fx(sheet: Texture2D, cell: int, point: Vector2, seconds: float, scale_factor: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = sheet
	sprite.hframes = sheet.get_width() / cell
	sprite.position = point
	sprite.scale = Vector2.ONE * scale_factor
	sprite.offset.y = -sheet.get_height() / 2.0
	$Effects.add_child(sprite)
	var tween := sprite.create_tween()
	tween.tween_method(func(frame: float): sprite.frame = int(frame), 0.0, float(sprite.hframes - 1), seconds)
	tween.tween_callback(sprite.queue_free)
	return sprite


func _cue(sound: StringName, volume: float, limit: float = 0.0, full_sample := false) -> AudioStreamPlayer:
	var sounds := get_node("/root/SoundManager")
	var voice := AudioStreamPlayer.new()
	voice.name = "Cue_" + String(sound)
	voice.stream = sounds.stream_for(sound)
	if voice.stream == null:
		voice.free()
		return null
	voice.bus = &"Dread" if String(sound).begins_with("monster_rumbling") else &"SFX"
	voice.volume_db = volume + sounds.gain_for(sound) - 3.0
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play(0.0 if full_sample else sounds.start_offset_for(sound))
	if limit > 0 and limit < voice.stream.get_length():
		var fade := voice.create_tween()
		fade.tween_interval(maxf(0.0, limit - 0.15))
		fade.tween_property(voice, "volume_db", -60.0, 0.15)
		fade.tween_callback(voice.queue_free)
	return voice


func _start_volley() -> void:
	_volley_aim = player.global_position - Vector2(0, 16)
	if monster.is_last_toll():
		_music_cue(&"last_toll")
	else:
		_cue(&"gate_unlock", -13, 0.75)

func _interrupt_last_toll() -> void:
	_clear_volley()
	_music_cue(&"")
	_cue(&"night_bell-1", -10.0, 1.4)
	_shake = 4.0


func _fire_burst(index: int) -> void:
	if _ending or _reviving or _dropping:
		return
	var origin: Vector2 = monster.volley_origin()
	_cue(&"boss_spit", -16)
	_music_cue(&"toll_release" if monster.is_last_toll() else &"volley_release")
	if monster.is_last_toll():
		var aim := origin.direction_to(_volley_aim)
		if aim.length_squared() < 0.01:
			aim = Vector2.DOWN
		for slot in range(-2, 3):
			_fire_web(origin, aim.rotated(deg_to_rad(slot * 19.0)) * 220.0, slot == 0)
		return
	if not _lower:
		# Keep the first arena's bursts narrow enough to leave room to dodge.
		var aim := origin.direction_to(_volley_aim).angle()
		for slot in range(-1, 2):
			var angle := aim + deg_to_rad(slot * 16.0 + (index - 1) * 7.0)
			_fire_web(origin, Vector2.from_angle(angle) * (210.0 + index * 10.0))
		return
	if _fan_next:
		# The gaps rotate on each pulse. The original aim stays fixed for the volley.
		var aim := origin.direction_to(_volley_aim).angle()
		for slot in range(-2, 3):
			var angle := aim + deg_to_rad(slot * 16.0 + (index - 1) * 4.0)
			_fire_web(origin, Vector2.from_angle(angle) * (205 + index * 10))
	else:
		# Vertical shots leave the same open lanes throughout the volley.
		for slot in range(4):
			var x := 82.0 + slot * 158.0
			_fire_web(Vector2(x, LOWER_OFFSET + 62), Vector2(0.0, 190.0 + index * 8.0))
	if index == 2:
		_fan_next = not _fan_next


func _fire_web(origin: Vector2, motion: Vector2, toll_shot := false) -> void:
	var web := WEB.new()
	web.source_actor = monster
	web.travel_velocity = motion
	web.radius = 11.0
	web.visual_scale = 1.05
	web.damage = 1
	web.max_bounces = 0
	web.shot_color = Color("ffe094") if toll_shot else Color("e7c6d5")
	if toll_shot:
		web.set_meta(&"last_toll", true)
	$Effects.add_child(web)
	web.global_position = origin


func _clear_volley() -> void:
	for child in $Effects.get_children():
		if child.is_in_group("enemy_projectiles") or child.is_in_group("boss_attack_warning"):
			child.set_physics_process(false)
			child.queue_free()


func _build_hud() -> void:
	_hud = Control.new()
	_hud.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.size = Vector2(640, 360)
	$HUD.add_child(_hud)
	var hearts := HEARTS.instantiate()
	hearts.position = Vector2(12, 12)
	hearts.health_path = NodePath("")
	_hud.add_child(hearts)
	hearts.bind_health(player.health)
	_boss_bar = ProgressBar.new()
	_boss_bar.position = Vector2(180, 25)
	_boss_bar.show_percentage = false
	for key in ["background", "fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("922e54") if key == "fill" else Color("261d2b")
		_boss_bar.add_theme_stylebox_override(key, style)
	_hud.add_child(_boss_bar)
	_boss_bar.size = Vector2(280, 5)
	_result_layer = Control.new()
	_result_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_result_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	$HUD.add_child(_result_layer)
	_result = PanelContainer.new()
	_result.position = Vector2(36, 36)
	_result.resized.connect(_fit_result)
	_result.custom_minimum_size = Vector2(460, 0)
	_result.theme = preload("res://Scenes/Menus/menu_style.gd").make_theme(1.2, false)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_result.add_child(column)
	_result_title = Label.new()
	_result_title.add_theme_font_size_override("font_size", 34)
	column.add_child(_result_title)
	column.add_child(HSeparator.new())
	for spec in [["Fight again", _retry], ["Return home", _return_home]]:
		var button := Button.new()
		button.text = spec[0]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 28)
		button.pressed.connect(spec[1])
		if spec[1] == _retry:
			_retry_button = button
		column.add_child(button)
	_result_layer.add_child(_result)
	_result.hide()

func _fit_result() -> void:
	if not is_inside_tree() or not is_instance_valid(_result): return
	var viewport_size := get_viewport_rect().size
	_result.position = Vector2(36.0, maxf(36.0, viewport_size.y - _result.size.y - 36.0))

func _fit_view() -> void:
	if not is_inside_tree() or not is_instance_valid(_hud): return
	var viewport_size := get_viewport_rect().size
	var factor := minf(viewport_size.x / 640.0, viewport_size.y / 360.0)
	camera.zoom = Vector2.ONE * factor
	_hud.scale = Vector2.ONE * factor
	_hud.position = (viewport_size - Vector2(640, 360) * factor) * 0.5
	_fit_result()

func _process(delta: float) -> void:
	_shake_time += delta
	_shake = move_toward(_shake, 0, delta * 10)
	camera.offset = Vector2(sin(_shake_time * 53), cos(_shake_time * 71)) * _shake

func _ground_impact(point: Vector2, heavy: bool) -> void:
	if not heavy and monster.phase == monster.Phase.SWIPE_DRAG:
		_sweep_dust(point)
		return
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

func _sweep_dust(point: Vector2) -> void:
	var dust := Sprite2D.new()
	dust.texture = SWEEP_DUST
	dust.hframes = 5
	dust.vframes = 5
	dust.offset = Vector2(0, -28)
	dust.position = point + Vector2(-12.0 * monster.sweep_direction(), 0)
	dust.flip_h = monster.sweep_direction() < 0.0
	dust.scale = Vector2.ONE * 0.70
	dust.modulate.a = 0.72
	$Effects.add_child(dust)
	var trail := dust.create_tween()
	trail.tween_method(func(index: float): dust.frame = int(index), 0.0, 24.0, 1.0)
	trail.tween_callback(dust.queue_free)

func _boss_health_changed(current: int, maximum: int) -> void:
	_boss_bar.max_value = maximum
	_boss_bar.value = current

func _boss_defeated() -> void:
	if _ending: return
	_cue(&"boss_death", -14)
	_music_cue(&"victory")
	_ending = true
	if get_tree().current_scene != self:
		get_node("/root/GameController").boss_defeated = true
	_retry_button.hide()
	_boss_bar.hide()
	_clear_volley()
	$Waves.stop()
	player.combat.actions_enabled = false
	player.combat.interrupt()
	player.get_node("Hurtbox").invulnerable = true
	_shake = 2.5

func _player_died(_hit: CombatHit) -> void:
	if _ending or _reviving:
		return
	if not _revival_used:
		_revival_used = true
		_reviving = true
		$Waves.process_mode = Node.PROCESS_MODE_DISABLED
		monster.set_physics_process(false)
		_revive.call_deferred()
		return
	_ending = true
	_clear_volley()
	$Waves.stop()
	monster.stop_attacks()

func _revive() -> void:
	_clear_volley()
	$Waves._clear_projectiles()
	$Waves.process_mode = Node.PROCESS_MODE_DISABLED
	monster.set_physics_process(false)
	# Keep the dead Chief's gravity and animation running through the grave landing.
	var sprite := player.get_node("Visuals/AnimatedSprite2D")
	await sprite.death_animation_finished
	player.set_physics_process(false)
	await get_tree().create_timer(0.28, false).timeout
	var overlay := REVIVAL.new()
	overlay.name = &"VillageRevival"
	_hud.add_child(overlay)
	var game := get_node("/root/GameController")
	var amount := ceili(player.health.max_health * lerpf(0.75, 1.0, game.village_health / 100.0))
	await overlay.play(player.health.max_health, amount, _cue)
	# Restore the living pose under the cover so the fade reveals the Chief already standing.
	player.get_node("Hurtbox").invulnerable = true
	player.health.reset_health(amount)
	player.reset_movement()
	await overlay.reveal_arena()
	overlay.queue_free()
	if not _dropping:
		player.set_physics_process(true)
		monster.set_physics_process(true)
		if not $Waves.active:
			monster.resume_fight()
	$Waves.process_mode = Node.PROCESS_MODE_INHERIT
	_music_cue(&"")
	_reviving = false
	_cue(&"revive", -12)
	await get_tree().create_timer(1.0, false).timeout
	if not _ending and not _dropping:
		player.get_node("Hurtbox").invulnerable = false

func _player_death_finished() -> void:
	if _ending and player.health.is_dead():
		_show_result("The Chief has fallen")

func _show_result(title: String) -> void:
	player.set_physics_process(false)
	_result_title.text = title
	if not player.health.is_dead():
		var caption := Label.new()
		caption.text = "The village will see another dawn."
		caption.custom_minimum_size.x = 380
		caption.add_theme_font_size_override("font_size", 26)
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var column := _result_title.get_parent()
		column.add_child(caption)
		column.move_child(caption, _result_title.get_index() + 1)
		var row := GridContainer.new()
		row.columns = 6
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 8)
		for villager: Villager in get_node("/root/VillageManager").get_villagers():
			var portrait := TextureRect.new()
			portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			portrait.texture = PORTRAITS.texture_for(villager.display_name)
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.custom_minimum_size = Vector2(48, 52)
			portrait.tooltip_text = villager.display_name
			row.add_child(portrait)
		_result_title.get_parent().add_child(row)
	_result.modulate.a = 0
	_result.show()
	_result.reset_size.call_deferred()
	_fit_result()
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
	game.return_to_stairs = not _ending or player.health.is_dead()
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
