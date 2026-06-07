extends RefCounted
class_name InteractionDeltaRules

static func apply_attach_object_to_npc(item, target_npc_id: StringName, previous_anchor_npc_id: StringName, participant_ids: Array, registry, gameplay_config: Dictionary, current_tick: int, gift_context: Dictionary = {}) -> Dictionary:
	if item == null:
		return {}
	var config := _attach_config(gameplay_config)
	_configure_registry(registry, config)
	var context := _gift_context(item, target_npc_id, previous_anchor_npc_id, gift_context)
	var repeat_trace := _repeat_trace(registry, item, target_npc_id, context)
	var receiver = registry.npcs.get(target_npc_id) if registry != null and registry.npcs.has(target_npc_id) else null
	var stance := gift_stance(item, target_npc_id, receiver, repeat_trace, config)
	var heat_delta := _heat_delta(item.social, stance, config)
	var trace := _update_interaction_trace(registry, item.id, target_npc_id, stance, heat_delta, config, current_tick)
	var gift_trace := _update_gift_trace(registry, item, target_npc_id, context, heat_delta, config, current_tick)
	var memory_updates := _update_object_memory(item, target_npc_id, stance, heat_delta, config, current_tick, trace)
	var relation_updates := _update_relation_memories(registry, target_npc_id, previous_anchor_npc_id, participant_ids, stance, context, config, current_tick)
	_update_item_custody(item)
	_update_npc_runtime(registry, item.id, target_npc_id, stance, memory_updates, config)
	return {
		"eventType": "attach_object_to_npc",
		"interactionTrace": trace,
		"giftTrace": gift_trace,
		"giftContext": context,
		"giftStance": stance,
		"heatDelta": heat_delta,
		"objectMemoryUpdates": memory_updates,
		"relationMemoryUpdates": relation_updates,
		"performancePlan": _performance_plan(target_npc_id, item.id, stance, memory_updates, trace, config),
	}


static func gift_stance(item, target_npc_id: StringName, receiver = null, repeat_trace: Dictionary = {}, config: Dictionary = {}) -> Dictionary:
	var stance_cfg: Dictionary = config.get("giftStance", {})
	var social: Dictionary = item.social if item != null else {}
	var access_rule: Dictionary = item.access_rule if item != null else {}
	var owner_id: StringName = item.owner_id if item != null else &""
	var allowed: Array = access_rule.get("allowedNpcIds", [])
	var exclusivity: int = int(access_rule.get("exclusivity", 0))
	var is_owner: bool = owner_id != &"" and owner_id == target_npc_id
	var is_allowed: bool = allowed.is_empty() or allowed.has(str(target_npc_id)) or allowed.has(target_npc_id)
	var forbidden_pressure: int = 0 if is_owner or is_allowed else max(int(stance_cfg.get("forbiddenPressureMin", 0)), exclusivity)
	var preference := _effective_preference(receiver, config)
	var classification_like := _classification_like(item, preference)
	var social_like := _social_like(social, preference)
	var want_weights: Dictionary = stance_cfg.get("wantWeights", {})
	var want_value := classification_like + social_like
	for key in want_weights.keys():
		if str(key) == "ownerBonus":
			continue
		want_value += float(social.get(key, 0)) * float(want_weights.get(key, 0.0))
	var want: int = int(round(want_value))
	if is_owner:
		want += int(want_weights.get("ownerBonus", 0))
	var pressure := _gift_pressure(social, preference, forbidden_pressure, config)
	var fatigue := _gift_fatigue(repeat_trace, preference, config)
	var reject: int = int(round(pressure + fatigue))
	var result := _gift_result(want, reject, pressure, fatigue, receiver, config)
	var reason := _dominant_reason(social, forbidden_pressure, config)
	var gag := _body_gag_for(receiver, item, reason)
	return {
		"like": clampi(want, 0, 100),
		"want": clampi(want, 0, 100),
		"reject": clampi(reject, 0, 100),
		"pressure": clampi(int(round(pressure)), 0, 100),
		"fatigue": clampi(int(round(fatigue)), 0, 100),
		"dominantReason": reason,
		"bodyGagId": str(gag.get("id", "")),
		"gagTag": str(gag.get("label", reason)),
		"gagAction": str(gag.get("action", "")),
		"preemptiveLine": str(gag.get("preemptiveLine", "")),
		"result": result,
		"legacyResult": _legacy_result(result),
	}


