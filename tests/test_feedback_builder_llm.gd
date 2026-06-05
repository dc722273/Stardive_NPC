extends RefCounted
class_name TestFeedbackBuilderLLM

## Deterministic 单测: NPCFeedbackBuilder 的兜底路径与 build_feedback 回归（不联网）。
## 由 tests/run_tests.gd 聚合调用 run()；run() 返回 failures 数组（空=全过）。

const NPCFeedbackBuilderScript := preload("res://scripts/npc/NPCFeedbackBuilder.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const WorldPlaceRegistryScript := preload("res://scripts/world/WorldPlaceRegistry.gd")
const GridPathfinderScript := preload("res://scripts/world/GridPathfinder.gd")
const InteractionEventLogScript := preload("res://scripts/world/InteractionEventLog.gd")


func run() -> Array:
	var failures: Array = []
	_test_stream_feedback_without_transport_uses_deterministic_text(failures)
	_test_stream_feedback_null_transport_emits_done_with_feedback(failures)
	_test_build_feedback_forced_drop_uses_stardive_text(failures)
	_test_build_feedback_drop_on_npc_uses_stardive_text(failures)
	_test_drop_on_npc_feedback_changes_with_repetition_stage(failures)
	_test_auto_drop_feedback_mentions_ground_action(failures)
	_test_transfer_feedback_changes_with_repetition_stage(failures)
	_test_feedback_prompt_requires_repetition_performance(failures)
	_test_transfer_feedback_distinguishes_previous_and_target(failures)
	_test_set_transport_does_not_break_existing_configure(failures)
	return failures


func _make_world() -> Dictionary:
	var entity_registry = WorldEntityRegistryScript.new()
	entity_registry.set_map_bounds(Rect2i(0, 0, 8, 8))
	var place_registry = WorldPlaceRegistryScript.new()
	var pathfinder = GridPathfinderScript.new()
	pathfinder.set_map_bounds(Rect2i(0, 0, 8, 8))
	var event_log = InteractionEventLogScript.new()

	var npc = NPCStateScript.from_dict({"id": "npc_alpha", "current_cell": {"x": 5, "y": 5}})
	var npc_beta = NPCStateScript.from_dict({"id": "npc_beta", "name": "Beta", "current_cell": {"x": 6, "y": 5}})
	entity_registry.add_npc(npc)
	entity_registry.add_npc(npc_beta)
	place_registry.create_place(&"place_clinic", "Clinic", "valid place", Rect2i(4, 4, 3, 3), Vector2i(5, 4), [Vector2i(4, 4)], [Vector2i(5, 5)])
	return {
		"entity_registry": entity_registry,
		"place_registry": place_registry,
		"pathfinder": pathfinder,
		"event_log": event_log,
		"npc": npc,
		"npc_beta": npc_beta,
	}


# transport=null 时 stream_feedback 调 on_chunk 和 on_done，文本等于 build_feedback 兜底文本。
func _test_stream_feedback_without_transport_uses_deterministic_text(failures: Array) -> void:
	var world := _make_world()
	var builder = NPCFeedbackBuilderScript.new()
	builder.configure(world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"])

	var event = world["event_log"].record(&"player_forced_drop_item", &"item_cola", &"npc_alpha", &"npc", Vector2i(5, 5))
	var expected: Dictionary = builder.build_feedback(event, world["npc"], world)

	var chunks: Array = []
	var done_payloads: Array = []
	builder.stream_feedback(
		event,
		world["npc"],
		world,
		func(chunk: String) -> void: chunks.append(chunk),
		func(result: Dictionary) -> void: done_payloads.append(result)
	)

	_assert_equal(chunks.size(), 1, "stream_feedback emits exactly one chunk on fallback path", failures)
	if not chunks.is_empty():
		_assert_equal(chunks[0], expected["text"], "stream_feedback fallback chunk equals build_feedback text", failures)
	_assert_equal(done_payloads.size(), 1, "stream_feedback emits exactly one done payload on fallback path", failures)
	if not done_payloads.is_empty():
		_assert_equal(str(done_payloads[0].get("text", "")), str(expected["text"]), "stream_feedback done text equals build_feedback text", failures)
		_assert_equal(bool(done_payloads[0].get("ok", false)), true, "stream_feedback done payload stays ok", failures)


# transport=null 时 on_done 收到的就是 build_feedback 的 feedback（不联网）。
func _test_stream_feedback_null_transport_emits_done_with_feedback(failures: Array) -> void:
	var world := _make_world()
	var builder = NPCFeedbackBuilderScript.new()
	# 显式只注入到 llm_client 缺失场景：transport 保持 null。
	builder.configure(world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"])
	builder.set_transport(null)

	var event = world["event_log"].record(&"player_drop_item_on_npc", &"item_cola", &"npc_alpha", &"npc", Vector2i(5, 5))
	var expected: Dictionary = builder.build_feedback(event, world["npc"], world)

	var done_payloads: Array = []
	builder.stream_feedback(
		event,
		world["npc"],
		world,
		func(_chunk: String) -> void: pass,
		func(result: Dictionary) -> void: done_payloads.append(result)
	)

	_assert_equal(done_payloads.size(), 1, "stream_feedback with null transport emits one done payload", failures)
	if not done_payloads.is_empty():
		_assert_equal(str(done_payloads[0].get("event_id", "")), str(expected["event_id"]), "stream_feedback done binds source event id", failures)
		_assert_equal(str(done_payloads[0].get("npc_id", "")), str(expected["npc_id"]), "stream_feedback done binds npc id", failures)


# build_feedback 兜底路径：player_forced_drop_item 使用 Stardive 中文反馈。
func _test_build_feedback_forced_drop_uses_stardive_text(failures: Array) -> void:
	var world := _make_world()
	var builder = NPCFeedbackBuilderScript.new()
	builder.configure(world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"])

	var event = world["event_log"].record(&"player_forced_drop_item", &"item_cola", &"npc_alpha", &"npc", Vector2i(5, 5))
	var feedback: Dictionary = builder.build_feedback(event, world["npc"], world)
	_assert_equal(str(feedback.get("text", "")), "npc_alpha注意到东西被丢下了。", "build_feedback forced-drop uses Stardive fallback text", failures)


# build_feedback 兜底路径：player_drop_item_on_npc 使用 Stardive 道具反应。
func _test_build_feedback_drop_on_npc_uses_stardive_text(failures: Array) -> void:
	var world := _make_world()
	var builder = NPCFeedbackBuilderScript.new()
	builder.configure(world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"])

	var event = world["event_log"].record(&"player_drop_item_on_npc", &"item_cola", &"npc_alpha", &"npc", Vector2i(5, 5))
	var feedback: Dictionary = builder.build_feedback(event, world["npc"], world)
	_assert_equal(str(feedback.get("text", "")), "npc_alpha接过物品，先看清楚它从谁手里来。", "build_feedback drop-on-npc uses Stardive fallback text", failures)


func _test_drop_on_npc_feedback_changes_with_repetition_stage(failures: Array) -> void:
	var world := _make_world()
	var builder = NPCFeedbackBuilderScript.new()
	builder.configure(world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"])
	var payload := {
		"item_name": "川普专属健怡可乐",
		"interaction_trace": {"countInWindow": 3, "stage": "noticed", "heat": 139},
		"performance_plan": {"pattern": "preemptive_gag"},
	}
	var event = world["event_log"].record(&"player_drop_item_on_npc", &"diet_coke", &"npc_alpha", &"npc", Vector2i(5, 5), payload)
	var feedback: Dictionary = builder.build_feedback(event, world["npc"], world)
	_assert_equal(str(feedback.get("text", "")).find("抢在别人开口前") >= 0, true, "third repeated drop uses preemptive gag fallback", failures)


func _test_auto_drop_feedback_mentions_ground_action(failures: Array) -> void:
	var world := _make_world()
	var builder = NPCFeedbackBuilderScript.new()
	builder.configure(world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"])
	var payload := {
		"item_name": "川普专属健怡可乐",
		"item_target_id": "npc_alpha",
		"interaction_trace": {"countInWindow": 3, "stage": "noticed", "heat": 139},
		"performance_plan": {"pattern": "preemptive_gag"},
		"npc_auto_drop": {"countInWindow": 3, "stage": "noticed", "finalAnchor": {"type": "ground"}},
	}
	var event = world["event_log"].record(&"player_drop_item_on_npc", &"diet_coke", &"npc_alpha", &"npc", Vector2i(5, 5), payload)
	var feedback: Dictionary = builder.build_feedback(event, world["npc"], world)
	_assert_equal(str(feedback.get("text", "")).find("脚边") >= 0 or str(feedback.get("text", "")).find("地上") >= 0, true, "auto-drop fallback mentions item put on ground", failures)


func _test_transfer_feedback_changes_with_repetition_stage(failures: Array) -> void:
	var world := _make_world()
	var builder = NPCFeedbackBuilderScript.new()
	builder.configure(world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"])
	var payload := {
		"item_name": "九筒的枪",
		"previousAnchorNpcId": "npc_alpha",
		"previousAnchorNpcName": "Alpha",
		"item_target_id": "npc_beta",
		"item_target_name": "Beta",
		"interaction_trace": {"countInWindow": 4, "stage": "gagged", "heat": 168},
		"performance_plan": {"pattern": "gag_callback"},
	}
	var event = world["event_log"].record(&"player_transfer_item_between_npcs", &"item_gun", &"npc_beta", &"npc", Vector2i(5, 5), payload)
	var target_feedback: Dictionary = builder.build_feedback(event, world["npc_beta"], world)
	_assert_equal(str(target_feedback.get("text", "")).find("又来") >= 0, true, "fourth transfer uses gag callback fallback", failures)


func _test_feedback_prompt_requires_repetition_performance(failures: Array) -> void:
	var world := _make_world()
	var builder = NPCFeedbackBuilderScript.new()
	builder.configure(world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"])
	var payload := {
		"scene_seed": {"visible_topic": "反复塞可乐"},
		"interaction_trace": {"countInWindow": 2, "stage": "repeated", "heat": 103},
		"performance_plan": {"pattern": "leak_cover"},
	}
	var event = world["event_log"].record(&"player_drop_item_on_npc", &"diet_coke", &"npc_alpha", &"npc", Vector2i(5, 5), payload)
	var feedback: Dictionary = builder.build_feedback(event, world["npc"], world)
	var messages: Array = builder._build_feedback_messages(feedback, event, world["npc"])
	var combined := ""
	for message in messages:
		combined += str(message.get("content", ""))
	_assert_equal(combined.contains("countInWindow 大于 1"), true, "feedback prompt requires visible repetition handling", failures)
	_assert_equal(combined.contains("这是第2次"), true, "feedback prompt includes concrete repetition count", failures)
	_assert_equal(combined.contains("pattern=leak_cover"), true, "feedback prompt includes concrete performance pattern", failures)
	_assert_equal(combined.contains("expression palette"), true, "feedback prompt asks for varied expression focus instead of one repeated metaphor", failures)
	_assert_equal(combined.contains("手部动作、面子、账、嫌疑、归属、旁观目光"), true, "feedback prompt provides varied expression focus set", failures)


func _test_transfer_feedback_distinguishes_previous_and_target(failures: Array) -> void:
	var world := _make_world()
	var builder = NPCFeedbackBuilderScript.new()
	builder.configure(world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"])
	var payload := {
		"item_name": "九筒的枪",
		"previousAnchorNpcId": "npc_alpha",
		"previousAnchorNpcName": "Alpha",
		"item_target_id": "npc_beta",
		"item_target_name": "Beta",
	}
	var event = world["event_log"].record(&"player_transfer_item_between_npcs", &"item_gun", &"npc_beta", &"npc", Vector2i(5, 5), payload)
	var previous_feedback: Dictionary = builder.build_feedback(event, world["npc"], world)
	var target_feedback: Dictionary = builder.build_feedback(event, world["npc_beta"], world)
	_assert_equal(str(previous_feedback.get("text", "")).find("递到Beta手里") >= 0, true, "transfer fallback gives previous holder a handoff line", failures)
	_assert_equal(str(target_feedback.get("text", "")).find("接住九筒的枪") >= 0, true, "transfer fallback gives target holder a receiving line", failures)
	_assert_equal(previous_feedback.get("text", "") != target_feedback.get("text", ""), true, "transfer fallback lines are not duplicated", failures)


# set_transport / configure 末参兼容：现有 configure 调用方（不传 transport）行为不变。
func _test_set_transport_does_not_break_existing_configure(failures: Array) -> void:
	var world := _make_world()
	var builder = NPCFeedbackBuilderScript.new()
	# 旧式 5 参 configure 调用（无 transport）必须仍然工作且 transport 保持 null。
	builder.configure(world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"], null)
	_assert_equal(builder.transport, null, "configure without transport leaves transport null", failures)
	_assert_equal(builder.entity_registry, world["entity_registry"], "configure still binds entity_registry", failures)
	_assert_equal(builder.place_registry, world["place_registry"], "configure still binds place_registry", failures)


func _assert_equal(actual: Variant, expected: Variant, message: String, failures: Array) -> void:
	if actual != expected:
		failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
