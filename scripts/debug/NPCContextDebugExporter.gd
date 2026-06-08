extends RefCounted
class_name NPCContextDebugExporter

const InteractionEventScript := preload("res://scripts/state/InteractionEvent.gd")

var entity_registry = null
var place_registry = null
var pathfinder = null
var event_log = null
var daily_todo_planner = null
var npc_feedback_builder = null
var gameplay_config: Dictionary = {}
var tick: int = 0
var output_dir: String = "res://debug"


func configure(options: Dictionary) -> void:
	entity_registry = options.get("entity_registry", null)
	place_registry = options.get("place_registry", null)
	pathfinder = options.get("pathfinder", null)
	event_log = options.get("event_log", null)
	daily_todo_planner = options.get("daily_todo_planner", null)
	npc_feedback_builder = options.get("npc_feedback_builder", null)
	gameplay_config = _dict_from(options.get("gameplay_config", {}))
	tick = int(options.get("tick", 0))
	output_dir = str(options.get("output_dir", output_dir))


func export_all() -> Dictionary:
	var dump := build_dump()
	var timestamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace("T", "_")
	var dir_path := ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var json_path := dir_path.path_join("npc_context_dump_%s.json" % timestamp)
	var md_path := dir_path.path_join("npc_context_dump_%s.md" % timestamp)
	var latest_json_path := dir_path.path_join("npc_context_dump_latest.json")
	var latest_md_path := dir_path.path_join("npc_context_dump_latest.md")
	var json_text := JSON.stringify(dump, "\t")
	var markdown_text := _dump_markdown(dump)
	var ok := _write_text(json_path, json_text)
	ok = _write_text(md_path, markdown_text) and ok
	ok = _write_text(latest_json_path, json_text) and ok
	ok = _write_text(latest_md_path, markdown_text) and ok
	return {
		"ok": ok,
		"json_path": json_path,
		"markdown_path": md_path,
		"latest_json_path": latest_json_path,
		"latest_markdown_path": latest_md_path,
		"npc_count": _npc_ids().size(),
	}


func build_dump() -> Dictionary:
	var world := {
		"entity_registry": entity_registry,
		"place_registry": place_registry,
		"pathfinder": pathfinder,
		"event_log": event_log,
	}
	var latest_event = _latest_event()
	var result := {
		"generated_at": Time.get_datetime_string_from_system(false, true),
		"tick": tick,
		"notes": [
			"planner_messages 是每日行动规划入模上下文。",
			"feedback_messages_for_latest_event 是最近事件下该 NPC 真实会交给互动反馈 LLM 的 messages。",
			"feedback_messages 只包含当前发言 NPC 自己的 tags/style/runtime/relation memory，不会自动包含其他 NPC 的设定。",
		],
		"scene": {
			"spawned_npc_ids": _npc_ids(),
			"spawned_item_ids": _item_ids(),
			"latest_event": _event_dict(latest_event),
		},
		"relation_memories": _relation_memories(),
		"interaction_traces": _interaction_traces(),
		"npcs": [],
	}
	for npc_id in _npc_ids():
		var npc = _npc_by_id(StringName(npc_id))
		if npc == null:
			continue
		var npc_dump := {
			"id": str(npc.id),
			"name": str(npc.name),
			"profile": npc.profile_dict() if npc.has_method("profile_dict") else {},
			"runtime": npc.runtime_dict() if npc.has_method("runtime_dict") else {},
			"current_cell": {"x": npc.current_cell.x, "y": npc.current_cell.y},
			"position": {"x": npc.position.x, "y": npc.position.y},
			"held_items": _held_items_for_npc(npc.id),
			"todo_list": _todo_list(npc),
			"recent_events": _recent_events(npc),
			"outgoing_relation_memories": _relations_from(npc.id),
			"incoming_relation_memories": _relations_to(npc.id),
			"planner_messages": _planner_messages(npc, world),
			"feedback_messages_for_latest_event": _feedback_messages(npc, latest_event, world),
		}
		result["npcs"].append(npc_dump)
	return result


func _planner_messages(npc, world: Dictionary) -> Array:
	if daily_todo_planner == null or not daily_todo_planner.has_method("build_prompt"):
		return []
	return daily_todo_planner.build_prompt(npc, world)


func _feedback_messages(npc, event, world: Dictionary) -> Array:
	if event == null or npc_feedback_builder == null:
		return []
	if not npc_feedback_builder.has_method("build_feedback"):
		return []
	var feedback: Dictionary = npc_feedback_builder.build_feedback(event, npc, world)
	if not npc_feedback_builder.has_method("_build_feedback_messages"):
		return []
	return npc_feedback_builder._build_feedback_messages(feedback, event, npc)


func _latest_event():
	if event_log == null:
		return null
	var events: Variant = event_log.get("events") if event_log is Object else []
	if not (events is Array) or events.is_empty():
		return null
	return events[events.size() - 1]


func _event_dict(event) -> Dictionary:
	if event == null:
		return {}
	if event is Object and event.has_method("to_dict"):
		return event.to_dict()
	if event is Dictionary:
		return event.duplicate(true)
	return {}


func _npc_ids() -> Array:
	var ids := []
	var npcs: Variant = entity_registry.get("npcs") if entity_registry is Object else {}
	if not (npcs is Dictionary):
		return ids
	for key in npcs.keys():
		ids.append(str(key))
	ids.sort()
	return ids


func _item_ids() -> Array:
	var ids := []
	var items: Variant = entity_registry.get("items") if entity_registry is Object else {}
	if not (items is Dictionary):
		return ids
	for key in items.keys():
		ids.append(str(key))
	ids.sort()
	return ids


