class_name VillageBlueprintPanel
extends Control
## Fixed village map with live management controls over the supplied artwork.

signal closed
signal sleep_requested

const MAP = preload("res://uiSprites/deskUi.png")
const PAPER = preload("res://uiSprites/paper.png")
const PORTRAITS = preload("res://Scenes/Village/villager_portraits.gd")
const CHIEF_IDLE = preload("res://Assets/Sprites/UI/Village/chief_idle.tres")
const INK = Color("392b24")
const MAP_OFFSET := Vector2(0, 16)
const HOTSPOTS = {
	&"farmer": Rect2(83, 44, 88, 63),
	&"blacksmith": Rect2(278, 33, 77, 80),
	&"apothecary": Rect2(75, 176, 111, 73),
	&"tailor": Rect2(281, 177, 90, 71),
	&"chief": Rect2(326, 120, 104, 56),
}

# Crop bounds in the original map, including props attached to each building.
const HIGHLIGHT_SHADER = preload("res://Scenes/Village/House/building_highlight.gdshader")
const HIGHLIGHT_REGIONS = {
	&"farmer": Rect2(94, 42, 79, 65),
	&"blacksmith": Rect2(276, 32, 83, 82),
	&"apothecary": Rect2(73, 172, 117, 77),
	&"tailor": Rect2(280, 176, 93, 73),
	&"chief": Rect2(324, 120, 77, 55),
}
const BADGE_CENTERS = {
	&"farmer": Vector2(128, 111),
	&"blacksmith": Vector2(318, 116),
	&"apothecary": Vector2(133, 249),
	&"tailor": Vector2(329, 249),
}


var selected_building: StringName = &"farmer"
var assignment_target: StringName = &""
var sleep_button: Button
var _canvas: Control
var _status: Label
var _details: VBoxContainer
var _assigned: VBoxContainer
var _bench: HBoxContainer
var _bums: HBoxContainer
var _markers: Dictionary = {}
var _badges: Dictionary = {}
var _notice: Label
var _chief: VBoxContainer
var _chief_sprite: AnimatedSprite2D
var _bum_attempts := 0
var _pending := false
var _drag_hint := false


func _ready() -> void:
	_build_layout()
	resized.connect(_fit)
	visibility_changed.connect(_visibility_changed)
	GameController.stats_changed.connect(_stats_changed)
	GameController.health_changed.connect(_vitals_changed)
	GameController.stamina_changed.connect(_vitals_changed)
	VillageManager.villagers_changed.connect(_queue_refresh)
	VillageManager.buildings_changed.connect(_queue_refresh)
	for event in [GameController.rations_changed, GameController.flesh_changed,
		GameController.potions_changed, GameController.village_health_changed,
		GameController.trips_changed, GameController.day_started]:
		event.connect(_state_changed)
	_fit()
	refresh()


func _stats_changed(_stats: Dictionary) -> void:
	_queue_refresh()


func _vitals_changed(_current: int, _maximum: int) -> void:
	_queue_refresh()


func _visibility_changed() -> void:
	if not visible:
		assignment_target = &""
		if _notice != null:
			_set_notice("")
	if _chief_sprite != null:
		if is_visible_in_tree() and selected_building == &"chief":
			_chief_sprite.play("idle")
		else:
			_chief_sprite.pause()


func _set_notice(message: String) -> void:
	_notice.text = message
	_notice.visible = not message.is_empty()


func _state_changed(_value: int) -> void:
	_queue_refresh()


func _queue_refresh() -> void:
	if not _pending:
		_pending = true
		refresh.call_deferred()


func _fit() -> void:
	if _canvas == null:
		return
	var factor := minf(size.x / 1920.0, size.y / 1080.0)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (size - Vector2(1920, 1080) * factor) / 2.0


