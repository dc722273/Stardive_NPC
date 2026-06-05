extends SceneTree

const PASS_MARKER := "SCHEDULE_SIDEBAR_ORACLE: PASS"
const FAIL_MARKER := "SCHEDULE_SIDEBAR_ORACLE: FAIL"

const SidebarScript := preload("res://scripts/ui/ScheduleSidebar.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const TodoItemScript := preload("res://scripts/state/TodoItem.gd")

var failures: Array = []


func _initialize() -> void:
	_run()
	_finish()


func _run() -> void:
	var sidebar = SidebarScript.new()
	get_root().add_child(sidebar)
	var npc = NPCStateScript.from_dict({"id": "npc_a", "display_name": "Jiu", "position": {"x": 16.0, "y": 16.0}})
	npc.todo_list = [
		TodoItemScript.from_dict({"id": "t1", "intent": "rest", "reason": "歇会儿", "status": "done"}),
		TodoItemScript.from_dict({"id": "t2", "intent": "wander", "reason": "逛逛", "status": "active"}),
		TodoItemScript.from_dict({"id": "t3", "intent": "visit_place", "reason": "回家", "status": "pending"}),
	]
	sidebar.show_for_npc(npc)
	var lines = sidebar.get_rendered_lines()
	_assert_true(lines.size() == 3, "renders 3 todo lines, got %d" % lines.size())
	_assert_true(lines[0].begins_with("✓"), "done prefixed ✓: %s" % lines[0])
	_assert_true(lines[1].begins_with("▶"), "active prefixed ▶: %s" % lines[1])
	_assert_true(lines[2].begins_with("·"), "pending prefixed ·: %s" % lines[2])
	sidebar.clear()
	_assert_true(sidebar.get_rendered_lines().is_empty(), "clear empties sidebar")

	# Bug fix: 选中后 todo 状态变化时,不重新 show_for_npc,只靠 refresh_if_changed 也应实时反映。
	var npc2 = NPCStateScript.from_dict({"id": "npc_b", "display_name": "Tam", "position": {"x": 32.0, "y": 32.0}})
	var t = TodoItemScript.from_dict({"id": "x1", "intent": "wander", "reason": "逛逛", "status": "pending"})
	npc2.todo_list = [t]
	sidebar.show_for_npc(npc2)
	_assert_true(sidebar.get_rendered_lines()[0].begins_with("·"), "initial pending ·")
	# 状态变了但没重新 show_for_npc —— refresh_if_changed 应检测到变化并重渲。
	t.status = &"done"
	var changed: bool = sidebar.refresh_if_changed(npc2)
	_assert_true(changed, "refresh_if_changed returns true when status changed")
	_assert_true(sidebar.get_rendered_lines()[0].begins_with("✓"), "after refresh, shows ✓ done: %s" % sidebar.get_rendered_lines()[0])
	# 再次无变化 —— 不应重建(返回 false,避免每帧浪费)。
	var changed2: bool = sidebar.refresh_if_changed(npc2)
	_assert_true(not changed2, "refresh_if_changed returns false when nothing changed")


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER)
		quit(0)
	else:
		print(FAIL_MARKER)
		for f in failures:
			print("  - %s" % f)
		quit(1)
