class_name VillageSim
extends RefCounted
## Pure village rules. No autoloads and no scenes, so it can run in headless tests.
## Handles villager assignments, training memory, building capacity, toll evaluation,
## starvation, and village health calculation.

var config: VillageConfig
var rng := RandomNumberGenerator.new()
var villagers: Array[Villager] = []
var building_levels: Dictionary = {}
# Everyone the village lost: {name, day, cause, was_bum}
var fallen: Array[Dictionary] = []
var pending_refugees: Array[Dictionary] = []
var is_first_day := true
var _next_id := 1
var _used_names: Array[String] = []


func _init(p_config: VillageConfig, seed_value: int = 0) -> void:
	config = p_config
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	# All buildings start at level 1 (empty)
	for b: BuildingData in config.get_buildings():
		building_levels[b.id] = 1

	# Starting population: 3 workers, 1 bum. All unassigned.
	for i in config.starting_workers:
		add_villager("", false)
	for i in config.starting_bums:
		add_villager("", true)


func population() -> int:
	return villagers.size()


func employed_count() -> int:
	var count := 0
	for v in villagers:
		if v.is_employed():
			count += 1
	return count


func get_villager(id: int) -> Villager:
	for v in villagers:
		if v.id == id:
			return v
	return null


func get_bums() -> Array[Villager]:
	var result: Array[Villager] = []
	for v in villagers:
		if v.is_bum:
			result.append(v)
	return result


func get_idle_workers() -> Array[Villager]:
	var result: Array[Villager] = []
	for v in villagers:
		if not v.is_bum and not v.is_employed():
			result.append(v)
	return result


func add_villager(p_name: String = "", is_bum: bool = false) -> Villager:
	var v := Villager.new()
	v.id = _next_id
	_next_id += 1
	v.is_bum = is_bum
	v.display_name = p_name if p_name != "" else _draw_name(v.id, is_bum)
	villagers.append(v)
	return v


func _draw_name(fallback_index: int, is_bum: bool) -> String:
	var free: Array[String] = []
	for n in config.villager_names:
		if not _used_names.has(n):
			free.append(n)
	var chosen := ("Bum %d" if is_bum else "Villager %d") % fallback_index
	if not free.is_empty():
		chosen = free[rng.randi_range(0, free.size() - 1)]
	_used_names.append(chosen)
	return chosen


func remove_villager(id: int, cause: StringName, day: int) -> Villager:
	var v := get_villager(id)
	if v == null:
		return null
	villagers.erase(v)
	fallen.append({"name": v.display_name, "day": day, "cause": String(cause), "was_bum": v.is_bum})
	return v


func random_villager_id() -> int:
	if villagers.is_empty():
		return -1
	return villagers[rng.randi_range(0, villagers.size() - 1)].id


func get_building(id: StringName) -> BuildingData:
	for b in config.get_buildings():
		if b.id == id:
			return b
	return null


func building_level(id: StringName) -> int:
	return int(building_levels.get(id, 0))


func building_capacity(id: StringName) -> int:
	var b := get_building(id)
	if b == null:
		return 0
	return b.worker_capacity(building_level(id))


func workers_of(building_id: StringName) -> Array[Villager]:
	var list: Array[Villager] = []
	for v in villagers:
		if v.assignment == building_id:
			list.append(v)
	return list


func is_staffed(building_id: StringName) -> bool:
	return not workers_of(building_id).is_empty()


func upgrade_cost(id: StringName) -> int:
	var b := get_building(id)
	if b == null:
		return -1
	return b.cost_to_upgrade(building_level(id))


func upgrade(id: StringName) -> bool:
	if upgrade_cost(id) < 0:
		return false
	building_levels[id] = building_level(id) + 1
	return true


