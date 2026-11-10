class_name AbyssEnemyPool
extends Resource
@export var entries: Array[AbyssEnemyPoolEntry] = []

static func roll(identity: String, domain: String) -> float:
	return float((domain + ":" + identity).sha256_text().substr(0, 8).hex_to_int()) / 4294967296.0

func select(level: int, identity: String) -> AbyssEnemyPoolEntry:
	var total := 0.0
	for entry in entries:
		if entry.scene != null: total += entry.weight(level)
	if total <= 0.0: return null
	var choice := roll(identity, "enemy_type") * total
	for entry in entries:
		if entry.scene == null: continue
		choice -= entry.weight(level)
		if choice < 0.0: return entry
	return null

func find(id: String) -> AbyssEnemyPoolEntry:
	for entry in entries:
		if String(entry.enemy_id) == id: return entry
	return null
