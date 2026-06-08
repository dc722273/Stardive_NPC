extends RefCounted
class_name NPCExecutionLoop

const ConstantsScript := preload("res://scripts/core/Constants.gd")
const NPCMoverScript := preload("res://scripts/npc/NPCMover.gd")
const InteractionDeltaRulesScript := preload("res://scripts/world/InteractionDeltaRules.gd")

var entity_registry = null
var place_registry = null
var pathfinder = null
var event_log = null
var todo_executor = null
var action_scheduler = null
var relationship_decision_service = null
var story_arc_registry = null
var gameplay_config: Dictionary = {}
var npc_movers: Dictionary = {}
var paused_checker: Callable
var event_rememberer: Callable
var visual_syncer: Callable


func configure(context: Dictionary) -> void:
	entity_registry = context.get("entity_registry")
	place_registry = context.get("place_registry")
	pathfinder = context.get("pathfinder")
	event_log = context.get("event_log")
	todo_executor = context.get("todo_executor")
	action_scheduler = context.get("action_scheduler")
	relationship_decision_service = context.get("relationship_decision_service")
	story_arc_registry = context.get("story_arc_registry")
	gameplay_config = context.get("gameplay_config", {})
	npc_movers = context.get("npc_movers", npc_movers)
	paused_checker = context.get("paused_checker", Callable())
	event_rememberer = context.get("event_rememberer", Callable())
	visual_syncer = context.get("visual_syncer", Callable())


func tick(current_tick: int) -> void:
	if entity_registry == null or todo_executor == null:
		return
	for npc in entity_registry.npcs.values():
		_decide_one_npc(npc, current_tick)


func decide_one_npc(npc, current_tick: int) -> void:
	_decide_one_npc(npc, current_tick)


func advance(delta: float, current_tick: int) -> void:
	if entity_registry == null:
		return
	for npc in entity_registry.npcs.values():
		if _is_paused(npc.id):
			continue
		var mover = npc_movers.get(npc.id)
		if mover == null or mover.is_idle():
			continue
		var result: Dictionary = mover.advance(npc, delta)
		if bool(result.get("done", false)):
			_complete_active_todo(npc, mover, current_tick)


func record_npc_todo_experience(npc, todo, event_type: StringName, reason: StringName, success: bool, current_tick: int):
	if npc == null or todo == null or event_log == null or not event_log.has_method("record"):
		return null
	var target_id := todo_target_id(todo)
	var target_type := todo_target_type(todo)
	var payload := {
		"todo_id": todo.id,
		"intent": str(todo.intent),
		"todo_reason": str(todo.reason),
		"success": success,
		"reason": str(reason),
	}
	var delta := InteractionDeltaRulesScript.apply_npc_experience_event(npc, event_type, todo, target_id, target_type, entity_registry, gameplay_config, current_tick, success, reason)
	if not delta.is_empty():
		payload["npc_experience_delta"] = delta
		payload["experience_memory"] = npc.experience_memory.duplicate(true)
		payload["relation_memory_updates"] = delta.get("relationMemoryUpdates", [])
	return event_log.record(event_type, npc.id, target_id, target_type, npc.current_cell, payload, npc.id, current_tick)


func npc_todo_event_type(todo) -> StringName:
	if todo == null:
		return &"npc_completed_todo"
	if todo.intent == &"visit_place":
		return &"npc_visited_place"
	if todo.intent == &"talk_to_npc":
		return &"npc_talked_to_npc"
	if todo.intent == &"inspect_item":
		return &"npc_inspected_item"
	if todo.intent == &"rest":
		return &"npc_rested"
	if todo.intent == &"wander":
		return &"npc_wandered"
	return &"npc_completed_todo"


func todo_target_id(todo) -> StringName:
	if todo == null:
		return &""
	if todo.intent == &"visit_place":
		return todo.target_place_id
	if todo.intent == &"talk_to_npc":
		return todo.target_npc_id
	if todo.intent == &"inspect_item":
		return todo.target_item_id
	return &""


func todo_target_type(todo) -> StringName:
	if todo == null:
		return &"cell"
	if todo.intent == &"visit_place":
		return &"place"
	if todo.intent == &"talk_to_npc":
		return &"npc"
	if todo.intent == &"inspect_item":
		return &"item"
	return &"cell"


func _decide_one_npc(npc, current_tick: int) -> void:
	if npc == null or not (npc.todo_list is Array):
		return
	if _is_paused(npc.id):
		return
	var mover = _mover_for(npc)
	if not mover.is_idle():
		return
	var emergent_todo = _maybe_create_emergent_todo(npc, current_tick)
	if emergent_todo != null:
		npc.todo_list.append(emergent_todo)
	var todo = _next_pending_todo(npc)
	if todo == null:
		return
	var lane_action := {"id": StringName("exec_%s_%s" % [str(npc.id), str(todo.id)]), "npc_id": npc.id, "lane": &"movement"}
	if action_scheduler != null:
		var lane_result: Dictionary = action_scheduler.start_action(lane_action)
		if not bool(lane_result.get("accepted", false)):
			return
	var ctx := {"entity_registry": entity_registry, "place_registry": place_registry, "pathfinder": pathfinder, "event_log": event_log, "mover": mover}
	var resolved: Dictionary = todo_executor._target_world_pos(todo, ctx, npc)
	if not bool(resolved.get("ok", false)):
		var blocked_event = record_npc_todo_experience(npc, todo, &"npc_todo_blocked", &"blocked", false, current_tick)
		todo_executor.mark_todo_blocked(npc, todo)
		_remember_event(blocked_event, [npc.id])
		if action_scheduler != null:
			action_scheduler.finish_action(npc.id, &"movement")
		return
	mover.begin_move(npc, resolved.get("world_pos"), resolved.get("interact_target"), todo, float(resolved.get("arrival_radius", ConstantsScript.INTERACT_RADIUS)))
	todo.status = &"active"
	_sync_visuals(npc, _todo_bubble_text(npc, todo))


