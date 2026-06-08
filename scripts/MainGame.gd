extends Node2D
class_name MainGame

const ConstantsScript := preload("res://scripts/core/Constants.gd")
const BuildingPlacementServiceScript := preload("res://scripts/world/BuildingPlacementService.gd")
const GridPathfinderScript := preload("res://scripts/world/GridPathfinder.gd")
const InteractionEventLogScript := preload("res://scripts/world/InteractionEventLog.gd")
const InteractionEventScript := preload("res://scripts/state/InteractionEvent.gd")
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
const NPCPerformanceDirectorScript := preload("res://scripts/npc/NPCPerformanceDirector.gd")
const ChatTransferParserScript := preload("res://scripts/npc/ChatTransferParser.gd")
const StakeholderPerceptionServiceScript := preload("res://scripts/npc/StakeholderPerceptionService.gd")
const NPCMoverScript := preload("res://scripts/npc/NPCMover.gd")
const TodoExecutorScript := preload("res://scripts/npc/TodoExecutor.gd")
const NPCActionSchedulerScript := preload("res://scripts/npc/NPCActionScheduler.gd")
const NPCAutoDropServiceScript := preload("res://scripts/npc/NPCAutoDropService.gd")
const NPCExecutionLoopScript := preload("res://scripts/npc/NPCExecutionLoop.gd")
const GameClockScript := preload("res://scripts/world/GameClock.gd")
const ConfigLoaderScript := preload("res://scripts/config/ConfigLoader.gd")
const InteractionDeltaRulesScript := preload("res://scripts/world/InteractionDeltaRules.gd")
const WellbeingRulesScript := preload("res://scripts/world/WellbeingRules.gd")
const RelationshipDecisionServiceScript := preload("res://scripts/npc/RelationshipDecisionService.gd")
const StoryArcRegistryScript := preload("res://scripts/world/StoryArcRegistry.gd")
const HeldItemLayoutScript := preload("res://scripts/ui/HeldItemLayout.gd")
const NPCContextDebugExporterScript := preload("res://scripts/debug/NPCContextDebugExporter.gd")

@export var cell_size: int = 64
@export var camera_speed: float = 420.0
@export var map_bounds: Rect2i = Rect2i(0, 0, 30, 25)

# 拖拽重力感：被抓实体每帧朝鼠标世界坐标插值，GRAB_PULL 为每帧拉拽比例。
const GRAB_PULL := 0.2
# 视觉 hit-test 选中半径（像素）：点击世界坐标落在该半径内即选中最近实体。
const HIT_RADIUS := 58.0
const NPC_CENTER_GRAB_RADIUS := 16.0
# 滚轮 zoom：以光标为锚，每档乘 ZOOM_STEP / 除 ZOOM_STEP，clamp 到 [ZOOM_MIN, ZOOM_MAX]。
const ZOOM_MIN := 0.8
const ZOOM_MAX := 2.35
const ZOOM_STEP := 1.12
const MOUSE_DRAG_THRESHOLD := 8.0
const FEEDBACK_PAUSE_SECONDS := 8.0
const NPC_RECENT_MEMORY_LIMIT := 20
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
var npc_performance_director
var chat_transfer_parser
var stakeholder_perception_service

# NPC 执行层：每个 NPC 一个 mover（持路径状态），共享 executor + scheduler。
var npc_movers: Dictionary = {}   # npc_id(StringName) -> NPCMover
var npc_feedback_pause_until_ms: Dictionary = {}  # npc_id(StringName) -> timestamp_ms
var todo_executor
var action_scheduler
var npc_auto_drop_service
var npc_execution_loop
var relationship_decision_service
var story_arc_registry
var npc_context_debug_exporter

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
var npc_chat_panel
var game_clock
var gameplay_config: Dictionary = {}
var wellbeing_config: Dictionary = {}
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
	_load_runtime_configs()
	_resolve_scene_nodes()
	_fit_world_background(_world_background_path())
	_wire_core_world_services()
	_wire_npc_llm_services()
	_seed_sample_npc_item_data()
	_wire_ui_nodes()
	_update_feedback_text(_ui_message("ready"))
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
			assign_daily_wellbeing_problem()
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
		elif event.keycode == KEY_D and event.ctrl_pressed:
			export_npc_context_debug_dump()
		elif event.keycode == KEY_H:
			toggle_controls_hint()


func toggle_controls_hint() -> void:
	_controls_expanded = not _controls_expanded
	if controls_hint != null:
		controls_hint.text = _controls_text(_controls_expanded)


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
		if npc_chat_panel != null and entity_registry.npcs.has(hit_id) and npc_chat_panel.has_method("select_target"):
			npc_chat_panel.select_target(hit_id)
		_update_feedback_text(_ui_message("selectedEntity", {"entity_id": str(hit_id)}))
		return
	selected_entity_id = &""
	grabbed_entity_id = &""
	_update_selected_highlight()
	if schedule_sidebar != null:
		schedule_sidebar.clear()
	_begin_camera_drag()
	_update_feedback_text(_ui_message("selectedCell", {"cell": str(cell)}))


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
		_emit_preemptive_item_gag(grabbed_entity_id)


func update_drag_preview(selection_rect: Rect2i, end_cell: Vector2i) -> void:
	latest_drag_rect = selection_rect
	latest_drag_end_cell = end_cell
	if fenced_area_mode:
		_update_feedback_text(_ui_message("fencedAreaFootprint", {"rect": str(selection_rect)}))


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
		_update_feedback_text(_ui_message("droppedEntity", {"entity_id": str(grabbed_entity_id)}))
	grabbed_entity_id = &""
	dragged_item_previous_anchor_npc_id = &""
	_end_camera_drag()


func discard_held_item_with_right_click() -> void:
	if selected_entity_id == &"" or not entity_registry.npcs.has(selected_entity_id):
		_update_feedback_text(_ui_message("rightClickDiscardHint"))
		return
	var before_count: int = event_log.events.size() if event_log != null and event_log.get("events") is Array else 0
	if entity_registry.drop_anchored_items(selected_entity_id, event_log):
		_update_feedback_text(_ui_message("discardedHeldItem"))
		var new_events: Array = event_log.events.slice(before_count, event_log.events.size()) if event_log != null and event_log.get("events") is Array else []
		for event in new_events:
			_apply_wellbeing_to_event(event)
			_emit_npc_feedback(event, selected_entity_id)
	else:
		_update_feedback_text(_ui_message("noHeldItemToDiscard"))


