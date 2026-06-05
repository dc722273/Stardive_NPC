extends SceneTree

const PASS_MARKER := "SELECTION_BOX_ORACLE: PASS"
const FAIL_MARKER := "SELECTION_BOX_ORACLE: FAIL"

const OverlayScript := preload("res://scripts/ui/GridSelectionOverlay.gd")

var failures: Array = []


func _initialize() -> void:
	_run()
	_finish()


func _run() -> void:
	var overlay = OverlayScript.new()
	# overlay 必须有 build_mode 标志，默认 false（非建造）。
	_assert_true("build_mode" in overlay, "overlay has build_mode flag")
	_assert_true(overlay.build_mode == false, "build_mode defaults to false")
	# 释放未入树的 CanvasItem，避免退出时 leak warning / "resources still in use"。
	overlay.free()


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER)
		quit(0)
	else:
		print(FAIL_MARKER)
		for f in failures:
			print("  - %s" % f)
		quit(1)
