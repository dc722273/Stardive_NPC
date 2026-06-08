extends RefCounted
class_name StakeholderPerceptionService

const ConfigLoaderScript := preload("res://scripts/config/ConfigLoader.gd")

var entity_registry = null
var gameplay_config: Dictionary = {}
var config: Dictionary = {}


func configure(p_entity_registry, p_gameplay_config: Dictionary = {}) -> void:
	entity_registry = p_entity_registry
	gameplay_config = p_gameplay_config
	config = gameplay_config.get("socialPerceptionConfig", {})
	if config.is_empty():
		config = ConfigLoaderScript.load_gameplay_config().get("socialPerceptionConfig", {})


func parse_chat_social_fact(_speaker_npc_id: StringName, message: String) -> Dictionary:
	if not bool(config.get("enabled", true)):
		return {"ok": false}
	var clean := message.strip_edges()
	if clean.is_empty() or not _message_has_any(clean, _array_from(config.get("giftMarkers", []))):
		return {"ok": false}
	var mentions := _mentioned_npcs(clean)
	if mentions.size() < 2:
		return {"ok": false}
	var actor: Dictionary = mentions[0]
	var target: Dictionary = mentions[1]
	var object_label := _object_label_from_text(clean)
	return {
		"ok": true,
		"kind": "gift",
		"actorNpcId": str(actor.get("id", "")),
		"actorName": _npc_display_name(StringName(actor.get("id", ""))),
		"targetNpcId": str(target.get("id", "")),
		"targetName": _npc_display_name(StringName(target.get("id", ""))),
		"objectLabel": object_label,
		"sourceText": clean,
		"confidence": 0.82 if object_label == str(config.get("genericObjectLabel", "礼物")) else 0.9,
	}


func apply_observer_perception(observer_npc_id: StringName, fact: Dictionary, current_tick: int = 0) -> Dictionary:
	if observer_npc_id == &"" or fact.is_empty() or not bool(fact.get("ok", false)):
		return {}
	if entity_registry == null or not entity_registry.npcs.has(observer_npc_id):
		return {}
	var observer = entity_registry.npcs[observer_npc_id]
	var rule := _matching_rule(observer, fact)
	if rule.is_empty():
		return {}
	var actor_id := StringName(fact.get("actorNpcId", ""))
	var target_id := StringName(fact.get("targetNpcId", ""))
	var updates := []
	var challenger_delta: Dictionary = rule.get("challengerRelationDelta", {})
	if actor_id != &"" and actor_id != observer_npc_id and not challenger_delta.is_empty():
		updates.append(entity_registry.apply_relation_delta(observer_npc_id, actor_id, challenger_delta, str(rule.get("tag", rule.get("id", "social_threat"))), current_tick))
	var target_delta: Dictionary = rule.get("targetRelationDelta", {})
	if target_id != &"" and target_id != observer_npc_id and not target_delta.is_empty():
		updates.append(entity_registry.apply_relation_delta(observer_npc_id, target_id, target_delta, str(rule.get("tag", rule.get("id", "social_threat"))), current_tick))
	return {
		"observerNpcId": str(observer_npc_id),
		"observerName": _npc_display_name(observer_npc_id),
		"ruleId": str(rule.get("id", "")),
		"fact": fact.duplicate(true),
		"threatText": _format_template(str(rule.get("threatText", "")), _fact_values(fact, observer_npc_id)),
		"visibleReaction": _format_template(str(rule.get("visibleReaction", "")), _fact_values(fact, observer_npc_id)),
		"responseFocus": str(rule.get("responseFocus", "challenger")),
		"instruction": _format_template(str(rule.get("instruction", "")), _fact_values(fact, observer_npc_id)),
		"relationMemoryUpdates": _non_empty_dicts(updates),
	}


func _matching_rule(observer, fact: Dictionary) -> Dictionary:
	if observer == null:
		return {}
	for raw_rule in _array_from(config.get("rules", [])):
		if not (raw_rule is Dictionary):
			continue
		var rule: Dictionary = raw_rule
		if str(rule.get("eventKind", "")) != str(fact.get("kind", "")):
			continue
		if not _npc_id_matches(StringName(fact.get("targetNpcId", "")), _array_from(rule.get("targetNpcIds", []))):
			continue
		if not _tags_match(_array_from(observer.tags), rule):
			continue
		if not _challenger_matches(StringName(fact.get("actorNpcId", "")), rule):
			continue
		return rule.duplicate(true)
	return {}