static func _update_interaction_trace(registry, object_id: StringName, target_npc_id: StringName, _stance: Dictionary, heat_delta: int, config: Dictionary, current_tick: int) -> Dictionary:
	var link_cfg: Dictionary = config.get("objectLinkDelta", {})
	var decay := float(link_cfg.get("heatDecayBeforeAdd", 1.0))
	var stage_order: Array = config.get("stageOrder", [])
	var initial_stage := str(stage_order[0]) if not stage_order.is_empty() else ""
	if registry != null and registry.has_method("update_interaction_trace"):
		return registry.update_interaction_trace("attach_object_to_npc", object_id, target_npc_id, heat_delta, decay, current_tick)
	return {
		"key": "attach_object_to_npc:%s:%s" % [str(object_id), str(target_npc_id)],
		"eventType": "attach_object_to_npc",
		"objectId": str(object_id),
		"targetNpcId": str(target_npc_id),
		"countInWindow": 1,
		"heat": heat_delta,
		"firstSeenAt": current_tick,
		"lastSeenAt": current_tick,
		"stage": initial_stage,
	}


static func _update_object_memory(item, target_npc_id: StringName, stance: Dictionary, heat_delta: int, config: Dictionary, current_tick: int, trace: Dictionary) -> Array:
	var updates: Array = []
	if int(trace.get("countInWindow", 1)) < 2:
		return updates
	var memory: Dictionary = item.memory if item.memory is Dictionary else {"topLinks": []}
	var links: Array = memory.get("topLinks", [])
	var link_cfg: Dictionary = config.get("objectLinkDelta", {})
	var decay := float(link_cfg.get("heatDecayBeforeAdd", 1.0))
	for link in links:
		if link is Dictionary:
			link["heat"] = int(float(link.get("heat", 0)) * decay)
	var link := _upsert_object_link(links, target_npc_id, heat_delta, stance, config, current_tick)
	updates.append(link.duplicate(true))
	links = _trim_links(links, int(link_cfg.get("maxTopLinks", links.size())))
	memory["topLinks"] = links
	item.memory = memory
	return updates


static func _update_relation_memories(registry, target_npc_id: StringName, previous_anchor_npc_id: StringName, participant_ids: Array, stance: Dictionary, context: Dictionary, config: Dictionary, current_tick: int) -> Array:
	var updates: Array = []
	if registry == null or not registry.has_method("apply_relation_delta"):
		return updates
	var giver_id := StringName(context.get("giverNpcId", previous_anchor_npc_id))
	var attribution := str(context.get("attributionTarget", "unknown"))
	var confidence := float(context.get("attributionConfidence", 0.0))
	if attribution != "npc" or giver_id == &"" or giver_id == target_npc_id or confidence <= 0.0:
		return updates
	var delta := _gift_relation_delta(stance, confidence, config)
	var tag := str(stance.get("dominantReason", "awkward"))
	updates.append(registry.apply_relation_delta(target_npc_id, giver_id, delta, tag, current_tick))
	for raw_id in participant_ids:
		var npc_id := StringName(raw_id)
		if npc_id == &"" or npc_id == target_npc_id or npc_id == giver_id:
			continue
		updates.append(registry.apply_relation_delta(npc_id, target_npc_id, _witness_relation_delta(config), "witnessed_object_shift", current_tick))
	return updates


static func _update_item_custody(item) -> void:
	if item != null:
		item.custody_state = "unclaimed"


