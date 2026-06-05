extends RefCounted
class_name TestLLMConfig

## Deterministic 单测: LLMConfig 的 .env 文本解析纯函数 + config 派生。
## 由 tests/run_tests.gd 聚合调用 run()；run() 返回 failures 数组（空=全过）。

const LLMConfigScript := preload("res://scripts/npc/LLMConfig.gd")


func run() -> Array:
	var failures: Array = []
	_test_parse_basic_multi_line(failures)
	_test_parse_skips_comment_lines(failures)
	_test_parse_skips_blank_lines(failures)
	_test_parse_strips_double_quotes(failures)
	_test_parse_strips_single_quotes(failures)
	_test_parse_keeps_equals_in_value(failures)
	_test_parse_trims_surrounding_whitespace(failures)
	_test_config_disabled_without_api_key(failures)
	_test_config_enabled_and_defaults(failures)
	_test_config_accepts_npc_llm_aliases(failures)
	_test_openrouter_keys_take_precedence_over_aliases(failures)
	_test_headers_shape(failures)
	return failures


func _test_parse_basic_multi_line(failures: Array) -> void:
	var parsed := LLMConfigScript.parse_env_text("OPENROUTER_API_KEY=dummy_openrouter_key\nOPENROUTER_MODEL=google/gemini-3.1-flash-lite")
	_assert_equal(parsed.get("OPENROUTER_API_KEY", ""), "dummy_openrouter_key", "parse keeps first key value", failures)
	_assert_equal(parsed.get("OPENROUTER_MODEL", ""), "google/gemini-3.1-flash-lite", "parse keeps second key value", failures)


func _test_parse_skips_comment_lines(failures: Array) -> void:
	var parsed := LLMConfigScript.parse_env_text("# this is a comment\n   # indented comment\nKEY=value")
	_assert_equal(parsed.has("# this is a comment"), false, "parse skips comment line as key", failures)
	_assert_equal(parsed.size(), 1, "parse keeps only non-comment lines", failures)
	_assert_equal(parsed.get("KEY", ""), "value", "parse keeps key after comments", failures)


func _test_parse_skips_blank_lines(failures: Array) -> void:
	var parsed := LLMConfigScript.parse_env_text("\n\n   \nKEY=value\n\n")
	_assert_equal(parsed.size(), 1, "parse skips blank/whitespace lines", failures)
	_assert_equal(parsed.get("KEY", ""), "value", "parse keeps key among blank lines", failures)


func _test_parse_strips_double_quotes(failures: Array) -> void:
	var parsed := LLMConfigScript.parse_env_text("OPENROUTER_API_KEY=\"dummy_key_double\"")
	_assert_equal(parsed.get("OPENROUTER_API_KEY", ""), "dummy_key_double", "parse strips matching double quotes", failures)


func _test_parse_strips_single_quotes(failures: Array) -> void:
	var parsed := LLMConfigScript.parse_env_text("OPENROUTER_API_KEY='dummy_key_single'")
	_assert_equal(parsed.get("OPENROUTER_API_KEY", ""), "dummy_key_single", "parse strips matching single quotes", failures)


func _test_parse_keeps_equals_in_value(failures: Array) -> void:
	var parsed := LLMConfigScript.parse_env_text("TOKEN=abc==")
	_assert_equal(parsed.get("TOKEN", ""), "abc==", "parse splits on first equals and keeps trailing equals", failures)


func _test_parse_trims_surrounding_whitespace(failures: Array) -> void:
	var parsed := LLMConfigScript.parse_env_text("  KEY   =   value  ")
	_assert_equal(parsed.has("KEY"), true, "parse trims whitespace around key", failures)
	_assert_equal(parsed.get("KEY", "<missing>"), "value", "parse trims whitespace around value", failures)


