extends RefCounted
class_name WorldEntityRegistry

const ConstantsScript := preload("res://scripts/core/Constants.gd")
const ItemStateScript := preload("res://scripts/state/ItemState.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")

var npcs: Dictionary = {}
var items: Dictionary = {}
var object_types: Dictionary = {}
var relation_memories: Dictionary = {}
var interaction_traces: Dictionary = {}
var map_bounds: Rect2i = Rect2i()
var blocked_cells: Dictionary = {}
var repair_warnings: Array = []
var interaction_stage_thresholds: Dictionary = {
	"new": 0,
	"repeated": 35,
	"noticed": 70,
	"gagged": 105,
	"ritualized": 140,
}


func set_map_bounds(bounds: Rect2i) -> void:
	map_bounds = bounds


func set_object_types(types: Dictionary) -> void:
	object_types = types.duplicate(true)


func set_interaction_stage_thresholds(thresholds: Dictionary) -> void:
	if thresholds.is_empty():
		return
	for key in thresholds.keys():
		interaction_stage_thresholds[str(key)] = int(thresholds[key])


func set_blocked_cell(cell: Vector2i, blocked: bool = true) -> void:
	if blocked:
		blocked_cells[cell] = true
	else:
		blocked_cells.erase(cell)


func add_npc(npc) -> void:
	npcs[npc.id] = npc


func add_item(item) -> void:
	items[item.id] = item


func apply_relation_delta(from_npc_id: StringName, to_npc_id: StringName, delta: Dictionary, tag: String = "", current_tick: int = 0) -> Dictionary:
	if from_npc_id == &"" or to_npc_id == &"" or from_npc_id == to_npc_id:
		return {}
	var key := _relation_key(from_npc_id, to_npc_id)
	var memory: Dictionary = relation_memories.get(key, {
		"fromNpcId": str(from_npc_id),
		"toNpcId": str(to_npc_id),
		"attention": 0,
		"warmth": 0,
		"awkward": 0,
		"suspicion": 0,
		"debt": 0,
		"fun": 0,
		"tags": [],
	})
	for field in ["attention", "warmth", "awkward", "suspicion", "debt", "fun"]:
		memory[field] = clampi(int(memory.get(field, 0)) + int(delta.get(field, 0)), 0, 100)
	if not tag.is_empty():
		_upsert_relation_tag(memory, tag, int(delta.get("fun", 1)) + int(delta.get("attention", 1)), current_tick)
	relation_memories[key] = memory
	return memory.duplicate(true)


func relation_memory(from_npc_id: StringName, to_npc_id: StringName) -> Dictionary:
	return relation_memories.get(_relation_key(from_npc_id, to_npc_id), {}).duplicate(true)


func update_interaction_trace(event_type: String, object_id: StringName, target_npc_id: StringName, heat_delta: int, heat_decay: float, current_tick: int) -> Dictionary:
	if object_id == &"" or target_npc_id == &"":
		return {}
	var key := _interaction_trace_key(event_type, object_id, target_npc_id)
	var had_existing := interaction_traces.has(key)
	var trace: Dictionary = interaction_traces.get(key, {
		"key": key,
		"eventType": event_type,
		"objectId": str(object_id),
		"targetNpcId": str(target_npc_id),
		"countInWindow": 0,
		"heat": 0,
		"firstSeenAt": current_tick,
		"lastSeenAt": current_tick,
		"stage": "new",
	})
	trace["countInWindow"] = int(trace.get("countInWindow", 0)) + 1
	trace["lastSeenAt"] = current_tick
	trace["heat"] = int(round(float(trace.get("heat", 0)) * heat_decay + float(heat_delta)))
	if had_existing:
		trace["stage"] = _advance_stage_by_one(str(trace.get("stage", "new")), _trace_stage_by_heat(int(trace["heat"])))
	else:
		trace["stage"] = "new"
	interaction_traces[key] = trace
	return trace.duplicate(true)


func interaction_trace(object_id: StringName, target_npc_id: StringName, event_type: String = "attach_object_to_npc") -> Dictionary:
	return interaction_traces.get(_interaction_trace_key(event_type, object_id, target_npc_id), {}).duplicate(true)