func _build_layout() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.07, 0.05, 0.04, 1.0)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas = Control.new()
	_canvas.size = Vector2(1920, 1080)
	_canvas.clip_contents = true
	add_child(_canvas)
	var map_view := TextureRect.new()
	map_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map_view.texture = MAP
	map_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_place(map_view, Rect2(MAP_OFFSET, Vector2(1920, 1080)), _canvas)
	var header_art := TextureRect.new()
	var header_crop := AtlasTexture.new()
	header_crop.atlas = MAP
	header_crop.region = Rect2(0, 0, 640, 1)
	header_art.texture = header_crop
	header_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	header_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	header_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(header_art, Rect2(0, 0, 1920, MAP_OFFSET.y), _canvas)
	map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status = _label("", 36)
	_place(_status, Rect2(160, 6, 1664, 44), _canvas)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notice = _label("", 28)
	_notice.add_theme_color_override("font_color", Color("f3d8ae"))
	var notice_style := StyleBoxFlat.new()
	notice_style.bg_color = Color("49352e")
	notice_style.content_margin_left = 14
	notice_style.content_margin_right = 14
	_notice.add_theme_stylebox_override("normal", notice_style)
	_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place(_notice, Rect2(146, 54, 1678, 42), _canvas)
	_notice.hide()
	for id: StringName in HOTSPOTS:
		var region: Rect2 = HOTSPOTS[id]
		var hit := Button.new()
		hit.name = "Map_" + String(id)
		hit.tooltip_text = "Chief's house" if id == &"chief" else VillageManager.get_building(id).display_name
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color.TRANSPARENT
			if state == "focus":
				style.border_color = Color("f1d697")
				style.set_border_width_all(2)
			hit.add_theme_stylebox_override(state, style)
		hit.pressed.connect(_select_building.bind(id))
		_place(hit, Rect2(region.position * 3 + MAP_OFFSET, region.size * 3), _canvas)
		var crop: Rect2 = HIGHLIGHT_REGIONS[id]
		var atlas := AtlasTexture.new()
		atlas.atlas = MAP
		atlas.region = crop
		var highlight := ShaderMaterial.new()
		highlight.shader = HIGHLIGHT_SHADER
		highlight.set_shader_parameter("ink_cutoff", 0.47 if crop.position.x < 200 else 0.48)
		if id == &"farmer":
			highlight.set_shader_parameter("left_trim", Vector2(99, 82))
		elif id == &"tailor":
			highlight.set_shader_parameter("left_trim", Vector2(297, 220))
		var marker := TextureRect.new()
		marker.texture = atlas
		marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		marker.material = highlight
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place(marker, Rect2(crop.position * 3.0 + MAP_OFFSET, crop.size * 3.0), _canvas)
		_markers[id] = marker
		if id != &"chief":
			_make_drop_target(hit, id)
			var badge := PanelContainer.new()
			badge.name = "Badge_" + String(id)
			var badge_style := StyleBoxFlat.new()
			badge_style.bg_color = Color.TRANSPARENT
			badge_style.border_color = INK
			badge_style.content_margin_left = 6
			badge_style.content_margin_right = 6
			badge_style.content_margin_top = 4
			badge_style.content_margin_bottom = 4
			badge.add_theme_stylebox_override("panel", badge_style)
			_place(badge, Rect2(BADGE_CENTERS[id] * 3.0 + MAP_OFFSET - Vector2(112, 0), Vector2(224, 46)), _canvas)
			badge.mouse_filter = Control.MOUSE_FILTER_PASS
			badge.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					_select_building(id))
			_badges[id] = badge
			_make_drop_target(badge, id)
	_details = _paper_box(Rect2(1302, 110, 522, 454), "Details")
	var assigned_box := _paper_box(Rect2(1302, 580, 522, 342), "Assigned")
	assigned_box.add_child(_label("Assigned villagers", 34))
	_assigned = _scroll_list(assigned_box, false) as VBoxContainer
	_make_drop_target(_canvas.get_node("AssignedPaper"), &"selected")
	var bench_box := _paper_box(Rect2(146, 850, 716, 207), "Bench", 12, Vector2i(28, 12))
	bench_box.add_child(_label("On bench", 30))
	_bench = _scroll_list(bench_box, true) as HBoxContainer
	_make_drop_target(_canvas.get_node("BenchPaper"), Villager.QUEUE)
	var bum_box := _paper_box(Rect2(880, 850, 390, 207), "Bums", 12, Vector2i(28, 12))
	bum_box.add_child(_label("Bums", 30))
	_bums = _scroll_list(bum_box, true) as HBoxContainer
	_chief = _paper_box(Rect2(1302, 110, 522, 812), "Chief")
	_chief.hide()
	var close := _button("Step away", func(): closed.emit(), 34)
	_place(close, Rect2(1302, 958, 224, 72), _canvas)
	sleep_button = _button("Sleep · End day", func(): sleep_requested.emit(), 34)
	sleep_button.name = "SleepButton"
	_place(sleep_button, Rect2(1542, 958, 282, 72), _canvas)


