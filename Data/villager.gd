class_name Villager
extends RefCounted
## One villager. assignment is a building id, or QUEUE when unassigned.

const QUEUE := &""

var id: int = 0
var display_name: String = ""
var is_bum: bool = false
var assignment: StringName = QUEUE
var known_professions: Array[StringName] = []


func can_work() -> bool:
	return not is_bum


func is_employed() -> bool:
	return assignment != QUEUE


func knows_profession(building_id: StringName) -> bool:
	return known_professions.has(building_id)


func learn_profession(building_id: StringName) -> void:
	if not knows_profession(building_id):
		known_professions.append(building_id)


func to_dict() -> Dictionary:
	var profs: Array = []
	for p in known_professions:
		profs.append(String(p))
	return {
		"id": id,
		"name": display_name,
		"is_bum": is_bum,
		"assignment": String(assignment),
		"known_professions": profs,
	}


static func from_dict(d: Dictionary) -> Villager:
	var v := Villager.new()
	v.id = int(d.get("id", 0))
	v.display_name = String(d.get("name", ""))
	v.is_bum = bool(d.get("is_bum", false))
	v.assignment = StringName(d.get("assignment", ""))
	v.known_professions.clear()
	for p in d.get("known_professions", []):
		v.known_professions.append(StringName(p))
	return v
