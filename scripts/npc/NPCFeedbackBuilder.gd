extends RefCounted
class_name NPCFeedbackBuilder

const ConfigLoaderScript := preload("res://scripts/config/ConfigLoader.gd")

var entity_registry = null
var place_registry = null
var event_log = null
var llm_client = null
var transport = null  # LLMTransport（Node），可选，由 set_transport 或 configure 末参注入
var feedback_config: Dictionary = {}


func configure(p_entity_registry, p_place_registry, _pathfinder = null, p_event_log = null, p_llm_client = null, p_transport = null) -> void:
	entity_registry = p_entity_registry
	place_registry = p_place_registry
	event_log = p_event_log
	llm_client = p_llm_client
	_load_config()
	if p_transport != null:
		transport = p_transport


## 单独的 transport 注入途径，保持现有 configure 调用方行为不变。
func set_transport(p_transport) -> void:
	transport = p_transport


func build_feedback(event, npc = null, world_context: Dictionary = {}) -> Dictionary:
	if event == null:
		return {"ok": false, "reason": &"missing_event"}
	var event_id := StringName(_field(event, "id", ""))
	var npc_id := _resolve_npc_id(event, npc)
	var context := _local_context(event, npc, world_context)
	var text := _feedback_text(event, npc_id, context)
	return {
		"ok": true,
		"event_id": event_id,
		"npc_id": npc_id,
		"text": text,
		"context": context,
		"chunks": [text],
	}


func begin_feedback_stream(event, npc = null, world_context: Dictionary = {}) -> Dictionary:
	var feedback := build_feedback(event, npc, world_context)
	if not bool(feedback.get("ok", false)) or llm_client == null or not llm_client.has_method("start_operation"):
		return feedback
	var operation: Dictionary = llm_client.start_operation(StringName(feedback.get("npc_id", "")), &"feedback")
	feedback["operation"] = operation
	feedback["operation_id"] = operation.get("operation_id", operation.get("id", &""))
	return feedback


## stream_feedback: 在 build_feedback 的确定性兜底之上，接 transport 做真实流式回填。
##   - transport / llm_client 缺失或 LLM 未启用 → 直接回放兜底文本（不联网）。
##   - 否则 start_operation 拿 operation，transport.request_chat 一次性 content，
##     切块经 append_stream_chunk 守卫 + on_chunk 回放，complete_operation 收尾。
##   - late generation：complete_operation 返回 committed=false 时不覆盖 UI（依赖 LLMClient 的 _is_current_operation）。
## on_chunk: Callable(chunk: String)
## on_done: Callable(result: Dictionary)
func stream_feedback(event, npc, world_context: Dictionary, on_chunk: Callable, on_done: Callable) -> void:
	var feedback := build_feedback(event, npc, world_context)

	# 兜底路径：未配置 transport / llm_client 或 LLM 未启用 → 走确定性文本，不联网。
	if not _can_stream() or not bool(feedback.get("ok", false)):
		_emit_chunk(on_chunk, str(feedback.get("text", "")))
		_emit_done(on_done, feedback)
		return

	var npc_id := StringName(feedback.get("npc_id", ""))
	var operation: Dictionary = llm_client.start_operation(npc_id, &"feedback")
	var op_id := StringName(operation.get("operation_id", operation.get("id", &"")))
	feedback["operation"] = operation
	feedback["operation_id"] = op_id

	var messages := _build_feedback_messages(feedback, event, npc)
	var opts := {"stream": true, "json": false, "kind": &"feedback"}

	transport.request_chat(messages, opts, func(response: Dictionary) -> void:
		_handle_transport_response(response, feedback, op_id, on_chunk, on_done)
	)


