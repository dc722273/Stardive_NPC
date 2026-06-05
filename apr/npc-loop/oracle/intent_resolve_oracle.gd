extends SceneTree
const PASS_MARKER := "INTENT_RESOLVE_ORACLE: PASS"
const FAIL_MARKER := "INTENT_RESOLVE_ORACLE: FAIL"
const TodoExecutorScript := preload("res://scripts/npc/TodoExecutor.gd")
const GridPathfinderScript := preload("res://scripts/world/GridPathfinder.gd")
const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const ItemStateScript := preload("res://scripts/state/ItemState.gd")
const TodoItemScript := preload("res://scripts/state/TodoItem.gd")
const ConstantsScript := preload("res://scripts/core/Constants.gd")
var failures: Array = []
func _initialize() -> void:
	_run()
	_finish()
func _run() -> void:
	var pathfinder = GridPathfinderScript.new()
	pathfinder.set_map_bounds(Rect2i(0, 0, 24, 16))
	var registry = WorldEntityRegistryScript.new()
	registry.set_map_bounds(Rect2i(0, 0, 24, 16))
	var npc = NPCStateScript.from_dict({"id": "npc_a", "position": {"x": 48.0, "y": 48.0}})
	registry.add_npc(npc)
	var item = ItemStateScript.from_dict({"id": "it_a", "position": {"x": 240.0, "y": 240.0}})
	registry.add_item(item)
	var executor = TodoExecutorScript.new()
	executor.configure(registry, null, pathfinder, null)
	var ctx := {"entity_registry": registry, "place_registry": null, "pathfinder": pathfinder, "event_log": null, "mover": null}
	var rest_todo = TodoItemScript.from_dict({"id": "t_rest", "intent": "rest", "status": "pending"})
	var rest = executor._target_world_pos(rest_todo, ctx, npc)
	_assert_true(bool(rest.get("ok", false)), "rest resolves ok")
	_assert_true(rest.get("world_pos") == npc.position, "rest target is npc current position")
	var insp_todo = TodoItemScript.from_dict({"id": "t_insp", "intent": "inspect_item", "target_item_id": "it_a", "status": "pending"})
	var insp = executor._target_world_pos(insp_todo, ctx, npc)
	_assert_true(bool(insp.get("ok", false)), "inspect resolves ok")
	_assert_true(insp.get("interact_target") == item.position, "inspect interact_target is item position")
	var wan_todo = TodoItemScript.from_dict({"id": "t_wan", "intent": "wander", "status": "pending"})
	var wan = executor._target_world_pos(wan_todo, ctx, npc)
	_assert_true(bool(wan.get("ok", false)), "wander resolves ok")
	var wan_pos: Vector2 = wan.get("world_pos")
	var wan_cell := ConstantsScript.world_to_cell(wan_pos)
	_assert_true(wan_cell != npc.current_cell, "wander target cell differs from current, got %s" % str(wan_cell))
	# wander 应走「更大范围」：目标必须远于 INTERACT_RADIUS，否则到达判定会让 NPC 一步不走就 dwell。
	_assert_true(wan_pos.distance_to(npc.position) > ConstantsScript.INTERACT_RADIUS,
		"wander target is farther than INTERACT_RADIUS (dist=%.1f > %.1f)" % [wan_pos.distance_to(npc.position), ConstantsScript.INTERACT_RADIUS])
	# 到达语义：wander/rest 是「走到坐标」，需精确到点 → arrival_radius 应远小于 INTERACT_RADIUS。
	_assert_true(wan.has("arrival_radius"), "wander resolved dict carries arrival_radius")
	_assert_true(float(wan.get("arrival_radius", 999.0)) < ConstantsScript.INTERACT_RADIUS,
		"wander arrival_radius is precise/small (%.1f < %.1f)" % [float(wan.get("arrival_radius", 999.0)), ConstantsScript.INTERACT_RADIUS])
	# rest 同为「走到坐标」语义（原地），arrival_radius 也应是精确小值。
	_assert_true(float(rest.get("arrival_radius", 999.0)) < ConstantsScript.INTERACT_RADIUS,
		"rest arrival_radius is precise/small (%.1f < %.1f)" % [float(rest.get("arrival_radius", 999.0)), ConstantsScript.INTERACT_RADIUS])
	# inspect 是「靠近交互对象」语义，arrival_radius 应为 INTERACT_RADIUS。
	_assert_true(float(insp.get("arrival_radius", 0.0)) == ConstantsScript.INTERACT_RADIUS,
		"inspect arrival_radius equals INTERACT_RADIUS (%.1f)" % float(insp.get("arrival_radius", 0.0)))
func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER); quit(0)
	else:
		print(FAIL_MARKER)
		for f in failures: print("  - %s" % f)
		quit(1)
