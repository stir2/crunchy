extends Node
## Root scene. Holds whichever top-level scene is active (house, abyss, cutscene).
## Switch scenes with: get_tree().current_scene.change_scene("res://Scenes/...tscn")

const HOUSE_SCENE := "res://Scenes/Village/House/house.tscn"
const CUTSCENE_SCENE := "res://Scenes/Cutscene/toll_cutscene.tscn"
const MENU_SCENE := "res://Scenes/Menus/main_menu.tscn"
const PAUSE_SCENE := preload("res://Scenes/Menus/pause_menu.tscn")

var _transitioning: bool = false
var active_scene: Node
var active_path := ""
var pause_menu: CanvasLayer


func _ready() -> void:
	pause_menu = PAUSE_SCENE.instantiate()
	add_child(pause_menu)
	change_scene(MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and active_path != MENU_SCENE and not _transitioning:
		pause_menu.toggle()
		get_viewport().set_input_as_handled()


func start_new_game() -> void:
	if _transitioning:
		return
	SoundManager.queue_start_cue()
	VillageManager.start_new_run()
	transition_to_scene(CUTSCENE_SCENE, 0.85)


func continue_game() -> bool:
	if _transitioning:
		return false
	if not SaveManager.load_game():
		return false
	SoundManager.queue_start_cue()
	_continue_intro()
	return true


func change_scene(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("change_scene: could not load %s" % path)
		return
	if active_scene != null:
		DialogueManager.cancel()
		remove_child(active_scene)
		active_scene.queue_free()
	active_path = path
	DebugMenu.close()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	active_scene = packed.instantiate()
	add_child(active_scene)


## A single overlay owns each handoff and is freed even if its destination changes.
func _transition_overlay() -> CanvasLayer:
	var screen := CanvasLayer.new()
	screen.layer = 100
	var image: Image
	if DisplayServer.get_name() != "headless":
		image = get_viewport().get_texture().get_image()
	var cover: Control
	if image != null and not image.is_empty():
		var picture := TextureRect.new()
		picture.texture = ImageTexture.create_from_image(image)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cover = picture
	else:
		var black := ColorRect.new()
		black.color = Color.BLACK
		cover = black
	cover.name = "Cover"
	screen.add_child(cover)
	add_child(screen)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	return screen


func transition_to_scene(path: String, duration: float = 0.85) -> void:
	var source := active_scene
	while _transitioning:
		await get_tree().process_frame
		if not is_instance_valid(source) or active_scene != source:
			return
	_transitioning = true
	var screen := _transition_overlay()
	change_scene(path)
	# The incoming sequence can start its audio beneath the outgoing image.
	var fade := create_tween()
	fade.tween_property(screen.get_node("Cover"), "modulate:a", 0.0, duration).set_trans(Tween.TRANS_SINE)
	await fade.finished
	screen.queue_free()
	_transitioning = false


func _continue_intro() -> void:
	_transitioning = true
	var screen := _transition_overlay()
	var cover := screen.get_node("Cover") as Control
	var source := active_scene
	active_scene.process_mode = Node.PROCESS_MODE_DISABLED
	var darken := create_tween()
	darken.tween_property(cover, "modulate", Color(0.04, 0.04, 0.05, 1), 0.65)
	await SoundManager.play_transition_cues(screen)
	if not is_instance_valid(source) or active_scene != source:
		screen.queue_free()
		_transitioning = false
		return
	change_scene(HOUSE_SCENE)
	# Continue restores the house directly; it does not replay a morning quota.
	var reveal := create_tween()
	reveal.tween_property(cover, "modulate:a", 0.0, 0.85).set_trans(Tween.TRANS_SINE)
	await reveal.finished
	screen.queue_free()
	_transitioning = false
