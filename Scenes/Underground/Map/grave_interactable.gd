extends InteractionTarget
## Minimal recovery hook, using the existing E interaction component.
var state: AbyssExplorationState
var world: String
const DEATH_SHEET = preload("res://SpriteSheets/chiefDeath_140x260_24fps.png")
var grave_id: String

func is_available(actor: Node2D) -> bool:
	return super.is_available(actor) and state != null and state.graves.get(world,{}).get("id","") == grave_id

func get_prompt(_actor: Node2D) -> String:
	return "Recover Grave — %d Flesh" % int(state.graves.get(world,{}).get("souls",0))

func _perform_interaction(_actor: Node2D) -> String:
	var recovered := state.recover_grave(world,grave_id,global_position)
	if not recovered.is_empty():
		get_node("/root/SoundManager").play_sfx(&"collect_grave", -13)
	return "Recovered %d Flesh" % int(recovered.souls) if not recovered.is_empty() else ""

func _draw() -> void:
	# Frame 46 ends at source y=145; align that baseline to the saved feet.
	draw_texture_rect_region(DEATH_SHEET,Rect2(-70,-145,140,260),Rect2(46*140,0,140,260))
