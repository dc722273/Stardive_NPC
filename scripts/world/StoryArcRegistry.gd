extends RefCounted
class_name StoryArcRegistry

const TodoItemScript := preload("res://scripts/state/TodoItem.gd")

var config: Dictionary = {}
var arcs: Dictionary = {}


func configure(gameplay_config: Dictionary) -> void:
	config = gameplay_config.get("storyArcConfig", {}).duplicate(true)


func observe_event(event, registry, current_tick: int) -> Array:
	if event == null or registry == null or not bool(config.get("enabled", true)):
		return []
	var updates: Array = []
	for raw_template in config.get("templates", _default_templates()):
		if not (raw_template is Dictionary):
			continue
		var template: Dictionary = raw_template
		var update: Dictionary = _observe_template(event, registry, current_tick, template)
		if not update.is_empty():
			updates.append(update)
	return updates


func pending_story_todo(npc, _registry, current_tick: int):
	if npc == null:
		return null
	for arc in arcs.values():
		if not (arc is Dictionary) or not bool(arc.get("active", true)):
			continue
		var participants: Array = _array_from(arc.get("participants", []))
		if not participants.has(str(npc.id)):
			continue
		var stage := str(arc.get("stage", ""))
		var stage_todos: Dictionary = arc.get("stageTodos", {})
		if not stage_todos.has(stage):
			continue
		var last_key := "storyTodo:%s:%s" % [str(arc.get("id", "")), stage]
		if npc.cooldowns.has(last_key):
			continue
		var todo_cfg: Dictionary = stage_todos.get(stage, {})
		var target_id := _other_participant(participants, str(npc.id))
		var todo = TodoItemScript.from_dict({
			"id": "story_%s_%s_%d" % [str(arc.get("type", "arc")), stage, current_tick],
			"intent": str(todo_cfg.get("intent", "talk_to_npc")),
			"target_npc_id": target_id,
			"reason": str(todo_cfg.get("reason", "继续推进正在发生的剧情")),
			"priority": int(arc.get("heat", 0)),
			"status": "pending",
		})
		npc.cooldowns[last_key] = current_tick
		npc.cooldowns["lastStoryArc"] = arc.duplicate(true)
		return todo
	return null


func to_dict() -> Dictionary:
	return {"arcs": arcs.duplicate(true)}


func load_from_dict(data: Dictionary) -> void:
	var raw_arcs: Variant = data.get("arcs", {})
	arcs = raw_arcs.duplicate(true) if raw_arcs is Dictionary else {}


func _observe_template(event, registry, current_tick: int, template: Dictionary) -> Dictionary:
	var participants: Array = _participants_for_event(event)
	if participants.size() < int(template.get("participants", 2)):
		return {}
	var signal_data: Dictionary = template.get("signal", {})
	if not _signal_matches(signal_data, participants, registry):
		return {}
	var arc_id := _arc_id(str(template.get("type", "story_arc")), participants)
	var arc: Dictionary = arcs.get(arc_id, {
		"id": arc_id,
		"type": str(template.get("type", "story_arc")),
		"participants": participants,
		"stage": "",
		"heat": 0,
		"lastEventIds": [],
		"active": true,
		"stageTodos": template.get("stageTodos", {}),
	})
	arc["heat"] = int(arc.get("heat", 0)) + int(template.get("heatDelta", 10))
	arc["lastSeenAt"] = current_tick
	arc["lastEventIds"] = _append_recent_id(arc.get("lastEventIds", []), str(event.id), int(config.get("maxEventIds", 6)))
	arc["stageTodos"] = template.get("stageTodos", {})
	var previous_stage := str(arc.get("stage", ""))
	arc["stage"] = _stage_for_heat(int(arc.get("heat", 0)), template.get("stages", []), previous_stage)
	arcs[arc_id] = arc
	return {
		"arcId": arc_id,
		"type": arc.get("type", ""),
		"participants": participants,
		"stage": arc.get("stage", ""),
		"previousStage": previous_stage,
		"stageChanged": previous_stage != str(arc.get("stage", "")),
		"heat": arc.get("heat", 0),
	}


