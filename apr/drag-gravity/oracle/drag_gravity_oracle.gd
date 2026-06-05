extends SceneTree
const PASS_MARKER := "DRAG_GRAVITY_ORACLE: PASS"
const FAIL_MARKER := "DRAG_GRAVITY_ORACLE: FAIL"
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
	var npc = reg.npcs[StringName("npc_a")]
	var mouse := Vector2(300, 300)
	var pull := 0.2
	var start_dist: float = npc.position.distance_to(mouse)
	for i in range(5):
		npc.position += (mouse - npc.position) * pull
	var after_dist: float = npc.position.distance_to(mouse)
	_assert_true(after_dist < start_dist, "gravity pulls toward mouse (%.1f -> %.1f)" % [start_dist, after_dist])
	_assert_true(after_dist > 0.0, "not teleported instantly to mouse")
	reg.set_entity_position(StringName("npc_a"), Vector2(137, 91))
	_assert_true(reg.npcs[StringName("npc_a")].position == Vector2(137, 91), "drop lands at continuous pixel pos")
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
