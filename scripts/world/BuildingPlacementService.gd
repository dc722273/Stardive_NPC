extends RefCounted
class_name BuildingPlacementService

const ConstantsScript := preload("res://scripts/core/Constants.gd")

var entity_registry = null
var place_registry = null
var pathfinder = null
var event_log = null
var movers: Dictionary = {}


func configure(p_entity_registry, p_place_registry, p_pathfinder, p_event_log = null) -> void:
	entity_registry = p_entity_registry
	place_registry = p_place_registry
	pathfinder = p_pathfinder
	event_log = p_event_log


func register_mover(npc_id: StringName, mover) -> void:
	movers[npc_id] = mover


func choose_door_cell_from_drag(footprint: Rect2i, drag_end_cell: Vector2i) -> Vector2i:
	var candidates: Array = _door_candidates(footprint)
	candidates.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		var left_distance: int = _cell_distance_squared(left, drag_end_cell)
		var right_distance: int = _cell_distance_squared(right, drag_end_cell)
		if left_distance == right_distance:
			if left.y == right.y:
				return left.x < right.x
			return left.y < right.y
		return left_distance < right_distance
	)
	for candidate in candidates:
		if _door_has_walkable_connection(footprint, candidate):
			return candidate
	return ConstantsScript.INVALID_CELL


func can_place_fenced_area(footprint: Rect2i, drag_end_cell: Vector2i) -> Dictionary:
	if footprint.size.x < 3 or footprint.size.y < 3:
		return _failure("footprint_too_thin")

	var door_cell: Vector2i = choose_door_cell_from_drag(footprint, drag_end_cell)
	if door_cell == ConstantsScript.INVALID_CELL:
		return _failure("illegal_door")
	var fence_cells: Array = get_fence_cells(footprint, door_cell)
	var interior_cells: Array = get_interior_cells(footprint)
	if interior_cells.is_empty():
		return _failure("footprint_has_no_interior")

	var footprint_cells: Array = _cells_in_rect(footprint)
	var occupying_npcs: Array = get_npcs_occupying_cells(footprint_cells)
	if not occupying_npcs.is_empty():
		return _failure("npc_occupies_footprint", {"npc_ids": occupying_npcs})

	for cell in footprint_cells:
		if not _is_cell_in_bounds(cell):
			return _failure("footprint_out_of_bounds", {"cell": cell})

	for cell in fence_cells:
		var existing_place = place_registry.get_place_at_cell(cell)
		if existing_place != null and existing_place.door_cell == cell:
			return _failure("door_covered_by_new_fence", {"cell": cell, "place_id": existing_place.id})

	for cell in footprint_cells:
		var existing_place = place_registry.get_place_at_cell(cell)
		if existing_place != null:
			return _failure("overlaps_fenced_area", {"cell": cell, "place_id": existing_place.id})

	for cell in footprint_cells:
		if entity_registry != null and entity_registry.blocked_cells.has(cell):
			return _failure("blocked_cell", {"cell": cell})

	for cell in fence_cells:
		if pathfinder != null and pathfinder.solid_cells.has(cell):
			return _failure("solid_cell", {"cell": cell})

	return {
		"ok": true,
		"reason": "",
		"door_cell": door_cell,
		"fence_cells": fence_cells,
		"interior_cells": interior_cells,
	}


