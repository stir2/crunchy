extends Node
## Root scene. Holds whichever top-level scene is active (house, abyss, cutscene).
## Switch scenes with: get_tree().current_scene.change_scene("res://Scenes/...tscn")

const HOUSE_SCENE := "res://Scenes/Village/House/house.tscn"
const CUTSCENE_SCENE := "res://Scenes/Cutscene/toll_cutscene.tscn"
const MENU_SCENE := "res://Scenes/Menus/main_menu.tscn"
const PAUSE_SCENE := preload("res://Scenes/Menus/pause_menu.tscn")

var active_scene: Node
var active_path := ""
var pause_menu: CanvasLayer


func _ready() -> void:
	pause_menu = PAUSE_SCENE.instantiate()
	add_child(pause_menu)
	change_scene(MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and active_path != MENU_SCENE:
		pause_menu.toggle()
		get_viewport().set_input_as_handled()


func start_new_game() -> void:
	VillageManager.start_new_run()
	change_scene(CUTSCENE_SCENE)


func continue_game() -> bool:
	if not SaveManager.load_game():
		return false
	change_scene(HOUSE_SCENE)
	return true


func change_scene(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("change_scene: could not load %s" % path)
		return
	if active_scene != null:
		remove_child(active_scene)
		active_scene.queue_free()
	active_path = path
	DebugMenu.close()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	active_scene = packed.instantiate()
	add_child(active_scene)