func _handle_transport_response(response: Dictionary, feedback: Dictionary, op_id: StringName, on_chunk: Callable, on_done: Callable) -> void:
	var fallback_text := str(feedback.get("text", ""))

	# 网络/状态错误 → 兜底确定性文本。
	if not bool(response.get("ok", false)):
		var failed := feedback.duplicate(true)
		failed["streamed"] = false
		failed["error"] = StringName(response.get("error", &"transport_error"))
		_emit_chunk(on_chunk, fallback_text)
		_emit_done(on_done, failed)
		return

	var content := str(response.get("content", ""))
	if content.strip_edges().is_empty():
		content = fallback_text

	# MVP：一次性 content 当作单块流式回填。append_stream_chunk 的守卫负责丢弃 late/cancelled。
	var accepted_buffer := ""
	if llm_client != null and llm_client.has_method("append_stream_chunk"):
		var chunk_result: Dictionary = llm_client.append_stream_chunk(op_id, content)
		if bool(chunk_result.get("accepted", false)):
			accepted_buffer = str(chunk_result.get("buffer", content))
			_emit_chunk(on_chunk, content)
		else:
			# late/cancelled：不回放到 UI，直接收尾（不覆盖当前 operation）。
			var stale := feedback.duplicate(true)
			stale["streamed"] = false
			stale["status"] = StringName(chunk_result.get("status", &"late"))
			_emit_done(on_done, stale)
			return
	else:
		_emit_chunk(on_chunk, content)

	var done := feedback.duplicate(true)
	if llm_client != null and llm_client.has_method("complete_operation"):
		# 空 final_text → LLMClient 用累积 buffer。
		var commit: Dictionary = llm_client.complete_operation(op_id, "")
		done["committed"] = bool(commit.get("committed", false))
		done["status"] = StringName(commit.get("status", &""))
		if bool(commit.get("committed", false)):
			# commit 成功：以 LLM 文本为准更新结果。
			var committed_text := str(commit.get("text", accepted_buffer))
			done["text"] = committed_text
			done["chunks"] = [committed_text]
			done["streamed"] = true
		else:
			# late generation / invalid payload：不覆盖 UI，保留兜底文本。
			done["streamed"] = false
	else:
		done["text"] = content
		done["chunks"] = [content]
		done["streamed"] = true

	_emit_done(on_done, done)


func _can_stream() -> bool:
	if transport == null or llm_client == null:
		return false
	if not transport.has_method("request_chat"):
		return false
	if not llm_client.has_method("start_operation"):
		return false
	# transport 暴露 _is_enabled 时用它做 LLM 启用判断；取不到则视为未启用（兜底）。
	if transport.has_method("_is_enabled"):
		return bool(transport._is_enabled())
	return false


func _build_feedback_messages(feedback: Dictionary, event, npc) -> Array:
	_load_config()
	var prompt_cfg: Dictionary = feedback_config.get("prompt", {})
	var labels: Dictionary = prompt_cfg.get("labels", {})
	var npc_id := str(feedback.get("npc_id", ""))
	var context: Dictionary = feedback.get("context", {})
	var event_type := str(context.get("event_type", _field(event, "type", "")))
	var place_name := str(context.get("place_name", ""))
	var payload: Dictionary = _field(event, "payload", {})
	var npc_name := str(_field(npc, "name", npc_id))
	var traits = _field(npc, "traits", {})
	var tags = _field(npc, "tags", [])
	var style = _field(npc, "style", {})
	var runtime := _prompt_runtime_payload(npc)
	var scene_seed: Dictionary = payload.get("scene_seed", {}) if payload is Dictionary else {}
	var participant_action := _participant_action_for(payload, npc_id)
	var gift_stance: Dictionary = payload.get("gift_stance", {}) if payload is Dictionary else {}
	var interaction_trace: Dictionary = payload.get("interaction_trace", {}) if payload is Dictionary else {}
	var performance_plan: Dictionary = payload.get("performance_plan", {}) if payload is Dictionary else {}
	var relation_updates: Array = payload.get("relation_memory_updates", []) if payload is Dictionary else []
	var npc_auto_drop: Dictionary = payload.get("npc_auto_drop", {}) if payload is Dictionary else {}

	var user_lines := PackedStringArray()
	user_lines.append("%s: %s" % [str(labels.get("eventType", "event type")), event_type])
	if not place_name.is_empty():
		user_lines.append("%s: %s" % [str(labels.get("placeName", "place name")), place_name])
	var prompt_scene_seed := _prompt_scene_seed(scene_seed)
	if not prompt_scene_seed.is_empty():
		user_lines.append("%s: %s" % [str(labels.get("sceneSeed", "scene seed")), JSON.stringify(prompt_scene_seed)])
	if not participant_action.is_empty():
		user_lines.append("%s: %s" % [str(labels.get("participantAction", "your participant action")), JSON.stringify(participant_action)])
	var gift_attitude_text := _gift_attitude_text(gift_stance)
	if not gift_attitude_text.is_empty():
		user_lines.append("%s: %s" % [str(labels.get("giftAttitude", "gift attitude")), gift_attitude_text])
	if not relation_updates.is_empty():
		user_lines.append("%s: %s" % [str(labels.get("relationMemory", "relation memory")), _relation_memory_text(relation_updates)])
	var standing_memory := _standing_memory_text(npc_id, npc, event)
	if not standing_memory.is_empty():
		user_lines.append("%s: %s" % [str(labels.get("rememberedHistory", "npc remembered history")), standing_memory])
	var auto_drop_fact := _auto_drop_fact_text(npc_auto_drop)
	if not auto_drop_fact.is_empty():
		user_lines.append("%s: %s" % [str(labels.get("worldFact", "world fact")), auto_drop_fact])
	if payload is Dictionary and not payload.is_empty():
		user_lines.append("%s: %s" % [str(labels.get("eventPayload", "event payload")), JSON.stringify(_prompt_event_payload(payload))])
	if traits is Dictionary and not traits.is_empty():
		user_lines.append("%s: %s" % [str(labels.get("traits", "traits")), JSON.stringify(traits)])
	if tags is Array and not tags.is_empty():
		user_lines.append("%s: %s" % [str(labels.get("tags", "tags")), JSON.stringify(tags)])
	if style is Dictionary and not style.is_empty():
		user_lines.append("%s: %s" % [str(labels.get("style", "style")), JSON.stringify(style)])
	if not runtime.is_empty():
		user_lines.append("%s: %s" % [str(labels.get("runtimeState", "runtime state")), JSON.stringify(runtime)])
	var repetition_hint := _repetition_instruction(interaction_trace, performance_plan)
	if not repetition_hint.is_empty():
		user_lines.append("%s: %s" % [str(labels.get("interactionMemory", "interaction memory")), repetition_hint])
	user_lines.append("%s: %s" % [str(labels.get("expressionPalette", "expression palette")), str(prompt_cfg.get("expressionPalette", ""))])

	return [
		{
			"role": "system",
			"content": _format_template(str(prompt_cfg.get("systemTemplate", "")), {"npc_name": npc_name}),
		},
		{
			"role": "user",
			"content": "\n".join(user_lines),
		},
	]


