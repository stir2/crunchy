extends Node2D

const VICTORY_CREDITS = preload("res://Scenes/Village/House/victory_credits.gd")
const DAY_ONE_TUTORIAL = preload("res://Scenes/Village/House/day_one_tutorial.gd")
const PORTRAITS = preload("res://Scenes/Village/villager_portraits.gd")
const ABYSS_SCENE := "res://Scenes/Underground/abyss_runtime.tscn"
const CUTSCENE_SCENE := "res://Scenes/Cutscene/toll_cutscene.tscn"

const WINDOW_ART = preload("res://Scenes/Village/House/village_window_art.gd")

enum RoomPanel { STAIRS = 0, DESK = 1, WINDOW = 2 }

var current_panel: RoomPanel = RoomPanel.DESK
var ending_dialog: AcceptDialog
var sleep_dialog: ConfirmationDialog
var _descent_panel: Control
var _descent_paper: PanelContainer
var _descent_destinations: BoxContainer
var _destination_list: VBoxContainer
var _destination_scroll: ScrollContainer
var _descent_cancel: Button
var _destination_map: AbyssMapView
var _destination_confirm: Button
var _destination_buttons: Dictionary = {}
var _selected_destination := ""
var _morning_transition: bool = false
var _credits_active := false
var _greeted_refugee: String = ""
var _rumble: AudioStreamPlayer
var _window_ambience_timer := Timer.new()
var _window_ambience_fade: Tween

@onready var stairs_panel: Control = %StairsPanel
@onready var desk_panel: Control = %DeskPanel
@onready var window_panel: Control = %WindowPanel

@onready var left_nav_btn: Button = %LeftNavButton
@onready var right_nav_btn: Button = %RightNavButton

@onready var top_day_label: Label = %TopDayLabel
@onready var top_flesh_label: Label = %TopFleshLabel
@onready var top_rations_label: Label = %TopRationsLabel
@onready var top_potions_label: Label = %TopPotionsLabel
@onready var top_trips_label: Label = %TopTripsLabel
@onready var top_hearts: HeartHUD = %TopHearts
@onready var top_vitals_label: Label = %TopVitalsLabel

@onready var descend_btn: Button = %DescendButton
@onready var stairs_trips_label: Label = %StairsTripsLabel
@onready var open_blueprint_btn: Button = %OpenBlueprintButton
@onready var village_panel: VillageBlueprintPanel = %VillagePanel

@onready var refugee_modal: Control = %RefugeeModal
@onready var refugee_portrait: TextureRect = %RefugeePortrait
@onready var refugee_name_label: Label = %RefugeeNameLabel
@onready var refugee_desc_label: Label = %RefugeeDescLabel
@onready var welcome_refugee_btn: Button = %WelcomeRefugeeButton
@onready var turn_away_refugee_btn: Button = %TurnAwayRefugeeButton

@onready var sacrifice_modal: Control = %SacrificeModal
@onready var sacrifice_list_container: GridContainer = %SacrificeListContainer
@onready var window_button: Button = %TalkMonsterButton
@onready var listen_button: Button = %ListenOutsideButton


func music_room() -> StringName:
	if _credits_active:
		return &"credits"
	match current_panel:
		RoomPanel.WINDOW: return &"window"
		RoomPanel.STAIRS: return &"stairs"
		_: return &"desk"

func _play_dawn() -> void:
	set_panel(RoomPanel.WINDOW)
	var survivors := VillageManager.get_villagers()
	if GameController.window_history.has("boss_dawn") or survivors.is_empty():
		return
	await get_tree().create_timer(0.8, false).timeout
	DialogueManager.play("boss_dawn", "Boss/dawn", survivors[0].display_name)
	if DialogueManager.current_id != "boss_dawn":
		return
	await DialogueManager.conversation_finished
	if is_inside_tree() and current_panel == RoomPanel.WINDOW and GameController.window_history.has("boss_dawn"):
		_credits_active = true
		add_child(VICTORY_CREDITS.new())

func _fit_room_panels() -> void:
	if not is_inside_tree():
		return
	$Panels.size = get_viewport_rect().size

