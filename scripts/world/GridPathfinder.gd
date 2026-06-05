extends RefCounted
class_name GridPathfinder

const ConstantsScript := preload("res://scripts/core/Constants.gd")

var map_bounds: Rect2i = Rect2i()
var solid_cells: Dictionary = {}


func set_map_bounds(bounds: Rect2i) -> void:
	map_bounds = bounds


func set_solid_cell(cell: Vector2i, solid: bool = true) -> void:
	if solid:
		solid_cells[cell] = true
	else:
		solid_cells.erase(cell)


func set_solid_cells(cells: Array, solid: bool = true) -> void:
	for cell in cells:
		set_solid_cell(cell, solid)


func is_walkable(cell: Vector2i) -> bool:
	if map_bounds.size.x > 0 and map_bounds.size.y > 0 and not map_bounds.has_point(cell):
		return false
	return not solid_cells.has(cell)


func find_path(start_cell: Vector2i, goal_cell: Vector2i) -> Array:
	if not is_walkable(start_cell) or not is_walkable(goal_cell):
		return []
	var frontier: Array = [start_cell]
	var came_from: Dictionary = {start_cell: ConstantsScript.INVALID_CELL}
	var index: int = 0
	while index < frontier.size():
		var current: Vector2i = frontier[index]
		index += 1
		if current == goal_cell:
			return _reconstruct_path(came_from, start_cell, goal_cell)
		for next_cell in _neighbors(current):
			if came_from.has(next_cell):
				continue
			if not is_walkable(next_cell):
				continue
			came_from[next_cell] = current
			frontier.append(next_cell)
	return []


func to_dict() -> Dictionary:
	return {
		"map_bounds": ConstantsScript.rect_to_dict(map_bounds),
		"solid_cells": ConstantsScript.cell_array_to_dicts(_sorted_cells(solid_cells.keys())),
	}


func load_from_dict(data: Dictionary) -> void:
	map_bounds = ConstantsScript.rect_from_dict(data.get("map_bounds", Rect2i()))
	solid_cells.clear()
	var raw_solid_cells: Variant = data.get("solid_cells", [])
	if raw_solid_cells is Array:
		for value in raw_solid_cells:
			set_solid_cell(ConstantsScript.cell_from_dict(value), true)


func _neighbors(cell: Vector2i) -> Array:
	return [
		Vector2i(cell.x, cell.y - 1),
		Vector2i(cell.x + 1, cell.y),
		Vector2i(cell.x, cell.y + 1),
		Vector2i(cell.x - 1, cell.y),
	]


func _reconstruct_path(came_from: Dictionary, start_cell: Vector2i, goal_cell: Vector2i) -> Array:
	var path: Array = []
	var current: Vector2i = goal_cell
	while current != ConstantsScript.INVALID_CELL:
		path.push_front(current)
		if current == start_cell:
			break
		current = came_from.get(current, ConstantsScript.INVALID_CELL)
	return path


func _sorted_cells(cells: Array) -> Array:
	var result: Array = cells.duplicate()
	result.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		if left.y == right.y:
			return left.x < right.x
		return left.y < right.y
	)
	return result