func _emit_chunk(on_chunk: Callable, chunk: String) -> void:
	if on_chunk.is_valid():
		on_chunk.call(chunk)


func _emit_done(on_done: Callable, result: Dictionary) -> void:
	if on_done.is_valid():
		on_done.call(result)


func _resolve_npc_id(event, npc) -> StringName:
	if npc != null:
		return StringName(_field(npc, "id", ""))
	var target_type := StringName(_field(event, "target_type", ""))
	if target_type == &"npc":
		return StringName(_field(event, "target_entity_id", ""))
	return StringName(_field(event, "actor_id", ""))


func _local_context(event, npc, world_context: Dictionary) -> Dictionary:
	var cell: Vector2i = _field(event, "cell", Vector2i(-1, -1))
	var context := {
		"event_type": StringName(_field(event, "type", "")),
		"cell": cell,
		"place_id": &"",
		"place_name": "",
	}
	var effective_place_registry = world_context.get("place_registry", place_registry)
	if effective_place_registry != null and effective_place_registry.has_method("get_place_at_cell"):
		var place = effective_place_registry.get_place_at_cell(cell)
		if place != null:
			context["place_id"] = place.id
			context["place_name"] = place.name
	return context


func _feedback_text(event, npc_id: StringName, context: Dictionary) -> String:
	var event_type := StringName(_field(event, "type", ""))
	var payload: Dictionary = _field(event, "payload", {})
	var scene_seed: Dictionary = payload.get("scene_seed", {}) if payload is Dictionary else {}
	var title := str(scene_seed.get("title", ""))
	var fallback_cfg: Dictionary = _cfg(["fallbackText"], {})
	if event_type == &"player_forced_drop_item":
		return _template(["fallbackText", "forcedDrop"], {"npc_id": str(npc_id)})
	if event_type == &"player_transfer_item_between_npcs":
		var item_name := str(payload.get("item_name", fallback_cfg.get("genericItemName", ""))) if payload is Dictionary else str(fallback_cfg.get("genericItemName", ""))
		var target_name := str(payload.get("item_target_name", fallback_cfg.get("genericNpcName", ""))) if payload is Dictionary else str(fallback_cfg.get("genericNpcName", ""))
		var target_id := str(payload.get("item_target_id", "")) if payload is Dictionary else ""
		var previous_id := str(payload.get("previousAnchorNpcId", "")) if payload is Dictionary else ""
		var previous_name := str(payload.get("previousAnchorNpcName", fallback_cfg.get("genericNpcName", ""))) if payload is Dictionary else str(fallback_cfg.get("genericNpcName", ""))
		var transfer_repeat := _repeat_fallback_suffix(payload, item_name)
		var relation_suffix := _relation_shift_suffix_for_npc(payload, str(npc_id))
		var values := {"npc_id": str(npc_id), "item_name": item_name, "target_name": target_name, "previous_name": previous_name, "repeat_suffix": "", "relation_suffix": relation_suffix}
		if str(npc_id) == previous_id:
			values["repeat_suffix"] = transfer_repeat.get("previous", _template(["transfer", "defaultSuffix", "previous"]))
			return _template(["transfer", "previous"], values)
		if str(npc_id) == target_id:
			var auto_drop_text := _auto_drop_fallback_text(str(npc_id), item_name, payload)
			if not auto_drop_text.is_empty():
				return "%s%s" % [auto_drop_text, relation_suffix]
			values["repeat_suffix"] = transfer_repeat.get("target", _template(["transfer", "defaultSuffix", "target"], values))
			return _template(["transfer", "target"], values)
		values["repeat_suffix"] = transfer_repeat.get("witness", _template(["transfer", "defaultSuffix", "witness"]))
		return _template(["transfer", "witness"], values)
	if event_type == &"player_drop_item_on_npc":
		var item_name := str(payload.get("item_name", fallback_cfg.get("genericItemName", ""))) if payload is Dictionary else str(fallback_cfg.get("genericItemName", ""))
		var relation_suffix := _relation_shift_suffix_for_npc(payload, str(npc_id))
		var auto_drop_text := _auto_drop_fallback_text(str(npc_id), item_name, payload)
		if not auto_drop_text.is_empty():
			return "%s%s" % [auto_drop_text, relation_suffix]
		return "%s%s" % [_drop_on_npc_repetition_text(str(npc_id), item_name, payload), relation_suffix]
	if event_type == &"player_chat_to_npc":
		var player_message := str(payload.get("player_message", "")) if payload is Dictionary else ""
		if not player_message.is_empty():
			return _template(["fallbackText", "chat"], {"npc_id": str(npc_id), "player_message": player_message})
	if event_type == &"player_chat_reported_item_transfer":
		var item_name := str(payload.get("item_name", fallback_cfg.get("genericItemName", ""))) if payload is Dictionary else str(fallback_cfg.get("genericItemName", ""))
		var giver_name := str(payload.get("previousAnchorNpcName", fallback_cfg.get("genericNpcName", ""))) if payload is Dictionary else str(fallback_cfg.get("genericNpcName", ""))
		return _template(["fallbackText", "reportedTransfer"], {"npc_id": str(npc_id), "giver_name": giver_name, "item_name": item_name, "relation_suffix": _relation_shift_suffix_for_npc(payload, str(npc_id))})
	if event_type == &"player_drag_started_trained_item":
		var item_name := str(payload.get("item_name", fallback_cfg.get("genericItemName", ""))) if payload is Dictionary else str(fallback_cfg.get("genericItemName", ""))
		var tag := str(payload.get("gagTag", "")) if payload is Dictionary else ""
		var line := str(payload.get("scene_seed", {}).get("visible_topic", "")) if payload is Dictionary else ""
		if not tag.is_empty():
			return _template(["fallbackText", "preemptiveTagged"], {"npc_id": str(npc_id), "item_name": item_name, "tag": tag})
		if not line.is_empty():
			return _template(["fallbackText", "preemptiveUntagged"], {"npc_id": str(npc_id), "item_name": item_name})
	if not title.is_empty():
		return _template(["fallbackText", "title"], {"npc_id": str(npc_id), "title": title})
	if not str(context.get("place_name", "")).is_empty():
		return _template(["fallbackText", "place"], {"npc_id": str(npc_id), "place_name": str(context["place_name"])})
	return _template(["fallbackText", "default"], {"npc_id": str(npc_id), "event_type": str(event_type)})


