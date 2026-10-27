class_name VillageBlueprintPanel
extends MarginContainer
## Desk management panel for assigning villagers, upgrading buildings, and sleeping.

signal closed
signal sleep_requested

var _button_styles: Dictionary = {}

@onready var status_label: Label = %StatusLabel
@onready var buildings_container: HBoxContainer = %BuildingsContainer
@onready var idle_workers_container: VBoxContainer = %IdleWorkersContainer
@onready var bums_container: VBoxContainer = %BumsContainer
@onready var close_button: Button = %CloseButton
@onready var sleep_button: Button = %SleepButton


func _ready() -> void:
	close_button.pressed.connect(closed.emit)
	sleep_button.pressed.connect(sleep_requested.emit)

	VillageManager.villagers_changed.connect(refresh)
	VillageManager.buildings_changed.connect(refresh)
	GameController.rations_changed.connect(refresh.unbind(1))
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	_refresh_status_banner()
	_refresh_buildings()
	_refresh_roster()


func _refresh_status_banner() -> void:
	var preview := VillageManager.night_preview()
	var pop: int = preview.food_cost
	var prod: int = preview.expected_production
	var net_change := prod - pop
	var net_str := ("+%d" % net_change) if net_change >= 0 else ("%d" % net_change)

	status_label.text = "Food: %d/night   |   Harvest: +%d (Net: %s)   |   Village health: %d%%" % [
		pop,
		prod,
		net_str,
		GameController.village_health,
	]


func _refresh_buildings() -> void:
	for child in buildings_container.get_children():
		buildings_container.remove_child(child)
		child.queue_free()

	for b: BuildingData in VillageManager.get_buildings():
		var card := _create_building_card(b)
		buildings_container.add_child(card)