func _signal_matches(signal_data: Dictionary, participants: Array, registry) -> bool:
	if signal_data.is_empty():
		return true
	if signal_data.has("eventTypes"):
		return true
	var field := str(signal_data.get("relationField", ""))
	if field.is_empty():
		return true
	var threshold := int(signal_data.get("gte", 0))
	for from_id in participants:
		for to_id in participants:
			if from_id == to_id:
				continue
			var memory: Dictionary = registry.relation_memory(StringName(from_id), StringName(to_id))
			if int(memory.get(field, 0)) >= threshold:
				return true
	return false


func _participants_for_event(event) -> Array:
	var payload: Dictionary = event.payload if event != null and event.payload is Dictionary else {}
	var raw: Array = []
	for key in ["npc_ids", "primary_npc_ids"]:
		if payload.get(key, []) is Array:
			raw.append_array(payload.get(key, []))
	raw.append(event.primary_entity_id)
	raw.append(event.target_entity_id)
	if payload.has("previousAnchorNpcId"):
		raw.append(payload.get("previousAnchorNpcId"))
	if payload.has("item_target_id"):
		raw.append(payload.get("item_target_id"))
	var result: Array = []
	for value in raw:
		var id := str(value)
		if id.is_empty() or result.has(id):
			continue
		if id.begins_with("npc_") or id in ["trump", "jd", "musk", "npc_alpha", "npc_beta"]:
			result.append(id)
	return result


func _arc_id(arc_type: String, participants: Array) -> String:
	var sorted: Array = participants.duplicate()
	sorted.sort()
	var parts := PackedStringArray()
	for value in sorted:
		parts.append(str(value))
	return "%s:%s" % [arc_type, ":".join(parts)]


func _stage_for_heat(heat: int, stages: Variant, fallback: String) -> String:
	var current := fallback
	if not (stages is Array):
		return current
	for stage in stages:
		if not (stage is Dictionary):
			continue
		if heat >= int(stage.get("heat", 0)):
			current = str(stage.get("id", current))
	return current


func _append_recent_id(ids: Variant, event_id: String, max_count: int) -> Array:
	var result: Array = ids.duplicate(true) if ids is Array else []
	if not event_id.is_empty():
		result.append(event_id)
	while result.size() > max(1, max_count):
		result.pop_front()
	return result


func _other_participant(participants: Array, npc_id: String) -> String:
	for value in participants:
		if str(value) != npc_id:
			return str(value)
	return ""


func _array_from(value: Variant) -> Array:
	return value.duplicate(true) if value is Array else []


func _default_templates() -> Array:
	return [
		{
			"type": "suspicion_spiral",
			"participants": 2,
			"signal": {"relationField": "suspicion", "gte": 35},
			"heatDelta": 18,
			"stages": [{"id": "spark", "heat": 20}, {"id": "accusation", "heat": 55}, {"id": "rupture", "heat": 85}],
			"stageTodos": {
				"accusation": {"intent": "talk_to_npc", "reason": "追问对方刚才到底隐瞒了什么"},
				"rupture": {"intent": "talk_to_npc", "reason": "把积累的怀疑当面摊开"},
			},
		},
		{
			"type": "debt_chain",
			"participants": 2,
			"signal": {"relationField": "debt", "gte": 35},
			"heatDelta": 14,
			"stages": [{"id": "favor", "heat": 20}, {"id": "pressure", "heat": 50}, {"id": "payoff", "heat": 80}],
			"stageTodos": {
				"pressure": {"intent": "talk_to_npc", "reason": "把这笔人情账说清楚"},
				"payoff": {"intent": "talk_to_npc", "reason": "要求对方给一个交代"},
			},
		},
	]
