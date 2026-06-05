extends RefCounted
class_name NPCState

const ConstantsScript := preload("res://scripts/core/Constants.gd")
const InteractionEventScript := preload("res://scripts/state/InteractionEvent.gd")
const TodoItemScript := preload("res://scripts/state/TodoItem.gd")

const DEFAULT_TRAITS := {
	"tell": 50,
	"face": 50,
	"control": 50,
	"caution": 50,
	"play": 50,
}

const DEFAULT_STYLE := {
	"leakActions": [],
	"coverActions": [],
	"wantActions": [],
	"rejectActions": [],
	"observeActions": [],
	"lineMode": "strategic_observer",
}

var id: StringName = &""
var name: String = ""
var traits: Dictionary = DEFAULT_TRAITS.duplicate(true)
var tags: Array = []
var style: Dictionary = DEFAULT_STYLE.duplicate(true)
var anim_set_id: String = ""

var performance_state: String = "idle"
var emotional_state: String = "neutral"
var stance_to_object: Dictionary = {}
var current_gag: Dictionary = {}
var cooldowns: Dictionary = {
	"lastMicroActionId": "",
	"lastLineMode": "",
	"lastReactedAt": 0,
}

var current_cell: Vector2i = Vector2i.ZERO
var position: Vector2 = Vector2.ZERO
var todo_list: Array = []
var recent_events: Array = []


static func from_dict(data: Dictionary):
	var state = load("res://scripts/state/NPCState.gd").new()
	state.id = StringName(data.get("id", data.get("npcId", "")))
	state.name = str(data.get("name", state.id))
	state.traits = _merge_dict(DEFAULT_TRAITS, data.get("traits", {}))
	state.tags = _array_from(data.get("tags", []))
	state.style = _merge_dict(DEFAULT_STYLE, data.get("style", {}))
	state.anim_set_id = str(data.get("animSetId", data.get("anim_set_id", state.id)))

	var runtime: Dictionary = _dict_from(data.get("runtime", data.get("runtimeState", {})))
	state.performance_state = str(runtime.get("performanceState", runtime.get("performance_state", "idle")))
	state.emotional_state = str(runtime.get("emotionalState", runtime.get("emotional_state", "neutral")))
	state.stance_to_object = _dict_from(runtime.get("stanceToObject", runtime.get("stance_to_object", {})))
	state.current_gag = _dict_from(runtime.get("currentGag", runtime.get("current_gag", {})))
	state.cooldowns = _merge_dict(state.cooldowns, runtime.get("cooldowns", {}))

	if data.has("position"):
		state.position = _vec2_from(data["position"])
		state.current_cell = ConstantsScript.world_to_cell(state.position)
	else:
		var fallback_cell := Vector2i(int(data.get("tile_x", 0)), int(data.get("tile_y", 0)))
		state.current_cell = ConstantsScript.cell_from_dict(data.get("current_cell", fallback_cell), fallback_cell)
		state.position = ConstantsScript.cell_to_world_center(state.current_cell)

	var raw_todos: Variant = data.get("todo_list", [])
	if raw_todos is Array:
		for value in raw_todos:
			if value is Object and value.has_method("to_dict"):
				state.todo_list.append(value)
			elif value is Dictionary:
				state.todo_list.append(TodoItemScript.from_dict(value))

	var raw_events: Variant = data.get("recent_events", [])
	if raw_events is Array:
		for value in raw_events:
			if value is Object and value.has_method("to_dict"):
				state.recent_events.append(value)
			elif value is Dictionary:
				state.recent_events.append(InteractionEventScript.from_dict(value))

	return state


func profile_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"traits": traits.duplicate(true),
		"tags": tags.duplicate(true),
		"style": style.duplicate(true),
		"animSetId": anim_set_id,
	}


func runtime_dict() -> Dictionary:
	var result := {
		"npcId": id,
		"performanceState": performance_state,
		"emotionalState": emotional_state,
		"cooldowns": cooldowns.duplicate(true),
	}
	if not stance_to_object.is_empty():
		result["stanceToObject"] = stance_to_object.duplicate(true)
	if not current_gag.is_empty():
		result["currentGag"] = current_gag.duplicate(true)
	return result


func to_dict() -> Dictionary:
	var todos: Array = []
	for todo in todo_list:
		todos.append(todo.to_dict())

	var events: Array = []
	for event in recent_events:
		events.append(event.to_dict())

	var result := profile_dict()
	result["runtime"] = runtime_dict()
	result["current_cell"] = ConstantsScript.cell_to_dict(current_cell)
	result["position"] = {"x": position.x, "y": position.y}
	result["todo_list"] = todos
	result["recent_events"] = events
	return result


static func _vec2_from(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.ZERO


static func _dict_from(value: Variant) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else {}


static func _array_from(value: Variant) -> Array:
	return value.duplicate(true) if value is Array else []


static func _merge_dict(base: Dictionary, override: Variant) -> Dictionary:
	var result := base.duplicate(true)
	if override is Dictionary:
		for key in override.keys():
			result[key] = override[key]
	return result
