extends Node

const PATH := "user://settings.cfg"
const AUDIO_BUSES := [&"Master", &"Music", &"SFX"]

var fullscreen := false
var show_abyss_minimap := true
var volumes: Dictionary = {}
var _default_gains: Dictionary = {}


func _ready() -> void:
	var config := ConfigFile.new()
	config.load(PATH)
	fullscreen = bool(config.get_value("display", "fullscreen", false))
	show_abyss_minimap = bool(config.get_value("display", "abyss_minimap", true))
	for bus in AUDIO_BUSES:
		var index := AudioServer.get_bus_index(bus)
		_default_gains[bus] = AudioServer.get_bus_volume_db(index)
		set_volume(bus, clampi(int(config.get_value("audio", bus, 100)), 0, 100))
	if fullscreen:
		_apply_display()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_display()


func _apply_display() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)


func set_volume(bus: StringName, percent: int) -> void:
	volumes[bus] = percent
	var index := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_mute(index, percent == 0)
	AudioServer.set_bus_volume_db(index, float(_default_gains[bus]) + linear_to_db(maxi(percent, 1) / 100.0))


func save() -> Error:
	var config := ConfigFile.new()
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "abyss_minimap", show_abyss_minimap)
	for bus in AUDIO_BUSES:
		config.set_value("audio", bus, volumes[bus])
	return config.save(PATH)
