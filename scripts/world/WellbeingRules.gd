extends RefCounted
class_name WellbeingRules


static func assign_daily_problem(npcs: Dictionary, config: Dictionary, day: int = 1) -> Dictionary:
	var ids := _candidate_npc_ids(npcs, config)
	if ids.is_empty():
		return {}
	var problems: Array = config.get("problemRotation", [])
	if problems.is_empty():
		problems = config.get("problems", {}).keys()
	if problems.is_empty():
		return {}
	var npc_id := StringName(ids[(max(1, day) - 1) % ids.size()])
	var problem := str(problems[(max(1, day) - 1) % problems.size()])
	var npc = npcs.get(npc_id)
	if npc == null:
		return {}
	var current: Dictionary = npc.wellbeing if npc.wellbeing is Dictionary else {}
	if _is_active(current, config):
		return current.duplicate(true)
	npc.wellbeing = {
		"state": "down",
		"problem": problem,
		"startedDay": day,
		"resolved": false,
	}
	return npc.wellbeing.duplicate(true)


static func evaluate_event(event, target_npc, item, config: Dictionary) -> Dictionary:
	if event == null or target_npc == null:
		return {}
	var wellbeing: Dictionary = target_npc.wellbeing if target_npc.wellbeing is Dictionary else {}
	if not _is_active(wellbeing, config):
		return {}
	var problem := str(wellbeing.get("problem", ""))
	if problem.is_empty():
		return {}
	var problems: Dictionary = config.get("problems", {})
	var problem_cfg: Dictionary = problems.get(problem, {})
	var judgement := _match_judgement(event, item, problem_cfg, config)
	if judgement.is_empty():
		return {}
	var next_state := str(judgement.get("nextNpcState", wellbeing.get("state", "down")))
	var result := str(judgement.get("result", "neutral"))
	var updated := wellbeing.duplicate(true)
	updated["state"] = next_state
	updated["lastResult"] = result
	updated["lastReason"] = str(judgement.get("reason", "unmatched_need"))
	updated["resolved"] = _resolved_states(config).has(next_state)
	target_npc.wellbeing = updated
	judgement["npcId"] = str(target_npc.id)
	judgement["problem"] = problem
	judgement["previousNpcState"] = str(wellbeing.get("state", "down"))
	judgement["resultLabel"] = _feedback_tags(config).get(result, result)
	return judgement


static func problem_visual(problem: String, config: Dictionary) -> Dictionary:
	var problems: Dictionary = config.get("problems", {})
	return problems.get(problem, {}).duplicate(true)


static func _match_judgement(event, item, problem_cfg: Dictionary, config: Dictionary) -> Dictionary:
	var rules: Array = problem_cfg.get("judgementRules", [])
	for raw_rule in rules:
		if not (raw_rule is Dictionary):
			continue
		var rule: Dictionary = raw_rule
		if not _event_type_matches(event, rule):
			continue
		if not _conditions_match(rule.get("conditions", []), event, item):
			continue
		return {
			"result": str(rule.get("result", "neutral")),
			"nextNpcState": str(rule.get("nextNpcState", "down")),
			"reason": str(rule.get("reason", "unmatched_need")),
		}
	var fallback: Dictionary = config.get("defaultJudgement", {})
	return {
		"result": str(fallback.get("result", "neutral")),
		"nextNpcState": str(fallback.get("nextNpcState", "down")),
		"reason": str(fallback.get("reason", "unmatched_need")),
	}


static func _event_type_matches(event, rule: Dictionary) -> bool:
	var types: Variant = rule.get("eventTypes", [])
	if not (types is Array):
		return false
	return types.has(str(event.type)) or types.has(event.type)


static func _conditions_match(conditions: Variant, event, item) -> bool:
	if not (conditions is Array):
		return true
	for raw_condition in conditions:
		if not (raw_condition is Dictionary):
			continue
		if not _condition_matches(raw_condition, event, item):
			return false
	return true


static func _condition_matches(condition: Dictionary, event, item) -> bool:
	var value: Variant = _condition_value(condition, event, item)
	if condition.has("gte") and not (float(value) >= float(condition.get("gte", 0))):
		return false
	if condition.has("lte") and not (float(value) <= float(condition.get("lte", 0))):
		return false
	if condition.has("eq") and str(value) != str(condition.get("eq", "")):
		return false
	if condition.has("equalsTargetNpc") and bool(condition.get("equalsTargetNpc", false)):
		if str(value) != str(event.target_entity_id if event != null else ""):
			return false
	if condition.has("in"):
		var values: Variant = condition.get("in", [])
		if not (values is Array) or not values.has(str(value)):
			return false
	return true


static func _condition_value(condition: Dictionary, event, item) -> Variant:
	var source := str(condition.get("source", "payload"))
	var field := str(condition.get("field", ""))
	if source == "object_social":
		if item != null and item.get("social") is Dictionary:
			return item.social.get(field, 0)
		var payload: Dictionary = event.payload if event != null and event.payload is Dictionary else {}
		var social: Dictionary = payload.get("object_social", {})
		return social.get(field, 0)
	if source == "item":
		if item != null:
			return item.get(field)
		var payload: Dictionary = event.payload if event != null and event.payload is Dictionary else {}
		return payload.get(field, null)
	if source == "classification":
		var classification: Dictionary = {}
		if item != null and item.get("classification") is Dictionary:
			classification = item.classification
		else:
			var payload: Dictionary = event.payload if event != null and event.payload is Dictionary else {}
			classification = payload.get("object_classification", {})
		return classification.get(field, "")
	var payload: Dictionary = event.payload if event != null and event.payload is Dictionary else {}
	return payload.get(field, null)


static func _candidate_npc_ids(npcs: Dictionary, config: Dictionary) -> Array:
	var configured: Array = config.get("candidateNpcIds", [])
	var ids: Array[StringName] = []
	if not configured.is_empty():
		for raw_id in configured:
			var npc_id := StringName(raw_id)
			if npcs.has(npc_id):
				ids.append(npc_id)
		return ids
	for npc_id in npcs.keys():
		ids.append(StringName(npc_id))
	ids.sort_custom(func(left: StringName, right: StringName) -> bool:
		return str(left) < str(right)
	)
	return ids


static func _is_active(wellbeing: Dictionary, config: Dictionary) -> bool:
	var state := str(wellbeing.get("state", config.get("defaultState", "normal")))
	return _active_states(config).has(state)


static func _active_states(config: Dictionary) -> Array:
	var states: Array = config.get("activeStates", [])
	return states


static func _resolved_states(config: Dictionary) -> Array:
	var states: Array = config.get("resolvedStates", [])
	return states


static func _feedback_tags(config: Dictionary) -> Dictionary:
	var tags: Dictionary = config.get("feedbackTags", {})
	return tags
