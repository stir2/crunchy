extends Node
## One local save slot. Saves are made at home, between night resolutions.

const SAVE_PATH := "user://save.json"
const VERSION := 1

var last_error := ""
var save_path := SAVE_PATH


func can_save() -> bool:
	var main := get_tree().current_scene
	return (main != null and main.get("active_path") == "res://Scenes/Village/House/house.tscn"
		and not GameController.night_in_progress and VillageManager.get_population() > 0
		and not DialogueManager.is_busy())


func has_save() -> bool:
	return not _read_save().is_empty()


func save_game() -> bool:
	last_error = ""
	if not can_save():
		last_error = "Return home and finish the night before saving."
		return false
	var game := {}
	for key in ["day", "trips_left", "flesh", "rations", "potions", "village_health", "health", "stamina"]:
		game[key] = GameController.get(key)
	var data := {
		"version": VERSION,
		"game": game,
		"village": VillageManager.get_save_data(),
		"abyss": GameController.abyss_room_state.serialize(),
		"progression": GameController.abyss_progression_state.serialize(),
		"monster_missing": GameController.monster_missing,
		"window_history": GameController.window_history.duplicate(),
	}
	# Write beside the slot first so a failed write leaves the old save intact.
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "Could not open the save file."
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(save_path + ".tmp", save_path)
	if error != OK:
		last_error = "Could not write the save file (%s)." % error_string(error)
	return error == OK


func load_game() -> bool:
	var data := _read_save()
	if data.is_empty():
		return false
	var state := AbyssRoomState.new()
	state.restore(data["abyss"])
	var progression := AbyssProgressionState.new()
	progression.restore(data["progression"])
	# Restore bonuses before vitals; loading must not grant morning potions again.
	VillageManager.load_save_data(data["village"])
	GameController.night_in_progress = false
	for key in data["game"]:
		GameController.set(key, int(data["game"][key]))
	# Old saves have no hunger or settlement-day fields.
	if not data["village"].has("current_day"):
		VillageManager.sim.current_day = maxi(0, GameController.day - 1)
	GameController.abyss_room_state = state
	GameController.abyss_progression_state = progression
	GameController.monster_missing = data["monster_missing"]
	GameController.window_history = data.get("window_history", {}).duplicate()
	return true


func _read_save() -> Dictionary:
	last_error = "Save missing or invalid."
	if not FileAccess.file_exists(save_path):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(save_path)) != OK:
		return {}
	var value: Variant = parser.data
	if not value is Dictionary or value.get("version") != VERSION:
		return {}
	if not value.get("game") is Dictionary or not value.get("village") is Dictionary or not value.get("abyss") is String:
		return {}
	if not value.get("monster_missing") is bool:
		return {}
	if not value.get("window_history", {}) is Dictionary:
		return {}
	for key in value.get("window_history", {}):
		if not key is String or not value.window_history[key] is bool:
			return {}
	if not value.get("progression") is String:
		return {}
	var game: Dictionary = value["game"]
	var keys := ["day", "trips_left", "flesh", "rations", "potions", "village_health", "health", "stamina"]
	if game.size() != keys.size():
		return {}
	for key in keys:
		var number: Variant = game.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or number < 0 or number != int(number):
			return {}
	if game.day < 1 or game.day > 10 or game.trips_left > 3 or game.village_health > 100:
		return {}
	if not _valid_village(value["village"]):
		return {}
	var state := AbyssRoomState.new()
	if state.restore(value["abyss"]) != OK:
		return {}
	var progression := AbyssProgressionState.new()
	if progression.restore(value["progression"]) != OK:
		return {}
	last_error = ""
	return value


func _valid_village(data: Dictionary) -> bool:
	if not data.get("villagers") is Array or not data.get("building_levels") is Dictionary:
		return false
	if data.villagers.is_empty() or data.villagers.size() > VillageManager.config.max_population:
		return false
	for field in ["hunger", "current_day"]:
		if data.has(field):
			var number: Variant = data[field]
			var maximum: int = VillageManager.config.hunger_threshold if field == "hunger" else 10
			if not (number is int or number is float) or not is_finite(float(number)) or number != int(number) or number < 0 or number > maximum:
				return false
	var ids: Array = []
	var counts := {}
	for building: BuildingData in VillageManager.get_buildings():
		var level: Variant = data.building_levels.get(String(building.id))
		if not (level is int or level is float) or level < 1 or level > building.max_level() or level != int(level):
			return false
	for entry in data.villagers:
		if not entry is Dictionary or not entry.get("id") is float and not entry.get("id") is int:
			return false
		if entry.id < 1 or ids.has(entry.id) or not entry.get("name") is String or not entry.get("is_bum") is bool:
			return false
		ids.append(entry.id)
		if not entry.get("assignment") is String or not entry.get("known_professions") is Array:
			return false
		for trade in entry.known_professions:
			if not trade is String or not data.building_levels.has(trade):
				return false
		var job: String = entry.assignment
		if job != "":
			if entry.is_bum or not data.building_levels.has(job) or not entry.known_professions.has(job):
				return false
			counts[job] = int(counts.get(job, 0)) + 1
			if counts[job] > data.building_levels[job]:
				return false
	for key in ["fallen", "pending_refugees", "used_names"]:
		if not data.get(key) is Array:
			return false
	for entry in data.fallen:
		if not entry is Dictionary or not entry.get("name") is String or not entry.get("day") is float and not entry.get("day") is int or not entry.get("cause") is String:
			return false
	for entry in data.pending_refugees:
		if not entry is Dictionary or not entry.get("name") is String or not entry.get("is_bum") is bool:
			return false
	for name_value in data.used_names:
		if not name_value is String:
			return false
	if not data.get("is_first_day") is bool or not data.get("rng_state") is String or not data.rng_state.is_valid_int():
		return false
	var next_id: Variant = data.get("next_id")
	if not (next_id is int or next_id is float):
		return false
	return next_id == int(next_id) and next_id > ids.max()
