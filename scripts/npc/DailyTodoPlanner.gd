extends RefCounted
class_name DailyTodoPlanner

const TodoItemScript := preload("res://scripts/state/TodoItem.gd")
const ConfigLoaderScript := preload("res://scripts/config/ConfigLoader.gd")

const ALLOWED_INTENTS := [&"visit_place", &"talk_to_npc", &"inspect_item", &"wander", &"rest"]


var entity_registry = null
var place_registry = null
var default_max_count: int = 5
var planner_config: Dictionary = {}


func configure(p_entity_registry, p_place_registry, _pathfinder = null, _event_log = null) -> void:
	entity_registry = p_entity_registry
	place_registry = p_place_registry
	_load_config()
	default_max_count = int(planner_config.get("defaultMaxCount", default_max_count))


func validate_todos(raw_items: Array, npc = null, p_entity_registry = null, p_place_registry = null, max_count: int = -1) -> Array:
	var effective_entity_registry = p_entity_registry if p_entity_registry != null else entity_registry
	var effective_place_registry = p_place_registry if p_place_registry != null else place_registry
	var limit: int = max_count if max_count >= 0 else default_max_count
	var result: Array = []

	for value in raw_items:
		if limit >= 0 and result.size() >= limit:
			break
		var todo = _coerce_todo(value)
		if todo == null:
			continue
		if not _allowed_intents().has(todo.intent):
			continue
		if not _has_valid_target(todo, effective_entity_registry, effective_place_registry):
			continue
		result.append(todo)

	if result.is_empty() and limit != 0:
		result.append(_fallback_todo(npc))
	return result


func validate_daily_todos(raw_items: Array, npc = null, p_entity_registry = null, p_place_registry = null, max_count: int = -1) -> Array:
	return validate_todos(raw_items, npc, p_entity_registry, p_place_registry, max_count)


func sanitize_todos(raw_items: Array, max_count: int = -1) -> Array:
	return validate_todos(raw_items, null, entity_registry, place_registry, max_count)


func _coerce_todo(value):
	if value is Object and value.has_method("to_dict"):
		return value
	if value is Dictionary:
		var data: Dictionary = value.duplicate(true)
		if not data.has("id") or str(data.get("id", "")).is_empty():
			data["id"] = "todo_%04d" % (randi() % 10000)
		if not data.has("status"):
			data["status"] = "pending"
		return TodoItemScript.from_dict(data)
	return null


func _has_valid_target(todo, p_entity_registry, p_place_registry) -> bool:
	if todo.intent == &"visit_place":
		return p_place_registry != null and p_place_registry.get("places").has(todo.target_place_id)
	if todo.intent == &"talk_to_npc":
		return p_entity_registry != null and p_entity_registry.get("npcs").has(todo.target_npc_id)
	if todo.intent == &"inspect_item":
		return p_entity_registry != null and p_entity_registry.get("items").has(todo.target_item_id)
	return true


func _fallback_todo(npc = null):
	_load_config()
	var fallback_cfg: Dictionary = planner_config.get("fallbackTodo", {})
	var npc_id: StringName = StringName(npc.get("id")) if npc != null and npc is Object else &""
	var values := {
		"npc_id": str(npc_id) if npc_id != &"" else str(fallback_cfg.get("idFallbackNpc", "npc")),
	}
	return TodoItemScript.from_dict({
		"id": _format_template(str(fallback_cfg.get("idTemplate", "todo_{npc_id}_fallback_wander")), values),
		"intent": str(fallback_cfg.get("intent", "wander")),
		"reason": str(fallback_cfg.get("reason", "fallback after invalid daily todo list")),
		"priority": int(fallback_cfg.get("priority", 0)),
		"status": str(fallback_cfg.get("status", "pending")),
	})


