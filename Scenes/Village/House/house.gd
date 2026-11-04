extends Node2D

const ABYSS_SCENE := "res://Scenes/Underground/abyss.tscn"
const CUTSCENE_SCENE := "res://Scenes/Cutscene/toll_cutscene.tscn"

enum RoomPanel { STAIRS = 0, DESK = 1, WINDOW = 2 }

var current_panel: RoomPanel = RoomPanel.DESK
var ending_dialog: AcceptDialog
var _rumble: AudioStreamPlayer

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
@onready var top_vitals_label: Label = %TopVitalsLabel

@onready var descend_btn: Button = %DescendButton
@onready var stairs_trips_label: Label = %StairsTripsLabel
@onready var open_blueprint_btn: Button = %OpenBlueprintButton
@onready var village_panel: VillageBlueprintPanel = %VillagePanel

@onready var refugee_modal: Control = %RefugeeModal
@onready var refugee_name_label: Label = %RefugeeNameLabel
@onready var refugee_desc_label: Label = %RefugeeDescLabel
@onready var welcome_refugee_btn: Button = %WelcomeRefugeeButton
@onready var turn_away_refugee_btn: Button = %TurnAwayRefugeeButton

@onready var sacrifice_modal: Control = %SacrificeModal
@onready var sacrifice_list_container: VBoxContainer = %SacrificeListContainer
@onready var window_button: Button = %TalkMonsterButton
@onready var listen_button: Button = %ListenOutsideButton


func _ready() -> void:
	_build_dialogs()
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

	left_nav_btn.pressed.connect(_on_left_nav_pressed)
	right_nav_btn.pressed.connect(_on_right_nav_pressed)

	descend_btn.pressed.connect(_descend)
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

	var start_panel := RoomPanel.DESK
	if GameController.return_to_stairs:
		GameController.return_to_stairs = false
		start_panel = RoomPanel.STAIRS
	set_panel(start_panel)
	_refresh_top_hud()
	if GameController.is_day_10():
		call_deferred("_start_day_10")
	else:
		VillageManager.check_next_refugee()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and village_panel.visible:
		if village_panel.assignment_target != &"":
			village_panel._cancel_assignment()
		else:
			_close_blueprint()
		get_viewport().set_input_as_handled()


func set_panel(p: RoomPanel) -> void:
	if DialogueManager.is_busy():
		return
	current_panel = p
	stairs_panel.visible = (p == RoomPanel.STAIRS)
	desk_panel.visible = (p == RoomPanel.DESK)
	window_panel.visible = (p == RoomPanel.WINDOW)

	match p:
		RoomPanel.STAIRS:
			left_nav_btn.hide()
			right_nav_btn.show()
			right_nav_btn.text = "DESK  ►"
		RoomPanel.DESK:
			left_nav_btn.show()
			left_nav_btn.text = "◄  STAIRS"
			right_nav_btn.show()
			right_nav_btn.text = "WINDOW  ►"
		RoomPanel.WINDOW:
			left_nav_btn.show()
			left_nav_btn.text = "◄  DESK"
			right_nav_btn.hide()

	_refresh_panel_content()
	if p == RoomPanel.WINDOW and GameController.is_day_10():
		call_deferred("_check_empty_window")


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
	village_panel.show()


func _close_blueprint() -> void:
	village_panel.hide()


func _descend() -> void:
	if DialogueManager.is_busy() or GameController.night_in_progress or refugee_modal.visible:
		return
	if GameController.is_day_10():
		if GameController.monster_missing:
			GameController.return_to_stairs = true
			get_tree().current_scene.change_scene("res://Scenes/Boss/boss_arena.tscn")
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
	if not GameController.use_trip():
		print("No trips left today. Sleep at the desk to end the day.")
		return
	main.change_scene(ABYSS_SCENE)


func _on_sleep_requested() -> void:
	if DialogueManager.is_busy() or GameController.is_day_10() or GameController.night_in_progress or refugee_modal.visible:
		return
	_close_blueprint()
	GameController.end_day()