func _place(node: Control, rect: Rect2, parent: Node) -> void:
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size


func _paper_box(rect: Rect2, title: String, padding: int = 28, side_padding: Vector2i = Vector2i(54, 44)) -> VBoxContainer:
	var paper := Control.new()
	paper.name = title + "Paper"
	paper.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var style := StyleBoxTexture.new()
	style.texture = PAPER
	style.set_texture_margin(SIDE_LEFT, 20)
	style.set_texture_margin(SIDE_RIGHT, 16)
	style.set_texture_margin(SIDE_TOP, 16)
	style.set_texture_margin(SIDE_BOTTOM, 16)
	_place(paper, rect, _canvas)
	var shadow := Panel.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.self_modulate = Color(0.22, 0.13, 0.10, 0.58)
	shadow.add_theme_stylebox_override("panel", style)
	_place(shadow, Rect2(Vector2(1, -3), rect.size + Vector2(3, 7)), paper)
	var surface := Panel.new()
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_theme_stylebox_override("panel", style)
	_place(surface, Rect2(Vector2.ZERO, rect.size), paper)
	var margin := MarginContainer.new()
	_place(margin, Rect2(Vector2.ZERO, rect.size), paper)
	margin.add_theme_constant_override("margin_left", side_padding.x)
	margin.add_theme_constant_override("margin_right", side_padding.y)
	margin.add_theme_constant_override("margin_top", padding)
	margin.add_theme_constant_override("margin_bottom", padding)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	return box


func _scroll_list(parent: Node, horizontal: bool) -> Container:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal else ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if horizontal else ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)
	var list: BoxContainer = HBoxContainer.new() if horizontal else VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	return list


func _label(text: String, font_size: int = 28) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, action: Callable, font_size: int = 32) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	button.add_theme_font_size_override("font_size", font_size)
	var fills := {
		"normal": Color("594139"),
		"hover": Color("704c3e"),
		"pressed": Color("47332f"),
		"disabled": Color("80664f"),
	}
	for state: String in fills:
		var style := StyleBoxFlat.new()
		style.bg_color = fills[state]
		style.border_color = Color("392823")
		style.set_border_width_all(1)
		style.border_width_bottom = 3
		style.content_margin_left = 12
		style.content_margin_right = 12
		button.add_theme_stylebox_override(state, style)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color("edca92")
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color("f3d8ae"))
	button.add_theme_color_override("font_disabled_color", Color("d0b69a"))
	button.pressed.connect(action)
	return button


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _select_building(id: StringName) -> void:
	if id == &"chief":
		assignment_target = &""
		_set_notice("")
	selected_building = id
	refresh()
	_visibility_changed()


