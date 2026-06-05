extends RefCounted
class_name NPCActionScheduler


var active_lanes: Dictionary = {}


func start_action(action: Dictionary) -> Dictionary:
	var npc_id := StringName(action.get("npc_id", ""))
	var lane := StringName(action.get("lane", ""))
	if npc_id == &"" or lane == &"":
		return {"accepted": false, "status": &"rejected", "reason": &"missing_npc_or_lane"}
	var key := _lane_key(npc_id, lane)
	if active_lanes.has(key):
		return {"accepted": false, "status": &"rejected", "reason": &"lane_locked", "active_action": active_lanes[key]}

	var running := action.duplicate(true)
	running["status"] = &"running"
	active_lanes[key] = running
	return {"accepted": true, "status": &"running", "action": running}


func try_start_action(action: Dictionary) -> Dictionary:
	return start_action(action)


func finish_action(npc_id: StringName, lane: StringName) -> bool:
	return active_lanes.erase(_lane_key(npc_id, lane))


func interrupt_action(npc_id: StringName, lane: StringName, event_log = null) -> bool:
	var key := _lane_key(npc_id, lane)
	if not active_lanes.has(key):
		return false
	var action: Dictionary = active_lanes[key]
	active_lanes.erase(key)
	if event_log != null and event_log.has_method("record"):
		event_log.record(&"npc_action_interrupted", npc_id, StringName(action.get("id", "")), lane)
	return true


func _lane_key(npc_id: StringName, lane: StringName) -> String:
	return "%s::%s" % [str(npc_id), str(lane)]