func place_fenced_area(
	place_id: StringName,
	place_name: String,
	place_description: String,
	footprint: Rect2i,
	drag_end_cell: Vector2i,
	created_by: StringName = &"player",
	updated_at_tick: int = 0,
	emoji: String = ""
) -> Dictionary:
	var validation: Dictionary = can_place_fenced_area(footprint, drag_end_cell)
	if not validation.get("ok", false):
		return validation

	var registry_snapshot: Dictionary = place_registry.to_dict()
	var pathfinder_snapshot: Dictionary = pathfinder.to_dict()
	var event_log_snapshot: Dictionary = _event_log_snapshot()
	var place = null

	place = place_registry.create_place(
		place_id,
		place_name,
		place_description,
		footprint,
		validation["door_cell"],
		validation["fence_cells"],
		validation["interior_cells"],
		created_by,
		updated_at_tick,
		emoji
	)
	if place == null:
		_rollback(registry_snapshot, pathfinder_snapshot, event_log_snapshot)
		return _failure("place_create_failed")

	# spec: fence cells become solid; the door and every interior cell must be
	# explicitly kept walkable. Setting them solid=false (rather than relying on
	# an implicit default) restores walkability even if those cells were solid
	# beforehand, so a fenced area never traps its own door or interior.
	pathfinder.set_solid_cells(validation["fence_cells"], true)
	pathfinder.set_solid_cells(validation["interior_cells"], false)
	pathfinder.set_solid_cell(validation["door_cell"], false)

	if event_log != null and event_log.has_method("record"):
		event_log.record(
			&"player_placed_building",
			place.id,
			&"",
			&"fenced_area",
			place.door_cell,
			{"name": place.name},
			created_by,
			updated_at_tick
		)

	var affected_npcs: Array = get_npcs_with_paths_intersecting(validation["fence_cells"])
	for npc_id in affected_npcs:
		_notify_replan_or_block(npc_id, place, validation["fence_cells"], updated_at_tick)

	return {
		"ok": true,
		"reason": "",
		"place": place,
		"affected_npc_ids": affected_npcs,
	}


func get_door_cell(footprint: Rect2i, drag_end_cell: Vector2i) -> Vector2i:
	return choose_door_cell_from_drag(footprint, drag_end_cell)


func get_fence_cells(footprint: Rect2i, door_cell: Vector2i) -> Array:
	var result: Array = []
	for cell in _cells_in_rect(footprint):
		if cell == door_cell:
			continue
		if _is_boundary_cell(footprint, cell):
			result.append(cell)
	return _sorted_cells(result)


func get_interior_cells(footprint: Rect2i) -> Array:
	var result: Array = []
	for cell in _cells_in_rect(footprint):
		if not _is_boundary_cell(footprint, cell):
			result.append(cell)
	return _sorted_cells(result)


func get_npcs_occupying_cells(cells: Array) -> Array:
	var result: Array = []
	if entity_registry == null:
		return result
	var cell_set: Dictionary = {}
	for cell in cells:
		cell_set[cell] = true
	for npc_id in entity_registry.npcs.keys():
		var npc = entity_registry.npcs[npc_id]
		var ncell: Vector2i = ConstantsScript.world_to_cell(npc.position)
		if cell_set.has(ncell):
			result.append(StringName(npc_id))
	return _sorted_string_names(result)


func get_npcs_with_paths_intersecting(cells: Array) -> Array:
	var impacted_cells: Dictionary = {}
	for cell in cells:
		impacted_cells[cell] = true
	var result: Array = []
	for npc_id in _sorted_string_names(movers.keys()):
		var mover = movers[npc_id]
		var path_cells: Array = _mover_path_cells(mover)
		for path_cell in path_cells:
			if impacted_cells.has(path_cell):
				result.append(npc_id)
				break
	return result


func _notify_replan_or_block(npc_id: StringName, place, fence_cells: Array, updated_at_tick: int) -> void:
	var mover = movers[npc_id]
	var replanned: bool = true
	if mover != null and mover.has_method("request_replan"):
		replanned = bool(mover.request_replan(place, fence_cells.duplicate()))
	if replanned:
		return

	var current_todo = mover.get("current_todo") if mover != null else null
	if current_todo != null:
		current_todo.status = &"BLOCKED"
	if event_log != null and event_log.has_method("record"):
		event_log.record(
			&"npc_todo_blocked_by_building",
			npc_id,
			place.id,
			&"fenced_area",
			place.door_cell,
			{"todo_id": current_todo.id if current_todo != null else &""},
			&"system",
			updated_at_tick
		)


func _mover_path_cells(mover) -> Array:
	if mover == null:
		return []
	if mover.has_method("get_path_cells"):
		return mover.get_path_cells()
	var path = mover.get("current_path")
	if path is Array:
		return path
	return []


func _door_candidates(footprint: Rect2i) -> Array:
	var result: Array = []
	if footprint.size.x < 3 or footprint.size.y < 3:
		return result
	for cell in _cells_in_rect(footprint):
		if _is_boundary_cell(footprint, cell) and not _is_corner_cell(footprint, cell):
			result.append(cell)
	return result


