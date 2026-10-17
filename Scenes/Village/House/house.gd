extends Node2D

# Not built yet.
const ABYSS_SCENE := "res://Scenes/Underground/abyss.tscn"

@onready var camera: HouseCamera = $Camera2D
@onready var hotspots: Node2D = $Hotspots
@onready var village_panel: Control = $UI/VillagePanel
@onready var info_label: Label = $UI/VillagePanel/VBox/InfoLabel
@onready var close_button: Button = $UI/VillagePanel/VBox/CloseButton
@onready var sleep_button: Button = $UI/VillagePanel/VBox/SleepButton


func _ready() -> void:
	for hotspot: Hotspot in hotspots.get_children():
		hotspot.activated.connect(_on_hotspot_activated)
	close_button.pressed.connect(_close_panel)
	sleep_button.pressed.connect(_on_sleep_pressed)

	GameController.day_started.connect(_refresh_info.unbind(1))
	GameController.souls_changed.connect(_refresh_info.unbind(1))
	GameController.rations_changed.connect(_refresh_info.unbind(1))
	GameController.trips_changed.connect(_refresh_info.unbind(1))

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
	info_label.text = "Day %d  |  Quota %d  |  Souls %d  |  Rations %d  |  Trips left %d" % [
		GameController.day,
		GameController.current_quota(),
		GameController.souls,
		GameController.rations,
		GameController.trips_left,
	]
