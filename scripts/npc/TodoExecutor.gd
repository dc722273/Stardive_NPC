extends RefCounted
class_name TodoExecutor

const ConstantsScript := preload("res://scripts/core/Constants.gd")
const TodoItemScript := preload("res://scripts/state/TodoItem.gd")

var entity_registry = null
var place_registry = null
var pathfinder = null
var event_log = null
var mover = null


func configure(p_entity_registry, p_place_registry, p_pathfinder, p_event_log = null, p_mover = null) -> void:
	entity_registry = p_entity_registry
	place_registry = p_place_registry
	pathfinder = p_pathfinder
	event_log = p_event_log
	mover = p_mover


func handle_replan_failed(npc, todo, _blocked_cell: Vector2i, p_event_log = null) -> Dictionary:
	return _mark_blocked(npc, todo, &"replan_failed", p_event_log if p_event_log != null else event_log)


func on_replan_failed(npc, todo, blocked_cell: Vector2i, p_event_log = null) -> Dictionary:
	return handle_replan_failed(npc, todo, blocked_cell, p_event_log)


func mark_todo_blocked(npc, todo) -> Dictionary:
	return _mark_blocked(npc, todo, &"blocked", event_log)


func execute_todo(npc, todo, p_entity_registry = null, p_place_registry = null, p_pathfinder = null, p_event_log = null, p_mover = null) -> Dictionary:
	var context := _context(p_entity_registry, p_place_registry, p_pathfinder, p_event_log, p_mover)
	var target_cell: Vector2i = _target_cell(todo, context)
	if target_cell == ConstantsScript.INVALID_CELL:
		return _mark_blocked(npc, todo, &"missing_target", context["event_log"])

	var move_result := _move_to_target(npc, todo, target_cell, context)
	if not bool(move_result.get("ok", false)):
		return _mark_blocked(npc, todo, &"path_blocked", context["event_log"])

	todo.status = &"done"
	_record_completion(npc, todo, target_cell, context["event_log"])
	return {
		"status": &"done",
		"todo": todo,
		"actions": _action_bundle(todo, target_cell),
		"movement": move_result,
	}


func start_todo(npc, todo, world: Dictionary) -> Dictionary:
	return execute_todo(
		npc,
		todo,
		world.get("entity_registry", entity_registry),
		world.get("place_registry", place_registry),
		world.get("pathfinder", pathfinder),
		world.get("event_log", event_log),
		world.get("mover", mover)
	)


func _context(p_entity_registry, p_place_registry, p_pathfinder, p_event_log, p_mover) -> Dictionary:
	return {
		"entity_registry": p_entity_registry if p_entity_registry != null else entity_registry,
		"place_registry": p_place_registry if p_place_registry != null else place_registry,
		"pathfinder": p_pathfinder if p_pathfinder != null else pathfinder,
		"event_log": p_event_log if p_event_log != null else event_log,
		"mover": p_mover if p_mover != null else mover,
	}


func _target_cell(todo, context: Dictionary) -> Vector2i:
	if todo.intent == &"visit_place":
		var places = context["place_registry"].get("places") if context["place_registry"] != null else {}
		if not places.has(todo.target_place_id):
			return ConstantsScript.INVALID_CELL
		var place = places[todo.target_place_id]
		if place.get("door_cell") != ConstantsScript.INVALID_CELL:
			return place.door_cell
		return context["place_registry"].get_random_cell_in_place(todo.target_place_id)
	if todo.intent == &"talk_to_npc":
		var npcs = context["entity_registry"].get("npcs") if context["entity_registry"] != null else {}
		if not npcs.has(todo.target_npc_id):
			return ConstantsScript.INVALID_CELL
		return npcs[todo.target_npc_id].current_cell
	if todo.intent == &"inspect_item":
		var items = context["entity_registry"].get("items") if context["entity_registry"] != null else {}
		if not items.has(todo.target_item_id):
			return ConstantsScript.INVALID_CELL
		return items[todo.target_item_id].current_cell
	if todo.intent == &"wander":
		return _wander_cell(context)
	if todo.intent == &"rest":
		return _field_cell(todo, "target_cell", ConstantsScript.INVALID_CELL)
	return ConstantsScript.INVALID_CELL


