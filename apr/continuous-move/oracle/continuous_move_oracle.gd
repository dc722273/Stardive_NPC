extends SceneTree
const PASS_MARKER := "CONTINUOUS_MOVE_ORACLE: PASS"
const FAIL_MARKER := "CONTINUOUS_MOVE_ORACLE: FAIL"
const NPCMoverScript := preload("res://scripts/npc/NPCMover.gd")
const GridPathfinderScript := preload("res://scripts/world/GridPathfinder.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const ConstantsScript := preload("res://scripts/core/Constants.gd")
var failures: Array = []
func _initialize() -> void:
	_run()
	_finish()
func _run() -> void:
	var pathfinder = GridPathfinderScript.new()
	pathfinder.set_map_bounds(Rect2i(0, 0, 24, 16))
	var mover = NPCMoverScript.new()
	mover.configure(null, null, pathfinder, null)
	var npc = NPCStateScript.from_dict({"id": "npc_a", "position": {"x": 48.0, "y": 48.0}})
	var goal := ConstantsScript.cell_to_world_center(Vector2i(5, 1))
	mover.begin_move(npc, goal, goal, null)
	_assert_true(not mover.is_idle(), "mover busy after begin_move")
	var start_pos: Vector2 = npc.position
	var arrived := false
	var steps := 0
	while steps < 600 and not arrived:
		var r: Dictionary = mover.advance(npc, 1.0 / 30.0)
		arrived = bool(r.get("arrived", false)) or bool(r.get("interacting", false))
		steps += 1
	_assert_true(arrived, "npc arrives within step budget, steps=%d" % steps)
	_assert_true(steps > 10, "movement is continuous (steps=%d > 10)" % steps)
	_assert_true(npc.position.distance_to(goal) <= ConstantsScript.INTERACT_RADIUS, "ends within interact radius, dist=%.1f" % npc.position.distance_to(goal))
	_assert_true(npc.current_cell == ConstantsScript.world_to_cell(npc.position), "current_cell mirrors position")
	_assert_true(npc.position != start_pos, "position changed from start")

	# Dwell:到达目标(或原地)后不应「同帧 done」,需停留 DWELL_DURATION 才 done。
	var mover2 = NPCMoverScript.new()
	mover2.configure(null, null, pathfinder, null)
	var npc2 = NPCStateScript.from_dict({"id": "npc_d", "position": {"x": 100.0, "y": 100.0}})
	# 原地目标(rest 语义):world_pos = interact_target = 当前 position。
	mover2.begin_move(npc2, npc2.position, npc2.position, null)
	var r0: Dictionary = mover2.advance(npc2, 1.0 / 60.0)
	_assert_true(not bool(r0.get("done", false)), "first frame at target must NOT be done (dwell not elapsed)")
	# 累加略少于 DWELL_DURATION 的时间,仍不应 done。
	var done := false
	var elapsed := 1.0 / 60.0
	while elapsed < ConstantsScript.DWELL_DURATION - 0.1:
		var rr: Dictionary = mover2.advance(npc2, 1.0 / 60.0)
		done = bool(rr.get("done", false))
		elapsed += 1.0 / 60.0
	_assert_true(not done, "not done before DWELL_DURATION elapsed (t=%.2f)" % elapsed)
	# 再推进越过 DWELL_DURATION,应 done。
	var done_after := false
	for i in range(20):
		var r2: Dictionary = mover2.advance(npc2, 1.0 / 60.0)
		if bool(r2.get("done", false)):
			done_after = true
			break
	_assert_true(done_after, "done after DWELL_DURATION elapsed")

	# arrival_radius:目标在 INTERACT_RADIUS 内（32px < 40px），但用精确小到达半径时，
	# NPC 仍必须真正走到 goal —— 这是 wander「走到坐标」语义，不能进交互半径就提前停。
	var mover3 = NPCMoverScript.new()
	mover3.configure(null, null, pathfinder, null)
	var npc3 = NPCStateScript.from_dict({"id": "npc_r", "position": {"x": 48.0, "y": 48.0}})
	var near_goal: Vector2 = npc3.position + Vector2(32.0, 0.0)  # 距起点 32px，落在 INTERACT_RADIUS 内
	mover3.begin_move(npc3, near_goal, near_goal, null, 2.0)  # arrival_radius=2px（精确到点）
	var moved3 := false
	var steps3 := 0
	while steps3 < 120:
		var r3: Dictionary = mover3.advance(npc3, 1.0 / 60.0)
		steps3 += 1
		if bool(r3.get("done", false)) or bool(r3.get("interacting", false)):
			break
	_assert_true(npc3.position.distance_to(near_goal) <= 2.5,
		"with small arrival_radius, NPC walks to precise goal (dist=%.1f)" % npc3.position.distance_to(near_goal))
	_assert_true(npc3.position.distance_to(Vector2(48.0, 48.0)) > 1.0,
		"NPC actually moved toward in-radius goal (moved=%.1f px)" % npc3.position.distance_to(Vector2(48.0, 48.0)))
func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER); quit(0)
	else:
		print(FAIL_MARKER)
		for f in failures: print("  - %s" % f)
		quit(1)