func decay_interaction_memories(config: Dictionary, current_tick: int) -> void:
	var trace_expire_ticks := int(config.get("traceExpireTicks", 1800))
	var scene_tick_decay := float(config.get("sceneTickDecay", 0.98))
	var remove_below_heat := int(config.get("removeBelowHeat", 15))
	for key in interaction_traces.keys().duplicate():
		var trace: Dictionary = interaction_traces[key]
		if current_tick - int(trace.get("lastSeenAt", 0)) > trace_expire_ticks and int(trace.get("countInWindow", 0)) < 2:
			interaction_traces.erase(key)
	for item in items.values():
		var memory: Dictionary = item.memory if item.memory is Dictionary else {"topLinks": []}
		var links: Array = memory.get("topLinks", [])
		var kept: Array = []
		for link in links:
			if not (link is Dictionary):
				continue
			link["heat"] = int(round(float(link.get("heat", 0)) * scene_tick_decay))
			if int(link.get("heat", 0)) >= remove_below_heat:
				kept.append(link)
		memory["topLinks"] = kept
		item.memory = memory


func get_npc_at_cell(cell: Vector2i) -> StringName:
	for npc_id in npcs.keys():
		if ConstantsScript.world_to_cell(npcs[npc_id].position) == cell:
			return StringName(npc_id)
	return &""


func get_item_at_cell(cell: Vector2i) -> StringName:
	for item_id in items.keys():
		var item = items[item_id]
		if item.anchor_type() == "ground" and ConstantsScript.world_to_cell(item.position) == cell:
			return StringName(item_id)
	return &""


func validate_forced_drop(entity_id: StringName, target_cell: Vector2i) -> bool:
	if not _entity_exists(entity_id):
		return false
	if not _is_cell_in_bounds(target_cell):
		return false
	if blocked_cells.has(target_cell):
		return false
	return true


func move_entity_to_cell(entity_id: StringName, target_cell: Vector2i) -> bool:
	if not _entity_exists(entity_id):
		return false
	return set_entity_position(entity_id, ConstantsScript.cell_to_world_center(target_cell))


func set_entity_position(entity_id: StringName, pos: Vector2) -> bool:
	if npcs.has(entity_id):
		return set_npc_position(entity_id, pos)
	if items.has(entity_id):
		return set_item_position(entity_id, pos)
	return false


func set_npc_position(npc_id: StringName, pos: Vector2) -> bool:
	if not npcs.has(npc_id):
		return false
	var resolved: Vector2 = _resolve_walkable_position(pos)
	var npc = npcs[npc_id]
	npc.position = resolved
	npc.current_cell = ConstantsScript.world_to_cell(resolved)
	return true


func set_item_position(item_id: StringName, pos: Vector2) -> bool:
	if not items.has(item_id):
		return false
	var item = items[item_id]
	if item.anchor_type() != "ground":
		return false
	var resolved: Vector2 = _resolve_walkable_position(pos)
	item.position = resolved
	item.current_cell = ConstantsScript.world_to_cell(resolved)
	return true


func _resolve_walkable_position(pos: Vector2) -> Vector2:
	var cell: Vector2i = ConstantsScript.world_to_cell(pos)
	if not blocked_cells.has(cell) and _is_cell_in_bounds(cell):
		return pos
	var max_radius = max(map_bounds.size.x, map_bounds.size.y)
	for radius in range(1, max_radius + 1):
		for y in range(cell.y - radius, cell.y + radius + 1):
			for x in range(cell.x - radius, cell.x + radius + 1):
				if max(abs(x - cell.x), abs(y - cell.y)) != radius:
					continue
				var cand := Vector2i(x, y)
				if _is_cell_in_bounds(cand) and not blocked_cells.has(cand):
					return ConstantsScript.cell_to_world_center(cand)
	return pos


func give_item_to_npc(item_id: StringName, npc_id: StringName) -> bool:
	if not items.has(item_id) or not npcs.has(npc_id):
		return false
	var item = items[item_id]
	item.attach_to_npc(npc_id, "unclaimed")
	return true


