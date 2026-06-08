extends RefCounted
class_name NPCAutoDropService

const ConstantsScript := preload("res://scripts/core/Constants.gd")
const ConfigLoaderScript := preload("res://scripts/config/ConfigLoader.gd")

var entity_registry = null
var gameplay_config: Dictionary = {}


func configure(p_entity_registry, p_gameplay_config: Dictionary) -> void:
	entity_registry = p_entity_registry
	gameplay_config = p_gameplay_config


func maybe_auto_drop_rejected_item(item_id: StringName, target_npc_id: StringName, payload: Dictionary) -> Dictionary:
	if entity_registry == null or not entity_registry.items.has(item_id) or not entity_registry.npcs.has(target_npc_id):
		return {}
	var stance: Dictionary = payload.get("gift_stance", {})
	var trace: Dictionary = payload.get("interaction_trace", {})
	var count := int(trace.get("countInWindow", 1))
	var stage := str(trace.get("stage", "new"))
	var item = entity_registry.items[item_id]
	var npc = entity_registry.npcs[target_npc_id]
	if not _npc_auto_drop_candidate(item, npc, stance):
		return {}
	var threshold_info := _npc_auto_drop_threshold(item, npc, stance)
	var threshold := int(threshold_info.get("threshold", 3))
	if count < threshold:
		return {}
	if item.anchor_npc_id() != target_npc_id:
		return {}
	var drop_pos := _npc_auto_drop_position(target_npc_id, item_id)
	item.attach_to_ground(drop_pos, "rejected")
	return {
		"npc_id": target_npc_id,
		"npc_name": npc.name,
		"item_id": item_id,
		"item_name": item.name,
		"reason": str(stance.get("dominantReason", "reject")),
		"countInWindow": count,
		"stage": stage,
		"threshold": threshold,
		"thresholdFactors": threshold_info.get("factors", []),
		"worldPosition": {"x": drop_pos.x, "y": drop_pos.y},
		"cell": ConstantsScript.cell_to_dict(ConstantsScript.world_to_cell(drop_pos)),
		"finalAnchor": {"type": "ground"},
	}


func _npc_auto_drop_candidate(item, npc, stance: Dictionary) -> bool:
	var threshold_config: Dictionary = _threshold_config()
	var candidate_cfg: Dictionary = threshold_config.get("candidate", {})
	var result := str(stance.get("result", ""))
	var direct_results: Array = _array_from(candidate_cfg.get("results", []))
	if direct_results.has(result):
		return true
	if result == "reject":
		return _auto_drop_conditions_match(candidate_cfg.get("rejectAny", []), item, npc, stance, false)
	return false


func _npc_auto_drop_threshold(item, npc, stance: Dictionary) -> Dictionary:
	var threshold_config: Dictionary = _threshold_config()
	var threshold := int(threshold_config.get("base", 3))
	var factors: Array = []
	var pressure_delta := 0
	var strongest_delay_delta := 0
	for raw_factor in threshold_config.get("factors", []):
		if not (raw_factor is Dictionary):
			continue
		var factor: Dictionary = raw_factor
		if _auto_drop_factor_matches(factor, item, npc, stance):
			var delta := int(factor.get("delta", 0))
			if delta < 0:
				pressure_delta += delta
			elif delta > strongest_delay_delta:
				strongest_delay_delta = delta
			factors.append(str(factor.get("name", "")))
	threshold += pressure_delta + strongest_delay_delta
	return {
		"threshold": clampi(threshold, int(threshold_config.get("min", 2)), int(threshold_config.get("max", 5))),
		"factors": factors,
	}


func _threshold_config() -> Dictionary:
	var threshold_config: Dictionary = gameplay_config.get("autoDropThreshold", {})
	if threshold_config.is_empty():
		threshold_config = ConfigLoaderScript.load_gameplay_config().get("autoDropThreshold", {})
	return threshold_config


func _auto_drop_factor_matches(factor: Dictionary, item, npc, stance: Dictionary) -> bool:
	if factor.has("all"):
		return _auto_drop_conditions_match(factor.get("all", []), item, npc, stance, true)
	if factor.has("any"):
		return _auto_drop_conditions_match(factor.get("any", []), item, npc, stance, false)
	return false


func _auto_drop_conditions_match(conditions: Variant, item, npc, stance: Dictionary, require_all: bool) -> bool:
	if not (conditions is Array):
		return true
	var matched_any := false
	for raw_condition in conditions:
		if not (raw_condition is Dictionary):
			continue
		var matched := _auto_drop_condition_matches(raw_condition, item, npc, stance)
		if require_all and not matched:
			return false
		if matched:
			matched_any = true
	return true if require_all else matched_any


func _auto_drop_condition_matches(condition: Dictionary, item, npc, stance: Dictionary) -> bool:
	var value: Variant = _auto_drop_condition_value(condition, item, npc, stance)
	if condition.has("eq") and str(value) != str(condition.get("eq", "")):
		return false
	if condition.has("gte") and not (float(value) >= float(condition.get("gte", 0))):
		return false
	if condition.has("lte") and not (float(value) <= float(condition.get("lte", 0))):
		return false
	if condition.has("has"):
		return value is Array and value.has(condition.get("has"))
	return true


func _auto_drop_condition_value(condition: Dictionary, item, npc, stance: Dictionary) -> Variant:
	var source := str(condition.get("source", "stance"))
	var field := str(condition.get("field", ""))
	if source == "social":
		var social: Dictionary = item.social if item != null and item.social is Dictionary else {}
		return social.get(field, 0)
	if source == "traits":
		var traits: Dictionary = npc.traits if npc != null and npc.traits is Dictionary else {}
		return traits.get(field, 0)
	if source == "tags":
		return npc.tags if npc != null and npc.tags is Array else []
	if field == "reject_margin":
		return int(stance.get("reject", 0)) - int(stance.get("want", 0))
	if field == "reason":
		return str(stance.get("dominantReason", ""))
	return stance.get(field, null)


func _npc_auto_drop_position(npc_id: StringName, item_id: StringName) -> Vector2:
	if entity_registry == null or not entity_registry.npcs.has(npc_id):
		return Vector2.ZERO
	var npc = entity_registry.npcs[npc_id]
	var offset := Vector2(ConstantsScript.CELL_SIZE * 0.85, ConstantsScript.CELL_SIZE * 0.42)
	if not str(item_id).is_empty():
		var sign := 1.0 if abs(hash(str(item_id))) % 2 == 0 else -1.0
		offset.x *= sign
	var candidate: Vector2 = npc.position + offset
	var cell := ConstantsScript.world_to_cell(candidate)
	if entity_registry.map_bounds != Rect2i() and not entity_registry.map_bounds.has_point(cell):
		return npc.position
	return candidate


func _array_from(value: Variant) -> Array:
	return value.duplicate(true) if value is Array else []