func refresh() -> void:
	_pending = false
	if not is_inside_tree() or _canvas == null:
		return
	if get_viewport().gui_is_dragging():
		return
	var preview := VillageManager.night_preview()
	var quota := "closed" if GameController.boss_defeated else ("∞" if GameController.is_day_10() else str(GameController.current_quota()))
	_status.text = "DAY %d     Flesh %d / %s     Rations %d     Potions %d     Population %d     Village health %d%%" % [GameController.day, GameController.flesh, quota, GameController.rations, GameController.potions, VillageManager.get_population(), GameController.village_health]
	_status.add_theme_color_override("font_color", INK)
	for id in _markers:
		_markers[id].visible = id == selected_building
	_refresh_badges()
	_canvas.get_node("DetailsPaper").visible = selected_building != &"chief"
	_canvas.get_node("AssignedPaper").visible = selected_building != &"chief"
	_canvas.get_node("ChiefPaper").visible = selected_building == &"chief"
	_refresh_details()
	_clear(_assigned)
	if selected_building != &"chief":
		for worker: Villager in VillageManager.get_workers_of(selected_building):
			_assigned.add_child(_worker_row(worker))
	if _assigned.get_child_count() == 0:
		_assigned.add_child(_label("No workers assigned." if selected_building != &"chief" else "The Chief manages the village.", 28))
	_clear(_bench)
	for worker: Villager in VillageManager.get_idle_workers():
		_bench.add_child(_portrait_card(worker, true))
	if _bench.get_child_count() == 0:
		_bench.add_child(_label("Everyone is assigned.", 28))
	_clear(_bums)
	for worker: Villager in VillageManager.get_bums():
		_bums.add_child(_portrait_card(worker, false))
	if _bums.get_child_count() == 0:
		_bums.add_child(_label("No bums.", 28))
	sleep_button.disabled = DialogueManager.is_busy() or GameController.is_day_10() or GameController.night_in_progress
	var outcome := "Toll met. Everyone survives the toll." if preview.toll_met else (
		"You choose who is taken." if preview.player_chooses else "The monster chooses who is taken.")
	var food := int(preview.rations + preview.expected_production + preview.expected_bonus - preview.food_cost)
	var food_result := "%d rations after dinner" % food if food >= 0 else "Dinner is short by %d rations" % -food
	sleep_button.tooltip_text = "%s\n%s" % [outcome, food_result]
	if GameController.is_day_10():
		sleep_button.tooltip_text = "The monster has fallen." if GameController.boss_defeated else "Visit the window and investigate the Abyss."


func _refresh_details() -> void:
	_clear(_details)
	if selected_building == &"chief":
		_refresh_chief()
		return
	var building := VillageManager.get_building(selected_building)
	var level := VillageManager.get_building_level(selected_building)
	var workers := VillageManager.get_workers_of(selected_building)
	var capacity := VillageManager.get_building_capacity(selected_building)
	_details.add_child(_label("%s · Level %d" % [building.display_name, level], 38))
	_details.add_child(_label("Workers: %d / %d" % [workers.size(), capacity], 28))
	var perk := _label(_format_building_perk(building), 30)
	perk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_child(perk)
	perk.tooltip_text = "%d rations per worker / night" % VillageManager.config.rations_per_worker
	perk.mouse_filter = Control.MOUSE_FILTER_PASS
	var cost := VillageManager.upgrade_cost(selected_building)
	var upgrade := _button("Upgrade · %d rations" % cost if cost >= 0 else "Maximum level", func(): VillageManager.upgrade_building(selected_building))
	upgrade.disabled = cost < 0 or GameController.rations < cost
	_details.add_child(upgrade)
	if selected_building == &"apothecary":
		var potion := _button("Buy potion · %d rations" % VillageManager.config.potion_cost, func(): VillageManager.buy_potion())
		potion.disabled = GameController.rations < VillageManager.config.potion_cost
		_details.add_child(potion)
	if assignment_target != &"":
		var target_name := VillageManager.get_building(assignment_target).display_name
		_details.add_child(_button("Cancel · " + target_name, _cancel_assignment))
	else:
		var assign := _button("Assign villager" if workers.size() < capacity else "Full", _begin_assignment)
		assign.disabled = workers.size() >= capacity
		_details.add_child(assign)
	for child in _details.get_children():
		if child is Button:
			child.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func _portrait(worker: Villager) -> TextureRect:
	var image := TextureRect.new()
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.texture = PORTRAITS.texture_for(worker.display_name)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(72, 76)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image


func _portrait_button_style(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color.TRANSPARENT
		if state == "hover" or state == "focus":
			style.border_color = Color("efd09b")
			style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, style)


