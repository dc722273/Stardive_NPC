extends RefCounted
class_name InteractionEventLog

const ConstantsScript := preload("res://scripts/core/Constants.gd")
const InteractionEventScript := preload("res://scripts/state/InteractionEvent.gd")

var events: Array = []
var next_event_number: int = 1


func append_event(event) -> Variant:
	if event.id == &"":
		event.id = _next_event_id()
	else:
		_advance_next_event_number_past(event.id)
	events.append(event)
	return event


func record(
	event_type: StringName,
	primary_entity_id: StringName = &"",
	target_entity_id: StringName = &"",
	target_type: StringName = &"cell",
	cell: Vector2i = ConstantsScript.INVALID_CELL,
	payload: Dictionary = {},
	actor_id: StringName = &"player",
	tick: int = 0
) -> Variant:
	var event = InteractionEventScript.new()
	event.id = _next_event_id()
	event.type = event_type
	event.actor_id = actor_id
	event.primary_entity_id = primary_entity_id
	event.target_entity_id = target_entity_id
	event.target_type = target_type
	event.cell = cell
	event.tick = tick
	event.payload = payload.duplicate(true)
	events.append(event)
	return event


func recent_events(limit: int = 10) -> Array:
	if limit <= 0:
		return []
	var start_index = max(0, events.size() - limit)
	return events.slice(start_index, events.size())


func to_dict() -> Dictionary:
	var serialized_events: Array = []
	for event in events:
		serialized_events.append(event.to_dict())
	return {
		"events": serialized_events,
		"next_event_number": next_event_number,
	}


func load_from_dict(data: Dictionary) -> void:
	events.clear()
	next_event_number = int(data.get("next_event_number", 1))
	var raw_events: Variant = data.get("events", [])
	if raw_events is Array:
		for value in raw_events:
			if value is Object and value.has_method("to_dict"):
				append_event(value)
			elif value is Dictionary:
				events.append(InteractionEventScript.from_dict(value))
	_update_next_event_number_from_loaded_events()


func _next_event_id() -> StringName:
	var event_id := StringName("event_%04d" % next_event_number)
	next_event_number += 1
	return event_id


func _update_next_event_number_from_loaded_events() -> void:
	for event in events:
		_advance_next_event_number_past(event.id)


func _advance_next_event_number_past(event_id: StringName) -> void:
	var id_text := str(event_id)
	if not id_text.begins_with("event_"):
		return
	var numeric_text := id_text.substr("event_".length())
	if not numeric_text.is_valid_int():
		return
	next_event_number = max(next_event_number, int(numeric_text) + 1)
