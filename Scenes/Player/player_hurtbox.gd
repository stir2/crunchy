class_name PlayerHurtbox
extends Area2D
## Detection only. Future damage code decides what an incoming area means.
signal damage_area_entered(area: Area2D)
signal damage_area_exited(area: Area2D)


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _on_area_entered(area: Area2D) -> void:
	damage_area_entered.emit(area)


func _on_area_exited(area: Area2D) -> void:
	damage_area_exited.emit(area)