func _handle_item_release(item_id: StringName, drop_world: Vector2) -> bool:
	var target_npc := _hit_test_npc_only(drop_world)
	if target_npc == &"":
		if entity_registry.set_entity_position(item_id, drop_world):
			event_log.record(&"player_move_entity", item_id, &"", &"cell", ConstantsScript.world_to_cell(drop_world), {}, &"player", tick)
			_update_feedback_text(_ui_message("droppedEntity", {"entity_id": str(item_id)}))
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
	var payload := _item_event_payload(item_id, target_npc, previous_holder, _gift_context_for_item_event(item_id, target_npc, previous_holder, "player_drag"))
	var auto_drop := _maybe_auto_drop_rejected_item(item_id, target_npc, payload)
	if not auto_drop.is_empty():
		payload["npc_auto_drop"] = auto_drop
		payload["currentAnchor"] = auto_drop.get("finalAnchor", {"type": "ground"})
		payload["finalAnchor"] = auto_drop.get("finalAnchor", {"type": "ground"})
		payload["event_text"] = _event_text_template("autoDrop", {
			"target_name": str(payload.get("item_target_name", target_npc)),
			"item_name": str(payload.get("item_name", item_id)),
		})
	var event = event_log.record(event_type, item_id, target_npc, &"npc", ConstantsScript.world_to_cell(drop_world), payload, &"player", tick)
	_apply_wellbeing_to_event(event)
	_update_feedback_text(str(event.payload.get("event_text", payload.get("event_text", _ui_message("npcAcceptedItemFallback")))))
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
		var payload := _item_event_payload(target_item, npc_id, previous_holder, _gift_context_for_item_event(target_item, npc_id, previous_holder, "player_drag_npc"))
		var auto_drop := _maybe_auto_drop_rejected_item(target_item, npc_id, payload)
		if not auto_drop.is_empty():
			payload["npc_auto_drop"] = auto_drop
			payload["currentAnchor"] = auto_drop.get("finalAnchor", {"type": "ground"})
			payload["finalAnchor"] = auto_drop.get("finalAnchor", {"type": "ground"})
			payload["event_text"] = _event_text_template("autoDrop", {
				"target_name": str(payload.get("item_target_name", npc_id)),
				"item_name": str(payload.get("item_name", target_item)),
			})
		var event_type := &"player_transfer_item_between_npcs" if previous_holder != &"" and previous_holder != npc_id else &"player_drop_npc_near_item"
		var event = event_log.record(event_type, target_item, npc_id, &"npc", ConstantsScript.world_to_cell(drop_world), payload, &"player", tick)
		_apply_wellbeing_to_event(event)
		_update_feedback_text(str(event.payload.get("event_text", payload.get("event_text", _ui_message("npcTouchedItemFallback")))))
		_emit_interaction_feedback(event, _payload_npc_ids(payload))
		return true
	if target_npc != &"" and target_npc != npc_id:
		_place_npc_near_target(npc_id, target_npc)
		var payload := _npc_encounter_payload(npc_id, target_npc)
		var event = event_log.record(&"player_drop_npc_near_npc", npc_id, target_npc, &"npc", ConstantsScript.world_to_cell(drop_world), payload, &"player", tick)
		_apply_wellbeing_to_event(event)
		_update_feedback_text(str(payload.get("event_text", _ui_message("droppedEntity", {"entity_id": str(npc_id)}))))
		_emit_interaction_feedback(event, _payload_npc_ids(payload))
		return true
	return false


func _item_event_payload(item_id: StringName, target_npc_id: StringName, previous_holder_id: StringName = &"", gift_context: Dictionary = {}) -> Dictionary:
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
	var template_values := _item_template_values(item_id, target_npc_id, previous_holder_id)
	var event_text := _event_text_template("itemDirect", template_values)
	if is_transfer:
		event_text = _event_text_template("itemTransfer", template_values)
	elif item != null and item.owner_id != &"" and item.owner_id != target_npc_id:
		event_text = _event_text_template("itemMisplaced", template_values)
	var participant_actions := _item_participant_actions(item_id, target_npc_id, previous_holder_id, npc_ids)
	var scene_seed := _item_scene_seed(item_id, target_npc_id, previous_holder_id, nearby_ids)
	if gift_context.is_empty():
		gift_context = _gift_context_for_item_event(item_id, target_npc_id, previous_holder_id, "player_drag")
	var interaction_delta := InteractionDeltaRulesScript.apply_attach_object_to_npc(item, target_npc_id, previous_holder_id, npc_ids, entity_registry, gameplay_config, tick, gift_context)
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
		"gift_trace": interaction_delta.get("giftTrace", {}),
		"gift_context": interaction_delta.get("giftContext", gift_context),
		"gift_stance": interaction_delta.get("giftStance", {}),
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
		"object_classification": item.classification.duplicate(true) if item != null else {},
		"object_social": item.social.duplicate(true) if item != null else {},
		"object_social_state": _item_social_state(item_id, target_npc_id, is_transfer),
		"object_memory": item.memory.duplicate(true) if item != null else {"topLinks": []},
	}


func _maybe_auto_drop_rejected_item(item_id: StringName, target_npc_id: StringName, payload: Dictionary) -> Dictionary:
	if npc_auto_drop_service == null:
		npc_auto_drop_service = NPCAutoDropServiceScript.new()
		npc_auto_drop_service.configure(entity_registry, gameplay_config)
	return npc_auto_drop_service.maybe_auto_drop_rejected_item(item_id, target_npc_id, payload)


func _gift_context_for_item_event(item_id: StringName, target_npc_id: StringName, previous_holder_id: StringName = &"", operator: String = "player_drag") -> Dictionary:
	var from_anchor := {"type": "ground"}
	if previous_holder_id != &"":
		from_anchor = {"type": "npc", "npcId": str(previous_holder_id)}
	elif entity_registry != null and entity_registry.items.has(item_id):
		var item = entity_registry.items[item_id]
		if item.current_anchor is Dictionary:
			from_anchor = item.current_anchor.duplicate(true)
	var attribution_target := "unknown"
	var confidence := 0.0
	if previous_holder_id != &"" and previous_holder_id != target_npc_id:
		attribution_target = "npc"
		confidence = 1.0
	elif operator.begins_with("player"):
		attribution_target = "player"
		confidence = 1.0
	return {
		"operator": operator,
		"giverNpcId": previous_holder_id if attribution_target == "npc" else &"",
		"receiverNpcId": target_npc_id,
		"fromAnchor": from_anchor,
		"toAnchor": {"type": "npc", "npcId": str(target_npc_id)},
		"attributionTarget": attribution_target,
		"attributionConfidence": confidence,
	}


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
		"recent_actions": [_event_text_template("npcEncounterRecent", {"primary_name": primary_name, "target_name": target_name})],
		"event_text": _event_text_template("npcEncounter", {"primary_name": primary_name, "target_name": target_name}),
		"scene_seed": _npc_scene_seed(primary_npc_id, target_npc_id),
		"relationship_hint": _interaction_template("relationshipHints", "npcEncounter"),
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
		"object_classification": item.classification.duplicate(true) if item != null else {},
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


func _emit_preemptive_item_gag(item_id: StringName) -> Dictionary:
	if entity_registry == null or event_log == null or not entity_registry.items.has(item_id):
		return {}
	var item = entity_registry.items[item_id]
	var best := {}
	for npc_id in entity_registry.npcs.keys():
		var gag := InteractionDeltaRulesScript.preemptive_gag_for_item_target(item, StringName(npc_id), gameplay_config)
		if gag.is_empty():
			continue
		if best.is_empty() or _gag_stage_rank(str(gag.get("stage", "new"))) > _gag_stage_rank(str(best.get("stage", "new"))):
			best = gag
	if best.is_empty():
		return {}
	var target_id := StringName(best.get("npcId", ""))
	if target_id == &"" or not entity_registry.npcs.has(target_id):
		return {}
	best = _promote_preemptive_item_gag_memory(item, target_id, best)
	var npc = entity_registry.npcs[target_id]
	var item_name: String = item.name if item != null else str(item_id)
	var line := str(best.get("preemptiveLine", ""))
	var gag_cfg := _interaction_config("preemptiveItemGag")
	var values := {
		"npc_name": npc.name,
		"item_name": item_name,
		"line": line,
	}
	if line.is_empty():
		line = _template_field(gag_cfg, "fallbackLine", values)
		values["line"] = line
	var retreat := _maybe_retreat_from_preemptive_gag(target_id, item_id, best)
	var scene_cfg: Dictionary = gag_cfg.get("sceneSeed", {})
	var payload := {
		"source": "preemptive_item_gag",
		"npc_ids": [target_id],
		"primary_npc_ids": [target_id],
		"item_id": item_id,
		"item_name": item_name,
		"gagTag": str(best.get("gagTag", "")),
		"gagAction": str(best.get("gagAction", "")),
		"stage": str(best.get("stage", "")),
		"body_reaction": retreat,
		"event_text": _template_field(gag_cfg, "eventText", values),
		"recent_actions": [_template_field(gag_cfg, "recentAction", values)],
		"scene_seed": {
			"type": _template_field(scene_cfg, "type", values),
			"title": _template_field(scene_cfg, "title", values),
			"visible_topic": _template_field(scene_cfg, "visibleTopic", values),
			"trigger_action": _template_field(scene_cfg, "triggerAction", values),
			"actor": target_id,
			"observer": &"player",
		"required_shift": _array_from(scene_cfg.get("requiredShift", [])),
		"allowed_outcomes": _array_from(scene_cfg.get("allowedOutcomes", [])),
			"interaction_goal": _template_field(scene_cfg, "goal", values),
			"consequence_rule": _template_field(scene_cfg, "consequence", values),
		},
	}
	var event = event_log.record(&"player_drag_started_trained_item", item_id, target_id, &"npc", npc.current_cell, payload, &"player", tick)
	_update_feedback_text(str(payload.get("event_text", "")))
	_emit_interaction_feedback(event, [target_id])
	return payload