static func _update_npc_runtime(registry, object_id: StringName, target_npc_id: StringName, stance: Dictionary, memory_updates: Array, config: Dictionary) -> void:
	if registry == null or not registry.npcs.has(target_npc_id):
		return
	var npc = registry.npcs[target_npc_id]
	var result := str(stance.get("result", "ambivalent"))
	var reason := str(stance.get("dominantReason", "awkward"))
	npc.stance_to_object = {
		"objectId": str(object_id),
		"result": result,
		"legacyResult": str(stance.get("legacyResult", result)),
		"like": int(stance.get("like", stance.get("want", 0))),
		"pressure": int(stance.get("pressure", 0)),
		"fatigue": int(stance.get("fatigue", 0)),
		"reason": reason,
		"bodyGagId": str(stance.get("bodyGagId", "")),
		"gagTag": str(stance.get("gagTag", reason)),
		"gagAction": str(stance.get("gagAction", "")),
		"preemptiveLine": str(stance.get("preemptiveLine", "")),
	}
	npc.performance_state = _performance_state_for_result(result, config)
	npc.emotional_state = _emotion_for_reason(reason, result, config)
	if not memory_updates.is_empty():
		var first: Dictionary = memory_updates[0]
		npc.current_gag = {
			"id": str(first.get("bodyGagId", "")),
			"tag": str(first.get("gagTag", reason)),
			"stage": str(first.get("stage", "new")),
			"action": str(first.get("gagAction", "")),
			"preemptiveLine": str(first.get("preemptiveLine", "")),
		}
		npc.cooldowns["lastReactedAt"] = int(first.get("lastUsedAt", 0))


static func _performance_plan(target_npc_id: StringName, object_id: StringName, stance: Dictionary, memory_updates: Array, trace: Dictionary = {}, config: Dictionary = {}) -> Dictionary:
	var plan_cfg: Dictionary = config.get("performancePlan", {})
	var stage := str(plan_cfg.get("defaultStage", ""))
	if not memory_updates.is_empty():
		stage = str((memory_updates[0] as Dictionary).get("stage", stage))
	elif not trace.is_empty():
		stage = str(trace.get("stage", stage))
	var result := str(stance.get("result", "ambivalent"))
	var default_pattern := str(plan_cfg.get("defaultPattern", ""))
	var stage_patterns: Dictionary = plan_cfg.get("stagePatterns", {})
	var new_patterns: Dictionary = plan_cfg.get("newResultPatterns", {})
	var pattern := str(stage_patterns.get(stage, default_pattern))
	if pattern == default_pattern and new_patterns.has(result):
		pattern = str(new_patterns.get(result, pattern))
	var large_stages: Array = plan_cfg.get("largeStages", [])
	return {
		"pattern": pattern,
		"scale": str(plan_cfg.get("largeScale", "")) if large_stages.has(stage) else str(plan_cfg.get("defaultScale", "")),
		"steps": _performance_steps(target_npc_id, object_id, plan_cfg, stance),
		"memoryUpdate": {
			"objectId": str(object_id),
			"npcId": str(target_npc_id),
			"gagTag": str(stance.get("gagTag", stance.get("dominantReason", ""))),
			"bodyGagId": str(stance.get("bodyGagId", "")),
			"gagAction": str(stance.get("gagAction", "")),
		},
	}


static func _attach_config(gameplay_config: Dictionary) -> Dictionary:
	var configured: Dictionary = gameplay_config.get("interactionDeltaConfig", gameplay_config.get("interaction_delta_config", {}))
	return configured.duplicate(true)


static func _performance_steps(target_npc_id: StringName, object_id: StringName, plan_cfg: Dictionary, stance: Dictionary = {}) -> Array:
	var result: Array = []
	var raw_steps: Variant = plan_cfg.get("steps", [])
	if not (raw_steps is Array):
		return result
	for raw_step in raw_steps:
		if not (raw_step is Dictionary):
			continue
		var step: Dictionary = raw_step.duplicate(true)
		step["actorId"] = str(step.get("actorId", target_npc_id))
		step["targetId"] = str(step.get("targetId", object_id))
		result.append(step)
	var expression_id := _performance_expression_id(plan_cfg, stance)
	if not expression_id.is_empty():
		result.insert(min(1, result.size()), {
			"actorId": str(target_npc_id),
			"targetId": str(object_id),
			"channel": "face",
			"expressionId": expression_id,
		})
	return result


static func _performance_expression_id(plan_cfg: Dictionary, stance: Dictionary) -> String:
	var reason := str(stance.get("dominantReason", ""))
	var reason_map: Dictionary = plan_cfg.get("expressionByReason", {})
	if reason_map.has(reason):
		return str(reason_map.get(reason, ""))
	var result := str(stance.get("result", "ambivalent"))
	var result_map: Dictionary = plan_cfg.get("expressionByResult", {})
	return str(result_map.get(result, ""))