func _auto_drop_fallback_text(npc_label: String, item_name: String, payload: Dictionary) -> String:
	var auto_drop: Dictionary = payload.get("npc_auto_drop", {}) if payload is Dictionary else {}
	if auto_drop.is_empty():
		return ""
	var trace: Dictionary = payload.get("interaction_trace", {}) if payload is Dictionary else {}
	var stage := str(auto_drop.get("stage", trace.get("stage", "new")))
	if stage == "ritualized":
		return _template(["autoDrop", "ritualized"], {"npc_id": npc_label, "item_name": item_name})
	if stage == "gagged":
		return _template(["autoDrop", "gagged"], {"npc_id": npc_label, "item_name": item_name})
	return _template(["autoDrop", "default"], {"npc_id": npc_label, "item_name": item_name})


func _drop_on_npc_repetition_text(npc_label: String, item_name: String, payload: Dictionary) -> String:
	var trace: Dictionary = payload.get("interaction_trace", {}) if payload is Dictionary else {}
	var plan: Dictionary = payload.get("performance_plan", {}) if payload is Dictionary else {}
	var stage := str(trace.get("stage", "new"))
	var pattern := str(plan.get("pattern", "single_reaction"))
	if stage == "ritualized" or pattern == "ritualized_gag":
		return _template(["dropOnNpc", "ritualized"], {"npc_id": npc_label, "item_name": item_name})
	if stage == "gagged" or pattern == "gag_callback":
		return _template(["dropOnNpc", "gagged"], {"npc_id": npc_label, "item_name": item_name})
	if stage == "noticed" or pattern == "preemptive_gag":
		return _template(["dropOnNpc", "noticed"], {"npc_id": npc_label, "item_name": item_name})
	if stage == "repeated" or pattern == "leak_cover":
		return _template(["dropOnNpc", "repeated"], {"npc_id": npc_label, "item_name": item_name})
	return _template(["dropOnNpc", "default"], {"npc_id": npc_label, "item_name": item_name})


