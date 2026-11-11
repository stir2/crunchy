extends Control
## Optional Day 1 guidance. The highlighted controls remain usable.

const MENU_STYLE = preload("res://Scenes/Menus/menu_style.gd")
const SKIPPED := "day1_tutorial_skipped"
const TOLL_SEEN := "day1_tutorial_toll"
const FOOD_SEEN := "day1_tutorial_food"
const PREP_SEEN := "day1_tutorial_prepare"
const STAFFING_DONE := "day1_tutorial_staffing"
const ROUTE_SEEN := "day1_tutorial_route"
const STAIRS_DONE := "day1_tutorial_stairs"

var house: Node2D
var _card: PanelContainer
var _heading: Label
var _body: Label
var _next: Button
var _skip: Button
var _targets: Array[Control] = []
var _step := ""

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_card = PanelContainer.new()
	_card.mouse_filter = MOUSE_FILTER_IGNORE
	_card.theme = MENU_STYLE.make_theme()
	_card.texture_filter = TEXTURE_FILTER_NEAREST
	_card.add_theme_stylebox_override("panel", MENU_STYLE.paper_style(31, 16, Color(1.16, 1.25, 1.34)))
	add_child(_card)
	var content := VBoxContainer.new()
	content.mouse_filter = MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)
	_card.add_child(content)
	_heading = _label(34)
	_body = _label(28)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_heading)
	content.add_child(_body)
	var actions := HBoxContainer.new()
	actions.mouse_filter = MOUSE_FILTER_IGNORE
	actions.add_theme_constant_override("separation", 12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(actions)
	_next = Button.new()
	_next.pressed.connect(_advance)
	actions.add_child(_next)
	_skip = Button.new()
	_skip.text = "Skip tutorial"
	_skip.pressed.connect(_skip_tutorial)
	actions.add_child(_skip)
	hide()

func _label(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("392b24"))
	return label

func _process(_delta: float) -> void:
	var step := _current_step()
	if step != _step or _targets.any(func(target): return not is_instance_valid(target) or target.is_queued_for_deletion()):
		_step = step
		_update_card()
	if visible:
		_layout_card()
		queue_redraw()

func _current_step() -> String:
	var history := GameController.window_history
	if GameController.day != 1 or history.has(SKIPPED) or DialogueManager.is_busy():
		return ""
	if house.refugee_modal.visible or house.sacrifice_modal.visible or house.sleep_dialog.visible:
		return ""
	var village: VillageBlueprintPanel = house.village_panel
	if village.visible:
		if history.has(STAFFING_DONE):
			return ""
		if not VillageManager.get_workers_of(&"farmer").is_empty():
			return "village_done"
		if village.assignment_target == &"farmer":
			return "pick_worker"
		return "assign" if village.selected_building == &"farmer" else "farm"
	if house.current_panel == house.RoomPanel.STAIRS:
		if history.has(STAIRS_DONE) or GameController.trips_left < GameController.TRIPS_PER_DAY:
			return ""
		return "route" if history.has(ROUTE_SEEN) else "stairs"
	if house.current_panel != house.RoomPanel.DESK:
		return ""
	if not history.has(TOLL_SEEN):
		return "toll"
	if not history.has(FOOD_SEEN):
		return "food"
	return "" if history.has(PREP_SEEN) else "prepare"

func _update_card() -> void:
	_targets.clear()
	visible = not _step.is_empty()
	if not visible:
		return
	var village: VillageBlueprintPanel = house.village_panel
	var next_text := "Next"
	match _step:
		"toll":
			_heading.text = "Today's toll"
			_body.text = "Hunt in the Abyss and return to the entrance to bank your Flesh. Bring home %d before you sleep." % GameController.current_quota()
			_targets.assign([house.top_day_label, house.top_flesh_label.get_parent()])
		"food":
			_heading.text = "Feed the village"
			_body.text = "Villagers eat when you end the day. Open the Village Blueprint and assign someone to the farm to produce rations."
			_targets.assign([house.top_rations_label.get_parent(), house.open_blueprint_btn])
			next_text = "Later"
		"prepare":
			_heading.text = "Before you descend"
			_body.text = "Hearts show your health. Stamina fuels your dash. Potions restore health in the Abyss. Use the Stairs to start a hunt, or visit the Window to listen outside."
			_targets.assign([house.top_potions_label.get_parent(), house.top_hearts, house.left_nav_btn])
			next_text = "Got it"
		"stairs":
			_heading.text = "Down into the Abyss"
			_body.text = "You get %d trips each day. Bring your Flesh back to the entrance after each hunt. Descend when you're ready." % GameController.TRIPS_PER_DAY
			_targets.assign([house.top_trips_label, house.descend_btn])
			next_text = "Got it"
		"route":
			_heading.text = "Find your way back"
			_body.text = "Open the map with M. Activate checkpoints you find, and collect key fragments to open deeper routes. If you fall, look for your grave to recover what you dropped."
			next_text = "Got it"
		"farm", "assign", "pick_worker":
			_heading.text = "Put someone on the farm"
			if _step == "farm":
				_body.text = "Select the farmhouse in the top-left of the map."
				var farm := village.find_child("Map_farmer", true, false) as Control
				if farm != null:
					_targets.append(farm)
			elif _step == "assign":
				_body.text = "Choose Assign villager, then pick someone from the bench. You can also drag them onto the farm."
				var assign := village.find_child("AssignVillager", true, false) as Control
				if assign != null:
					_targets.append(assign)
			else:
				_body.text = "Pick a villager from On bench to put them to work."
				var bench := village.find_child("BenchPaper", true, false) as Control
				if bench != null:
					_targets.append(bench)
			next_text = "Later"
		"village_done":
			_heading.text = "Manage the village"
			_body.text = "Select buildings for worker bonuses and upgrades. Buy potions at the Apothecary. Sleep to settle the toll and feed the village."
			_targets.assign([village.sleep_button])
			next_text = "Got it"
	_next.text = next_text

func _layout_card() -> void:
	if house.village_panel.visible:
		var scale_factor := minf(size.x / 1920.0, size.y / 1080.0)
		var origin := (size - Vector2(1920, 1080) * scale_factor) * 0.5
		_card.scale = Vector2.ONE * scale_factor
		_size_card(476.0)
		_card.position = origin + Vector2(1324, 640) * scale_factor
	else:
		_card.scale = Vector2.ONE
		var width := minf(610.0, size.x * 0.76)
		_size_card(width)
		_card.position = Vector2((size.x - width) * 0.5, size.y * 0.16)

func _size_card(width: float) -> void:
	var inner_width := width - 72.0
	if not is_equal_approx(_body.size.x, inner_width):
		_body.size.x = inner_width
	_card.size = Vector2(width, _card.get_combined_minimum_size().y)


func _draw() -> void:
	for target in _targets:
		if is_instance_valid(target) and target.is_visible_in_tree():
			var transform := target.get_global_transform_with_canvas()
			var rect := Rect2(transform.origin, transform.basis_xform(target.size)).grow(4.0)
			draw_rect(rect, Color("e7b779"), false, 2.0)

func _advance() -> void:
	var history := GameController.window_history
	match _step:
		"toll": history[TOLL_SEEN] = true
		"food": history[FOOD_SEEN] = true
		"prepare": history[PREP_SEEN] = true
		"stairs": history[ROUTE_SEEN] = true
		"route": history[STAIRS_DONE] = true
		"farm", "assign", "pick_worker", "village_done": history[STAFFING_DONE] = true

func _skip_tutorial() -> void:
	GameController.window_history[SKIPPED] = true
