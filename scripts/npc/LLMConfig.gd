extends RefCounted
class_name LLMConfig

const DEFAULT_MODEL := "google/gemini-3.1-flash-lite"
const DEFAULT_BASE_URL := "https://openrouter.ai/api/v1"
const ENV_FILE_PATHS := ["res://.env"]
const API_KEY_KEYS := ["OPENROUTER_API_KEY", "NPC_LLM_API_KEY"]
const MODEL_KEYS := ["OPENROUTER_MODEL", "NPC_LLM_MODEL"]
const BASE_URL_KEYS := ["OPENROUTER_BASE_URL", "NPC_LLM_BASE_URL"]


var api_key: String = ""
var model: String = DEFAULT_MODEL
var base_url: String = DEFAULT_BASE_URL
var enabled: bool = false


static func load_from_project_root() -> LLMConfig:
	var parsed := {}
	for env_path in ENV_FILE_PATHS:
		_merge_env(parsed, parse_env_text(_read_text_file(env_path)), false)
	_merge_env(parsed, read_process_environment(), true)
	return from_env_dict(parsed)


static func from_env_text(text: String) -> LLMConfig:
	return from_env_dict(parse_env_text(text))


static func from_env_dict(parsed: Dictionary) -> LLMConfig:
	var config: LLMConfig = (load("res://scripts/npc/LLMConfig.gd") as GDScript).new()
	config.api_key = _first_non_empty(parsed, API_KEY_KEYS)
	var parsed_model := _first_non_empty(parsed, MODEL_KEYS)
	config.model = parsed_model if not parsed_model.is_empty() else DEFAULT_MODEL
	var parsed_base_url := _first_non_empty(parsed, BASE_URL_KEYS)
	config.base_url = parsed_base_url if not parsed_base_url.is_empty() else DEFAULT_BASE_URL
	config.enabled = not config.api_key.is_empty()
	return config


static func parse_env_text(text: String) -> Dictionary:
	var result: Dictionary = {}
	for raw_line in text.split("\n"):
		var line := str(raw_line).strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("#"):
			continue
		var split_index := line.find("=")
		if split_index < 0:
			continue
		var key := line.substr(0, split_index).strip_edges()
		if key.is_empty():
			continue
		var value := line.substr(split_index + 1).strip_edges()
		value = _strip_matching_quotes(value)
		result[key] = value
	return result


static func read_process_environment() -> Dictionary:
	var result := {}
	for key in _all_supported_env_keys():
		var value := OS.get_environment(key).strip_edges()
		if not value.is_empty():
			result[key] = value
	return result


func headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json",
		"HTTP-Referer: https://localhost",
		"X-Title: AI NPC Sandbox",
	])


static func _strip_matching_quotes(value: String) -> String:
	if value.length() < 2:
		return value
	var first := value[0]
	var last := value[value.length() - 1]
	if (first == "\"" and last == "\"") or (first == "'" and last == "'"):
		return value.substr(1, value.length() - 2)
	return value


static func _read_text_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


static func _first_non_empty(values: Dictionary, keys: Array) -> String:
	for key in keys:
		var value := str(values.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""


static func _merge_env(target: Dictionary, source: Dictionary, override_existing: bool) -> void:
	for key in source.keys():
		if override_existing or not target.has(key):
			target[key] = source[key]


static func _all_supported_env_keys() -> Array:
	var keys := []
	keys.append_array(API_KEY_KEYS)
	keys.append_array(MODEL_KEYS)
	keys.append_array(BASE_URL_KEYS)
	return keys
