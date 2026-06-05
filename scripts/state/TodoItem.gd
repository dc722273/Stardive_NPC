extends RefCounted
class_name TodoItem


var id: StringName = &""
var intent: StringName = &"wander"
var target_place_id: StringName = &""
var target_npc_id: StringName = &""
var target_item_id: StringName = &""
var reason: String = ""
var priority: int = 0
var status: StringName = &"pending"


static func from_dict(data: Dictionary):
	var state = load("res://scripts/state/TodoItem.gd").new()
	state.id = StringName(data.get("id", ""))
	state.intent = StringName(data.get("intent", "wander"))
	state.target_place_id = StringName(data.get("target_place_id", ""))
	state.target_npc_id = StringName(data.get("target_npc_id", ""))
	state.target_item_id = StringName(data.get("target_item_id", ""))
	state.reason = str(data.get("reason", ""))
	state.priority = int(data.get("priority", 0))
	state.status = StringName(data.get("status", "pending"))
	return state


func to_dict() -> Dictionary:
	return {
		"id": id,
		"intent": intent,
		"target_place_id": target_place_id,
		"target_npc_id": target_npc_id,
		"target_item_id": target_item_id,
		"reason": reason,
		"priority": priority,
		"status": status,
	}
