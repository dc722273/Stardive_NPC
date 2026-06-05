extends RefCounted
class_name TestLLMTransport

## Deterministic 单测: LLMTransport 的纯函数 parse_sse_line + FIFO 队列入队行为。
## 真实 HTTP 由 apr/npc-loop/oracle/llm_live_oracle.gd 覆盖（需 key），这里不联网。
## 由 tests/run_tests.gd 聚合调用 run()；run() 返回 failures 数组（空=全过）。

const LLMTransportScript := preload("res://scripts/npc/LLMTransport.gd")


func run() -> Array:
	var failures: Array = []
	_test_done_line(failures)
	_test_non_data_line_is_ignored(failures)
	_test_empty_line_is_ignored(failures)
	_test_blank_data_line_is_ignored(failures)
	_test_streaming_delta_line(failures)
	_test_non_streaming_message_line(failures)
	_test_broken_json_is_ignored(failures)
	_test_delta_without_content_is_ignored(failures)
	_test_disabled_transport_short_circuits(failures)
	_test_repeated_disabled_requests_each_resolve(failures)
	return failures


func _test_done_line(failures: Array) -> void:
	var result := LLMTransportScript.parse_sse_line("data: [DONE]")
	_assert_equal(result.get("type", &""), &"done", "data: [DONE] parses as done", failures)


func _test_non_data_line_is_ignored(failures: Array) -> void:
	var result := LLMTransportScript.parse_sse_line(": OPENROUTER PROCESSING")
	_assert_equal(result.get("type", &""), &"ignore", "non-data line parses as ignore", failures)


func _test_empty_line_is_ignored(failures: Array) -> void:
	var result := LLMTransportScript.parse_sse_line("")
	_assert_equal(result.get("type", &""), &"ignore", "empty line parses as ignore", failures)


func _test_blank_data_line_is_ignored(failures: Array) -> void:
	var result := LLMTransportScript.parse_sse_line("data: ")
	_assert_equal(result.get("type", &""), &"ignore", "blank data line parses as ignore", failures)


func _test_streaming_delta_line(failures: Array) -> void:
	var line := "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}"
	var result := LLMTransportScript.parse_sse_line(line)
	_assert_equal(result.get("type", &""), &"delta", "streaming delta line parses as delta", failures)
	_assert_equal(result.get("content", ""), "Hello", "streaming delta line keeps delta content", failures)


func _test_non_streaming_message_line(failures: Array) -> void:
	var line := "data: {\"choices\":[{\"message\":{\"content\":\"World\"}}]}"
	var result := LLMTransportScript.parse_sse_line(line)
	_assert_equal(result.get("type", &""), &"delta", "non-streaming message line parses as delta", failures)
	_assert_equal(result.get("content", ""), "World", "non-streaming message line keeps message content", failures)


func _test_broken_json_is_ignored(failures: Array) -> void:
	var result := LLMTransportScript.parse_sse_line("data: {broken json")
	_assert_equal(result.get("type", &""), &"ignore", "broken json data line parses as ignore", failures)


func _test_delta_without_content_is_ignored(failures: Array) -> void:
	var line := "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}"
	var result := LLMTransportScript.parse_sse_line(line)
	_assert_equal(result.get("type", &""), &"ignore", "delta line without content parses as ignore", failures)


# 无 config（未启用）时 request_chat 立即回 llm_disabled，不入队、不发请求。
func _test_disabled_transport_short_circuits(failures: Array) -> void:
	var transport = LLMTransportScript.new()
	var got: Array = []
	transport.request_chat([], {}, func(r: Dictionary) -> void: got.append(r))
	_assert_equal(got.size(), 1, "disabled transport calls on_done synchronously", failures)
	if not got.is_empty():
		_assert_equal(str(got[0].get("error", "")), "llm_disabled", "disabled transport returns llm_disabled", failures)
	transport.free()


# disabled 路径：未启用时每次 request_chat 都立即回 llm_disabled，不入队、不静默丢弃。
# 注：真正的 FIFO 入队 / superseded 跳过行为在 tests/test_planner_queue_llm.gd 用 fake 覆盖
# （需 _is_enabled 为 true 才会进队列，这里 disabled 在守卫处提前返回，测不到队列）。
func _test_repeated_disabled_requests_each_resolve(failures: Array) -> void:
	var transport = LLMTransportScript.new()
	var got: Array = []
	for i in range(3):
		transport.request_chat([], {}, func(r: Dictionary) -> void: got.append(r))
	_assert_equal(got.size(), 3, "three disabled requests each resolve immediately (no silent drop)", failures)
	transport.free()


func _assert_equal(actual: Variant, expected: Variant, message: String, failures: Array) -> void:
	if actual != expected:
		failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
