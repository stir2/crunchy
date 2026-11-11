extends SceneTree
## Exercise real swing queries and dash collisions against grouped tile terrain.
var failures: int = 0
var player: Player
var room: AbyssAuthoredRoom
var state := AbyssRoomState.new()
var request := AbyssRoomConstructionRequest.new()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func tick() -> void:
	await physics_frame
	await process_frame

func make_room() -> AbyssAuthoredRoom:
	var result := AbyssAuthoredRoom.new()
	result.room_size = Vector2i(40,40)
	for layer_name in ["Solid","BreakableWalls"]:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = AbyssRoomTerrainBuilder.TILES
		result.add_child(layer)
	var floor_layer := result.get_node("Solid") as TileMapLayer
	for x in range(25):
		floor_layer.set_cell(Vector2i(x,13),0,Vector2i.ZERO)
	var walls := result.get_node("BreakableWalls") as TileMapLayer
	for y in range(10,13):
		walls.set_cell(Vector2i(10,y),0,Vector2i(5,0))
	result.breakables = AbyssBreakableTerrain.new()
	result.breakables.setup(result,request,state,AbyssTileGroups.describe(walls,&"breakable_test",{}),{})
	return result

func check_close_swing(x: float, facing: int, gap: float, expect_hit: bool) -> void:
	state = AbyssRoomState.new()
	request.breakable_health = 3.0
	room = make_room()
	root.add_child(room)
	player.reset_movement()
	player.position = Vector2(x,208)
	player._move_direction = facing
	player.update_facing_direction()
	# Narrow hitboxes used to pass entirely beyond a wall at touching distance.
	player.combat.hitbox_width = 16.0
	for frame in range(4): await tick()
	Input.action_press("Attack")
	await tick()
	Input.action_release("Attack")
	var froze := false
	for frame in range(150):
		await tick()
		froze = froze or player.combat.is_hitstopped()
		if not player.combat.is_attacking(): break
	check(room.breakables.groups()[0].health == (2.0 if expect_hit else 3.0),"Close swing damage incorrect: facing=%d gap=%s expected_hit=%s" % [facing,gap,expect_hit])
	check(froze == expect_hit,"Close swing hitstop incorrect")
	room.queue_free()
	await tick()

func run() -> void:
	request.requirements = AbyssRoomRequirements.new()
	request.template_id = &"breakable_test"
	room = make_room()
	root.add_child(room)
	player = load("res://Scenes/Player/player.tscn").instantiate() as Player
	player.get_node("CombatController").mouse_aim_attacks = false
	root.add_child(player)
	player.position = Vector2(120,208)
	player.combat.repeat_while_held = false
	for frame in range(5): await tick()
	for swing in range(3):
		Input.action_press("Attack")
		await tick()
		Input.action_release("Attack")
		var saw_freeze := false
		for frame in range(150):
			await tick()
			saw_freeze = saw_freeze or player.combat.is_hitstopped()
			if not player.combat.is_attacking(): break
		check(saw_freeze,"Swing connection must freeze")
		check(room.breakables.groups()[0].health == maxf(0,2-swing),"Exactly one damage per group per swing")
	check(room.get_node("BreakableWalls").get_used_cells().is_empty(),"Three swings must remove wall")
	room.queue_free()
	await tick()
	room = make_room()
	root.add_child(room)
	check(room.get_node("BreakableWalls").get_used_cells().is_empty(),"Swing destruction must persist on reconstruction")
	room.queue_free()
	await tick()
	state = AbyssRoomState.new()
	room = make_room()
	root.add_child(room)
	player.reset_movement()
	player.position = Vector2(120,208)
	for frame in range(4): await tick()
	player.dash_direction = 1
	player.begin_dash()
	var connected := false
	for frame in range(30):
		await tick()
		if player.combat.is_hitstopped():
			connected = true
			check(player.velocity.x > 0,"Dash contact must preserve forward velocity without knockback")
			check(player.movement_state == Player.MovementState.DASHING,"Dash must survive connection")
			var position := player.position
			var remaining := player.dash_phase_frames_remaining
			await tick()
			check(player.position == position and player.dash_phase_frames_remaining == remaining,"Hitstop must preserve position and dash timer")
			break
	check(connected,"Dash collision must trigger hitstop")
	check(room.breakables.groups()[0].health == 0,"Dash must destroy default wall")
	for frame in range(player.combat.dash_breakable_hitstop_frames + 3): await tick()
	check(player.position.x > 145,"Dash must continue through destroyed wall after freeze")
	room.queue_free()
	await tick()
	state = AbyssRoomState.new()
	request.breakable_health = 9.0
	room = make_room()
	root.add_child(room)
	player.reset_movement()
	player.position = Vector2(120,208)
	for frame in range(4): await tick()
	player.dash_direction = 1
	player.begin_dash()
	for frame in range(30): await tick()
	check(room.breakables.groups()[0].health == 6.0,"A surviving group must take damage only once per dash")
	check(player.position.x < 146,"Surviving breakables must retain collision")
	for facing in [-1,1]:
		for gap in [0.0,4.0,24.0]:
			await check_close_swing(145.0-gap if facing == 1 else 191.0+gap,facing,gap,true)
		await check_close_swing(145.0-44.0 if facing == 1 else 191.0+44.0,facing,44.0,false)
	await check_close_swing(145.0,-1,0.0,false) # Do not hit a wall behind the swing.
	print("Player breakables: swing grouping, dash impact, hitstop, forward momentum and persistence; failures=",failures)
	quit(1 if failures else 0)