func can_assign(villager_id: int, target: StringName) -> bool:
	var v := get_villager(villager_id)
	if v == null or v.is_bum:
		return false
	if target == Villager.QUEUE:
		return true
	if not building_levels.has(target):
		return false
	if v.assignment == target:
		return true
	if workers_of(target).size() >= building_capacity(target):
		return false
	return true


## Ration cost to assign or train. 0 for queue, learned trades, or Day 1 free picks.
func assignment_cost(villager_id: int, target: StringName) -> int:
	if not can_assign(villager_id, target):
		return -1
	if target == Villager.QUEUE:
		return 0
	var v := get_villager(villager_id)
	if v.assignment == target or v.knows_profession(target):
		return 0
	if is_first_day and v.known_professions.is_empty():
		return 0
	return config.training_cost


func assign(villager_id: int, target: StringName) -> bool:
	if not can_assign(villager_id, target):
		return false
	var v := get_villager(villager_id)
	if target != Villager.QUEUE:
		v.learn_profession(target)
	v.assignment = target
	return true


func stat_bonuses() -> Dictionary:
	var out := {}
	for b in config.get_buildings():
		if b.stat_key == "":
			continue
		var count := workers_of(b.id).size()
		if count > 0:
			out[b.stat_key] = int(out.get(b.stat_key, 0)) + b.bonus_per_worker * count
	return out


func effect(key: String) -> float:
	var total := 0.0
	for b in config.get_buildings():
		var count := workers_of(b.id).size()
		if count > 0:
			total += float(b.extras_per_worker.get(key, 0.0)) * count
	return total


func free_potions() -> int:
	return int(effect("free_potions"))


func production() -> int:
	return employed_count() * config.rations_per_worker


func bonus_rations_for(flesh: int, quota: int) -> int:
	var excess := maxi(flesh - quota, 0)
	return mini(int(excess * config.bonus_rations_per_excess_flesh), config.bonus_rations_cap)


func calc_village_health(fed: bool, nobody_died: bool) -> int:
	var pop := population()
	if pop <= 0:
		return 0
	var alive_score := clampf(float(pop) / float(config.healthy_population), 0.0, 1.0)
	var employed_score := float(employed_count()) / float(pop)
	var score := config.weight_alive * alive_score + config.weight_employed * employed_score
	score += config.weight_fed * (1.0 if fed else 0.0)
	score += config.weight_no_deaths * (1.0 if nobody_died else 0.0)
	var total := config.weight_alive + config.weight_employed + config.weight_fed + config.weight_no_deaths
	return clampi(roundi(100.0 * score / total), 0, 100)


func _queue_refugee_candidate() -> Dictionary:
	var is_bum := rng.randf() >= config.refugee_worker_chance
	var candidate_name := _draw_name(_next_id + pending_refugees.size(), is_bum)
	var candidate := {
		"name": candidate_name,
		"is_bum": is_bum,
	}
	pending_refugees.append(candidate)
	return candidate


func poll_refugee() -> Dictionary:
	if pending_refugees.is_empty() or population() >= config.max_population:
		return {}
	return pending_refugees[0]


func accept_refugee() -> Villager:
	if pending_refugees.is_empty() or population() >= config.max_population:
		return null
	var candidate: Dictionary = pending_refugees.pop_front()
	return add_villager(candidate.get("name", ""), candidate.get("is_bum", false))


func dismiss_refugee() -> void:
	if not pending_refugees.is_empty():
		pending_refugees.pop_front()


func has_pending_refugee() -> bool:
	return not pending_refugees.is_empty() and population() < config.max_population


func arrive_refugee() -> Villager:
	if pending_refugees.is_empty():
		_queue_refugee_candidate()
	return accept_refugee()


func evaluate_toll(flesh: int, quota: int) -> Dictionary:
	var met := flesh >= quota
	var miss_ratio := 0.0
	if not met and quota > 0:
		miss_ratio = float(quota - flesh) / float(quota)
	return {
		"met": met,
		"miss_ratio": miss_ratio,
		"player_chooses": (not met) and (miss_ratio <= config.choose_threshold),
	}