## --- LLM wiring (增量) ---------------------------------------------------
## 以下方法把 daily todo 接到真实 LLM，遵守 AI Town 边界:
## LLM 只产出文本/JSON -> LLMClient generation 守卫 -> validate_todos 校验 -> runtime 采纳。
## planner 无副作用: 不直接写 npc.todo_list，校验结果通过 on_done 交给调用方。


## build_prompt: 组 OpenAI 风格 messages (system + user)。
func build_prompt(npc, world: Dictionary) -> Array:
	_load_config()
	var allowed := []
	for intent in _allowed_intents():
		allowed.append(str(intent))
	var prompt_cfg: Dictionary = planner_config.get("prompt", {})

	var npc_id := ""
	var npc_name := ""
	var npc_traits: Variant = {}
	var npc_tags: Variant = []
	var npc_runtime: Variant = {}
	if npc != null and npc is Object:
		npc_id = str(npc.get("id"))
		npc_name = str(npc.get("name"))
		npc_traits = npc.get("traits")
		npc_tags = npc.get("tags")
		if npc.has_method("runtime_dict"):
			npc_runtime = npc.runtime_dict()

	var place_ids := _registry_ids(world.get("place_registry", null), "places")
	var npc_ids := _registry_ids(world.get("entity_registry", null), "npcs")
	var item_ids := _registry_ids(world.get("entity_registry", null), "items")
	var place_summaries := _place_summaries(world.get("place_registry", null))

	var values := {
		"allowed_intents": ", ".join(allowed),
		"json_schema": str(prompt_cfg.get("jsonSchema", "{\"todos\":[]}")),
		"npc_id": npc_id,
		"npc_name": npc_name,
		"npc_traits": JSON.stringify(npc_traits),
		"npc_tags": JSON.stringify(npc_tags),
		"npc_runtime": JSON.stringify(npc_runtime),
		"place_ids": str(place_ids),
		"place_summaries": JSON.stringify(place_summaries),
		"npc_ids": str(npc_ids),
		"item_ids": str(item_ids),
	}
	var system_text := _format_template(str(prompt_cfg.get("systemTemplate", "")), values)
	var user_text := _format_template(str(prompt_cfg.get("userTemplate", "")), values)

	return [
		{"role": "system", "content": system_text},
		{"role": "user", "content": user_text},
	]


## parse_todos_payload: 纯函数。JSON.parse_string -> 取 .todos (顶层数组也兼容) -> raw_items。
## 非法/坏 JSON/无 todos 返回 []。
func parse_todos_payload(json_text: String) -> Array:
	var trimmed := json_text.strip_edges()
	if trimmed.is_empty():
		return []
	# 用实例 JSON.parse (返回 error code) 而非 JSON.parse_string，
	# 后者解析失败时会向引擎日志推 ERROR，污染 headless 测试输出。语义等价。
	var json := JSON.new()
	if json.parse(trimmed) != OK:
		return []
	var parsed: Variant = json.data
	if parsed is Array:
		return parsed
	if parsed is Dictionary:
		var todos: Variant = parsed.get("todos", null)
		if todos is Array:
			return todos
	return []