func _maybe_retreat_from_preemptive_gag(npc_id: StringName, item_id: StringName, gag: Dictionary) -> Dictionary:
	if entity_registry == null or not entity_registry.npcs.has(npc_id) or not entity_registry.items.has(item_id):
		return {}
	var action := str(gag.get("gagAction", ""))
	var stage := str(gag.get("stage", "new"))
	if not _gag_action_implies_retreat(action):
		return {}
	var npc = entity_registry.npcs[npc_id]
	var item_pos := _item_world_position(item_id)
	var direction: Vector2 = (npc.position - item_pos).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var distance: float = float(ConstantsScript.CELL_SIZE) * (1.25 if _gag_stage_rank(stage) >= _gag_stage_rank("noticed") else 0.75)
	var before: Vector2 = npc.position
	var target_pos: Vector2 = before + direction * distance
	if not entity_registry.set_npc_position(npc_id, target_pos):
		return {}
	return {
		"type": "retreat",
		"action": action,
		"from": {"x": before.x, "y": before.y},
		"to": {"x": npc.position.x, "y": npc.position.y},
	}


func _gag_action_implies_retreat(action: String) -> bool:
	return ["step_back", "hold_up_hands", "push_object_back", "snap_notebook_close"].has(action)


func _promote_preemptive_item_gag_memory(item, target_id: StringName, gag: Dictionary) -> Dictionary:
	if item == null or not (item.memory is Dictionary):
		return gag
	var memory: Dictionary = item.memory
	var links: Array = memory.get("topLinks", [])
	for link in links:
		if not (link is Dictionary):
			continue
		if StringName(link.get("npcId", "")) != target_id:
			continue
		if _gag_stage_rank(str(link.get("stage", "new"))) < _gag_stage_rank("noticed"):
			link["stage"] = "noticed"
			link["lastStageChangedAt"] = tick
		link["lastUsedAt"] = tick
		memory["topLinks"] = links
		item.memory = memory
		var promoted := gag.duplicate(true)
		promoted["stage"] = str(link.get("stage", gag.get("stage", "")))
		return promoted
	return gag


func _gag_stage_rank(stage: String) -> int:
	var order := ["new", "repeated", "noticed", "gagged", "ritualized"]
	return max(0, order.find(stage))


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
	var action_cfg := _interaction_config("itemParticipantActions")
	var values := _item_template_values(item_id, target_id, previous_holder_id)
	var actions: Array = []
	var target_label := _template_field(action_cfg, "targetOwnedLabel", values)
	var target_motive := _template_field(action_cfg, "targetOwnedMotive", values)
	if previous_holder_id != &"" and previous_holder_id != target_id:
		target_label = _template_field(action_cfg, "targetTransferLabel", values)
		target_motive = _template_field(action_cfg, "targetTransferMotive", values)
	elif owner_id != &"" and owner_id != target_id:
		target_label = _template_field(action_cfg, "targetMisplacedLabel", values)
		target_motive = _template_field(action_cfg, "targetMisplacedMotive", values)
	actions.append({
		"npc_id": target_id,
		"name": target_name,
		"intention_label": target_label,
		"intention_motive": target_motive,
		"desired_outcome": _template_field(action_cfg, "targetDesiredOutcome", values),
	})
	if previous_holder_id != &"" and previous_holder_id != target_id:
		actions.append({
			"npc_id": previous_holder_id,
			"name": _npc_name(previous_holder_id),
			"intention_label": _template_field(action_cfg, "previousLabel", values),
			"intention_motive": _template_field(action_cfg, "previousMotive", values),
			"desired_outcome": _template_field(action_cfg, "previousDesiredOutcome", values),
		})
	for raw_id in npc_ids:
		var npc_id := StringName(raw_id)
		if npc_id == target_id or npc_id == previous_holder_id:
			continue
		var witness_values := values.duplicate(true)
		witness_values["radius_meters"] = "%.1f" % _item_involvement_radius_meters()
		actions.append({
			"npc_id": npc_id,
			"name": _npc_name(npc_id),
			"intention_label": _template_field(action_cfg, "witnessLabel", witness_values),
			"intention_motive": _template_field(action_cfg, "witnessMotive", witness_values),
			"desired_outcome": _template_field(action_cfg, "witnessDesiredOutcome", witness_values),
		})
	return actions


func _item_template_values(item_id: StringName, target_id: StringName, previous_holder_id: StringName = &"") -> Dictionary:
	var item = entity_registry.items.get(item_id) if entity_registry != null else null
	var owner_id: StringName = item.owner_id if item != null else &""
	return {
		"item_id": str(item_id),
		"item_name": item.name if item != null else str(item_id),
		"target_id": str(target_id),
		"target_name": _npc_name(target_id),
		"previous_id": str(previous_holder_id),
		"previous_name": _npc_name(previous_holder_id),
		"owner_id": str(owner_id),
		"owner_name": _npc_name(owner_id),
	}


func _meeting_participant_actions(npc_ids: Array) -> Array:
	var actions: Array = []
	var action_cfg := _interaction_config("meetingParticipantActions")
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
			"intention_label": _template_field(action_cfg, "label"),
			"intention_motive": _template_field(action_cfg, "motive"),
			"desired_outcome": _template_field(action_cfg, "desiredOutcome"),
		})
	return actions


