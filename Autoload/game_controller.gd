extends Node
## Global game state (autoload "GameController"): day loop, souls, Rations, stats.
## The numbers here are placeholders until the quota table exists.

signal day_started(day: int)
## quota_met is false when the monster should take a villager.
signal day_ended(day: int, quota_met: bool)
signal finale_reached(village_health: int)
signal trips_changed(trips_left: int)
signal souls_changed(souls: int)
signal rations_changed(rations: int)
signal village_health_changed(village_health: int)
signal stats_changed(stats: Dictionary)
signal health_changed(current: int, max_health: int)
signal stamina_changed(current: int, max_stamina: int)

const RUN_LENGTH := 10
const TRIPS_PER_DAY := 3
# 4 starting villagers, 2 days of upkeep each
const STARTING_RATIONS := 8

const BASE_STATS := {
	"max_health": 100,
	"damage": 10,
	"max_stamina": 100,
	"map_range": 1,
}

## Persistent abyss mutations survive scene/chunk unloading and later descents.
## Save/load code can serialize/restore this store independently of generation.
var abyss_room_state := AbyssRoomState.new()

var day: int = 1
var trips_left: int = TRIPS_PER_DAY:
	set(value):
		trips_left = maxi(value, 0)
		trips_changed.emit(trips_left)
# Souls banked today. Only the toll spends them, and they reset every day.
var souls: int = 0:
	set(value):
		souls = maxi(value, 0)
		souls_changed.emit(souls)
var rations: int = STARTING_RATIONS:
	set(value):
		rations = maxi(value, 0)
		rations_changed.emit(rations)
var village_health: int = 100:
	set(value):
		village_health = clampi(value, 0, 100)
		village_health_changed.emit(village_health)

# Chief vitals that carry over between descents
var health: int = 100:
	set(value):
		var max_hp: int = stats.get("max_health", 100) if stats != null else 100
		health = clampi(value, 0, max_hp)
		health_changed.emit(health, max_hp)

var stamina: int = 100:
	set(value):
		var max_sta: int = stats.get("max_stamina", 100) if stats != null else 100
		stamina = clampi(value, 0, max_sta)
		stamina_changed.emit(stamina, max_sta)

# BASE_STATS plus building bonuses. Read it from anywhere, but change bonuses
# through set_stat_bonus() so stats_changed fires.
var stats: Dictionary = BASE_STATS.duplicate()
var stat_bonuses: Dictionary = {}


func _ready() -> void:
	recalculate_stats()
	start_day()


# Placeholder curve, replace once the quota table is tuned.
func quota_for_day(for_day: int) -> int:
	return 5 + 3 * (for_day - 1)


func current_quota() -> int:
	return quota_for_day(day)


func set_stat_bonus(key: String, value: int) -> void:
	stat_bonuses[key] = value
	recalculate_stats()


func recalculate_stats() -> void:
	stats = BASE_STATS.duplicate()
	for key in stat_bonuses:
		stats[key] = stats.get(key, 0) + stat_bonuses[key]
	var max_hp: int = stats.get("max_health", 100)
	var max_sta: int = stats.get("max_stamina", 100)
	health = mini(health, max_hp)
	stamina = mini(stamina, max_sta)
	stats_changed.emit(stats)


func add_souls(amount: int) -> void:
	souls += amount


func spend_rations(amount: int) -> bool:
	if rations < amount:
		return false
	rations -= amount
	return true


## Returns false when no trips are left. Dying in the abyss also costs a trip.
func use_trip() -> bool:
	if trips_left <= 0:
		return false
	trips_left -= 1
	return true


func start_day() -> void:
	souls = 0
	trips_left = TRIPS_PER_DAY
	health = stats.get("max_health", 100)
	stamina = stats.get("max_stamina", 100)
	day_started.emit(day)


## Called when the player sleeps at the desk. The last day has no toll, so
## it hands off to the finale instead of starting another day.
func end_day() -> void:
	if day >= RUN_LENGTH:
		return
	day_ended.emit(day, souls >= current_quota())
	day += 1
	if day >= RUN_LENGTH:
		finale_reached.emit(village_health)
	else:
		start_day()
