extends SceneTree
## Display lag never changes money. The real SaveManager uses a temporary slot.
var checks: int = 0
var failures: int = 0
var hud: AbyssFleshHUD
var game: Node
var world: String = "flesh-smoke-world"

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func tick(count: int = 1) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame

func finish_flights() -> void:
	for id in hud._pending.keys(): hud.complete_arrival(int(id))

func run() -> void:
	game = root.get_node("GameController")
	game.abyss_room_state = AbyssRoomState.new()
	game.abyss_progression_state = AbyssProgressionState.new()
	game.flesh = 146
	var region := AbyssRegionConfig.new()
	var seed_before := region.global_seed
	var configs: Array[Resource] = [region,AbyssRouteConfig.new(),AbyssTerrainConfig.new(),AbyssProgressionConfig.new()]
	var settings := AbyssRuntimeWorldSettings.capture(configs,load("res://Scenes/Underground/Rooms/authored_registry.tres"))
	var json_settings: Dictionary = JSON.parse_string(JSON.stringify(settings))
	check(AbyssRuntimeWorldSettings.apply(json_settings,configs) and region.global_seed == seed_before,"World ID seed rounded on save/load")
	var source := Node2D.new()
	root.add_child(source)
	hud = load("res://Scenes/Underground/HUD/flesh_hud.tscn").instantiate() as AbyssFleshHUD
	root.add_child(hud)
	hud.flight_seconds = 1.0 # Explicit arrivals below isolate accounting from wall-clock jitter.
	var state: AbyssExplorationState = game.abyss_room_state.exploration
	check(game.begin_abyss_descent(world) and not game.begin_abyss_descent(world),"Begin must initialize once without resetting twice")
	hud.bind_state(game,state,world,source)
	await tick()
	check(hud.previous_label.text == "146" and hud.current_label.text == "+ 0","Both balances must always be displayed")
	check(hud.previous_label.get_theme_color("font_color") == hud.previous_color and hud.current_label.get_theme_color("font_color") == hud.current_color,"HUD colors not applied")
	check(hud.row is HBoxContainer and hud.icon.texture != null,"Icon and counters must use replaceable horizontal layout")
	check(game.collect_descent_flesh(world,24,Vector2(200,200),"room/0:0/pickup-a"),"Pickup award rejected")
	check(game.flesh == 146 and state.current_flesh(world) == 24,"Pickup must immediately change only carried Flesh")
	check(hud.displayed_previous == 146 and hud.displayed_current == 0 and hud.pending_amount() == 24,"Pickup did not defer only the blue display")
	check(not game.collect_descent_flesh(world,24,Vector2.ZERO,"room/0:0/pickup-a"),"Duplicate stable pickup paid twice")
	var id: int = hud._pending.keys()[0]
	var assigned: int = hud._pending[id].amount
	hud.complete_arrival(id)
	hud.complete_arrival(id)
	check(hud.displayed_current == assigned and state.current_flesh(world) == 24 and game.flesh == 146,"Arrival duplicated display or authoritative balance")
	check(hud._bounce != null and hud.displayed_previous == 146,"Icon arrival did not bounce or changed gray value")
	finish_flights()
	check(hud.current_label.text == "+ 24" and hud.previous_label.text == "146","Final pickup displays incorrect")
	# A second pickup remains in flight across a real save/load round trip.
	game.collect_descent_flesh(world,6,Vector2.ZERO,"room/0:0/pickup-b")
	check(state.current_flesh(world) == 30 and hud.displayed_current == 24,"Second pickup balance/display coupling")
	var host: Node = load("res://Scenes/Main/main.tscn").instantiate()
	root.add_child(host)
	current_scene = host
	host.change_scene("res://Scenes/Village/House/house.tscn")
	await tick()
	var saves := root.get_node("SaveManager")
	saves.save_path = "/tmp/crunchy-flesh-hud-smoke.json"
	check(saves.save_game(),"Save during flight failed: "+saves.last_error)
	check(saves.load_game(),"Flesh save/load failed: "+saves.last_error)
	state = game.abyss_room_state.exploration
	hud.bind_state(game,state,world,source)
	check(game.flesh == 146 and state.current_flesh(world) == 30 and hud.displayed_current == 30,"Load did not restore independent authoritative balances")
	check(hud._pending.is_empty() and hud.displayed_previous == 146,"Old flights survived rebinding")
	check(not game.collect_descent_flesh(world,24,Vector2.ZERO,"room/0:0/pickup-a"),"Saved pickup collected twice")
	await tick(90)
	check(hud.displayed_current == 30 and game.flesh == 146,"Stale callbacks awarded Flesh after load")
	check(game.return_abyss_descent(world) == 30 and game.return_abyss_descent(world) == 0,"Return did not transfer exactly once")
	check(game.flesh == 176 and state.current_flesh(world) == 0,"Return failed to bank carried Flesh")
	check(hud.previous_label.text == "176" and hud.current_label.text == "+ 0","Return displays not synchronized")
	check(game.begin_abyss_descent(world) and hud.current_label.text == "+ 0","New descent did not begin at zero")
	game.collect_descent_flesh(world,9,Vector2.ZERO,"room/1:0/pickup-c")
	var late: int = hud._pending.keys()[0]
	var grave := state.record_death(world,Vector2i(1,0),Vector2(700,100))
	hud.complete_arrival(late)
	check(game.flesh == 176 and state.current_flesh(world) == 0 and int(grave.souls) == 4,"Death touched bank or failed half-Flesh grave rule")
	check(hud.previous_label.text == "176" and hud.current_label.text == "+ 0" and hud._pending.is_empty(),"Death retained blue display or pending flights")
	check(game.begin_abyss_descent(world),"New descent rejected after death")
	game.collect_descent_flesh(world,2,Vector2.ZERO,"room/2:0/pickup-d")
	finish_flights()
	check(not state.recover_grave(world,grave.id,Vector2(200,200)).is_empty(),"Prior descent grave recovery failed")
	check(game.flesh == 176 and state.current_flesh(world) == 6 and hud.displayed_current == 2 and hud.pending_amount() == 4,"Grave must credit current descent immediately but animate blue display")
	check(state.recover_grave(world,grave.id).is_empty(),"Grave recovered twice")
	finish_flights()
	check(hud.current_label.text == "+ 6" and hud.previous_label.text == "176","Grave animated wrong displayed balance")
	# Let actual Tween arrivals finish one small pickup too.
	hud.flight_seconds = 0.05
	hud.flight_stagger = 0.0
	game.collect_descent_flesh(world,3,Vector2(300,200),"room/2:0/pickup-e")
	await tick(12)
	check(hud.displayed_current == 9 and state.current_flesh(world) == 9 and hud._pending.is_empty(),"Automatic icon arrival accounting failed")
	check(not game.begin_abyss_descent(world) and state.current_flesh(world) == 9,"Repeated begin discarded carried balance")
	game.collect_descent_flesh(world,5,Vector2.ZERO,"room/2:0/pickup-f")
	check(game.return_abyss_descent(world) == 14,"Return while icons in flight missed authoritative Flesh")
	await tick(12)
	check(game.flesh == 190 and hud.previous_label.text == "190" and hud.current_label.text == "+ 0","Late return callbacks double-counted Flesh")
	check(game.current_descent_flesh("another-world") == 0,"Carried Flesh leaked between worlds")
	DirAccess.remove_absolute(saves.save_path)
	hud.unbind()
	hud.queue_free()
	source.queue_free()
	host.queue_free()
	await process_frame
	print("Flesh HUD/descent accounting: ",checks," checks; failures=",failures)
	quit(1 if failures else 0)
