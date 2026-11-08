extends InteractionTarget
## Travel-only main-entrance marker. Its position is the runtime's safe entry point.
@onready var runtime: AbyssRuntime = get_parent() as AbyssRuntime

func is_available(_actor: Node2D) -> bool:
	return false # E never extracts from an entrance.

func is_available_for_action(_actor: Node2D, channel: Channel) -> bool:
	return channel == Channel.TRAVEL and enabled and is_visible_in_tree() and runtime != null and runtime.is_active()

func can_interact_for_action(actor: Node2D, channel: Channel) -> bool:
	return is_available_for_action(actor,channel) and runtime.can_safe_return()

func get_prompt_for_action(_actor: Node2D, _channel: Channel) -> String:
	return "Return to Village"

func interact_for_action(actor: Node2D, channel: Channel) -> String:
	if not can_interact_for_action(actor,channel): return ""
	if runtime.request_safe_return(self):
		interacted.emit(actor)
		return "Returning to village"
	return ""

func _draw() -> void:
	var color := Color(0.65,0.9,0.9)
	draw_line(Vector2(-8,5),Vector2(0,-3),color,2)
	draw_line(Vector2(0,-3),Vector2(8,5),color,2)
	draw_line(Vector2(-8,11),Vector2(0,3),color,2)
	draw_line(Vector2(0,3),Vector2(8,11),color,2)
