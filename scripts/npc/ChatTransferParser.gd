extends RefCounted
class_name ChatTransferParser

const ConfigLoaderScript := preload("res://scripts/config/ConfigLoader.gd")

var entity_registry = null
var gameplay_config: Dictionary = {}


func configure(p_entity_registry, p_gameplay_config: Dictionary) -> void:
	entity_registry = p_entity_registry
	gameplay_config = p_gameplay_config


func parse_transfer(target_npc_id: StringName, message: String) -> Dictionary:
	if not _looks_like_transfer_text(message):
		return {"ok": false}
	var item_id := _find_item_in_text(message)
	var giver_id := _find_giver_before_transfer_marker(message, target_npc_id)
	var recipient_id := _find_explicit_recipient_after_transfer_marker(message, target_npc_id)
	var quantity := _find_quantity_near_item(message, item_id)
	if recipient_id == &"":
		recipient_id = target_npc_id
	if item_id == &"" or giver_id == &"" or recipient_id == &"":
		return {"ok": false}
	return {
		"ok": true,
		"item_id": item_id,
		"giver_id": giver_id,
		"recipient_id": recipient_id,
		"quantity": quantity,
	}


func _looks_like_transfer_text(text: String) -> bool:
	for marker in _chat_transfer_markers():
		if text.find(marker) >= 0:
			return true
	return false


func _chat_transfer_markers() -> Array:
	var chat_cfg: Dictionary = _chat_config()
	return _array_from(chat_cfg.get("transferMarkers", []))


func _chat_pronoun_recipients() -> Array:
	var chat_cfg: Dictionary = _chat_config()
	return _array_from(chat_cfg.get("pronounRecipients", []))


func _chat_config() -> Dictionary:
	var chat_cfg: Dictionary = gameplay_config.get("chat", {})
	if chat_cfg.is_empty():
		chat_cfg = ConfigLoaderScript.load_gameplay_config().get("chat", {})
	return chat_cfg


func _find_npc_in_text(text: String, exclude_id: StringName = &"") -> StringName:
	var best_id: StringName = &""
	var best_len := 0
	if entity_registry == null:
		return best_id
	for npc in entity_registry.npcs.values():
		if npc.id == exclude_id:
			continue
		for alias in _npc_text_aliases(npc):
			if alias.length() > best_len and text.find(alias) >= 0:
				best_id = npc.id
				best_len = alias.length()
	return best_id


func _find_giver_before_transfer_marker(text: String, exclude_id: StringName = &"") -> StringName:
	var marker_start := -1
	for marker in _chat_transfer_markers():
		var pos := text.find(marker)
		if pos >= 0 and (marker_start < 0 or pos < marker_start):
			marker_start = pos
	if marker_start < 0:
		return _find_npc_in_text(text, exclude_id)
	var giver_id := _find_npc_in_text(text.substr(0, marker_start), exclude_id)
	if giver_id != &"":
		return giver_id
	return _find_npc_in_text(text, exclude_id)


func _find_explicit_recipient_after_transfer_marker(text: String, fallback_id: StringName = &"") -> StringName:
	var marker_pos := -1
	for marker in _chat_transfer_markers():
		var pos := text.find(marker)
		if pos >= 0 and (marker_pos < 0 or pos < marker_pos):
			marker_pos = pos + marker.length()
	if marker_pos < 0:
		return fallback_id
	var tail := text.substr(marker_pos)
	var best_id: StringName = &""
	var best_pos := 999999
	var best_len := 0
	if entity_registry == null:
		return best_id
	for npc in entity_registry.npcs.values():
		for alias in _npc_text_aliases(npc):
			var pos := tail.find(alias)
			if pos >= 0 and (pos < best_pos or (pos == best_pos and alias.length() > best_len)):
				best_id = npc.id
				best_pos = pos
				best_len = alias.length()
	if best_id == &"" and _text_has_pronoun_recipient(tail):
		return fallback_id
	return best_id


func _text_has_pronoun_recipient(text: String) -> bool:
	for pronoun in _chat_pronoun_recipients():
		if text.find(pronoun) >= 0:
			return true
	return false


func _find_item_in_text(text: String) -> StringName:
	var best_id: StringName = &""
	var best_len := 0
	if entity_registry == null:
		return best_id
	for item in entity_registry.items.values():
		for alias in _item_text_aliases(item):
			if alias.length() > best_len and text.find(alias) >= 0:
				best_id = item.id
				best_len = alias.length()
	return best_id


