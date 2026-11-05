class_name CombatHit
extends RefCounted
## Shared hit payload for players, enemies, hazards and breakable adapters.
## source is the attacking actor/root, not its attack Area2D. world_position is
## the impact/source location. The receiver decides damage acceptance/reaction.
var amount: int = 1
var source: Node2D
var direction: Vector2 = Vector2.RIGHT
var knockback: Vector2 = Vector2.ZERO
var world_position: Vector2
var swing_id: int = 0