func _ready() -> void:
	var pointer := preload("res://Scenes/Village/House/controller_pointer.gd").new()
	pointer.name = "ControllerPointer"
	$UI.add_child(pointer)
	get_viewport().size_changed.connect(_fit_room_panels)
	_fit_room_panels()
	_build_dialogs()
	var menu_style := preload("res://Scenes/Menus/menu_style.gd")
	var modal_theme := menu_style.make_theme()
	var action_theme := menu_style.make_confirmation_theme()
	for button in [left_nav_btn, right_nav_btn, open_blueprint_btn, descend_btn, window_button, listen_button]:
		button.theme = action_theme
	for state in ["normal", "hover", "pressed", "focus"]:
		modal_theme.set_stylebox(state, "Button", action_theme.get_stylebox(state, "Button"))
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		modal_theme.set_color(color_name, "Button", action_theme.get_color(color_name, "Button"))
	for modal in [refugee_modal, sacrifice_modal]:
		modal.theme = modal_theme
		modal.resized.connect(_position_modal.bind(modal))
	window_button.pressed.connect(_talk_to_monster)
	listen_button.pressed.connect(_listen_outside)
	DialogueManager.conversation_started.connect(_refresh_panel_content)
	DialogueManager.conversation_finished.connect(_on_conversation_finished)
	DialogueManager.window_rumbled.connect(_investigate_window)
	# Custom cursor
	var cursor_tex: Texture2D = load("res://Assets/Sprites/UI/cursor.png")
	if cursor_tex != null:
		Input.set_custom_mouse_cursor(cursor_tex, Input.CURSOR_ARROW)
		Input.set_custom_mouse_cursor(cursor_tex, Input.CURSOR_POINTING_HAND)

	for button in [left_nav_btn, right_nav_btn, open_blueprint_btn]:
		button.set_meta("own_click_sound", true)
	left_nav_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	right_nav_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	left_nav_btn.pressed.connect(_on_left_nav_pressed)
	right_nav_btn.pressed.connect(_on_right_nav_pressed)

	descend_btn.pressed.connect(_open_descent_panel)
	_build_descent_panel(modal_theme)
	open_blueprint_btn.pressed.connect(_open_blueprint)

	village_panel.closed.connect(_close_blueprint)
	village_panel.sleep_requested.connect(_on_sleep_requested)
	village_panel.hide()

	refugee_modal.hide()
	sacrifice_modal.hide()
	welcome_refugee_btn.pressed.connect(_on_welcome_refugee_pressed)
	turn_away_refugee_btn.pressed.connect(_on_turn_away_refugee_pressed)

	GameController.day_started.connect(_refresh_top_hud.unbind(1))
	GameController.flesh_changed.connect(_refresh_top_hud.unbind(1))
	GameController.rations_changed.connect(_refresh_top_hud.unbind(1))
	GameController.potions_changed.connect(_refresh_top_hud.unbind(1))
	GameController.trips_changed.connect(_refresh_top_hud.unbind(1))
	GameController.health_changed.connect(_refresh_top_hud.unbind(2))
	GameController.stamina_changed.connect(_refresh_top_hud.unbind(2))
	GameController.village_health_changed.connect(_refresh_top_hud.unbind(1))

	VillageManager.refugee_waiting.connect(_on_refugee_waiting)
	VillageManager.victim_choice_requested.connect(_on_victim_choice_requested)
	VillageManager.night_resolved.connect(_on_night_resolved)
	VillageManager.village_wiped.connect(_on_village_wiped)

	var tutorial := DAY_ONE_TUTORIAL.new()
	tutorial.name = "DayOneTutorial"
	tutorial.house = self
	$UI.add_child(tutorial)
	var start_panel := RoomPanel.DESK
	if GameController.return_to_stairs:
		GameController.return_to_stairs = false
		start_panel = RoomPanel.STAIRS
	set_panel(start_panel)
	_refresh_top_hud()
	if GameController.boss_defeated:
		call_deferred("_play_dawn")
	elif GameController.is_final_day():
		call_deferred("_start_final_day")
	else:
		VillageManager.check_next_refugee()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _descent_panel.visible:
		_close_descent_panel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and village_panel.visible:
		if village_panel.assignment_target != &"":
			village_panel._cancel_assignment()
		else:
			_close_blueprint()
		get_viewport().set_input_as_handled()


