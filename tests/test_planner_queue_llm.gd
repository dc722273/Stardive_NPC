extends RefCounted
class_name TestPlannerQueueLLM

## Deterministic 单测: 用 fake transport/llm_client 验证 request_daily_todos 的
## 分支语义（无需联网）：
##   - should_dispatch 谓词：op 被取代时 transport 回 superseded -> planner 不注入 wander。
##   - commit late/cancelled -> 不注入任何 todo（todos 为空）。
##   - 真实失败（非 superseded、非 late）-> fallback 到单个 wander。
##   - 正常 JSON -> 经 validate_todos 产出校验后 todos。
## 由 tests/run_tests.gd 聚合调用 run()；run() 返回 failures 数组（空=全过）。

const DailyTodoPlannerScript := preload("res://scripts/npc/DailyTodoPlanner.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const WorldPlaceRegistryScript := preload("res://scripts/world/WorldPlaceRegistry.gd")


func run() -> Array:
	var failures: Array = []
	_test_superseded_does_not_inject_wander(failures)
	_test_should_dispatch_false_yields_superseded(failures)
	_test_commit_late_does_not_inject_wander(failures)
	_test_network_failure_falls_back_to_wander(failures)
	_test_valid_json_produces_validated_todos(failures)
	return failures


# fake transport：尊重 should_dispatch（false -> superseded），否则按预设 result 同步回调。
class FakeTransport:
	var preset_result: Dictionary = {"ok": false, "error": "network_down", "status_code": 0}
	func request_chat(_messages: Array, opts: Dictionary, on_done: Callable) -> void:
		var should = opts.get("should_dispatch", null)
		if should is Callable and should.is_valid() and not bool(should.call()):
			on_done.call({"ok": false, "error": "superseded", "status_code": 0})
			return
		on_done.call(preset_result)


# fake llm_client：start_operation 递增 generation 并记录 current op id；
# complete_operation 按 current 性返回 committed/late。模拟 LLMClient 的关键契约。
class FakeLLMClient:
	var current_operation_ids: Dictionary = {}
	var _counter: int = 0
	var _commit_status: StringName = &"committed"
	func start_operation(npc_id: StringName, kind: StringName) -> Dictionary:
		_counter += 1
		var op_id := StringName("op_%d" % _counter)
		var key := "%s::%s" % [str(npc_id), str(kind)]
		current_operation_ids[key] = op_id
		return {"operation_id": op_id, "id": op_id, "generation": _counter}
	func complete_operation(_op_id: StringName, final_text: String = "") -> Dictionary:
		if _commit_status != &"committed":
			return {"committed": false, "status": _commit_status, "text": final_text}
		return {"committed": true, "status": &"committed", "text": final_text}


func _make_world() -> Dictionary:
	var entity_registry = WorldEntityRegistryScript.new()
	entity_registry.set_map_bounds(Rect2i(0, 0, 8, 8))
	var place_registry = WorldPlaceRegistryScript.new()
	var npc = NPCStateScript.from_dict({"id": "npc_alpha", "current_cell": {"x": 0, "y": 0}})
	entity_registry.add_npc(npc)
	place_registry.create_place(&"place_clinic", "Clinic", "valid place", Rect2i(4, 4, 3, 3), Vector2i(5, 4), [Vector2i(4, 4)], [Vector2i(5, 5)])
	return {"entity_registry": entity_registry, "place_registry": place_registry, "npc": npc}


# transport 回 superseded -> planner 返回 ok=false/status=late，todos 为空（不注入 wander）。
func _test_superseded_does_not_inject_wander(failures: Array) -> void:
	var planner = DailyTodoPlannerScript.new()
	var world := _make_world()
	var transport := FakeTransport.new()
	transport.preset_result = {"ok": true, "content": "{\"todos\":[]}"}  # 即便会成功，也应被 should_dispatch 拦下
	var client := FakeLLMClient.new()
	# 先起一个 op，再起第二个把 current 顶掉，使第一个的谓词为 false。
	client.start_operation(&"npc_alpha", &"daily_todo")  # op_1
	# 手动制造"当前是更新的 op"：request_daily_todos 内部还会再 start 一次（op_3），
	# 这里直接验证 should_dispatch 行为：我们让 transport 在 dispatch 时检查谓词。
	var done: Array = []
	# 注入一个永远过期的谓词场景：把 current 改成别的 id 后再发。
	planner.request_daily_todos(world["npc"], world, transport, client, func(r: Dictionary) -> void: done.append(r))
	# request_daily_todos 内部 start_operation 会把 current 设为自己的 op_id，
	# 所以默认谓词为 true、不会 superseded。这个用例改测：dispatch 前 current 被顶替。
	# 见下一个用例做精确控制；此处仅断言回调被调用一次且结构合法。
	_assert_true(done.size() == 1, "request_daily_todos invokes on_done exactly once", failures)


# 精确控制：构造 should_dispatch=false 的场景——request 发起后立刻起新 op 顶替 current。
# 用自定义 transport：先捕获 opts.should_dispatch，等外部顶替 current 后再 dispatch。
func _test_should_dispatch_false_yields_superseded(failures: Array) -> void:
	var planner = DailyTodoPlannerScript.new()
	var world := _make_world()
	var client := FakeLLMClient.new()

	# 延迟 transport：把请求暂存，外部顶替 current 后手动 fire。
	var deferred := DeferredTransport.new()
	var done: Array = []
	planner.request_daily_todos(world["npc"], world, deferred, client, func(r: Dictionary) -> void: done.append(r))
	# 此刻 current[npc_alpha::daily_todo] == 这次请求的 op。再起一个新 op 顶替它。
	client.start_operation(&"npc_alpha", &"daily_todo")
	# 现在 fire：should_dispatch 应返回 false -> superseded -> planner 回 late，无 wander。
	deferred.fire()
	_assert_true(done.size() == 1, "deferred request resolves once", failures)
	if not done.is_empty():
		_assert_equal(bool(done[0].get("ok", false)), false, "superseded -> ok=false", failures)
		_assert_equal(StringName(done[0].get("status", "")), &"late", "superseded mapped to late status", failures)
		var todos: Variant = done[0].get("todos", [])
		_assert_true(todos is Array and (todos as Array).is_empty(), "superseded injects NO todo (no wander)", failures)


# complete_operation 返回 late -> planner 不注入任何 todo。
func _test_commit_late_does_not_inject_wander(failures: Array) -> void:
	var planner = DailyTodoPlannerScript.new()
	var world := _make_world()
	var transport := FakeTransport.new()
	transport.preset_result = {"ok": true, "content": "{\"todos\":[{\"intent\":\"wander\"}]}"}
	var client := FakeLLMClient.new()
	client._commit_status = &"late"  # 模拟 LLMClient 判定为过期
	var done: Array = []
	planner.request_daily_todos(world["npc"], world, transport, client, func(r: Dictionary) -> void: done.append(r))
	_assert_true(done.size() == 1, "late commit resolves once", failures)
	if not done.is_empty():
		_assert_equal(bool(done[0].get("ok", false)), false, "late commit -> ok=false", failures)
		var todos: Variant = done[0].get("todos", [])
		_assert_true(todos is Array and (todos as Array).is_empty(), "late commit injects NO todo", failures)


# 真实失败（非 superseded、非 late）-> fallback 到单个 wander。
func _test_network_failure_falls_back_to_wander(failures: Array) -> void:
	var planner = DailyTodoPlannerScript.new()
	var world := _make_world()
	var transport := FakeTransport.new()
	transport.preset_result = {"ok": false, "error": "http_status_500", "status_code": 500}
	var client := FakeLLMClient.new()
	var done: Array = []
	planner.request_daily_todos(world["npc"], world, transport, client, func(r: Dictionary) -> void: done.append(r))
	_assert_true(done.size() == 1, "network failure resolves once", failures)
	if not done.is_empty():
		_assert_equal(bool(done[0].get("ok", false)), true, "network failure -> ok=true with fallback", failures)
		var todos: Variant = done[0].get("todos", [])
		_assert_true(todos is Array and (todos as Array).size() == 1, "network failure injects one fallback todo", failures)
		if todos is Array and not (todos as Array).is_empty():
			_assert_equal(StringName(todos[0].intent), &"wander", "fallback todo intent is wander", failures)


# 正常 JSON -> 经 validate_todos 产出校验后 todos。
func _test_valid_json_produces_validated_todos(failures: Array) -> void:
	var planner = DailyTodoPlannerScript.new()
	var world := _make_world()
	var transport := FakeTransport.new()
	# place_clinic 在 world 内合法；teleport 非法 intent 应被 validate_todos 丢弃。
	transport.preset_result = {"ok": true, "content": "{\"todos\":[{\"intent\":\"visit_place\",\"target_place_id\":\"place_clinic\"},{\"intent\":\"teleport\"}]}"}
	var client := FakeLLMClient.new()
	var done: Array = []
	planner.request_daily_todos(world["npc"], world, transport, client, func(r: Dictionary) -> void: done.append(r))
	_assert_true(done.size() == 1, "valid json resolves once", failures)
	if not done.is_empty():
		_assert_equal(bool(done[0].get("ok", false)), true, "valid json -> ok=true", failures)
		var todos: Variant = done[0].get("todos", [])
		_assert_true(todos is Array, "valid json -> todos is Array", failures)
		# 只保留合法的 visit_place（teleport 被丢弃）。
		var intents := []
		for t in todos:
			intents.append(StringName(t.intent))
		_assert_true(intents.has(&"visit_place"), "validated todos keep visit_place", failures)
		_assert_true(not intents.has(&"teleport"), "validated todos drop invalid teleport intent", failures)


# 暂存请求的 transport：fire() 时才真正按 should_dispatch 判定回调。
class DeferredTransport:
	var _messages: Array = []
	var _opts: Dictionary = {}
	var _on_done: Callable = Callable()
	func request_chat(messages: Array, opts: Dictionary, on_done: Callable) -> void:
		_messages = messages
		_opts = opts
		_on_done = on_done
	func fire() -> void:
		var should = _opts.get("should_dispatch", null)
		if should is Callable and should.is_valid() and not bool(should.call()):
			_on_done.call({"ok": false, "error": "superseded", "status_code": 0})
			return
		_on_done.call({"ok": true, "content": "{\"todos\":[]}"})


func _assert_true(condition: bool, message: String, failures: Array) -> void:
	if not condition:
		failures.append(message)


func _assert_equal(actual, expected, message: String, failures: Array) -> void:
	if actual != expected:
		failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
