extends RefCounted
class_name WorldPlaceRegistry

const ConstantsScript := preload("res://scripts/core/Constants.gd")
const FencedAreaPlaceScript := preload("res://scripts/state/FencedAreaPlace.gd")

var places: Dictionary = {}
var next_place_number: int = 1


func create_place(
	place_id: StringName,
	place_name: String,
	place_description: String,
	footprint: Rect2i,
	door_cell: Vector2i,
	fence_cells: Array,
	interior_cells: Array,
	created_by: StringName = &"player",
	updated_at_tick: int = 0,
	emoji: String = ""
):
	if place_id == &"":
		place_id = _next_place_id()
	else:
		_advance_next_place_number_past(place_id)
	if places.has(place_id):
		return null

	var place = FencedAreaPlaceScript.new()
	place.id = place_id
	place.name = place_name
	place.description = place_description
	place.created_by = created_by
	place.updated_at_tick = updated_at_tick
	place.emoji = emoji
	place.footprint = footprint
	place.door_cell = door_cell
	place.fence_cells = _typed_cell_array(fence_cells)
	place.interior_cells = _typed_cell_array(interior_cells)
	places[place_id] = place
	return place


func update_text(place_id: StringName, place_name: String, place_description: String, emoji: String = "", updated_at_tick: int = 0) -> bool:
	if not places.has(place_id):
		return false
	var place = places[place_id]
	place.name = place_name
	place.description = place_description
	place.emoji = emoji
	place.updated_at_tick = updated_at_tick
	return true


func remove_place(place_id: StringName) -> bool:
	return places.erase(place_id)


func get_place_at_cell(cell: Vector2i):
	for place in _sorted_places():
		if place.footprint.has_point(cell):
			return place
	return null


func get_places_near_cell(cell: Vector2i, radius: int = 1) -> Array:
	var result: Array = []
	for place in _sorted_places():
		if _place_is_near_cell(place, cell, radius):
			result.append(place)
	return result


func get_random_cell_in_place(place_id: StringName, rng = null) -> Vector2i:
	if not places.has(place_id):
		return ConstantsScript.INVALID_CELL
	var place = places[place_id]
	# spec: get_random_cell_in_place may only return door_cell or an interior
	# cell, never a fence cell. interior_cells are walkable by construction; when
	# there is no interior, the only legal non-fence cell is the door. Never fall
	# back to fence_cells or the raw footprint rect (those would expose fence
	# cells, which NPC autonomous movement treats as solid).
	var candidates: Array = place.interior_cells.duplicate()
	if candidates.is_empty():
		if place.door_cell != ConstantsScript.INVALID_CELL and not place.fence_cells.has(place.door_cell):
			candidates = [place.door_cell]
	if candidates.is_empty():
		return ConstantsScript.INVALID_CELL
	candidates = _sorted_cells(candidates)
	if rng != null and rng.has_method("randi_range"):
		return candidates[int(rng.randi_range(0, candidates.size() - 1))]
	return candidates[0]


func to_dict() -> Dictionary:
	var serialized_places: Array = []
	for place in _sorted_places():
		serialized_places.append(place.to_dict())
	return {
		"places": serialized_places,
		"next_place_number": next_place_number,
	}


func load_from_dict(data: Dictionary) -> void:
	places.clear()
	next_place_number = int(data.get("next_place_number", 1))
	var raw_places: Variant = data.get("places", [])
	if raw_places is Array:
		for value in raw_places:
			var place = null
			if value is Object and value.has_method("to_dict"):
				place = value
			elif value is Dictionary:
				place = FencedAreaPlaceScript.from_dict(value)
			if place != null and place.id != &"":
				places[place.id] = place
				_advance_next_place_number_past(place.id)


func _next_place_id() -> StringName:
	var place_id: StringName = StringName("place_%04d" % next_place_number)
	next_place_number += 1
	return place_id


func _advance_next_place_number_past(place_id: StringName) -> void:
	var id_text: String = str(place_id)
	if not id_text.begins_with("place_"):
		return
	var numeric_text: String = id_text.substr("place_".length())
	if not numeric_text.is_valid_int():
		return
	next_place_number = max(next_place_number, int(numeric_text) + 1)


func _place_is_near_cell(place, cell: Vector2i, radius: int) -> bool:
	var min_x: int = place.footprint.position.x - radius
	var max_x: int = place.footprint.position.x + place.footprint.size.x - 1 + radius
	var min_y: int = place.footprint.position.y - radius
	var max_y: int = place.footprint.position.y + place.footprint.size.y - 1 + radius
	return cell.x >= min_x and cell.x <= max_x and cell.y >= min_y and cell.y <= max_y


func _cells_in_rect(rect: Rect2i) -> Array:
	var result: Array = []
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			result.append(Vector2i(x, y))
	return result


func _typed_cell_array(values: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for value in values:
		result.append(value)
	return result


func _sorted_places() -> Array:
	var result: Array = places.values()
	result.sort_custom(func(left, right) -> bool:
		return str(left.id) < str(right.id)
	)
	return result


func _sorted_cells(cells: Array) -> Array:
	var result: Array = cells.duplicate()
	result.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		if left.y == right.y:
			return left.x < right.x
		return left.y < right.y
	)
	return result