func set_panel(p: RoomPanel) -> void:
	if DialogueManager.is_busy():
		return
	if current_panel != p:
		SoundManager.play_ui(&"panel_transition", -26)
	current_panel = p
	_update_window_ambience()
	stairs_panel.visible = (p == RoomPanel.STAIRS)
	desk_panel.visible = (p == RoomPanel.DESK)
	window_panel.visible = (p == RoomPanel.WINDOW)

	match p:
		RoomPanel.STAIRS:
			left_nav_btn.hide()
			right_nav_btn.show()
			right_nav_btn.text = "DESK  >"
		RoomPanel.DESK:
			left_nav_btn.show()
			left_nav_btn.text = "<  STAIRS"
			right_nav_btn.show()
			right_nav_btn.text = "WINDOW  >"
		RoomPanel.WINDOW:
			left_nav_btn.show()
			left_nav_btn.text = "<  DESK"
			right_nav_btn.hide()

	_refresh_panel_content()
	if p == RoomPanel.WINDOW:
		_refresh_window_art()
		call_deferred("_check_window_story")


func _on_left_nav_pressed() -> void:
	if village_panel.visible:
		_close_blueprint()
	if current_panel == RoomPanel.DESK:
		set_panel(RoomPanel.STAIRS)
	elif current_panel == RoomPanel.WINDOW:
		set_panel(RoomPanel.DESK)


func _on_right_nav_pressed() -> void:
	if village_panel.visible:
		_close_blueprint()
	if current_panel == RoomPanel.STAIRS:
		set_panel(RoomPanel.DESK)
	elif current_panel == RoomPanel.DESK:
		set_panel(RoomPanel.WINDOW)


func _open_blueprint() -> void:
	if DialogueManager.is_busy() or refugee_modal.visible or GameController.night_in_progress or _waiting_for_window():
		return
	if DialogueManager.action_thought("manage"):
		await DialogueManager.conversation_finished
		if not is_inside_tree():
			return
	village_panel.refresh()
	SoundManager.play_ui(&"open_ledger", -23)
	village_panel.show()
	if GameController.day == 1:
		var history := GameController.window_history
		history[DAY_ONE_TUTORIAL.FOOD_SEEN] = true


func _close_blueprint() -> void:
	if village_panel.visible:
		SoundManager.play_ui(&"close_ledger", -24)
	village_panel.hide()


func _build_descent_panel(panel_theme: Theme) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.09, 0.05, 0.11, 0.65)
	$UI.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_descent_panel = shade
	var center := Control.new()
	shade.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.theme = panel_theme
	_descent_paper = panel
	panel.custom_minimum_size.x = 1050
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	panel.add_child(content)
	var title := Label.new()
	title.text = "Where will you descend?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var destinations := BoxContainer.new()
	_descent_destinations = destinations
	destinations.add_theme_constant_override("separation", 16)
	content.add_child(destinations)
	var scroll := ScrollContainer.new()
	_destination_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size.x = 300
	destinations.add_child(scroll)
	_destination_list = VBoxContainer.new()
	_destination_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_destination_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_destination_list)
	_destination_map = AbyssMapView.new()
	_destination_map.custom_minimum_size = Vector2(640, 420)
	_destination_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_destination_map.clip_contents = true
	_destination_map.show_player = false
	_destination_map.pin_gates = false
	_destination_map.checkpoint_selected.connect(_select_descent_destination)
	destinations.add_child(_destination_map)
	var map_help := Label.new()
	map_help.text = "Click an activated checkpoint to select it. Drag to pan and scroll to zoom."
	map_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(map_help)
	_destination_confirm = Button.new()
	_destination_confirm.pressed.connect(func():
		_close_descent_panel()
		_descend(_selected_destination))
	content.add_child(_destination_confirm)
	var cancel := Button.new()
	_descent_cancel = cancel
	cancel.text = "Back to stairs"
	cancel.pressed.connect(_close_descent_panel)
	content.add_child(cancel)
	shade.hide()
	get_viewport().size_changed.connect(_fit_descent_panel)
	panel.minimum_size_changed.connect(_fit_descent_panel.call_deferred)
	_fit_descent_panel.call_deferred()

