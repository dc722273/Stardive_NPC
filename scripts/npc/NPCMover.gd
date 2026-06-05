extends RefCounted
class_name NPCMover

const ConstantsScript := preload("res://scripts/core/Constants.gd")

var entity_registry = null
var place_registry = null
var pathfinder = null
var event_log = null
var npc = null
var current_todo = null
var target_cell: Vector2i = ConstantsScript.INVALID_CELL
var planned_path: Array = []
var waypoints: Array = []
var interact_target: Vector2 = Vector2.ZERO
# 到达半径:position 进入 interact_target 该半径内即算「到达」。
# 「靠近交互对象」类(talk/inspect/visit)用 INTERACT_RADIUS;「走到坐标」类(wander/rest)
# 用精确小半径,否则目标落在交互半径内时 NPC 会一步不走就 dwell(wander 不移动 bug 的根因)。
var _arrival_radius: float = ConstantsScript.INTERACT_RADIUS
# Dwell:到达目标后「执行该 intent」的停留计时。进入交互半径/走完航点即开始累加,
# 满 DWELL_DURATION 才算 done —— 让 rest/inspect/talk 不再瞬间完成。
var _dwelling: bool = false
var _dwell_elapsed: float = 0.0


func configure(p_entity_registry, p_place_registry, p_pathfinder, p_event_log = null) -> void:
	entity_registry = p_entity_registry
	place_registry = p_place_registry
	pathfinder = p_pathfinder
	event_log = p_event_log


func plan_path(p_npc, p_target_cell: Vector2i, p_todo = null) -> Dictionary:
	npc = p_npc
	current_todo = p_todo
	target_cell = p_target_cell
	if pathfinder == null or npc == null or target_cell == ConstantsScript.INVALID_CELL:
		planned_path = []
		return {"ok": false, "status": &"blocked", "path": []}
	planned_path = pathfinder.find_path(npc.current_cell, target_cell)
	return {"ok": not planned_path.is_empty(), "status": &"planned" if not planned_path.is_empty() else &"blocked", "path": planned_path.duplicate()}


func move_to_cell(p_npc, p_target_cell: Vector2i, p_todo = null) -> Dictionary:
	var plan: Dictionary = plan_path(p_npc, p_target_cell, p_todo)
	if not bool(plan.get("ok", false)):
		return plan
	var final_cell: Vector2i = planned_path[planned_path.size() - 1]
	if entity_registry != null and entity_registry.has_method("move_entity_to_cell"):
		var moved: bool = entity_registry.move_entity_to_cell(p_npc.id, final_cell)
		if not moved:
			return {"ok": false, "status": &"blocked", "path": planned_path.duplicate()}
	else:
		p_npc.current_cell = final_cell
	return {"ok": true, "status": &"arrived", "path": planned_path.duplicate()}


func get_path_cells() -> Array:
	return planned_path.duplicate()


func request_replan(_place = null, blocked_cells: Array = []) -> bool:
	if not _path_intersects(blocked_cells):
		return true
	if npc == null or target_cell == ConstantsScript.INVALID_CELL or pathfinder == null:
		planned_path = []
		return false
	planned_path = pathfinder.find_path(npc.current_cell, target_cell)
	return not planned_path.is_empty()


func _path_intersects(cells: Array) -> bool:
	if cells.is_empty():
		return true
	var impacted := {}
	for cell in cells:
		impacted[cell] = true
	for cell in planned_path:
		if impacted.has(cell):
			return true
	return false


func begin_move(p_npc, target_world_pos: Vector2, p_interact_target: Vector2, p_todo = null, p_arrival_radius: float = ConstantsScript.INTERACT_RADIUS) -> void:
	npc = p_npc
	current_todo = p_todo
	interact_target = p_interact_target
	_arrival_radius = p_arrival_radius
	waypoints = []
	_dwelling = false
	_dwell_elapsed = 0.0
	if pathfinder == null or npc == null:
		return
	var start_cell: Vector2i = ConstantsScript.world_to_cell(npc.position)
	var goal_cell: Vector2i = ConstantsScript.world_to_cell(target_world_pos)
	target_cell = goal_cell
	planned_path = pathfinder.find_path(start_cell, goal_cell)
	for cell in planned_path:
		var wp: Vector2 = ConstantsScript.cell_to_world_center(cell)
		if wp.distance_to(npc.position) < 1.0:
			continue
		waypoints.append(wp)
	if not waypoints.is_empty():
		waypoints[waypoints.size() - 1] = target_world_pos


func advance(p_npc, delta: float) -> Dictionary:
	npc = p_npc
	if npc == null:
		return {"arrived": true, "interacting": false, "done": true}

	# 已在 dwell(到达后执行 intent 的停留)阶段:只累加计时,满 DWELL_DURATION 才 done。
	if _dwelling:
		return _tick_dwell(delta)

	# 未到达:沿航点推进一步。
	var reached: bool = npc.position.distance_to(interact_target) <= _arrival_radius
	if not reached and not waypoints.is_empty():
		var step: float = ConstantsScript.NPC_SPEED * delta
		var next_wp: Vector2 = waypoints[0]
		var to_wp: Vector2 = next_wp - npc.position
		if to_wp.length() <= step:
			npc.position = next_wp
			waypoints.pop_front()
		else:
			npc.position += to_wp.normalized() * step
		npc.current_cell = ConstantsScript.world_to_cell(npc.position)
		reached = npc.position.distance_to(interact_target) <= _arrival_radius

	# 到达(进入交互半径或走完航点):进入 dwell,本帧尚未 done。
	if reached or waypoints.is_empty():
		waypoints = []
		npc.current_cell = ConstantsScript.world_to_cell(npc.position)
		_dwelling = true
		return _tick_dwell(delta)

	# 仍在路上。
	return {"arrived": false, "interacting": false, "done": false}


## _tick_dwell: 在 dwell 阶段累加计时,满 DWELL_DURATION 返回 done=true。
func _tick_dwell(delta: float) -> Dictionary:
	_dwell_elapsed += delta
	var done: bool = _dwell_elapsed >= ConstantsScript.DWELL_DURATION
	return {"arrived": true, "interacting": true, "dwelling": not done, "done": done}


func is_idle() -> bool:
	# 走完航点且 dwell 也结束才算 idle —— dwell 期间 mover 仍「忙」,
	# 这样 advance_npc_movement 会继续每帧推进 dwell 计时直到 done。
	return waypoints.is_empty() and not _dwelling


## reset: todo 完成后清空移动+dwell 状态,让 mover 回到 idle,可接受下一个 todo。
func reset() -> void:
	waypoints = []
	_dwelling = false
	_dwell_elapsed = 0.0
	_arrival_radius = ConstantsScript.INTERACT_RADIUS
