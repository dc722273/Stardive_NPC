extends RefCounted
class_name ConfigLoader


static func load_json_file(path: String, fallback = null) -> Variant:
	if not FileAccess.file_exists(path):
		return fallback
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fallback
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("[ConfigLoader] JSON parse failed: %s line=%d %s" % [path, json.get_error_line(), json.get_error_message()])
		return fallback
	return json.data


static func load_gameplay_config() -> Dictionary:
	var data = load_json_file("res://config/gameplay.json", {})
	return data if data is Dictionary else {}


static func load_feedback_config() -> Dictionary:
	var data = load_json_file("res://config/feedback.json", {})
	return data if data is Dictionary else {}


static func load_planner_config() -> Dictionary:
	var data = load_json_file("res://config/planner.json", {})
	return data if data is Dictionary else {}


static func load_wellbeing_config() -> Dictionary:
	var data = load_json_file("res://config/wellbeing.json", {})
	return data if data is Dictionary else {}


static func load_item_configs() -> Array:
	var bundle := load_item_bundle()
	return bundle.get("objects", [])


static func load_item_bundle() -> Dictionary:
	var data = load_json_file("res://config/items.json", [])
	if data is Array:
		return {"objectTypes": {}, "objects": data}
	if data is Dictionary:
		var object_types: Dictionary = data.get("objectTypes", {})
		var objects: Array = data.get("objects", [])
		return {
			"objectTypes": object_types if object_types is Dictionary else {},
			"objects": objects if objects is Array else [],
		}
	return {"objectTypes": {}, "objects": []}


static func load_npc_configs() -> Dictionary:
	var by_id: Dictionary = {}
	var configs: Array = []
	var dir := DirAccess.open("res://config/npcs")
	if dir == null:
		return {"configs": configs, "by_id": by_id}
	var names: Array[String] = []
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".json"):
			names.append(filename)
		filename = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for filename_value in names:
		var raw = load_json_file("res://config/npcs/%s" % filename_value, {})
		if not (raw is Dictionary):
			continue
		var npc_id := str(raw.get("npc_id", raw.get("id", ""))).strip_edges()
		if npc_id.is_empty():
			continue
		var cfg: Dictionary = raw.duplicate(true)
		cfg["id"] = npc_id
		by_id[npc_id] = cfg
		configs.append(cfg)
	return {"configs": configs, "by_id": by_id}
