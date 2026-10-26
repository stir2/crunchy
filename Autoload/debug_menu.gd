extends CanvasLayer
## Developer debug menu toggled with the '=' key.
## Lets you inspect and modify all core variables in real time.

var _panel: PanelContainer
var _updating := false

var _day_spin: SpinBox
var _flesh_spin: SpinBox
var _rations_spin: SpinBox
var _potions_spin: SpinBox
var _trips_spin: SpinBox
var _vhealth_spin: SpinBox
var _hp_spin: SpinBox
var _stamina_spin: SpinBox
var _quota_label: Label


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.hide()


func _input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_EQUAL:
			toggle()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	if _panel.visible:
		_panel.hide()
	else:
		_refresh_values()
		_panel.show()


func close() -> void:
	_panel.hide()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(460, 480)
	_panel.anchors_preset = Control.PRESET_CENTER
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -230.0
	_panel.offset_top = -240.0
	_panel.offset_right = 230.0
	_panel.offset_bottom = 240.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.12, 0.95)
	bg.border_color = Color(0.28, 0.45, 0.65, 0.9)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(6)
	bg.content_margin_left = 16
	bg.content_margin_right = 16
	bg.content_margin_top = 12
	bg.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", bg)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(root_vbox)

	# Header
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "DEBUG MENU  [ = to close ]"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0, 1))
	title.add_theme_font_size_override("font_size", 15)
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.pressed.connect(func(): _panel.hide())
	header.add_child(close_btn)
	root_vbox.add_child(header)

	var sep1 := HSeparator.new()
	root_vbox.add_child(sep1)

	# Quota status
	_quota_label = Label.new()
	_quota_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	_quota_label.add_theme_font_size_override("font_size", 12)
	root_vbox.add_child(_quota_label)

	# Spinbox rows grid
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	root_vbox.add_child(grid)

	# Flesh / Souls
	_flesh_spin = _add_var_row(grid, "Flesh / Souls:", 0, 9999, 1, func(v):
		GameController.flesh = int(v)
	)
	var flesh_quick := HBoxContainer.new()
	var b10 := _quick_btn("+10", func(): GameController.add_flesh(10); _refresh_values())
	var b50 := _quick_btn("+50", func(): GameController.add_flesh(50); _refresh_values())
	var bquota := _quick_btn("Quota", func(): GameController.flesh = GameController.current_quota(); _refresh_values())
	flesh_quick.add_child(b10)
	flesh_quick.add_child(b50)
	flesh_quick.add_child(bquota)
	grid.add_child(flesh_quick)

	# Rations
	_rations_spin = _add_var_row(grid, "Rations:", 0, 999, 1, func(v):
		GameController.rations = int(v)
	)
	var rations_quick := HBoxContainer.new()
	var r5 := _quick_btn("+5", func(): GameController.add_rations(5); _refresh_values())
	var r20 := _quick_btn("+20", func(): GameController.add_rations(20); _refresh_values())
	rations_quick.add_child(r5)
	rations_quick.add_child(r20)
	grid.add_child(rations_quick)

	# Potions
	_potions_spin = _add_var_row(grid, "Potions:", 0, 99, 1, func(v):
		GameController.potions = int(v)
	)
	var p1 := _quick_btn("+1", func(): GameController.add_potions(1); _refresh_values())
	grid.add_child(p1)

	# Trips Left
	_trips_spin = _add_var_row(grid, "Trips Left:", 0, 10, 1, func(v):
		GameController.trips_left = int(v)
	)
	var trips_btn := _quick_btn("Reset (3)", func(): GameController.trips_left = 3; _refresh_values())
	grid.add_child(trips_btn)

	# Day
	_day_spin = _add_var_row(grid, "Day (1-10):", 1, 10, 1, func(v):
		GameController.day = int(v)
		_refresh_values()
	)
	var next_day_btn := _quick_btn("Next Day", func():
		GameController.day = mini(GameController.day + 1, 10)
		_refresh_values()
	)
	grid.add_child(next_day_btn)

	# Village Health
	_vhealth_spin = _add_var_row(grid, "Village Health %:", 0, 100, 1, func(v):
		GameController.village_health = int(v)
	)
	var vh_btn := _quick_btn("Set 100%", func(): GameController.village_health = 100; _refresh_values())
	grid.add_child(vh_btn)

	# Chief HP
	_hp_spin = _add_var_row(grid, "Chief HP (2=1 Heart):", 0, 30, 1, func(v):
		GameController.health = int(v)
	)
	var heal_btn := _quick_btn("Full Heal", func(): GameController.heal_to_full(); _refresh_values())
	grid.add_child(heal_btn)

	# Chief Stamina
	_stamina_spin = _add_var_row(grid, "Chief Stamina:", 0, 300, 5, func(v):
		GameController.stamina = int(v)
	)
	var sta_btn := _quick_btn("Full Sta", func(): GameController.stamina = GameController.stats.get("max_stamina", 100); _refresh_values())
	grid.add_child(sta_btn)

	var sep2 := HSeparator.new()
	root_vbox.add_child(sep2)

	# Action triggers
	var act_title := Label.new()
	act_title.text = "ACTIONS & SIMULATION:"
	act_title.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1))
	act_title.add_theme_font_size_override("font_size", 12)
	root_vbox.add_child(act_title)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(actions_row)

	var refugee_btn := _action_btn("Spawn Refugee", func():
		if VillageManager.sim != null:
			VillageManager.sim._queue_refugee_candidate()
			VillageManager.check_next_refugee()
			_panel.hide()
	)
	actions_row.add_child(refugee_btn)

	var add_worker_btn := _action_btn("+1 Worker", func():
		if VillageManager.sim != null:
			VillageManager.sim.add_villager("", false)
			VillageManager.villagers_changed.emit()
			_refresh_values()
	)
	actions_row.add_child(add_worker_btn)

	var add_bum_btn := _action_btn("+1 Bum", func():
		if VillageManager.sim != null:
			VillageManager.sim.add_villager("", true)
			VillageManager.villagers_changed.emit()
			_refresh_values()
	)
	actions_row.add_child(add_bum_btn)

	var sleep_btn := _action_btn("Sleep (End Day)", func():
		GameController.end_day()
		_panel.hide()
	)
	actions_row.add_child(sleep_btn)


