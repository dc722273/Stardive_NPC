extends SceneTree

const PASS_MARKER := "NPC_LOOP_ORACLE: PASS"

const TodoItemScript := preload("res://scripts/state/TodoItem.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const ItemStateScript := preload("res://scripts/state/ItemState.gd")
const ConstantsScript := preload("res://scripts/core/Constants.gd")
const InteractionEventLogScript := preload("res://scripts/world/InteractionEventLog.gd")
const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const WorldPlaceRegistryScript := preload("res://scripts/world/WorldPlaceRegistry.gd")
const GridPathfinderScript := preload("res://scripts/world/GridPathfinder.gd")
const NPCMoverScript := preload("res://scripts/npc/NPCMover.gd")
const TodoExecutorScript := preload("res://scripts/npc/TodoExecutor.gd")

const REQUIRED_NPC_MODULES := {
	"llm": "res://scripts/npc/LLMClient.gd",
	"planner": "res://scripts/npc/DailyTodoPlanner.gd",
	"scheduler": "res://scripts/npc/NPCActionScheduler.gd",
	"executor": "res://scripts/npc/TodoExecutor.gd",
	"mover": "res://scripts/npc/NPCMover.gd",
}

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var scripts := _load_required_npc_modules()
	if not failures.is_empty():
		_finish()
		return

	_test_daily_todo_planner_discards_invalid_and_falls_back(scripts["planner"])
	_test_llm_client_discards_late_generation_and_commits_current(scripts["llm"])
	_test_action_scheduler_lanes(scripts["scheduler"])
	_test_todo_executor_blocks_or_falls_back()
	_finish()


func _load_required_npc_modules() -> Dictionary:
	var result := {}
	for key in REQUIRED_NPC_MODULES.keys():
		var path: String = REQUIRED_NPC_MODULES[key]
		# Provenance: P0 implementation plan Task 4 names these NPC backend modules as the feature surface.
		_assert_true(ResourceLoader.exists(path), "required NPC module is loadable: %s" % path)
		if ResourceLoader.exists(path):
			result[key] = load(path)
	return result


func _test_daily_todo_planner_discards_invalid_and_falls_back(planner_script) -> void:
	var planner = planner_script.new()
	var world := _make_world()
	var npc = world["npc"]
	_configure_if_supported(planner, world)

	var mixed_items := [
		{"intent": "visit_place", "target_place_id": "place_clinic", "reason": "valid place", "priority": 90},
		{"intent": "teleport", "target_place_id": "place_clinic", "reason": "invalid intent", "priority": 80},
		{"intent": "visit_place", "target_place_id": "place_missing", "reason": "invalid place", "priority": 70},
		{"intent": "talk_to_npc", "target_npc_id": "npc_missing", "reason": "invalid npc", "priority": 60},
		{"intent": "inspect_item", "target_item_id": "item_missing", "reason": "invalid item", "priority": 50},
		{"intent": "rest", "reason": "valid non-target intent", "priority": 40},
	]
	var capped := _validate_todos(planner, mixed_items, npc, world, 2)
	# Provenance: spec "LLM Daily Todo List" runtime guard says invalid intents/targets are discarded and todo count is capped.
	_assert_true(capped.size() <= 2, "DailyTodoPlanner caps validated todos to requested daily limit")
	# Provenance: spec allowed intent list contains visit_place/talk_to_npc/inspect_item/wander/rest only.
	_assert_equal(_todo_field(capped[0], "intent"), &"visit_place", "DailyTodoPlanner keeps valid visit_place todo")
	# Provenance: spec runtime guard requires invalid targets and invalid intents to be discarded before commit.
	_assert_true(_all_todos_have_allowed_intents_and_valid_targets(capped, world), "DailyTodoPlanner output contains only allowed intents with valid targets")

	var only_invalid := [
		{"intent": "teleport", "target_place_id": "place_clinic"},
		{"intent": "visit_place", "target_place_id": "place_missing"},
	]
	var fallback := _validate_todos(planner, only_invalid, npc, world, 4)
	# Provenance: spec "LLM Daily Todo List" runtime guard says if the list is empty after discard, fallback to wander.
	_assert_equal(fallback.size(), 1, "DailyTodoPlanner creates one fallback todo when all LLM items are invalid")
	# Provenance: spec fallback behavior names wander/rest; this oracle freezes wander as the deterministic MVP fallback.
	_assert_equal(_todo_field(fallback[0], "intent"), &"wander", "DailyTodoPlanner fallback todo intent is wander")


func _test_llm_client_discards_late_generation_and_commits_current(llm_script) -> void:
	var client = llm_script.new()
	var old_operation = _start_operation(client, &"npc_alpha", &"daily_todo")
	var current_operation = _start_operation(client, &"npc_alpha", &"daily_todo")

	# Provenance: spec generation rules require per (npc_id, kind) monotonic generations.
	_assert_true(_operation_generation(current_operation) > _operation_generation(old_operation), "LLMClient increments generation for same npc_id/kind")
	# Provenance: spec operation completion must match operation_id and current generation.
	_assert_true(_operation_id(current_operation) != _operation_id(old_operation), "LLMClient creates distinct operation ids")

	_append_chunk(client, old_operation, "[{\"intent\":\"rest\"}]")
	var late_result = _complete_operation(client, old_operation, "[{\"intent\":\"rest\"}]")
	# Provenance: spec "late response" says stale operation_id/generation results are discarded and cannot commit.
	_assert_equal(_result_committed(late_result), false, "LLMClient discards late response from old generation")

	_append_chunk(client, current_operation, "[{\"intent\":\"wander\"}]")
	var current_result = _complete_operation(client, current_operation, "[{\"intent\":\"wander\"}]")
	# Provenance: spec generation rules allow the current matching operation to commit.
	_assert_equal(_result_committed(current_result), true, "LLMClient commits the current operation result")


func _test_action_scheduler_lanes(scheduler_script) -> void:
	var scheduler = scheduler_script.new()
	var move_first = _start_action(scheduler, &"npc_alpha", &"movement", &"move_to_place")
	var speech_first = _start_action(scheduler, &"npc_alpha", &"speech", &"feedback_stream")
	var move_second = _start_action(scheduler, &"npc_alpha", &"movement", &"move_elsewhere")
	var speech_second = _start_action(scheduler, &"npc_alpha", &"speech", &"conversation_stream")

	# Provenance: spec "Parallel action lanes" allows one movement lane action per NPC.
	_assert_equal(_action_accepted(move_first), true, "NPCActionScheduler accepts first movement action")
	# Provenance: spec "Parallel action lanes" allows movement and speech to run in parallel.
	_assert_equal(_action_accepted(speech_first), true, "NPCActionScheduler accepts speech while movement is running")
	# Provenance: spec "Parallel action lanes" rejects a second movement action for the same NPC.
	_assert_equal(_action_accepted(move_second), false, "NPCActionScheduler rejects duplicate movement action")
	# Provenance: spec "Parallel action lanes" rejects a second speech stream for the same NPC.
	_assert_equal(_action_accepted(speech_second), false, "NPCActionScheduler rejects duplicate speech action")


func _test_todo_executor_blocks_or_falls_back() -> void:
	var pathfinder = GridPathfinderScript.new()
	pathfinder.set_map_bounds(Rect2i(0, 0, 24, 16))
	for c in [Vector2i(4,5), Vector2i(6,5), Vector2i(5,4), Vector2i(5,6)]:
		pathfinder.set_solid_cell(c, true)
	var registry = WorldEntityRegistryScript.new()
	registry.set_map_bounds(Rect2i(0, 0, 24, 16))
	var npc = NPCStateScript.from_dict({"id": "npc_blk", "position": {"x": 48.0, "y": 48.0}})
	registry.add_npc(npc)
	var mover = NPCMoverScript.new()
	mover.configure(registry, null, pathfinder, null)
	var goal := ConstantsScript.cell_to_world_center(Vector2i(5, 5))
	mover.begin_move(npc, goal, goal, null)
	_assert_true(mover.is_idle(), "unreachable target yields no waypoints")
	_assert_true(npc.position.distance_to(goal) > ConstantsScript.INTERACT_RADIUS, "npc not already within interact radius")
	var executor = TodoExecutorScript.new()
	executor.configure(registry, null, pathfinder, null)
	var todo = TodoItemScript.from_dict({"id": "t_blk", "intent": "visit_place", "target_place_id": "nope", "status": "pending"})
	npc.todo_list = [todo]
	executor.mark_todo_blocked(npc, todo)
	_assert_true(StringName(todo.status) == &"BLOCKED", "todo marked BLOCKED")
	_assert_true(npc.todo_list.size() >= 2, "fallback todo appended")


func _make_world() -> Dictionary:
	var entity_registry = WorldEntityRegistryScript.new()
	entity_registry.set_map_bounds(Rect2i(0, 0, 8, 8))
	var place_registry = WorldPlaceRegistryScript.new()
	var pathfinder = GridPathfinderScript.new()
	pathfinder.set_map_bounds(Rect2i(0, 0, 8, 8))
	var event_log = InteractionEventLogScript.new()

	var npc = NPCStateScript.from_dict({"id": "npc_alpha", "current_cell": {"x": 0, "y": 0}})
	var target_npc = NPCStateScript.from_dict({"id": "npc_beta", "current_cell": {"x": 6, "y": 6}})
	var item = ItemStateScript.from_dict({"id": "item_cola", "current_cell": {"x": 1, "y": 0}})
	entity_registry.add_npc(npc)
	entity_registry.add_npc(target_npc)
	entity_registry.add_item(item)

	place_registry.create_place(&"place_clinic", "Clinic", "known valid target place", Rect2i(4, 4, 3, 3), Vector2i(5, 4), [Vector2i(4, 4)], [Vector2i(5, 5)])
	return {
		"entity_registry": entity_registry,
		"place_registry": place_registry,
		"pathfinder": pathfinder,
		"event_log": event_log,
		"npc": npc,
	}


func _configure_if_supported(target, world: Dictionary, extra = null) -> void:
	var variants := [
		[world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"], extra],
		[world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"]],
		[world["entity_registry"], world["place_registry"], world["pathfinder"]],
		[world["entity_registry"], world["place_registry"]],
		[world],
	]
	_call_optional(target, ["configure", "set_context", "set_registries"], variants)


func _validate_todos(planner, raw_items: Array, npc, world: Dictionary, max_count: int) -> Array:
	var result = _call_required(
		planner,
		["validate_todos", "validate_daily_todos", "validate_llm_todos", "sanitize_todos"],
		[
			[raw_items, npc, world["entity_registry"], world["place_registry"], max_count],
			[npc, raw_items, world["entity_registry"], world["place_registry"], max_count],
			[raw_items, world["entity_registry"], world["place_registry"], max_count],
			[raw_items, npc, world, max_count],
			[raw_items, world, max_count],
			[raw_items, max_count],
			[raw_items],
		],
		"DailyTodoPlanner must expose a todo validation method"
	)
	_assert_true(result is Array, "DailyTodoPlanner validation returns an Array")
	return result if result is Array else []


func _start_operation(client, npc_id: StringName, kind: StringName):
	return _call_required(
		client,
		["start_operation", "begin_operation", "create_operation", "request_operation"],
		[[npc_id, kind], [npc_id, kind, {}]],
		"LLMClient must expose an operation start method"
	)


func _append_chunk(client, operation, chunk: String) -> void:
	_call_required(
		client,
		["append_stream_chunk", "receive_stream_chunk", "on_stream_chunk"],
		[[_operation_id(operation), chunk], [_operation_id(operation), _operation_generation(operation), chunk], [operation, chunk]],
		"LLMClient must expose a streaming chunk method"
	)


func _complete_operation(client, operation, final_text: String):
	return _call_required(
		client,
		["complete_operation", "finish_operation", "commit_operation"],
		[[_operation_id(operation), final_text], [_operation_id(operation), _operation_generation(operation), final_text], [_operation_id(operation)], [operation, final_text], [operation]],
		"LLMClient must expose an operation completion method"
	)


func _start_action(scheduler, npc_id: StringName, lane: StringName, kind: StringName):
	var action := {
		"id": StringName("%s_%s" % [lane, kind]),
		"npc_id": npc_id,
		"lane": lane,
		"kind": kind,
		"status": &"queued",
	}
	return _call_required(
		scheduler,
		["start_action", "try_start_action", "schedule_action", "acquire_lane"],
		[[action], [npc_id, lane, kind], [npc_id, lane, action], [npc_id, action]],
		"NPCActionScheduler must expose an action/lane start method"
	)


func _call_optional(target, names: Array, variants: Array) -> Variant:
	var call := _select_call(target, names, variants)
	if call.is_empty():
		return null
	return target.callv(call["name"], call["args"])


func _call_required(target, names: Array, variants: Array, message: String) -> Variant:
	var call := _select_call(target, names, variants)
	_assert_true(not call.is_empty(), message)
	if call.is_empty():
		return null
	return target.callv(call["name"], call["args"])


func _select_call(target, names: Array, variants: Array) -> Dictionary:
	for method in target.get_method_list():
		var method_name: String = str(method.get("name", ""))
		if not names.has(method_name):
			continue
		var arg_count: int = (method.get("args", []) as Array).size()
		for args in variants:
			if args.size() == arg_count:
				return {"name": method_name, "args": args}
	return {}


func _all_todos_have_allowed_intents_and_valid_targets(todos: Array, world: Dictionary) -> bool:
	for todo in todos:
		var intent: StringName = _todo_field(todo, "intent")
		if not [&"visit_place", &"talk_to_npc", &"inspect_item", &"wander", &"rest"].has(intent):
			return false
		if intent == &"visit_place" and not world["place_registry"].places.has(_todo_field(todo, "target_place_id")):
			return false
		if intent == &"talk_to_npc" and not world["entity_registry"].npcs.has(_todo_field(todo, "target_npc_id")):
			return false
		if intent == &"inspect_item" and not world["entity_registry"].items.has(_todo_field(todo, "target_item_id")):
			return false
	return true


func _operation_id(operation) -> StringName:
	return StringName(_field(operation, "id", _field(operation, "operation_id", "")))


func _operation_generation(operation) -> int:
	return int(_field(operation, "generation", 0))


func _result_committed(result) -> bool:
	if result == null:
		return false
	if result is bool:
		return result
	if result is Dictionary:
		if result.has("committed"):
			return bool(result["committed"])
		var status := StringName(result.get("status", ""))
		if [&"discarded", &"late", &"cancelled", &"failed", &"ignored"].has(status):
			return false
		if [&"done", &"committed", &"ok", &"success"].has(status):
			return true
	if result is Array:
		return not result.is_empty()
	if result is String:
		return not result.is_empty()
	return bool(_field(result, "committed", false))


func _action_accepted(result) -> bool:
	if result is bool:
		return result
	if result is Dictionary:
		if result.has("accepted"):
			return bool(result["accepted"])
		if result.has("ok"):
			return bool(result["ok"])
		var status := StringName(result.get("status", ""))
		if [&"running", &"queued", &"accepted", &"ok"].has(status):
			return true
		if [&"rejected", &"blocked", &"failed"].has(status):
			return false
	if result == null:
		return false
	return bool(_field(result, "accepted", false))


func _todo_field(todo, name: String) -> Variant:
	return _field(todo, name, &"")


func _field(value, name: String, fallback = null) -> Variant:
	if value is Dictionary:
		return value.get(name, fallback)
	if value != null and value is Object:
		return value.get(name)
	return fallback


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _assert_equal(actual, expected, message: String) -> void:
	if actual != expected:
		failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER)
		quit(0)
		return

	print("NPC_LOOP_ORACLE: FAIL")
	for failure in failures:
		push_error(failure)
	quit(1)