func _fit_descent_panel() -> void:
	if not is_inside_tree() or not is_instance_valid(_descent_paper):
		return
	var available := (get_viewport_rect().size - Vector2(24, 24)).max(Vector2.ONE)
	var narrow := available.x < 800
	_descent_destinations.vertical = narrow
	_descent_paper.custom_minimum_size.x = 300 if narrow else 1050
	_destination_scroll.custom_minimum_size.x = 240 if narrow else 300
	_destination_map.custom_minimum_size = Vector2(280, 240) if narrow else Vector2(640, 420)
	_descent_paper.size = _descent_paper.get_combined_minimum_size()
	var fit := minf(1.0, minf(available.x / _descent_paper.size.x, available.y / _descent_paper.size.y))
	_descent_paper.scale = Vector2.ONE * fit
	_descent_paper.position = (get_viewport_rect().size - _descent_paper.size * fit) * 0.5

func _open_descent_panel() -> void:
	if GameController.is_final_day():
		_descend()
		return
	if descend_btn.disabled or _descent_panel.visible:
		return
	for child in _destination_list.get_children():
		_destination_list.remove_child(child)
		child.queue_free()
	_destination_buttons.clear()
	var entrance := _add_descent_destination("Abyss Entrance", "")
	var settings := GameController.abyss_room_state.world_settings
	var progression := GameController.abyss_progression_state
	var region := AbyssRegionConfig.new()
	var route := AbyssRouteConfig.new()
	var rules := AbyssProgressionConfig.new()
	var configs: Array[Resource] = [region, route, AbyssTerrainConfig.new(), rules]
	if not AbyssRuntimeWorldSettings.restore_configuration(settings, configs).error.is_empty():
		_descend()
		return
	var routes := AbyssRouteGenerator.new(region, route, rules)
	var specials := AbyssSpecialRooms.new(routes, rules, progression)
	var model := AbyssMapModel.new(specials, GameController.abyss_room_state.exploration, region.room_size)
	var entrance_position := model.room_center(routes.entrance_room())
	var markers: Array[Dictionary] = []
	var checkpoints := progression.activated_checkpoints()
	checkpoints.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.level != b.level:
			return a.level < b.level
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	var count_by_level := {}
	for checkpoint: Dictionary in checkpoints:
		var level := int(checkpoint.level)
		var destination := specials.checkpoint_destination(checkpoint.id)
		if destination.is_empty():
			continue
		markers.append({"kind": "checkpoint", "active": true, "id": checkpoint.id,
			"position": model.room_anchor(destination.room_coords)})
		var count := int(count_by_level.get(level, 0)) + 1
		count_by_level[level] = count
		_add_descent_destination("Level %d  /  Checkpoint %d" % [level, count], checkpoint.id)
	if _destination_list.get_child_count() == 1:
		_descend()
		return
	var buttons := _destination_list.get_children()
	_destination_scroll.custom_minimum_size.y = minf(240, buttons.size() * 56 - 8)
	buttons.append(_destination_confirm)
	buttons.append(_descent_cancel)
	for i in buttons.size():
		var button: Button = buttons[i]
		button.focus_next = button.get_path_to(buttons[(i + 1) % buttons.size()])
		button.focus_previous = button.get_path_to(buttons[posmod(i - 1, buttons.size())])
		button.focus_neighbor_bottom = button.focus_next
		button.focus_neighbor_top = button.focus_previous
		button.focus_neighbor_left = NodePath(".")
		button.focus_neighbor_right = NodePath(".")
	var graph := model.snapshot(1, entrance_position, Rect2i(), false)
	# Saved activation can precede the discovery dwell threshold.
	graph.markers = graph.markers.filter(func(marker: Dictionary) -> bool:
		return not _destination_buttons.has(marker.id))
	graph.markers.append_array(markers)
	_destination_map.selectable_checkpoints = _destination_buttons
	var room_pixels := float(region.room_size.x * model.tile_pixels)
	var bounds := Rect2(entrance_position, Vector2.ZERO)
	for marker in markers:
		bounds = bounds.expand(marker.position)
	var fit := _destination_map.custom_minimum_size - Vector2(64, 64)
	_destination_map.map_zoom = minf(1.0, minf(fit.x / maxf(1.0, bounds.size.x),
		fit.y / maxf(1.0, bounds.size.y)) * room_pixels / _destination_map.room_spacing)
	_destination_map.minimum_zoom = minf(0.35, _destination_map.map_zoom)
	_destination_map.set_graph(graph, room_pixels, bounds.get_center())
	_destination_map.recenter()
	_fit_descent_panel()
	_descent_panel.show()
	_select_descent_destination("")
	entrance.grab_focus()


