extends PanelContainer
class_name FencedAreaEditPanel

signal placement_confirmed(result: Dictionary)
signal placement_cancelled

const BuildingPlacementServiceScript := preload("res://scripts/world/BuildingPlacementService.gd")

var building_placement_service = null
var pending_footprint: Rect2i = Rect2i()
var pending_drag_end_cell: Vector2i = Vector2i.ZERO
var current_tick: int = 0

var name_edit: LineEdit
var description_text: TextEdit
var confirm_button: Button
var cancel_button: Button
var status_label: Label


func _ready() -> void:
	_build_controls_if_needed()
	visible = false


func configure(service) -> void:
	building_placement_service = service


func open_for_selection(footprint: Rect2i, drag_end_cell: Vector2i, suggested_name: String = "Fenced Area") -> void:
	_build_controls_if_needed()
	pending_footprint = footprint
	pending_drag_end_cell = drag_end_cell
	name_edit.text = suggested_name
	description_text.text = ""
	status_label.text = ""
	visible = true
	name_edit.grab_focus()


func cancel_edit() -> void:
	visible = false
	emit_signal("placement_cancelled")


func confirm_fenced_area() -> void:
	_build_controls_if_needed()
	if building_placement_service == null:
		_show_status("placement service missing")
		return
	var place_name: String = name_edit.text.strip_edges()
	if place_name.is_empty():
		place_name = "Fenced Area"
	var result: Dictionary = building_placement_service.place_fenced_area(
		&"",
		place_name,
		description_text.text.strip_edges(),
		pending_footprint,
		pending_drag_end_cell,
		&"player",
		current_tick,
		""
	)
	emit_signal("placement_confirmed", result)
	if result.get("ok", false):
		visible = false
	else:
		_show_status(str(result.get("reason", "placement failed")))


func _build_controls_if_needed() -> void:
	if name_edit != null:
		return

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var stack := VBoxContainer.new()
	stack.custom_minimum_size = Vector2(280, 180)
	margin.add_child(stack)

	var title := Label.new()
	title.text = "FencedArea"
	stack.add_child(title)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "name"
	stack.add_child(name_edit)

	description_text = TextEdit.new()
	description_text.placeholder_text = "description"
	description_text.custom_minimum_size = Vector2(260, 72)
	stack.add_child(description_text)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(status_label)

	var buttons := HBoxContainer.new()
	stack.add_child(buttons)

	confirm_button = Button.new()
	confirm_button.text = "Create"
	confirm_button.pressed.connect(confirm_fenced_area)
	buttons.add_child(confirm_button)

	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(cancel_edit)
	buttons.add_child(cancel_button)


func _show_status(message: String) -> void:
	_build_controls_if_needed()
	status_label.text = message