func _repeat_fallback_suffix(payload: Dictionary, item_name: String) -> Dictionary:
	var trace: Dictionary = payload.get("interaction_trace", {}) if payload is Dictionary else {}
	var plan: Dictionary = payload.get("performance_plan", {}) if payload is Dictionary else {}
	var stage := str(trace.get("stage", "new"))
	var pattern := str(plan.get("pattern", "single_reaction"))
	var stage_key := _stage_key_from_trace(stage, pattern)
	if not stage_key.is_empty():
		var suffixes: Dictionary = _cfg(["repeatSuffix", stage_key], {})
		var values := {"item_name": item_name}
		return {
			"previous": _format_template(str(suffixes.get("previous", "")), values),
			"target": _format_template(str(suffixes.get("target", "")), values),
			"witness": _format_template(str(suffixes.get("witness", "")), values),
		}
	return {}


func _stage_key_from_trace(stage: String, pattern: String) -> String:
	var pattern_map: Dictionary = _cfg(["stagePatternMap"], {})
	if stage in ["repeated", "noticed", "gagged", "ritualized"]:
		return stage
	return str(pattern_map.get(pattern, ""))


func _relation_shift_suffix_for_npc(payload: Dictionary, npc_id: String) -> String:
	if not (payload is Dictionary):
		return ""
	var updates: Variant = payload.get("relation_memory_updates", [])
	if not (updates is Array):
		return ""
	var shift_cfg: Dictionary = _cfg(["relationShift"], {})
	var fragments: Dictionary = shift_cfg.get("fragments", {})
	var parts := PackedStringArray()
	for update in updates:
		if not (update is Dictionary) or str(update.get("fromNpcId", "")) != npc_id:
			continue
		var to_name := _payload_npc_display_name(payload, str(update.get("toNpcId", "")))
		var warmth := int(update.get("warmth", 0))
		var debt := int(update.get("debt", 0))
		var awkward := int(update.get("awkward", 0))
		var suspicion := int(update.get("suspicion", 0))
		var fun := int(update.get("fun", 0))
		if warmth > 0:
			parts.append(_format_template(str(fragments.get("warmth", "")), {"to_name": to_name}))
		if debt > 0:
			parts.append(_format_template(str(fragments.get("debt", "")), {"to_name": to_name}))
		if awkward > 0:
			parts.append(_format_template(str(fragments.get("awkward", "")), {"to_name": to_name}))
		if suspicion > 0:
			parts.append(_format_template(str(fragments.get("suspicion", "")), {"to_name": to_name}))
		if fun > 0:
			parts.append(_format_template(str(fragments.get("fun", "")), {"to_name": to_name}))
		break
	if parts.is_empty():
		return ""
	var visible := PackedStringArray()
	for index in range(min(int(shift_cfg.get("maxParts", 2)), parts.size())):
		visible.append(parts[index])
	return str(shift_cfg.get("prefix", "，")) + str(shift_cfg.get("joiner", "，")).join(visible)


func _payload_npc_display_name(payload: Dictionary, npc_id: String) -> String:
	var payload_name_keys := {
		str(payload.get("previousAnchorNpcId", "")): "previousAnchorNpcName",
		str(payload.get("item_target_id", "")): "item_target_name",
		str(payload.get("target_npc_id", "")): "target_npc_name",
		str(payload.get("primary_npc_id", "")): "primary_npc_name",
	}
	var name_key := str(payload_name_keys.get(npc_id, ""))
	if not name_key.is_empty():
		var payload_name := str(payload.get(name_key, ""))
		if not payload_name.is_empty():
			return payload_name
	return _npc_display_name(npc_id)


func _prompt_event_payload(payload: Dictionary) -> Dictionary:
	var clean := payload.duplicate(true)
	for key in _cfg(["prompt", "eventPayloadScrubKeys"], ["interaction_trace", "gift_trace", "gift_context", "gift_stance", "performance_plan", "interaction_delta", "object_memory", "relation_memory_updates", "npc_auto_drop", "bodyGagId", "gagTag", "gagAction", "preemptiveLine", "stage"]):
		clean.erase(key)
	if clean.has("scene_seed") and clean["scene_seed"] is Dictionary:
		clean["scene_seed"] = _prompt_scene_seed(clean["scene_seed"])
	return clean


