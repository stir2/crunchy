extends Node2D

const HOUSE_SCENE := "res://Scenes/Village/House/house.tscn"

@onready var hp_bar: TextureProgressBar = $HUD/MarginContainer/VBoxContainer/HPBar
@onready var stamina_bar: TextureProgressBar = $HUD/MarginContainer/VBoxContainer/StaminaBar
@onready var return_button: Button = $HUD/MarginContainer/VBoxContainer/ReturnButton


func _ready() -> void:
	return_button.pressed.connect(_on_return_pressed)
	GameController.health_changed.connect(_on_health_changed)
	GameController.stamina_changed.connect(_on_stamina_changed)
	_refresh_bars()


func _refresh_bars() -> void:
	var max_hp: int = GameController.stats.get("max_health", 100)
	var max_sta: int = GameController.stats.get("max_stamina", 100)
	_on_health_changed(GameController.health, max_hp)
	_on_stamina_changed(GameController.stamina, max_sta)


func _on_health_changed(current: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = current


func _on_stamina_changed(current: int, max_sta: int) -> void:
	stamina_bar.max_value = max_sta
	stamina_bar.value = current


func _on_return_pressed() -> void:
	var main := get_tree().current_scene
	if main != null and main.has_method("change_scene"):
		main.change_scene(HOUSE_SCENE)
	else:
		get_tree().change_scene_to_file(HOUSE_SCENE)
