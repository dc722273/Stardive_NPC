extends PanelContainer
class_name ScheduleSidebar

var _vbox: VBoxContainer
var _lines: Array = []
# 脏检查:记住当前渲染的 NPC 与内容指纹,避免 _process 每帧无谓重建 Label。
var _shown_npc_id: StringName = &""
var _last_fingerprint: String = ""


func _ready() -> void:
	if _vbox == null:
		_vbox = VBoxContainer.new()
		_vbox.name = "VBox"
		add_child(_vbox)
	visible = false


func _ensure_vbox() -> void:
	if _vbox == null:
		_vbox = VBoxContainer.new()
		_vbox.name = "VBox"
		add_child(_vbox)


func show_for_npc(npc) -> void:
	_ensure_vbox()
	clear()
	if npc == null or not (npc.todo_list is Array):
		return
	visible = true
	for todo in npc.todo_list:
		var prefix := _status_prefix(StringName(todo.status))
		var line := prefix + " " + str(todo.intent) + " — " + str(todo.reason)
		var label := Label.new()
		label.text = line
		_vbox.add_child(label)
		_lines.append(line)
	_shown_npc_id = StringName(npc.id) if npc is Object else &""
	_last_fingerprint = _fingerprint(npc)


## refresh_if_changed: 给 MainGame._process 每帧调用。仅当该 NPC 的 todo 内容(状态/intent/reason)
## 相对上次渲染发生变化时才重渲,返回是否重渲。无变化返回 false —— 避免每帧重建 Label。
func refresh_if_changed(npc) -> bool:
	if npc == null or not (npc is Object) or not (npc.todo_list is Array):
		return false
	var npc_id := StringName(npc.id)
	var fp := _fingerprint(npc)
	if npc_id == _shown_npc_id and fp == _last_fingerprint:
		return false
	show_for_npc(npc)
	return true


func clear() -> void:
	_ensure_vbox()
	for child in _vbox.get_children():
		child.queue_free()
	_lines = []
	visible = false
	_shown_npc_id = &""
	_last_fingerprint = ""


## _fingerprint: 把 todo_list 的可见内容(状态+intent+reason)拼成指纹串,用于脏检查。
func _fingerprint(npc) -> String:
	if npc == null or not (npc is Object) or not (npc.todo_list is Array):
		return ""
	var parts: Array = []
	for todo in npc.todo_list:
		parts.append("%s|%s|%s" % [str(todo.status), str(todo.intent), str(todo.reason)])
	return "\n".join(parts)


func get_rendered_lines() -> Array:
	return _lines.duplicate()


func _status_prefix(status: StringName) -> String:
	if status == &"done":
		return "✓"
	if status == &"active":
		return "▶"
	if status == &"BLOCKED":
		return "✗"
	return "·"
