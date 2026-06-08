extends RefCounted
class_name NPCPerformanceDirector


var llm_client = null
var transport = null
var config: Dictionary = {}


func configure(p_config: Dictionary = {}, p_llm_client = null, p_transport = null) -> void:
	config = p_config.duplicate(true)
	llm_client = p_llm_client
	transport = p_transport


func request_plan(judgement: Dictionary, npc, item, on_done: Callable) -> void:
	if judgement.is_empty():
		_emit_done(on_done, {})
		return
	if not _can_stream():
		_emit_done(on_done, _fallback_plan(judgement, npc, item))
		return
	var npc_id := StringName(judgement.get("npcId", _field(npc, "id", "")))
	var op: Dictionary = llm_client.start_operation(npc_id, &"performance")
	var op_id := StringName(op.get("operation_id", op.get("id", "")))
	var messages := _build_messages(judgement, npc, item)
	transport.request_chat(messages, {"stream": false, "json": true, "kind": &"performance"}, func(response: Dictionary) -> void:
		if not bool(response.get("ok", false)):
			_emit_done(on_done, _fallback_plan(judgement, npc, item))
			return
		var commit: Dictionary = llm_client.complete_operation(op_id, str(response.get("content", "")))
		if not bool(commit.get("committed", false)):
			_emit_done(on_done, _fallback_plan(judgement, npc, item))
			return
		var parsed := _parse_json_object(str(commit.get("text", "")))
		var sanitized := sanitize_plan(parsed, judgement)
		if sanitized.is_empty():
			sanitized = _fallback_plan(judgement, npc, item)
		_emit_done(on_done, sanitized)
	)


func sanitize_plan(plan: Dictionary, judgement: Dictionary) -> Dictionary:
	if plan.is_empty():
		return {}
	var action_catalog: Dictionary = config.get("actionCatalog", {})
	var expression_catalog: Dictionary = config.get("expressionCatalog", {})
	var result := str(judgement.get("result", "neutral"))
	var pattern := str(plan.get("pattern", _pattern_for_result(result)))
	var steps: Array = []
	var speech_count := 0
	var raw_steps: Variant = plan.get("steps", [])
	if raw_steps is Array:
		for raw_step in raw_steps:
			if not (raw_step is Dictionary):
				continue
			var step := _sanitize_step(raw_step, action_catalog, expression_catalog)
			if step.is_empty():
				continue
			if str(step.get("channel", "")) == "speech":
				speech_count += 1
				if speech_count > 2:
					continue
			steps.append(step)
			if steps.size() >= 6:
				break
	if steps.is_empty():
		return {}
	return {
		"pattern": pattern,
		"steps": steps,
		"source": "llm",
		"lockedResult": result,
		"lockedReason": str(judgement.get("reason", "")),
	}


func render_plan(plan: Dictionary, judgement: Dictionary = {}, include_labels: bool = true) -> String:
	var parts := PackedStringArray()
	var tag := str(judgement.get("resultLabel", ""))
	if include_labels and not tag.is_empty():
		parts.append("[%s]" % tag)
	for step in plan.get("steps", []):
		if not (step is Dictionary):
			continue
		var channel := str(step.get("channel", ""))
		if channel == "speech":
			var line := str(step.get("line", "")).strip_edges()
			if not line.is_empty():
				parts.append(line)
			continue
		if not include_labels:
			continue
		var label := _step_label(step)
		if not label.is_empty():
			parts.append("[%s]" % label)
	return " ".join(parts)


func _build_messages(judgement: Dictionary, npc, item) -> Array:
	var perf_cfg: Dictionary = config.get("performance", {})
	var prompt_cfg: Dictionary = perf_cfg.get("prompt", {})
	var system_text := str(prompt_cfg.get("systemTemplate", ""))
	var user_template := str(prompt_cfg.get("userTemplate", ""))
	var npc_payload := {
		"id": str(_field(npc, "id", judgement.get("npcId", ""))),
		"name": str(_field(npc, "name", judgement.get("npcId", ""))),
	}
	var object_payload := {}
	if item != null:
		object_payload = {"id": str(_field(item, "id", "")), "name": str(_field(item, "name", ""))}
	var replacements := {
		"result": str(judgement.get("result", "neutral")),
		"reason": str(judgement.get("reason", "unmatched_need")),
		"npc": JSON.stringify(npc_payload),
		"problem": str(judgement.get("problem", "")),
		"object": JSON.stringify(object_payload),
		"npc_style": JSON.stringify(_field(npc, "style", {})),
		"action_catalog": JSON.stringify(config.get("actionCatalog", {})),
		"expression_catalog": JSON.stringify(config.get("expressionCatalog", {})),
	}
	return [
		{"role": "system", "content": system_text},
		{"role": "user", "content": _format_template(user_template, replacements)},
	]


