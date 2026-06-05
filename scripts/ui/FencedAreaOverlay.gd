extends Node2D
class_name FencedAreaOverlay

@export var cell_size: int = 32
@export var map_origin: Vector2 = Vector2.ZERO

const WorldPlaceRegistryScript := preload("res://scripts/world/WorldPlaceRegistry.gd")

var place_registry = null


func configure(registry) -> void:
	place_registry = registry
	queue_redraw()


func refresh_from_registry() -> void:
	queue_redraw()


func _draw() -> void:
	if place_registry == null:
		return
	var place_list: Array = place_registry.get("places").values()
	place_list.sort_custom(func(left, right) -> bool:
		return str(left.id) < str(right.id)
	)
	for place in place_list:
		_draw_place_footprint(place)
		_draw_fence_boundary(place)
		_draw_door(place)
		_draw_label(place)


func _draw_place_footprint(place) -> void:
	var rect := Rect2(_grid_to_world(place.footprint.position), Vector2(place.footprint.size.x * cell_size, place.footprint.size.y * cell_size))
	draw_rect(rect, Color(0.17, 0.56, 0.34, 0.18), true)


func _draw_fence_boundary(place) -> void:
	for cell in place.fence_cells:
		var rect := Rect2(_grid_to_world(cell), Vector2(cell_size, cell_size))
		draw_rect(rect, Color(0.45, 0.28, 0.14, 0.76), false, 2.0)


func _draw_door(place) -> void:
	if place.door_cell.x < -1000:
		return
	# Door marker circles are intentionally hidden; fence gaps already indicate doors.


func _draw_label(place) -> void:
	var label_position: Vector2 = _grid_to_world(place.footprint.position) + Vector2(4, -4)
	draw_string(ThemeDB.fallback_font, label_position, place.name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.92, 0.96, 0.92, 1.0))


func _grid_to_world(cell: Vector2i) -> Vector2:
	return map_origin + Vector2(cell.x * cell_size, cell.y * cell_size)
