extends RefCounted
class_name TestDailyPlannerLLM

## Deterministic 单测: DailyTodoPlanner 的 LLM 接线纯函数 (parse_todos_payload / build_prompt)。
## request_daily_todos 的联网部分由 apr/npc-loop/oracle/llm_live_oracle.gd 覆盖，这里不测网络。
## 由 tests/run_tests.gd 聚合调用 run()；run() 返回 failures 数组（空=全过）。

const DailyTodoPlannerScript := preload("res://scripts/npc/DailyTodoPlanner.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const WorldPlaceRegistryScript := preload("res://scripts/world/WorldPlaceRegistry.gd")
const ItemStateScript := preload("res://scripts/state/ItemState.gd")


func run() -> Array:
	var failures: Array = []
	_test_parse_todos_payload_object_with_todos(failures)
	_test_parse_todos_payload_top_level_array(failures)
	_test_parse_todos_payload_bad_json(failures)
	_test_parse_todos_payload_empty_object(failures)
	_test_build_prompt_returns_system_and_user(failures)
	return failures


func _test_parse_todos_payload_object_with_todos(failures: Array) -> void:
	var planner = DailyTodoPlannerScript.new()
	var raw = planner.parse_todos_payload("{\"todos\":[{\"intent\":\"wander\"},{\"intent\":\"rest\"}]}")
	_assert_true(raw is Array, "parse_todos_payload returns Array for {todos:[...]}", failures)
	_assert_equal(raw.size(), 2, "parse_todos_payload extracts .todos entries", failures)
	_assert_equal(str(raw[0].get("intent", "")), "wander", "parse_todos_payload preserves first todo", failures)


func _test_parse_todos_payload_top_level_array(failures: Array) -> void:
	var planner = DailyTodoPlannerScript.new()
	var raw = planner.parse_todos_payload("[{\"intent\":\"rest\"}]")
	_assert_true(raw is Array, "parse_todos_payload tolerates top-level array", failures)
	_assert_equal(raw.size(), 1, "parse_todos_payload returns top-level array entries", failures)


func _test_parse_todos_payload_bad_json(failures: Array) -> void:
	var planner = DailyTodoPlannerScript.new()
	var raw = planner.parse_todos_payload("not json at all {")
	_assert_true(raw is Array and raw.is_empty(), "parse_todos_payload returns [] for bad json", failures)


func _test_parse_todos_payload_empty_object(failures: Array) -> void:
	var planner = DailyTodoPlannerScript.new()
	var raw = planner.parse_todos_payload("{}")
	_assert_true(raw is Array and raw.is_empty(), "parse_todos_payload returns [] for object without todos", failures)


func _test_build_prompt_returns_system_and_user(failures: Array) -> void:
	var planner = DailyTodoPlannerScript.new()
	var world := _make_world()
	var messages = planner.build_prompt(world["npc"], world)
	_assert_true(messages is Array and not messages.is_empty(), "build_prompt returns non-empty Array", failures)
	var roles := []
	for message in messages:
		_assert_true(message is Dictionary, "build_prompt entry is a Dictionary", failures)
		roles.append(str(message.get("role", "")))
	_assert_true(roles.has("system"), "build_prompt includes a system message", failures)
	_assert_true(roles.has("user"), "build_prompt includes a user message", failures)
	# user content 应携带 NPC 人格与可见 place id，证明 world 上下文被组进 prompt。
	var user_content := ""
	for message in messages:
		if str(message.get("role", "")) == "user":
			user_content = str(message.get("content", ""))
	_assert_true(user_content.contains("place_clinic"), "build_prompt user content lists visible place ids", failures)


func _make_world() -> Dictionary:
	var entity_registry = WorldEntityRegistryScript.new()
	entity_registry.set_map_bounds(Rect2i(0, 0, 8, 8))
	var place_registry = WorldPlaceRegistryScript.new()
	var npc = NPCStateScript.from_dict({"id": "npc_alpha", "name": "Alpha", "traits": {"tell": 60, "face": 50, "control": 40, "caution": 55, "play": 45}, "current_cell": {"x": 0, "y": 0}})
	var target_npc = NPCStateScript.from_dict({"id": "npc_beta", "current_cell": {"x": 6, "y": 6}})
	var item = ItemStateScript.from_dict({"id": "item_cola", "current_cell": {"x": 1, "y": 0}})
	entity_registry.add_npc(npc)
	entity_registry.add_npc(target_npc)
	entity_registry.add_item(item)
	place_registry.create_place(&"place_clinic", "Clinic", "known valid target place", Rect2i(4, 4, 3, 3), Vector2i(5, 4), [Vector2i(4, 4)], [Vector2i(5, 5)])
	return {
		"entity_registry": entity_registry,
		"place_registry": place_registry,
		"npc": npc,
	}


func _assert_true(condition: bool, message: String, failures: Array) -> void:
	if not condition:
		failures.append(message)


func _assert_equal(actual, expected, message: String, failures: Array) -> void:
	if actual != expected:
		failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