func _prompt_scene_seed(scene_seed: Dictionary) -> Dictionary:
	var clean := {}
	for key in _cfg(["prompt", "sceneSeedPromptKeys"], ["title", "trigger_action", "visible_topic", "object_social_state"]):
		if scene_seed.has(key):
			clean[key] = scene_seed[key]
	return clean


func _gift_attitude_text(stance: Dictionary) -> String:
	if stance.is_empty():
		return ""
	var result := str(stance.get("result", stance.get("legacyResult", "ambivalent")))
	var like := int(stance.get("like", stance.get("want", 0)))
	var reject := int(stance.get("reject", 0))
	var pressure := int(stance.get("pressure", 0))
	var fatigue := int(stance.get("fatigue", 0))
	var reason := _gift_reason_text(str(stance.get("dominantReason", "")))
	var attitude_cfg: Dictionary = _cfg(["giftAttitude"], {})
	var result_text: Dictionary = attitude_cfg.get("resultText", {})
	var parts := PackedStringArray()
	parts.append(str(result_text.get(result, result_text.get("ambivalent", ""))))
	if not reason.is_empty():
		parts.append(_template(["giftAttitude", "reasonTemplate"], {"reason": reason}))
	var balance := _gift_balance_text(like, reject)
	if not balance.is_empty():
		parts.append(balance)
	var pressure_text := _gift_pressure_text(pressure, fatigue)
	if not pressure_text.is_empty():
		parts.append(pressure_text)
	return "；".join(parts)


func _gift_reason_text(reason: String) -> String:
	var reason_text: Dictionary = _cfg(["giftAttitude", "reasonText"], {})
	return str(reason_text.get(reason, ""))


func _gift_balance_text(like: int, reject: int) -> String:
	var balance_cfg: Dictionary = _cfg(["giftAttitude", "balance"], {})
	var gap := like - reject
	if balance_cfg.has("likeGap") and gap >= int(balance_cfg.get("likeGap", 0)):
		return str(balance_cfg.get("likeText", ""))
	if balance_cfg.has("rejectGap") and gap <= int(balance_cfg.get("rejectGap", 0)):
		return str(balance_cfg.get("rejectText", ""))
	if balance_cfg.has("closeGapAbs") and abs(gap) <= int(balance_cfg.get("closeGapAbs", 0)):
		return str(balance_cfg.get("closeText", ""))
	return ""


func _gift_pressure_text(pressure: int, fatigue: int) -> String:
	var pressure_cfg: Dictionary = _cfg(["giftAttitude", "pressure"], {})
	var parts := PackedStringArray()
	if pressure_cfg.has("high") and pressure >= int(pressure_cfg.get("high", 0)):
		parts.append(str(pressure_cfg.get("highText", "")))
	elif pressure_cfg.has("visible") and pressure >= int(pressure_cfg.get("visible", 0)):
		parts.append(str(pressure_cfg.get("visibleText", "")))
	if pressure_cfg.has("fatigueHigh") and fatigue >= int(pressure_cfg.get("fatigueHigh", 0)):
		parts.append(str(pressure_cfg.get("fatigueHighText", "")))
	elif pressure_cfg.has("fatigueVisible") and fatigue >= int(pressure_cfg.get("fatigueVisible", 0)):
		parts.append(str(pressure_cfg.get("fatigueVisibleText", "")))
	return "，".join(parts)


func _relation_memory_text(relation_updates: Array) -> String:
	var parts := PackedStringArray()
	var tones_cfg: Dictionary = _cfg(["relationMemory", "tones"], {})
	for update in relation_updates:
		if not (update is Dictionary):
			continue
		var from_id := str(update.get("fromNpcId", ""))
		var to_id := str(update.get("toNpcId", ""))
		if from_id.is_empty() or to_id.is_empty():
			continue
		var from_name := _npc_display_name(from_id)
		var to_name := _npc_display_name(to_id)
		var tones := PackedStringArray()
		if int(update.get("warmth", 0)) > 0:
			tones.append(str(tones_cfg.get("warmth", "")))
		if int(update.get("awkward", 0)) > 0:
			tones.append(str(tones_cfg.get("awkward", "")))
		if int(update.get("suspicion", 0)) > 0:
			tones.append(str(tones_cfg.get("suspicion", "")))
		if int(update.get("debt", 0)) > 0:
			tones.append(str(tones_cfg.get("debt", "")))
		if int(update.get("fun", 0)) > 0:
			tones.append(str(tones_cfg.get("fun", "")))
		var tone_text := str(_cfg(["relationMemory", "defaultTone"], "")) if tones.is_empty() else "、".join(tones)
		parts.append(_template(["relationMemory", "lineTemplate"], {"from_name": from_name, "to_name": to_name, "tone_text": tone_text}))
	return "；".join(parts)


