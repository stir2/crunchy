extends SceneTree
## Exercise runtime profile selection without writing saves or streaming a world.
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var game := root.get_node("GameController")
	var scene := load("res://Scenes/Underground/abyss_runtime.tscn") as PackedScene
	game.run_length = 5
	game.reset_run()
	var short_world := scene.instantiate() as AbyssRuntime
	short_world.auto_start = false
	root.add_child(short_world)
	var state := AbyssRoomState.new()
	check(short_world._configure_world(state), "New short world configuration failed")
	var first_seed := short_world.configuration.global_seed
	check(short_world.progression_configuration.depth_chunks == 0
		and short_world.progression_configuration.level_width_chunks == 2
		and short_world.progression_configuration.fragment_interval == 25, "New short profile is wrong")
	var snapshot := JSON.stringify(state.world_settings)
	check(short_world._configure_world(state), "Short world reconfiguration failed")
	check(short_world.configuration.global_seed == first_seed
		and JSON.stringify(state.world_settings) == snapshot, "Reentry regenerated the seed or layout")
	check(short_world._configure_world(AbyssRoomState.new()), "Second new short world configuration failed")
	check(short_world.configuration.global_seed != first_seed, "New short world reused the previous seed")
	short_world.free()
	# A saved compact world must retain every old generation input and progression ID.
	var region := AbyssRegionConfig.new()
	region.global_seed = 514087
	region.open_threshold = 1.0
	var routes := AbyssRouteConfig.new()
	routes.main_route_horizontal_wander = 0.0
	routes.main_path_stretch = 1.0
	routes.branching_probability = 0.25
	routes.branch_min_length = 1
	routes.branch_max_length = 2
	routes.room_density = 0.28
	routes.secondary_branch_probability = 0.0
	routes.inter_chunk_loop_probability = 0.0
	routes.attachment_band_height = 2
	var progression := AbyssProgressionConfig.new()
	progression.level_width_chunks = 2
	progression.depth_chunks = 2
	progression.fragment_interval = 8
	var configs: Array[Resource] = [region,routes,AbyssTerrainConfig.new(),progression]
	state = AbyssRoomState.new()
	state.world_settings = AbyssRuntimeWorldSettings.capture(configs,load("res://Scenes/Underground/Rooms/authored_registry.tres"))
	snapshot = JSON.stringify(state.world_settings)
	var legacy := scene.instantiate() as AbyssRuntime
	legacy.auto_start = false
	root.add_child(legacy)
	check(legacy._configure_world(state), "Existing compact save configuration failed")
	check(JSON.stringify(state.world_settings) == snapshot, "Existing compact save was retuned")
	check(legacy.configuration.global_seed == 514087 and legacy.progression_configuration.depth_chunks == 2,
		"Existing compact save lost its original seed or bounds")
	legacy.free()
	# The same runtime still uses untouched default configuration for a new ten-day world.
	game.run_length = 10
	game.reset_run()
	var classic := scene.instantiate() as AbyssRuntime
	classic.auto_start = false
	root.add_child(classic)
	check(classic._configure_world(AbyssRoomState.new()), "Classic world configuration failed")
	check(classic.configuration.global_seed == AbyssRegionConfig.new().global_seed
		and classic.configuration.open_threshold == 0.36
		and classic.progression_configuration.level_width_chunks == 3
		and classic.progression_configuration.fragment_interval == 50
		and classic.progression_configuration.depth_chunks == 0, "Classic generation settings changed")
	classic.free()
	await process_frame
	print("Short campaign profile: failures=",failures)
	quit(int(failures > 0))
