extends Control
## Mechanical slot-style number wheel cutscene.
## Black void + silence -> reels spin and agonizingly decelerate with Geiger clicks
## -> heavy latch impact + housing shudder -> hard silence hold -> Chief's house.
## Day 10: the number counts up from 1, accelerating into a blur, then brakes onto "∞".

signal finished

const HOUSE_SCENE := "res://Scenes/Village/House/house.tscn"

const DIGIT_CELL_WIDTH := 92.0
const INFINITY_CELL_WIDTH := 280.0
const CELL_HEIGHT := 220.0
const DIGIT_FONT_SIZE := 150

const PRELUDE_TIME := 0.8
const HOLD_TIME := 1.8
const INFINITY_COUNT_TIME := 5.5 # 1 -> huge, accelerating
const INFINITY_LAND_TIME := 1.6  # final brake onto the infinity symbol

# --- audio tuning ---
const SAMPLE_RATE := 44100
const TICK_POOL := 6
const TICK_MIN_INTERVAL_MS := 22 # caps the click rate so the frenzy stays a crackle, not mush
const TICK_VOLUME_DB := -9.0
const IMPACT_VOLUME_DB := -2.0

enum Phase { PRELUDE, SPINNING, HOLD, DONE }

@onready var reels_container: HBoxContainer = %ReelsContainer
@onready var housing: Control = %Housing
@onready var top_border: ColorRect = %TopBorder
@onready var bottom_border: ColorRect = %BottomBorder
@onready var aperture: Control = %Aperture
@onready var top_shadow: ColorRect = %TopShadow
@onready var bottom_shadow: ColorRect = %BottomShadow
@onready var click_audio_player: AudioStreamPlayer = %ClickAudioPlayer

var _phase := Phase.PRELUDE
var _is_infinity := false
var _reels: Array[DigitReel] = []
var _landed_count := 0
var _shake_root: Control # full-screen CenterContainer: rest position is always (0, 0)
var _shake_tween: Tween

var _tick_players: Array[AudioStreamPlayer] = []
var _tick_idx := 0
var _last_tick_ms := 0
var _impact_player: AudioStreamPlayer


