class_name AbyssEntranceSpawn
extends RefCounted
## Find existing support/clearance. Never carve terrain or paint a spawn platform.
static func find(player: Player, stream: AbyssRoomStreamer, entrance: Vector2i) -> Dictionary:
	var origin := stream.container.to_global(Vector2(entrance)*stream.room_pixels)
	var preferred := origin + Vector2(stream.room_pixels.x*0.5,48)
	var candidates: Array[Vector2] = []
	var room_size := stream.routes.get_chunk(Vector2i.ZERO).config.room_size
	var pixels := stream.selector.select_room(stream.routes,entrance).requirements.tile_pixels
	for dy in range(0,3):
		for dx in range(-2,3):
			var coords := entrance+Vector2i(dx,dy)
			if stream.specials.level_at(coords) != 1 or not stream.room_ready(coords):
				continue
			var room_origin := Vector2(coords)*stream.room_pixels
			for y in range(2,room_size.y):
				for x in range(1,room_size.x-1):
					candidates.append(stream.container.to_global(room_origin+Vector2((x+0.5)*pixels,y*pixels-0.25)))
	candidates.sort_custom(func(a: Vector2,b: Vector2) -> bool:
		var da := a.distance_squared_to(preferred)
		var db := b.distance_squared_to(preferred)
		return da < db if not is_equal_approx(da,db) else (a.y < b.y or (a.y == b.y and a.x < b.x)))
	for feet in candidates:
		if safe(player,feet):
			return {"kind":"entrance", "room_coords":stream.world_to_room(feet), "spawn_position":feet}
	return {}

static func find_checkpoint(player: Player, stream: AbyssRoomStreamer, checkpoint: Dictionary) -> Dictionary:
	var coords: Vector2i = checkpoint.room_coords
	var room := stream.rooms.get(coords) as AbyssAuthoredRoom
	if room == null:
		return {}
	for request in room.spawn_requests:
		if request.kind != &"checkpoint" or String(request.marker_id) != checkpoint.id:
			continue
		var preferred := room.to_global(request.local_position)
		var pixels := room.tile_pixels
		var candidates: Array[Vector2] = []
		for y in range(2, room.room_size.y):
			for x in range(1, room.room_size.x - 1):
				candidates.append(room.to_global(Vector2((x + 0.5) * pixels, y * pixels - 0.25)))
		candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return a.distance_squared_to(preferred) < b.distance_squared_to(preferred))
		for feet in candidates:
			if safe(player, feet):
				var result := checkpoint.duplicate()
				result["kind"] = "checkpoint"
				result["spawn_position"] = feet
				return result
	return {}

static func safe(player: Player, feet: Vector2) -> bool:
	var shape_node := player.get_node("CollisionShape2D") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape_node.shape
	query.transform = Transform2D(0,feet) * shape_node.transform
	query.collision_mask = player.collision_mask
	query.margin = 0.01
	query.exclude = [player.get_rid()]
	query.collide_with_areas = false
	var space := player.get_world_2d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():
		return false
	for x in [-12.0,12.0]:
		var support := PhysicsRayQueryParameters2D.create(feet+Vector2(x,-1),feet+Vector2(x,2),player.collision_mask)
		support.exclude = [player.get_rid()]
		if space.intersect_ray(support).is_empty():
			return false
	var previous := player.global_position
	player.global_position = feet
	var hazard: CombatHit = player.get_node("HazardDetector").overlapping_hit(1,Vector2.ZERO)
	player.global_position = previous
	return hazard == null
