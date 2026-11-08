class_name InteractionTarget
extends Node2D
## Reusable contract. Subclasses supply eligibility, prompt and an atomic action.
enum Channel { PRIMARY, TRAVEL }
signal interacted(actor: Node2D)
@export var enabled: bool = true
@export var action_text: String = "Interact"

func is_available(_actor: Node2D) -> bool:
	return enabled and is_visible_in_tree()

func can_interact(actor: Node2D) -> bool:
	return is_available(actor)

func get_prompt(_actor: Node2D) -> String:
	return action_text

func interact(actor: Node2D) -> String:
	if not is_available(actor) or not can_interact(actor):
		return ""
	var message := _perform_interaction(actor)
	if not message.is_empty():
		interacted.emit(actor)
	return message

func _perform_interaction(_actor: Node2D) -> String:
	return ""

## Channel adapters keep existing item/NPC targets primary-only by default.
func is_available_for_action(actor: Node2D, channel: Channel) -> bool:
	return channel == Channel.PRIMARY and is_available(actor)

func can_interact_for_action(actor: Node2D, channel: Channel) -> bool:
	return channel == Channel.PRIMARY and can_interact(actor)

func get_prompt_for_action(actor: Node2D, channel: Channel) -> String:
	return get_prompt(actor) if channel == Channel.PRIMARY else ""

func interact_for_action(actor: Node2D, channel: Channel) -> String:
	return interact(actor) if channel == Channel.PRIMARY else ""
