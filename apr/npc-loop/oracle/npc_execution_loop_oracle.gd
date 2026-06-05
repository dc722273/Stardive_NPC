extends SceneTree

## Oracle: MainGame 把 NPC 执行循环接进主循环后，NPC 能真正消费 todo 并移动。
##
## Work type: feature（执行层接线缺失——TodoExecutor/NPCMover 从未被 MainGame 驱动）。
## 信号：seed 一个 NPC + 一个 place + 一个 visit_place todo，调 MainGame 的执行步进方法后，
##       NPC.current_cell 从起点移动到目标可达格，且 todo.status==done。
##
## Pre-state（实现前）：MainGame 没有 tick_npc_execution() 方法，调用即报错 → FAIL_EXPECTED。
## Post-state（实现后）：调用后 NPC 移动且 todo done → PASS。
##
## Provenance:
## - spec "TodoExecutor"：todo 执行驱动 NPC 移动；P0 Task 5 要求 MainGame 接线 runtime。
## - 当前 MainGame._process 只做 tick++/相机/重绘，无任何 NPC 执行驱动（本 oracle 要补的缺口）。

const PASS_MARKER := "NPC_EXECUTION_LOOP_ORACLE: PASS"
const FAIL_MARKER := "NPC_EXECUTION_LOOP_ORACLE: FAIL"

const MainGameScript := preload("res://scripts/MainGame.gd")
const TodoItemScript := preload("res://scripts/state/TodoItem.gd")
const ConstantsScript := preload("res://scripts/core/Constants.gd")

var failures: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var game = MainGameScript.new()
	get_root().add_child(game)
	await process_frame  # 让 MainGame._ready 完成 wiring（services + npc seed）

	var entity_registry = game.entity_registry
	if entity_registry == null:
		_fail("MainGame.entity_registry not wired after _ready")
		return _finish(game)

	# 取 seed NPC（_seed_sample_npc_item_data 放了 npc_jiutong）。
	var npc = entity_registry.npcs.get(&"npc_jiutong", null)
	if npc == null:
		# 兼容：取任意一个 NPC。
		for v in entity_registry.npcs.values():
			npc = v
			break
	if npc == null:
		_fail("no seeded NPC found in entity_registry")
		return _finish(game)

	# 在地图内造一个可达 place，给 NPC 一个 visit_place todo。
	var place_registry = game.place_registry
	if place_registry == null:
		_fail("MainGame.place_registry not wired")
		return _finish(game)
	# 用一个 3x3 footprint 造 place（door_cell 可达、walkable）。
	# door_cell 必须离 NPC 起点远于 INTERACT_RADIUS（40px / >1 格），否则一开始就在交互半径内、
	# 会瞬间 arrived 而不产生连续移动——本 oracle 要验证的是逐帧推进，故把目标放到远格。
	place_registry.create_place(&"place_target", "Target", "oracle target place", Rect2i(11, 9, 3, 3), Vector2i(12, 9), [Vector2i(11, 9)], [Vector2i(12, 10)])

	var todo = TodoItemScript.from_dict({
		"id": "todo_oracle_visit",
		"intent": "visit_place",
		"target_place_id": "place_target",
		"status": "pending",
	})
	npc.todo_list = [todo]

	# === 关键调用：tick=DECISION 层一次（解析目标 + begin_move + status=active），
	#     然后 advance=逐帧推进层把 NPC 沿 waypoints 连续移动到目标。 ===
	if not game.has_method("tick_npc_execution"):
		_fail("MainGame has no tick_npc_execution() — execution loop not wired into MainGame")
		return _finish(game)
	if not game.has_method("advance_npc_movement"):
		_fail("MainGame has no advance_npc_movement() — per-frame advance layer not wired into MainGame")
		return _finish(game)

	var start_pos: Vector2 = npc.position
	# tick 一次：做决策（resolve 目标 + begin_move + todo.status=active）。
	game.tick_npc_execution()
	# 逐帧推进直到 todo done（连续移动；30fps，留 300 帧余量 = 10 秒模拟时间）。
	var arrived := false
	var frames := 0
	while frames < 300 and not arrived:
		game.advance_npc_movement(1.0 / 30.0)
		if StringName(todo.status) == &"done":
			arrived = true
		frames += 1

	# Provenance: spec 连续移动——NPC 的 position 应随帧推进而改变（不再瞬移）。
	if npc.position == start_pos:
		_fail("NPC did not move continuously (start_pos=%s end_pos=%s)" % [str(start_pos), str(npc.position)])
	# Provenance: 到达/进入交互半径后 todo.status==done。
	if StringName(todo.status) != &"done":
		_fail("todo not marked done after arrival (status=%s frames=%d)" % [str(todo.status), frames])

	# === wander 端到端:wander 目标曾被当成「靠近交互对象」(相邻格 32px < INTERACT_RADIUS),
	#     导致 NPC 一步不走就 dwell→done(wander 不移动 bug)。这里验证 wander 在真实
	#     tick+advance 循环里 NPC 真的连续移动。 ===
	npc.todo_list = []
	var release = game.action_scheduler
	if release != null and release.has_method("finish_action"):
		release.finish_action(npc.id, &"movement")
	var wander_mover = game.npc_movers.get(npc.id, null)
	if wander_mover != null and wander_mover.has_method("reset"):
		wander_mover.reset()
	var wander_todo = TodoItemScript.from_dict({"id": "todo_oracle_wander", "intent": "wander", "status": "pending"})
	npc.todo_list = [wander_todo]
	var wander_start: Vector2 = npc.position
	game.tick_npc_execution()
	var wander_done := false
	var wframes := 0
	while wframes < 300 and not wander_done:
		game.advance_npc_movement(1.0 / 30.0)
		if StringName(wander_todo.status) == &"done":
			wander_done = true
		wframes += 1
	if npc.position.distance_to(wander_start) <= ConstantsScript.INTERACT_RADIUS:
		_fail("wander did not move NPC beyond INTERACT_RADIUS (moved=%.1f px, frames=%d)" % [npc.position.distance_to(wander_start), wframes])
	if StringName(wander_todo.status) != &"done":
		_fail("wander todo not done after movement (status=%s frames=%d)" % [str(wander_todo.status), wframes])

	_finish(game)


func _fail(message: String) -> void:
	failures.append(message)


func _finish(game) -> void:
	if game != null:
		game.queue_free()
	if failures.is_empty():
		print(PASS_MARKER)
		quit(0)
		return
	print(FAIL_MARKER)
	for f in failures:
		push_error(str(f))
	quit(1)
