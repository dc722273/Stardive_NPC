extends SceneTree
const PASS_MARKER := "SET_POSITION_ORACLE: PASS"
const FAIL_MARKER := "SET_POSITION_ORACLE: FAIL"
const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const ConstantsScript := preload("res://scripts/core/Constants.gd")
var failures: Array = []
func _initialize() -> void:
	_run()
	_finish()
func _run() -> void:
	var reg = WorldEntityRegistryScript.new()
	reg.set_map_bounds(Rect2i(0, 0, 24, 16))
	reg.add_npc(NPCStateScript.from_dict({"id": "npc_a", "position": {"x": 48.0, "y": 48.0}}))
	reg.add_npc(NPCStateScript.from_dict({"id": "npc_b", "position": {"x": 200.0, "y": 48.0}}))
	var ok = reg.set_entity_position(StringName("npc_a"), Vector2(100, 60))
	_assert_true(ok, "set_entity_position returns true")
	var a = reg.npcs[StringName("npc_a")]
	_assert_true(a.position == Vector2(100, 60), "npc_a position written")
	_assert_true(a.current_cell == ConstantsScript.world_to_cell(Vector2(100, 60)), "npc_a current_cell derived")
	var ok2 = reg.set_entity_position(StringName("npc_b"), Vector2(100, 60))
	_assert_true(ok2, "overlap allowed (no occupancy rejection)")
	_assert_true(reg.npcs[StringName("npc_b")].position == Vector2(100, 60), "npc_b at same pos as npc_a")
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
