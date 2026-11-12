extends RefCounted
## The house and Continue preview use the same campaign stages.

const STAGES: Array[Texture2D] = [
	preload("res://uiSprites/villageProgress0001.png"),
	preload("res://uiSprites/villageProgress0002.png"),
	preload("res://uiSprites/villageProgress0003.png"),
	preload("res://uiSprites/villageProgress0004.png"),
	preload("res://uiSprites/villageProgress0005.png"),
]

static func stage(day: int, boss_defeated: bool, run_length: int = 10) -> int:
	if boss_defeated:
		return 0
	if day >= run_length:
		return 4
	if run_length == 5:
		return clampi(day - 1, 0, 3)
	if day >= 8:
		return 3
	if day >= 6:
		return 2
	if day >= 4:
		return 1
	return 0

static func texture_for(day: int, boss_defeated: bool, run_length: int = 10) -> Texture2D:
	return STAGES[stage(day, boss_defeated, run_length)]