func _item_scene_seed(item_id: StringName, target_id: StringName, previous_holder_id: StringName, nearby_ids: Array) -> Dictionary:
	var item = entity_registry.items.get(item_id)
	var item_name: String = item.name if item != null else str(item_id)
	var owner_id: StringName = item.owner_id if item != null else &""
	var is_transfer := previous_holder_id != &"" and previous_holder_id != target_id
	var seed_cfg := _interaction_config("itemSceneSeed")
	var values := _item_template_values(item_id, target_id, previous_holder_id)
	var mode_cfg: Dictionary = seed_cfg.get("solo", {})
	var visible_topic := _template_field(mode_cfg, "visibleTopic", values)
	if is_transfer:
		mode_cfg = seed_cfg.get("transfer", {})
		visible_topic = _template_field(mode_cfg, "visibleTopic", values)
	elif owner_id != &"" and owner_id != target_id:
		visible_topic = _template_field(seed_cfg, "misplacedVisibleTopic", values)
	if not is_transfer and not nearby_ids.is_empty():
		mode_cfg = seed_cfg.get("witness", {})
		values["witness_name"] = _npc_name(StringName(nearby_ids[0]))
		values["radius_meters"] = "%.1f" % _item_involvement_radius_meters()
		visible_topic = _template_field(mode_cfg, "visibleTopic", values)
	return {
		"type": _template_field(mode_cfg, "type", values),
		"title": _template_field(mode_cfg, "title", values),
		"trigger_action": _template_field(seed_cfg, "triggerAction", values),
		"actor": target_id,
		"observer": previous_holder_id if is_transfer else (StringName(nearby_ids[0]) if not nearby_ids.is_empty() else &""),
		"visible_topic": visible_topic,
		"object_social_state": _item_social_state(item_id, target_id, is_transfer),
		"emotional_charge": _item_scene_emotional_charge(seed_cfg, is_transfer),
		"conflict_question": _template_field(seed_cfg, "conflictQuestion", values),
		"required_shift": _array_from(seed_cfg.get("requiredShift", [])),
		"allowed_outcomes": _array_from(seed_cfg.get("allowedOutcomes", [])),
		"stakes": _template_field(seed_cfg, "stakes", values),
		"interaction_goal": _template_field(mode_cfg, "goal", values),
		"consequence_rule": _template_field(mode_cfg, "consequence", values),
	}


func _item_scene_emotional_charge(seed_cfg: Dictionary, is_transfer: bool) -> int:
	var charge_cfg: Dictionary = seed_cfg.get("emotionalCharge", {})
	return int(charge_cfg.get("transfer" if is_transfer else "solo", 0))


func _npc_scene_seed(primary_id: StringName, target_id: StringName) -> Dictionary:
	var seed_cfg := _interaction_config("npcSceneSeed")
	var values := {
		"primary_name": _npc_name(primary_id),
		"target_name": _npc_name(target_id),
	}
	return {
		"type": _template_field(seed_cfg, "type", values),
		"title": _template_field(seed_cfg, "title", values),
		"trigger_action": _template_field(seed_cfg, "triggerAction", values),
		"actor": primary_id,
		"observer": target_id,
		"visible_topic": _template_field(seed_cfg, "visibleTopic", values),
		"emotional_charge": int(seed_cfg.get("emotionalCharge", 0)),
		"conflict_question": _template_field(seed_cfg, "conflictQuestion", values),
		"required_shift": _array_from(seed_cfg.get("requiredShift", [])),
		"allowed_outcomes": _array_from(seed_cfg.get("allowedOutcomes", [])),
		"stakes": _template_field(seed_cfg, "stakes", values),
		"interaction_goal": _template_field(seed_cfg, "goal", values),
		"consequence_rule": _template_field(seed_cfg, "consequence", values),
	}


func _item_relationship_hint(item_id: StringName, target_id: StringName, previous_holder_id: StringName, nearby_ids: Array) -> String:
	var values := _item_template_values(item_id, target_id, previous_holder_id)
	if previous_holder_id != &"" and previous_holder_id != target_id:
		return _interaction_template("relationshipHints", "itemTransfer", values)
	if not nearby_ids.is_empty():
		return _interaction_template("relationshipHints", "itemWitness", values)
	return _interaction_template("relationshipHints", "itemSolo", values)


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
	_remember_event_for_npcs(event, participants)
	_pause_feedback_participants(participants)
	for npc_id in participants:
		_emit_interaction_performance_text(event, npc_id)
		_emit_npc_feedback(event, npc_id)


func _emit_interaction_performance_text(event, npc_id: StringName) -> void:
	if event == null or npc_performance_director == null or entity_registry == null or not entity_registry.npcs.has(npc_id):
		return
	var payload: Dictionary = event.payload if event.payload is Dictionary else {}
	var plan: Dictionary = payload.get("performance_plan", {})
	if plan.is_empty():
		return
	var judgement: Dictionary = _performance_judgement_from_payload(payload, npc_id)
	var rendered: String = npc_performance_director.render_plan(plan, judgement, false)
	if rendered.is_empty():
		return
	event.payload["interaction_performance_text"] = rendered
	_add_npc_chat_line(npc_id, rendered)
	if entity_visual_layer != null and entity_visual_layer.npc_visuals.has(npc_id):
		entity_visual_layer.npc_visuals[npc_id].show_bubble(rendered)


func _performance_judgement_from_payload(payload: Dictionary, npc_id: StringName) -> Dictionary:
	var stance: Dictionary = payload.get("gift_stance", {})
	var result := str(stance.get("result", "ambivalent"))
	var judgement_result := "neutral"
	if ["like", "like_then_reject"].has(result):
		judgement_result = "help"
	elif ["reject", "accept_then_discard"].has(result):
		judgement_result = "harm"
	var labels: Dictionary = wellbeing_config.get("feedbackTags", {}) if wellbeing_config is Dictionary else {}
	return {
		"result": judgement_result,
		"reason": str(stance.get("dominantReason", "object_interaction")),
		"resultLabel": str(labels.get(judgement_result, judgement_result)),
		"npcId": str(npc_id),
	}


func assign_daily_wellbeing_problem() -> void:
	if entity_registry == null or wellbeing_config.is_empty():
		return
	var day: int = game_clock.day if game_clock != null else 1
	var assigned: Dictionary = WellbeingRulesScript.assign_daily_problem(entity_registry.npcs, wellbeing_config, day)
	if not assigned.is_empty() and entity_visual_layer != null:
		entity_visual_layer.sync_from_registry(entity_registry)


func _apply_wellbeing_to_event(event) -> void:
	if event == null or wellbeing_config.is_empty() or entity_registry == null:
		return
	var target_id := _wellbeing_target_npc_id(event)
	if target_id == &"" or not entity_registry.npcs.has(target_id):
		return
	var item = _wellbeing_event_item(event)
	var npc = entity_registry.npcs[target_id]
	var judgement: Dictionary = WellbeingRulesScript.evaluate_event(event, npc, item, wellbeing_config)
	if judgement.is_empty():
		return
	event.payload["wellbeing_judgement"] = judgement
	if npc_performance_director == null:
		return
	npc_performance_director.request_plan(judgement, npc, item, func(plan: Dictionary) -> void:
		if plan.is_empty():
			return
		event.payload["wellbeing_performance_plan"] = plan
		var rendered: String = npc_performance_director.render_plan(plan, judgement, false)
		if not rendered.is_empty():
			event.payload["wellbeing_feedback_text"] = rendered
			event.payload["event_text"] = rendered
			_update_feedback_text(rendered)
			_add_npc_chat_line(target_id, rendered)
			if entity_visual_layer != null and entity_visual_layer.npc_visuals.has(target_id):
				entity_visual_layer.npc_visuals[target_id].show_bubble(rendered)
	)


func _add_npc_chat_line(npc_id: StringName, message: String) -> void:
	var clean_message := message.strip_edges()
	if clean_message.is_empty() or npc_chat_panel == null or not npc_chat_panel.has_method("add_line"):
		return
	var speaker := str(npc_id)
	if entity_registry != null and entity_registry.npcs.has(npc_id):
		speaker = str(entity_registry.npcs[npc_id].name)
	npc_chat_panel.add_line(speaker, clean_message)


