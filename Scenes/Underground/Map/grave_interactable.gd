extends InteractionTarget
## Minimal recovery hook, using the existing E interaction component.
var state: AbyssExplorationState
var world: String
var grave_id: String

func is_available(actor: Node2D) -> bool:
	return super.is_available(actor) and state != null and state.graves.get(world,{}).get("id","") == grave_id

func get_prompt(_actor: Node2D) -> String:
	return "Recover Grave — %d Flesh" % int(state.graves.get(world,{}).get("souls",0))

func _perform_interaction(_actor: Node2D) -> String:
	var recovered := state.recover_grave(world,grave_id,global_position)
	if not recovered.is_empty():
		get_node("/root/SoundManager").play_sfx(&"collect_grave", -17)
	return "Recovered %d Flesh" % int(recovered.souls) if not recovered.is_empty() else ""

func _draw() -> void:
	draw_rect(Rect2(-5,-13,10,13),Color(0.65,0.75,0.8))
	draw_line(Vector2(0,-11),Vector2(0,-3),Color(0.1,0.15,0.2),2)
	draw_line(Vector2(-3,-8),Vector2(3,-8),Color(0.1,0.15,0.2),2)