func _create_building_card(b: BuildingData) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(240, 260)

	var card_bg := StyleBoxFlat.new()
	card_bg.bg_color = Color(0.96, 0.93, 0.86, 0.95)
	card_bg.border_color = Color(0.48, 0.38, 0.28, 0.9)
	card_bg.set_border_width_all(2)
	card_bg.set_corner_radius_all(6)
	card_bg.content_margin_left = 12
	card_bg.content_margin_right = 12
	card_bg.content_margin_top = 10
	card_bg.content_margin_bottom = 10
	card_bg.shadow_color = Color(0, 0, 0, 0.12)
	card_bg.shadow_size = 4
	card_bg.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", card_bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = b.display_name.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.20, 0.15, 0.10, 1))
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	# Level & Slots
	var level := VillageManager.get_building_level(b.id)
	var cap := VillageManager.get_building_capacity(b.id)
	var workers := VillageManager.get_workers_of(b.id)

	var info := Label.new()
	info.text = "LEVEL %d  •  %d/%d SLOTS" % [level, workers.size(), cap]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var is_full := workers.size() >= cap and cap > 0
	info.add_theme_color_override("font_color", Color(0.15, 0.45, 0.15, 1) if is_full else Color(0.45, 0.35, 0.25, 1))
	info.add_theme_font_size_override("font_size", 12)
	vbox.add_child(info)

	var perk := Label.new()
	perk.text = _format_building_perk(b)
	perk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	perk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perk.add_theme_font_size_override("font_size", 11)
	perk.add_theme_color_override("font_color", Color(0.28, 0.24, 0.20, 1))
	vbox.add_child(perk)

	# Workers list
	var workers_box := VBoxContainer.new()
	workers_box.add_theme_constant_override("separation", 3)
	vbox.add_child(workers_box)

	if workers.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No workers assigned"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.35, 0.35, 1))
		workers_box.add_child(empty_lbl)
	else:
		for w: Villager in workers:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)

			var name_lbl := Label.new()
			name_lbl.text = "• " + w.display_name
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.add_theme_font_size_override("font_size", 12)
			name_lbl.add_theme_color_override("font_color", Color(0.12, 0.40, 0.12, 1))
			row.add_child(name_lbl)

			var unassign_btn := Button.new()
			unassign_btn.text = "✕"
			unassign_btn.tooltip_text = "Unassign %s to queue (Free)" % w.display_name
			unassign_btn.custom_minimum_size = Vector2(22, 20)
			unassign_btn.add_theme_font_size_override("font_size", 11)
			_apply_compact_button_style(unassign_btn)
			unassign_btn.pressed.connect(func():
				VillageManager.assign(w.id, Villager.QUEUE)
			)
			row.add_child(unassign_btn)
			workers_box.add_child(row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Building upgrade button
	var up_cost := VillageManager.upgrade_cost(b.id)
	var up_btn := Button.new()
	up_btn.custom_minimum_size = Vector2(0, 30)
	if up_cost > 0:
		up_btn.text = "Upgrade (%d Rations)" % up_cost
		up_btn.disabled = GameController.rations < up_cost
		up_btn.pressed.connect(func():
			VillageManager.upgrade_building(b.id)
		)
	else:
		up_btn.text = "Max Level (Lv 3)"
		up_btn.disabled = true
	up_btn.add_theme_font_size_override("font_size", 11)
	_apply_compact_button_style(up_btn)
	vbox.add_child(up_btn)

	# Apothecary potion purchase
	if b.id == &"apothecary":
		var pot_btn := Button.new()
		pot_btn.custom_minimum_size = Vector2(0, 28)
		var pot_cost: int = VillageManager.config.potion_cost
		pot_btn.text = "Buy Potion (%d R)" % pot_cost
		pot_btn.disabled = GameController.rations < pot_cost
		pot_btn.add_theme_font_size_override("font_size", 11)
		_apply_compact_button_style(pot_btn)
		pot_btn.pressed.connect(func():
			VillageManager.buy_potion()
		)
		vbox.add_child(pot_btn)

	return panel


func _format_building_perk(b: BuildingData) -> String:
	match b.id:
		&"apothecary":
			return "+1 Heart & +1 Potion/day per worker"
		&"blacksmith":
			return "+2 DMG & +0.15s Cleaver Stun per worker"
		&"farmer":
			return "+15 Max Stamina & +10% Regen per worker"
		&"tailor":
			return "+8% Speed per worker"
		_:
			return ""


func _refresh_roster() -> void:
	for child in idle_workers_container.get_children():
		idle_workers_container.remove_child(child)
		child.queue_free()
	for child in bums_container.get_children():
		bums_container.remove_child(child)
		child.queue_free()

	# Idle workers list
	var idles := VillageManager.get_idle_workers()
	if idles.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "All able citizens are assigned to huts."
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.add_theme_color_override("font_color", Color(0.45, 0.40, 0.35, 1))
		idle_workers_container.add_child(empty_lbl)
	else:
		for w: Villager in idles:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)

			var name_lbl := Label.new()
			name_lbl.text = w.display_name
			name_lbl.custom_minimum_size = Vector2(95, 0)
			name_lbl.add_theme_color_override("font_color", Color(0.18, 0.15, 0.12, 1))
			name_lbl.add_theme_font_size_override("font_size", 13)
			row.add_child(name_lbl)

			var trades_lbl := Label.new()
			var trades_str := "New" if w.known_professions.is_empty() else ", ".join(w.known_professions)
			trades_lbl.text = "[%s]" % trades_str
			trades_lbl.custom_minimum_size = Vector2(105, 0)
			trades_lbl.add_theme_color_override("font_color", Color(0.45, 0.35, 0.25, 1))
			trades_lbl.add_theme_font_size_override("font_size", 11)
			row.add_child(trades_lbl)

			# Quick-assign buttons for open building slots
			for b: BuildingData in VillageManager.get_buildings():
				if not VillageManager.can_assign(w.id, b.id):
					continue
				var cost := VillageManager.assignment_cost(w.id, b.id)
				var btn := Button.new()
				btn.custom_minimum_size = Vector2(76, 24)
				var cost_str := "Free" if cost == 0 else ("%dR" % cost)
				btn.text = "+ %s (%s)" % [b.display_name.substr(0, 4), cost_str]
				btn.disabled = cost > 0 and GameController.rations < cost
				btn.add_theme_font_size_override("font_size", 10)
				_apply_compact_button_style(btn)
				btn.pressed.connect(func():
					VillageManager.assign(w.id, b.id)
				)
				row.add_child(btn)

			idle_workers_container.add_child(row)

	# Bums list
	var bums := VillageManager.get_bums()
	if bums.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No bums."
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.add_theme_color_override("font_color", Color(0.45, 0.40, 0.35, 1))
		bums_container.add_child(empty_lbl)
	else:
		for b: Villager in bums:
			var lbl := Label.new()
			lbl.text = "• %s — Doesn't work. Uses 1 Ration/night." % b.display_name
			lbl.add_theme_color_override("font_color", Color(0.55, 0.20, 0.20, 1))
			lbl.add_theme_font_size_override("font_size", 12)
			bums_container.add_child(lbl)


func _apply_compact_button_style(btn: Button) -> void:
	if _button_styles.is_empty():
		for state in ["normal", "hover", "disabled"]:
			var style := StyleBoxTexture.new()
			style.texture = load("res://Assets/Sprites/UI/button_%s.png" % state)
			style.texture_margin_left = 6
			style.texture_margin_right = 6
			style.texture_margin_top = 5
			style.texture_margin_bottom = 5
			style.content_margin_left = 6
			style.content_margin_right = 6
			style.content_margin_top = 2
			style.content_margin_bottom = 2
			_button_styles[state] = style
	for state in _button_styles:
		btn.add_theme_stylebox_override(state, _button_styles[state])
	btn.add_theme_stylebox_override("focus", _button_styles["hover"])
	btn.add_theme_color_override("font_color", Color(0.14, 0.11, 0.08, 1))
	btn.add_theme_color_override("font_hover_color", Color(0.04, 0.04, 0.04, 1))
	btn.add_theme_color_override("font_disabled_color", Color(0.50, 0.46, 0.42, 0.7))
