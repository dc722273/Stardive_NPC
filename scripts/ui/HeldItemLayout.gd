extends RefCounted
class_name HeldItemLayout

const ConstantsScript := preload("res://scripts/core/Constants.gd")

const HELD_ITEM_DRAG_HIT_RADIUS := 84.0


static func anchor_offset() -> Vector2:
	return Vector2(ConstantsScript.CELL_SIZE * 0.3, 0.0)


static func item_offset(index: int) -> Vector2:
	return Vector2(20.0 + 16.0 * float(index % 3), -18.0 - 12.0 * float(index / 3))
