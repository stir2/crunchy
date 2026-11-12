class_name AbyssMapView
extends Control
signal checkpoint_selected(id: String)

var selectable_checkpoints: Dictionary = {}
var selected_checkpoint := ""
var show_player := true
var marker_scale := 1.0
var pin_gates := true
var _press_position := Vector2.INF
@export var marker_scene: PackedScene = preload("res://Scenes/Underground/Map/map_marker.tscn")
@export_range(24.0,128.0,1.0) var room_spacing: float = 64.0
var graph: Dictionary = {"nodes":{},"edges":[],"markers":[]}
var room_pixels: float = 640.0
var center: Vector2 = Vector2.ZERO
var map_zoom: float = 1.0
var minimum_zoom := 0.35
var player_position: Vector2
var _dragging: bool = false
var _icons: Array[Node2D] = []

func _ready() -> void:
	resized.connect(_refresh_positions)

func world_to_screen(point: Vector2) -> Vector2:
	return size*0.5+(point-center)*(room_spacing*map_zoom/room_pixels)

func set_graph(value: Dictionary, pixels: float, player: Vector2) -> void:
	graph = value
	room_pixels = pixels
	player_position = player
	for icon in _icons:
		remove_child(icon)
		icon.queue_free()
	_icons.clear()
	for marker: Dictionary in graph.markers:
		var icon := marker_scene.instantiate() as Node2D
		icon.kind = marker.kind
		icon.active = marker.active
		icon.scale = Vector2.ONE * marker_scale
		add_child(icon)
		_icons.append(icon)
	var player_icon := marker_scene.instantiate() as Node2D
	player_icon.kind = "player"
	player_icon.visible = show_player
	player_icon.scale = Vector2.ONE * marker_scale
	add_child(player_icon)
	_icons.append(player_icon)
	_refresh_positions()

func select_checkpoint(id: String) -> void:
	selected_checkpoint = id
	queue_redraw()

func recenter() -> void:
	center = player_position
	_dragging = false
	_refresh_positions()

func pan_screen(delta: Vector2) -> void:
	center -= delta*room_pixels/(room_spacing*map_zoom)
	_refresh_positions()

func zoom_at(factor: float, cursor: Vector2) -> void:
	var anchor := center+(cursor-size*0.5)*room_pixels/(room_spacing*map_zoom)
	map_zoom = clampf(map_zoom*factor,minimum_zoom,3.0)
	center = anchor-(cursor-size*0.5)*room_pixels/(room_spacing*map_zoom)
	_refresh_positions()

func _refresh_positions() -> void:
	for index in range(_icons.size()):
		var point: Vector2 = graph.markers[index].position if index < graph.markers.size() else player_position
		_icons[index].position = world_to_screen(point)
		if index < graph.markers.size() and graph.markers[index].kind == "gate" and pin_gates:
			_icons[index].position = _gate_screen_position(point)
	queue_redraw()

func _gate_screen_position(point: Vector2) -> Vector2:
	var offset := world_to_screen(point)-size*0.5
	var extent := (size*0.5-Vector2(24,24)).max(Vector2.ONE)
	var scale_down := maxf(1.0,maxf(absf(offset.x)/extent.x,absf(offset.y)/extent.y))
	return size*0.5+offset/scale_down

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_position = event.position
			elif _press_position.distance_to(event.position) <= 5.0:
				var nearest := 16.0
				var id := ""
				for marker: Dictionary in graph.markers:
					if marker.kind != "checkpoint" or not selectable_checkpoints.has(marker.id): continue
					var distance := world_to_screen(marker.position).distance_to(event.position)
					if distance < nearest:
						nearest = distance
						id = marker.id
				if not id.is_empty(): checkpoint_selected.emit(id)
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]:
			_dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.2,event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		if _press_position.distance_to(event.position) > 5.0 or selectable_checkpoints.is_empty():
			_press_position = Vector2.INF
			pan_screen(event.relative)
		accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.025,0.035,0.045,0.98))
	draw_rect(Rect2(Vector2.ONE,size-Vector2(2,2)),Color(0.44,0.38,0.32),false,2.0)
	for edge: Dictionary in graph.edges:
		var points: PackedVector2Array = edge.points
		if edge.unlocked_gate:
			var glow := PackedVector2Array()
			for point in points: glow.append(world_to_screen(point))
			var glow_color: Color = edge.from_color.lerp(edge.to_color,0.5)
			glow_color.a = 0.14
			draw_polyline(glow,glow_color,6,true)
		var start := world_to_screen(points[0])
		var end := world_to_screen(points[1])
		var middle := start.lerp(end,0.5)
		draw_line(start,middle,edge.from_color,1.5,true)
		draw_line(middle,end,edge.to_color,1.5,true)
	for node: Dictionary in graph.nodes.values():
		draw_circle(world_to_screen(node.position),3.5 if node.visited else 3.0,node.color,true,-1,true)
	for marker: Dictionary in graph.markers:
		if marker.kind == "checkpoint" and marker.id == selected_checkpoint:
			draw_arc(world_to_screen(marker.position), 12, 0, TAU, 24, Color(1, 0.82, 0.45), 2, true)
		if marker.kind != "gate" or not pin_gates: continue
		var target := world_to_screen(marker.position)
		var pinned := _gate_screen_position(marker.position)
		if target.is_equal_approx(pinned): continue
		var direction := (target-pinned).normalized()
		var tip := pinned+direction*16.0
		var color := Color(0.5,1,0.75) if marker.active else Color(0.8,0.65,0.45)
		draw_line(pinned,tip,color,1.5,true)
		draw_line(tip,tip-direction.rotated(0.6)*6.0,color,1.5,true)
		draw_line(tip,tip-direction.rotated(-0.6)*6.0,color,1.5,true)
