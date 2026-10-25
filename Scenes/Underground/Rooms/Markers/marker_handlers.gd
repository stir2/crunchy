class_name RoomMarkerHandlers
extends RefCounted
## Optional extension factories. Built-in markers also work without this registry.
static var _handlers: Dictionary = {}
static func register(kind: StringName, factory: Callable) -> void:
	_handlers[kind] = factory
static func unregister(kind: StringName) -> void:
	_handlers.erase(kind)
static func create(marker: RoomMarker) -> RoomSpawnRequest:
	var result := marker.make_request()
	if result != null:
		return result
	if _handlers.has(marker.kind()):
		var value: Variant = _handlers[marker.kind()].call(marker)
		if value is RoomSpawnRequest:
			return value
	return null