func settle_night(day: int, flesh: int, quota: int, rations: int, toll_met: bool,
		taken_id: int) -> Dictionary:
	is_first_day = false
	var report := {
		"day": day, "flesh": flesh, "quota": quota, "toll_met": toll_met,
		"taken": "", "produced": 0, "bonus": 0, "upkeep": 0, "starved": "", "fed": true,
		"rations": rations, "village_health": 0, "refugee_coming": false,
		"population": population(), "wiped": false,
	}

	if population() == 0:
		report["wiped"] = true
		return report

	# Daytime production: everyone alive today worked their shift
	var produced := production()
	var bonus := bonus_rations_for(flesh, quota) if toll_met else 0
	rations += produced + bonus

	# Night toll: if missed, monster takes the victim
	var taken: Villager = null
	if taken_id > 0:
		taken = remove_villager(taken_id, &"taken", day)
		if taken != null:
			report["taken"] = taken.display_name

	# Upkeep: surviving villagers eat dinner
	var upkeep := population()
	var fed := rations >= upkeep
	var starved := ""

	if fed:
		rations -= upkeep
	else:
		rations = 0
		var victim := remove_villager(random_villager_id(), &"starved", day)
		if victim != null:
			starved = victim.display_name

	report["produced"] = produced
	report["bonus"] = bonus
	report["upkeep"] = upkeep
	report["starved"] = starved
	report["fed"] = fed
	report["rations"] = rations
	report["population"] = population()

	if population() == 0:
		report["wiped"] = true
		return report

	var nobody_died := (taken == null) and (starved == "")
	var v_health := calc_village_health(fed, nobody_died)
	report["village_health"] = v_health

	pending_refugees.clear()
	if population() < config.max_population:
		var chance := config.refugee_base_chance if toll_met else config.refugee_missed_toll_chance
		if rng.randf() < chance:
			_queue_refugee_candidate()
			# High village health and met toll can bring a rare second traveler
			if toll_met and v_health >= config.refugee_double_min_health and (population() + pending_refugees.size()) < config.max_population:
				if rng.randf() < config.refugee_double_chance:
					_queue_refugee_candidate()

	report["refugee_coming"] = not pending_refugees.is_empty()
	report["refugee_count"] = pending_refugees.size()
	return report


func to_dict() -> Dictionary:
	var vs: Array = []
	for v in villagers:
		vs.append(v.to_dict())
	var levels := {}
	for key in building_levels:
		levels[String(key)] = building_levels[key]
	var refs: Array = []
	for r in pending_refugees:
		refs.append(r.duplicate())
	return {
		"villagers": vs,
		"building_levels": levels,
		"fallen": fallen.duplicate(true),
		"pending_refugees": refs,
		"is_first_day": is_first_day,
		"next_id": _next_id,
		"used_names": _used_names.duplicate(),
		"rng_state": str(rng.state),
	}


func load_dict(d: Dictionary) -> void:
	if d.has("rng_state"):
		rng.state = int(d["rng_state"])
	villagers.clear()
	for entry in d.get("villagers", []):
		villagers.append(Villager.from_dict(entry))
	building_levels.clear()
	var levels: Dictionary = d.get("building_levels", {})
	for key in levels:
		building_levels[StringName(key)] = int(levels[key])
	fallen.clear()
	for f in d.get("fallen", []):
		fallen.append(f)
	pending_refugees.clear()
	for r in d.get("pending_refugees", []):
		pending_refugees.append(r.duplicate())
	if pending_refugees.is_empty() and not d.get("pending_refugee", {}).is_empty():
		pending_refugees.append(d.get("pending_refugee", {}).duplicate())
	is_first_day = bool(d.get("is_first_day", false))
	_next_id = int(d.get("next_id", 1))
	_used_names.clear()
	for n in d.get("used_names", []):
		_used_names.append(String(n))