static func _configure_registry(registry, config: Dictionary) -> void:
	if registry != null and registry.has_method("set_interaction_stage_thresholds"):
		registry.set_interaction_stage_thresholds(config.get("stageThresholds", {}))


static func _heat_delta(social: Dictionary, stance: Dictionary, config: Dictionary) -> int:
	var value := float(config.get("baseHeatDelta", 0))
	var weights: Dictionary = config.get("objectHeatWeights", {})
	for key in weights.keys():
		value += float(social.get(key, 0)) * float(weights[key])
	var stance_delta: Dictionary = config.get("stanceHeatDelta", {})
	value += float(stance_delta.get(str(stance.get("result", "ambivalent")), 0))
	return int(round(value))


static func _dominant_reason(social: Dictionary, forbidden_pressure: int, config: Dictionary = {}) -> String:
	if forbidden_pressure > 0:
		return "forbidden"
	var best_key := ""
	var best_value := -1
	var stance_cfg: Dictionary = config.get("giftStance", {})
	var priority: Array = stance_cfg.get("dominantReasonPriority", [])
	for key in priority:
		var value := int(social.get(key, 0))
		if value > best_value:
			best_key = str(key)
			best_value = value
	return best_key


static func _gift_context(item, target_npc_id: StringName, previous_anchor_npc_id: StringName, override: Dictionary) -> Dictionary:
	var giver_id := StringName(override.get("giverNpcId", previous_anchor_npc_id))
	var attribution := str(override.get("attributionTarget", ""))
	var confidence := float(override.get("attributionConfidence", -1.0))
	if attribution.is_empty():
		attribution = "npc" if giver_id != &"" and giver_id != target_npc_id else "unknown"
	if confidence < 0.0:
		confidence = 1.0 if attribution == "npc" else 0.0
	return {
		"eventType": "give_object_to_npc",
		"objectId": str(item.id) if item != null else "",
		"objectTypeId": str(item.type_id) if item != null else "",
		"operator": str(override.get("operator", "player")),
		"giverNpcId": giver_id,
		"receiverNpcId": target_npc_id,
		"fromAnchor": override.get("fromAnchor", {"type": "npc", "npcId": str(previous_anchor_npc_id)} if previous_anchor_npc_id != &"" else {"type": "ground"}),
		"toAnchor": override.get("toAnchor", {"type": "npc", "npcId": str(target_npc_id)}),
		"attributionTarget": attribution,
		"attributionConfidence": clampf(confidence, 0.0, 1.0),
	}


static func _repeat_trace(registry, item, target_npc_id: StringName, context: Dictionary) -> Dictionary:
	if registry == null or item == null or not registry.has_method("interaction_trace"):
		return {}
	var giver_key := _gift_giver_key(context)
	var object_key := _gift_object_key(item)
	return registry.interaction_trace(StringName(object_key), target_npc_id, "gift:%s" % giver_key)


static func preemptive_gag_for_item_target(item, target_npc_id: StringName, gameplay_config: Dictionary = {}) -> Dictionary:
	if item == null or not (item.memory is Dictionary):
		return {}
	var trained_stages: Array = _attach_config(gameplay_config).get("performancePlan", {}).get("trainedStages", [])
	var links: Array = item.memory.get("topLinks", [])
	for link in links:
		if not (link is Dictionary):
			continue
		if StringName(link.get("npcId", "")) != target_npc_id:
			continue
		var stage := str(link.get("stage", ""))
		if not trained_stages.has(stage):
			return {}
		if str(link.get("bodyGagId", "")).is_empty() and str(link.get("preemptiveLine", "")).is_empty() and str(link.get("gagAction", "")).is_empty():
			return {}
		return {
			"npcId": str(target_npc_id),
			"objectId": str(item.id),
			"stage": stage,
			"bodyGagId": str(link.get("bodyGagId", "")),
			"gagTag": str(link.get("gagTag", "")),
			"gagAction": str(link.get("gagAction", "")),
			"preemptiveLine": str(link.get("preemptiveLine", "")),
			"trained": true,
		}
	return {}


