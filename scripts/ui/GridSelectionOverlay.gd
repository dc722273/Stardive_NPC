extends Node2D
class_name GridSelectionOverlay

signal cell_clicked(cell: Vector2i)
signal drag_started(start_cell: Vector2i)
signal drag_changed(selection_rect: Rect2i, end_cell: Vector2i)
signal drag_finished(selection_rect: Rect2i, end_cell: Vector2i)

@export var cell_size: int = 32
@export var map_origin: Vector2 = Vector2.ZERO
@export var enabled: bool = true
# 仅建造模式（fenced_area_mode）绘制 drag-rect 选中框；MainGame.toggle_fenced_area_mode 同步。
var build_mode: bool = false

var is_dragging: bool = false
var drag_start_cell: Vector2i = Vector2i.ZERO
var drag_end_cell: Vector2i = Vector2i.ZERO
var selection_rect: Rect2i = Rect2i()
# 视觉 hit-test 用：记录左键按下时的世界坐标（MainGame.select_cell_target 据此选最近实体）。
var _last_click_world: Vector2 = Vector2.ZERO


func get_last_click_world() -> Vector2:
	return _last_click_world


func _ready() -> void:
	set_process_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_mouse_drag(event.position)
		else:
			_finish_mouse_drag(event.position)
	elif event is InputEventMouseMotion and is_dragging:
		_update_mouse_drag(event.position)


func screen_to_grid(screen_position: Vector2) -> Vector2i:
	var world_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen_position
	return world_to_grid(world_position)


func world_to_grid(world_position: Vector2) -> Vector2i:
	var local_position: Vector2 = world_position - map_origin
	return Vector2i(floor(local_position.x / float(cell_size)), floor(local_position.y / float(cell_size)))


func grid_to_world(cell: Vector2i) -> Vector2:
	return map_origin + Vector2(cell.x * cell_size, cell.y * cell_size)


func get_selection_rect() -> Rect2i:
	return selection_rect


func _begin_mouse_drag(screen_position: Vector2) -> void:
	is_dragging = true
	_last_click_world = get_local_mouse_position()
	drag_start_cell = screen_to_grid(screen_position)
	drag_end_cell = drag_start_cell
	selection_rect = _make_drag_rect(drag_start_cell, drag_end_cell)
	emit_signal("cell_clicked", drag_start_cell)
	emit_signal("drag_started", drag_start_cell)
	queue_redraw()


func _update_mouse_drag(screen_position: Vector2) -> void:
	drag_end_cell = screen_to_grid(screen_position)
	selection_rect = _make_drag_rect(drag_start_cell, drag_end_cell)
	emit_signal("drag_changed", selection_rect, drag_end_cell)
	queue_redraw()


func _finish_mouse_drag(screen_position: Vector2) -> void:
	if not is_dragging:
		return
	drag_end_cell = screen_to_grid(screen_position)
	selection_rect = _make_drag_rect(drag_start_cell, drag_end_cell)
	is_dragging = false
	emit_signal("drag_finished", selection_rect, drag_end_cell)
	queue_redraw()


func _make_drag_rect(start_cell: Vector2i, end_cell: Vector2i) -> Rect2i:
	var min_cell := Vector2i(min(start_cell.x, end_cell.x), min(start_cell.y, end_cell.y))
	var max_cell := Vector2i(max(start_cell.x, end_cell.x), max(start_cell.y, end_cell.y))
	return Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)


func _draw() -> void:
	# 非建造模式不画 drag-rect 选中框（仅建造模式才显示）。
	if not build_mode:
		return
	if selection_rect.size.x <= 0 or selection_rect.size.y <= 0:
		return
	var top_left: Vector2 = grid_to_world(selection_rect.position)
	var size := Vector2(selection_rect.size.x * cell_size, selection_rect.size.y * cell_size)
	var preview := Rect2(top_left, size)
	draw_rect(preview, Color(0.2, 0.65, 1.0, 0.16), true)
	draw_rect(preview, Color(0.2, 0.65, 1.0, 0.9), false, 2.0)
