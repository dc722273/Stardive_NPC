extends Node
class_name LLMTransport

const LLMConfigScript := preload("res://scripts/npc/LLMConfig.gd")

## Node 唯一持有 HTTPRequest 的地方。LLMClient 是 RefCounted 不能直接发请求，
## 所以网络 IO 全部收敛在这里。LLM 只产出文本/JSON，runtime 校验后才采纳。
##
## MVP 阶段流式（stream=true）也用一次性的非流式请求 + 在 on_done 一次性回调实现，
## SSE 真·逐块回填留作后续；但 parse_sse_line 纯函数已就位，供 feedback 解析逐行 SSE。


var config = null  # LLMConfig 实例，由调用方通过 configure 注入

var _http_request: HTTPRequest = null
var _pending_on_done: Callable = Callable()
var _request_in_flight: bool = false

# FIFO 队列：多个调用方（如多 NPC daily todo）并发 request_chat 时，
# 单个 HTTPRequest 一次只能跑一个，其余排队，完成后依次 dispatch。
# 每项可携带 should_dispatch 谓词：dispatch 前若返回 false（如该 generation 已被新请求取代），
# 则跳过这次真实网络调用（省钱），直接回 superseded，不发请求。
var _queue: Array = []


func _ready() -> void:
	_ensure_http_request()


func configure(p_config) -> void:
	config = p_config
	_ensure_http_request()


func _ensure_http_request() -> void:
	if _http_request != null:
		return
	_http_request = HTTPRequest.new()
	_http_request.name = "LLMHTTPRequest"
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)


## request_chat: 发起一次 chat/completions 调用。
## opts: { "stream": bool, "json": bool, "kind": StringName, "should_dispatch"?: Callable }
##   should_dispatch（可选）：dispatch 前调用，返回 false 则跳过真实网络调用（省钱），
##   回 { ok:false, error:"superseded" }。用于 generation 已被新请求取代时不付费。
## on_done: Callable，回调 { "ok": true, "content": String, "status_code": int }
##                     或 { "ok": false, "error": String, "status_code": int }
##
## 并发安全：若已有请求在飞，新调用入 FIFO 队列，完成后依次 dispatch（单 HTTPRequest 串行）。
func request_chat(messages: Array, opts: Dictionary, on_done: Callable) -> void:
	if not _is_enabled():
		_call_done(on_done, {"ok": false, "error": "llm_disabled", "status_code": 0})
		return

	_ensure_http_request()

	if _request_in_flight:
		_queue.append({"messages": messages, "opts": opts, "on_done": on_done})
		return

	_start_request(messages, opts, on_done)


## _start_request: 真正发起一次 HTTPRequest（假定无 in-flight）。
func _start_request(messages: Array, opts: Dictionary, on_done: Callable) -> void:
	# generation currency 检查：调用方可注入 should_dispatch，若已过期则不发请求。
	var should_dispatch = opts.get("should_dispatch", null)
	if should_dispatch is Callable and should_dispatch.is_valid() and not bool(should_dispatch.call()):
		_call_done(on_done, {"ok": false, "error": "superseded", "status_code": 0})
		_dispatch_next()
		return

	var url := _chat_completions_url()
	if url.is_empty():
		_call_done(on_done, {"ok": false, "error": "missing_base_url", "status_code": 0})
		_dispatch_next()
		return

	var body := {
		"model": _model(),
		"messages": messages,
	}
	if bool(opts.get("json", false)):
		body["response_format"] = {"type": "json_object"}
	# MVP: 即使 opts.stream 为 true 也走非流式整体响应，回调里一次性返回 content。
	# 真·SSE 逐块流式留作后续；parse_sse_line 已为那条路径准备好。

	var headers := _request_headers()
	var json_body := JSON.stringify(body)

	print("[LLM] -> POST %s | model=%s | kind=%s | stream=%s | json=%s | msg_count=%d" % [
		url, _model(), str(opts.get("kind", "")), str(opts.get("stream", false)), str(opts.get("json", false)), messages.size()
	])

	_pending_on_done = on_done
	_request_in_flight = true
	var err := _http_request.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		_request_in_flight = false
		_pending_on_done = Callable()
		_call_done(on_done, {"ok": false, "error": "request_error_%d" % err, "status_code": 0})
		_dispatch_next()