func _tags_match(tags: Array, rule: Dictionary) -> bool:
	var any_tags := _array_from(rule.get("watcherAnyTags", []))
	if not any_tags.is_empty() and not _has_any(tags, any_tags):
		return false
	var all_tags := _array_from(rule.get("watcherAllTags", []))
	for tag in all_tags:
		if not tags.has(tag):
			return false
	return true


func _challenger_matches(challenger_id: StringName, rule: Dictionary) -> bool:
	if challenger_id == &"" or entity_registry == null or not entity_registry.npcs.has(challenger_id):
		return false
	var tags: Array = entity_registry.npcs[challenger_id].tags
	var any_tags := _array_from(rule.get("challengerAnyTags", []))
	if any_tags.is_empty():
		return true
	return _has_any(tags, any_tags)


func _npc_id_matches(npc_id: StringName, allowed: Array) -> bool:
	if allowed.is_empty():
		return true
	for value in allowed:
		if StringName(value) == npc_id or str(value) == str(npc_id):
			return true
	return false


func _mentioned_npcs(text: String) -> Array:
	var mentions := []
	if entity_registry == null:
		return mentions
	for npc in entity_registry.npcs.values():
		for alias in _npc_aliases(npc):
			var pos := text.find(alias)
			if pos < 0:
				continue
			mentions.append({
				"id": str(npc.id),
				"alias": alias,
				"pos": pos,
				"length": alias.length(),
			})
			break
	mentions.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left.get("pos", 0)) == int(right.get("pos", 0)):
			return int(left.get("length", 0)) > int(right.get("length", 0))
		return int(left.get("pos", 0)) < int(right.get("pos", 0))
	)
	return mentions


func _npc_aliases(npc) -> Array[String]:
	var aliases: Array[String] = []
	for value in [str(npc.id), str(npc.name)]:
		if not value.is_empty() and not aliases.has(value):
			aliases.append(value)
	var raw_aliases: Variant = npc.get("aliases")
	if raw_aliases is Array:
		for raw_alias in raw_aliases:
			var alias := str(raw_alias)
			if not alias.is_empty() and not aliases.has(alias):
				aliases.append(alias)
	aliases.sort_custom(func(left: String, right: String) -> bool:
		return left.length() > right.length()
	)
	return aliases


func _object_label_from_text(text: String) -> String:
	for label in _array_from(config.get("genericObjectWords", [])):
		if text.find(str(label)) >= 0:
			return str(label)
	return str(config.get("genericObjectLabel", "礼物"))


func _message_has_any(text: String, values: Array) -> bool:
	for value in values:
		if not str(value).is_empty() and text.find(str(value)) >= 0:
			return true
	return false


func _has_any(values: Array, expected: Array) -> bool:
	for value in expected:
		if values.has(value):
			return true
	return false


func _fact_values(fact: Dictionary, observer_npc_id: StringName) -> Dictionary:
	return {
		"observer_name": _npc_display_name(observer_npc_id),
		"actor_name": str(fact.get("actorName", fact.get("actorNpcId", ""))),
		"target_name": str(fact.get("targetName", fact.get("targetNpcId", ""))),
		"object_label": str(fact.get("objectLabel", config.get("genericObjectLabel", "礼物"))),
	}


func _npc_display_name(npc_id: StringName) -> String:
	if entity_registry != null and entity_registry.npcs.has(npc_id):
		return str(entity_registry.npcs[npc_id].name)
	return str(npc_id)


func _non_empty_dicts(values: Array) -> Array:
	var result := []
	for value in values:
		if value is Dictionary and not value.is_empty():
			result.append(value)
	return result


func _array_from(value: Variant) -> Array:
	return value.duplicate(true) if value is Array else []


func _format_template(template: String, values: Dictionary) -> String:
	var result := template
	for key in values.keys():
		result = result.replace("{%s}" % str(key), str(values[key]))
	return result
