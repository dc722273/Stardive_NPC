extends RefCounted
class_name InteractionEvent

const ConstantsScript := preload("res://scripts/core/Constants.gd")

var id: StringName = &""
var type: StringName = &""
var actor_id: StringName = &"player"
var primary_entity_id: StringName = &""
var target_entity_id: StringName = &""
var target_type: StringName = &"cell"
var cell: Vector2i = ConstantsScript.INVALID_CELL
var tick: int = 0
var payload: Dictionary = {}


static func from_dict(data: Dictionary):
	var state = load("res://scripts/state/InteractionEvent.gd").new()
	state.id = StringName(data.get("id", ""))
	state.type = StringName(data.get("type", ""))
	state.actor_id = StringName(data.get("actor_id", "player"))
	state.primary_entity_id = StringName(data.get("primary_entity_id", ""))
	state.target_entity_id = StringName(data.get("target_entity_id", ""))
	state.target_type = StringName(data.get("target_type", "cell"))
	state.cell = ConstantsScript.cell_from_dict(data.get("cell", ConstantsScript.INVALID_CELL))
	state.tick = int(data.get("tick", 0))
	var raw_payload: Variant = data.get("payload", {})
	if raw_payload is Dictionary:
		state.payload = raw_payload.duplicate(true)
	else:
		state.payload = {}
	return state


func to_dict() -> Dictionary:
	return {
		"id": id,
		"type": type,
		"actor_id": actor_id,
		"primary_entity_id": primary_entity_id,
		"target_entity_id": target_entity_id,
		"target_type": target_type,
		"cell": ConstantsScript.cell_to_dict(cell),
		"tick": tick,
		"payload": payload.duplicate(true),
	}