func _refresh_top_hud() -> void:
	top_day_label.text = "Day %d/%d" % [GameController.day, GameController.RUN_LENGTH]
	top_flesh_label.text = "%d / %d Flesh" % [GameController.flesh, GameController.current_quota()]
	top_rations_label.text = "%d Rations" % GameController.rations
	if top_potions_label != null:
		top_potions_label.text = "%d Potions" % GameController.potions
	top_trips_label.text = "%d/%d Trips" % [GameController.trips_left, GameController.TRIPS_PER_DAY]
	if GameController.is_day_10():
		top_flesh_label.text = "Toll: ∞"
		top_trips_label.text = "Investigate the abyss" if GameController.monster_missing else "Check the window"
	top_vitals_label.text = "Hearts: %.1f/%.1f  |  Stamina: %d/%d  |  Village Health: %d%%" % [
		GameController.health / 2.0,
		GameController.stats.get("max_health", 6) / 2.0,
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
		if GameController.is_day_10():
			stairs_trips_label.text = "The sound came from down here." if GameController.monster_missing else "Check the window first."
	if descend_btn != null:
		descend_btn.disabled = talking or GameController.night_in_progress or (not GameController.monster_missing if GameController.is_day_10() else GameController.trips_left <= 0)
		descend_btn.text = "Investigate the abyss" if GameController.is_day_10() else "DESCEND"
	if window_button != null:
		window_button.visible = not GameController.is_day_10() and not talking
		listen_button.visible = not GameController.is_day_10() and not talking
		window_button.disabled = talking or GameController.night_in_progress
		listen_button.disabled = talking or GameController.night_in_progress
	if village_panel != null:
		village_panel.sleep_button.disabled = talking or GameController.is_day_10() or GameController.night_in_progress


func _on_refugee_waiting(candidate: Dictionary) -> void:
	if GameController.is_day_10():
		return
	var is_bum: bool = candidate.get("is_bum", false)
	var type_str := "Bum" if is_bum else "Worker"
	refugee_name_label.text = "%s (%s)" % [candidate.get("name", "Traveler"), type_str]
	if is_bum:
		refugee_desc_label.text = "Won't work, but still needs food."
	else:
		refugee_desc_label.text = "Can learn a trade and work in a building."
	refugee_modal.show()


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

	for v: Villager in sorted:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var name_lbl := Label.new()
		name_lbl.text = "• " + v.display_name
		name_lbl.custom_minimum_size = Vector2(130, 0)
		name_lbl.add_theme_font_size_override("font_size", 14)

		var desc_lbl := Label.new()
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_lbl.add_theme_font_size_override("font_size", 12)

		if v.is_bum:
			name_lbl.add_theme_color_override("font_color", Color(0.65, 0.18, 0.18, 1))
			desc_lbl.text = "[Permanent Bum] — Meat shield (Recommended)"
			desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.22, 0.22, 1))
		elif v.is_employed():
			name_lbl.add_theme_color_override("font_color", Color(0.18, 0.15, 0.12, 1))
			desc_lbl.text = "[%s Worker] — Active contributor" % v.assignment.capitalize()
			desc_lbl.add_theme_color_override("font_color", Color(0.40, 0.35, 0.28, 1))
		else:
			name_lbl.add_theme_color_override("font_color", Color(0.18, 0.15, 0.12, 1))
			desc_lbl.text = "[Idle Worker] — In queue"
			desc_lbl.add_theme_color_override("font_color", Color(0.40, 0.35, 0.28, 1))

		row.add_child(name_lbl)
		row.add_child(desc_lbl)

		var sac_btn := Button.new()
		sac_btn.text = "SACRIFICE"
		sac_btn.custom_minimum_size = Vector2(100, 30)
		sac_btn.add_theme_font_size_override("font_size", 11)
		sac_btn.add_theme_color_override("font_color", Color(0.70, 0.15, 0.15, 1))
		sac_btn.pressed.connect(func():
			sacrifice_modal.hide()
			VillageManager.choose_victim(v.id)
		)
		row.add_child(sac_btn)

		sacrifice_list_container.add_child(row)

	sacrifice_modal.show()


func _on_night_resolved(report: Dictionary) -> void:
	if bool(report.get("wiped", false)):
		return
	call_deferred("_transition_to_morning_cutscene")


func _transition_to_morning_cutscene() -> void:
	var main := get_tree().current_scene
	if main != null and main.has_method("change_scene"):
		main.change_scene(CUTSCENE_SCENE)
	else:
		get_tree().change_scene_to_file(CUTSCENE_SCENE)


func _on_village_wiped() -> void:
	_close_blueprint()
	ending_dialog.dialog_text = "The village is empty. The monster takes the Chief.\nYour run ended on Day %d." % GameController.day
	ending_dialog.get_ok_button().text = "Main Menu"
	ending_dialog.confirmed.connect(_return_to_menu, CONNECT_ONE_SHOT)
	ending_dialog.canceled.connect(_return_to_menu, CONNECT_ONE_SHOT)
	ending_dialog.popup_centered()


func _return_to_menu() -> void:
	get_tree().current_scene.change_scene("res://Scenes/Menus/main_menu.tscn")


func _build_dialogs() -> void:
	ending_dialog = AcceptDialog.new()
	ending_dialog.title = "Run status"
	add_child(ending_dialog)
	_rumble = AudioStreamPlayer.new()
	_rumble.bus = &"Dread"
	add_child(_rumble)


func _investigate_window() -> void:
	# A short low rumble, made in memory for the temporary scene.
	var samples := PackedByteArray()
	var rate := 22050
	var duration := 2.0
	samples.resize(int(rate * duration) * 2)
	for i in samples.size() / 2:
		var time := float(i) / rate
		var envelope := sin(PI * time / duration)
		var value := (sin(TAU * 38.0 * time) + sin(TAU * 53.0 * time) * 0.5) * envelope * 0.25
		samples.encode_s16(i * 2, int(value * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = samples
	_rumble.stream = stream
	_rumble.play()
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
	return GameController.is_day_10() and not GameController.monster_missing


func _start_day_10() -> void:
	if not is_inside_tree() or DialogueManager.is_busy():
		return
	if not GameController.monster_missing and not GameController.window_history.has("day_10_morning"):
		DialogueManager.play("day_10_morning", "Monster/day_10_morning")


func _check_empty_window() -> void:
	if _waiting_for_window() and not DialogueManager.is_busy():
		DialogueManager.talk_to_monster()


func _on_conversation_finished() -> void:
	_refresh_top_hud()
	if current_panel == RoomPanel.WINDOW and _waiting_for_window():
		call_deferred("_check_empty_window")
