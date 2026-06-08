extends RefCounted
class_name RelationshipDecisionService

const TodoItemScript := preload("res://scripts/state/TodoItem.gd")

var config: Dictionary = {}


func configure(gameplay_config: Dictionary) -> void:
	config = gameplay_config.get("relationshipDecisionConfig", {}).duplicate(true)


func maybe_create_todo(npc, registry, current_tick: int):
	if npc == null or registry == null or not bool(config.get("enabled", true)):
		return null
	if _has_duplicate_relationship_todo(npc):
		return null
	var motive := strongest_motive(npc, registry, current_tick)
	if motive.is_empty():
		return null
	var todo = TodoItemScript.from_dict({
		"id": "rel_%s_%s_%d" % [str(npc.id), str(motive.get("motive", "motive")), current_tick],
		"intent": str(motive.get("intent", "talk_to_npc")),
		"target_npc_id": str(motive.get("targetNpcId", "")),
		"reason": str(motive.get("reason", "")),
		"priority": int(motive.get("score", 0)),
		"status": "pending",
	})
	npc.cooldowns["lastRelationshipDecisionAt"] = current_tick
	npc.cooldowns["lastRelationshipMotive"] = motive.duplicate(true)
	return todo


func strongest_motive(npc, registry, current_tick: int) -> Dictionary:
	var cooldown := int(config.get("cooldownTicks", 120))
	if current_tick - int(npc.cooldowns.get("lastRelationshipDecisionAt", -cooldown)) < cooldown:
		return {}
	var memories: Dictionary = registry.relation_memories if registry != null and registry.get("relation_memories") is Dictionary else {}
	var best := {}
	for memory in memories.values():
		if not (memory is Dictionary) or StringName(memory.get("fromNpcId", "")) != npc.id:
			continue
		var candidate := _motive_from_memory(npc, memory)
		if candidate.is_empty():
			continue
		if best.is_empty() or int(candidate.get("score", 0)) > int(best.get("score", 0)):
			best = candidate
	var min_score := int(config.get("minScore", 45))
	if int(best.get("score", 0)) < min_score:
		return {}
	return best


func _motive_from_memory(npc, memory: Dictionary) -> Dictionary:
	var best := {}
	for raw_rule in config.get("rules", _default_rules()):
		if not (raw_rule is Dictionary):
			continue
		var rule: Dictionary = raw_rule
		var field := str(rule.get("field", ""))
		if field.is_empty():
			continue
		var value := int(memory.get(field, 0))
		if rule.has("gte") and value < int(rule.get("gte", 0)):
			continue
		if rule.has("lte") and value > int(rule.get("lte", 100)):
			continue
		var score := int(round(float(value) * float(rule.get("weight", 1.0))))
		var candidate := {
			"targetNpcId": str(memory.get("toNpcId", "")),
			"motive": str(rule.get("motive", field)),
			"intent": str(rule.get("intent", "talk_to_npc")),
			"score": score,
			"field": field,
			"value": value,
			"reason": _reason_text(npc, memory, rule, value),
		}
		if best.is_empty() or score > int(best.get("score", 0)):
			best = candidate
	return best


func _reason_text(npc, memory: Dictionary, rule: Dictionary, value: int) -> String:
	var template := str(rule.get("reason", "{npc_id}因为{field}={value}，主动回应{target_id}"))
	return template.format({
		"npc_id": str(npc.id),
		"target_id": str(memory.get("toNpcId", "")),
		"field": str(rule.get("field", "")),
		"value": str(value),
		"motive": str(rule.get("motive", "")),
	})


func _has_duplicate_relationship_todo(npc) -> bool:
	for todo in npc.todo_list:
		if todo == null:
			continue
		var status := StringName(todo.get("status"))
		if status != &"pending" and status != &"active":
			continue
		if str(todo.get("id")).begins_with("rel_"):
			return true
	return false


func _default_rules() -> Array:
	return [
		{"field": "warmth", "gte": 45, "motive": "seek_closeness", "intent": "talk_to_npc", "weight": 1.0, "reason": "{npc_id}对{target_id}有好感，主动靠近说话"},
		{"field": "suspicion", "gte": 35, "motive": "confront", "intent": "talk_to_npc", "weight": 1.25, "reason": "{npc_id}怀疑{target_id}，准备当面试探"},
		{"field": "awkward", "gte": 45, "motive": "clear_air", "intent": "talk_to_npc", "weight": 1.05, "reason": "{npc_id}觉得和{target_id}之间有尴尬，想把话说开"},
		{"field": "debt", "gte": 35, "motive": "settle_debt", "intent": "talk_to_npc", "weight": 1.15, "reason": "{npc_id}记着和{target_id}的人情账"},
		{"field": "fun", "gte": 45, "motive": "tease", "intent": "talk_to_npc", "weight": 1.0, "reason": "{npc_id}觉得{target_id}这里有乐子，又想去逗一句"},
	]
