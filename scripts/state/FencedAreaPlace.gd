extends RefCounted
class_name FencedAreaPlace

const ConstantsScript := preload("res://scripts/core/Constants.gd")

var id: StringName = &""
var name: String = ""
var description: String = ""
var created_by: StringName = &"player"
var updated_at_tick: int = 0
var emoji: String = ""
var footprint: Rect2i = Rect2i()
var door_cell: Vector2i = ConstantsScript.INVALID_CELL
var fence_cells: Array[Vector2i] = []
var interior_cells: Array[Vector2i] = []


static func from_dict(data: Dictionary):
	var state = load("res://scripts/state/FencedAreaPlace.gd").new()
	state.id = StringName(data.get("id", ""))
	state.name = str(data.get("name", ""))
	state.description = str(data.get("description", ""))
	state.created_by = StringName(data.get("created_by", "player"))
	state.updated_at_tick = int(data.get("updated_at_tick", 0))
	state.emoji = str(data.get("emoji", ""))
	state.footprint = ConstantsScript.rect_from_dict(data.get("footprint", Rect2i()))
	state.door_cell = ConstantsScript.cell_from_dict(data.get("door_cell", ConstantsScript.INVALID_CELL))
	var raw_fence_cells: Variant = data.get("fence_cells", [])
	if raw_fence_cells is Array:
		state.fence_cells = ConstantsScript.cell_array_from_dicts(raw_fence_cells)
	var raw_interior_cells: Variant = data.get("interior_cells", [])
	if raw_interior_cells is Array:
		state.interior_cells = ConstantsScript.cell_array_from_dicts(raw_interior_cells)
	return state


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"description": description,
		"created_by": created_by,
		"updated_at_tick": updated_at_tick,
		"emoji": emoji,
		"footprint": ConstantsScript.rect_to_dict(footprint),
		"door_cell": ConstantsScript.cell_to_dict(door_cell),
		"fence_cells": ConstantsScript.cell_array_to_dicts(fence_cells),
		"interior_cells": ConstantsScript.cell_array_to_dicts(interior_cells),
	}