func _npc_by_id(npc_id: StringName):
	var npcs: Variant = entity_registry.get("npcs") if entity_registry is Object else {}
	if npcs is Dictionary and npcs.has(npc_id):
		return npcs[npc_id]
	return null


func _held_items_for_npc(npc_id: StringName) -> Array:
	var result := []
	var items: Variant = entity_registry.get("items") if entity_registry is Object else {}
	if not (items is Dictionary):
		return result
	for item in items.values():
		if item == null or not item.has_method("anchor_npc_id") or item.anchor_npc_id() != npc_id:
			continue
		result.append(_item_summary(item))
	return result


func _item_summary(item) -> Dictionary:
	return {
		"id": str(item.id),
		"name": str(item.name),
		"ownerId": str(item.owner_id),
		"currentAnchor": item.current_anchor.duplicate(true),
		"custodyState": str(item.custody_state),
		"classification": item.classification.duplicate(true),
		"social": item.social.duplicate(true),
		"memory": item.memory.duplicate(true),
	}


func _todo_list(npc) -> Array:
	var result := []
	var todos: Variant = npc.todo_list if npc != null else []
	if not (todos is Array):
		return result
	for todo in todos:
		if todo is Object and todo.has_method("to_dict"):
			result.append(todo.to_dict())
		elif todo is Dictionary:
			result.append(todo.duplicate(true))
	return result


func _recent_events(npc) -> Array:
	var result := []
	var raw_events: Variant = npc.recent_events if npc != null else []
	if not (raw_events is Array):
		return result
	for event in raw_events:
		result.append(_event_dict(event))
	return result


func _relation_memories() -> Array:
	var memories: Variant = entity_registry.get("relation_memories") if entity_registry is Object else {}
	if not (memories is Dictionary):
		return []
	return _sorted_dict_values(memories)


func _interaction_traces() -> Array:
	var traces: Variant = entity_registry.get("interaction_traces") if entity_registry is Object else {}
	if not (traces is Dictionary):
		return []
	return _sorted_dict_values(traces)


func _relations_from(npc_id: StringName) -> Array:
	var result := []
	for memory in _relation_memories():
		if memory is Dictionary and str(memory.get("fromNpcId", "")) == str(npc_id):
			result.append(memory)
	return result


func _relations_to(npc_id: StringName) -> Array:
	var result := []
	for memory in _relation_memories():
		if memory is Dictionary and str(memory.get("toNpcId", "")) == str(npc_id):
			result.append(memory)
	return result


func _sorted_dict_values(values: Dictionary) -> Array:
	var keys := values.keys()
	keys.sort_custom(func(left, right) -> bool:
		return str(left) < str(right)
	)
	var result := []
	for key in keys:
		var value = values[key]
		result.append(value.duplicate(true) if value is Dictionary else value)
	return result


func _dump_markdown(dump: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("# NPC Context Dump")
	lines.append("")
	lines.append("- generated_at: `%s`" % str(dump.get("generated_at", "")))
	lines.append("- tick: `%s`" % str(dump.get("tick", "")))
	lines.append("- spawned_npc_ids: `%s`" % str(dump.get("scene", {}).get("spawned_npc_ids", [])))
	lines.append("- spawned_item_ids: `%s`" % str(dump.get("scene", {}).get("spawned_item_ids", [])))
	lines.append("")
	lines.append("## Notes")
	for note in dump.get("notes", []):
		lines.append("- %s" % str(note))
	lines.append("")
	lines.append("## Latest Event")
	lines.append("```json")
	lines.append(JSON.stringify(dump.get("scene", {}).get("latest_event", {}), "\t"))
	lines.append("```")
	lines.append("")
	for npc in dump.get("npcs", []):
		lines.append("## %s (%s)" % [str(npc.get("name", "")), str(npc.get("id", ""))])
		lines.append("")
		lines.append("### Profile")
		lines.append("```json")
		lines.append(JSON.stringify(npc.get("profile", {}), "\t"))
		lines.append("```")
		lines.append("")
		lines.append("### Runtime")
		lines.append("```json")
		lines.append(JSON.stringify(npc.get("runtime", {}), "\t"))
		lines.append("```")
		lines.append("")
		lines.append("### Relation Memories")
		lines.append("```json")
		lines.append(JSON.stringify({
			"outgoing": npc.get("outgoing_relation_memories", []),
			"incoming": npc.get("incoming_relation_memories", []),
		}, "\t"))
		lines.append("```")
		lines.append("")
		lines.append("### Todos / Held Items / Recent Events")
		lines.append("```json")
		lines.append(JSON.stringify({
			"held_items": npc.get("held_items", []),
			"todo_list": npc.get("todo_list", []),
			"recent_events": npc.get("recent_events", []),
		}, "\t"))
		lines.append("```")
		lines.append("")
		lines.append("### Planner Messages")
		lines.append("```json")
		lines.append(JSON.stringify(npc.get("planner_messages", []), "\t"))
		lines.append("```")
		lines.append("")
		lines.append("### Feedback Messages For Latest Event")
		lines.append("```json")
		lines.append(JSON.stringify(npc.get("feedback_messages_for_latest_event", []), "\t"))
		lines.append("```")
		lines.append("")
	return "\n".join(lines)


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[NPCContextDebugExporter] Failed to write %s" % path)
		return false
	file.store_string(text)
	file.close()
	return true


func _dict_from(value: Variant) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else {}