static func _update_gift_trace(registry, item, target_npc_id: StringName, context: Dictionary, heat_delta: int, config: Dictionary, current_tick: int) -> Dictionary:
	if registry == null or item == null or not registry.has_method("update_interaction_trace"):
		return {}
	var decay := float(config.get("objectLinkDelta", {}).get("heatDecayBeforeAdd", 1.0))
	var giver_key := _gift_giver_key(context)
	var object_key := _gift_object_key(item)
	return registry.update_interaction_trace("gift:%s" % giver_key, StringName(object_key), target_npc_id, heat_delta, decay, current_tick)


static func _gift_giver_key(context: Dictionary) -> String:
	if str(context.get("attributionTarget", "unknown")) == "npc" and StringName(context.get("giverNpcId", &"")) != &"":
		return "npc:%s" % str(context.get("giverNpcId", ""))
	if str(context.get("attributionTarget", "unknown")) == "player":
		return "player"
	return "unknown"


static func _gift_object_key(item) -> String:
	var classification: Dictionary = item.classification if item != null and item.classification is Dictionary else {}
	var category := str(classification.get("category", item.category if item != null else "object"))
	var subtype := str(classification.get("subtype", ""))
	if not subtype.is_empty():
		return "%s.%s" % [category, subtype]
	if not category.is_empty():
		return category
	return str(item.type_id) if item != null else "object"


static func _classification_keys(item) -> Array:
	var keys: Array = []
	if item == null:
		return keys
	var classification: Dictionary = item.classification if item.classification is Dictionary else {}
	var category := str(classification.get("category", item.category))
	if not category.is_empty():
		keys.append(category)
	var subtype := str(classification.get("subtype", ""))
	if not category.is_empty() and not subtype.is_empty():
		keys.append("%s.%s" % [category, subtype])
	var material := str(classification.get("material", ""))
	if not material.is_empty():
		keys.append("material.%s" % material)
	return keys


static func _body_gag_for(receiver, item, reason: String) -> Dictionary:
	var raw_gags: Variant = _receiver_field(receiver, "body_gags", _receiver_field(receiver, "bodyGags", []))
	if not (raw_gags is Array):
		return {}
	var item_keys := _classification_keys(item)
	var best: Dictionary = {}
	var best_score := -1
	for raw_gag in raw_gags:
		if not (raw_gag is Dictionary):
			continue
		var gag: Dictionary = raw_gag
		var match: Dictionary = gag.get("match", {})
		var score := 0
		var class_keys: Variant = match.get("classificationKeys", [])
		if class_keys is Array:
			for key in class_keys:
				if item_keys.has(str(key)):
					score = max(score, 2 + max(0, str(key).split(".").size() - 1))
		var reasons: Variant = match.get("reasons", [])
		if reasons is Array and reasons.has(reason):
			score += 1
		if score > best_score:
			best_score = score
			best = gag
	return best if best_score > 0 else {}


static func _effective_preference(receiver, config: Dictionary = {}) -> Dictionary:
	var default_preference: Dictionary = config.get("defaultPreference", {})
	var preference: Variant = _receiver_field(receiver, "preference", {})
	if preference is Dictionary:
		return _merge_dict(default_preference, preference)
	return default_preference.duplicate(true)


static func _receiver_field(receiver, field_name: String, fallback = null) -> Variant:
	if receiver is Dictionary:
		return receiver.get(field_name, fallback)
	if receiver != null and receiver is Object:
		var value: Variant = receiver.get(field_name)
		return fallback if value == null else value
	return fallback


static func _classification_like(item, preference: Dictionary) -> float:
	var affinity: Dictionary = preference.get("classificationAffinity", {})
	var total := 0.0
	for key in _classification_keys(item):
		total += float(affinity.get(str(key), 0.0))
	return total


static func _social_like(social: Dictionary, preference: Dictionary) -> float:
	var affinity: Dictionary = preference.get("socialAffinity", {})
	var total := 0.0
	for key in social.keys():
		total += float(social.get(key, 0.0)) * float(affinity.get(str(key), 0.0)) * 0.01
	return total