## request_daily_todos: 发起一次真实 LLM daily todo 请求。
## 流程: start_operation -> transport.request_chat -> complete_operation -> validate_todos -> on_done。
## 失败 (网络/late/非 JSON) 均回退到单个 wander todo。无副作用: 不写 npc.todo_list。
func request_daily_todos(npc, world: Dictionary, transport, llm_client, on_done: Callable) -> void:
	var npc_id := _npc_id_name(npc)
	var op: Dictionary = llm_client.start_operation(npc_id, &"daily_todo")
	var op_id: StringName = StringName(op.get("operation_id", op.get("id", "")))

	var messages := build_prompt(npc, world)
	# should_dispatch: 在队列真正 dispatch 这次请求前调用。若此 op 已被同 (npc, daily_todo)
	# 的更新 generation 取代（current_operation_ids 不再指向 op_id），返回 false，
	# transport 跳过真实网络调用（省钱），回 superseded。LLMClient 的 current_operation_ids
	# 是 public，无需修改 LLMClient。
	var op_key := "%s::%s" % [str(npc_id), "daily_todo"]
	var still_current := func() -> bool:
		var current = llm_client.current_operation_ids.get(op_key, &"")
		return StringName(current) == op_id
	var opts := {"stream": false, "json": true, "kind": &"daily_todo", "should_dispatch": still_current}

	transport.request_chat(messages, opts, func(result: Dictionary) -> void:
		if not bool(result.get("ok", false)):
			# transport 层因新请求取代而跳过（superseded）：等同 late，不注入 wander。
			if str(result.get("error", "")) == "superseded":
				_call_done(on_done, {"ok": false, "status": &"late", "todos": []})
				return
			# 真实失败（无 key / 网络 / 超时）→ 回退到 wander。
			_call_done(on_done, _fallback_result(npc))
			return
		var commit: Dictionary = llm_client.complete_operation(op_id, str(result.get("content", "")))
		if not bool(commit.get("committed", false)):
			# 区分「被新 generation 取代/取消」与「LLM 没产出可用内容」：
			# late / cancelled → 不注入任何 todo（更新的请求会产出真正计划）。
			# invalid_payload（非 JSON）等 → 才回退到 wander。
			var commit_status := StringName(commit.get("status", ""))
			if commit_status == &"late" or commit_status == &"cancelled":
				_call_done(on_done, {"ok": false, "status": commit_status, "todos": []})
				return
			_call_done(on_done, _fallback_result(npc))
			return
		var raw := parse_todos_payload(str(commit.get("text", "")))
		var validated := validate_todos(raw, npc, world.get("entity_registry", null), world.get("place_registry", null), default_max_count)
		# source="llm"：todos 来自真实 LLM 响应（经 validate_todos 校验）。
		# 注意 validate_todos 对空/全非法输入也会补一个 wander，但 source 仍是 llm，
		# 用于和 transport/commit 失败的 source="fallback" 区分（live oracle 据此确认走了真实路径）。
		_call_done(on_done, {"ok": true, "source": &"llm", "todos": validated})
	)


func _fallback_result(npc) -> Dictionary:
	# source="fallback"：transport/commit 真实失败（无 key/网络/非 JSON）后的兜底，
	# 不是来自 LLM。live oracle 据此判定未真正联调成功。
	return {"ok": true, "source": &"fallback", "todos": [_fallback_todo(npc)]}


func _npc_id_name(npc) -> StringName:
	if npc != null and npc is Object:
		return StringName(npc.get("id"))
	return &""


func _registry_ids(registry, field: String) -> Array:
	if registry == null:
		return []
	var collection = registry.get(field) if registry is Object else null
	if not (collection is Dictionary):
		return []
	var ids := []
	for key in collection.keys():
		ids.append(str(key))
	return ids


func _place_summaries(registry) -> Array:
	if registry == null:
		return []
	var places = registry.get("places") if registry is Object else null
	if not (places is Dictionary):
		return []
	var result := []
	for key in places.keys():
		var place = places[key]
		result.append({
			"id": str(key),
			"name": str(place.name),
			"description": str(place.description),
		})
	return result


func _call_done(on_done: Callable, payload: Dictionary) -> void:
	if on_done.is_valid():
		on_done.call(payload)


func _load_config() -> void:
	if planner_config.is_empty():
		planner_config = ConfigLoaderScript.load_planner_config()


func _allowed_intents() -> Array:
	_load_config()
	var raw: Array = planner_config.get("allowedIntents", [])
	if raw.is_empty():
		return ALLOWED_INTENTS.duplicate()
	var result: Array[StringName] = []
	for value in raw:
		result.append(StringName(value))
	return result


func _format_template(template: String, values: Dictionary) -> String:
	var result := template
	for key in values.keys():
		result = result.replace("{%s}" % str(key), str(values[key]))
	return result