func _add_descent_destination(label: String, checkpoint_id: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 48
	button.toggle_mode = true
	button.pressed.connect(_select_descent_destination.bind(checkpoint_id))
	_destination_buttons[checkpoint_id] = button
	_destination_list.add_child(button)
	return button


func _select_descent_destination(checkpoint_id: String) -> void:
	_selected_destination = checkpoint_id
	for id: String in _destination_buttons:
		_destination_buttons[id].set_pressed_no_signal(id == checkpoint_id)
	_destination_map.select_checkpoint(checkpoint_id)
	_destination_confirm.text = "Descend here  /  " + _destination_buttons[checkpoint_id].text


func _close_descent_panel() -> void:
	_descent_panel.hide()
	descend_btn.grab_focus()


func _descend(checkpoint_id: String = "") -> void:
	if _morning_transition or DialogueManager.is_busy() or GameController.night_in_progress or refugee_modal.visible:
		return
	if GameController.is_final_day():
		if GameController.monster_missing and not GameController.boss_defeated:
			get_tree().current_scene.transition_to_scene("res://Scenes/Boss/boss_arena.tscn", 0.95)
		return
	var main := get_tree().current_scene
	if not ResourceLoader.exists(ABYSS_SCENE) or not main.has_method("change_scene"):
		print("Can't descend yet: abyss scene missing, or house not run through Main.")
		return
	if GameController.trips_left <= 0:
		return
	if DialogueManager.action_thought("descend"):
		await DialogueManager.conversation_finished
		if not is_inside_tree():
			return
	if GameController.trips_left <= 0:
		return
	main.change_scene(ABYSS_SCENE, checkpoint_id)
	var runtime := main.active_scene as AbyssRuntime
	if runtime != null:
		runtime.ready_for_play.connect(GameController.use_trip.unbind(1), CONNECT_ONE_SHOT)


func _on_sleep_requested() -> void:
	if _morning_transition or DialogueManager.is_busy() or GameController.is_final_day() or GameController.night_in_progress or refugee_modal.visible:
		return
	var preview := VillageManager.night_preview()
	if GameController.day == 1 and not GameController.window_history.has(DAY_ONE_TUTORIAL.SKIPPED):
		var toll := "The toll is met." if preview.toll_met else ("You choose who the monster takes." if preview.player_chooses else "The monster chooses who it takes.")
		var food := int(preview.rations + preview.expected_production + preview.expected_bonus - preview.food_cost)
		var dinner := "Rations left after feeding the village: %d." % food if food >= 0 else "Food is short by %d rations. Some villagers will go hungry." % -food
		sleep_dialog.dialog_text = "Banked Flesh: %d / %d. %s\n\n%s" % [GameController.flesh, GameController.current_quota(), toll, dinner]
		sleep_dialog.popup_centered(Vector2i(680, 210))
		return
	if not preview.toll_met:
		sleep_dialog.dialog_text = ("The toll is short. You will choose who the monster takes."
			if preview.player_chooses else "The toll is short. The monster will choose who it takes.")
		sleep_dialog.popup_centered(Vector2i(660, 220))
		return
	_sleep()


func _sleep() -> void:
	_close_blueprint()
	GameController.end_day()


func _refresh_top_hud() -> void:
	top_day_label.text = "Day %d/%d" % [GameController.day, GameController.run_length]
	top_flesh_label.text = "%d / %d Flesh" % [GameController.flesh, GameController.current_quota()]
	top_rations_label.text = "%d Rations" % GameController.rations
	if top_potions_label != null:
		top_potions_label.text = "%d Potions" % GameController.potions
	top_trips_label.text = "%d/%d Trips" % [GameController.trips_left, GameController.TRIPS_PER_DAY]
	if GameController.is_final_day():
		top_flesh_label.text = "Toll ended" if GameController.boss_defeated else "Toll: ∞"
		top_trips_label.text = "The village is safe" if GameController.boss_defeated else ("Investigate the abyss" if GameController.monster_missing else "Check the window")
	top_hearts.set_display_health(GameController.health, int(GameController.stats.get("max_health", 6)))
	top_vitals_label.text = "Stamina: %d/%d  |  Village Health: %d%%" % [
		GameController.stamina,
		GameController.stats.get("max_stamina", 100),
		GameController.village_health,
	]
	_refresh_panel_content()


func _refresh_panel_content() -> void:
	var talking := DialogueManager.is_busy()
	left_nav_btn.disabled = talking
	right_nav_btn.disabled = talking
	open_blueprint_btn.disabled = talking or _waiting_for_window()
	if stairs_trips_label != null:
		stairs_trips_label.text = "Trips Remaining Today: %d / %d" % [GameController.trips_left, GameController.TRIPS_PER_DAY]
		if GameController.is_final_day():
			stairs_trips_label.text = "The monster has fallen." if GameController.boss_defeated else ("The sound came from down here." if GameController.monster_missing else "Check the window first.")
	if descend_btn != null:
		var can_descend := GameController.trips_left > 0
		if GameController.is_final_day():
			can_descend = GameController.monster_missing and not GameController.boss_defeated
		descend_btn.disabled = talking or _morning_transition or GameController.night_in_progress or not can_descend
		descend_btn.text = "Run complete" if GameController.boss_defeated else ("Investigate the abyss" if GameController.is_final_day() else "DESCEND")
	if window_button != null:
		window_button.visible = not GameController.is_final_day() and not talking
		listen_button.visible = not GameController.is_final_day() and not talking
		window_button.disabled = talking or GameController.night_in_progress
		listen_button.disabled = talking or GameController.night_in_progress
	if village_panel != null:
		village_panel.sleep_button.disabled = talking or GameController.is_final_day() or GameController.night_in_progress


func _on_refugee_waiting(candidate: Dictionary) -> void:
	if GameController.is_final_day() or _morning_transition:
		return
	refugee_portrait.texture = PORTRAITS.texture_for(String(candidate.get("name", "Traveler")))
	var is_bum: bool = candidate.get("is_bum", false)
	refugee_name_label.text = String(candidate.get("name", "Traveler"))
	if is_bum:
		refugee_desc_label.text = "Won't work, but still needs food."
	else:
		refugee_desc_label.text = "Can learn a trade and work in a building."
	refugee_modal.show()
	_center_modal.call_deferred(refugee_modal)
	var identity := str(candidate.get("id", candidate.get("name", "Traveler")))
	if identity != _greeted_refugee:
		_greeted_refugee = identity
		_greet_refugee_when_visible(identity)


func _greet_refugee_when_visible(identity: String) -> void:
	# The house is ready underneath the wake/Continue overlay before it is visible.
	while is_inside_tree():
		if not refugee_modal.visible or _greeted_refugee != identity:
			return
		var main := get_tree().current_scene
		if not get_tree().paused and (main == null or main.get("_transitioning") != true):
			break
		await get_tree().process_frame
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.1, false).timeout
	if is_inside_tree() and refugee_modal.is_visible_in_tree() and _greeted_refugee == identity:
		SoundManager.greet_refugee()