func _maybe_create_emergent_todo(npc, current_tick: int):
	if story_arc_registry != null and story_arc_registry.has_method("pending_story_todo"):
		var story_todo = story_arc_registry.pending_story_todo(npc, entity_registry, current_tick)
		if story_todo != null:
			return story_todo
	if relationship_decision_service != null and relationship_decision_service.has_method("maybe_create_todo"):
		return relationship_decision_service.maybe_create_todo(npc, entity_registry, current_tick)
	return null


func _complete_active_todo(npc, mover, current_tick: int) -> void:
	var todo = mover.current_todo
	if todo != null:
		todo.status = &"done"
		var event = record_npc_todo_experience(npc, todo, npc_todo_event_type(todo), &"", true, current_tick)
		_remember_event(event, [npc.id])
	if action_scheduler != null:
		action_scheduler.finish_action(npc.id, &"movement")
	mover.reset()


func _next_pending_todo(npc):
	var best = null
	for todo in npc.todo_list:
		if todo == null or not (todo is Object) or StringName(todo.status) != &"pending":
			continue
		if best == null or int(todo.priority) > int(best.priority):
			best = todo
	return best


func _mover_for(npc):
	var key: StringName = npc.id
	if npc_movers.has(key):
		return npc_movers[key]
	var mover = NPCMoverScript.new()
	mover.configure(entity_registry, place_registry, pathfinder, event_log)
	npc_movers[key] = mover
	return mover


func _is_paused(npc_id: StringName) -> bool:
	return bool(paused_checker.call(npc_id)) if paused_checker.is_valid() else false


func _remember_event(event, npc_ids: Array) -> void:
	if event != null and event_rememberer.is_valid():
		event_rememberer.call(event, npc_ids)


func _sync_visuals(npc, bubble_text: String) -> void:
	if visual_syncer.is_valid():
		visual_syncer.call(npc, bubble_text)


func _todo_bubble_text(npc, todo) -> String:
	if npc == null or todo == null:
		return ""
	if StringName(todo.intent) == &"talk_to_npc":
		var relation_text := _relation_talk_bubble_text(npc, todo)
		if not relation_text.is_empty():
			return relation_text
	return str(todo.reason)


func _relation_talk_bubble_text(npc, todo) -> String:
	if entity_registry == null or not entity_registry.has_method("relation_memory"):
		return ""
	var target_id := StringName(todo.target_npc_id)
	if target_id == &"":
		return ""
	var memory: Dictionary = entity_registry.relation_memory(npc.id, target_id)
	if memory.is_empty():
		return ""
	var rule := _relation_talk_rule(memory)
	if rule.is_empty():
		return ""
	var target_name := _npc_name(target_id)
	return _format_template(str(rule.get("line", "")), {
		"from_id": str(npc.id),
		"from_name": _npc_name(npc.id),
		"target_id": str(target_id),
		"target_name": target_name,
		"field": str(rule.get("field", "")),
		"value": int(rule.get("_value", 0)),
	})


func _relation_talk_rule(memory: Dictionary) -> Dictionary:
	var cfg: Dictionary = gameplay_config.get("npcExecutionVisual", {}).get("relationTalk", {})
	if not bool(cfg.get("enabled", true)):
		return {}
	var best: Dictionary = {}
	for raw_rule in cfg.get("rules", []):
		if not (raw_rule is Dictionary):
			continue
		var rule: Dictionary = raw_rule
		var field := str(rule.get("field", ""))
		if field.is_empty():
			continue
		var value := int(memory.get(field, 0))
		if value < int(rule.get("gte", 0)):
			continue
		var score := float(value) * float(rule.get("weight", 1.0))
		if best.is_empty() or score > float(best.get("_score", -1.0)):
			best = rule.duplicate(true)
			best["_score"] = score
			best["_value"] = value
	return best


func _npc_name(npc_id: StringName) -> String:
	if entity_registry != null and entity_registry.get("npcs") is Dictionary:
		var npcs: Dictionary = entity_registry.get("npcs")
		if npcs.has(npc_id):
			return str(npcs[npc_id].name)
		if npcs.has(str(npc_id)):
			return str(npcs[str(npc_id)].name)
	return str(npc_id)


func _format_template(template: String, values: Dictionary) -> String:
	var result := template
	for key in values.keys():
		result = result.replace("{%s}" % str(key), str(values[key]))
	return result