func drop_anchored_items(npc_id: StringName, event_log = null) -> bool:
	if not npcs.has(npc_id):
		return false
	var anchored_items := items_anchored_to_npc(npc_id)
	if anchored_items.is_empty():
		return false

	for index in range(anchored_items.size()):
		drop_anchored_item(npc_id, anchored_items[index], event_log, index)
	return true


func drop_anchored_item(npc_id: StringName, item_id: StringName, event_log = null, offset_index: int = 0, actor_id: StringName = &"player") -> bool:
	if not npcs.has(npc_id) or not items.has(item_id):
		return false
	var item = items[item_id]
	if item.anchor_npc_id() != npc_id:
		return false
	var holder_pos: Vector2 = npcs[npc_id].position
	var target_pos: Vector2 = holder_pos + Vector2(ConstantsScript.CELL_SIZE * 0.72 + 18.0 * float(offset_index), ConstantsScript.CELL_SIZE * 0.66 + 10.0 * float(offset_index))
	item.attach_to_ground(_resolve_walkable_position(target_pos), "unclaimed")
	if event_log != null and event_log.has_method("record"):
		event_log.record(&"player_forced_drop_item", item_id, npc_id, &"npc", item.current_cell, {
			"source": "player_remove_object_from_npc",
			"npc_ids": [npc_id],
			"primary_npc_ids": [npc_id],
			"item_id": item_id,
			"item_name": item.name,
			"item_target_id": npc_id,
			"item_target_name": npcs[npc_id].name,
			"currentAnchor": {"type": "ground"},
			"object_social": item.social.duplicate(true),
		}, actor_id)
	return true


func repair_inventory_links() -> void:
	repair_warnings.clear()
	for item in _sorted_objects_by_id(items.values()):
		var anchor_npc_id: StringName = item.anchor_npc_id()
		if anchor_npc_id != &"" and not npcs.has(anchor_npc_id):
			_warn_and_clear_item_holder(item)

	for item in _sorted_objects_by_id(items.values()):
		if item.anchor_npc_id() != &"":
			item.current_cell = ConstantsScript.INVALID_CELL


func to_dict() -> Dictionary:
	return {
		"object_types": object_types.duplicate(true),
		"map_bounds": ConstantsScript.rect_to_dict(map_bounds),
		"blocked_cells": ConstantsScript.cell_array_to_dicts(_sorted_cells(blocked_cells.keys())),
		"npcs": _objects_to_dicts(_sorted_objects_by_id(npcs.values())),
		"items": _objects_to_dicts(_sorted_objects_by_id(items.values())),
		"relation_memories": relation_memories.values(),
		"interaction_traces": interaction_traces.values(),
		"repair_warnings": repair_warnings.duplicate(),
	}


func load_from_dict(data: Dictionary) -> void:
	npcs.clear()
	items.clear()
	object_types.clear()
	relation_memories.clear()
	interaction_traces.clear()
	blocked_cells.clear()
	repair_warnings.clear()

	object_types = _dict_from(data.get("object_types", data.get("objectTypes", {})))
	map_bounds = ConstantsScript.rect_from_dict(data.get("map_bounds", Rect2i()))
	var raw_blocked_cells: Variant = data.get("blocked_cells", [])
	if raw_blocked_cells is Array:
		for value in raw_blocked_cells:
			set_blocked_cell(ConstantsScript.cell_from_dict(value), true)

	var raw_npcs: Variant = data.get("npcs", [])
	if raw_npcs is Array:
		for value in raw_npcs:
			if value is Object and value.has_method("to_dict"):
				add_npc(value)
			elif value is Dictionary:
				add_npc(NPCStateScript.from_dict(value))

	var raw_items: Variant = data.get("items", [])
	if raw_items is Array:
		for value in raw_items:
			if value is Object and value.has_method("to_dict"):
				add_item(value)
			elif value is Dictionary:
				add_item(ItemStateScript.from_dict(value, object_types))

	var raw_relations: Variant = data.get("relation_memories", data.get("relationMemories", []))
	if raw_relations is Array:
		for value in raw_relations:
			if value is Dictionary:
				var from_id := StringName(value.get("fromNpcId", ""))
				var to_id := StringName(value.get("toNpcId", ""))
				if from_id != &"" and to_id != &"":
					if not value.has("warmth"):
						value["warmth"] = 0
					relation_memories[_relation_key(from_id, to_id)] = value.duplicate(true)

	var raw_traces: Variant = data.get("interaction_traces", data.get("traces", []))
	if raw_traces is Array:
		for value in raw_traces:
			if value is Dictionary:
				var event_type := str(value.get("eventType", "attach_object_to_npc"))
				var object_id := StringName(value.get("objectId", ""))
				var target_npc_id := StringName(value.get("targetNpcId", ""))
				if object_id != &"" and target_npc_id != &"":
					interaction_traces[_interaction_trace_key(event_type, object_id, target_npc_id)] = value.duplicate(true)

	repair_inventory_links()


