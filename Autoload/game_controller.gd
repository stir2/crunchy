extends Node
## Global game state (autoload "GameController"): day loop, flesh, rations, potions, stats.
## Village rules live in VillageManager.

signal day_started(day: int)
## Emitted after the night is fully resolved. quota_met is false when someone was taken.
signal day_ended(day: int, quota_met: bool)
## Emitted when the player sleeps. VillageManager resolves the night, then calls finish_night().
signal night_started(day: int, flesh: int, quota: int)
signal finale_reached(village_health: int)
signal trips_changed(trips_left: int)
signal flesh_changed(flesh: int)
signal rations_changed(rations: int)
signal potions_changed(potions: int)
signal village_health_changed(village_health: int)
signal stats_changed(stats: Dictionary)
signal health_changed(current: int, max_health: int)
signal stamina_changed(current: int, max_stamina: int)

const RUN_LENGTH := 10
const TRIPS_PER_DAY := 3
# 4 starting villagers, 2 days of upkeep each
const STARTING_RATIONS := 8
# Health is in half-hearts: 2 HP = 1 full heart
const HP_PER_HEART := 2
const POTION_HEAL := 2

const QUOTA_TABLE: Array[int] = [12, 18, 25, 40, 48, 58, 70, 84, 98, 0]

const BASE_STATS := {
	"max_health": 6,
	"damage": 10,
	"max_stamina": 100,
	"speed": 0,
}

## Persistent abyss mutations survive scene/chunk unloading and later descents.
## Save/load code can serialize/restore this store independently of generation.
var abyss_room_state := AbyssRoomState.new()
var abyss_progression_state := AbyssProgressionState.new()

var day: int = 1
var night_in_progress := false
var monster_missing := false
var trips_left: int = TRIPS_PER_DAY:
	set(value):
		trips_left = maxi(value, 0)
		trips_changed.emit(trips_left)
# Flesh banked today. Only the toll spends it, and it resets every day.
var flesh: int = 0:
	set(value):
		flesh = maxi(value, 0)
		flesh_changed.emit(flesh)
var rations: int = STARTING_RATIONS:
	set(value):
		rations = maxi(value, 0)
		rations_changed.emit(rations)
var potions: int = 0:
	set(value):
		potions = maxi(value, 0)
		potions_changed.emit(potions)
var village_health: int = 100:
	set(value):
		village_health = clampi(value, 0, 100)
		village_health_changed.emit(village_health)

# Chief vitals that carry over between descents
var health: int = 6:
	set(value):
		var max_hp: int = stats.get("max_health", 6) if stats != null else 6
		health = clampi(value, 0, max_hp)
		health_changed.emit(health, max_hp)

var stamina: int = 100:
	set(value):
		var max_sta: int = stats.get("max_stamina", 100) if stats != null else 100
		stamina = clampi(value, 0, max_sta)
		stamina_changed.emit(stamina, max_sta)

# BASE_STATS plus building bonuses. Read it from anywhere, but change bonuses
# through set_stat_bonuses() so stats_changed fires.
var stats: Dictionary = BASE_STATS.duplicate()
var stat_bonuses: Dictionary = {}


func _ready() -> void:
	recalculate_stats()
	start_day()


func quota_for_day(for_day: int) -> int:
	if for_day >= 1 and for_day <= QUOTA_TABLE.size():
		return QUOTA_TABLE[for_day - 1]
	return 0


func current_quota() -> int:
	return quota_for_day(day)


func is_day_10() -> bool:
	return day == RUN_LENGTH


func set_stat_bonus(key: String, value: int) -> void:
	stat_bonuses[key] = value
	recalculate_stats()


func set_stat_bonuses(bonuses: Dictionary) -> void:
	stat_bonuses = bonuses.duplicate()
	recalculate_stats()


func recalculate_stats() -> void:
	stats = BASE_STATS.duplicate()
	for key in stat_bonuses:
		stats[key] = stats.get(key, 0) + stat_bonuses[key]
	var max_hp: int = stats.get("max_health", 6)
	var max_sta: int = stats.get("max_stamina", 100)
	health = mini(health, max_hp)
	stamina = mini(stamina, max_sta)
	stats_changed.emit(stats)


func heal_to_full() -> void:
	health = stats.get("max_health", 6)
	stamina = stats.get("max_stamina", 100)


func add_flesh(amount: int) -> void:
	flesh += amount


func add_rations(amount: int) -> void:
	rations += amount


func spend_rations(amount: int) -> bool:
	if rations < amount:
		return false
	rations -= amount
	return true


func add_potions(amount: int) -> void:
	potions += amount


func use_potion() -> bool:
	var max_hp: int = stats.get("max_health", 6)
	if potions <= 0 or health >= max_hp:
		return false
	potions -= 1
	health = mini(health + POTION_HEAL, max_hp)
	return true


## Returns false when no trips are left. Dying in the abyss also costs a trip.
func use_trip() -> bool:
	if trips_left <= 0:
		return false
	trips_left -= 1
	return true


## Trips are spent on descent, so trips_left == 0 means this is the third trip.
func is_last_trip() -> bool:
	return trips_left == 0


## Share of carried flesh lost on death: 50%, or 25% on the third descent.
func death_loss_fraction() -> float:
	return 0.25 if is_last_trip() else 0.5


func recover_from_death() -> void:
	var max_hp: int = stats.get("max_health", 6)
	health = clampi(maxi(health, 4), 1, max_hp)


## Wipes run state. Call VillageManager.start_new_run() instead of this.
func reset_run() -> void:
	abyss_progression_state = AbyssProgressionState.new()
	day = 1
	abyss_room_state = AbyssRoomState.new()
	monster_missing = false
	night_in_progress = false
	rations = STARTING_RATIONS
	potions = 0
	village_health = 100
	stat_bonuses = {}
	recalculate_stats()
	heal_to_full()


func start_day() -> void:
	_reset_daily_state()
	day_started.emit(day)
	if is_day_10():
		finale_reached.emit(village_health)


## Called when the player sleeps at the desk. The last day has no toll.
func end_day() -> void:
	if night_in_progress or day >= RUN_LENGTH:
		return
	night_in_progress = true
	night_started.emit(day, flesh, current_quota())


func finish_night(quota_met: bool) -> void:
	if not night_in_progress:
		return
	night_in_progress = false
	day_ended.emit(day, quota_met)
	day += 1
	if day > RUN_LENGTH:
		_reset_daily_state()
		finale_reached.emit(village_health)
	else:
		start_day()


func _reset_daily_state() -> void:
	flesh = 0
	trips_left = TRIPS_PER_DAY
	heal_to_full()
