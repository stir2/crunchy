extends "res://Scenes/Underground/Progression/special_interactable.gd"
## A painted door blocks its own opening as well as the shared level boundary.
func _refresh() -> void:
	super._refresh()
	var open := request.progression.is_gate_unlocked(request.definition)
	$DoorBody/CollisionShape2D.set_deferred("disabled",open)