func _prompt_auto_drop_payload(auto_drop: Dictionary) -> Dictionary:
	if auto_drop.is_empty():
		return {}
	return {
		"npc_name": auto_drop.get("npc_name", ""),
		"item_name": auto_drop.get("item_name", ""),
		"reason": auto_drop.get("reason", ""),
		"finalAnchor": auto_drop.get("finalAnchor", {}),
	}


func _auto_drop_fact_text(auto_drop: Dictionary) -> String:
	if auto_drop.is_empty():
		return ""
	var fallback_cfg: Dictionary = _cfg(["fallbackText"], {})
	var npc_name := str(auto_drop.get("npc_name", auto_drop.get("npc_id", fallback_cfg.get("genericNpcName", ""))))
	var item_name := str(auto_drop.get("item_name", fallback_cfg.get("genericItemName", "")))
	var final_anchor: Dictionary = auto_drop.get("finalAnchor", {})
	if str(final_anchor.get("type", "")) == "ground":
		return _template(["autoDropFact", "ground"], {"npc_name": npc_name, "item_name": item_name})
	return _template(["autoDropFact", "default"], {"npc_name": npc_name, "item_name": item_name})


func _standing_memory_text(npc_id: String, npc, current_event) -> String:
	var parts := PackedStringArray()
	var remembered := _recent_event_memory_text(npc, current_event)
	if not remembered.is_empty():
		parts.append(remembered)
	var relations := _standing_relation_memory_text(npc_id)
	if not relations.is_empty():
		parts.append(relations)
	return "；".join(parts)


func _recent_event_memory_text(npc, current_event) -> String:
	var raw_events: Variant = _field(npc, "recent_events", [])
	if not (raw_events is Array):
		return ""
	var current_id := StringName(_field(current_event, "id", &""))
	var lines := PackedStringArray()
	var start_index = max(0, raw_events.size() - 8)
	for index in range(start_index, raw_events.size()):
		var remembered = raw_events[index]
		if remembered == null or StringName(_field(remembered, "id", &"")) == current_id:
			continue
		var text := _memory_event_text(remembered)
		if text.is_empty() or lines.has(text):
			continue
		lines.append(text)
		if lines.size() >= 5:
			break
	return "；".join(lines)


func _memory_event_text(event) -> String:
	var event_type := StringName(_field(event, "type", &""))
	var payload: Dictionary = _field(event, "payload", {})
	var fallback_cfg: Dictionary = _cfg(["fallbackText"], {})
	if event_type == &"player_chat_to_npc":
		var message := str(payload.get("player_message", "")).strip_edges()
		return _template(["rememberedEvent", "chat"], {"message": message}) if not message.is_empty() else ""
	if event_type == &"player_chat_reported_item_transfer":
		var message := str(payload.get("player_message", "")).strip_edges()
		var item_name := str(payload.get("item_name", fallback_cfg.get("genericItemName", "")))
		var from_name := str(payload.get("previousAnchorNpcName", payload.get("item_owner_name", fallback_cfg.get("genericNpcName", ""))))
		var to_name := str(payload.get("item_target_name", fallback_cfg.get("genericNpcName", "")))
		var key := "reportedTransferWithMessage" if not message.is_empty() else "reportedTransfer"
		return _template(["rememberedEvent", key], {"message": message, "item_name": item_name, "from_name": from_name, "to_name": to_name})
	if event_type == &"npc_feedback_line":
		var speaker := str(payload.get("speakerName", fallback_cfg.get("genericNpcName", "")))
		var text := str(payload.get("text", "")).strip_edges()
		return _template(["rememberedEvent", "npcReply"], {"speaker": speaker, "text": text}) if not text.is_empty() else ""
	if event_type == &"player_drop_item_on_npc" or event_type == &"player_transfer_item_between_npcs":
		var item_name := str(payload.get("item_name", _field(event, "primary_entity_id", fallback_cfg.get("genericItemName", ""))))
		var target_name := str(payload.get("item_target_name", _field(event, "target_entity_id", fallback_cfg.get("genericNpcName", ""))))
		var previous_name := str(payload.get("previousAnchorNpcName", ""))
		if not previous_name.is_empty():
			return _template(["rememberedEvent", "itemTransfer"], {"item_name": item_name, "previous_name": previous_name, "target_name": target_name})
		return _template(["rememberedEvent", "itemDrop"], {"item_name": item_name, "target_name": target_name})
	if event_type == &"player_drag_started_trained_item":
		var item_name := str(payload.get("item_name", _field(event, "primary_entity_id", fallback_cfg.get("genericItemName", ""))))
		return _template(["rememberedEvent", "preemptive"], {"item_name": item_name})
	if event_type == &"player_forced_drop_item":
		return _template(["rememberedEvent", "forcedDrop"])
	return ""


