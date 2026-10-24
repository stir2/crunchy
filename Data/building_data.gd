class_name BuildingData
extends Resource
## One building type. Capacity scales with level (level 1 = 1, level 2 = 2, etc).

@export var id: StringName = &""
@export var display_name: String = ""
# GameController stat this building raises per worker ("" for none).
@export var stat_key: String = ""
@export var bonus_per_worker: int = 0
# Other per-worker effects ("free_potions", "stun_seconds").
@export var extras_per_worker: Dictionary = {}
# Rations to go from level n to n+1. Index 0 is level 1 to 2.
@export var upgrade_costs: PackedInt32Array = PackedInt32Array()


func max_level() -> int:
	return upgrade_costs.size() + 1


func worker_capacity(level: int) -> int:
	return maxi(level, 1)


## Returns -1 when already at max level.
func cost_to_upgrade(level: int) -> int:
	if level < 1 or level > upgrade_costs.size():
		return -1
	return upgrade_costs[level - 1]


static func make(p_id: StringName, p_name: String, p_stat_key: String, p_bonus: int,
		p_extras: Dictionary, p_costs: PackedInt32Array) -> BuildingData:
	var b := BuildingData.new()
	b.id = p_id
	b.display_name = p_name
	b.stat_key = p_stat_key
	b.bonus_per_worker = p_bonus
	b.extras_per_worker = p_extras
	b.upgrade_costs = p_costs
	return b