static func _gift_pressure(social: Dictionary, preference: Dictionary, forbidden_pressure: int, config: Dictionary = {}) -> float:
	var tolerance: Dictionary = preference.get("tolerance", {})
	var stance_cfg: Dictionary = config.get("giftStance", {})
	var weights: Dictionary = stance_cfg.get("pressureWeights", {})
	var tolerance_max := float(stance_cfg.get("toleranceMax", 100))
	return float(social.get("danger", 0)) * float(tolerance_max - int(tolerance.get("danger", 0))) * float(weights.get("danger", 0.0)) + float(social.get("debt", 0)) * float(tolerance_max - int(tolerance.get("debt", 0))) * float(weights.get("debt", 0.0)) + float(social.get("awkward", 0)) * float(tolerance_max - int(tolerance.get("awkward", 0))) * float(weights.get("awkward", 0.0)) + float(forbidden_pressure) * float(weights.get("forbidden", 0.0))


static func _gift_fatigue(repeat_trace: Dictionary, preference: Dictionary, config: Dictionary = {}) -> float:
	var tolerance: Dictionary = preference.get("tolerance", {})
	var stance_cfg: Dictionary = config.get("giftStance", {})
	var fatigue_cfg: Dictionary = stance_cfg.get("fatigue", {})
	var repeat_count := int(repeat_trace.get("countInWindow", 0)) + int(fatigue_cfg.get("countOffset", 1))
	return float(max(0, repeat_count - 1)) * float(float(stance_cfg.get("toleranceMax", 100)) - int(tolerance.get("repetition", 0))) * float(fatigue_cfg.get("toleranceScale", 0.0))


static func _gift_result(like: int, reject: int, pressure: float, fatigue: float, receiver, config: Dictionary = {}) -> String:
	var result_cfg: Dictionary = config.get("giftStance", {}).get("result", {})
	var margin := float(result_cfg.get("margin", 0.0))
	if float(like) > float(reject) + margin:
		return "like_then_reject" if result_cfg.has("likeThenRejectFatigue") and fatigue > float(result_cfg.get("likeThenRejectFatigue", 0.0)) else "like"
	if float(reject) > float(like) + margin:
		return "accept_then_discard" if _should_accept_then_discard(pressure, fatigue, receiver, config) else "reject"
	return "ambivalent"


static func _should_accept_then_discard(pressure: float, fatigue: float, receiver, config: Dictionary = {}) -> bool:
	var discard_cfg: Dictionary = config.get("giftStance", {}).get("acceptThenDiscard", {})
	if receiver == null:
		return discard_cfg.has("pressureFallback") and discard_cfg.has("fatigueFallback") and pressure > float(discard_cfg.get("pressureFallback", 0.0)) and fatigue > float(discard_cfg.get("fatigueFallback", 0.0))
	var raw_traits: Variant = _receiver_field(receiver, "traits", {})
	var traits: Dictionary = raw_traits if raw_traits is Dictionary else {}
	var stance_cfg: Dictionary = config.get("giftStance", {})
	if not discard_cfg.has("baseThreshold"):
		return false
	var threshold := float(discard_cfg.get("baseThreshold", 0.0))
	for raw_adjustment in discard_cfg.get("traitAdjustments", []):
		if not (raw_adjustment is Dictionary):
			continue
		var adjustment: Dictionary = raw_adjustment
		var field := str(adjustment.get("field", ""))
		threshold += float(max(0, int(traits.get(field, stance_cfg.get("traitDefault", 0))) - int(adjustment.get("above", 0)))) * float(adjustment.get("scale", 0.0))
	return pressure + fatigue * float(discard_cfg.get("fatigueWeight", 0.0)) >= threshold


static func _legacy_result(result: String) -> String:
	if result == "like" or result == "like_then_reject":
		return "want"
	if result == "reject" or result == "accept_then_discard":
		return "reject"
	return "ambivalent"


static func _gift_relation_delta(stance: Dictionary, confidence: float, config: Dictionary = {}) -> Dictionary:
	var result := str(stance.get("result", "ambivalent"))
	var c := clampf(confidence, 0.0, 1.0)
	var delta := {"attention": 0, "warmth": 0, "awkward": 0, "suspicion": 0, "debt": 0, "fun": 0}
	var result_cfg: Dictionary = config.get("giftRelationDelta", {}).get(result, {})
	for axis in delta.keys():
		var rule: Dictionary = result_cfg.get(axis, {})
		if rule.is_empty():
			continue
		var min_source := str(rule.get("minSource", ""))
		if not min_source.is_empty() and float(stance.get(min_source, 0)) < float(rule.get("min", 0)):
			continue
		var source := str(rule.get("source", ""))
		var base := float(rule.get("base", 0.0))
		var value := base
		if not source.is_empty():
			value += float(stance.get(source, 0.0)) * float(rule.get("scale", 0.0))
		delta[axis] = int(round(value * c))
	return delta


