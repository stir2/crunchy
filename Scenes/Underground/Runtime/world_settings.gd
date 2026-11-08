class_name AbyssRuntimeWorldSettings
extends RefCounted
const VERSION: int = 2
## Save exported generation inputs once; later descents ignore changed Inspector defaults.
## These primitive snapshots travel through the existing AbyssRoomState save payload.
static func capture(configs: Array[Resource], registry: AbyssRoomTemplateRegistry) -> Dictionary:
	var result := {"version":VERSION, "registry":registry.resource_path}
	for i in range(configs.size()):
		var values := {}
		for info in configs[i].get_property_list():
			if not (info.usage & PROPERTY_USAGE_STORAGE) or not (info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var value: Variant = configs[i].get(info.name)
			if value is Vector2i:
				value = [value.x, value.y]
			elif value is StringName:
				value = String(value)
			elif value is int and info.name == &"global_seed":
				value = str(value) # JSON numbers cannot preserve every 64-bit seed.
			values[info.name] = value
		result[str(i)] = values
	return result

static func apply(saved: Dictionary, configs: Array[Resource]) -> bool:
	if saved.get("version") != VERSION or not saved.get("registry") is String:
		return false
	for i in range(configs.size()):
		var values: Variant = saved.get(str(i))
		if not values is Dictionary:
			return false
		for info in configs[i].get_property_list():
			if not (info.usage & PROPERTY_USAGE_STORAGE) or not (info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			if not values.has(info.name):
				return false
			var value: Variant = values[info.name]
			if int(info.type) == TYPE_INT and info.name == &"global_seed" and value is String:
				if not value.is_valid_int() or str(value.to_int()) != value:
					return false
				value = value.to_int()
			match int(info.type):
				TYPE_VECTOR2I:
					if not value is Array or value.size() != 2:
						return false
					for part in value:
						if not (part is int or part is float) or not is_finite(float(part)) or part != int(part):
							return false
					value = Vector2i(int(value[0]),int(value[1]))
				TYPE_INT, TYPE_FLOAT:
					if not (value is int or value is float) or not is_finite(float(value)):
						return false
					if int(info.type) == TYPE_INT:
						if value != int(value):
							return false
						value = int(value)
				TYPE_BOOL:
					if not value is bool:
						return false
				TYPE_STRING_NAME:
					if not value is String:
						return false
					value = StringName(value)
			configs[i].set(info.name,value)
	return true

## Reject before touching room mutations, progression, day state or actor vitals.
static func compatibility_error(saved: Dictionary, region: AbyssRegionConfig, routes: AbyssRouteConfig) -> String:
	if saved.get("version") != VERSION:
		return "This abyss save uses the old room layout. It cannot enter the 40x40 runtime; the save and progression have been preserved. Start a separate new run to use the larger rooms."
	var dimensions: Variant = saved.get("0")
	var openings: Variant = saved.get("1")
	if not dimensions is Dictionary or not openings is Dictionary:
		return "Saved abyss layout data is missing or invalid; no progress was changed."
	if not _matches_size(dimensions.get("room_size"),region.room_size) or not _matches_size(dimensions.get("chunk_size"),region.chunk_size):
		return "Saved abyss room/chunk dimensions differ from this runtime. The save and progression have been preserved."
	if openings.get("opening_schema") != String(routes.opening_schema) or openings.get("opening_width") != routes.opening_width:
		return "Saved abyss openings are incompatible with this runtime. The save and progression have been preserved."
	return ""

static func _matches_size(value: Variant, expected: Vector2i) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for i in range(2):
		if not (value[i] is int or value[i] is float) or not is_finite(float(value[i])) or float(value[i]) != float(expected[i]):
			return false
	return true