## _dispatch_next: 从 FIFO 队列取下一项发起请求（假定当前无 in-flight）。
func _dispatch_next() -> void:
	if _request_in_flight or _queue.is_empty():
		return
	var item: Dictionary = _queue.pop_front()
	_start_request(item["messages"], item["opts"], item["on_done"])


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var on_done := _pending_on_done
	_pending_on_done = Callable()
	_request_in_flight = false

	if result != HTTPRequest.RESULT_SUCCESS:
		print("[LLM] <- FAIL http_result=%d status=%d" % [result, response_code])
		_call_done(on_done, {"ok": false, "error": "http_result_%d" % result, "status_code": response_code})
		_dispatch_next()
		return

	if response_code < 200 or response_code >= 300:
		var err_body := body.get_string_from_utf8()
		print("[LLM] <- FAIL http_status=%d body=%s" % [response_code, err_body.substr(0, 300)])
		_call_done(on_done, {"ok": false, "error": "http_status_%d" % response_code, "status_code": response_code})
		_dispatch_next()
		return

	var text := body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(text) != OK:
		print("[LLM] <- FAIL invalid_response_json | raw=%s" % text.substr(0, 200))
		_call_done(on_done, {"ok": false, "error": "invalid_response_json", "status_code": response_code})
		_dispatch_next()
		return
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		_call_done(on_done, {"ok": false, "error": "invalid_response_json", "status_code": response_code})
		_dispatch_next()
		return

	var content: Variant = _extract_message_content(parsed)
	if content == null:
		print("[LLM] <- FAIL missing_content status=%d" % response_code)
		_call_done(on_done, {"ok": false, "error": "missing_content", "status_code": response_code})
		_dispatch_next()
		return

	var content_str := str(content)
	print("[LLM] <- OK status=%d content_len=%d content=%s" % [response_code, content_str.length(), content_str.substr(0, 200)])
	_call_done(on_done, {"ok": true, "content": content_str, "status_code": response_code})
	_dispatch_next()


## parse_sse_line: 纯函数，解析单行 SSE。
## 返回 { "type": StringName, "content": String }。
##   不以 "data:" 开头        -> {type:&"ignore"}
##   "data: [DONE]"           -> {type:&"done"}
##   "data: {json}" 有内容    -> {type:&"delta", content:<文本>}（delta.content 或 message.content）
##   "data: {json}" 无内容/坏 -> {type:&"ignore"}
static func parse_sse_line(line: String) -> Dictionary:
	var trimmed := line.strip_edges()
	if not trimmed.begins_with("data:"):
		return {"type": &"ignore"}

	var payload := trimmed.substr(5).strip_edges()
	if payload.is_empty():
		return {"type": &"ignore"}
	if payload == "[DONE]":
		return {"type": &"done"}

	# 用实例 JSON.parse（返回 error code）而非 JSON.parse_string，
	# 后者在解析失败时会向引擎日志推一条 ERROR，污染 headless 测试输出。
	var json := JSON.new()
	if json.parse(payload) != OK:
		return {"type": &"ignore"}
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		return {"type": &"ignore"}

	var content = _extract_choice_content(parsed)
	if content == null or str(content).is_empty():
		return {"type": &"ignore"}
	return {"type": &"delta", "content": str(content)}


## 从 OpenAI 兼容的 choices[0] 中取 content，优先 delta.content（流式），
## 退回 message.content（非流式块）。取不到返回 null。
static func _extract_choice_content(parsed: Dictionary):
	var choices = parsed.get("choices", null)
	if not (choices is Array) or choices.is_empty():
		return null
	var choice = choices[0]
	if not (choice is Dictionary):
		return null
	var delta = choice.get("delta", null)
	if delta is Dictionary and delta.has("content") and delta["content"] != null:
		return delta["content"]
	var message = choice.get("message", null)
	if message is Dictionary and message.has("content") and message["content"] != null:
		return message["content"]
	return null


## 非流式完整响应里取 choices[0].message.content（也兼容 delta.content）。
func _extract_message_content(parsed: Dictionary):
	return _extract_choice_content(parsed)


func _is_enabled() -> bool:
	if config == null:
		return false
	# LLMConfig 暴露 enabled；用 duck-typing 兜底防止 LLMConfig 尚未落地。
	if config is Object and config.get("enabled") != null:
		return bool(config.get("enabled"))
	return false


func _model() -> String:
	if config != null and config is Object and config.get("model") != null:
		var model := str(config.get("model"))
		if not model.is_empty():
			return model
	return LLMConfigScript.DEFAULT_MODEL


func _chat_completions_url() -> String:
	var base := ""
	if config != null and config is Object and config.get("base_url") != null:
		base = str(config.get("base_url"))
	if base.is_empty():
		return ""
	return base.rstrip("/") + "/chat/completions"


func _request_headers() -> PackedStringArray:
	# 优先用 LLMConfig.headers()，它负责 Authorization / Content-Type / 可选 referer。
	if config != null and config is Object and config.has_method("headers"):
		var provided = config.headers()
		if provided is PackedStringArray:
			return provided
		if provided is Array:
			var packed := PackedStringArray()
			for entry in provided:
				packed.append(str(entry))
			return packed
	# 兜底：仅在 config 暴露 api_key 时构造最小 headers。
	var headers := PackedStringArray()
	headers.append("Content-Type: application/json")
	if config != null and config is Object and config.get("api_key") != null:
		var key := str(config.get("api_key"))
		if not key.is_empty():
			headers.append("Authorization: Bearer %s" % key)
	return headers


func _call_done(on_done: Callable, payload: Dictionary) -> void:
	if on_done.is_valid():
		on_done.call(payload)
