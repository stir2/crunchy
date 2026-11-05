class_name PlayerHazardDetector
extends Node
## Cache room providers on tree changes, then query only body-overlapping cells.
## No terrain mutation, per-tile nodes or per-frame scene/group discovery.
var _rooms: Array[Node2D] = []
@onready var player: CharacterBody2D = get_parent()
@onready var body: CollisionShape2D = player.get_node("CollisionShape2D")

func _ready() -> void:
	_discover(get_tree().root)
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)

func _discover(node: Node) -> void:
	_register(node)
	for child in node.get_children():
		_discover(child)

func _on_node_added(node: Node) -> void:
	_register(node)

func _register(node: Node) -> void:
	if node is Node2D and node.has_method("hazard_type_at") and not _rooms.has(node):
		_rooms.append(node)

func _on_node_removed(node: Node) -> void:
	if node is Node2D:
		_rooms.erase(node)

func overlapping_hit(damage: int, knockback: Vector2) -> CombatHit:
	var rectangle := body.shape as RectangleShape2D
	if rectangle == null or body.disabled:
		return null
	for room in _rooms:
		var layer := room.get_node_or_null("Hazards") as TileMapLayer
		if layer == null or layer.tile_set == null:
			continue
		# Transform the fixed physical body, never the mirrored sprite/hurtbox.
		var corners := PackedVector2Array()
		for corner in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
			corners.append(layer.to_local(body.to_global(corner * rectangle.size * 0.5)))
		var bounds := Rect2(corners[0], Vector2.ZERO)
		for corner in corners:
			bounds = bounds.expand(corner)
		var first := layer.local_to_map(bounds.position + Vector2(0.01,0.01))
		var last := layer.local_to_map(bounds.end - Vector2(0.01,0.01))
		if not layer.get_used_rect().intersects(Rect2i(first, last - first + Vector2i.ONE)):
			continue
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var center := layer.map_to_local(Vector2i(x,y))
				var world_center := layer.to_global(center)
				if room.hazard_type_at(world_center) != &"spike":
					continue
				var half := Vector2(layer.tile_set.tile_size) * 0.5
				var tile := PackedVector2Array([center-half, center+Vector2(half.x,-half.y), center+half, center+Vector2(-half.x,half.y)])
				if Geometry2D.intersect_polygons(corners, tile).is_empty():
					continue
				var hit := CombatHit.new()
				hit.amount = damage
				hit.source = room
				hit.world_position = world_center
				var side := signf(player.global_position.x - world_center.x)
				hit.direction = Vector2(side if side != 0.0 else -player.facing_direction, 0)
				hit.knockback = Vector2(absf(knockback.x) * hit.direction.x, knockback.y)
				return hit
	return null
