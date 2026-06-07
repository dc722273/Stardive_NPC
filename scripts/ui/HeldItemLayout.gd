extends RefCounted
class_name HeldItemLayout

const ConstantsScript := preload("res://scripts/core/Constants.gd")

const HELD_ITEM_DRAG_HIT_RADIUS := 84.0


static func anchor_offset() -> Vector2:
	return Vector2(ConstantsScript.CELL_SIZE * 0.3, 0.0)


static func item_offset(index: int) -> Vector2:
	return Vector2(34.0 + 44.0 * float(index % 3), -30.0 - 34.0 * float(index / 3))
