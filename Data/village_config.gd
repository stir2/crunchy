class_name VillageConfig
extends Resource
## Village configuration numbers for economy, staffing, toll, and balance.

@export_group("Start")
@export var starting_workers := 3
@export var starting_bums := 1
@export var max_population := 14
@export var healthy_population := 8

@export_group("Economy")
@export var training_cost := 2
@export var rations_per_worker := 2
@export var potion_cost := 3
@export var bonus_rations_per_excess_flesh := 0.25
@export var bonus_rations_cap := 4

@export_group("Toll")
@export_range(0.0, 1.0) var choose_threshold := 0.25

@export_group("Village health weights")
@export var weight_alive := 0.35
@export var weight_employed := 0.25
@export var weight_fed := 0.25
@export var weight_no_deaths := 0.15

@export_group("Refugees")
@export_range(0.0, 1.0) var refugee_base_chance := 1.0
@export_range(0.0, 1.0) var refugee_missed_toll_chance := 0.70
@export_range(0.0, 1.0) var refugee_double_chance := 0.25
@export var refugee_double_min_health := 70
@export_range(0.0, 1.0) var refugee_worker_chance := 0.75

@export_group("Names")
@export var villager_names := PackedStringArray([
	"Bob", "Gordon Freeman", "John", "Napoleon", "Paul", "Peter", "James", "Edward",
	"Heisenberg", "Glorb", "Grishma", "Sinclair", "Kajta", "Viktoria", "Alex", "Aria",
	"G-man", "Gerald", "Jerry",
])

@export_group("Buildings")
@export var buildings: Array[BuildingData] = []

var _default_buildings: Array[BuildingData] = []


func get_buildings() -> Array[BuildingData]:
	if not buildings.is_empty():
		return buildings
	if _default_buildings.is_empty():
		_default_buildings.append(BuildingData.make(
			&"apothecary", "Apothecary", "max_health", 2,
			{"free_potions": 1.0}, PackedInt32Array([8, 16])))
		_default_buildings.append(BuildingData.make(
			&"blacksmith", "Blacksmith", "damage", 2,
			{"stun_seconds": 0.15}, PackedInt32Array([8, 16])))
		_default_buildings.append(BuildingData.make(
			&"farmer", "Farmer", "max_stamina", 15,
			{"stamina_regen_pct": 10.0}, PackedInt32Array([8, 16])))
		_default_buildings.append(BuildingData.make(
			&"tailor", "Tailor", "speed", 8,
			{}, PackedInt32Array([8, 16])))
	return _default_buildings
