extends Node
## Root scene. Holds whichever top-level scene is active (house, abyss, cutscene).
## Switch scenes with: get_tree().current_scene.change_scene("res://Scenes/...tscn")

const HOUSE_SCENE := "res://Scenes/Village/House/house.tscn"
const CUTSCENE_SCENE := "res://Scenes/Cutscene/toll_cutscene.tscn"

var active_scene: Node


func _ready() -> void:
	change_scene(CUTSCENE_SCENE)


func change_scene(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("change_scene: could not load %s" % path)
		return
	if active_scene != null:
		active_scene.queue_free()
	active_scene = packed.instantiate()
	add_child(active_scene)
