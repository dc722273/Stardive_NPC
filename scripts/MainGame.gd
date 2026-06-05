extends Node2D
class_name MainGame

const ConstantsScript := preload("res://scripts/core/Constants.gd")
const BuildingPlacementServiceScript := preload("res://scripts/world/BuildingPlacementService.gd")
const GridPathfinderScript := preload("res://scripts/world/GridPathfinder.gd")
const InteractionEventLogScript := preload("res://scripts/world/InteractionEventLog.gd")
const ItemStateScript := preload("res://scripts/state/ItemState.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const TodoItemScript := preload("res://scripts/state/TodoItem.gd")
const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const WorldPlaceRegistryScript := preload("res://scripts/world/WorldPlaceRegistry.gd")
const LLMConfigScript := preload("res://scripts/npc/LLMConfig.gd")
const LLMTransportScript := preload("res://scripts/npc/LLMTransport.gd")
const LLMClientScript := preload("res://scripts/npc/LLMClient.gd")
const DailyTodoPlannerScript := preload("res://scripts/npc/DailyTodoPlanner.gd")
const NPCFeedbackBuilderScript := preload("res://scripts/npc/NPCFeedbackBuilder.gd")
const NPCMoverScript := preload("res://scripts/npc/NPCMover.gd")
const TodoExecutorScript := preload("res://scripts/npc/TodoExecutor.gd")
const NPCActionSchedulerScript := preload("res://scripts/npc/NPCActionScheduler.gd")
const GameClockScript := preload("res://scripts/world/GameClock.gd")
const ConfigLoaderScript := preload("res://scripts/config/ConfigLoader.gd")
const InteractionDeltaRulesScript := preload("res://scripts/world/InteractionDeltaRules.gd")
const HeldItemLayoutScript := preload("res://scripts/ui/HeldItemLayout.gd")

@export var cell_size: int = 64
@export var camera_speed: float = 420.0
@export var map_bounds: Rect2i = Rect2i(0, 0, 30, 25)

# 拖拽重力感：被抓实体每帧朝鼠标世界坐标插值，GRAB_PULL 为每帧拉拽比例。
const GRAB_PULL := 0.2
# 视觉 hit-test 选中半径（像素）：点击世界坐标落在该半径内即选中最近实体。
const HIT_RADIUS := 58.0
const NPC_CENTER_GRAB_RADIUS := 16.0
# 滚轮 zoom：以光标为锚，每档乘 ZOOM_STEP / 除 ZOOM_STEP，clamp 到 [ZOOM_MIN, ZOOM_MAX]。
const DEFAULT_BG_PATH := "res://assets/bg/鹅城地图.png"
const ZOOM_MIN := 0.8
const ZOOM_MAX := 2.35
const ZOOM_STEP := 1.12
const MOUSE_DRAG_THRESHOLD := 8.0
const FEEDBACK_PAUSE_SECONDS := 8.0
# 控制 UI 折叠提示：角落一行 "[H] 控制说明"，按 H 展开/收起完整按键表。
const CONTROLS_FULL := "[H] 收起\nWASD 移动镜头\n空白处左键拖动画布\nF 建造模式\n滚轮 缩放\n左键 选中/拖拽\n右键 丢弃手持物\nCtrl+S 保存 / Ctrl+L 读取"
var grab_mouse_world: Vector2 = Vector2.ZERO
var camera_dragging: bool = false
var camera_drag_started: bool = false
var camera_drag_start_screen: Vector2 = Vector2.ZERO

var entity_registry
var place_registry
var pathfinder
var placement_service
var event_log

var llm_config
var llm_transport
var llm_client
var daily_todo_planner
var npc_feedback_builder

# NPC 执行层：每个 NPC 一个 mover（持路径状态），共享 executor + scheduler。
var npc_movers: Dictionary = {}   # npc_id(StringName) -> NPCMover
var npc_feedback_pause_until_ms: Dictionary = {}  # npc_id(StringName) -> timestamp_ms
var todo_executor
var action_scheduler

# 执行节流：每隔 npc_execution_interval 秒自动驱动一次 NPC 执行（瞬移式 executor）。
@export var npc_execution_interval: float = 0.8
var _execution_accumulator: float = 0.0

var world_map: Node2D
var world_state: Node
var npc_system: Node
var ui_layer: CanvasLayer
var camera: Camera2D
var background_sprite: Sprite2D
var grid_selection_overlay
var entity_visual_layer
var fenced_area_overlay
var fenced_area_edit_panel
var feedback_label: Label
var controls_hint: Label
var _controls_expanded: bool = false
var schedule_sidebar
var clock_label: Label
var game_clock
var gameplay_config: Dictionary = {}
var npc_config_by_id: Dictionary = {}

var selected_entity_id: StringName = &""
var grabbed_entity_id: StringName = &""
var dragged_item_previous_anchor_npc_id: StringName = &""
var last_selected_cell: Vector2i = ConstantsScript.INVALID_CELL
var fenced_area_mode: bool = false
var latest_drag_rect: Rect2i = Rect2i()
var latest_drag_end_cell: Vector2i = ConstantsScript.INVALID_CELL
var saved_snapshot: Dictionary = {}
var tick: int = 0


func _ready() -> void:
	_resolve_scene_nodes()
	_fit_world_background(DEFAULT_BG_PATH)
	_wire_core_world_services()
	_wire_npc_llm_services()
	_seed_sample_npc_item_data()
	_wire_ui_nodes()
	_update_feedback_text("Ready")
	print("[NPC] _ready done | npcs=%d | executor=%s | scheduler=%s | exec_interval=%.2fs" % [
		entity_registry.npcs.size() if entity_registry != null else -1,
		"ok" if todo_executor != null else "NULL",
		"ok" if action_scheduler != null else "NULL",
		npc_execution_interval,
	])
	for npc in entity_registry.npcs.values():
		print("[NPC]   seeded %s at %s, todos=%d" % [str(npc.id), str(npc.current_cell), npc.todo_list.size()])


func _process(delta: float) -> void:
	tick += 1
	_move_camera_from_input(delta)
	# 节流驱动 NPC 执行：每隔 npc_execution_interval 秒消费一步 todo（瞬移式）。
	_execution_accumulator += delta
	if _execution_accumulator >= npc_execution_interval:
		_execution_accumulator = 0.0
		tick_npc_execution()
	# 逐帧推进层：每帧把非 idle 的 NPC 沿 waypoints 连续移动一步。
	advance_npc_movement(delta)
	# 拖拽重力感：左键按住时把被抓实体每帧朝鼠标世界坐标拉近。
	_apply_drag_gravity()
	# 时钟驱动自动日程：每帧推进时钟，跨入新一天的早上事件触发一次每日规划。
	if game_clock != null:
		game_clock.advance(delta)
		if game_clock.consume_morning_event():
			request_daily_todos_for_all_npcs()
		if clock_label != null:
			clock_label.text = game_clock.time_label()
	if entity_visual_layer != null:
		entity_visual_layer.sync_from_registry(entity_registry)
	# 选中 NPC 的日程侧栏实时刷新:todo 状态变化时(脏检查,无变化不重建)自动重渲。
	if schedule_sidebar != null and selected_entity_id != &"" and entity_registry.npcs.has(selected_entity_id):
		schedule_sidebar.refresh_if_changed(entity_registry.npcs[selected_entity_id])
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		discard_held_item_with_right_click()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_camera_drag()
	if event is InputEventMouseMotion and camera_dragging:
		_update_camera_drag(event)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			apply_zoom(ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			apply_zoom(1.0 / ZOOM_STEP)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			toggle_fenced_area_mode()
		elif event.keycode == KEY_T:
			generate_daily_todo_hotkey_placeholder()
		elif event.keycode == KEY_S and event.ctrl_pressed:
			save_game_state()
		elif event.keycode == KEY_L and event.ctrl_pressed:
			load_game_state()
		elif event.keycode == KEY_H:
			toggle_controls_hint()


func toggle_controls_hint() -> void:
	_controls_expanded = not _controls_expanded
	if controls_hint != null:
		controls_hint.text = CONTROLS_FULL if _controls_expanded else "[H] 控制说明"


func _draw() -> void:
	# 背景由旧 Stardive 美术图提供；这里只在缺图时保底画底色。
	var origin := Vector2(map_bounds.position.x * cell_size, map_bounds.position.y * cell_size)
	var size := Vector2(map_bounds.size.x * cell_size, map_bounds.size.y * cell_size)
	if background_sprite == null or background_sprite.texture == null:
		draw_rect(Rect2(origin, size), Color(0.30, 0.55, 0.28, 1.0), true)
	# 网格线仅建造模式可见（用于定位建筑）。
	if fenced_area_mode:
		for x in range(map_bounds.position.x, map_bounds.position.x + map_bounds.size.x + 1):
			var sx := Vector2(x * cell_size, map_bounds.position.y * cell_size)
			var ex := Vector2(x * cell_size, (map_bounds.position.y + map_bounds.size.y) * cell_size)
			draw_line(sx, ex, Color(1, 1, 1, 0.25), 1.0)
		for y in range(map_bounds.position.y, map_bounds.position.y + map_bounds.size.y + 1):
			var sy := Vector2(map_bounds.position.x * cell_size, y * cell_size)
			var ey := Vector2((map_bounds.position.x + map_bounds.size.x) * cell_size, y * cell_size)
			draw_line(sy, ey, Color(1, 1, 1, 0.25), 1.0)


func _move_camera_from_input(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		direction.y += 1.0
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction.x += 1.0

	if direction != Vector2.ZERO and camera != null:
		camera.position += direction.normalized() * camera_speed * delta
		_clamp_camera_to_bounds()


# 滚轮 zoom（以光标为锚）：缩放后修正 camera.position，使鼠标指向的 world 点保持不动。
func apply_zoom(factor: float) -> void:
	if camera == null or world_map == null:
		return
	var mouse_world_before: Vector2 = world_map.get_local_mouse_position()
	var before: float = camera.zoom.x
	var target: float = clamp(before * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(target, target)
	var mouse_world_after: Vector2 = world_map.get_local_mouse_position()
	camera.position += mouse_world_before - mouse_world_after
	_clamp_camera_to_bounds()


func _begin_camera_drag() -> void:
	if fenced_area_mode or grabbed_entity_id != &"":
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	camera_dragging = true
	camera_drag_started = false
	camera_drag_start_screen = viewport.get_mouse_position()


func _update_camera_drag(event: InputEventMouseMotion) -> void:
	if camera == null:
		return
	if not camera_drag_started and event.position.distance_to(camera_drag_start_screen) >= MOUSE_DRAG_THRESHOLD:
		camera_drag_started = true
	if not camera_drag_started:
		return
	var zoom_value: float = max(camera.zoom.x, 0.01)
	camera.position -= event.relative / zoom_value
	_clamp_camera_to_bounds()


func _end_camera_drag() -> void:
	camera_dragging = false
	camera_drag_started = false


func _camera_bounds_rect() -> Rect2:
	return Rect2(
		Vector2(map_bounds.position.x * cell_size, map_bounds.position.y * cell_size),
		Vector2(map_bounds.size.x * cell_size, map_bounds.size.y * cell_size)
	)


func _clamp_camera_to_bounds() -> void:
	if camera == null:
		return
	var bounds := _camera_bounds_rect()
	var viewport := get_viewport()
	if viewport == null:
		camera.position = bounds.get_center()
		return
	var viewport_size := viewport.get_visible_rect().size
	var half_view := Vector2(
		(viewport_size.x * 0.5) / max(camera.zoom.x, 0.01),
		(viewport_size.y * 0.5) / max(camera.zoom.y, 0.01)
	)
	var min_pos := bounds.position + half_view
	var max_pos := bounds.position + bounds.size - half_view
	if min_pos.x > max_pos.x:
		min_pos.x = bounds.get_center().x
		max_pos.x = bounds.get_center().x
	if min_pos.y > max_pos.y:
		min_pos.y = bounds.get_center().y
		max_pos.y = bounds.get_center().y
	camera.position = Vector2(
		clamp(camera.position.x, min_pos.x, max_pos.x),
		clamp(camera.position.y, min_pos.y, max_pos.y)
	)


## 选中 = 视觉 hit-test：点击世界坐标 → HIT_RADIUS 内最近实体。
## 入参仍是 cell（保持与 GridSelectionOverlay.cell_clicked 信号兼容）；优先用 overlay 记录的
## 真实点击世界坐标，无 overlay 时退回 cell 中心。
func select_cell_target(cell: Vector2i) -> void:
	last_selected_cell = cell
	var click_world: Vector2 = ConstantsScript.cell_to_world_center(cell)
	if grid_selection_overlay != null and grid_selection_overlay.has_method("get_last_click_world"):
		click_world = grid_selection_overlay.get_last_click_world()
	var hit_id := _hit_test_entity(click_world)
	if hit_id != &"":
		selected_entity_id = hit_id
		grabbed_entity_id = hit_id
		grab_mouse_world = click_world
		_update_selected_highlight()
		if schedule_sidebar != null and entity_registry.npcs.has(hit_id):
			schedule_sidebar.show_for_npc(entity_registry.npcs[hit_id])
		elif schedule_sidebar != null:
			schedule_sidebar.clear()
		_update_feedback_text("Selected %s" % str(hit_id))
		return
	selected_entity_id = &""
	grabbed_entity_id = &""
	_update_selected_highlight()
	if schedule_sidebar != null:
		schedule_sidebar.clear()
	_begin_camera_drag()
	_update_feedback_text("Selected cell %s" % str(cell))


func _hit_test_entity(world_pos: Vector2) -> StringName:
	var held_item_id := _hit_test_held_item_for_drag(world_pos)
	if held_item_id != &"":
		return held_item_id

	var best_id: StringName = &""
	var best_dist: float = HIT_RADIUS
	for npc in entity_registry.npcs.values():
		var d: float = npc.position.distance_to(world_pos)
		if d <= best_dist:
			best_dist = d
			best_id = npc.id
	for item in entity_registry.items.values():
		var d: float = _item_world_position(item.id).distance_to(world_pos)
		if d <= best_dist:
			best_dist = d
			best_id = item.id
	return best_id


func _hit_test_held_item_for_drag(world_pos: Vector2) -> StringName:
	var best_id: StringName = &""
	var best_dist: float = HeldItemLayoutScript.HELD_ITEM_DRAG_HIT_RADIUS
	for item in entity_registry.items.values():
		if item.anchor_npc_id() == &"":
			continue
		var anchor_npc_id: StringName = item.anchor_npc_id()
		if entity_registry.npcs.has(anchor_npc_id) and entity_registry.npcs[anchor_npc_id].position.distance_to(world_pos) <= NPC_CENTER_GRAB_RADIUS:
			continue
		var d: float = _item_world_position(item.id).distance_to(world_pos)
		if d <= best_dist:
			best_dist = d
			best_id = item.id
	return best_id


func _hit_test_npc_only(world_pos: Vector2, exclude_id: StringName = &"") -> StringName:
	var best_id: StringName = &""
	var best_dist: float = HIT_RADIUS
	for npc in entity_registry.npcs.values():
		if npc.id == exclude_id:
			continue
		var d: float = npc.position.distance_to(world_pos)
		if d <= best_dist:
			best_dist = d
			best_id = npc.id
	return best_id


func _hit_test_item_only(world_pos: Vector2) -> StringName:
	var best_id: StringName = &""
	var best_dist: float = HIT_RADIUS
	for item in entity_registry.items.values():
		var d: float = _item_world_position(item.id).distance_to(world_pos)
		if d <= best_dist:
			best_dist = d
			best_id = item.id
	return best_id


func _update_selected_highlight() -> void:
	if entity_visual_layer == null:
		return
	for npc_id in entity_visual_layer.npc_visuals.keys():
		var v = entity_visual_layer.npc_visuals[npc_id]
		v.selected = (npc_id == selected_entity_id)
		v.queue_redraw()


func start_drag_grab(cell: Vector2i) -> void:
	select_cell_target(cell)
	dragged_item_previous_anchor_npc_id = &""
	if entity_registry != null and entity_registry.items.has(grabbed_entity_id):
		dragged_item_previous_anchor_npc_id = entity_registry.items[grabbed_entity_id].anchor_npc_id()


func update_drag_preview(selection_rect: Rect2i, end_cell: Vector2i) -> void:
	latest_drag_rect = selection_rect
	latest_drag_end_cell = end_cell
	if fenced_area_mode:
		_update_feedback_text("FencedArea footprint %s" % str(selection_rect))


## 拖拽重力感：左键按住时把被抓实体（npc 或 item）每帧朝鼠标世界坐标插值拉近。
## 位置是 source of truth，current_cell 仅作 derived mirror 同步更新。
func _apply_drag_gravity() -> void:
	if grabbed_entity_id == &"" or world_map == null:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	grab_mouse_world = world_map.get_local_mouse_position()
	var ent = entity_registry.npcs.get(grabbed_entity_id)
	if ent == null:
		ent = entity_registry.items.get(grabbed_entity_id)
	if ent == null:
		return
	if entity_registry.items.has(grabbed_entity_id):
		_detach_item_for_drag(grabbed_entity_id)
	ent.position += (grab_mouse_world - ent.position) * GRAB_PULL
	ent.current_cell = ConstantsScript.world_to_cell(ent.position)


## 释放：被抓实体落在当前鼠标世界坐标的连续点。
## 若抓的是 item 且 drop 落点 HIT_RADIUS 内有 NPC → give_item_to_npc（在手）。
## 否则 set_entity_position 落连续点（建筑墙内则推到最近 walkable）。
func drop_or_release_selection(selection_rect: Rect2i, end_cell: Vector2i) -> void:
	latest_drag_rect = selection_rect
	latest_drag_end_cell = end_cell
	if fenced_area_mode:
		confirm_fenced_area_from_drag(selection_rect, end_cell)
		return
	if grabbed_entity_id == &"":
		_end_camera_drag()
		return
	var drop_world: Vector2 = world_map.get_local_mouse_position() if world_map != null else ConstantsScript.cell_to_world_center(end_cell)
	if entity_registry.items.has(grabbed_entity_id):
		if _handle_item_release(grabbed_entity_id, drop_world):
			grabbed_entity_id = &""
			dragged_item_previous_anchor_npc_id = &""
			_end_camera_drag()
			return
	if entity_registry.npcs.has(grabbed_entity_id):
		if _handle_npc_release(grabbed_entity_id, drop_world):
			grabbed_entity_id = &""
			dragged_item_previous_anchor_npc_id = &""
			_end_camera_drag()
			return
	if entity_registry.set_entity_position(grabbed_entity_id, drop_world):
		event_log.record(&"player_move_entity", grabbed_entity_id, &"", &"cell", ConstantsScript.world_to_cell(drop_world), {}, &"player", tick)
		_update_feedback_text("Dropped %s" % str(grabbed_entity_id))
	grabbed_entity_id = &""
	dragged_item_previous_anchor_npc_id = &""
	_end_camera_drag()


func discard_held_item_with_right_click() -> void:
	if selected_entity_id == &"" or not entity_registry.npcs.has(selected_entity_id):
		_update_feedback_text("Right-click an NPC with a held item to discard")
		return
	if entity_registry.drop_anchored_items(selected_entity_id, event_log):
		var event = event_log.recent_events(1)[0] if not event_log.recent_events(1).is_empty() else null
		_update_feedback_text("Discarded held item")
		if event != null:
			_emit_npc_feedback(event, selected_entity_id)
	else:
		_update_feedback_text("No held item to discard")


func _handle_item_release(item_id: StringName, drop_world: Vector2) -> bool:
	var target_npc := _hit_test_npc_only(drop_world)
	if target_npc == &"":
		if entity_registry.set_entity_position(item_id, drop_world):
			event_log.record(&"player_move_entity", item_id, &"", &"cell", ConstantsScript.world_to_cell(drop_world), {}, &"player", tick)
			_update_feedback_text("Dropped %s" % str(item_id))
			return true
		return false
	var previous_holder := dragged_item_previous_anchor_npc_id
	if previous_holder == &"":
		previous_holder = entity_registry.items[item_id].anchor_npc_id()
	if previous_holder != &"" and previous_holder != target_npc:
		_move_holder_into_transfer_range(previous_holder, target_npc)
	if not entity_registry.give_item_to_npc(item_id, target_npc):
		return false
	var event_type := &"player_transfer_item_between_npcs" if previous_holder != &"" and previous_holder != target_npc else &"player_drop_item_on_npc"
	var payload := _item_event_payload(item_id, target_npc, previous_holder)
	var auto_drop := _maybe_auto_drop_rejected_item(item_id, target_npc, payload)
	if not auto_drop.is_empty():
		payload["npc_auto_drop"] = auto_drop
		payload["currentAnchor"] = auto_drop.get("finalAnchor", {"type": "ground"})
		payload["finalAnchor"] = auto_drop.get("finalAnchor", {"type": "ground"})
		payload["event_text"] = "%s接到%s后主动丢到地上" % [str(payload.get("item_target_name", target_npc)), str(payload.get("item_name", item_id))]
	var event = event_log.record(event_type, item_id, target_npc, &"npc", ConstantsScript.world_to_cell(drop_world), payload, &"player", tick)
	_update_feedback_text(str(payload.get("event_text", "NPC accepted item")))
	_emit_interaction_feedback(event, _payload_npc_ids(payload))
	return true


func _handle_npc_release(npc_id: StringName, drop_world: Vector2) -> bool:
	var target_npc := _hit_test_npc_only(drop_world, npc_id)
	var target_item := _hit_test_item_only(drop_world)
	var target_npc_distance := INF
	var target_item_distance := INF
	if target_npc != &"":
		target_npc_distance = entity_registry.npcs[target_npc].position.distance_to(drop_world)
	if target_item != &"":
		target_item_distance = _item_world_position(target_item).distance_to(drop_world)
	if target_item != &"" and (target_npc == &"" or target_item_distance <= target_npc_distance):
		var previous_holder: StringName = entity_registry.items[target_item].anchor_npc_id()
		if previous_holder != &"" and previous_holder != npc_id:
			_move_holder_into_transfer_range(previous_holder, npc_id)
		if not entity_registry.give_item_to_npc(target_item, npc_id):
			return false
		var payload := _item_event_payload(target_item, npc_id, previous_holder)
		var auto_drop := _maybe_auto_drop_rejected_item(target_item, npc_id, payload)
		if not auto_drop.is_empty():
			payload["npc_auto_drop"] = auto_drop
			payload["currentAnchor"] = auto_drop.get("finalAnchor", {"type": "ground"})
			payload["finalAnchor"] = auto_drop.get("finalAnchor", {"type": "ground"})
			payload["event_text"] = "%s接到%s后主动丢到地上" % [str(payload.get("item_target_name", npc_id)), str(payload.get("item_name", target_item))]
		var event_type := &"player_transfer_item_between_npcs" if previous_holder != &"" and previous_holder != npc_id else &"player_drop_npc_near_item"
		var event = event_log.record(event_type, target_item, npc_id, &"npc", ConstantsScript.world_to_cell(drop_world), payload, &"player", tick)
		_update_feedback_text(str(payload.get("event_text", "NPC touched item")))
		_emit_interaction_feedback(event, _payload_npc_ids(payload))
		return true
	if target_npc != &"" and target_npc != npc_id:
		_place_npc_near_target(npc_id, target_npc)
		var payload := _npc_encounter_payload(npc_id, target_npc)
		var event = event_log.record(&"player_drop_npc_near_npc", npc_id, target_npc, &"npc", ConstantsScript.world_to_cell(drop_world), payload, &"player", tick)
		_emit_interaction_feedback(event, _payload_npc_ids(payload))
		return true
	return false


func _item_event_payload(item_id: StringName, target_npc_id: StringName, previous_holder_id: StringName = &"") -> Dictionary:
	var item = entity_registry.items.get(item_id)
	var target_npc = entity_registry.npcs.get(target_npc_id)
	var previous_holder = entity_registry.npcs.get(previous_holder_id)
	var owner_npc = entity_registry.npcs.get(item.owner_id) if item != null else null
	var primary_ids: Array[StringName] = [target_npc_id]
	if previous_holder_id != &"" and previous_holder_id != target_npc_id:
		primary_ids = [previous_holder_id, target_npc_id]
	var center := _interaction_center_for_ids(primary_ids, _item_world_position(item_id))
	var radius_meters := _item_involvement_radius_meters()
	var npc_ids := _interaction_participant_ids(primary_ids, center, radius_meters)
	var nearby_ids := _nearby_ids_from_participants(primary_ids, npc_ids)
	var item_name: String = item.name if item != null else str(item_id)
	var target_name: String = target_npc.name if target_npc != null else str(target_npc_id)
	var owner_name: String = owner_npc.name if owner_npc != null else ""
	var previous_name: String = previous_holder.name if previous_holder != null else ""
	var is_transfer := previous_holder_id != &"" and previous_holder_id != target_npc_id
	var event_text := "%s与%s发生直接互动" % [target_name, item_name]
	if is_transfer:
		event_text = "%s从%s转移到%s身上" % [item_name, previous_name, target_name]
	elif item != null and item.owner_id != &"" and item.owner_id != target_npc_id:
		event_text = "%s手里突然多了%s，原本属于%s" % [target_name, item_name, owner_name]
	var participant_actions := _item_participant_actions(item_id, target_npc_id, previous_holder_id, npc_ids)
	var scene_seed := _item_scene_seed(item_id, target_npc_id, previous_holder_id, nearby_ids)
	var interaction_delta := InteractionDeltaRulesScript.apply_attach_object_to_npc(item, target_npc_id, previous_holder_id, npc_ids, entity_registry, gameplay_config, tick)
	return {
		"source": "item_drag",
		"npc_ids": npc_ids,
		"primary_npc_ids": primary_ids,
		"nearby_involved_npc_ids": nearby_ids,
		"involvement_radius_meters": radius_meters,
		"participant_actions": participant_actions,
		"recent_actions": [event_text],
		"event_text": event_text,
		"scene_seed": scene_seed,
		"interaction_delta": interaction_delta,
		"interaction_trace": interaction_delta.get("interactionTrace", {}),
		"object_stance": interaction_delta.get("objectStance", {}),
		"performance_plan": interaction_delta.get("performancePlan", {}),
		"relation_memory_updates": interaction_delta.get("relationMemoryUpdates", []),
		"relationship_hint": _item_relationship_hint(item_id, target_npc_id, previous_holder_id, nearby_ids),
		"item_id": item_id,
		"item_name": item_name,
		"ownerId": item.owner_id if item != null else &"",
		"item_owner_name": owner_name,
		"previousAnchorNpcId": previous_holder_id,
		"previousAnchorNpcName": previous_name,
		"item_target_id": target_npc_id,
		"item_target_name": target_name,
		"currentAnchor": {"type": "npc", "npcId": str(target_npc_id)},
		"custodyState": item.custody_state if item != null else "unclaimed",
		"item_interaction": true,
		"item_solo_interaction": npc_ids.size() == 1,
		"item_transfer_interaction": is_transfer,
		"item_witness_interaction": not is_transfer and not nearby_ids.is_empty(),
		"object_access_rule": item.access_rule.duplicate(true) if item != null else {},
		"object_social": item.social.duplicate(true) if item != null else {},
		"object_social_state": _item_social_state(item_id, target_npc_id, is_transfer),
		"object_memory": item.memory.duplicate(true) if item != null else {"topLinks": []},
	}


func _maybe_auto_drop_rejected_item(item_id: StringName, target_npc_id: StringName, payload: Dictionary) -> Dictionary:
	if not entity_registry.items.has(item_id) or not entity_registry.npcs.has(target_npc_id):
		return {}
	var stance: Dictionary = payload.get("object_stance", {})
	if str(stance.get("result", "")) != "reject":
		return {}
	var trace: Dictionary = payload.get("interaction_trace", {})
	var count := int(trace.get("countInWindow", 1))
	var stage := str(trace.get("stage", "new"))
	var item = entity_registry.items[item_id]
	var npc = entity_registry.npcs[target_npc_id]
	var threshold_info := _npc_auto_drop_threshold(item, npc, stance)
	var threshold := int(threshold_info.get("threshold", 3))
	if count < threshold:
		return {}

	if item.anchor_npc_id() != target_npc_id:
		return {}
	var drop_pos := _npc_auto_drop_position(target_npc_id, item_id)
	item.attach_to_ground(drop_pos, "rejected")
	return {
		"npc_id": target_npc_id,
		"npc_name": npc.name,
		"item_id": item_id,
		"item_name": item.name,
		"reason": str(stance.get("dominantReason", "reject")),
		"countInWindow": count,
		"stage": stage,
		"threshold": threshold,
		"thresholdFactors": threshold_info.get("factors", []),
		"worldPosition": {"x": drop_pos.x, "y": drop_pos.y},
		"cell": ConstantsScript.cell_to_dict(ConstantsScript.world_to_cell(drop_pos)),
		"finalAnchor": {"type": "ground"},
	}


func _npc_auto_drop_threshold(item, npc, stance: Dictionary) -> Dictionary:
	var threshold := 3
	var factors: Array = []
	var social: Dictionary = item.social if item != null else {}
	var traits: Dictionary = npc.traits if npc != null else {}
	var tags: Array = npc.tags if npc != null and npc.tags is Array else []
	var reason := str(stance.get("dominantReason", ""))
	var reject := int(stance.get("reject", 0))
	var want := int(stance.get("want", 0))
	var reject_margin := reject - want
	var danger := int(social.get("danger", 0))
	var awkward := int(social.get("awkward", 0))
	var status := int(social.get("status", 0))
	var utility := int(social.get("utility", 0))
	var joke := int(social.get("joke", 0))
	var caution := int(traits.get("caution", 50))
	var face := int(traits.get("face", 50))
	var control := int(traits.get("control", 50))
	var play := int(traits.get("play", 50))

	if reason == "danger" or danger >= 80:
		threshold -= 1
		factors.append("danger")
	if reason == "forbidden":
		threshold -= 1
		factors.append("forbidden")
	if reject_margin >= 35:
		threshold -= 1
		factors.append("strong_reject")
	if caution >= 75:
		threshold -= 1
		factors.append("high_caution")
	if tags.has("avoid_responsibility"):
		threshold -= 1
		factors.append("avoid_responsibility")
	if awkward >= 85 and caution >= 60:
		threshold -= 1
		factors.append("awkward_pressure")

	if face >= 75:
		threshold += 1
		factors.append("high_face")
	if control >= 75:
		threshold += 1
		factors.append("high_control")
	if status >= 70 or utility >= 70:
		threshold += 1
		factors.append("valuable_object")
	if joke >= 80 and play >= 70:
		threshold += 1
		factors.append("plays_with_gag")

	return {
		"threshold": clampi(threshold, 2, 5),
		"factors": factors,
	}


func _npc_auto_drop_position(npc_id: StringName, item_id: StringName) -> Vector2:
	if not entity_registry.npcs.has(npc_id):
		return Vector2.ZERO
	var npc = entity_registry.npcs[npc_id]
	var offset := Vector2(ConstantsScript.CELL_SIZE * 0.85, ConstantsScript.CELL_SIZE * 0.42)
	if not str(item_id).is_empty():
		var sign := 1.0 if abs(hash(str(item_id))) % 2 == 0 else -1.0
		offset.x *= sign
	var candidate: Vector2 = npc.position + offset
	var cell := ConstantsScript.world_to_cell(candidate)
	if entity_registry.map_bounds != Rect2i() and not entity_registry.map_bounds.has_point(cell):
		return npc.position
	return candidate


func _npc_encounter_payload(primary_npc_id: StringName, target_npc_id: StringName) -> Dictionary:
	var primary = entity_registry.npcs.get(primary_npc_id)
	var target = entity_registry.npcs.get(target_npc_id)
	var primary_ids: Array[StringName] = [primary_npc_id, target_npc_id]
	var center := _interaction_center_for_ids(primary_ids)
	var npc_ids := _interaction_participant_ids(primary_ids, center, _involvement_radius_meters())
	var primary_name: String = primary.name if primary != null else str(primary_npc_id)
	var target_name: String = target.name if target != null else str(target_npc_id)
	return {
		"source": "observer_drag",
		"npc_ids": npc_ids,
		"primary_npc_ids": primary_ids,
		"nearby_involved_npc_ids": _nearby_ids_from_participants(primary_ids, npc_ids),
		"involvement_radius_meters": _involvement_radius_meters(),
		"primary_npc_id": primary_npc_id,
		"primary_npc_name": primary_name,
		"target_npc_id": target_npc_id,
		"target_npc_name": target_name,
		"participant_actions": _meeting_participant_actions(npc_ids),
		"recent_actions": ["%s被观察者拖到%s身边，现场被迫开聊" % [primary_name, target_name]],
		"event_text": "%s被拖到%s身边，实时对话开始" % [primary_name, target_name],
		"scene_seed": _npc_scene_seed(primary_npc_id, target_npc_id),
		"relationship_hint": "观察者强制拉近距离，NPC需要立刻回应眼前关系和刚才的行为。",
	}


func _npc_item_observation_payload(npc_id: StringName, item_id: StringName) -> Dictionary:
	var npc = entity_registry.npcs.get(npc_id)
	var item = entity_registry.items.get(item_id)
	var owner = entity_registry.npcs.get(item.owner_id) if item != null else null
	return {
		"source": "npc_near_item",
		"npc_id": npc_id,
		"npc_name": npc.name if npc != null else str(npc_id),
		"item_id": item_id,
		"item_name": item.name if item != null else str(item_id),
		"ownerId": item.owner_id if item != null else &"",
		"item_owner_name": owner.name if owner != null else "",
		"object_access_rule": item.access_rule.duplicate(true) if item != null else {},
		"object_social": item.social.duplicate(true) if item != null else {},
	}


func _detach_item_for_drag(item_id: StringName) -> void:
	if not entity_registry.items.has(item_id):
		return
	var item = entity_registry.items[item_id]
	var anchor_npc_id: StringName = item.anchor_npc_id()
	if anchor_npc_id == &"":
		return
	if dragged_item_previous_anchor_npc_id == &"":
		dragged_item_previous_anchor_npc_id = anchor_npc_id
	item.position = _item_world_position(item_id)
	item.current_cell = ConstantsScript.world_to_cell(item.position)
	item.current_anchor = {"type": "ground"}


func _item_world_position(item_id: StringName) -> Vector2:
	if not entity_registry.items.has(item_id):
		return Vector2.ZERO
	var item = entity_registry.items[item_id]
	var anchor_npc_id: StringName = item.anchor_npc_id()
	if anchor_npc_id != &"" and entity_registry.npcs.has(anchor_npc_id):
		var holder = entity_registry.npcs[anchor_npc_id]
		var held_items: Array = entity_registry.items_anchored_to_npc(anchor_npc_id)
		var index: int = max(0, held_items.find(item_id))
		return holder.position + _held_item_anchor_offset() + _held_item_offset(index)
	return item.position


func _held_item_anchor_offset() -> Vector2:
	return HeldItemLayoutScript.anchor_offset()


func _held_item_offset(index: int) -> Vector2:
	return HeldItemLayoutScript.item_offset(index)


func _move_holder_into_transfer_range(from_id: StringName, to_id: StringName) -> void:
	if not entity_registry.npcs.has(from_id) or not entity_registry.npcs.has(to_id):
		return
	var from_npc = entity_registry.npcs[from_id]
	var to_npc = entity_registry.npcs[to_id]
	var threshold := _item_transfer_distance_pixels()
	if from_npc.position.distance_to(to_npc.position) <= threshold:
		return
	var direction: Vector2 = (from_npc.position - to_npc.position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var distance: float = max(12.0, threshold * 0.55)
	entity_registry.set_npc_position(from_id, to_npc.position + direction * distance)


func _place_npc_near_target(npc_id: StringName, target_id: StringName) -> void:
	if not entity_registry.npcs.has(npc_id) or not entity_registry.npcs.has(target_id):
		return
	var npc = entity_registry.npcs[npc_id]
	var target = entity_registry.npcs[target_id]
	var direction: Vector2 = (npc.position - target.position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	entity_registry.set_npc_position(npc_id, target.position + direction * ConstantsScript.CELL_SIZE * 0.85)


func _payload_npc_ids(payload: Dictionary) -> Array:
	var raw: Variant = payload.get("npc_ids", [])
	if raw is Array and not raw.is_empty():
		return raw
	var result: Array = []
	for key in ["previousAnchorNpcId", "item_target_id", "primary_npc_id", "target_npc_id", "npc_id"]:
		var value := StringName(payload.get(key, &""))
		if value != &"" and not result.has(value):
			result.append(value)
	return result


func _interaction_center_for_ids(npc_ids: Array, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for raw_id in npc_ids:
		var npc_id := StringName(raw_id)
		if entity_registry.npcs.has(npc_id):
			total += entity_registry.npcs[npc_id].position
			count += 1
	if count == 0:
		return fallback
	return total / float(count)


func _involvement_radius_meters() -> float:
	var free_roam: Dictionary = gameplay_config.get("free_roam", {})
	return max(0.0, float(free_roam.get("involvement_radius_meters", 1.0)))


func _item_involvement_radius_meters() -> float:
	var free_roam: Dictionary = gameplay_config.get("free_roam", {})
	return max(0.0, float(free_roam.get("item_involvement_radius_meters", free_roam.get("involvement_radius_meters", 1.0))))


func _item_transfer_distance_pixels() -> float:
	var free_roam: Dictionary = gameplay_config.get("free_roam", {})
	return max(0.0, float(free_roam.get("item_transfer_distance_meters", 1.5))) * float(ConstantsScript.CELL_SIZE)


func _radius_pixels(radius_meters: float) -> float:
	return max(0.0, radius_meters) * float(ConstantsScript.CELL_SIZE)


func _interaction_participant_ids(primary_ids: Array, center: Vector2, radius_meters: float) -> Array:
	var ids: Array = []
	for raw_id in primary_ids:
		var npc_id := StringName(raw_id)
		if npc_id != &"" and entity_registry.npcs.has(npc_id) and not ids.has(npc_id):
			ids.append(npc_id)
	var radius := _radius_pixels(radius_meters)
	if radius <= 0.0:
		return ids
	var candidates: Array = []
	for npc in entity_registry.npcs.values():
		if ids.has(npc.id):
			continue
		var score: float = npc.position.distance_squared_to(center)
		if score <= radius * radius:
			candidates.append({"npc_id": npc.id, "score": score})
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left.get("score", 0.0)) < float(right.get("score", 0.0))
	)
	for candidate in candidates:
		ids.append(StringName(candidate.get("npc_id", "")))
	return ids


func _nearby_ids_from_participants(primary_ids: Array, participant_ids: Array) -> Array:
	var extras: Array = []
	for raw_id in participant_ids:
		var npc_id := StringName(raw_id)
		if npc_id != &"" and not primary_ids.has(npc_id):
			extras.append(npc_id)
	return extras


func _item_participant_actions(item_id: StringName, target_id: StringName, previous_holder_id: StringName, npc_ids: Array) -> Array:
	var item = entity_registry.items.get(item_id)
	var target = entity_registry.npcs.get(target_id)
	var owner_id: StringName = item.owner_id if item != null else &""
	var item_name: String = item.name if item != null else str(item_id)
	var target_name: String = target.name if target != null else str(target_id)
	var owner_name := _npc_name(owner_id)
	var actions: Array = []
	var target_label := "正在处理自己的%s" % item_name
	var target_motive := "确认这个道具还属于自己，并把态度表现出来"
	if previous_holder_id != &"" and previous_holder_id != target_id:
		target_label = "从%s手里接过%s" % [_npc_name(previous_holder_id), item_name]
		target_motive = "先回应这个可见交接，判断它是示好、栽赃、试探，还是被迫保管"
	elif owner_id != &"" and owner_id != target_id:
		target_label = "手里突然多了%s（原本属于%s）" % [item_name, owner_name]
		target_motive = "先解释这件不属于自己的东西为什么在自己手里，避免被扣成偷拿或栽赃"
	actions.append({
		"npc_id": target_id,
		"name": target_name,
		"intention_label": target_label,
		"intention_motive": target_motive,
		"desired_outcome": "先用动作处理这个社交事故，再用短句解释、遮掩或反击。",
	})
	if previous_holder_id != &"" and previous_holder_id != target_id:
		actions.append({
			"npc_id": previous_holder_id,
			"name": _npc_name(previous_holder_id),
			"intention_label": "把%s交到%s身上" % [item_name, target_name],
			"intention_motive": "这个转交动作会暴露占有、偏爱、试探或被迫让步",
			"desired_outcome": "必须回应为什么愿意/被迫交出这个道具。",
		})
	for raw_id in npc_ids:
		var npc_id := StringName(raw_id)
		if npc_id == target_id or npc_id == previous_holder_id:
			continue
		actions.append({
			"npc_id": npc_id,
			"name": _npc_name(npc_id),
			"intention_label": "在%.1fm内看见%s到了%s手里" % [_item_involvement_radius_meters(), item_name, target_name],
			"intention_motive": "把目击到的道具归属变化解读成把柄、笑料、怀疑或台阶",
			"desired_outcome": "只围绕眼前道具归属变化起哄、追问、护短或记账。",
		})
	return actions


func _meeting_participant_actions(npc_ids: Array) -> Array:
	var actions: Array = []
	for raw_id in npc_ids:
		var npc_id := StringName(raw_id)
		var npc = entity_registry.npcs.get(npc_id)
		if npc == null:
			continue
		actions.append({
			"npc_id": npc_id,
			"name": npc.name,
			"performanceState": npc.performance_state,
			"emotionalState": npc.emotional_state,
			"intention_label": "观察眼前社交压力",
			"intention_motive": "按 traits、style 和当前身体状态回应被拖到一起的现场",
			"desired_outcome": "让关系、尴尬、怀疑、乐子或亏欠至少有一个发生变化。",
		})
	return actions


func _item_scene_seed(item_id: StringName, target_id: StringName, previous_holder_id: StringName, nearby_ids: Array) -> Dictionary:
	var item = entity_registry.items.get(item_id)
	var item_name: String = item.name if item != null else str(item_id)
	var owner_id: StringName = item.owner_id if item != null else &""
	var owner_name := _npc_name(owner_id)
	var target_name := _npc_name(target_id)
	var is_transfer := previous_holder_id != &"" and previous_holder_id != target_id
	var visible_topic := "%s正在和%s互动：确认、护住、收回或重新摆放，不牵涉其他 NPC" % [target_name, item_name]
	var type := "solo_item_interaction"
	var title := "%s处理%s" % [target_name, item_name]
	var goal := "生成一句短而有角色味的单人道具反应；先回应%s现在在%s手里，再体现他的动作、情绪或占有态度。" % [item_name, target_name]
	var consequence := "1句内结束：留下一个清楚的动作、情绪或占有态度。"
	if is_transfer:
		type = "item_transfer"
		title = "%s交给%s" % [_npc_name(previous_holder_id), target_name]
		visible_topic = "%s刚从%s身上转到%s身上；这不是凭空出现，而是一次可见的交接" % [item_name, _npc_name(previous_holder_id), target_name]
		goal = "先回应交接动作本身，再演出%s归属变化造成的占有、嫌疑、偏爱或亏欠。" % item_name
		consequence = "4句内留下明确道具后果：谁暂时持有、谁被怀疑或被维护、关系/信任/怨气哪一项变化。"
	elif owner_id != &"" and owner_id != target_id:
		visible_topic = "%s手里突然多了%s；这件东西原本属于%s。重点是%s如何处理这个突兀转手：护住、甩开、解释、试探或借题发挥。" % [target_name, item_name, owner_name, target_name]
	if not is_transfer and not nearby_ids.is_empty():
		type = "item_witness_interaction"
		title = "%s处理%s被%s看见" % [target_name, item_name, _npc_name(StringName(nearby_ids[0]))]
		visible_topic = "%s正在处理%s，%s在%.1fm内看见并被卷入" % [target_name, item_name, _npc_name(StringName(nearby_ids[0])), _item_involvement_radius_meters()]
		goal = "先回应%s正在处理%s这件事，再让旁观者给出符合人设的目击反应。" % [target_name, item_name]
		consequence = "4句内留下目击后果：尴尬、起哄、怀疑、维护、关系变化或新把柄之一。"
	return {
		"type": type,
		"title": title,
		"trigger_action": "观察者拖拽道具：%s -> %s" % [item_name, target_name],
		"actor": target_id,
		"observer": previous_holder_id if is_transfer else (StringName(nearby_ids[0]) if not nearby_ids.is_empty() else &""),
		"visible_topic": visible_topic,
		"object_social_state": _item_social_state(item_id, target_id, is_transfer),
		"emotional_charge": 78 if is_transfer else 64,
		"conflict_question": "%s为什么会在%s手里？现场要把占有、嫌疑、偏爱、亏欠或笑料演出来。" % [item_name, target_name],
		"required_shift": ["micro_action_seen", "object_consequence", "relation_pressure_shift"],
		"allowed_outcomes": ["质问", "遮掩", "起哄", "推回", "临时保管", "形成梗"],
		"stakes": "这个道具会改变谁被怀疑、谁欠谁解释、谁获得乐子或把柄。",
		"interaction_goal": goal,
		"consequence_rule": consequence,
	}


func _npc_scene_seed(primary_id: StringName, target_id: StringName) -> Dictionary:
	return {
		"type": "activity_collision",
		"title": "%s撞见%s" % [_npc_name(primary_id), _npc_name(target_id)],
		"trigger_action": "观察者把两名 NPC 拖到一起",
		"actor": primary_id,
		"observer": target_id,
		"visible_topic": "%s被拖到%s身边，双方必须先回应眼前距离和正在做的事。" % [_npc_name(primary_id), _npc_name(target_id)],
		"emotional_charge": 62,
		"conflict_question": "这次被迫靠近会制造尴尬、试探、起哄、怀疑还是临时合作？",
		"required_shift": ["relationship_change"],
		"allowed_outcomes": ["试探", "反击", "起哄", "让步", "形成临时目标"],
		"stakes": "对话必须留下关系或行动后果。",
		"interaction_goal": "把普通相遇变成一次关系试探，让好感、尴尬、怀疑、乐子或亏欠至少有一个发生变化。",
		"consequence_rule": "4句内必须留下明确后果，不能只是互相调侃后散开。",
	}


func _item_relationship_hint(item_id: StringName, target_id: StringName, previous_holder_id: StringName, nearby_ids: Array) -> String:
	var item = entity_registry.items.get(item_id)
	var item_name: String = item.name if item != null else str(item_id)
	if previous_holder_id != &"" and previous_holder_id != target_id:
		return "这是明确的物品交接，不是捡到或凭空出现；NPC必须回应%s为什么从%s到%s。" % [item_name, _npc_name(previous_holder_id), _npc_name(target_id)]
	if not nearby_ids.is_empty():
		return "这是道具近距离目击事件，旁观者可以起哄、误读或追问，但必须围绕%s现在在%s手里。" % [item_name, _npc_name(target_id)]
	return "这是单人道具反应，只表现 NPC 与物品的关系，不牵涉其他 NPC。"


func _item_social_state(item_id: StringName, target_id: StringName, is_transfer: bool = false) -> String:
	var item = entity_registry.items.get(item_id)
	if item == null:
		return "unknown"
	if is_transfer:
		return "transferred"
	if item.owner_id == &"":
		return "unclaimed"
	if item.owner_id == target_id:
		return "owned"
	return "misplaced"


func _npc_name(npc_id: StringName) -> String:
	if npc_id != &"" and entity_registry.npcs.has(npc_id):
		return entity_registry.npcs[npc_id].name
	return str(npc_id)


func _emit_interaction_feedback(event, npc_ids: Array) -> void:
	var participants := _valid_unique_npc_ids(npc_ids)
	_pause_feedback_participants(participants)
	for npc_id in participants:
		_emit_npc_feedback(event, npc_id)


func _valid_unique_npc_ids(npc_ids: Array) -> Array:
	var result: Array[StringName] = []
	var seen: Dictionary = {}
	for raw_id in npc_ids:
		var npc_id := StringName(raw_id)
		if npc_id == &"" or seen.has(npc_id) or entity_registry == null or not entity_registry.npcs.has(npc_id):
			continue
		seen[npc_id] = true
		result.append(npc_id)
	return result


func _pause_feedback_participants(npc_ids: Array, seconds: float = FEEDBACK_PAUSE_SECONDS) -> void:
	for raw_id in npc_ids:
		_pause_npc_for_feedback(StringName(raw_id), seconds)


func _pause_npc_for_feedback(npc_id: StringName, seconds: float = FEEDBACK_PAUSE_SECONDS) -> void:
	if npc_id == &"":
		return
	var until_ms := Time.get_ticks_msec() + int(max(0.0, seconds) * 1000.0)
	npc_feedback_pause_until_ms[npc_id] = max(int(npc_feedback_pause_until_ms.get(npc_id, 0)), until_ms)


func _is_npc_feedback_paused(npc_id: StringName) -> bool:
	if not npc_feedback_pause_until_ms.has(npc_id):
		return false
	var until_ms := int(npc_feedback_pause_until_ms.get(npc_id, 0))
	if Time.get_ticks_msec() <= until_ms:
		return true
	npc_feedback_pause_until_ms.erase(npc_id)
	return false


func _emit_npc_feedback(event, npc_id: StringName) -> void:
	if npc_feedback_builder == null or event == null or not entity_registry.npcs.has(npc_id):
		return
	_pause_npc_for_feedback(npc_id)
	var npc = entity_registry.npcs[npc_id]
	var world_context := {
		"entity_registry": entity_registry,
		"place_registry": place_registry,
		"event_log": event_log,
	}
	npc_feedback_builder.stream_feedback(event, npc, world_context, func(chunk: String) -> void:
		_update_feedback_text(chunk)
		_pause_npc_for_feedback(npc_id)
		if entity_visual_layer != null and entity_visual_layer.npc_visuals.has(npc_id):
			entity_visual_layer.npc_visuals[npc_id].show_bubble(chunk)
	, func(_result: Dictionary) -> void:
		pass
	)


func toggle_fenced_area_mode() -> void:
	fenced_area_mode = not fenced_area_mode
	grid_selection_overlay.enabled = true
	grid_selection_overlay.build_mode = fenced_area_mode
	grid_selection_overlay.queue_redraw()
	_update_feedback_text("FencedArea mode %s" % ("on" if fenced_area_mode else "off"))


func confirm_fenced_area_from_drag(selection_rect: Rect2i, drag_end_cell: Vector2i) -> void:
	if selection_rect.size.x < 3 or selection_rect.size.y < 3:
		_update_feedback_text("FencedArea needs at least 3x3")
		return
	if fenced_area_edit_panel != null:
		fenced_area_edit_panel.current_tick = tick
		fenced_area_edit_panel.open_for_selection(selection_rect, drag_end_cell, "Fenced Area %d" % (place_registry.places.size() + 1))


func create_fenced_area_mode() -> void:
	fenced_area_mode = true
	_update_feedback_text("Drag a 3x3 or larger fenced area")


func on_fenced_area_placement_confirmed(result: Dictionary) -> void:
	if result.get("ok", false):
		fenced_area_mode = false
		fenced_area_overlay.refresh_from_registry()
		_update_feedback_text("Created %s" % result["place"].name)
	else:
		_update_feedback_text("FencedArea failed: %s" % str(result.get("reason", "unknown")))


func update_feedback_reaction(event_text: String) -> void:
	_update_feedback_text(event_text)
	if entity_visual_layer != null and selected_entity_id != &"" and entity_visual_layer.npc_visuals.has(selected_entity_id):
		_pause_npc_for_feedback(selected_entity_id)
		entity_visual_layer.npc_visuals[selected_entity_id].show_bubble(event_text)


func generate_daily_todo_hotkey_placeholder() -> void:
	request_daily_todos_for_all_npcs()


## 按 T：对每个 NPC 发起真实 daily todo 规划。
## 流程: planner.request_daily_todos -> transport (HTTPRequest) -> LLMClient generation 守卫
##        -> validate_todos -> on_done 把校验后的 todos 写进 npc.todo_list。
## 无 key (llm_config.enabled==false): transport 立即回 llm_disabled，planner 回退到 wander，
##        on_done 仍 ok=true 带一个 wander todo；UI 提示 "LLM disabled / fallback"。
func request_daily_todos_for_all_npcs() -> void:
	if daily_todo_planner == null or llm_transport == null or llm_client == null:
		_update_feedback_text("LLM services not wired")
		return

	var llm_enabled := llm_config != null and bool(llm_config.enabled)
	if llm_enabled:
		_update_feedback_text("Requesting daily todos from LLM...")
	else:
		_update_feedback_text("LLM disabled / fallback (set OPENROUTER_API_KEY in .env)")

	var world := {
		"entity_registry": entity_registry,
		"place_registry": place_registry,
		"pathfinder": pathfinder,
		"event_log": event_log,
	}
	for npc in entity_registry.npcs.values():
		var target_npc = npc
		daily_todo_planner.request_daily_todos(target_npc, world, llm_transport, llm_client, func(result: Dictionary) -> void:
			_on_daily_todos_ready(target_npc, result, llm_enabled)
		)


func _on_daily_todos_ready(npc, result: Dictionary, llm_enabled: bool) -> void:
	var npc_id := str(npc.id)

	# #4: 被新一轮请求取代（late/cancelled）的结果不注入任何 todo——
	# 更新的 generation 会产出真正的计划。只有 ok 才替换当天计划。
	if not bool(result.get("ok", false)):
		var status := StringName(result.get("status", ""))
		if status == &"late" or status == &"cancelled":
			_update_feedback_text("NPC %s daily plan superseded by newer request" % npc_id)
			return

	var todos: Variant = result.get("todos", [])
	if not (todos is Array):
		todos = []

	# #3: daily planning 是「重排当天计划」而非累加。先清掉该 NPC 还没开始的
	# pending todo（上一轮 daily 计划残留），保留 active/in-progress/blocked/done 的，
	# 避免反复按 T 时 todo_list 无界堆积，也不打断正在执行的 todo。
	_clear_pending_todos(npc)
	for todo in todos:
		npc.todo_list.append(todo)

	if llm_enabled:
		_update_feedback_text("NPC %s daily todos: %d" % [npc_id, (todos as Array).size()])
	else:
		_update_feedback_text("LLM disabled / fallback wander for NPC %s" % npc_id)


## 移除该 NPC todo_list 中 status==pending 的 todo（未开始的当天计划残留）。
## 绝不移除 active/in-progress/blocked/done 的 todo，以免打断执行中的动作。
func _clear_pending_todos(npc) -> void:
	if npc == null or not (npc.todo_list is Array):
		return
	var kept: Array = []
	for todo in npc.todo_list:
		var status := StringName(todo.get("status")) if (todo != null and todo is Object) else &""
		if status != &"pending":
			kept.append(todo)
	npc.todo_list = kept


## tick_npc_execution: DECISION 层（被 _process 节流调用，也可被 oracle/测试直接调）。
## 每个 NPC 若 mover idle 且有 pending todo，则：锁 movement lane → resolve 目标世界坐标
## → mover.begin_move 规划 waypoints → todo.status=active（交给逐帧 advance 层连续推进）。
## 遵守 AI Town 边界：只消费已存在（且经 validate_todos 校验过）的 todo，不凭空造 world state。
func tick_npc_execution() -> void:
	if entity_registry == null or todo_executor == null:
		return
	for npc in entity_registry.npcs.values():
		_decide_one_npc(npc)


func _decide_one_npc(npc) -> void:
	if npc == null or not (npc.todo_list is Array):
		return
	if _is_npc_feedback_paused(npc.id):
		return
	var mover = _mover_for(npc)
	if not mover.is_idle():
		return
	var todo = _next_pending_todo(npc)
	if todo == null:
		return
	# movement lane 锁：同一 NPC 同一时刻只跑一个 movement action（spec Parallel action lanes）。
	var lane_action := {"id": StringName("exec_%s_%s" % [str(npc.id), str(todo.id)]), "npc_id": npc.id, "lane": &"movement"}
	if action_scheduler != null:
		var lane_result: Dictionary = action_scheduler.start_action(lane_action)
		if not bool(lane_result.get("accepted", false)):
			return
	var ctx := {"entity_registry": entity_registry, "place_registry": place_registry, "pathfinder": pathfinder, "event_log": event_log, "mover": mover}
	var resolved: Dictionary = todo_executor._target_world_pos(todo, ctx, npc)
	if not bool(resolved.get("ok", false)):
		todo_executor.mark_todo_blocked(npc, todo)
		if action_scheduler != null:
			action_scheduler.finish_action(npc.id, &"movement")
		return
	mover.begin_move(npc, resolved.get("world_pos"), resolved.get("interact_target"), todo, float(resolved.get("arrival_radius", ConstantsScript.INTERACT_RADIUS)))
	todo.status = &"active"
	if entity_visual_layer != null:
		entity_visual_layer.sync_from_registry(entity_registry)
		if entity_visual_layer.npc_visuals.has(npc.id):
			entity_visual_layer.npc_visuals[npc.id].show_bubble(str(todo.reason))


## advance_npc_movement: ADVANCE 层（_process 每帧调用）。把每个非 idle 的 NPC 沿 waypoints
## 连续推进一步；到达目标或进入交互半径时 → todo.status=done + 记录完成事件 + 释放 movement lane。
func advance_npc_movement(delta: float) -> void:
	if entity_registry == null:
		return
	for npc in entity_registry.npcs.values():
		if _is_npc_feedback_paused(npc.id):
			continue
		var mover = npc_movers.get(npc.id)
		if mover == null or mover.is_idle():
			continue
		var r: Dictionary = mover.advance(npc, delta)
		# 到达后进入 dwell(执行 intent 的停留);只有 dwell 满 DWELL_DURATION(done)才完成 todo,
		# 避免 rest/inspect/talk 等到达即瞬间 done 的「哗哗连发」。
		if bool(r.get("done", false)):
			_complete_active_todo(npc, mover)


func _complete_active_todo(npc, mover) -> void:
	var todo = mover.current_todo
	if todo != null:
		todo.status = &"done"
		if event_log != null and event_log.has_method("record"):
			event_log.record(&"npc_completed_todo", npc.id, &"", &"cell", npc.current_cell, {"todo_id": todo.id}, &"system", tick)
	if action_scheduler != null:
		action_scheduler.finish_action(npc.id, &"movement")
	mover.reset()


## 取该 NPC todo_list 中第一个 pending todo（按 list 顺序；优先级排序留待后续）。
func _next_pending_todo(npc):
	for todo in npc.todo_list:
		if todo != null and todo is Object and StringName(todo.status) == &"pending":
			return todo
	return null


## 懒创建并缓存每个 NPC 的 NPCMover（持各自路径状态）。
func _mover_for(npc):
	var key: StringName = npc.id
	if npc_movers.has(key):
		return npc_movers[key]
	var mover = NPCMoverScript.new()
	mover.configure(entity_registry, place_registry, pathfinder, event_log)
	npc_movers[key] = mover
	return mover


func save_game_state() -> void:
	saved_snapshot = {
		"entities": entity_registry.to_dict(),
		"places": place_registry.to_dict(),
		"pathfinder": pathfinder.to_dict(),
		"events": event_log.to_dict(),
		"selected_entity_id": selected_entity_id,
	}
	_update_feedback_text("Saved")


func load_game_state() -> void:
	if saved_snapshot.is_empty():
		_update_feedback_text("No save snapshot")
		return
	entity_registry.load_from_dict(saved_snapshot.get("entities", {}))
	place_registry.load_from_dict(saved_snapshot.get("places", {}))
	pathfinder.load_from_dict(saved_snapshot.get("pathfinder", {}))
	event_log.load_from_dict(saved_snapshot.get("events", {}))
	selected_entity_id = StringName(saved_snapshot.get("selected_entity_id", ""))
	fenced_area_overlay.refresh_from_registry()
	_update_feedback_text("Loaded")


func _resolve_scene_nodes() -> void:
	world_map = get_node_or_null("WorldMap")
	world_state = get_node_or_null("WorldState")
	npc_system = get_node_or_null("NPCSystem")
	ui_layer = get_node_or_null("UI")
	if world_map == null:
		world_map = Node2D.new()
		world_map.name = "WorldMap"
		add_child(world_map)
	if world_state == null:
		world_state = Node.new()
		world_state.name = "WorldState"
		add_child(world_state)
	if npc_system == null:
		npc_system = Node.new()
		npc_system.name = "NPCSystem"
		add_child(npc_system)
	if ui_layer == null:
		ui_layer = CanvasLayer.new()
		ui_layer.name = "UI"
		add_child(ui_layer)
	camera = world_map.get_node_or_null("Camera2D")
	if camera == null:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		world_map.add_child(camera)
	camera.enabled = true
	camera.position = _camera_bounds_rect().get_center()
	_clamp_camera_to_bounds()
	background_sprite = world_map.get_node_or_null("BgTexture")
	if background_sprite == null:
		background_sprite = Sprite2D.new()
		background_sprite.name = "BgTexture"
		background_sprite.z_index = -100
		world_map.add_child(background_sprite)
		world_map.move_child(background_sprite, 0)
	entity_visual_layer = world_map.get_node_or_null("EntityVisualLayer")
	if entity_visual_layer == null:
		entity_visual_layer = preload("res://scripts/ui/EntityVisualLayer.gd").new()
		entity_visual_layer.name = "EntityVisualLayer"
		world_map.add_child(entity_visual_layer)


func _fit_world_background(bg_path: String) -> void:
	if background_sprite == null:
		return
	var tex: Texture2D = _load_png_texture(bg_path)
	background_sprite.texture = tex
	if tex == null:
		return
	var world_size := Vector2(map_bounds.size.x * cell_size, map_bounds.size.y * cell_size)
	background_sprite.position = Vector2(map_bounds.position.x * cell_size, map_bounds.position.y * cell_size)
	background_sprite.centered = false
	background_sprite.scale = Vector2(world_size.x / float(tex.get_width()), world_size.y / float(tex.get_height()))


func _load_png_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var image := Image.new()
	if image.load_png_from_buffer(file.get_buffer(file.get_length())) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _wire_core_world_services() -> void:
	entity_registry = WorldEntityRegistryScript.new()
	place_registry = WorldPlaceRegistryScript.new()
	pathfinder = GridPathfinderScript.new()
	placement_service = BuildingPlacementServiceScript.new()
	event_log = InteractionEventLogScript.new()
	entity_registry.set_map_bounds(map_bounds)
	pathfinder.set_map_bounds(map_bounds)
	placement_service.configure(entity_registry, place_registry, pathfinder, event_log)
	game_clock = GameClockScript.new()


func _wire_npc_llm_services() -> void:
	# .env -> LLMConfig (RefCounted). 无 key 时 enabled=false，T 键走 fallback wander。
	llm_config = LLMConfigScript.load_from_project_root()

	# LLMTransport 是唯一发 HTTPRequest 的地方，必须挂在 scene tree 的 Node 上。
	llm_transport = LLMTransportScript.new()
	llm_transport.name = "LLMTransport"
	npc_system.add_child(llm_transport)
	llm_transport.configure(llm_config)

	# LLMClient 是 RefCounted 状态机（不发请求），由 planner / feedback builder 共用。
	llm_client = LLMClientScript.new()

	daily_todo_planner = DailyTodoPlannerScript.new()
	daily_todo_planner.configure(entity_registry, place_registry, pathfinder, event_log)

	npc_feedback_builder = NPCFeedbackBuilderScript.new()
	npc_feedback_builder.configure(entity_registry, place_registry, pathfinder, event_log, llm_client, llm_transport)

	# 执行层：TodoExecutor 消费 todo（瞬移式移动），NPCActionScheduler 管 lane 锁。
	# 每个 NPC 的 NPCMover 按需在 _mover_for 里懒创建（seed 在本方法之后才跑）。
	action_scheduler = NPCActionSchedulerScript.new()
	todo_executor = TodoExecutorScript.new()
	todo_executor.configure(entity_registry, place_registry, pathfinder, event_log)


func _seed_sample_npc_item_data() -> void:
	gameplay_config = ConfigLoaderScript.load_gameplay_config()
	var loaded_npcs: Dictionary = ConfigLoaderScript.load_npc_configs()
	npc_config_by_id = loaded_npcs.get("by_id", {})
	var npc_configs: Array = loaded_npcs.get("configs", [])
	if npc_configs.is_empty():
		npc_configs = _fallback_stardive_npcs()

	for cfg in npc_configs:
		var npc = NPCStateScript.from_dict(cfg)
		entity_registry.add_npc(npc)

	var item_bundle: Dictionary = ConfigLoaderScript.load_item_bundle()
	entity_registry.set_object_types(item_bundle.get("objectTypes", {}))
	for item_cfg in item_bundle.get("objects", []):
		if not (item_cfg is Dictionary):
			continue
		var item = ItemStateScript.from_dict(item_cfg, entity_registry.object_types)
		entity_registry.add_item(item)
	entity_registry.repair_inventory_links()
	_seed_places_from_gameplay()
	_seed_initial_todos_from_intentions()


func _seed_places_from_gameplay() -> void:
	var free_roam: Dictionary = gameplay_config.get("free_roam", {})
	for raw_location in free_roam.get("locations", []):
		if not (raw_location is Dictionary):
			continue
		var location: Dictionary = raw_location
		var place_id := StringName(location.get("id", ""))
		if place_id == &"":
			continue
		var tile := _tile_from_array(location.get("tile", [0, 0]))
		var footprint := Rect2i(max(0, tile.x - 1), max(0, tile.y - 1), 3, 3)
		var door := tile
		var fence_cells := [Vector2i(footprint.position.x, footprint.position.y)]
		var interior_cells := [tile]
		place_registry.create_place(place_id, str(location.get("name", place_id)), _tags_text(location.get("tags", [])), footprint, door, fence_cells, interior_cells)


func _seed_initial_todos_from_intentions() -> void:
	var free_roam: Dictionary = gameplay_config.get("free_roam", {})
	var intentions: Dictionary = free_roam.get("intentions", {})
	for npc in entity_registry.npcs.values():
		var npc_intentions: Array = intentions.get(str(npc.id), [])
		if npc_intentions.is_empty():
			npc.todo_list = [TodoItemScript.from_dict({
				"id": "todo_%s_seed_wander" % str(npc.id),
				"intent": "wander",
				"reason": "%s先在鹅城里观察情况" % npc.name,
				"priority": 10,
				"status": "pending",
			})]
			continue
		var intention: Dictionary = npc_intentions[0]
		var locations: Array = intention.get("locations", [])
		var location_id := str(locations[0].get("location", "")) if not locations.is_empty() and locations[0] is Dictionary else ""
		npc.todo_list = [TodoItemScript.from_dict({
			"id": "todo_%s_%s" % [str(npc.id), str(intention.get("id", "seed"))],
			"intent": "visit_place",
			"target_place_id": location_id,
			"reason": str(intention.get("label", "按动机行动")),
			"priority": 50,
			"status": "pending",
		})]


func _tile_from_array(value: Variant) -> Vector2i:
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO


func _tags_text(value: Variant) -> String:
	if not (value is Array):
		return ""
	var parts: PackedStringArray = []
	for entry in value:
		parts.append(str(entry))
	return ", ".join(parts)


func _fallback_stardive_npcs() -> Array:
	return [
		{"id": "trump", "name": "特朗普", "tile_x": 16, "tile_y": 8, "traits": {"tell": 78, "face": 86, "control": 88, "caution": 44, "play": 72}, "tags": ["authority"], "style": {"lineMode": "over_denial"}, "animSetId": "trump"},
		{"id": "jiu_tong", "name": "九筒", "tile_x": 13, "tile_y": 14, "traits": {"tell": 42, "face": 65, "control": 52, "caution": 82, "play": 36}, "tags": ["debt_avoidant"], "style": {"lineMode": "strategic_observer"}, "animSetId": "jiu_tong"},
		{"id": "shi_ye", "name": "师爷", "tile_x": 14, "tile_y": 13, "traits": {"tell": 66, "face": 78, "control": 74, "caution": 70, "play": 92}, "tags": ["bureaucratic"], "style": {"lineMode": "bureaucratic_rename"}, "animSetId": "shi_ye"},
	]


func _wire_ui_nodes() -> void:
	grid_selection_overlay = world_map.get_node_or_null("GridSelectionOverlay")
	if grid_selection_overlay != null:
		grid_selection_overlay.cell_size = cell_size
		grid_selection_overlay.cell_clicked.connect(select_cell_target)
		grid_selection_overlay.drag_started.connect(start_drag_grab)
		grid_selection_overlay.drag_changed.connect(update_drag_preview)
		grid_selection_overlay.drag_finished.connect(drop_or_release_selection)

	fenced_area_overlay = world_map.get_node_or_null("FencedAreaOverlay")
	if fenced_area_overlay != null:
		fenced_area_overlay.cell_size = cell_size
		fenced_area_overlay.configure(place_registry)

	fenced_area_edit_panel = ui_layer.get_node_or_null("FencedAreaEditPanel")
	if fenced_area_edit_panel != null:
		fenced_area_edit_panel.configure(placement_service)
		fenced_area_edit_panel.placement_confirmed.connect(on_fenced_area_placement_confirmed)

	feedback_label = ui_layer.get_node_or_null("FeedbackLabel")
	if feedback_label == null:
		feedback_label = Label.new()
		feedback_label.name = "FeedbackLabel"
		feedback_label.position = Vector2(16, 16)
		feedback_label.custom_minimum_size = Vector2(420, 32)
		ui_layer.add_child(feedback_label)

	controls_hint = ui_layer.get_node_or_null("ControlsHint")

	schedule_sidebar = ui_layer.get_node_or_null("ScheduleSidebar")

	clock_label = ui_layer.get_node_or_null("ClockLabel")


func _update_feedback_text(message: String) -> void:
	if feedback_label != null:
		feedback_label.text = message


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size + cell_size * 0.5, cell.y * cell_size + cell_size * 0.5)