func _wellbeing_target_npc_id(event) -> StringName:
	var event_type := StringName(event.type if event != null else &"")
	var payload: Dictionary = event.payload if event != null and event.payload is Dictionary else {}
	if event_type == &"player_drop_npc_near_npc":
		var target_id := StringName(payload.get("target_npc_id", event.target_entity_id))
		return target_id if target_id != &"" else StringName(event.target_entity_id)
	if event_type == &"player_forced_drop_item":
		return StringName(payload.get("item_target_id", event.target_entity_id))
	return StringName(payload.get("item_target_id", event.target_entity_id))


func _wellbeing_event_item(event):
	if event == null or entity_registry == null:
		return null
	var item_id := StringName(event.primary_entity_id)
	if item_id != &"" and entity_registry.items.has(item_id):
		return entity_registry.items[item_id]
	var payload: Dictionary = event.payload if event.payload is Dictionary else {}
	item_id = StringName(payload.get("item_id", &""))
	if item_id != &"" and entity_registry.items.has(item_id):
		return entity_registry.items[item_id]
	return null


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


func _remember_event_for_npcs(event, npc_ids: Array) -> void:
	if event == null or entity_registry == null:
		return
	_observe_story_arcs(event)
	for raw_id in npc_ids:
		_remember_event_for_npc(event, StringName(raw_id))


func _remember_event_for_npc(event, npc_id: StringName) -> void:
	if npc_id == &"" or not entity_registry.npcs.has(npc_id):
		return
	var npc = entity_registry.npcs[npc_id]
	var event_id := StringName(event.id if event != null else &"")
	if event_id != &"":
		for remembered in npc.recent_events:
			if remembered != null and StringName(remembered.id) == event_id:
				return
	var snapshot = InteractionEventScript.from_dict(event.to_dict()) if event != null and event.has_method("to_dict") else event
	npc.recent_events.append(snapshot)
	_trim_npc_recent_events(npc)


func _remember_npc_feedback_line(npc_id: StringName, source_event, line: String) -> void:
	var clean_line := line.strip_edges()
	if clean_line.is_empty() or entity_registry == null or not entity_registry.npcs.has(npc_id):
		return
	var npc = entity_registry.npcs[npc_id]
	var source_event_id := str(source_event.id if source_event != null else "")
	var memory_id := StringName("%s:%s:reply" % [source_event_id, str(npc_id)])
	for remembered in npc.recent_events:
		if remembered != null and StringName(remembered.id) == memory_id:
			return
	var reply_event = InteractionEventScript.from_dict({
		"id": memory_id,
		"type": "npc_feedback_line",
		"actor_id": str(npc_id),
		"primary_entity_id": str(npc_id),
		"target_entity_id": str(source_event.primary_entity_id if source_event != null else ""),
		"target_type": str(source_event.target_type if source_event != null else "npc"),
		"cell": ConstantsScript.cell_to_dict(npc.current_cell),
		"tick": tick,
		"payload": {
			"source": "npc_feedback",
			"sourceEventId": source_event_id,
			"speakerNpcId": str(npc_id),
			"speakerName": npc.name,
			"text": clean_line,
		},
	})
	npc.recent_events.append(reply_event)
	_trim_npc_recent_events(npc)


func _trim_npc_recent_events(npc) -> void:
	while npc != null and npc.recent_events.size() > NPC_RECENT_MEMORY_LIMIT:
		npc.recent_events.pop_front()


func _observe_story_arcs(event) -> Array:
	if story_arc_registry == null or event == null or entity_registry == null:
		return []
	var updates: Array = story_arc_registry.observe_event(event, entity_registry, tick)
	if not updates.is_empty() and event.payload is Dictionary:
		event.payload["story_arc_updates"] = updates
		event.payload["active_story_arcs"] = story_arc_registry.to_dict().get("arcs", {})
	return updates


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
	_remember_event_for_npcs(event, [npc_id])
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
	, func(result: Dictionary) -> void:
		var final_text := str(result.get("text", ""))
		_remember_npc_feedback_line(npc_id, event, final_text)
		_add_npc_chat_line(npc_id, final_text)
		)


func submit_npc_chat_message(target_npc_id: StringName, message: String) -> void:
	var clean_message := message.strip_edges()
	if clean_message.is_empty() or entity_registry == null or not entity_registry.npcs.has(target_npc_id):
		return
	var target = entity_registry.npcs[target_npc_id]
	if npc_chat_panel != null and npc_chat_panel.has_method("add_line"):
		npc_chat_panel.add_line(_chat_player_speaker_label(target), clean_message)
	if npc_chat_panel != null and npc_chat_panel.has_method("set_waiting"):
		npc_chat_panel.set_waiting(true)
	var event = _event_from_chat_message(target_npc_id, clean_message)
	if event == null:
		if npc_chat_panel != null and npc_chat_panel.has_method("set_waiting"):
			npc_chat_panel.set_waiting(false)
		return
	_update_feedback_text(str(event.payload.get("event_text", clean_message)))
	_emit_npc_chat_feedback(event, target_npc_id)


func _chat_player_speaker_label(target) -> String:
	var panel_cfg: Dictionary = gameplay_config.get("ui", {}).get("chatPanel", {})
	return _format_template(str(panel_cfg.get("playerSpeakerTemplate", "{npc_name}")), {"npc_name": str(target.name if target != null else "")})


func _event_from_chat_message(target_npc_id: StringName, message: String):
	var transfer := _parse_chat_transfer(target_npc_id, message)
	if bool(transfer.get("ok", false)):
		return _apply_chat_transfer_event(target_npc_id, message, transfer)
	return _record_direct_chat_event(target_npc_id, message)


func _record_direct_chat_event(target_npc_id: StringName, message: String):
	var npc = entity_registry.npcs[target_npc_id]
	var chat_cfg := _interaction_config("playerChat")
	var values := {
		"npc_name": npc.name,
		"message": message,
	}
	var payload := {
		"source": "player_chat",
		"player_message": message,
		"npc_ids": [target_npc_id],
		"primary_npc_ids": [target_npc_id],
		"participant_actions": [{
			"npc_id": target_npc_id,
			"name": npc.name,
			"intention_label": _template_field(chat_cfg, "participantLabel", values),
			"intention_motive": _template_field(chat_cfg, "participantMotive", values),
			"desired_outcome": _template_field(chat_cfg, "participantDesiredOutcome", values),
		}],
		"recent_actions": [_template_field(chat_cfg, "recentAction", values)],
		"event_text": _template_field(chat_cfg, "eventText", values),
		"scene_seed": _chat_scene_seed(chat_cfg.get("sceneSeed", {}), target_npc_id, values),
		"relationship_hint": _template_field(chat_cfg, "relationshipHint", values),
	}
	var social_fact := _chat_social_fact(target_npc_id, message)
	if not social_fact.is_empty():
		payload["social_fact"] = social_fact
		var perception := _apply_chat_stakeholder_perception(target_npc_id, social_fact)
		if not perception.is_empty():
			payload["stakeholder_perception"] = perception
			payload["relation_memory_updates"] = perception.get("relationMemoryUpdates", [])
	var event = event_log.record(&"player_chat_to_npc", target_npc_id, target_npc_id, &"npc", npc.current_cell, payload, &"player", tick)
	_remember_event_for_npcs(event, [target_npc_id])
	return event