func _find_quantity_near_item(text: String, item_id: StringName) -> int:
	if item_id == &"" or entity_registry == null or not entity_registry.items.has(item_id):
		return 1
	var item = entity_registry.items[item_id]
	var best_quantity := 1
	var best_score := 999999
	for alias in _item_text_aliases(item):
		var alias_pos := text.find(alias)
		if alias_pos < 0:
			continue
		for quantity_match in _quantity_matches(text):
			var quantity := int(quantity_match.get("quantity", 1))
			var pos := int(quantity_match.get("pos", 0))
			var score: int = abs(pos - alias_pos)
			if score < best_score:
				best_score = score
				best_quantity = quantity
	return clampi(best_quantity, 1, int(_chat_config().get("maxReportedQuantity", 100)))


func _quantity_matches(text: String) -> Array:
	var matches: Array = []
	var digit_re := RegEx.new()
	if digit_re.compile("\\d+") == OK:
		for result in digit_re.search_all(text):
			matches.append({"quantity": int(result.get_string()), "pos": result.get_start()})
	var cn_re := RegEx.new()
	if cn_re.compile("[一二两三四五六七八九十百]+") == OK:
		for result in cn_re.search_all(text):
			var quantity := _chinese_quantity_to_int(result.get_string())
			if quantity > 0:
				matches.append({"quantity": quantity, "pos": result.get_start()})
	return matches


func _chinese_quantity_to_int(text: String) -> int:
	var digits := {
		"一": 1,
		"二": 2,
		"两": 2,
		"三": 3,
		"四": 4,
		"五": 5,
		"六": 6,
		"七": 7,
		"八": 8,
		"九": 9,
	}
	if text == "十":
		return 10
	if text == "百":
		return 100
	var hundred_pos := text.find("百")
	if hundred_pos >= 0:
		var prefix := text.substr(0, hundred_pos)
		var suffix := text.substr(hundred_pos + 1)
		var hundreds: int = 1 if prefix.is_empty() else int(digits.get(prefix, 0))
		return hundreds * 100 + _chinese_quantity_to_int(suffix)
	var ten_pos := text.find("十")
	if ten_pos >= 0:
		var prefix := text.substr(0, ten_pos)
		var suffix := text.substr(ten_pos + 1)
		var tens: int = 1 if prefix.is_empty() else int(digits.get(prefix, 0))
		var ones: int = 0 if suffix.is_empty() else int(digits.get(suffix, 0))
		return tens * 10 + ones
	return int(digits.get(text, 0))


func _npc_text_aliases(npc) -> Array[String]:
	var aliases: Array[String] = []
	for value in [str(npc.id), npc.name]:
		if not value.is_empty() and not aliases.has(value):
			aliases.append(value)
	var raw_aliases: Variant = _object_field(npc, "aliases", [])
	if raw_aliases is Array:
		for raw_alias in raw_aliases:
			var alias := str(raw_alias)
			if not alias.is_empty() and not aliases.has(alias):
				aliases.append(alias)
	return aliases


func _item_text_aliases(item) -> Array[String]:
	var aliases: Array[String] = []
	for value in [str(item.id), str(item.type_id), item.name, item.category]:
		if not value.is_empty() and not aliases.has(value):
			aliases.append(value)
	var object_type: Dictionary = entity_registry.object_types.get(str(item.type_id), entity_registry.object_types.get(item.type_id, {}))
	var type_name := str(object_type.get("name", ""))
	if not type_name.is_empty() and not aliases.has(type_name):
		aliases.append(type_name)
	var raw_aliases: Variant = object_type.get("aliases", [])
	if raw_aliases is Array:
		for raw_alias in raw_aliases:
			var alias := str(raw_alias)
			if not alias.is_empty() and not aliases.has(alias):
				aliases.append(alias)
	return aliases


func _object_field(value, field_name: String, fallback = null) -> Variant:
	if value is Dictionary:
		return value.get(field_name, fallback)
	if value != null and value is Object:
		var field_value: Variant = value.get(field_name)
		return fallback if field_value == null else field_value
	return fallback


func _array_from(value: Variant) -> Array:
	return value.duplicate(true) if value is Array else []
