extends PanelContainer
class_name NPCChatPanel

signal message_submitted(target_npc_id: StringName, message: String)

const MAX_HISTORY := 10
const UI_SCALE := 2.0
const PANEL_SIZE := Vector2(1120, 520)
const HISTORY_SIZE := Vector2(1088, 392)
const SELECTOR_SIZE := Vector2(240, 60)
const INPUT_HEIGHT := 60
const SEND_SIZE := Vector2(120, 60)
const FONT_SIZE := 32
const INPUT_ROW_TOP_OFFSET := 10

var target_selector: OptionButton
var history_label: RichTextLabel
var input_edit: LineEdit
var send_button: Button
var _history: Array[String] = []
var _target_ids: Array[StringName] = []


func _ready() -> void:
	_build_controls_if_needed()


func configure_npcs(npcs: Dictionary, selected_id: StringName = &"") -> void:
	_build_controls_if_needed()
	var previous_id := selected_id
	if previous_id == &"":
		previous_id = current_target_id()
	target_selector.clear()
	_target_ids = []
	var entries: Array = []
	for npc_id in npcs.keys():
		var npc = npcs[npc_id]
		entries.append({"id": StringName(npc_id), "name": str(npc.name if npc != null else npc_id)})
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("name", "")) < str(right.get("name", ""))
	)
	var selected_index := 0
	for entry in entries:
		var npc_id := StringName(entry.get("id", &""))
		_target_ids.append(npc_id)
		target_selector.add_item(str(entry.get("name", npc_id)))
		var index := target_selector.get_item_count() - 1
		target_selector.set_item_metadata(index, npc_id)
		if npc_id == previous_id:
			selected_index = index
	if target_selector.get_item_count() > 0:
		target_selector.select(selected_index)
	_update_input_enabled()


func current_target_id() -> StringName:
	_build_controls_if_needed()
	var index := target_selector.selected
	if index < 0 or index >= target_selector.get_item_count():
		return &""
	return StringName(target_selector.get_item_metadata(index))


func select_target(npc_id: StringName) -> void:
	_build_controls_if_needed()
	for index in range(target_selector.get_item_count()):
		if StringName(target_selector.get_item_metadata(index)) == npc_id:
			target_selector.select(index)
			return


func add_line(speaker: String, message: String) -> void:
	_build_controls_if_needed()
	var clean_speaker := speaker.strip_edges()
	var clean_message := message.strip_edges()
	if clean_speaker.is_empty() or clean_message.is_empty():
		return
	_history.append("[b]%s[/b]: %s" % [_escape_bbcode(clean_speaker), _escape_bbcode(clean_message)])
	while _history.size() > MAX_HISTORY:
		_history.pop_front()
	_render_history()


func set_waiting(waiting: bool) -> void:
	_build_controls_if_needed()
	input_edit.editable = not waiting
	send_button.disabled = waiting or current_target_id() == &""
	if not waiting:
		input_edit.grab_focus()


func _build_controls_if_needed() -> void:
	if input_edit != null:
		return

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(8 * UI_SCALE))
	margin.add_theme_constant_override("margin_top", int(8 * UI_SCALE))
	margin.add_theme_constant_override("margin_right", int(8 * UI_SCALE))
	margin.add_theme_constant_override("margin_bottom", int(8 * UI_SCALE))
	add_child(margin)

	var stack := VBoxContainer.new()
	stack.custom_minimum_size = PANEL_SIZE
	stack.add_theme_constant_override("separation", int(4 * UI_SCALE))
	margin.add_child(stack)

	history_label = RichTextLabel.new()
	history_label.bbcode_enabled = true
	history_label.fit_content = false
	history_label.scroll_following = true
	history_label.custom_minimum_size = HISTORY_SIZE
	history_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_label.size_flags_stretch_ratio = 1.0
	history_label.add_theme_font_size_override("font_size", FONT_SIZE)
	history_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	history_label.add_theme_font_size_override("bold_font_size", FONT_SIZE)
	stack.add_child(history_label)

	var controls_margin := MarginContainer.new()
	controls_margin.add_theme_constant_override("margin_top", INPUT_ROW_TOP_OFFSET)
	stack.add_child(controls_margin)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", int(4 * UI_SCALE))
	controls_margin.add_child(controls)

	target_selector = OptionButton.new()
	target_selector.custom_minimum_size = SELECTOR_SIZE
	target_selector.add_theme_font_size_override("font_size", FONT_SIZE)
	target_selector.item_selected.connect(func(_index: int) -> void:
		_update_input_enabled()
	)
	controls.add_child(target_selector)

	input_edit = LineEdit.new()
	input_edit.placeholder_text = "说点什么"
	input_edit.custom_minimum_size = Vector2(0, INPUT_HEIGHT)
	input_edit.add_theme_font_size_override("font_size", FONT_SIZE)
	input_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_edit.text_submitted.connect(func(_text: String) -> void:
		_submit_message()
	)
	controls.add_child(input_edit)

	send_button = Button.new()
	send_button.text = "发送"
	send_button.custom_minimum_size = SEND_SIZE
	send_button.add_theme_font_size_override("font_size", FONT_SIZE)
	send_button.pressed.connect(_submit_message)
	controls.add_child(send_button)

	_update_input_enabled()


func _submit_message() -> void:
	var message := input_edit.text.strip_edges()
	var target_id := current_target_id()
	if message.is_empty() or target_id == &"":
		return
	input_edit.text = ""
	emit_signal("message_submitted", target_id, message)


func _render_history() -> void:
	history_label.text = "\n".join(_history)
	_scroll_history_to_latest()
	call_deferred("_scroll_history_to_latest")


func _scroll_history_to_latest() -> void:
	if history_label == null:
		return
	history_label.scroll_to_line(max(0, history_label.get_line_count() - 1))


func _update_input_enabled() -> void:
	if input_edit == null or send_button == null:
		return
	var has_target := current_target_id() != &""
	input_edit.editable = has_target
	send_button.disabled = not has_target


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "［").replace("]", "］")