func _portrait_card(worker: Villager, selectable: bool) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 176
	box.add_theme_constant_override("separation", 4)
	var button := _button("", _pick_worker.bind(worker.id))
	_make_draggable(button, worker.id)
	button.tooltip_text = _worker_info(worker)
	button.custom_minimum_size = Vector2(102, 96)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_portrait_button_style(button)
	var portrait := _portrait(worker)
	button.add_child(portrait)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(button)
	var caption := worker.display_name
	if selectable and assignment_target != &"":
		var cost := VillageManager.assignment_cost(worker.id, assignment_target)
		caption += " · " + ("Free" if cost == 0 else "%dR" % cost if cost > 0 else "Full")
	var name_label := _label(caption, 28)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size.x = 176
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	box.add_child(name_label)
	return box


func _worker_row(worker: Villager) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_make_draggable(row, worker.id)
	var choose := _button("", _pick_worker.bind(worker.id))
	choose.custom_minimum_size = Vector2(144, 152)
	_portrait_button_style(choose)
	_make_draggable(choose, worker.id)
	var image := _portrait(worker)
	choose.add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(choose)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label(worker.display_name, 34)
	title.clip_text = true
	info.add_child(title)
	row.tooltip_text = _worker_info(worker)
	row.add_child(info)
	if assignment_target != &"":
		var cost := VillageManager.assignment_cost(worker.id, assignment_target)
		row.add_child(_button("Pick · " + ("Free" if cost == 0 else "%dR" % cost if cost > 0 else "Full"), _pick_worker.bind(worker.id)))
	else:
		var bench_button := _button("Bench", func(): VillageManager.assign(worker.id, Villager.QUEUE))
		bench_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bench_button)
	return row


func _worker_info(worker: Villager) -> String:
	if worker.is_bum:
		return "Cannot work. Uses 1 ration / night."
	var trades := PackedStringArray()
	for id in worker.known_professions:
		trades.append(VillageManager.get_building(id).display_name)
	return ("New worker · first trade free" if GameController.day == 1 else "Untrained worker") if trades.is_empty() else "Trained: " + ", ".join(trades)


func _format_building_perk(building: BuildingData) -> String:
	match building.id:
		&"apothecary": return "+1 heart and +1 daily potion per worker."
		&"blacksmith": return "+2 attack damage per worker in the Abyss and finale."
		&"farmer": return "+15 max stamina and +10% regen per worker."
		&"tailor": return "+8% speed per worker."
	return ""


func _get_worker(id: int) -> Villager:
	for worker: Villager in VillageManager.get_villagers():
		if worker.id == id:
			return worker
	return null


func _begin_assignment() -> void:
	assignment_target = selected_building
	_set_notice("Pick a villager for " + VillageManager.get_building(assignment_target).display_name + ".")
	_queue_refresh()


func _cancel_assignment() -> void:
	assignment_target = &""
	_set_notice("")
	_queue_refresh()


func _pick_worker(id: int) -> void:
	if assignment_target == &"":
		_set_notice("")
		return
	_transfer_worker(id, assignment_target)


func _transfer_worker(id: int, target: StringName) -> bool:
	if DialogueManager.is_busy() or GameController.night_in_progress or get_tree().paused:
		return false
	var worker := _get_worker(id)
	if worker == null:
		return false
	if worker.is_bum:
		var jokes := ["%s has a full-time job avoiding full-time jobs.", "%s says they're supervising. From over there.", "%s would help, but that sounds suspiciously like work."]
		_set_notice(jokes[_bum_attempts % jokes.size()] % worker.display_name)
		_bum_attempts += 1
		return false
	if worker.assignment == target:
		_set_notice("")
		return false
	var cost := VillageManager.assignment_cost(id, target)
	if cost < 0:
		_set_notice("That hut is full.")
		return false
	if cost > GameController.rations:
		_set_notice("Training %s costs %d rations. You have %d." % [worker.display_name, cost, GameController.rations])
		return false
	if VillageManager.assign(id, target):
		assignment_target = &""
		if target != Villager.QUEUE:
			selected_building = target
		_set_notice("")
		_queue_refresh()
		return true
	else:
		_set_notice("Couldn't assign that villager.")
		return false