func _on_welcome_refugee_pressed() -> void:
	refugee_modal.hide()
	VillageManager.accept_refugee()
	_refresh_top_hud()


func _on_turn_away_refugee_pressed() -> void:
	refugee_modal.hide()
	VillageManager.dismiss_refugee()


func _on_victim_choice_requested(candidates: Array) -> void:
	for child in sacrifice_list_container.get_children():
		sacrifice_list_container.remove_child(child)
		child.queue_free()

	# Sort candidates so Bums are placed at the top (prime meat shields)
	var sorted := candidates.duplicate()
	sorted.sort_custom(func(a, b):
		if a.is_bum and not b.is_bum:
			return true
		return false
	)

	sacrifice_list_container.columns = mini(3, maxi(1, ceili(sorted.size() / 5.0)))
	for v: Villager in sorted:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		sacrifice_list_container.add_child(row)

		var portrait := TextureRect.new()
		portrait.texture = PORTRAITS.texture_for(v.display_name)
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.custom_minimum_size = Vector2(68, 72)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(portrait)

		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.alignment = BoxContainer.ALIGNMENT_CENTER
		details.custom_minimum_size.x = 145
		row.add_child(details)

		var name_label := Label.new()
		name_label.text = v.display_name
		name_label.add_theme_font_size_override("font_size", 26)
		details.add_child(name_label)

		var occupation := Label.new()
		var building := VillageManager.get_building(v.assignment) if v.is_employed() else null
		occupation.text = "Bum" if v.is_bum else ("Idle Worker" if building == null else building.display_name)
		occupation.add_theme_font_size_override("font_size", 22)
		details.add_child(occupation)

		var sacrifice := Button.new()
		sacrifice.text = "Sacrifice"
		sacrifice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sacrifice.add_theme_font_size_override("font_size", 22)
		sacrifice.pressed.connect(func():
			sacrifice_modal.hide()
			VillageManager.choose_victim(v.id)
		)
		row.add_child(sacrifice)

	sacrifice_modal.show()
	_center_modal.call_deferred(sacrifice_modal)


