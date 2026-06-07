extends RefCounted
class_name ItemState

const ConstantsScript := preload("res://scripts/core/Constants.gd")

const DEFAULT_ACCESS_RULE := {
	"allowedNpcIds": [],
	"publicKnown": true,
	"exclusivity": 0,
}

const DEFAULT_AFFORDANCE := {
	"draggable": true,
	"openable": false,
	"consumable": false,
}

const DEFAULT_SOCIAL := {
	"status": 0,
	"power": 0,
	"utility": 0,
	"debt": 0,
	"awkward": 0,
	"joke": 0,
	"danger": 0,
}

const DEFAULT_CLASSIFICATION := {
	"category": "",
	"subtype": "",
	"material": "",
}

var id: StringName = &""
var type_id: StringName = &""
var name: String = ""
var category: String = ""
var classification: Dictionary = DEFAULT_CLASSIFICATION.duplicate(true)
var owner_id: StringName = &""
var access_rule: Dictionary = DEFAULT_ACCESS_RULE.duplicate(true)
var current_anchor: Dictionary = {"type": "ground"}
var custody_state: String = "unclaimed"
var affordance: Dictionary = DEFAULT_AFFORDANCE.duplicate(true)
var social: Dictionary = DEFAULT_SOCIAL.duplicate(true)
var social_override: Dictionary = {}
var visual: Dictionary = {}
var state: Dictionary = {}
var memory: Dictionary = {"topLinks": []}
var current_cell: Vector2i = Vector2i.ZERO
var position: Vector2 = Vector2.ZERO


static func from_dict(data: Dictionary, object_types: Dictionary = {}):
	var object = load("res://scripts/state/ItemState.gd").new()
	object.id = StringName(data.get("id", data.get("objectId", "")))
	object.type_id = StringName(data.get("typeId", data.get("type_id", object.id)))
	var object_type: Dictionary = _dict_from(object_types.get(str(object.type_id), object_types.get(object.type_id, {})))
	var type_social: Dictionary = _dict_from(object_type.get("defaultSocial", {}))
	var type_affordance: Dictionary = _dict_from(object_type.get("defaultAffordance", {}))
	var type_classification: Dictionary = _dict_from(object_type.get("classification", {}))
	if type_classification.is_empty() and object_type.has("category"):
		type_classification = {"category": str(object_type.get("category", ""))}
	var instance_classification: Dictionary = _dict_from(data.get("classification", {}))
	object.name = str(data.get("name", object_type.get("name", object.id)))
	object.classification = _merge_dict(_merge_dict(DEFAULT_CLASSIFICATION, type_classification), instance_classification)
	object.category = str(data.get("category", object.classification.get("category", object_type.get("category", ""))))
	object.classification["category"] = object.category
	object.owner_id = StringName(data.get("ownerId", ""))
	object.access_rule = _merge_dict(DEFAULT_ACCESS_RULE, data.get("accessRule", {}))
	object.current_anchor = _dict_from(data.get("currentAnchor", {"type": "ground"}))
	object.custody_state = str(data.get("custodyState", "unclaimed"))
	object.affordance = _merge_dict(_merge_dict(DEFAULT_AFFORDANCE, type_affordance), data.get("affordance", {}))
	object.social_override = _dict_from(data.get("social", {}))
	object.social = _merge_dict(_merge_dict(DEFAULT_SOCIAL, type_social), object.social_override)
	object.visual = _merge_dict(_dict_from(object_type.get("visual", {})), data.get("visual", {}))
	object.state = _dict_from(data.get("state", {}))
	object.memory = _merge_dict({"topLinks": []}, data.get("memory", {}))

	if object.anchor_npc_id() != &"":
		object.current_cell = ConstantsScript.INVALID_CELL
		object.position = Vector2.ZERO
	elif data.has("position"):
		object.position = _vec2_from(data["position"])
		object.current_cell = ConstantsScript.world_to_cell(object.position)
	else:
		object.current_cell = ConstantsScript.cell_from_dict(data.get("current_cell", Vector2.ZERO), Vector2i.ZERO)
		object.position = ConstantsScript.cell_to_world_center(object.current_cell)
	return object


func anchor_type() -> String:
	return str(current_anchor.get("type", "ground"))


func anchor_npc_id() -> StringName:
	if anchor_type() != "npc":
		return &""
	return StringName(current_anchor.get("npcId", ""))


func anchor_npc_ids() -> Array:
	var raw: Variant = current_anchor.get("npcIds", [])
	if raw is Array:
		return raw.duplicate(true)
	var npc_id := anchor_npc_id()
	return [npc_id] if npc_id != &"" else []


func attach_to_npc(npc_id: StringName, new_custody_state: String = "unclaimed") -> void:
	current_anchor = {"type": "npc", "npcId": str(npc_id)}
	custody_state = new_custody_state
	current_cell = ConstantsScript.INVALID_CELL
	position = Vector2.ZERO


func attach_to_ground(world_position: Vector2, new_custody_state: String = "unclaimed") -> void:
	current_anchor = {"type": "ground"}
	custody_state = new_custody_state
	position = world_position
	current_cell = ConstantsScript.world_to_cell(position)


func to_dict() -> Dictionary:
	var result := {
		"id": id,
		"typeId": type_id,
		"ownerId": owner_id,
		"accessRule": access_rule.duplicate(true),
		"currentAnchor": current_anchor.duplicate(true),
		"custodyState": custody_state,
		"state": state.duplicate(true),
		"memory": memory.duplicate(true),
		"current_cell": ConstantsScript.cell_to_dict(current_cell),
		"position": {"x": position.x, "y": position.y},
	}
	if not social_override.is_empty():
		result["social"] = social_override.duplicate(true)
	return result


static func _vec2_from(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.ZERO


static func _dict_from(value: Variant) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else {}


static func _merge_dict(base: Dictionary, override: Variant) -> Dictionary:
	var result := base.duplicate(true)
	if override is Dictionary:
		for key in override.keys():
			result[key] = override[key]
	return result
