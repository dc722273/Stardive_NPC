extends RefCounted
class_name InteractionDeltaRules

const DEFAULT_ATTACH_CONFIG := {
	"baseHeatDelta": 18,
	"objectHeatWeights": {
		"status": 0.05,
		"utility": 0.02,
		"debt": 0.08,
		"awkward": 0.10,
		"joke": 0.12,
		"danger": 0.10,
	},
	"stanceHeatDelta": {
		"want": 4,
		"reject": 8,
		"ambivalent": 12,
	},
	"objectLinkDelta": {
		"heatDecayBeforeAdd": 0.8,
		"maxTopLinks": 5,
	},
	"relationDelta": {
		"attention": 3,
		"awkward": 2,
		"suspicion": 0,
		"debt": 0,
		"fun": 1,
	},
	"reasonRelationDelta": {
		"danger": {"attention": 2, "awkward": 4, "suspicion": 2, "fun": 1},
		"forbidden": {"attention": 3, "awkward": 5, "suspicion": 1, "debt": 1, "fun": 2},
		"awkward": {"attention": 3, "awkward": 6, "debt": 1, "fun": 3},
		"debt": {"attention": 2, "awkward": 3, "debt": 5, "fun": 2},
		"joke": {"attention": 2, "awkward": 2, "fun": 5},
		"status": {"attention": 2, "awkward": 3, "debt": 3, "fun": 2},
	},
	"stageThresholds": {
		"new": 0,
		"repeated": 35,
		"noticed": 70,
		"gagged": 105,
		"ritualized": 140,
	},
}


static func apply_attach_object_to_npc(item, target_npc_id: StringName, previous_anchor_npc_id: StringName, participant_ids: Array, registry, gameplay_config: Dictionary, current_tick: int) -> Dictionary:
	if item == null:
		return {}
	var config := _attach_config(gameplay_config)
	var stance := object_stance(item, target_npc_id)
	var heat_delta := _heat_delta(item.social, stance, config)
	var trace := _update_interaction_trace(registry, item.id, target_npc_id, stance, heat_delta, config, current_tick)
	var memory_updates := _update_object_memory(item, target_npc_id, stance, heat_delta, config, current_tick, trace)
	var relation_updates := _update_relation_memories(registry, target_npc_id, previous_anchor_npc_id, participant_ids, stance, config, current_tick)
	_update_item_custody(item)
	_update_npc_runtime(registry, item.id, target_npc_id, stance, memory_updates)
	return {
		"eventType": "attach_object_to_npc",
		"interactionTrace": trace,
		"objectStance": stance,
		"heatDelta": heat_delta,
		"objectMemoryUpdates": memory_updates,
		"relationMemoryUpdates": relation_updates,
		"performancePlan": _performance_plan(target_npc_id, item.id, stance, memory_updates, trace),
	}


static func object_stance(item, target_npc_id: StringName) -> Dictionary:
	var social: Dictionary = item.social if item != null else {}
	var access_rule: Dictionary = item.access_rule if item != null else {}
	var owner_id: StringName = item.owner_id if item != null else &""
	var allowed: Array = access_rule.get("allowedNpcIds", [])
	var exclusivity: int = int(access_rule.get("exclusivity", 0))
	var is_owner: bool = owner_id != &"" and owner_id == target_npc_id
	var is_allowed: bool = allowed.is_empty() or allowed.has(str(target_npc_id)) or allowed.has(target_npc_id)
	var forbidden_pressure: int = 0 if is_owner or is_allowed else max(35, exclusivity)
	var want: int = int(float(social.get("utility", 0)) * 0.36 + float(social.get("status", 0)) * 0.24 + float(social.get("joke", 0)) * 0.14)
	if is_owner:
		want += 28
	var reject: int = int(float(social.get("danger", 0)) * 0.36 + float(social.get("awkward", 0)) * 0.26 + float(social.get("debt", 0)) * 0.18 + float(forbidden_pressure) * 0.45)
	var result: String = "ambivalent"
	if want - reject >= 15:
		result = "want"
	elif reject - want >= 15:
		result = "reject"
	var reason := _dominant_reason(social, forbidden_pressure)
	return {
		"want": clampi(want, 0, 100),
		"reject": clampi(reject, 0, 100),
		"dominantReason": reason,
		"result": result,
	}


