class_name AbyssEnemyPoolEntry
extends Resource
## One type, with independent weights for the three existing abyss levels.
@export var enemy_id: StringName
@export var scene: PackedScene
@export var level_weights: Vector3 = Vector3.ZERO

func weight(level: int) -> float:
	return maxf(0.0, level_weights[level - 1]) if level >= 1 and level <= 3 else 0.0