func _center_modal(modal: Control) -> void:
	if not is_inside_tree() or not is_instance_valid(modal) or not modal.is_inside_tree():
		return
	modal.reset_size()
	_position_modal(modal)


func _position_modal(modal: Control) -> void:
	if not is_inside_tree() or not is_instance_valid(modal) or not modal.is_inside_tree():
		return
	modal.position = (get_viewport_rect().size - modal.size) * 0.5


func _on_night_resolved(report: Dictionary) -> void:
	_morning_transition = true
	refugee_modal.hide()
	if bool(report.get("wiped", false)):
		return
	call_deferred("_transition_to_morning_cutscene")


func _transition_to_morning_cutscene() -> void:
	# Let the closed blueprint and resolved popups leave the frame before capture.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var main := get_tree().current_scene
	if main != null and main.has_method("transition_to_scene"):
		main.transition_to_scene(CUTSCENE_SCENE)
	else:
		get_tree().change_scene_to_file(CUTSCENE_SCENE)


func _on_village_wiped() -> void:
	call_deferred("_present_village_wiped")


func _present_village_wiped() -> void:
	_close_blueprint()
	var screen := CanvasLayer.new()
	screen.layer = 100
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(black)
	add_child(screen)
	var night := create_tween()
	night.tween_property(black, "color:a", 0.97, 0.9).set_trans(Tween.TRANS_SINE)
	await SoundManager.play_transition_cues(screen)
	if not is_inside_tree():
		return
	ending_dialog.dialog_text = "The village is empty. The monster takes the Chief.\nYour run ended on Day %d." % GameController.day
	ending_dialog.get_ok_button().text = "Main Menu"
	ending_dialog.confirmed.connect(_return_to_menu, CONNECT_ONE_SHOT)
	ending_dialog.canceled.connect(_return_to_menu, CONNECT_ONE_SHOT)
	ending_dialog.popup_centered(Vector2i(680, 240))


func _return_to_menu() -> void:
	get_tree().current_scene.change_scene("res://Scenes/Menus/main_menu.tscn")


func _build_dialogs() -> void:
	var confirm_theme := preload("res://Scenes/Menus/menu_style.gd").make_confirmation_theme()
	sleep_dialog = ConfirmationDialog.new()
	sleep_dialog.transparent_bg = true
	sleep_dialog.title = "End the day?"
	sleep_dialog.ok_button_text = "Sleep"
	sleep_dialog.theme = confirm_theme
	sleep_dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sleep_dialog.get_label().vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sleep_dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sleep_dialog.confirmed.connect(_sleep)
	add_child(sleep_dialog)
	ending_dialog = AcceptDialog.new()
	ending_dialog.transparent_bg = true
	ending_dialog.title = "Run status"
	ending_dialog.theme = confirm_theme
	ending_dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ending_dialog.get_label().vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ending_dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(ending_dialog)
	_rumble = AudioStreamPlayer.new()
	_rumble.bus = &"Dread"
	add_child(_rumble)
	_window_ambience_timer.one_shot = true
	_window_ambience_timer.timeout.connect(_play_window_ambience)
	add_child(_window_ambience_timer)


