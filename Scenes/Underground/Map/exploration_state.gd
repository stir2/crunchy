class_name AbyssExplorationState
extends RefCounted
## Save-owned exploration and carried Flesh. Banked Flesh stays in GameController.
signal changed
signal flesh_collected(world: String, amount: int, origin: Vector2)
var visited: Dictionary = {} # world -> {"x:y": {x,y}}
var graves: Dictionary = {} # world -> latest grave
## Legacy storage name retained for compatibility; values are current-descent Flesh.
var descent_souls: Dictionary = {}
var active_descents: Dictionary = {}
var checkpoint_heals: Dictionary = {} # world -> checkpoint IDs healed in this descent
var grave_serial: int = 0

static func room_key(coords: Vector2i) -> String:
	return "%d:%d" % [coords.x,coords.y]

func is_visited(world: String, coords: Vector2i) -> bool:
	return visited.get(world,{}).has(room_key(coords))

func visit(world: String, coords: Vector2i) -> bool:
	if is_visited(world,coords): return false
	if not visited.has(world): visited[world] = {}
	visited[world][room_key(coords)] = {"x":coords.x,"y":coords.y}
	changed.emit()
	return true

func visited_rooms(world: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for entry: Dictionary in visited.get(world,{}).values():
		result.append(Vector2i(int(entry.x),int(entry.y)))
	result.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result

func current_flesh(world: String) -> int:
	return int(descent_souls.get(world,0))

func begin_descent(world: String) -> bool:
	# A repeated begin or an unreturned balance must never silently lose Flesh.
	if active_descents.get(world,false) or current_flesh(world) > 0: return false
	active_descents[world] = true
	checkpoint_heals[world] = {}
	descent_souls[world] = 0
	changed.emit()
	return true

func checkpoint_heal_available(world: String, id: String) -> bool:
	return not checkpoint_heals.get(world,{}).has(id)

func use_checkpoint_heal(world: String, id: String) -> bool:
	if not checkpoint_heal_available(world,id): return false
	if not checkpoint_heals.has(world): checkpoint_heals[world] = {}
	checkpoint_heals[world][id] = true
	changed.emit()
	return true

func add_descent_flesh(world: String, amount: int, origin: Vector2 = Vector2.INF) -> bool:
	if amount <= 0: return false
	active_descents[world] = true
	descent_souls[world] = current_flesh(world)+amount
	# The balance is already authoritative; HUD flight completion never awards it.
	flesh_collected.emit(world,amount,origin)
	changed.emit()
	return true

func take_descent_flesh(world: String) -> int:
	var amount := current_flesh(world)
	if amount == 0 and not active_descents.get(world,false): return 0
	descent_souls[world] = 0
	active_descents[world] = false
	changed.emit()
	return amount

## Compatibility aliases for the map's original minimal grave ledger.
func add_descent_souls(world: String, amount: int) -> void:
	add_descent_flesh(world,amount)

func take_descent_souls(world: String) -> int:
	return take_descent_flesh(world)

func record_death(world: String, coords: Vector2i, position: Vector2, loss_fraction: float = 0.5) -> Dictionary:
	var amount := floori(current_flesh(world) * clampf(loss_fraction, 0.0, 1.0))
	descent_souls[world] = 0
	active_descents[world] = false
	grave_serial += 1
	var grave := {"id":"%s/grave/%d" % [world,grave_serial],"world":world,
		"x":coords.x,"y":coords.y,"position_x":position.x,"position_y":position.y,"souls":amount}
	graves[world] = grave
	changed.emit()
	return grave.duplicate(true)

func recover_grave(world: String, id: String, origin: Vector2 = Vector2.INF) -> Dictionary:
	var grave: Dictionary = graves.get(world,{})
	if grave.is_empty() or grave.id != id: return {}
	graves.erase(world) # Clear before signaling, so repeated recovery cannot pay twice.
	active_descents[world] = true
	descent_souls[world] = current_flesh(world)+int(grave.souls)
	if int(grave.souls) > 0: flesh_collected.emit(world,int(grave.souls),origin)
	changed.emit()
	return grave.duplicate(true)

func serialize() -> Dictionary:
	return {"version":1,"visited":visited.duplicate(true),"graves":graves.duplicate(true),
		"descent_souls":descent_souls.duplicate(true),"active_descents":active_descents.duplicate(true),"checkpoint_heals":checkpoint_heals.duplicate(true),"grave_serial":grave_serial}

static func _integer(value: Variant, minimum: int = -2147483648) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == int(value) and value >= minimum

func restore(data: Dictionary) -> Error:
	if data.is_empty(): return OK # Saves predating exploration.
	if data.get("version") != 1: return ERR_INVALID_DATA
	for key in ["visited","graves","descent_souls"]:
		if not data.get(key) is Dictionary: return ERR_INVALID_DATA
	if not _integer(data.get("grave_serial"),0): return ERR_INVALID_DATA
	for world in data.visited:
		if not world is String or not data.visited[world] is Dictionary: return ERR_INVALID_DATA
		for key in data.visited[world]:
			var entry: Variant = data.visited[world][key]
			if not key is String or not entry is Dictionary or not _integer(entry.get("x")) or not _integer(entry.get("y")): return ERR_INVALID_DATA
			if key != room_key(Vector2i(int(entry.x),int(entry.y))): return ERR_INVALID_DATA
	for world in data.graves:
		var grave: Variant = data.graves[world]
		if not world is String or not grave is Dictionary or grave.get("world") != world or not grave.get("id") is String: return ERR_INVALID_DATA
		for key in ["x","y","souls"]:
			if not _integer(grave.get(key),0 if key == "souls" else -2147483648): return ERR_INVALID_DATA
		for key in ["position_x","position_y"]:
			if not (grave.get(key) is int or grave.get(key) is float) or not is_finite(float(grave[key])): return ERR_INVALID_DATA
	for world in data.descent_souls:
		if not world is String or not _integer(data.descent_souls[world],0): return ERR_INVALID_DATA
	var active: Variant = data.get("active_descents",{})
	if not active is Dictionary: return ERR_INVALID_DATA
	for world in active:
		if not world is String or not active[world] is bool: return ERR_INVALID_DATA
	var heals: Variant = data.get("checkpoint_heals",{})
	if not heals is Dictionary: return ERR_INVALID_DATA
	for world in heals:
		if not world is String or not heals[world] is Dictionary: return ERR_INVALID_DATA
		for id in heals[world]:
			if not id is String or not heals[world][id] is bool or not heals[world][id]: return ERR_INVALID_DATA
	checkpoint_heals = heals.duplicate(true)
	active_descents = active.duplicate(true)
	visited = data.visited.duplicate(true)
	graves = data.graves.duplicate(true)
	descent_souls = data.descent_souls.duplicate(true)
	# JSON numbers decode as floats; retain canonical integer coordinates/counts.
	for rooms: Dictionary in visited.values():
		for entry: Dictionary in rooms.values():
			entry.x = int(entry.x)
			entry.y = int(entry.y)
	for grave: Dictionary in graves.values():
		for key in ["x","y","souls"]: grave[key] = int(grave[key])
	for world in descent_souls: descent_souls[world] = int(descent_souls[world])
	grave_serial = int(data.grave_serial)
	changed.emit()
	return OK
