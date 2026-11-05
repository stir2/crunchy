class_name PlayerClimbing
extends Node
## Existing authored-room tile providers; no ladder colliders or placement system.
signal climbing_changed(attached: bool)
@export_range(1.0, 500.0, 1.0) var climb_speed: float = 200.0
@export_range(0.0, 100.0, 0.5) var stamina_drain_per_second: float = 5.0
@export_range(0.1, 100.0, 0.1) var minimum_attach_stamina: float = 1.0
var _attached: bool = false
var _reattach_requires_up_release: bool = false
var _moving_this_tick: bool = false
var _motion_start_y: float = 0.0
var _providers: Array[Node2D] = []
@onready var player: CharacterBody2D = get_parent()
@onready var detector: CollisionShape2D = player.get_node("ClimbDetector/CollisionShape2D")
@onready var stamina: StaminaComponent = player.get_node("Stamina")

func _ready() -> void:
	_discover(get_tree().root)
	get_tree().node_added.connect(_register)
	get_tree().node_removed.connect(_unregister)
	player.movement_reset.connect(detach)
	stamina.exhausted.connect(_on_exhausted)

func _discover(node: Node) -> void:
	_register(node)
	for child in node.get_children():
		_discover(child)

func _register(node: Node) -> void:
	if node is Node2D and node.has_method("climbable_layers") and not _providers.has(node):
		_providers.append(node)

func _unregister(node: Node) -> void:
	if node is Node2D:
		_providers.erase(node)

func is_climbing() -> bool:
	return _attached

func overlaps_climbable() -> bool:
	for provider in _providers:
		var layers: Array[TileMapLayer] = provider.climbable_layers()
		for layer in layers:
			if _overlaps_layer(layer):
				return true
	return false

func _overlaps_layer(layer: TileMapLayer) -> bool:
	var rectangle := detector.shape as RectangleShape2D
	if rectangle == null or not is_instance_valid(layer) or layer.tile_set == null or not layer.enabled:
		return false
	var corners := PackedVector2Array()
	for corner in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
		corners.append(layer.to_local(detector.to_global(corner * rectangle.size * 0.5)))
	var bounds := Rect2(corners[0], Vector2.ZERO)
	for corner in corners:
		bounds = bounds.expand(corner)
	var first := layer.local_to_map(bounds.position + Vector2(0.01,0.01))
	var last := layer.local_to_map(bounds.end - Vector2(0.01,0.01))
	if not layer.get_used_rect().intersects(Rect2i(first, last-first+Vector2i.ONE)):
		return false
	for y in range(first.y, last.y+1):
		for x in range(first.x, last.x+1):
			var cell := Vector2i(x,y)
			if not AbyssClimbableTiles.is_climbable(layer, cell):
				continue
			var center := layer.map_to_local(cell)
			var half := Vector2(layer.tile_set.tile_size) * 0.5
			var tile := PackedVector2Array([
				center-half, center+Vector2(half.x,-half.y),
				center+half, center+Vector2(-half.x,half.y)
			])
			if not Geometry2D.intersect_polygons(corners,tile).is_empty():
				return true
	return false

func begin_physics_tick() -> void:
	if not Input.is_action_pressed("Move Up") or Input.is_action_just_pressed("Move Up"):
		_reattach_requires_up_release = false
	if _attached:
		if player.damage.is_action_locked() or stamina.current_stamina <= 0.0 or not overlaps_climbable():
			detach()
		elif player.jump_buffer_frames_remaining > 0 and not player._ignore_jump_until_release:
			player.jump_from_climb() # Jump wins over simultaneous horizontal detachment.
		elif Input.is_action_just_pressed("Move Left") or Input.is_action_just_pressed("Move Right"):
			detach()
		return
	# Up may already be held when reaching the tiles. A previous detach still
	# requires releasing Up, so jumping/exhaustion cannot immediately grab again.
	if _reattach_requires_up_release or not Input.is_action_pressed("Move Up"):
		return
	if Input.is_action_pressed("Move Down") or Input.is_action_just_pressed("Jump"):
		return
	if player.damage.is_action_locked() or player.is_jump_charging() or player.combat.is_attacking():
		return
	if player.movement_state != Player.MovementState.NORMAL or not stamina.can_spend(minimum_attach_stamina):
		return
	if overlaps_climbable():
		player.cancel_jump_grace()
		player.clear_wall_momentum()
		player.velocity = Vector2.ZERO
		_attached = true
		climbing_changed.emit(true)

func apply_motion(_delta: float) -> void:
	var direction := Input.get_axis("Move Up", "Move Down")
	_motion_start_y = player.global_position.y
	_moving_this_tick = not is_zero_approx(direction)
	player.velocity = Vector2(0.0, direction * climb_speed)

func end_physics_tick(delta: float) -> void:
	# Charge actual vertical movement, not an input held against a floor/ceiling.
	if _moving_this_tick and not is_equal_approx(player.global_position.y, _motion_start_y):
		stamina.drain(stamina_drain_per_second * delta)
	_moving_this_tick = false
	if _attached and not overlaps_climbable():
		detach()

func _on_exhausted() -> void:
	if _attached:
		detach()
		player.velocity.y = maxf(0.0, player.velocity.y)

func detach() -> void:
	if _attached:
		_attached = false
		_reattach_requires_up_release = Input.is_action_pressed("Move Up")
		climbing_changed.emit(false)