func _refresh_badges() -> void:
	for id: StringName in _badges:
		var badge: PanelContainer = _badges[id]
		_clear(badge)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 5)
		badge.add_child(row)
		var workers := VillageManager.get_workers_of(id)
		row.add_child(_label("Lv %d · %d/%d" % [VillageManager.get_building_level(id), workers.size(), VillageManager.get_building_capacity(id)], 28))
		var names := PackedStringArray()
		for worker: Villager in workers:
			var image := _portrait(worker)
			image.custom_minimum_size = Vector2(24, 26)
			image.mouse_filter = Control.MOUSE_FILTER_STOP
			image.tooltip_text = worker.display_name
			_make_draggable(image, worker.id)
			row.add_child(image)
			names.append(worker.display_name)
		badge.tooltip_text = "%s\n%s" % [VillageManager.get_building(id).display_name, "No workers" if names.is_empty() else ", ".join(names)]


func _refresh_chief() -> void:
	var old_frame := 0
	var old_progress := 0.0
	if is_instance_valid(_chief_sprite):
		old_frame = _chief_sprite.frame
		old_progress = _chief_sprite.frame_progress
	_clear(_chief)
	_chief.show()
	_chief.add_child(_label("The Chief", 40))
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, 172)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chief.add_child(stage)
	_chief_sprite = AnimatedSprite2D.new()
	_chief_sprite.name = "ChiefIdle"
	_chief_sprite.sprite_frames = CHIEF_IDLE
	_chief_sprite.position = Vector2(269, 86)
	_chief_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_chief_sprite.scale = Vector2(4, 4)
	stage.add_child(_chief_sprite)
	_chief_sprite.play("idle")
	_chief_sprite.set_frame_and_progress(old_frame, old_progress)
	var vitals_row := HFlowContainer.new()
	vitals_row.add_theme_constant_override("h_separation", 18)
	vitals_row.add_theme_constant_override("v_separation", 6)
	vitals_row.mouse_filter = Control.MOUSE_FILTER_PASS
	vitals_row.tooltip_text = "%.1f / %.1f hearts" % [GameController.health / 2.0, GameController.stats.max_health / 2.0]
	var hearts_group := HBoxContainer.new()
	hearts_group.add_theme_constant_override("separation", 10)
	hearts_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hearts_lbl := _label("Hearts", 28)
	hearts_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hearts_group.add_child(hearts_lbl)
	var hearts_icons := HBoxContainer.new()
	hearts_icons.name = "HeartsIcons"
	hearts_icons.add_theme_constant_override("separation", 4)
	hearts_icons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hearts_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heart_slots := maxi(1, ceili(GameController.stats.max_health / 2.0))
	for i in range(heart_slots):
		var fill := clampi(GameController.health - i * 2, 0, 2)
		hearts_icons.add_child(_heart_icon(fill))
	hearts_group.add_child(hearts_icons)
	vitals_row.add_child(hearts_group)
	var stamina_lbl := _label("Stamina %d / %d" % [GameController.stamina, GameController.stats.max_stamina], 28)
	stamina_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vitals_row.add_child(stamina_lbl)
	_chief.add_child(vitals_row)
	var keys := ["max_health", "damage", "max_stamina", "speed"]
	var captions := ["Max hearts", "Finale damage", "Max stamina", "Movement speed"]
	for i in range(keys.size()):
		var key: String = keys[i]
		var base := float(GameController.BASE_STATS[key])
		var bonus := float(GameController.stat_bonuses.get(key, 0))
		var maximum_bonus := 0.0
		for building: BuildingData in VillageManager.get_buildings():
			if building.stat_key == key:
				maximum_bonus += building.bonus_per_worker * building.max_level()
		var unit := ""
		if key == "max_health":
			base /= 2.0
			bonus /= 2.0
			maximum_bonus /= 2.0
		elif key == "speed":
			base = 100.0
			unit = "%"
		_add_stat_bar(captions[i], base, bonus, base + maximum_bonus, unit)
	_chief.add_child(_label("Stamina regen: +%.0f%%\nDaily potions: +%d" % [VillageManager.get_effect("stamina_regen_pct"), int(VillageManager.get_effect("free_potions"))], 28))


