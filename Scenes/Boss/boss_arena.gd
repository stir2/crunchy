extends Control
## Temporary destination for the Day 10 descent, until boss combat is ready.


func _ready() -> void:
	$Center/Buttons/ReturnButton.pressed.connect(func():
		get_tree().current_scene.change_scene("res://Scenes/Village/House/house.tscn"))