static func _witness_relation_delta(config: Dictionary) -> Dictionary:
	return config.get("witnessRelationDelta", {}).duplicate(true)


static func _upsert_object_link(links: Array, npc_id: StringName, heat_delta: int, stance: Dictionary, config: Dictionary, current_tick: int) -> Dictionary:
	for link in links:
		if link is Dictionary and str(link.get("npcId", "")) == str(npc_id):
			link["heat"] = int(link.get("heat", 0)) + heat_delta
			link["countInScene"] = int(link.get("countInScene", 0)) + 1
			_apply_stage(link, config, current_tick)
			link["lastUsedAt"] = current_tick
			link["bodyGagId"] = str(stance.get("bodyGagId", ""))
			link["gagTag"] = str(stance.get("gagTag", stance.get("dominantReason", "")))
			link["gagAction"] = str(stance.get("gagAction", ""))
			link["preemptiveLine"] = str(stance.get("preemptiveLine", ""))
			return link
	var created := {
		"npcId": str(npc_id),
		"heat": heat_delta,
		"countInScene": 1,
		"stage": _initial_stage(config),
		"lastUsedAt": current_tick,
		"bodyGagId": str(stance.get("bodyGagId", "")),
		"gagTag": str(stance.get("gagTag", stance.get("dominantReason", ""))),
		"gagAction": str(stance.get("gagAction", "")),
		"preemptiveLine": str(stance.get("preemptiveLine", "")),
	}
	_apply_stage(created, config, current_tick)
	links.append(created)
	return created


static func _apply_stage(link: Dictionary, config: Dictionary, current_tick: int) -> void:
	var thresholds: Dictionary = config.get("stageThresholds", {})
	var stage_order: Array = config.get("stageOrder", thresholds.keys())
	if stage_order.is_empty():
		stage_order = [str(link.get("stage", ""))]
	var heat := int(link.get("heat", 0))
	var target_stage := str(stage_order[0])
	var reverse_order := stage_order.duplicate()
	reverse_order.reverse()
	for candidate in reverse_order:
		if heat >= int(thresholds.get(candidate, 0)):
			target_stage = str(candidate)
			break
	var stage := _advance_stage_by_one(str(link.get("stage", target_stage)), target_stage, stage_order)
	if str(link.get("stage", "")) != stage:
		link["lastStageChangedAt"] = current_tick
	link["stage"] = stage


static func _initial_stage(config: Dictionary) -> String:
	var stage_order: Array = config.get("stageOrder", [])
	return str(stage_order[0]) if not stage_order.is_empty() else ""


static func _advance_stage_by_one(current: String, target: String, order: Array) -> String:
	var current_index := order.find(current)
	var target_index := order.find(target)
	if current_index < 0:
		current_index = 0
	if target_index < 0:
		target_index = 0
	return order[min(current_index + 1, target_index)]


static func _trim_links(links: Array, max_links: int) -> Array:
	links.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("heat", 0)) > int(right.get("heat", 0))
	)
	return links.slice(0, max(0, max_links))


static func _performance_state_for_result(result: String, config: Dictionary) -> String:
	var mapping: Dictionary = config.get("runtimeState", {}).get("performanceByResult", {})
	return str(mapping.get(result, mapping.get("default", "")))


static func _emotion_for_reason(reason: String, result: String, config: Dictionary) -> String:
	var mapping: Dictionary = config.get("runtimeState", {}).get("emotionByReason", {})
	var reason_cfg: Variant = mapping.get(reason, {})
	if reason_cfg is Dictionary:
		return str(reason_cfg.get(result, reason_cfg.get("default", mapping.get("default", ""))))
	return str(mapping.get("default", ""))


static func _merge_dict(base: Dictionary, override: Variant) -> Dictionary:
	var result := base.duplicate(true)
	if override is Dictionary:
		for key in override.keys():
			if result.get(key) is Dictionary and override[key] is Dictionary:
				result[key] = _merge_dict(result[key], override[key])
			else:
				result[key] = override[key]
	return result