func _test_config_disabled_without_api_key(failures: Array) -> void:
	var config = LLMConfigScript.from_env_text("OPENROUTER_MODEL=google/gemini-3.1-flash-lite")
	_assert_equal(config.enabled, false, "config disabled when OPENROUTER_API_KEY missing", failures)
	_assert_equal(config.api_key, "", "config api_key empty when missing", failures)

	var empty_config = LLMConfigScript.from_env_text("OPENROUTER_API_KEY=")
	_assert_equal(empty_config.enabled, false, "config disabled when OPENROUTER_API_KEY blank", failures)


func _test_config_enabled_and_defaults(failures: Array) -> void:
	var config = LLMConfigScript.from_env_text("OPENROUTER_API_KEY=dummy_openrouter_key")
	_assert_equal(config.enabled, true, "config enabled when api key present", failures)
	_assert_equal(config.api_key, "dummy_openrouter_key", "config keeps api key", failures)
	_assert_equal(config.model, "google/gemini-3.1-flash-lite", "config falls back to default model", failures)
	_assert_equal(config.base_url, "https://openrouter.ai/api/v1", "config falls back to default base_url", failures)

	var overridden = LLMConfigScript.from_env_text("OPENROUTER_API_KEY=dummy_key\nOPENROUTER_MODEL=anthropic/claude\nOPENROUTER_BASE_URL=https://example.test/api")
	_assert_equal(overridden.model, "anthropic/claude", "config honors overridden model", failures)
	_assert_equal(overridden.base_url, "https://example.test/api", "config honors overridden base_url", failures)


func _test_config_accepts_npc_llm_aliases(failures: Array) -> void:
	var config = LLMConfigScript.from_env_text("NPC_LLM_API_KEY=dummy_npc_key\nNPC_LLM_MODEL=deepseek-chat\nNPC_LLM_BASE_URL=https://api.deepseek.com/v1")
	_assert_equal(config.enabled, true, "config enabled from NPC_LLM_API_KEY alias", failures)
	_assert_equal(config.api_key, "dummy_npc_key", "config keeps NPC_LLM_API_KEY alias", failures)
	_assert_equal(config.model, "deepseek-chat", "config honors NPC_LLM_MODEL alias", failures)
	_assert_equal(config.base_url, "https://api.deepseek.com/v1", "config honors NPC_LLM_BASE_URL alias", failures)


func _test_openrouter_keys_take_precedence_over_aliases(failures: Array) -> void:
	var config = LLMConfigScript.from_env_text("NPC_LLM_API_KEY=alias_key\nOPENROUTER_API_KEY=openrouter_key\nNPC_LLM_MODEL=alias-model\nOPENROUTER_MODEL=openrouter-model\nNPC_LLM_BASE_URL=https://alias.test/v1\nOPENROUTER_BASE_URL=https://openrouter.test/v1")
	_assert_equal(config.api_key, "openrouter_key", "OPENROUTER_API_KEY wins over NPC_LLM_API_KEY", failures)
	_assert_equal(config.model, "openrouter-model", "OPENROUTER_MODEL wins over NPC_LLM_MODEL", failures)
	_assert_equal(config.base_url, "https://openrouter.test/v1", "OPENROUTER_BASE_URL wins over NPC_LLM_BASE_URL", failures)


func _test_headers_shape(failures: Array) -> void:
	var config = LLMConfigScript.from_env_text("OPENROUTER_API_KEY=dummy_openrouter_key")
	var headers := config.headers()
	_assert_equal(headers.size(), 4, "headers returns four entries", failures)
	_assert_equal(headers[0], "Authorization: Bearer dummy_openrouter_key", "headers includes bearer auth", failures)
	_assert_equal(headers[1], "Content-Type: application/json", "headers includes content type", failures)
	_assert_equal(headers[2], "HTTP-Referer: https://localhost", "headers includes referer", failures)
	_assert_equal(headers[3], "X-Title: AI NPC Sandbox", "headers includes title", failures)


func _assert_equal(actual: Variant, expected: Variant, message: String, failures: Array) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])
