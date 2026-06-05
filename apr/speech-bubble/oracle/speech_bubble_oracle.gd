extends SceneTree

const PASS_MARKER := "SPEECH_BUBBLE_ORACLE: PASS"
const FAIL_MARKER := "SPEECH_BUBBLE_ORACLE: FAIL"

const MainGameScript := preload("res://scripts/MainGame.gd")
const TodoItemScript := preload("res://scripts/state/TodoItem.gd")

var failures: Array = []
var main = null


func _initialize() -> void:
	main = MainGameScript.new()
	get_root().add_child(main)
	_async()


func _async() -> void:
	await process_frame
	_run()
	_finish()


func _run() -> void:
	# 取 seed NPC,给一个带 reason 的 pending todo,tick 决策后气泡应显示 reason。
	var npc = null
	for n in main.entity_registry.npcs.values():
		npc = n
		break
	_assert_true(npc != null, "seed npc exists")
	if npc == null:
		return
	npc.todo_list = [TodoItemScript.from_dict({"id": "tb", "intent": "wander", "reason": "去看看那罐可乐", "status": "pending"})]
	main.tick_npc_execution()
	var visual = main.entity_visual_layer.npc_visuals.get(npc.id)
	_assert_true(visual != null, "npc visual exists")
	if visual == null:
		return
	var bubble = visual.get_node_or_null("SpeechBubble")
	_assert_true(bubble != null and bubble.visible, "bubble visible after decide")
	_assert_true(bubble != null and bubble.text == "去看看那罐可乐", "bubble shows todo reason, got: %s" % (bubble.text if bubble != null else "<none>"))


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
