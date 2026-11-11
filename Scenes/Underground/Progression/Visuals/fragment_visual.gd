extends "res://Scenes/Underground/Progression/special_placeholder.gd"
## Replaceable artwork; the existing interactable owns collection and persistence.
@export var first_half: Texture2D = preload("res://Assets/Tiles/keyhalf1_16x16.png")
@export var second_half: Texture2D = preload("res://Assets/Tiles/keyhalf2_16x16.png")
var half_index: int = 0

func set_state(value: bool) -> void:
	# Retain the collected half during its collection effect.
	if not value:
		var target := get_parent()
		if target.request != null and target.request.progression != null:
			half_index = AbyssKeyFragmentArt.next_half(target.request.progression.state, target.request.definition.world_level)
	super.set_state(value)

func _draw() -> void:
	var texture := first_half if half_index == 0 else second_half
	if texture != null:
		draw_texture_rect(texture, Rect2(-8, -8, 16, 16), false)