func _standing_relation_memory_text(npc_id: String) -> String:
	if entity_registry == null:
		return ""
	var memories: Variant = entity_registry.get("relation_memories") if entity_registry is Object else {}
	if not (memories is Dictionary):
		return ""
	var lines := PackedStringArray()
	var standing_cfg: Dictionary = _cfg(["relationMemory"], {})
	var standing_tones: Dictionary = standing_cfg.get("standingTones", {})
	var threshold := int(standing_cfg.get("standingThreshold", 4))
	for memory in memories.values():
		if not (memory is Dictionary) or str(memory.get("fromNpcId", "")) != npc_id:
			continue
		var to_id := str(memory.get("toNpcId", ""))
		var to_name := _npc_display_name(to_id)
		var tones := PackedStringArray()
		if int(memory.get("warmth", 0)) >= threshold:
			tones.append(str(standing_tones.get("warmth", "")))
		if int(memory.get("awkward", 0)) >= threshold:
			tones.append(str(standing_tones.get("awkward", "")))
		if int(memory.get("suspicion", 0)) >= threshold:
			tones.append(str(standing_tones.get("suspicion", "")))
		if int(memory.get("debt", 0)) >= threshold:
			tones.append(str(standing_tones.get("debt", "")))
		if int(memory.get("fun", 0)) >= threshold:
			tones.append(str(standing_tones.get("fun", "")))
		if not tones.is_empty():
			lines.append(_template(["relationMemory", "standingTemplate"], {"to_name": to_name, "tone_text": "、".join(tones)}))
		if lines.size() >= 3:
			break
	return "；".join(lines)


func _npc_display_name(npc_id: String) -> String:
	if entity_registry != null:
		var npcs: Variant = entity_registry.get("npcs") if entity_registry is Object else {}
		if npcs is Dictionary and npcs.has(StringName(npc_id)):
			return str(npcs[StringName(npc_id)].name)
		if npcs is Dictionary and npcs.has(npc_id):
			return str(npcs[npc_id].name)
	return npc_id


func _repetition_instruction(interaction_trace: Dictionary, performance_plan: Dictionary) -> String:
	var stage := str(interaction_trace.get("stage", "new"))
	var _pattern := str(performance_plan.get("pattern", "single_reaction"))
	var heat := int(interaction_trace.get("heat", 0))
	if heat <= 0 and stage == "new":
		return ""
	var memory_cfg: Dictionary = _cfg(["repetitionMemory"], {})
	var pressure := str(memory_cfg.get("defaultText", ""))
	for raw_threshold in memory_cfg.get("thresholds", []):
		if not (raw_threshold is Dictionary):
			continue
		var threshold: Dictionary = raw_threshold
		if heat >= int(threshold.get("heat", 0)) or stage == str(threshold.get("stage", "")):
			pressure = str(threshold.get("text", pressure))
			break
	return _template(["repetitionMemory", "template"], {"pressure_text": pressure})


func _participant_action_for(payload: Dictionary, npc_id: String) -> Dictionary:
	if not (payload is Dictionary):
		return {}
	var actions: Variant = payload.get("participant_actions", [])
	if not (actions is Array):
		return {}
	for action in actions:
		if action is Dictionary and str(action.get("npc_id", "")) == npc_id:
			return action.duplicate(true)
	return {}


func _prompt_runtime_payload(npc) -> Dictionary:
	if npc == null:
		return {}
	var result := {
		"performanceState": _field(npc, "performance_state", "idle"),
		"emotionalState": _field(npc, "emotional_state", "neutral"),
	}
	var stance: Dictionary = _field(npc, "stance_to_object", {})
	var stance_text := _gift_attitude_text(stance)
	if not stance_text.is_empty():
		result["currentObjectAttitude"] = stance_text
	return result


func _field(value, name: String, fallback = null) -> Variant:
	if value is Dictionary:
		return value.get(name, fallback)
	if value != null and value is Object:
		return value.get(name)
	return fallback


func _load_config() -> void:
	if feedback_config.is_empty():
		feedback_config = ConfigLoaderScript.load_feedback_config()


func _cfg(path: Array, fallback = null) -> Variant:
	_load_config()
	var current: Variant = feedback_config
	for key in path:
		if not (current is Dictionary):
			return fallback
		current = current.get(key, fallback)
	return current


func _format_template(template: String, values: Dictionary) -> String:
	var result := template
	for key in values.keys():
		result = result.replace("{%s}" % str(key), str(values[key]))
	return result


func _template(path: Array, values: Dictionary = {}, fallback: String = "") -> String:
	return _format_template(str(_cfg(path, fallback)), values)