func _add_var_row(grid: GridContainer, label_text: String, min_v: float, max_v: float, step_v: float, callback: Callable) -> SpinBox:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	grid.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step_v
	spin.custom_minimum_size = Vector2(90, 26)
	spin.value_changed.connect(func(v: float):
		if not _updating:
			callback.call(v)
	)
	grid.add_child(spin)
	return spin


func _quick_btn(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 11)
	btn.custom_minimum_size = Vector2(50, 24)
	btn.pressed.connect(callback)
	return btn


func _action_btn(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 12)
	btn.custom_minimum_size = Vector2(0, 30)
	btn.pressed.connect(callback)
	return btn


func _refresh_values() -> void:
	_updating = true
	if _flesh_spin != null:
		_flesh_spin.value = GameController.flesh
	if _rations_spin != null:
		_rations_spin.value = GameController.rations
	if _potions_spin != null:
		_potions_spin.value = GameController.potions
	if _trips_spin != null:
		_trips_spin.value = GameController.trips_left
	if _day_spin != null:
		_day_spin.value = GameController.day
	if _vhealth_spin != null:
		_vhealth_spin.value = GameController.village_health
	if _hp_spin != null:
		_hp_spin.value = GameController.health
	if _stamina_spin != null:
		_stamina_spin.value = GameController.stamina
	if _quota_label != null:
		_quota_label.text = "Day %d Quota: %d Flesh (Met: %s)" % [
			GameController.day,
			GameController.current_quota(),
			"YES" if GameController.flesh >= GameController.current_quota() else "NO"
		]
	_updating = false
