extends Node
## Conversation selection and one-time thoughts. Dialogic handles the timelines.

signal conversation_started
signal conversation_finished
signal window_rumbled

const TEXT_ROOT := "res://Dialogue/"
const RUMOURS := [
	{"id": "food", "file": "food", "condition": "hungry"},
	{"id": "chief_blame", "file": "chief_blame", "condition": "loss"},
	{"id": "closer", "file": "closer", "condition": "late"},
	{"id": "chief_family", "file": "chief_family", "condition": "middle"},
	{"id": "doing_well", "file": "doing_well", "condition": "healthy"},
	{"id": "chief_desk", "file": "chief_desk", "condition": "after_first"},
	{"id": "cooking", "file": "cooking", "condition": "any"},
	{"id": "work", "file": "work", "condition": "any"},
	{"id": "home", "file": "home", "condition": "any"},
]

var busy := false
var current_id := ""
var lost_name := ""
var lost_fact := ""
var _layout: Node
var _daily_key := ""


func _ready() -> void:
	Dialogic.timeline_ended.connect(_on_finished)
	Dialogic.signal_event.connect(_on_signal)


func is_busy() -> bool:
	return busy or Dialogic.current_timeline != null


func talk_to_monster() -> void:
	if GameController.is_day_10():
		if not GameController.monster_missing:
			play("missing_monster", "Monster/missing_monster")
		return
	var file := "monster_early"
	if GameController.day >= 7:
		file = "monster_late"
	elif GameController.day >= 4:
		file = "monster_middle"
	if GameController.window_history.has(file):
		if GameController.day >= 4 and not GameController.window_history.has("ancestors"):
			play("ancestors", "Monster/ancestors")
		else:
			play("", "Monster/nothing_to_say")
	else:
		play(file, "Monster/" + file)


func listen_outside() -> void:
	if GameController.is_day_10():
		return
	# Recent losses come first, even if today's ordinary conversation was heard.
	var fallen := VillageManager.get_fallen()
	for i in range(fallen.size() - 1, -1, -1):
		var loss: Dictionary = fallen[i]
		var key := "loss_%d" % i
		if int(loss.day) < GameController.day - 2 or GameController.window_history.has(key):
			continue
		var file := "taken" if loss.cause == "taken" else "starved"
		if loss.cause == "taken" and bool(loss.get("was_bum", false)):
			file = "taken_bum"
		play(key, "Rumours/" + file, String(loss.name))
		return
	var daily_key := "listen_day_%d" % GameController.day
	if not GameController.window_history.has(daily_key):
		for rumour in RUMOURS:
			if not GameController.window_history.has(rumour.id) and _matches(rumour.condition):
				play(rumour.id, "Rumours/" + rumour.file, "", daily_key)
				return
	play("", "Rumours/nothing_else")


func _matches(condition: String) -> bool:
	match condition:
		"hungry":
			return GameController.rations < VillageManager.get_population()
		"late":
			return GameController.day >= 6
		"healthy":
			return GameController.village_health >= 70 and GameController.day > 1
		"loss":
			return not VillageManager.get_fallen().is_empty()
		"middle":
			return GameController.day >= 4
		"after_first":
			return GameController.day > 1
	return true


func action_thought(action: String) -> bool:
	if is_busy() or GameController.is_day_10():
		return false
	var daily_key := "thought_%s_day_%d" % [action, GameController.day]
	if GameController.window_history.has(daily_key):
		return false
	var choices: Array[String] = []
	match action:
		"manage":
			if not VillageManager.get_fallen().is_empty():
				choices.append("manage_loss")
			if GameController.rations < VillageManager.get_population():
				choices.append("manage_food")
			choices.append("manage_first")
		"descend":
			if GameController.health <= 2:
				choices.append("descend_hurt")
			if GameController.trips_left == 1:
				choices.append("descend_last")
			choices.append("descend_first")
	for file in choices:
		if not GameController.window_history.has(file):
			play(file, "Thoughts/" + file, "", daily_key)
			return true
	return false


func play(id: String, file: String, loss_name: String = "", daily_key: String = "") -> void:
	if is_busy():
		return
	var path := TEXT_ROOT + file + ".dtl"
	if not ResourceLoader.exists(path):
		push_error("Missing conversation: %s" % path)
		return
	lost_name = loss_name
	var facts := [
		"They loved cats. Knew every stray around here by name.",
		"They loved dogs. Always saved a bit of bread for them.",
		"They could name every bird around here. I never knew how.",
	]
	lost_fact = facts[posmod(loss_name.hash(), facts.size())]
	busy = true
	current_id = id
	_daily_key = daily_key
	DebugMenu.close()
	conversation_started.emit()
	_layout = Dialogic.Styles.load_style()
	await _layout.ready
	if not busy:
		return
	Dialogic.start(path)


func cancel() -> void:
	if not busy:
		return
	current_id = ""
	_daily_key = ""
	busy = false
	Dialogic.paused = false
	if Dialogic.current_timeline != null:
		Dialogic.end_timeline(true)
	elif is_instance_valid(_layout):
		_layout.queue_free()


func _on_signal(value: Variant) -> void:
	if busy and current_id == "missing_monster" and value == "window_rumble":
		window_rumbled.emit()


func _on_finished() -> void:
	if not busy:
		return
	if not current_id.is_empty():
		GameController.window_history[current_id] = true
	if not _daily_key.is_empty():
		GameController.window_history[_daily_key] = true
	if current_id == "missing_monster":
		GameController.monster_missing = true
	busy = false
	current_id = ""
	_daily_key = ""
	conversation_finished.emit()