func _chat_scene_seed(seed_cfg: Dictionary, target_npc_id: StringName, values: Dictionary) -> Dictionary:
	return {
		"type": _template_field(seed_cfg, "type", values),
		"title": _template_field(seed_cfg, "title", values),
		"trigger_action": _template_field(seed_cfg, "triggerAction", values),
		"actor": target_npc_id,
		"observer": &"player",
		"visible_topic": _template_field(seed_cfg, "visibleTopic", values),
		"emotional_charge": int(seed_cfg.get("emotionalCharge", 0)),
		"conflict_question": _template_field(seed_cfg, "conflictQuestion", values),
		"required_shift": _array_from(seed_cfg.get("requiredShift", [])),
		"allowed_outcomes": _array_from(seed_cfg.get("allowedOutcomes", [])),
		"stakes": _template_field(seed_cfg, "stakes", values),
		"interaction_goal": _template_field(seed_cfg, "goal", values),
		"consequence_rule": _template_field(seed_cfg, "consequence", values),
	}


func _parse_chat_transfer(target_npc_id: StringName, message: String) -> Dictionary:
	if chat_transfer_parser == null:
		chat_transfer_parser = ChatTransferParserScript.new()
		chat_transfer_parser.configure(entity_registry, gameplay_config)
	return chat_transfer_parser.parse_transfer(target_npc_id, message)


func _chat_social_fact(target_npc_id: StringName, message: String) -> Dictionary:
	_ensure_stakeholder_perception_service()
	if stakeholder_perception_service == null:
		return {}
	var fact: Dictionary = stakeholder_perception_service.parse_chat_social_fact(target_npc_id, message)
	return fact if bool(fact.get("ok", false)) else {}


func _apply_chat_stakeholder_perception(target_npc_id: StringName, social_fact: Dictionary) -> Dictionary:
	_ensure_stakeholder_perception_service()
	if stakeholder_perception_service == null:
		return {}
	return stakeholder_perception_service.apply_observer_perception(target_npc_id, social_fact, tick)


func _ensure_stakeholder_perception_service() -> void:
	if stakeholder_perception_service != null:
		return
	stakeholder_perception_service = StakeholderPerceptionServiceScript.new()
	stakeholder_perception_service.configure(entity_registry, gameplay_config)


func _apply_chat_transfer_event(target_npc_id: StringName, message: String, transfer: Dictionary):
	var item_id := StringName(transfer.get("item_id", &""))
	var giver_id := StringName(transfer.get("giver_id", &""))
	var recipient_id := StringName(transfer.get("recipient_id", target_npc_id))
	var quantity: int = max(1, int(transfer.get("quantity", 1)))
	if item_id == &"" or giver_id == &"" or not entity_registry.items.has(item_id) or not entity_registry.npcs.has(recipient_id):
		return _record_direct_chat_event(target_npc_id, message)
	entity_registry.give_item_to_npc(item_id, recipient_id)
	var gift_context := {
		"operator": "player_chat_report",
		"giverNpcId": giver_id,
		"receiverNpcId": recipient_id,
		"fromAnchor": {"type": "npc", "npcId": str(giver_id)},
		"toAnchor": {"type": "npc", "npcId": str(recipient_id)},
		"attributionTarget": "npc",
		"attributionConfidence": 1.0,
	}
	var payload := _item_event_payload(item_id, recipient_id, giver_id, gift_context)
	if quantity > 1:
		for _index in range(quantity - 1):
			payload = _item_event_payload(item_id, recipient_id, giver_id, gift_context)
		payload["reported_quantity"] = quantity
	var world_event_text := str(payload.get("event_text", ""))
	var auto_drop := _maybe_auto_drop_rejected_item(item_id, recipient_id, payload)
	if not auto_drop.is_empty():
		payload["npc_auto_drop"] = auto_drop
		payload["currentAnchor"] = auto_drop.get("finalAnchor", {"type": "ground"})
		payload["finalAnchor"] = auto_drop.get("finalAnchor", {"type": "ground"})
		world_event_text = _event_text_template("autoDrop", {
			"target_name": str(payload.get("item_target_name", recipient_id)),
			"item_name": str(payload.get("item_name", item_id)),
		})
	payload["source"] = "player_chat_reported_transfer"
	payload["player_message"] = message
	payload["reported_by_chat_target_id"] = target_npc_id
	payload["reported_by_chat_target_name"] = _npc_name(target_npc_id)
	var reported_cfg := _interaction_config("reportedTransfer")
	var reported_values := {
		"target_name": _npc_name(target_npc_id),
		"message": message,
		"item_name": str(payload.get("item_name", item_id)),
		"giver_name": _npc_name(giver_id),
		"recipient_name": _npc_name(recipient_id),
	}
	payload["event_text"] = _template_field(reported_cfg, "eventText", reported_values)
	payload["recent_actions"] = [_template_field(reported_cfg, "recentAction", reported_values), world_event_text]
	var scene_seed: Dictionary = payload.get("scene_seed", {})
	scene_seed["trigger_action"] = _template_field(reported_cfg, "sceneTriggerAction", reported_values)
	var world_fact := _template_field(reported_cfg, "worldFact", reported_values)
	if not auto_drop.is_empty():
		world_fact = _template_field(reported_cfg, "autoDropWorldFact", reported_values)
	reported_values["world_fact"] = world_fact
	scene_seed["visible_topic"] = _template_field(reported_cfg, "visibleTopic", reported_values)
	payload["scene_seed"] = scene_seed
	var event = event_log.record(&"player_chat_reported_item_transfer", item_id, recipient_id, &"npc", entity_registry.npcs[recipient_id].current_cell, payload, &"player", tick)
	_remember_event_for_npcs(event, _valid_unique_npc_ids([target_npc_id, recipient_id, giver_id]))
	return event


func _emit_npc_chat_feedback(event, npc_id: StringName) -> void:
	if npc_feedback_builder == null or event == null or not entity_registry.npcs.has(npc_id):
		return
	_remember_event_for_npcs(event, [npc_id])
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
	, func(result: Dictionary) -> void:
		var final_text := str(result.get("text", ""))
		_remember_npc_feedback_line(npc_id, event, final_text)
		_add_npc_chat_line(npc_id, final_text)
		if npc_chat_panel != null and npc_chat_panel.has_method("set_waiting"):
			npc_chat_panel.set_waiting(false)
	)


func toggle_fenced_area_mode() -> void:
	fenced_area_mode = not fenced_area_mode
	grid_selection_overlay.enabled = true
	grid_selection_overlay.build_mode = fenced_area_mode
	grid_selection_overlay.queue_redraw()
	_update_feedback_text(_ui_message("fencedAreaMode", {"mode": "on" if fenced_area_mode else "off"}))


func confirm_fenced_area_from_drag(selection_rect: Rect2i, drag_end_cell: Vector2i) -> void:
	if selection_rect.size.x < 3 or selection_rect.size.y < 3:
		_update_feedback_text(_ui_message("fencedAreaSizeHint"))
		return
	if fenced_area_edit_panel != null:
		fenced_area_edit_panel.current_tick = tick
		fenced_area_edit_panel.open_for_selection(selection_rect, drag_end_cell, "Fenced Area %d" % (place_registry.places.size() + 1))


func create_fenced_area_mode() -> void:
	fenced_area_mode = true
	_update_feedback_text(_ui_message("fencedAreaDragHint"))


func on_fenced_area_placement_confirmed(result: Dictionary) -> void:
	if result.get("ok", false):
		fenced_area_mode = false
		fenced_area_overlay.refresh_from_registry()
		_update_feedback_text(_ui_message("fencedAreaCreated", {"place_name": str(result["place"].name)}))
	else:
		_update_feedback_text(_ui_message("fencedAreaFailed", {"reason": str(result.get("reason", "unknown"))}))