## One wheel. `wheel` is a float position in symbol units; only 3 labels are ever alive.
## Digit reels: wheel DEcreases while spinning, so digits scroll downward.
## Counting reel (infinity): wheel INcreases 1 -> N, so numbers roll upward like a counter.
class DigitReel extends Control:
	signal tick
	signal landed

	const COUNT_TOP := 1000000 # infinity counter races from 1 to this
	const BRAKE_DISTANCE := 15 # numbers it brakes through before landing on ∞
	const BONE := Color(0.86, 0.83, 0.77, 1.0)
	const CRIMSON := Color(0.85, 0.16, 0.16, 1.0)

	var symbols: Array[String] = []
	var target_index := 0
	var counting := false
	var cell_w := 92.0
	var cell_h := 220.0
	var base_font_size := 150
	var is_landed := false

	var _slots: Array = [] # 3 slots, each: [main, ghost-2, ghost-1, ghost+1, ghost+2]
	var _blur_half := 0.0
	var _last_step := 0
	var _prev_wheel := 0.0
	var _tween: Tween
	var _kick_tween: Tween

	var wheel := 0.0:
		set(v):
			wheel = v
			_refresh()
			var step := int(round(v))
			if step != _last_step:
				_last_step = step
				if not is_landed:
					tick.emit()

	var kick := 0.0: # landing recoil, in pixels
		set(v):
			kick = v
			_refresh()

	func _init(p_symbols: Array[String], p_target: int, p_cell_w: float, p_cell_h: float, p_font_size: int, p_counting: bool = false) -> void:
		symbols = p_symbols
		target_index = p_target
		counting = p_counting
		cell_w = p_cell_w
		cell_h = p_cell_h
		base_font_size = p_font_size
		custom_minimum_size = Vector2(cell_w, cell_h)
		size = custom_minimum_size
		clip_contents = true

		# Motion blur = ghost copies of each label, offset vertically and faded by wheel speed.
		# (A screen-texture shader can't be used: with several reels it samples a stale copy
		# of the screen and blanks every reel after the first.)
		for j in 3:
			var layers: Array[Label] = []
			for g in 5:
				var lbl := Label.new()
				lbl.size = Vector2(cell_w, cell_h)
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				lbl.add_theme_font_size_override("font_size", base_font_size)
				lbl.visible = (g == 0)
				add_child(lbl)
				layers.append(lbl)
			_slots.append(layers)

		set_process(false)
		_last_step = target_index
		wheel = float(target_index)

	func _symbol_for(v: int) -> String:
		if counting:
			# Wheel decreases (scrolls DOWN, same as every other reel) while the
			# displayed number m = -v counts UP; the end position is "∞".
			var m := -v
			if m >= -target_index:
				return "∞"
			if m < 1:
				return ""
			return str(m)
		return symbols[posmod(v, symbols.size())]

	func _fit_font(sym: String) -> int:
		if counting and sym != "∞" and sym.length() > 0:
			return mini(base_font_size, int(cell_w * 0.9 / (0.58 * sym.length())))
		return base_font_size

	const GHOST_MULT := [0.0, -1.0, -0.5, 0.5, 1.0]
	const GHOST_ALPHA := [1.0, 0.25, 0.4, 0.4, 0.25]

	func _refresh() -> void:
		if _slots.is_empty():
			return
		var base := int(round(wheel))
		var t := _blur_half / 44.0
		for j in 3:
			var v := base + j - 1
			var sym := _symbol_for(v)
			var y := (float(v) - wheel) * cell_h + kick
			var layers: Array = _slots[j]
			var changed: bool = (layers[0] as Label).text != sym
			for g in 5:
				var lbl: Label = layers[g]
				if g > 0:
					lbl.visible = _blur_half > 0.5
					if not lbl.visible:
						continue
				if changed or (g > 0 and lbl.text != sym):
					lbl.text = sym
					lbl.add_theme_color_override("font_color", CRIMSON if sym == "∞" else BONE)
					lbl.add_theme_font_size_override("font_size", _fit_font(sym))
				lbl.position.y = y + GHOST_MULT[g] * _blur_half
				lbl.modulate.a = lerpf(1.0, 0.55, t) if g == 0 else GHOST_ALPHA[g] * t * 1.6

	func _process(delta: float) -> void:
		var speed := absf(wheel - _prev_wheel) * cell_h / maxf(delta, 0.0001) # px/sec
		_prev_wheel = wheel
		_blur_half = clampf((speed - 500.0) * 0.012, 0.0, 44.0)
		_refresh()

	func _start_motion() -> void:
		is_landed = false
		_prev_wheel = wheel
		set_process(true)

	func _stop_motion() -> void:
		set_process(false)
		_blur_half = 0.0
		_refresh()

	func spin(rotations: int, duration: float) -> void:
		var start := float(target_index + symbols.size() * rotations)
		_last_step = int(round(start))
		wheel = start
		_start_motion()
		_tween = create_tween()
		_tween.tween_property(self, "wheel", float(target_index), duration) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		_tween.tween_callback(_land)

	## Infinity: count 1 -> huge with exponential acceleration, then brake hard onto the symbol.
	func spin_counting(count_time: float, land_time: float) -> void:
		var lead := float(-target_index - BRAKE_DISTANCE)
		_last_step = -1
		wheel = -1.0
		_start_motion()
		_tween = create_tween()
		_tween.tween_method(func(t: float) -> void: wheel = -pow(lead, t), 0.0, 1.0, count_time)
		_tween.tween_property(self, "wheel", float(target_index), land_time) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		_tween.tween_callback(_land)

	func _land() -> void:
		is_landed = true
		_stop_motion()
		wheel = float(target_index)
		# Heavy steel pawl drops into the gear
		_kick_tween = create_tween()
		_kick_tween.tween_property(self, "kick", 7.0, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_kick_tween.tween_property(self, "kick", -2.0, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_kick_tween.tween_property(self, "kick", 0.0, 0.06).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		landed.emit()

	func snap_to_final() -> void:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		if _kick_tween != null and _kick_tween.is_valid():
			_kick_tween.kill()
		is_landed = true
		_stop_motion()
		_last_step = target_index
		kick = 0.0
		wheel = float(target_index)


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	_shake_root = housing.get_parent() as Control

	var quota := GameController.current_quota()
	# Day 10 quota is 0 -> display the impossible toll: "∞"
	_is_infinity = quota == 0 or GameController.is_day_10()
	var target := "∞" if _is_infinity else str(quota)

	_setup_reels(target)
	_setup_shadow_gradients()
	_build_audio()

	# Pure black void until the reels lurch to life
	housing.visible = false
	_run_sequence()


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _unhandled_input(event: InputEvent) -> void:
	if not (event.is_action_pressed("ui_accept") \
			or (event is InputEventMouseButton and event.pressed)):
		return
	match _phase:
		Phase.PRELUDE, Phase.SPINNING:
			_skip_to_landed()
		Phase.HOLD:
			_transition_to_house()


func _setup_reels(quota_str: String) -> void:
	for child in reels_container.get_children():
		reels_container.remove_child(child)
		child.queue_free()
	_reels.clear()

	var num_reels := 1 if _is_infinity else quota_str.length()
	var widths: Array[float] = []
	for i in num_reels:
		widths.append(INFINITY_CELL_WIDTH if _is_infinity else DIGIT_CELL_WIDTH)

	var separation := 2
	reels_container.add_theme_constant_override("separation", separation)

	var inner_w := float((num_reels - 1) * separation)
	for w in widths:
		inner_w += w
	var total_w := inner_w + 24.0
	var total_h := CELL_HEIGHT + 16.0

	housing.custom_minimum_size = Vector2(total_w, total_h)
	housing.size = Vector2(total_w, total_h)
	top_border.size.x = total_w
	bottom_border.size.x = total_w
	bottom_border.position.y = total_h - 2.0

	aperture.position = Vector2(12.0, 8.0)
	aperture.size = Vector2(inner_w, CELL_HEIGHT)
	top_shadow.position = Vector2(12.0, 8.0)
	top_shadow.size = Vector2(inner_w, 42.0)
	bottom_shadow.position = Vector2(12.0, total_h - 50.0)
	bottom_shadow.size = Vector2(inner_w, 42.0)

	var digits: Array[String] = []
	for d in 10:
		digits.append(str(d))

	for i in num_reels:
		var reel: DigitReel
		if _is_infinity:
			reel = DigitReel.new(digits, -(DigitReel.COUNT_TOP + 1), widths[i], CELL_HEIGHT, DIGIT_FONT_SIZE, true)
		else:
			reel = DigitReel.new(digits, int(quota_str.substr(i, 1)), widths[i], CELL_HEIGHT, DIGIT_FONT_SIZE)
		reel.tick.connect(_play_tick)
		reel.landed.connect(_on_reel_landed)
		reels_container.add_child(reel)
		_reels.append(reel)


func _run_sequence() -> void:
	await get_tree().create_timer(PRELUDE_TIME).timeout
	if _phase != Phase.PRELUDE or not is_inside_tree():
		return # skipped during the prelude
	_phase = Phase.SPINNING
	housing.visible = true

	if _is_infinity:
		_reels[0].spin_counting(INFINITY_COUNT_TIME, INFINITY_LAND_TIME)
		return

	for i in _reels.size():
		# Tens land ~3.6s, ones ~4.8s, etc. Later reels also make more full turns.
		var duration := 3.6 + i * 1.2 if _reels.size() > 1 else 4.2
		_reels[i].spin(3 + i, duration)


func _on_reel_landed() -> void:
	if _phase != Phase.SPINNING:
		return
	_play_impact()
	_shudder_housing()
	_landed_count += 1
	if _landed_count >= _reels.size():
		_begin_hold()


func _skip_to_landed() -> void:
	housing.visible = true
	for reel in _reels:
		reel.snap_to_final()
	_play_impact()
	_shudder_housing()
	_begin_hold()


func _begin_hold() -> void:
	if _phase == Phase.HOLD or _phase == Phase.DONE:
		return
	_phase = Phase.HOLD
	# Hard, dread silence holding the number in darkness
	await get_tree().create_timer(HOLD_TIME).timeout
	if is_inside_tree():
		_transition_to_house()


func _shudder_housing() -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_root.position = Vector2.ZERO
	_shake_tween = create_tween()
	_shake_tween.tween_property(_shake_root, "position:y", 4.0, 0.03).set_trans(Tween.TRANS_QUAD)
	_shake_tween.tween_property(_shake_root, "position:y", -2.0, 0.04).set_trans(Tween.TRANS_QUAD)
	_shake_tween.tween_property(_shake_root, "position:y", 0.0, 0.05).set_trans(Tween.TRANS_BOUNCE)


func _setup_shadow_gradients() -> void:
	# Fade the top/bottom shadows toward the middle instead of flat bars over the digits.
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform bool flip = false;
void fragment() {
	float t = flip ? 1.0 - UV.y : UV.y;
	COLOR = vec4(0.0, 0.0, 0.0, 0.85 * (1.0 - t) * (1.0 - t));
}
"""
	for pair in [[top_shadow, false], [bottom_shadow, true]]:
		var rect := pair[0] as ColorRect
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("flip", pair[1])
		rect.material = mat
		rect.color = Color.WHITE


# ---------------------------------------------------------------------------
# Audio. Everything is synthesized so the cutscene works with no assets.
# To use your own sounds, assign a stream to ClickAudioPlayer in the editor
# (used for ticks); the impact is built in _make_impact().
# ---------------------------------------------------------------------------

func _build_audio() -> void:
	var tick_streams: Array[AudioStream] = []
	if click_audio_player.stream != null:
		tick_streams.append(click_audio_player.stream)
	else:
		for i in 4:
			tick_streams.append(_make_click(i))

	# Small pool so fast ticks overlap instead of cutting each other off
	_tick_players.append(click_audio_player)
	for i in TICK_POOL - 1:
		var p := AudioStreamPlayer.new()
		p.bus = click_audio_player.bus
		add_child(p)
		_tick_players.append(p)
	for i in _tick_players.size():
		_tick_players[i].stream = tick_streams[i % tick_streams.size()]
		_tick_players[i].volume_db = TICK_VOLUME_DB

	_impact_player = AudioStreamPlayer.new()
	_impact_player.bus = click_audio_player.bus
	_impact_player.stream = _make_impact()
	_impact_player.volume_db = IMPACT_VOLUME_DB
	add_child(_impact_player)


func _play_tick() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_tick_ms < TICK_MIN_INTERVAL_MS:
		return
	_last_tick_ms = now
	var p := _tick_players[_tick_idx]
	_tick_idx = (_tick_idx + 1) % _tick_players.size()
	p.pitch_scale = randf_range(0.92, 1.08)
	p.volume_db = TICK_VOLUME_DB + randf_range(-3.0, 0.0)
	p.play()


func _play_impact() -> void:
	if _impact_player != null:
		_impact_player.play()


## Geiger-tube style click: a very short dry "tk" (damped high ring) with a tiny low body,
## softened by a low-pass and a dark, empty-room echo. Four slightly different variants.
func _make_click(seed_i: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (seed_i + 1)
	var n := int(SAMPLE_RATE * 0.30)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var f1 := rng.randf_range(2200.0, 3000.0)
	var f2 := rng.randf_range(4300.0, 5400.0)
	var f0 := rng.randf_range(190.0, 250.0)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		buf[i] = cos(TAU * f1 * t) * exp(-t * 1000.0) * 0.8 \
			+ cos(TAU * f2 * t) * exp(-t * 1600.0) * 0.35 \
			+ sin(TAU * f0 * t) * exp(-t * 300.0) * 0.35
	_lowpass(buf, 0.5)
	_comb_reverb(buf, [0.029, 0.043, 0.067], [0.30, 0.24, 0.18], 0.45)
	return _to_wav(buf, 0.6)


## Heavy latch: sub-bass thud falling in pitch, a dull body thump and a few dark metallic
## partials, with a long cold echo. Deliberately nothing like the tick.
func _make_impact() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var n := int(SAMPLE_RATE * 1.6)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var partials := [[418.0, 24.0, 0.30], [697.0, 32.0, 0.22], [1133.0, 44.0, 0.16], [1769.0, 60.0, 0.10]]
	var phase := 0.0
	var noise_lp := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		phase += TAU * (36.0 + 90.0 * exp(-t * 16.0)) / SAMPLE_RATE
		var v := sin(phase) * exp(-t * 4.0)
		noise_lp += 0.12 * ((rng.randf() * 2.0 - 1.0) - noise_lp)
		v += noise_lp * exp(-t * 90.0) * 1.4
		var attack := 1.0 - exp(-t * 3000.0)
		for p in partials:
			v += cos(TAU * p[0] * t) * exp(-t * p[1]) * p[2] * attack
		buf[i] = v
	_lowpass(buf, 0.3)
	_comb_reverb(buf, [0.071, 0.103, 0.139, 0.181], [0.50, 0.46, 0.40, 0.34], 0.35)
	return _to_wav(buf, 0.95)


func _lowpass(buf: PackedFloat32Array, a: float) -> void:
	var y := 0.0
	for i in buf.size():
		y += a * (buf[i] - y)
		buf[i] = y


func _comb_reverb(buf: PackedFloat32Array, delays: Array, gains: Array, damp: float) -> void:
	var n := buf.size()
	var dry := buf.duplicate()
	for k in delays.size():
		var d := int(float(delays[k]) * SAMPLE_RATE)
		var g: float = gains[k]
		var comb := PackedFloat32Array()
		comb.resize(n)
		var lp := 0.0
		for i in n:
			var fb := 0.0
			if i >= d:
				lp += damp * (comb[i - d] - lp)
				fb = lp * g
			comb[i] = dry[i] + fb
		for i in n:
			buf[i] += comb[i] - dry[i]


func _to_wav(buf: PackedFloat32Array, peak: float) -> AudioStreamWAV:
	var n := buf.size()
	var m := 0.0001
	for x in buf:
		m = maxf(m, absf(x))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var fade := minf(1.0, float(n - i) / (n * 0.1)) # no click at the very end
		var v := clampf(buf[i] / m * peak * fade, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _transition_to_house() -> void:
	if _phase == Phase.DONE:
		return
	_phase = Phase.DONE

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	finished.emit()

	var main := get_tree().current_scene
	if main != null and main.has_method("change_scene"):
		main.change_scene(HOUSE_SCENE)
	else:
		get_tree().change_scene_to_file(HOUSE_SCENE)
