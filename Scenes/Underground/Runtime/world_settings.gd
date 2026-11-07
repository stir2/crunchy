class_name AbyssRuntimeWorldSettings
extends RefCounted
## Save exported generation inputs once; later descents ignore changed Inspector defaults.
## These primitive snapshots travel through the existing AbyssRoomState save payload.
static func capture(configs: Array[Resource], registry: AbyssRoomTemplateRegistry) -> Dictionary:
	var result := {"version":1, "registry":registry.resource_path}
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
			values[info.name] = value
		result[str(i)] = values
	return result

static func apply(saved: Dictionary, configs: Array[Resource]) -> bool:
	if saved.get("version") != 1 or not saved.get("registry") is String:
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
	# Existing saved worlds keep their seed/topology, but use the updated physical
	# slot convention too. Explicit custom offsets and other schemas stay intact.
	for config in configs:
		if config is AbyssRouteConfig and config.opening_schema == &"abyss_slots_v1":
			if config.horizontal_offsets == Vector2i(6,17):
				config.horizontal_offsets = AbyssRouteConfig.DEFAULT_OPENING_OFFSETS
			if config.vertical_offsets == Vector2i(6,17):
				config.vertical_offsets = AbyssRouteConfig.DEFAULT_OPENING_OFFSETS
	return true
