extends RefCounted
class_name LLMClient


var current_generations: Dictionary = {}
var current_operation_ids: Dictionary = {}
var operations: Dictionary = {}
var next_operation_number: int = 1


func start_operation(npc_id: StringName, kind: StringName) -> Dictionary:
	var key := _operation_key(npc_id, kind)
	var generation: int = int(current_generations.get(key, 0)) + 1
	var operation_id := StringName("llm_op_%04d" % next_operation_number)
	next_operation_number += 1

	current_generations[key] = generation
	current_operation_ids[key] = operation_id
	operations[operation_id] = {
		"id": operation_id,
		"operation_id": operation_id,
		"npc_id": npc_id,
		"kind": kind,
		"generation": generation,
		"buffer": "",
		"cancelled": false,
		"committed": false,
	}
	return operations[operation_id].duplicate(true)


func append_stream_chunk(operation_id: StringName, chunk: String) -> Dictionary:
	if not operations.has(operation_id):
		return {"accepted": false, "status": &"missing_operation"}
	var operation: Dictionary = operations[operation_id]
	if bool(operation.get("cancelled", false)):
		return {"accepted": false, "status": &"cancelled"}
	if not _is_current_operation(operation):
		return {"accepted": false, "status": &"late"}
	operation["buffer"] = str(operation.get("buffer", "")) + chunk
	operations[operation_id] = operation
	return {"accepted": true, "status": &"buffered", "buffer": operation["buffer"]}


func complete_operation(operation_id: StringName, final_text: String = "") -> Dictionary:
	if not operations.has(operation_id):
		return {"committed": false, "status": &"missing_operation"}
	var operation: Dictionary = operations[operation_id]
	if bool(operation.get("cancelled", false)):
		return {"committed": false, "status": &"cancelled"}
	if not _is_current_operation(operation):
		return {"committed": false, "status": &"late"}

	var text := final_text
	if text.is_empty():
		text = str(operation.get("buffer", ""))
	if not _is_valid_final_payload(text):
		return {"committed": false, "status": &"invalid_payload", "text": text}

	operation["buffer"] = text
	operation["committed"] = true
	operations[operation_id] = operation
	return {
		"committed": true,
		"status": &"committed",
		"text": text,
		"operation_id": operation_id,
		"generation": int(operation.get("generation", 0)),
	}


func cancel_operation(operation_id: StringName) -> bool:
	if not operations.has(operation_id):
		return false
	var operation: Dictionary = operations[operation_id]
	operation["cancelled"] = true
	operations[operation_id] = operation
	return true


func _is_current_operation(operation: Dictionary) -> bool:
	var key := _operation_key(StringName(operation.get("npc_id", "")), StringName(operation.get("kind", "")))
	return current_operation_ids.get(key, &"") == operation.get("operation_id", &"") and int(current_generations.get(key, 0)) == int(operation.get("generation", 0))


func _operation_key(npc_id: StringName, kind: StringName) -> String:
	return "%s::%s" % [str(npc_id), str(kind)]


func _is_valid_final_payload(text: String) -> bool:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return false
	if not (trimmed.begins_with("[") or trimmed.begins_with("{")):
		return true
	var parsed: Variant = JSON.parse_string(trimmed)
	return parsed != null
