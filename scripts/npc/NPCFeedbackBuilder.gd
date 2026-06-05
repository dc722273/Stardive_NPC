extends RefCounted
class_name NPCFeedbackBuilder


var entity_registry = null
var place_registry = null
var event_log = null
var llm_client = null
var transport = null  # LLMTransport（Node），可选，由 set_transport 或 configure 末参注入


func configure(p_entity_registry, p_place_registry, _pathfinder = null, p_event_log = null, p_llm_client = null, p_transport = null) -> void:
	entity_registry = p_entity_registry
	place_registry = p_place_registry
	event_log = p_event_log
	llm_client = p_llm_client
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
	var npc_id := str(feedback.get("npc_id", ""))
	var context: Dictionary = feedback.get("context", {})
	var event_type := str(context.get("event_type", _field(event, "type", "")))
	var place_name := str(context.get("place_name", ""))
	var payload: Dictionary = _field(event, "payload", {})
	var npc_name := str(_field(npc, "name", npc_id))
	var traits = _field(npc, "traits", {})
	var tags = _field(npc, "tags", [])
	var style = _field(npc, "style", {})
	var runtime := _npc_runtime_payload(npc)
	var scene_seed: Dictionary = payload.get("scene_seed", {}) if payload is Dictionary else {}
	var participant_action := _participant_action_for(payload, npc_id)
	var object_stance: Dictionary = payload.get("object_stance", {}) if payload is Dictionary else {}
	var interaction_trace: Dictionary = payload.get("interaction_trace", {}) if payload is Dictionary else {}
	var performance_plan: Dictionary = payload.get("performance_plan", {}) if payload is Dictionary else {}
	var relation_updates: Array = payload.get("relation_memory_updates", []) if payload is Dictionary else []
	var npc_auto_drop: Dictionary = payload.get("npc_auto_drop", {}) if payload is Dictionary else {}

	var user_lines := PackedStringArray()
	user_lines.append("event type: %s" % event_type)
	if not place_name.is_empty():
		user_lines.append("place name: %s" % place_name)
	if not scene_seed.is_empty():
		user_lines.append("scene seed: %s" % JSON.stringify(scene_seed))
	if not participant_action.is_empty():
		user_lines.append("your participant action: %s" % JSON.stringify(participant_action))
	if not object_stance.is_empty():
		user_lines.append("object stance: %s" % JSON.stringify(object_stance))
	if not interaction_trace.is_empty():
		user_lines.append("interaction trace: %s" % JSON.stringify(interaction_trace))
	if not performance_plan.is_empty():
		user_lines.append("performance plan: %s" % JSON.stringify(performance_plan))
	if not relation_updates.is_empty():
		user_lines.append("relation memory updates: %s" % JSON.stringify(relation_updates))
	if not npc_auto_drop.is_empty():
		user_lines.append("npc auto drop: %s" % JSON.stringify(npc_auto_drop))
	if payload is Dictionary and not payload.is_empty():
		user_lines.append("event payload: %s" % JSON.stringify(payload))
	if traits is Dictionary and not traits.is_empty():
		user_lines.append("traits: %s" % JSON.stringify(traits))
	if tags is Array and not tags.is_empty():
		user_lines.append("tags: %s" % JSON.stringify(tags))
	if style is Dictionary and not style.is_empty():
		user_lines.append("style: %s" % JSON.stringify(style))
	if not runtime.is_empty():
		user_lines.append("runtime state: %s" % JSON.stringify(runtime))
	var repetition_hint := _repetition_instruction(interaction_trace, performance_plan)
	if not repetition_hint.is_empty():
		user_lines.append("repetition instruction: %s" % repetition_hint)
	user_lines.append("expression palette: 每次从不同焦点取一句：手部动作、面子、账、嫌疑、归属、旁观目光、临时保管、推回地面。优先具体动作和关系后果，少用单一比喻。")

	return [
		{
			"role": "system",
			"content": "你是%s。你正在参与一个即时 NPC 交互。只输出当前角色的一句中文反应，可在台词前用一个括号动作。必须先回应 scene seed 的 visible_topic 和你的 participant action；如果有 object stance，要按 want/reject/ambivalent 与 dominantReason 表演，不能反着说。如果有 performance plan，按 pattern 的方向演，不要另开话题。如果 interaction trace 的 countInWindow 大于 1，台词必须明显体现“又来一次”的累积感：第2次泄露遮掩，第3次抢先吐槽，第4次回调老梗，第5次及以上仪式化处理；不能写成第一次见到。表达要轮换焦点：动作、面子、账、嫌疑、归属、旁观目光、临时保管、推回地面，不要把每次反应都写成同一种形容。如果 npc auto drop 存在，要把主动丢地上当成已发生的世界事实。如果是物品事件，必须区分 ownerId 和 currentAnchor：ownerId 是社会归属，currentAnchor 是现在贴在谁身上，拖拽不会改变 ownerId。台词短、准、有角色味。" % npc_name,
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
	if event_type == &"player_forced_drop_item":
		return "%s注意到东西被丢下了。" % str(npc_id)
	if event_type == &"player_transfer_item_between_npcs":
		var item_name := str(payload.get("item_name", "物品")) if payload is Dictionary else "物品"
		var target_name := str(payload.get("item_target_name", "对方")) if payload is Dictionary else "对方"
		var target_id := str(payload.get("item_target_id", "")) if payload is Dictionary else ""
		var previous_id := str(payload.get("previousAnchorNpcId", "")) if payload is Dictionary else ""
		var previous_name := str(payload.get("previousAnchorNpcName", "对方")) if payload is Dictionary else "对方"
		var transfer_repeat := _repeat_fallback_suffix(payload, item_name)
		if str(npc_id) == previous_id:
			return "%s把%s递到%s手里%s" % [str(npc_id), item_name, target_name, transfer_repeat.get("previous", "，先等对方给个说法。")]
		if str(npc_id) == target_id:
			var auto_drop_text := _auto_drop_fallback_text(str(npc_id), item_name, payload)
			if not auto_drop_text.is_empty():
				return auto_drop_text
			return "%s接住%s%s" % [str(npc_id), item_name, transfer_repeat.get("target", "，先问%s这一下是什么意思。" % previous_name)]
		return "%s看见%s从%s转到%s手里%s" % [str(npc_id), item_name, previous_name, target_name, transfer_repeat.get("witness", "，立刻闻到一点不对劲。")]
	if event_type == &"player_drop_item_on_npc":
		var item_name := str(payload.get("item_name", "物品")) if payload is Dictionary else "物品"
		var auto_drop_text := _auto_drop_fallback_text(str(npc_id), item_name, payload)
		if not auto_drop_text.is_empty():
			return auto_drop_text
		return _drop_on_npc_repetition_text(str(npc_id), item_name, payload)
	if not title.is_empty():
		return "%s回应“%s”。" % [str(npc_id), title]
	if not str(context.get("place_name", "")).is_empty():
		return "%s在%s停下，回应眼前情况。" % [str(npc_id), str(context["place_name"])]
	return "%s回应%s。" % [str(npc_id), str(event_type)]


func _auto_drop_fallback_text(npc_label: String, item_name: String, payload: Dictionary) -> String:
	var auto_drop: Dictionary = payload.get("npc_auto_drop", {}) if payload is Dictionary else {}
	if auto_drop.is_empty():
		return ""
	var trace: Dictionary = payload.get("interaction_trace", {}) if payload is Dictionary else {}
	var count := int(auto_drop.get("countInWindow", trace.get("countInWindow", 1)))
	var stage := str(auto_drop.get("stage", trace.get("stage", "new")))
	if count >= 5 or stage == "ritualized":
		return "%s接住%s，照老规矩往脚边一放：这回连解释都省了。" % [npc_label, item_name]
	if count == 4 or stage == "gagged":
		return "%s看见%s又到手里，直接丢回地上：这账别再往我身上记。" % [npc_label, item_name]
	return "%s接住%s，马上放到脚边：东西在这儿，别算我拿的。" % [npc_label, item_name]


func _drop_on_npc_repetition_text(npc_label: String, item_name: String, payload: Dictionary) -> String:
	var trace: Dictionary = payload.get("interaction_trace", {}) if payload is Dictionary else {}
	var plan: Dictionary = payload.get("performance_plan", {}) if payload is Dictionary else {}
	var count := int(trace.get("countInWindow", 1))
	var stage := str(trace.get("stage", "new"))
	var pattern := str(plan.get("pattern", "single_reaction"))
	if count >= 5 or stage == "ritualized" or pattern == "ritualized_gag":
		return "%s熟练接住%s，像接住一个老梗：第%d回了，账先记你头上。" % [npc_label, item_name, max(count, 5)]
	if count == 4 or stage == "gagged" or pattern == "gag_callback":
		return "%s一看%s又飞回来，条件反射往外推：又来？这锅我不背。" % [npc_label, item_name]
	if count == 3 or stage == "noticed" or pattern == "preemptive_gag":
		return "%s抢在别人开口前按住%s：别问，问就是它自己来的。" % [npc_label, item_name]
	if count == 2 or stage == "repeated" or pattern == "leak_cover":
		return "%s第二次摸到%s，嘴上说别塞了，手却先把它藏住。" % [npc_label, item_name]
	return "%s接过%s，先看清楚它从谁手里来。" % [npc_label, item_name]


func _repeat_fallback_suffix(payload: Dictionary, item_name: String) -> Dictionary:
	var trace: Dictionary = payload.get("interaction_trace", {}) if payload is Dictionary else {}
	var plan: Dictionary = payload.get("performance_plan", {}) if payload is Dictionary else {}
	var count := int(trace.get("countInWindow", 1))
	var stage := str(trace.get("stage", "new"))
	var pattern := str(plan.get("pattern", "single_reaction"))
	if count >= 5 or stage == "ritualized" or pattern == "ritualized_gag":
		return {
			"previous": "，熟得像在交接一件固定节目。",
			"target": "，顺手摆出老位置：第%d回了，%s今天归我背锅。" % [max(count, 5), item_name],
			"witness": "，大家已经把它当成固定梗看。",
		}
	if count == 4 or stage == "gagged" or pattern == "gag_callback":
		return {
			"previous": "，自己先露出“又到了这一步”的表情。",
			"target": "，立刻回调前几次的账：又来？别把这锅焊我身上。",
			"witness": "，现场明显想起前几次的同一个梗。",
		}
	if count == 3 or stage == "noticed" or pattern == "preemptive_gag":
		return {
			"previous": "，话还没出口就等着对方抢先辩解。",
			"target": "，抢先堵话：我知道你们要问什么，不是我主动要的。",
			"witness": "，旁边人已经不用解释也知道这事不对。",
		}
	if count == 2 or stage == "repeated" or pattern == "leak_cover":
		return {
			"previous": "，这第二次显得比第一次更像试探。",
			"target": "，第二次接住时明显想藏，又怕藏得太明显。",
			"witness": "，重复感让这事从偶然变成了话柄。",
		}
	return {}


func _repetition_instruction(interaction_trace: Dictionary, performance_plan: Dictionary) -> String:
	var count := int(interaction_trace.get("countInWindow", 1))
	var stage := str(interaction_trace.get("stage", "new"))
	var pattern := str(performance_plan.get("pattern", "single_reaction"))
	if count <= 1 and stage == "new":
		return ""
	return "这是第%d次同物件/同NPC触发，trace stage=%s，pattern=%s；必须让台词听起来不是第一次。" % [count, stage, pattern]


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


func _npc_runtime_payload(npc) -> Dictionary:
	if npc == null:
		return {}
	return {
		"performanceState": _field(npc, "performance_state", "idle"),
		"emotionalState": _field(npc, "emotional_state", "neutral"),
		"stanceToObject": _field(npc, "stance_to_object", {}),
		"currentGag": _field(npc, "current_gag", {}),
		"cooldowns": _field(npc, "cooldowns", {}),
	}


func _field(value, name: String, fallback = null) -> Variant:
	if value is Dictionary:
		return value.get(name, fallback)
	if value != null and value is Object:
		return value.get(name)
	return fallback
