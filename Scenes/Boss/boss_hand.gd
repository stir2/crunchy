extends CombatDamageable
## Both hands belong to one actor and share its Health node.

func damage_owner() -> Node2D:
	return get_parent().get_parent() as Node2D
