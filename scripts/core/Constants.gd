extends RefCounted
class_name Constants


const INVALID_CELL := Vector2i(-1, -1)
const CELL_SIZE := 64
const NPC_SPEED := 44.0
const INTERACT_RADIUS := 40.0
# 到达目标后「执行该 intent」的停留时长(秒)。让 rest/inspect/talk 等原地/近距离
# todo 不再瞬间 done,体现 NPC 正在休息/查看/交谈的过程,避免一串 todo 哗哗秒完。
const DWELL_DURATION := 2.5
# 「走到坐标」类 todo(wander/rest)的到达半径:精确到点,远小于 INTERACT_RADIUS,
# 否则目标落在交互半径内时 NPC 会一步不走就 dwell。
const ARRIVAL_RADIUS_PRECISE := 4.0
# wander 溜达的格距范围(曼哈顿/扫描半径):取 [min, max],让 NPC 走更大范围而非贴着原地挪一格。
const WANDER_MIN_CELLS := 3
const WANDER_MAX_CELLS := 6


static func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELL_SIZE)), int(floor(pos.y / CELL_SIZE)))


static func cell_to_world_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL_SIZE + CELL_SIZE * 0.5, cell.y * CELL_SIZE + CELL_SIZE * 0.5)


static func cell_to_dict(cell: Vector2i) -> Dictionary:
	return {
		"x": cell.x,
		"y": cell.y,
	}


static func cell_from_dict(value: Variant, default_value: Vector2i = INVALID_CELL) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Dictionary:
		return Vector2i(int(value.get("x", default_value.x)), int(value.get("y", default_value.y)))
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return default_value


static func rect_to_dict(rect: Rect2i) -> Dictionary:
	return {
		"position": cell_to_dict(rect.position),
		"size": cell_to_dict(rect.size),
	}


static func rect_from_dict(value: Variant, default_value: Rect2i = Rect2i()) -> Rect2i:
	if value is Rect2i:
		return value
	if value is Dictionary:
		return Rect2i(
			cell_from_dict(value.get("position", {}), default_value.position),
			cell_from_dict(value.get("size", {}), default_value.size)
		)
	return default_value


static func cell_array_to_dicts(cells: Array) -> Array:
	var result: Array = []
	for cell in cells:
		result.append(cell_to_dict(cell))
	return result


static func cell_array_from_dicts(values: Array) -> Array:
	var result: Array[Vector2i] = []
	for value in values:
		result.append(cell_from_dict(value))
	return result