func update_feedback_reaction(event_text: String) -> void:
	_update_feedback_text(event_text)
	if entity_visual_layer != null and selected_entity_id != &"" and entity_visual_layer.npc_visuals.has(selected_entity_id):
		_pause_npc_for_feedback(selected_entity_id)
		entity_visual_layer.npc_visuals[selected_entity_id].show_bubble(event_text)


func generate_daily_todo_hotkey_placeholder() -> void:
	request_daily_todos_for_all_npcs()


func export_npc_context_debug_dump() -> Dictionary:
	if entity_registry == null:
		_update_feedback_text(_ui_message("contextExportFailed", {}, "NPC context export failed"))
		return {"ok": false, "reason": "missing_entity_registry"}
	npc_context_debug_exporter = NPCContextDebugExporterScript.new()
	npc_context_debug_exporter.configure({
		"entity_registry": entity_registry,
		"place_registry": place_registry,
		"pathfinder": pathfinder,
		"event_log": event_log,
		"daily_todo_planner": daily_todo_planner,
		"npc_feedback_builder": npc_feedback_builder,
		"gameplay_config": gameplay_config,
		"tick": tick,
		"output_dir": "res://debug",
	})
	var result: Dictionary = npc_context_debug_exporter.export_all()
	if bool(result.get("ok", false)):
		_update_feedback_text(_ui_message("contextExported", {"path": str(result.get("latest_markdown_path", ""))}, "NPC context exported: {path}"))
	else:
		_update_feedback_text(_ui_message("contextExportFailed", {}, "NPC context export failed"))
	return result


## 按 T：对每个 NPC 发起真实 daily todo 规划。
## 流程: planner.request_daily_todos -> transport (HTTPRequest) -> LLMClient generation 守卫
##        -> validate_todos -> on_done 把校验后的 todos 写进 npc.todo_list。
## 无 key (llm_config.enabled==false): transport 立即回 llm_disabled，planner 回退到 wander，
##        on_done 仍 ok=true 带一个 wander todo；UI 提示 "LLM disabled / fallback"。
func request_daily_todos_for_all_npcs() -> void:
	if daily_todo_planner == null or llm_transport == null or llm_client == null:
		_update_feedback_text(_ui_message("llmServicesMissing"))
		return

	var llm_enabled := llm_config != null and bool(llm_config.enabled)
	if llm_enabled:
		_update_feedback_text(_ui_message("requestDailyTodos"))
	else:
		_update_feedback_text(_ui_message("llmDisabledFallback"))

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
			_update_feedback_text(_ui_message("dailyPlanSuperseded", {"npc_id": npc_id}))
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
		_update_feedback_text(_ui_message("dailyTodosReady", {"npc_id": npc_id, "count": str((todos as Array).size())}))
	else:
		_update_feedback_text(_ui_message("dailyFallbackReady", {"npc_id": npc_id}))


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
	_ensure_npc_execution_loop()
	if npc_execution_loop != null:
		npc_execution_loop.tick(tick)


func _decide_one_npc(npc) -> void:
	_ensure_npc_execution_loop()
	if npc_execution_loop != null:
		npc_execution_loop.decide_one_npc(npc, tick)


func _maybe_create_emergent_todo(npc):
	_ensure_npc_execution_loop()
	if npc_execution_loop != null:
		return npc_execution_loop._maybe_create_emergent_todo(npc, tick)
	return null


func _sync_npc_execution_visual(npc, bubble_text: String) -> void:
	if entity_visual_layer == null:
		return
	entity_visual_layer.sync_from_registry(entity_registry)
	if npc != null and entity_visual_layer.npc_visuals.has(npc.id):
		entity_visual_layer.npc_visuals[npc.id].show_bubble(bubble_text)


func _ensure_npc_execution_loop() -> void:
	if npc_execution_loop != null:
		return
	npc_execution_loop = NPCExecutionLoopScript.new()
	npc_execution_loop.configure({
		"entity_registry": entity_registry,
		"place_registry": place_registry,
		"pathfinder": pathfinder,
		"event_log": event_log,
		"todo_executor": todo_executor,
		"action_scheduler": action_scheduler,
		"relationship_decision_service": relationship_decision_service,
		"story_arc_registry": story_arc_registry,
		"gameplay_config": gameplay_config,
		"npc_movers": npc_movers,
		"paused_checker": Callable(self, "_is_npc_feedback_paused"),
		"event_rememberer": Callable(self, "_remember_event_for_npcs"),
		"visual_syncer": Callable(self, "_sync_npc_execution_visual"),
	})


## advance_npc_movement: ADVANCE 层（_process 每帧调用）。把每个非 idle 的 NPC 沿 waypoints
## 连续推进一步；到达目标或进入交互半径时 → todo.status=done + 记录完成事件 + 释放 movement lane。
func advance_npc_movement(delta: float) -> void:
	_ensure_npc_execution_loop()
	if npc_execution_loop != null:
		npc_execution_loop.advance(delta, tick)


func _complete_active_todo(npc, mover) -> void:
	_ensure_npc_execution_loop()
	if npc_execution_loop != null:
		npc_execution_loop._complete_active_todo(npc, mover, tick)


func _record_npc_todo_experience(npc, todo, event_type: StringName, reason: StringName, success: bool):
	_ensure_npc_execution_loop()
	return npc_execution_loop.record_npc_todo_experience(npc, todo, event_type, reason, success, tick) if npc_execution_loop != null else null


func _npc_todo_event_type(todo) -> StringName:
	_ensure_npc_execution_loop()
	return npc_execution_loop.npc_todo_event_type(todo) if npc_execution_loop != null else &"npc_completed_todo"


func _todo_target_id(todo) -> StringName:
	_ensure_npc_execution_loop()
	return npc_execution_loop.todo_target_id(todo) if npc_execution_loop != null else &""


func _todo_target_type(todo) -> StringName:
	_ensure_npc_execution_loop()
	return npc_execution_loop.todo_target_type(todo) if npc_execution_loop != null else &"cell"


## 取该 NPC todo_list 中优先级最高的 pending todo。
func _next_pending_todo(npc):
	_ensure_npc_execution_loop()
	return npc_execution_loop._next_pending_todo(npc) if npc_execution_loop != null else null


## 懒创建并缓存每个 NPC 的 NPCMover（持各自路径状态）。
func _mover_for(npc):
	_ensure_npc_execution_loop()
	return npc_execution_loop._mover_for(npc) if npc_execution_loop != null else null


func save_game_state() -> void:
	saved_snapshot = {
		"entities": entity_registry.to_dict(),
		"places": place_registry.to_dict(),
		"pathfinder": pathfinder.to_dict(),
		"events": event_log.to_dict(),
		"story_arcs": story_arc_registry.to_dict() if story_arc_registry != null else {},
		"selected_entity_id": selected_entity_id,
	}
	_update_feedback_text(_ui_message("saved"))


func load_game_state() -> void:
	if saved_snapshot.is_empty():
		_update_feedback_text(_ui_message("noSaveSnapshot"))
		return
	entity_registry.load_from_dict(saved_snapshot.get("entities", {}))
	place_registry.load_from_dict(saved_snapshot.get("places", {}))
	pathfinder.load_from_dict(saved_snapshot.get("pathfinder", {}))
	event_log.load_from_dict(saved_snapshot.get("events", {}))
	if story_arc_registry != null:
		story_arc_registry.load_from_dict(saved_snapshot.get("story_arcs", {}))
	selected_entity_id = StringName(saved_snapshot.get("selected_entity_id", ""))
	fenced_area_overlay.refresh_from_registry()
	_update_feedback_text(_ui_message("loaded"))


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
	if entity_visual_layer != null and entity_visual_layer.has_method("configure_wellbeing"):
		entity_visual_layer.configure_wellbeing(wellbeing_config)


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