func _heart_icon(fill: int, pixel_scale: int = 4) -> TextureRect:
	var rows := HeartHUD.HEART
	var cols := rows[0].length()
	var img := Image.create_empty(cols * pixel_scale, rows.size() * pixel_scale, false, Image.FORMAT_RGBA8)
	var full_col := Color(0.86, 0.20, 0.24)
	var empty_col := Color(0.45, 0.34, 0.26, 0.42)
	for y in range(rows.size()):
		for x in range(cols):
			if rows[y][x] == "1":
				var filled := fill == 2 or (fill == 1 and x < 3)
				var col := full_col if filled else empty_col
				img.fill_rect(Rect2i(x * pixel_scale, y * pixel_scale, pixel_scale, pixel_scale), col)
	var tex := TextureRect.new()
	tex.texture = ImageTexture.create_from_image(img)
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.stretch_mode = TextureRect.STRETCH_KEEP
	tex.custom_minimum_size = Vector2(cols * pixel_scale, rows.size() * pixel_scale)
	tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tex


func _add_stat_bar(caption: String, base: float, bonus: float, maximum: float, unit: String) -> void:
	var text := _label("%s  %s%s" % [caption, str(snappedf(base + bonus, 0.1)), unit], 28)
	text.tooltip_text = "Base %s + %s" % [str(snappedf(base, 0.1)), str(snappedf(bonus, 0.1))]
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	_chief.add_child(text)
	var bar := HBoxContainer.new()
	bar.custom_minimum_size.y = 18
	bar.add_theme_constant_override("separation", 0)
	_chief.add_child(bar)
	var values := [base, bonus, maxf(maximum - base - bonus, 0.0)]
	var colors := [Color("936b46"), Color("65834e"), Color("c4a273")]
	for i in range(values.size()):
		if values[i] <= 0:
			continue
		var segment := ColorRect.new()
		segment.color = colors[i]
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segment.size_flags_stretch_ratio = values[i]
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(segment)


func _make_draggable(control: Control, worker_id: int) -> void:
	control.set_drag_forwarding(_create_drag.bind(worker_id, control), Callable(), Callable())


func _make_drop_target(control: Control, target: StringName) -> void:
	control.set_drag_forwarding(Callable(), _can_drop_worker.bind(target), _drop_worker.bind(target))


func _create_drag(_position: Vector2, worker_id: int, source: Control) -> Variant:
	var worker := _get_worker(worker_id)
	if worker == null or DialogueManager.is_busy() or GameController.night_in_progress:
		return null
	var preview := VBoxContainer.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(_portrait(worker))
	var name_label := _label(worker.display_name, 25)
	name_label.add_theme_color_override("font_color", INK)
	preview.add_child(name_label)
	source.set_drag_preview(preview)
	return {"type": "village_worker", "panel": get_instance_id(), "id": worker_id, "from": worker.assignment}


func _drag_worker(data: Variant) -> Villager:
	if not data is Dictionary or data.get("type") != "village_worker" or data.get("panel") != get_instance_id():
		return null
	var worker := _get_worker(int(data.get("id", 0)))
	if worker == null or worker.assignment != data.get("from"):
		return null
	return worker


func _can_drop_worker(_position: Vector2, data: Variant, target: StringName) -> bool:
	var worker := _drag_worker(data)
	if worker == null or not is_visible_in_tree() or DialogueManager.is_busy() or GameController.night_in_progress:
		return false
	if target == &"selected":
		target = selected_building
	if target == &"chief":
		return false
	_drag_hint = true
	if worker.is_bum:
		_set_notice("")
	elif target == Villager.QUEUE:
		_set_notice("Bench · Free")
	else:
		var cost := VillageManager.assignment_cost(worker.id, target)
		var name_text := VillageManager.get_building(target).display_name
		_set_notice("%s · %s" % [name_text, "Full" if cost < 0 else "Free" if cost == 0 else "%d rations" % cost])
	return true


func _drop_worker(_position: Vector2, data: Variant, target: StringName) -> void:
	var worker := _drag_worker(data)
	if worker == null:
		return
	_drag_hint = false
	if target == &"selected":
		target = selected_building
	if target != &"chief":
		_transfer_worker(worker.id, target)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		if _drag_hint:
			_set_notice("")
			_drag_hint = false
		_queue_refresh()