## _target_world_pos: 把 todo 解析成世界坐标目标 + 到达语义。
## 返回 arrival_radius 区分两种到达语义:
##   - wander/rest =「走到坐标」→ ARRIVAL_RADIUS_PRECISE(精确到点,必须真走到);
##   - talk/inspect/visit =「靠近交互对象」→ INTERACT_RADIUS(进半径即可交互)。
func _target_world_pos(todo, context: Dictionary, npc) -> Dictionary:
	if todo.intent == &"rest":
		return {"ok": true, "world_pos": npc.position, "interact_target": npc.position, "arrival_radius": ConstantsScript.ARRIVAL_RADIUS_PRECISE}
	if todo.intent == &"wander":
		var wcell: Vector2i = _wander_cell_continuous(context, npc)
		if wcell == ConstantsScript.INVALID_CELL:
			return {"ok": true, "world_pos": npc.position, "interact_target": npc.position, "arrival_radius": ConstantsScript.ARRIVAL_RADIUS_PRECISE}
		var wpos: Vector2 = ConstantsScript.cell_to_world_center(wcell)
		return {"ok": true, "world_pos": wpos, "interact_target": wpos, "arrival_radius": ConstantsScript.ARRIVAL_RADIUS_PRECISE}
	if todo.intent == &"inspect_item":
		var items = context["entity_registry"].get("items") if context["entity_registry"] != null else {}
		if not items.has(todo.target_item_id):
			return {"ok": false}
		var ipos: Vector2 = items[todo.target_item_id].position
		return {"ok": true, "world_pos": ipos, "interact_target": ipos, "arrival_radius": ConstantsScript.INTERACT_RADIUS}
	if todo.intent == &"talk_to_npc":
		var npcs = context["entity_registry"].get("npcs") if context["entity_registry"] != null else {}
		if not npcs.has(todo.target_npc_id):
			return {"ok": false}
		var npos: Vector2 = npcs[todo.target_npc_id].position
		return {"ok": true, "world_pos": npos, "interact_target": npos, "arrival_radius": ConstantsScript.INTERACT_RADIUS}
	if todo.intent == &"visit_place":
		var cell: Vector2i = _target_cell(todo, context)
		if cell == ConstantsScript.INVALID_CELL:
			return {"ok": false}
		var ppos: Vector2 = ConstantsScript.cell_to_world_center(cell)
		return {"ok": true, "world_pos": ppos, "interact_target": ppos, "arrival_radius": ConstantsScript.INTERACT_RADIUS}
	return {"ok": false}


## _wander_cell_continuous: 为 wander 选一个「更大范围」的可达目标格(WANDER_MIN..MAX 格远,
## ≥3 格 = ≥96px,远于 INTERACT_RADIUS,确保 NPC 真的会走一段)。
## 方向与距离用 NPC id + current_cell 派生的确定性种子选取 —— 不同 NPC/不同位置走不同方向,
## 同一状态结果确定(可被 oracle 测),避免 randi() 破坏测试可复现性。
func _wander_cell_continuous(context: Dictionary, npc) -> Vector2i:
	var pf = context["pathfinder"]
	if pf == null:
		return ConstantsScript.INVALID_CELL
	var bounds: Rect2i = pf.get("map_bounds")
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return ConstantsScript.INVALID_CELL
	var current: Vector2i = ConstantsScript.world_to_cell(npc.position)
	# 8 方向(含对角),从派生种子决定的方向起始环扫,优先更远的距离。
	var dirs: Array = [
		Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	]
	var seed: int = _wander_seed(npc, current)
	var dir_offset: int = seed % dirs.size()
	# 距离从远到近找第一个可达点,保证「更大范围」优先。
	for dist in range(ConstantsScript.WANDER_MAX_CELLS, ConstantsScript.WANDER_MIN_CELLS - 1, -1):
		for i in range(dirs.size()):
			var dir: Vector2i = dirs[(i + dir_offset) % dirs.size()]
			var cand := Vector2i(current.x + dir.x * dist, current.y + dir.y * dist)
			if cand == current or not bounds.has_point(cand) or not pf.is_walkable(cand):
				continue
			if not pf.find_path(current, cand).is_empty():
				return cand
	return ConstantsScript.INVALID_CELL


## _wander_seed: 由 NPC id 与当前格派生的确定性正整数种子(无 randi,可复现)。
func _wander_seed(npc, cell: Vector2i) -> int:
	var base: int = int(hash(str(npc.id)))
	var s: int = absi(base + cell.x * 73856093 + cell.y * 19349663)
	return s