func _is_cell_in_bounds(cell: Vector2i) -> bool:
	return map_bounds.has_point(cell)


func _entity_exists(entity_id: StringName) -> bool:
	return npcs.has(entity_id) or items.has(entity_id)


func _warn_and_clear_item_holder(item) -> void:
	repair_warnings.append("Cleared inconsistent anchor for object %s" % item.id)
	item.attach_to_ground(item.position, "unclaimed")


func items_anchored_to_npc(npc_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for item in _sorted_objects_by_id(items.values()):
		if item.anchor_npc_id() == npc_id:
			result.append(item.id)
	return result


func first_item_anchored_to_npc(npc_id: StringName, exclude_item_id: StringName = &"") -> StringName:
	for item_id in items_anchored_to_npc(npc_id):
		if item_id != exclude_item_id:
			return item_id
	return &""


func _objects_to_dicts(objects: Array) -> Array:
	var result: Array = []
	for object in objects:
		result.append(object.to_dict())
	return result


func _sorted_cells(cells: Array) -> Array:
	var result := cells.duplicate()
	result.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		if left.y == right.y:
			return left.x < right.x
		return left.y < right.y
	)
	return result


func _sorted_objects_by_id(objects: Array) -> Array:
	var result := objects.duplicate()
	result.sort_custom(func(left, right) -> bool:
		return str(left.id) < str(right.id)
	)
	return result


func _sorted_string_names(values: Array) -> Array:
	var result := values.duplicate()
	result.sort_custom(func(left, right) -> bool:
		return str(left) < str(right)
	)
	return result


func _relation_key(from_npc_id: StringName, to_npc_id: StringName) -> String:
	return "%s->%s" % [str(from_npc_id), str(to_npc_id)]


func _interaction_trace_key(event_type: String, object_id: StringName, target_npc_id: StringName) -> String:
	return "%s:%s:%s" % [event_type, str(object_id), str(target_npc_id)]


func _trace_stage_by_heat(heat: int) -> String:
	var stage := "new"
	for candidate in ["ritualized", "gagged", "noticed", "repeated", "new"]:
		if heat >= int(interaction_stage_thresholds.get(candidate, 0)):
			stage = candidate
			break
	return stage


func _advance_stage_by_one(current: String, target: String) -> String:
	var order := ["new", "repeated", "noticed", "gagged", "ritualized"]
	var current_index := order.find(current)
	var target_index := order.find(target)
	if current_index < 0:
		current_index = 0
	if target_index < 0:
		target_index = 0
	return order[min(current_index + 1, target_index)]


func _upsert_relation_tag(memory: Dictionary, tag: String, strength_delta: int, current_tick: int) -> void:
	var tags: Array = memory.get("tags", [])
	for entry in tags:
		if entry is Dictionary and str(entry.get("tag", "")) == tag:
			entry["strength"] = clampi(int(entry.get("strength", 0)) + strength_delta, 0, 100)
			entry["lastUsedAt"] = current_tick
			memory["tags"] = tags
			return
	tags.append({"tag": tag, "strength": clampi(strength_delta, 0, 100), "lastUsedAt": current_tick})
	memory["tags"] = tags


func _dict_from(value: Variant) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else {}