static func _update_interaction_trace(registry, object_id: StringName, target_npc_id: StringName, _stance: Dictionary, heat_delta: int, config: Dictionary, current_tick: int) -> Dictionary:
	var decay := float(config.get("objectLinkDelta", {}).get("heatDecayBeforeAdd", 0.8))
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
		"stage": "new",
	}


static func _update_object_memory(item, target_npc_id: StringName, stance: Dictionary, heat_delta: int, config: Dictionary, current_tick: int, trace: Dictionary) -> Array:
	var updates: Array = []
	if int(trace.get("countInWindow", 1)) < 2:
		return updates
	var memory: Dictionary = item.memory if item.memory is Dictionary else {"topLinks": []}
	var links: Array = memory.get("topLinks", [])
	var decay := float(config.get("objectLinkDelta", {}).get("heatDecayBeforeAdd", 0.8))
	for link in links:
		if link is Dictionary:
			link["heat"] = int(float(link.get("heat", 0)) * decay)
	var link := _upsert_object_link(links, target_npc_id, heat_delta, stance, config, current_tick)
	updates.append(link.duplicate(true))
	links = _trim_links(links, int(config.get("objectLinkDelta", {}).get("maxTopLinks", 5)))
	memory["topLinks"] = links
	item.memory = memory
	return updates


static func _update_relation_memories(registry, target_npc_id: StringName, previous_anchor_npc_id: StringName, participant_ids: Array, stance: Dictionary, config: Dictionary, current_tick: int) -> Array:
	var updates: Array = []
	if registry == null or not registry.has_method("apply_relation_delta"):
		return updates
	var delta := _relation_delta_for_reason(stance, config)
	var tag := str(stance.get("dominantReason", "awkward"))
	if previous_anchor_npc_id != &"" and previous_anchor_npc_id != target_npc_id:
		updates.append(registry.apply_relation_delta(target_npc_id, previous_anchor_npc_id, delta, tag, current_tick))
		updates.append(registry.apply_relation_delta(previous_anchor_npc_id, target_npc_id, delta, tag, current_tick))
	for raw_id in participant_ids:
		var npc_id := StringName(raw_id)
		if npc_id == &"" or npc_id == target_npc_id or npc_id == previous_anchor_npc_id:
			continue
		updates.append(registry.apply_relation_delta(npc_id, target_npc_id, {"attention": 2, "awkward": 1, "suspicion": 0, "debt": 0, "fun": 2}, "witnessed_object_shift", current_tick))
	return updates


static func _update_item_custody(item) -> void:
	if item != null:
		item.custody_state = "unclaimed"


static func _update_npc_runtime(registry, object_id: StringName, target_npc_id: StringName, stance: Dictionary, memory_updates: Array) -> void:
	if registry == null or not registry.npcs.has(target_npc_id):
		return
	var npc = registry.npcs[target_npc_id]
	var result := str(stance.get("result", "ambivalent"))
	var reason := str(stance.get("dominantReason", "awkward"))
	npc.stance_to_object = {
		"objectId": str(object_id),
		"result": result,
		"reason": reason,
	}
	npc.performance_state = "approaching" if result == "want" else ("pulling_away" if result == "reject" else "hesitating")
	npc.emotional_state = _emotion_for_reason(reason, result)
	if not memory_updates.is_empty():
		var first: Dictionary = memory_updates[0]
		npc.current_gag = {"tag": str(first.get("gagTag", reason)), "stage": str(first.get("stage", "new"))}
		npc.cooldowns["lastReactedAt"] = int(first.get("lastUsedAt", 0))


static func _performance_plan(target_npc_id: StringName, object_id: StringName, stance: Dictionary, memory_updates: Array, trace: Dictionary = {}) -> Dictionary:
	var stage := "new"
	if not memory_updates.is_empty():
		stage = str((memory_updates[0] as Dictionary).get("stage", "new"))
	elif not trace.is_empty():
		stage = str(trace.get("stage", "new"))
	var result := str(stance.get("result", "ambivalent"))
	var pattern := "single_reaction"
	if stage == "new":
		if result == "reject":
			pattern = "reject_object"
		elif result == "want":
			pattern = "want_but_cover"
	elif stage == "repeated":
		pattern = "leak_cover"
	elif stage == "noticed":
		pattern = "preemptive_gag"
	elif stage == "gagged":
		pattern = "gag_callback"
	elif stage == "ritualized":
		pattern = "ritualized_gag"
	return {
		"pattern": pattern,
		"scale": "medium" if stage in ["noticed", "gagged", "ritualized"] else "small",
		"steps": [
			{"actorId": str(target_npc_id), "channel": "gaze", "action": "glance_object", "targetId": str(object_id)},
			{"actorId": str(target_npc_id), "channel": "speech", "targetId": str(object_id)},
		],
		"memoryUpdate": {
			"objectId": str(object_id),
			"npcId": str(target_npc_id),
			"gagTag": str(stance.get("dominantReason", "")),
		},
	}


