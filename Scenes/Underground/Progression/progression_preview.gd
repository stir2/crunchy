extends Node2D
## Lightweight whole-level overview; no physical terrain or player required.
@export var configuration: AbyssRegionConfig = AbyssRegionConfig.new()
@export var progression_configuration: AbyssProgressionConfig = AbyssProgressionConfig.new()
@export_range(50,200) var depth_rows: int = 100
var service: AbyssSpecialRooms
var entries: Array[Dictionary] = []
var rooms: Array[AbyssRoomData] = []
var cell := Vector2(6,6)
var origin_x: int
func _ready() -> void:
	regenerate()
func regenerate() -> void:
	var routes := AbyssRouteGenerator.new(configuration,AbyssRouteConfig.new(),progression_configuration)
	service = AbyssSpecialRooms.new(routes,progression_configuration,GameController.abyss_progression_state)
	entries.clear()
	rooms.clear()
	origin_x = progression_configuration.first_chunk_x*configuration.chunk_size.x
	var width := progression_configuration.level_width_chunks*configuration.chunk_size.x*3
	cell = Vector2(minf(7,(get_viewport_rect().size.x-40)/width),minf(7,(get_viewport_rect().size.y-90)/depth_rows))
	for y in range(depth_rows):
		for x in range(origin_x,origin_x+width):
			rooms.append(routes.regions.get_room(Vector2i(x,y)))
			entries.append_array(service.definitions_at(Vector2i(x,y)))
	queue_redraw()
	print("Special overview seed=",configuration.global_seed," checkpoints=",entries.filter(func(d: Dictionary) -> bool: return d.kind == "checkpoint").size()," fragments=",entries.filter(func(d: Dictionary) -> bool: return d.kind == "fragment").size()," gates=",entries.filter(func(d: Dictionary) -> bool: return d.kind == "gate").size())
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Preview Next Seed"):
		configuration.global_seed += 1
		regenerate()
func _draw() -> void:
	draw_string(ThemeDB.fallback_font,Vector2(20,22),"Special rooms — N: next seed | cyan checkpoint | gold fragment | red gate | vertical lines: sealed level borders",HORIZONTAL_ALIGNMENT_LEFT,-1,15)
	var offset := Vector2(20,55)
	for room in rooms:
		var point := Vector2(room.global_coords-Vector2i(origin_x,0))*cell+offset
		draw_rect(Rect2(point,cell),Color("365c69") if room.region == AbyssRoomData.Region.OPEN else Color("1c2433"))
	for definition in entries:
		var point := (Vector2(definition.x-origin_x,definition.y)+Vector2(0.5,0.5))*cell+offset
		draw_circle(point,2.5,Color.CYAN if definition.kind == "checkpoint" else (Color.GOLD if definition.kind == "fragment" else Color.ORANGE_RED))
	for level in range(4):
		var x := level*progression_configuration.level_width_chunks*configuration.chunk_size.x*cell.x+offset.x
		draw_line(Vector2(x,offset.y),Vector2(x,offset.y+depth_rows*cell.y),Color.ORANGE_RED,1)