func _load_runtime_configs() -> void:
	gameplay_config = ConfigLoaderScript.load_gameplay_config()
	wellbeing_config = ConfigLoaderScript.load_wellbeing_config()


func _world_background_path() -> String:
	var world_cfg: Dictionary = gameplay_config.get("world", {})
	return str(world_cfg.get("backgroundPath", ""))


func _ui_message(key: String, values: Dictionary = {}, fallback: String = "") -> String:
	var messages: Dictionary = gameplay_config.get("ui", {}).get("messages", {})
	var template := str(messages.get(key, fallback))
	return _format_template(template, values)


func _controls_text(expanded: bool) -> String:
	var controls: Dictionary = gameplay_config.get("ui", {}).get("controls", {})
	return str(controls.get("expandedText" if expanded else "collapsedText", ""))


func _interaction_template(section: String, key: String, values: Dictionary = {}, fallback: String = "") -> String:
	var templates: Dictionary = _interaction_templates_config()
	var section_cfg: Dictionary = templates.get(section, {})
	return _format_template(str(section_cfg.get(key, fallback)), values)


func _interaction_config(section: String) -> Dictionary:
	var templates: Dictionary = _interaction_templates_config()
	return templates.get(section, {})


func _interaction_templates_config() -> Dictionary:
	var templates: Dictionary = gameplay_config.get("interactionTemplates", {})
	if templates.is_empty():
		var loaded: Dictionary = ConfigLoaderScript.load_gameplay_config()
		templates = loaded.get("interactionTemplates", {})
	return templates


func _template_field(config: Dictionary, key: String, values: Dictionary = {}, fallback: String = "") -> String:
	return _format_template(str(config.get(key, fallback)), values)


func _event_text_template(key: String, values: Dictionary = {}, fallback: String = "") -> String:
	return _interaction_template("eventText", key, values, fallback)


func _format_template(template: String, values: Dictionary) -> String:
	var result := template
	for key in values.keys():
		result = result.replace("{%s}" % str(key), str(values[key]))
	return result


func _array_from(value: Variant) -> Array:
	return value.duplicate(true) if value is Array else []


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

	chat_transfer_parser = ChatTransferParserScript.new()
	chat_transfer_parser.configure(entity_registry, gameplay_config)
	stakeholder_perception_service = StakeholderPerceptionServiceScript.new()
	stakeholder_perception_service.configure(entity_registry, gameplay_config)

	npc_feedback_builder = NPCFeedbackBuilderScript.new()
	npc_feedback_builder.configure(entity_registry, place_registry, pathfinder, event_log, llm_client, llm_transport)

	npc_performance_director = NPCPerformanceDirectorScript.new()
	npc_performance_director.configure(wellbeing_config, llm_client, llm_transport)

	# 执行层：TodoExecutor 消费 todo（瞬移式移动），NPCActionScheduler 管 lane 锁。
	# 每个 NPC 的 NPCMover 按需在 _mover_for 里懒创建（seed 在本方法之后才跑）。
	action_scheduler = NPCActionSchedulerScript.new()
	todo_executor = TodoExecutorScript.new()
	todo_executor.configure(entity_registry, place_registry, pathfinder, event_log)
	npc_auto_drop_service = NPCAutoDropServiceScript.new()
	npc_auto_drop_service.configure(entity_registry, gameplay_config)
	relationship_decision_service = RelationshipDecisionServiceScript.new()
	relationship_decision_service.configure(gameplay_config)
	story_arc_registry = StoryArcRegistryScript.new()
	story_arc_registry.configure(gameplay_config)
	_ensure_npc_execution_loop()


func _seed_sample_npc_item_data() -> void:
	if gameplay_config.is_empty() and wellbeing_config.is_empty():
		_load_runtime_configs()
	if npc_performance_director != null:
		npc_performance_director.configure(wellbeing_config, llm_client, llm_transport)
	if entity_visual_layer != null and entity_visual_layer.has_method("configure_wellbeing"):
		entity_visual_layer.configure_wellbeing(wellbeing_config)
	var loaded_npcs: Dictionary = ConfigLoaderScript.load_npc_configs()
	npc_config_by_id = loaded_npcs.get("by_id", {})
	var npc_configs: Array = loaded_npcs.get("configs", [])

	for cfg in npc_configs:
		if not _config_spawns_in_scene(cfg):
			continue
		var npc = NPCStateScript.from_dict(cfg)
		entity_registry.add_npc(npc)

	var item_bundle: Dictionary = ConfigLoaderScript.load_item_bundle()
	entity_registry.set_object_types(item_bundle.get("objectTypes", {}))
	for item_cfg in item_bundle.get("objects", []):
		if not (item_cfg is Dictionary):
			continue
		if not _config_spawns_in_scene(item_cfg):
			continue
		var item = ItemStateScript.from_dict(item_cfg, entity_registry.object_types)
		entity_registry.add_item(item)
	entity_registry.repair_inventory_links()
	_seed_places_from_gameplay()
	_seed_initial_todos_from_intentions()


func _config_spawns_in_scene(config: Dictionary) -> bool:
	if bool(config.get("disabled", false)):
		return false
	var spawn: Variant = config.get("spawn", {})
	if spawn is Dictionary and spawn.has("enabled"):
		return bool(spawn.get("enabled", true))
	if config.has("spawnEnabled"):
		return bool(config.get("spawnEnabled", true))
	if config.has("enabled"):
		return bool(config.get("enabled", true))
	return true


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
	var default_todo: Dictionary = free_roam.get("defaultTodo", {})
	for npc in entity_registry.npcs.values():
		var npc_intentions: Array = intentions.get(str(npc.id), [])
		if npc_intentions.is_empty():
			npc.todo_list = [_default_seed_todo(npc, default_todo)]
			continue
		var intention: Dictionary = npc_intentions[0]
		var locations: Array = intention.get("locations", [])
		var location_id := str(locations[0].get("location", "")) if not locations.is_empty() and locations[0] is Dictionary else ""
		npc.todo_list = [TodoItemScript.from_dict({
		"id": "todo_%s_%s" % [str(npc.id), str(intention.get("id", "seed"))],
		"intent": "visit_place",
		"target_place_id": location_id,
		"reason": str(intention.get("label", default_todo.get("reasonTemplate", ""))),
		"priority": 50,
		"status": "pending",
	})]
	assign_daily_wellbeing_problem()


func _default_seed_todo(npc, config: Dictionary):
	var values := {
		"npc_id": str(npc.id),
		"npc_name": str(npc.name),
	}
	return TodoItemScript.from_dict({
		"id": _format_template(str(config.get("idTemplate", "todo_{npc_id}_seed")), values),
		"intent": str(config.get("intent", "wander")),
		"reason": _format_template(str(config.get("reasonTemplate", "")), values),
		"priority": int(config.get("priority", 10)),
		"status": str(config.get("status", "pending")),
	})


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

	npc_chat_panel = ui_layer.get_node_or_null("NPCChatPanel")
	if npc_chat_panel != null:
		if npc_chat_panel.has_method("configure_npcs"):
			npc_chat_panel.configure_npcs(entity_registry.npcs, selected_entity_id)
		if npc_chat_panel.has_signal("message_submitted"):
			npc_chat_panel.message_submitted.connect(submit_npc_chat_message)


func _update_feedback_text(message: String) -> void:
	if feedback_label != null:
		feedback_label.text = message


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size + cell_size * 0.5, cell.y * cell_size + cell_size * 0.5)
