extends SceneTree

## 联网 live oracle：唯一会真实花钱联网的脚本，且只在项目根 .env 有 OPENROUTER_API_KEY 时跑。
##
## 无 key (LLMConfig.enabled==false) -> 打印 SKIP 并 quit(0)，绝不 FAIL（保 CI 绿）。
## 有 key -> 真实 new LLMTransport（挂 get_root()，因为 HTTPRequest 需要 scene tree），
##          构造最小 world，调 DailyTodoPlanner.request_daily_todos，await 回调，
##          验证拿到的 todos 是 Array 且每个 intent 都在允许集合里。
##          成功 print PASS + quit(0)，失败 push_error + quit(1)。

const PASS_MARKER := "LLM_LIVE_ORACLE: PASS"
const SKIP_MARKER := "LLM_LIVE_ORACLE: SKIP (no OPENROUTER_API_KEY)"
const FAIL_MARKER := "LLM_LIVE_ORACLE: FAIL"

const LLMConfigScript := preload("res://scripts/npc/LLMConfig.gd")
const LLMTransportScript := preload("res://scripts/npc/LLMTransport.gd")
const LLMClientScript := preload("res://scripts/npc/LLMClient.gd")
const DailyTodoPlannerScript := preload("res://scripts/npc/DailyTodoPlanner.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const ItemStateScript := preload("res://scripts/state/ItemState.gd")
const InteractionEventLogScript := preload("res://scripts/world/InteractionEventLog.gd")
const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const WorldPlaceRegistryScript := preload("res://scripts/world/WorldPlaceRegistry.gd")
const GridPathfinderScript := preload("res://scripts/world/GridPathfinder.gd")

const ALLOWED_INTENTS := [&"visit_place", &"talk_to_npc", &"inspect_item", &"wander", &"rest"]
const REQUEST_TIMEOUT_MSEC := 30000


func _initialize() -> void:
	_run()


func _run() -> void:
	var config = LLMConfigScript.load_from_project_root()
	if config == null or not bool(config.enabled):
		print(SKIP_MARKER)
		quit(0)
		return

	# 真实联网路径。LLMTransport 是 Node，HTTPRequest 需要 scene tree。
	# 注意：SceneTree 脚本的 _initialize() 阶段 add_child 是 deferred 的——
	# 必须 await 一帧让 transport 真正进树，否则其子 HTTPRequest is_inside_tree()==false，
	# request() 会返回 ERR_UNCONFIGURED 而静默退化到 fallback wander（掩盖真实联调）。
	var transport = LLMTransportScript.new()
	transport.name = "LLMLiveTransport"
	get_root().add_child(transport)
	await process_frame  # 等 transport（及其子 HTTPRequest）真正进入 scene tree
	transport.configure(config)

	var llm_client = LLMClientScript.new()

	var world := _make_world()
	var npc = world["npc"]

	var planner = DailyTodoPlannerScript.new()
	planner.configure(world["entity_registry"], world["place_registry"], world["pathfinder"], world["event_log"])

	var done := {"called": false, "result": {}}
	planner.request_daily_todos(npc, world, transport, llm_client, func(result: Dictionary) -> void:
		done["called"] = true
		done["result"] = result
	)

	# 轮询等待 transport 的 HTTPRequest 回调（带 wall-clock 超时）。
	var deadline := Time.get_ticks_msec() + REQUEST_TIMEOUT_MSEC
	while not bool(done["called"]) and Time.get_ticks_msec() < deadline:
		await process_frame

	transport.queue_free()

	if not bool(done["called"]):
		push_error("live LLM request timed out after %d ms" % REQUEST_TIMEOUT_MSEC)
		print(FAIL_MARKER)
		quit(1)
		return

	var result: Dictionary = done["result"]
	if not bool(result.get("ok", false)):
		push_error("live LLM request returned not ok: %s" % str(result))
		print(FAIL_MARKER)
		quit(1)
		return

	# 关键：拒绝 fallback 误判。source 必须是 "llm"（真实联调成功），
	# 而非 "fallback"（transport/commit 失败后的兜底 wander）。
	# 没有这条断言，HTTPRequest 静默失败时 fallback wander 会让 oracle 假绿。
	if StringName(result.get("source", "")) != &"llm":
		push_error("live LLM did NOT reach the real OpenRouter path; source=%s (fallback masks failure): %s" % [str(result.get("source", "")), str(result)])
		print(FAIL_MARKER)
		quit(1)
		return

	var todos: Variant = result.get("todos", null)
	if not (todos is Array):
		push_error("live LLM result todos is not an Array: %s" % str(todos))
		print(FAIL_MARKER)
		quit(1)
		return

	for todo in todos:
		var intent := _todo_intent(todo)
		if not ALLOWED_INTENTS.has(intent):
			push_error("live LLM todo has disallowed intent: %s" % str(intent))
			print(FAIL_MARKER)
			quit(1)
			return

	print(PASS_MARKER)
	quit(0)


func _make_world() -> Dictionary:
	var entity_registry = WorldEntityRegistryScript.new()
	entity_registry.set_map_bounds(Rect2i(0, 0, 8, 8))
	var place_registry = WorldPlaceRegistryScript.new()
	var pathfinder = GridPathfinderScript.new()
	pathfinder.set_map_bounds(Rect2i(0, 0, 8, 8))
	var event_log = InteractionEventLogScript.new()

	var npc = NPCStateScript.from_dict({
		"id": "npc_alpha",
		"display_name": "Alpha",
		"personality": "curious explorer",
		"current_cell": {"x": 0, "y": 0},
	})
	var item = ItemStateScript.from_dict({"id": "item_cola", "current_cell": {"x": 1, "y": 0}})
	entity_registry.add_npc(npc)
	entity_registry.add_item(item)

	place_registry.create_place(&"place_clinic", "Clinic", "known valid target place", Rect2i(4, 4, 3, 3), Vector2i(5, 4), [Vector2i(4, 4)], [Vector2i(5, 5)])

	return {
		"entity_registry": entity_registry,
		"place_registry": place_registry,
		"pathfinder": pathfinder,
		"event_log": event_log,
		"npc": npc,
	}


func _todo_intent(todo) -> StringName:
	if todo is Object:
		return StringName(todo.get("intent"))
	if todo is Dictionary:
		return StringName(todo.get("intent", ""))
	return &""