func _sanitize_step(step: Dictionary, action_catalog: Dictionary, expression_catalog: Dictionary) -> Dictionary:
	var channel := str(step.get("channel", ""))
	if not ["body", "face", "gaze", "speech", "silence", "icon"].has(channel):
		return {}
	var result := {"channel": channel, "delayMs": max(0, int(step.get("delayMs", 0)))}
	var action_id := str(step.get("actionId", step.get("action", "")))
	if not action_id.is_empty():
		if not action_catalog.has(action_id):
			return {}
		result["actionId"] = action_id
	var expression_id := str(step.get("expressionId", step.get("expression", "")))
	if not expression_id.is_empty():
		if not expression_catalog.has(expression_id):
			return {}
		result["expressionId"] = expression_id
	var line := str(step.get("line", "")).strip_edges()
	if channel == "speech":
		if line.is_empty():
			return {}
		result["line"] = line
	elif result.size() <= 2:
		return {}
	return result


func _fallback_plan(judgement: Dictionary, npc, item) -> Dictionary:
	var result := str(judgement.get("result", "neutral"))
	var action_catalog: Dictionary = config.get("actionCatalog", {})
	var expression_catalog: Dictionary = config.get("expressionCatalog", {})
	var action_id := _first_existing_action(_fallback_action_candidates(result, npc), action_catalog)
	var expression_id := _first_existing_expression(_fallback_expression_candidates(result), expression_catalog)
	var steps: Array = []
	if not action_id.is_empty():
		steps.append({"channel": "body", "actionId": action_id, "delayMs": 0})
	if not expression_id.is_empty():
		steps.append({"channel": "face", "expressionId": expression_id, "delayMs": 160})
	var line := _fallback_line(result)
	if not line.is_empty():
		steps.append({"channel": "speech", "line": line, "delayMs": 320})
	return {
		"pattern": _pattern_for_result(result),
		"steps": steps,
		"source": "fallback",
		"lockedResult": result,
		"lockedReason": str(judgement.get("reason", "")),
	}


func _fallback_action_candidates(result: String, npc) -> Array:
	var performance_cfg: Dictionary = config.get("performance", {})
	var style_fields: Array = performance_cfg.get("styleActionFields", {}).get(result, [])
	var style: Dictionary = _field(npc, "style", {})
	var candidates: Array = []
	for field_name in style_fields:
		candidates.append_array(_array_from(style.get(str(field_name), [])))
	candidates.append_array(_array_from(performance_cfg.get("fallbackActions", {}).get(result, [])))
	return candidates


func _fallback_expression_candidates(result: String) -> Array:
	return _array_from(config.get("performance", {}).get("fallbackExpressions", {}).get(result, []))


func _first_existing_action(candidates: Array, catalog: Dictionary) -> String:
	for value in candidates:
		var id := str(value)
		if catalog.has(id):
			return id
	return ""


func _first_existing_expression(candidates: Array, catalog: Dictionary) -> String:
	for value in candidates:
		var id := str(value)
		if catalog.has(id):
			return id
	return ""


func _fallback_line(result: String) -> String:
	var line_cfg: Dictionary = config.get("performance", {}).get("fallbackLine", {})
	return str(line_cfg.get(result, ""))


func _pattern_for_result(result: String) -> String:
	var patterns: Dictionary = config.get("performance", {}).get("patterns", {})
	return str(patterns.get(result, patterns.get("neutral", "neutral_reaction")))


func _step_label(step: Dictionary) -> String:
	var action_id := str(step.get("actionId", ""))
	if not action_id.is_empty():
		var action: Dictionary = config.get("actionCatalog", {}).get(action_id, {})
		return str(action.get("label", action_id))
	var expression_id := str(step.get("expressionId", ""))
	if not expression_id.is_empty():
		var expression: Dictionary = config.get("expressionCatalog", {}).get(expression_id, {})
		return str(expression.get("label", expression_id))
	return ""


func _can_stream() -> bool:
	if transport == null or llm_client == null:
		return false
	if not transport.has_method("request_chat") or not llm_client.has_method("start_operation"):
		return false
	if transport.has_method("_is_enabled"):
		return bool(transport._is_enabled())
	return false


func _parse_json_object(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text.strip_edges()) != OK:
		return {}
	var parsed: Variant = json.data
	return parsed if parsed is Dictionary else {}


func _format_template(template: String, values: Dictionary) -> String:
	var result := template
	for key in values.keys():
		result = result.replace("{%s}" % str(key), str(values[key]))
	return result


func _field(value, name: String, fallback = null) -> Variant:
	if value is Dictionary:
		return value.get(name, fallback)
	if value != null and value is Object:
		var field_value: Variant = value.get(name)
		return fallback if field_value == null else field_value
	return fallback


func _array_from(value: Variant) -> Array:
	return value.duplicate(true) if value is Array else []


func _emit_done(on_done: Callable, payload: Dictionary) -> void:
	if on_done.is_valid():
		on_done.call(payload)