static func _attach_config(gameplay_config: Dictionary) -> Dictionary:
	var configured: Dictionary = gameplay_config.get("interactionDeltaConfig", gameplay_config.get("interaction_delta_config", {}))
	return _merge_dict(DEFAULT_ATTACH_CONFIG, configured)


static func _heat_delta(social: Dictionary, stance: Dictionary, config: Dictionary) -> int:
	var value := float(config.get("baseHeatDelta", 18))
	var weights: Dictionary = config.get("objectHeatWeights", {})
	for key in weights.keys():
		value += float(social.get(key, 0)) * float(weights[key])
	var stance_delta: Dictionary = config.get("stanceHeatDelta", {})
	value += float(stance_delta.get(str(stance.get("result", "ambivalent")), 0))
	return int(round(value))


static func _relation_delta_for_reason(stance: Dictionary, config: Dictionary) -> Dictionary:
	var base: Dictionary = config.get("relationDelta", {})
	var reason_delta: Dictionary = config.get("reasonRelationDelta", {}).get(str(stance.get("dominantReason", "awkward")), {})
	return _merge_dict(base, reason_delta)


static func _dominant_reason(social: Dictionary, forbidden_pressure: int) -> String:
	if forbidden_pressure > 0:
		return "forbidden"
	var best_key := "utility"
	var best_value := -1
	for key in ["danger", "awkward", "joke", "debt", "status", "utility"]:
		var value := int(social.get(key, 0))
		if value > best_value:
			best_key = key
			best_value = value
	return best_key


static func _upsert_object_link(links: Array, npc_id: StringName, heat_delta: int, stance: Dictionary, config: Dictionary, current_tick: int) -> Dictionary:
	for link in links:
		if link is Dictionary and str(link.get("npcId", "")) == str(npc_id):
			link["heat"] = int(link.get("heat", 0)) + heat_delta
			link["countInScene"] = int(link.get("countInScene", 0)) + 1
			_apply_stage(link, config, current_tick)
			link["lastUsedAt"] = current_tick
			link["gagTag"] = str(stance.get("dominantReason", ""))
			return link
	var created := {
		"npcId": str(npc_id),
		"heat": heat_delta,
		"countInScene": 1,
		"stage": "new",
		"lastUsedAt": current_tick,
		"gagTag": str(stance.get("dominantReason", "")),
	}
	_apply_stage(created, config, current_tick)
	links.append(created)
	return created


static func _apply_stage(link: Dictionary, config: Dictionary, current_tick: int) -> void:
	var thresholds: Dictionary = config.get("stageThresholds", {})
	var heat := int(link.get("heat", 0))
	var target_stage := "new"
	for candidate in ["ritualized", "gagged", "noticed", "repeated", "new"]:
		if heat >= int(thresholds.get(candidate, 0)):
			target_stage = candidate
			break
	var stage := _advance_stage_by_one(str(link.get("stage", "new")), target_stage)
	if str(link.get("stage", "")) != stage:
		link["lastStageChangedAt"] = current_tick
	link["stage"] = stage


static func _advance_stage_by_one(current: String, target: String) -> String:
	var order := ["new", "repeated", "noticed", "gagged", "ritualized"]
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


static func _emotion_for_reason(reason: String, result: String) -> String:
	if reason == "danger":
		return "nervous"
	if reason == "forbidden" or reason == "awkward" or reason == "debt":
		return "awkward" if result != "reject" else "defensive"
	if reason == "joke":
		return "amused"
	if reason == "status":
		return "smug"
	return "curious"


static func _merge_dict(base: Dictionary, override: Variant) -> Dictionary:
	var result := base.duplicate(true)
	if override is Dictionary:
		for key in override.keys():
			if result.get(key) is Dictionary and override[key] is Dictionary:
				result[key] = _merge_dict(result[key], override[key])
			else:
				result[key] = override[key]
	return result