func _move_to_target(npc, todo, target_cell: Vector2i, context: Dictionary) -> Dictionary:
	var active_mover = context["mover"]
	if active_mover != null and active_mover.has_method("move_to_cell"):
		return active_mover.move_to_cell(npc, target_cell, todo)
	if context["pathfinder"] == null:
		return {"ok": false, "status": &"blocked"}
	var path: Array = context["pathfinder"].find_path(npc.current_cell, target_cell)
	if path.is_empty():
		return {"ok": false, "status": &"blocked", "path": []}
	if context["entity_registry"] != null and context["entity_registry"].has_method("move_entity_to_cell"):
		if not context["entity_registry"].move_entity_to_cell(npc.id, target_cell):
			return {"ok": false, "status": &"blocked", "path": path}
	else:
		npc.current_cell = target_cell
	return {"ok": true, "status": &"arrived", "path": path}


func _mark_blocked(npc, todo, reason: StringName, p_event_log = null) -> Dictionary:
	todo.status = &"BLOCKED"
	_ensure_fallback_todo(npc)
	if p_event_log != null and p_event_log.has_method("record"):
		p_event_log.record(&"npc_todo_blocked_by_building", npc.id, todo.id, &"todo", npc.current_cell, {"reason": reason}, &"system")
	return {"status": &"BLOCKED", "reason": reason, "todo": todo}


func _ensure_fallback_todo(npc) -> void:
	if npc == null:
		return
	for item in npc.todo_list:
		if item != null and (item.intent == &"wander" or item.intent == &"rest") and item.status == &"pending":
			return
	npc.todo_list.append(TodoItemScript.from_dict({
		"id": "todo_%s_fallback_wander" % str(npc.id),
		"intent": "wander",
		"reason": "fallback after blocked todo",
		"status": "pending",
	}))


func _record_completion(npc, todo, target_cell: Vector2i, p_event_log = null) -> void:
	if p_event_log == null or not p_event_log.has_method("record"):
		return
	var event_type := &"npc_completed_todo"
	if todo.intent == &"visit_place":
		event_type = &"npc_visited_place"
	elif todo.intent == &"talk_to_npc":
		event_type = &"npc_talked_to_npc"
	elif todo.intent == &"inspect_item":
		event_type = &"npc_inspected_item"
	p_event_log.record(event_type, npc.id, _target_id(todo), _target_type(todo), target_cell, {"todo_id": todo.id}, &"system")


func _action_bundle(todo, target_cell: Vector2i) -> Array:
	if todo.intent == &"rest":
		return [{"lane": &"cognition", "kind": &"rest", "target_cell": target_cell}]
	var movement_kind := &"move_to_cell"
	if todo.intent == &"visit_place":
		movement_kind = &"move_to_place_cell"
	elif todo.intent == &"talk_to_npc":
		movement_kind = &"move_near_target_npc"
	elif todo.intent == &"inspect_item":
		movement_kind = &"move_near_item"
	return [
		{"lane": &"movement", "kind": movement_kind, "target_cell": target_cell},
		{"lane": &"speech", "kind": &"todo_feedback"},
	]


func _target_id(todo) -> StringName:
	if todo.intent == &"visit_place":
		return todo.target_place_id
	if todo.intent == &"talk_to_npc":
		return todo.target_npc_id
	if todo.intent == &"inspect_item":
		return todo.target_item_id
	return &""


func _target_type(todo) -> StringName:
	if todo.intent == &"visit_place":
		return &"place"
	if todo.intent == &"talk_to_npc":
		return &"npc"
	if todo.intent == &"inspect_item":
		return &"item"
	return &"cell"


func _wander_cell(context: Dictionary) -> Vector2i:
	var effective_pathfinder = context["pathfinder"]
	if effective_pathfinder != null and effective_pathfinder.get("map_bounds").size.x > 0:
		return effective_pathfinder.get("map_bounds").position
	return Vector2i.ZERO


func _field_cell(value, name: String, fallback: Vector2i) -> Vector2i:
	if value is Dictionary:
		return value.get(name, fallback)
	if value != null and value is Object:
		var field_value = value.get(name)
		return field_value if field_value is Vector2i else fallback
	return fallback