func _update_window_ambience() -> void:
	if current_panel == RoomPanel.WINDOW and not GameController.is_final_day() and not GameController.boss_defeated:
		_window_ambience_timer.start(0.85)
	else:
		_window_ambience_timer.stop()
		if _window_ambience_fade != null and _window_ambience_fade.is_running():
			_window_ambience_fade.kill()
			_rumble.stop()


func _play_window_ambience() -> void:
	_rumble.stream = SoundManager.next_rumble()
	var cue := StringName(_rumble.stream.resource_path.get_file().get_basename())
	var day_gain := clampf((GameController.day - 1) * 0.45, 0.0, 3.6)
	var level := -24.0 + day_gain + SoundManager.gain_for(cue)
	_rumble.volume_db = -60.0
	_rumble.play()
	_window_ambience_fade = create_tween()
	_window_ambience_fade.tween_property(_rumble, "volume_db", level, 0.85)
	_window_ambience_fade.tween_interval(1.9)
	_window_ambience_fade.tween_property(_rumble, "volume_db", -60.0, 1.2)
	_window_ambience_fade.tween_callback(_rumble.stop)
	_window_ambience_timer.start(randf_range(9.0, 14.0))


func _investigate_window() -> void:
	_rumble.stream = SoundManager.next_rumble()
	_rumble.volume_db = -12.0 + SoundManager.gain_for(StringName(_rumble.stream.resource_path.get_file().get_basename()))
	_rumble.play()
	# Use a short swell here; the supplied recordings are over thirty seconds.
	var fade := create_tween()
	fade.tween_interval(2.0)
	fade.tween_property(_rumble, "volume_db", -45.0, 0.6)
	fade.tween_callback(_rumble.stop)
	var panels: Control = $Panels
	var origin := panels.position
	var shake := create_tween()
	for i in 16:
		shake.tween_property(panels, "position", origin + Vector2(6 if i % 2 == 0 else -6, 3 if i % 3 == 0 else -3), 0.07)
	shake.tween_property(panels, "position", origin, 0.1)


func _can_use_window() -> bool:
	return (current_panel == RoomPanel.WINDOW and not DialogueManager.is_busy()
		and not refugee_modal.visible and not sacrifice_modal.visible
		and not GameController.night_in_progress)


func _talk_to_monster() -> void:
	if _can_use_window() and not GameController.monster_missing:
		DialogueManager.talk_to_monster()


func _listen_outside() -> void:
	if _can_use_window():
		DialogueManager.listen_outside()


func _waiting_for_window() -> bool:
	return GameController.is_final_day() and not GameController.monster_missing


func _start_final_day() -> void:
	if not is_inside_tree() or DialogueManager.is_busy():
		return
	if not GameController.monster_missing and not GameController.window_history.has("day_10_morning"):
		DialogueManager.play("day_10_morning", "Monster/day_10_morning")


func _refresh_window_art() -> void:
	$Panels/WindowPanel/TextureRect.texture = WINDOW_ART.texture_for(GameController.day, GameController.boss_defeated, GameController.run_length)


func _check_window_story() -> void:
	if current_panel != RoomPanel.WINDOW or DialogueManager.is_busy() or GameController.boss_defeated:
		return
	if _waiting_for_window():
		DialogueManager.talk_to_monster()
		return
	var stage := WINDOW_ART.stage(GameController.day, GameController.boss_defeated, GameController.run_length)
	if stage >= 1 and stage <= 3:
		var id := "window_approach_%d" % stage
		if not GameController.window_history.has(id):
			DialogueManager.play(id, "Monster/" + id)


func _on_conversation_finished() -> void:
	_refresh_top_hud()
	if current_panel == RoomPanel.WINDOW:
		call_deferred("_check_window_story")