func _door_has_walkable_connection(footprint: Rect2i, door_cell: Vector2i) -> bool:
	var normal: Vector2i = _door_outward_normal(footprint, door_cell)
	if normal == Vector2i.ZERO:
		return false
	var outside_cell: Vector2i = door_cell + normal
	var inside_cell: Vector2i = door_cell - normal
	return _is_static_walkable(outside_cell) and _is_static_walkable(inside_cell)


func _is_static_walkable(cell: Vector2i) -> bool:
	if not _is_cell_in_bounds(cell):
		return false
	if entity_registry != null and entity_registry.blocked_cells.has(cell):
		return false
	if pathfinder != null and pathfinder.solid_cells.has(cell):
		return false
	return true


func _is_cell_in_bounds(cell: Vector2i) -> bool:
	if entity_registry != null and entity_registry.map_bounds.size.x > 0 and entity_registry.map_bounds.size.y > 0:
		return entity_registry.map_bounds.has_point(cell)
	if pathfinder != null and pathfinder.map_bounds.size.x > 0 and pathfinder.map_bounds.size.y > 0:
		return pathfinder.map_bounds.has_point(cell)
	return true


func _door_outward_normal(footprint: Rect2i, cell: Vector2i) -> Vector2i:
	var min_x: int = footprint.position.x
	var max_x: int = footprint.position.x + footprint.size.x - 1
	var min_y: int = footprint.position.y
	var max_y: int = footprint.position.y + footprint.size.y - 1
	if cell.x == min_x:
		return Vector2i(-1, 0)
	if cell.x == max_x:
		return Vector2i(1, 0)
	if cell.y == min_y:
		return Vector2i(0, -1)
	if cell.y == max_y:
		return Vector2i(0, 1)
	return Vector2i.ZERO


func _is_boundary_cell(footprint: Rect2i, cell: Vector2i) -> bool:
	var min_x: int = footprint.position.x
	var max_x: int = footprint.position.x + footprint.size.x - 1
	var min_y: int = footprint.position.y
	var max_y: int = footprint.position.y + footprint.size.y - 1
	return cell.x == min_x or cell.x == max_x or cell.y == min_y or cell.y == max_y


func _is_corner_cell(footprint: Rect2i, cell: Vector2i) -> bool:
	var min_x: int = footprint.position.x
	var max_x: int = footprint.position.x + footprint.size.x - 1
	var min_y: int = footprint.position.y
	var max_y: int = footprint.position.y + footprint.size.y - 1
	return (cell.x == min_x or cell.x == max_x) and (cell.y == min_y or cell.y == max_y)


func _cell_distance_squared(left: Vector2i, right: Vector2i) -> int:
	var delta: Vector2i = left - right
	return delta.x * delta.x + delta.y * delta.y


func _cells_in_rect(rect: Rect2i) -> Array:
	var result: Array = []
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			result.append(Vector2i(x, y))
	return result


func _sorted_cells(cells: Array) -> Array:
	var result: Array = cells.duplicate()
	result.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		if left.y == right.y:
			return left.x < right.x
		return left.y < right.y
	)
	return result


func _sorted_string_names(values: Array) -> Array:
	var result: Array = values.duplicate()
	result.sort_custom(func(left, right) -> bool:
		return str(left) < str(right)
	)
	return result


func _failure(reason: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"reason": reason,
	}
	for key in extra.keys():
		result[key] = extra[key]
	return result


func _event_log_snapshot() -> Dictionary:
	# Snapshot the full event-log state (events + next_event_number) so rollback
	# restores both the entries and the generated-id counter, not just the event
	# count. Pop-by-count alone would leave next_event_number advanced.
	if event_log != null and event_log.has_method("to_dict"):
		return event_log.to_dict()
	return {}


func _rollback(registry_snapshot: Dictionary, pathfinder_snapshot: Dictionary, event_log_snapshot: Dictionary) -> void:
	if place_registry != null and place_registry.has_method("load_from_dict"):
		place_registry.load_from_dict(registry_snapshot)
	if pathfinder != null and pathfinder.has_method("load_from_dict"):
		pathfinder.load_from_dict(pathfinder_snapshot)
	if event_log != null and event_log.has_method("load_from_dict"):
		event_log.load_from_dict(event_log_snapshot)
