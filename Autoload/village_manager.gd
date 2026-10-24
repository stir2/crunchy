extends Node
## Autoload "VillageManager". Glue between VillageSim and the rest of the game.
## UI and abyss code talk to this, never to VillageSim directly.

signal villagers_changed
signal buildings_changed
signal villager_left(villager_name: String, cause: StringName)
signal victim_choice_requested(candidates: Array)
signal refugee_waiting(candidate: Dictionary)
signal refugee_arrived(villager_name: String, is_worker: bool)
signal night_resolved(report: Dictionary)
signal village_wiped

const CONFIG_PATH := "res://Data/village_config.tres"

var sim: VillageSim
var config: VillageConfig
var _choosing := false
var _toll: Dictionary = {}


func _ready() -> void:
	GameController.night_started.connect(_on_night_started)
	GameController.day_started.connect(_on_day_started)
	new_game()
	_grant_daily_potions()


func new_game(seed_value: int = 0) -> void:
	config = null
	if ResourceLoader.exists(CONFIG_PATH):
		config = load(CONFIG_PATH) as VillageConfig
	if config == null:
		config = VillageConfig.new()
	sim = VillageSim.new(config, seed_value)
	_choosing = false
	GameController.village_health = sim.calc_village_health(true, true)
	_sync_stats()
	GameController.heal_to_full()
	villagers_changed.emit()
	buildings_changed.emit()


func start_new_run(seed_value: int = 0) -> void:
	GameController.reset_run()
	new_game(seed_value)
	GameController.start_day()


func get_villagers() -> Array[Villager]:
	return sim.villagers


func get_buildings() -> Array[BuildingData]:
	return config.get_buildings()


func get_building(building_id: StringName) -> BuildingData:
	return sim.get_building(building_id)


func get_building_level(building_id: StringName) -> int:
	return sim.building_level(building_id)


func get_building_capacity(building_id: StringName) -> int:
	return sim.building_capacity(building_id)


func is_staffed(building_id: StringName) -> bool:
	return sim.is_staffed(building_id)


func get_workers_of(building_id: StringName) -> Array[Villager]:
	return sim.workers_of(building_id)


func get_idle_workers() -> Array[Villager]:
	return sim.get_idle_workers()


func get_bums() -> Array[Villager]:
	return sim.get_bums()


func can_assign(villager_id: int, target: StringName) -> bool:
	if _choosing:
		return false
	return sim.can_assign(villager_id, target)


func assignment_cost(villager_id: int, target: StringName) -> int:
	return sim.assignment_cost(villager_id, target)


func upgrade_cost(building_id: StringName) -> int:
	return sim.upgrade_cost(building_id)


func get_population() -> int:
	return sim.population()


func get_fallen() -> Array[Dictionary]:
	return sim.fallen


func get_effect(key: String) -> float:
	return sim.effect(key)


func night_preview() -> Dictionary:
	var flesh := GameController.flesh
	var quota := GameController.current_quota()
	var met := flesh >= quota
	return {
		"flesh": flesh,
		"quota": quota,
		"toll_met": met,
		"rations": GameController.rations,
		"food_cost": sim.population(),
		"expected_production": sim.production(),
		"expected_bonus": sim.bonus_rations_for(flesh, quota) if met else 0,
	}


func assign(villager_id: int, target: StringName) -> bool:
	if _choosing or not sim.can_assign(villager_id, target):
		return false
	var cost := sim.assignment_cost(villager_id, target)
	if cost < 0:
		return false
	if cost > 0 and not GameController.spend_rations(cost):
		return false
	if not sim.assign(villager_id, target):
		return false
	_sync_stats()
	villagers_changed.emit()
	buildings_changed.emit()
	return true


func upgrade_building(building_id: StringName) -> bool:
	if _choosing:
		return false
	var cost := sim.upgrade_cost(building_id)
	if cost < 0 or not GameController.spend_rations(cost):
		return false
	sim.upgrade(building_id)
	_sync_stats()
	buildings_changed.emit()
	return true


func buy_potion() -> bool:
	if _choosing or not GameController.spend_rations(config.potion_cost):
		return false
	GameController.add_potions(1)
	return true


func choose_victim(villager_id: int) -> bool:
	if not _choosing or sim.get_villager(villager_id) == null:
		return false
	_choosing = false
	_settle(villager_id)
	return true


func accept_refugee() -> bool:
	var v := sim.accept_refugee()
	if v != null:
		_sync_stats()
		villagers_changed.emit()
		refugee_arrived.emit(v.display_name, not v.is_bum)
		check_next_refugee()
		return true
	return false


func dismiss_refugee() -> void:
	sim.dismiss_refugee()
	check_next_refugee()


func check_next_refugee() -> void:
	var candidate := sim.poll_refugee()
	if not candidate.is_empty():
		refugee_waiting.emit(candidate)


func get_save_data() -> Dictionary:
	return sim.to_dict()


func load_save_data(data: Dictionary) -> void:
	sim.load_dict(data)
	_sync_stats()
	villagers_changed.emit()
	buildings_changed.emit()


func _on_night_started(day: int, flesh: int, quota: int) -> void:
	_toll = sim.evaluate_toll(flesh, quota)
	_toll["day"] = day
	_toll["flesh"] = flesh
	_toll["quota"] = quota
	if bool(_toll["met"]):
		_settle(0)
	elif bool(_toll["player_chooses"]):
		_choosing = true
		victim_choice_requested.emit(sim.villagers.duplicate())
	else:
		_settle(sim.random_villager_id())


func _settle(taken_id: int) -> void:
	var victim: Villager = sim.get_villager(taken_id) if taken_id > 0 else null
	if victim != null:
		villager_left.emit(victim.display_name, &"taken")
	var report := sim.settle_night(
		int(_toll["day"]), int(_toll["flesh"]), int(_toll["quota"]),
		GameController.rations, bool(_toll["met"]), taken_id)
	if report["starved"] != "":
		villager_left.emit(String(report["starved"]), &"starved")
	GameController.rations = int(report["rations"])
	if bool(report["wiped"]):
		GameController.village_health = 0
		villagers_changed.emit()
		night_resolved.emit(report)
		village_wiped.emit()
		return
	GameController.village_health = int(report["village_health"])
	_sync_stats()
	villagers_changed.emit()
	buildings_changed.emit()
	night_resolved.emit(report)
	GameController.finish_night(bool(report["toll_met"]))


func _on_day_started(_day: int) -> void:
	check_next_refugee()
	_grant_daily_potions()


func _grant_daily_potions() -> void:
	GameController.add_potions(sim.free_potions())


func _sync_stats() -> void:
	GameController.set_stat_bonuses(sim.stat_bonuses())
