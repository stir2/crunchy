extends Node2D

const ABYSS_SCENE := "res://Scenes/Underground/abyss.tscn"

@onready var camera: HouseCamera = $Camera2D
@onready var hotspots: Node2D = $Hotspots
@onready var village_panel: Control = $UI/VillagePanel
@onready var info_label: Label = %InfoLabel
@onready var close_button: Button = %CloseButton
@onready var close_x_button: TextureButton = %CloseXButton
@onready var sleep_button: Button = %SleepButton
@onready var day_label: Label = %DayLabel
@onready var toll_label: Label = %TollLabel
@onready var rations_label: Label = %RationsLabel
@onready var trips_label: Label = %TripsLabel


func _ready() -> void:
	# Set custom cursor provided by user
	var cursor_tex: Texture2D = load("res://Assets/Sprites/UI/cursor.png")
	if cursor_tex != null:
		Input.set_custom_mouse_cursor(cursor_tex, Input.CURSOR_ARROW)
		Input.set_custom_mouse_cursor(cursor_tex, Input.CURSOR_POINTING_HAND)

	for hotspot: Hotspot in hotspots.get_children():
		hotspot.activated.connect(_on_hotspot_activated)
	close_button.pressed.connect(_close_panel)
	if close_x_button != null:
		close_x_button.pressed.connect(_close_panel)
	sleep_button.pressed.connect(_on_sleep_pressed)

	GameController.day_started.connect(_refresh_info.unbind(1))
	GameController.souls_changed.connect(_refresh_info.unbind(1))
	GameController.rations_changed.connect(_refresh_info.unbind(1))
	GameController.trips_changed.connect(_refresh_info.unbind(1))
	GameController.health_changed.connect(_refresh_info.unbind(2))
	GameController.stamina_changed.connect(_refresh_info.unbind(2))

	village_panel.hide()
	_refresh_info()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and village_panel.visible:
		_close_panel()


func _on_hotspot_activated(id: StringName) -> void:
	match id:
		&"stairs":
			_descend()
		&"desk":
			_open_panel()
		&"window":
			print("Window clicked, village view goes here later.")


func _descend() -> void:
	# Check first so a failed descent doesn't waste a day trip.
	var main := get_tree().current_scene
	if not ResourceLoader.exists(ABYSS_SCENE) or not main.has_method("change_scene"):
		print("Can't descend yet: abyss scene missing, or house not run through Main.")
		return
	if not GameController.use_trip():
		print("No trips left today. Sleep at the desk to end the day.")
		return
	main.change_scene(ABYSS_SCENE)


func _open_panel() -> void:
	village_panel.show()
	camera.pan_enabled = false
	_set_hotspots_enabled(false)


func _close_panel() -> void:
	village_panel.hide()
	camera.pan_enabled = true
	_set_hotspots_enabled(true)


func _set_hotspots_enabled(enabled: bool) -> void:
	for hotspot: Hotspot in hotspots.get_children():
		hotspot.input_pickable = enabled


func _on_sleep_pressed() -> void:
	GameController.end_day()
	_close_panel()


func _refresh_info() -> void:
	day_label.text = "Day %d/%d" % [GameController.day, GameController.RUN_LENGTH]
	toll_label.text = "%d / %d Souls" % [GameController.souls, GameController.current_quota()]
	rations_label.text = "%d Tokens" % GameController.rations
	trips_label.text = "%d/%d Trips" % [GameController.trips_left, GameController.TRIPS_PER_DAY]
	info_label.text = "Village Health: %d%%  |  Chief: %d/%d HP  |  %d/%d Stamina" % [
		GameController.village_health,
		GameController.health,
		GameController.stats.get("max_health", 100),
		GameController.stamina,
		GameController.stats.get("max_stamina", 100),
	]
