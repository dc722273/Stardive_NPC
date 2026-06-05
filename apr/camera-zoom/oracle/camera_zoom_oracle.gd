extends SceneTree

const PASS_MARKER := "CAMERA_ZOOM_ORACLE: PASS"
const FAIL_MARKER := "CAMERA_ZOOM_ORACLE: FAIL"

const MainGameScript := preload("res://scripts/MainGame.gd")

var failures: Array = []


func _initialize() -> void:
	_run()
	await _async()


func _async() -> void:
	await process_frame
	_finish()


func _run() -> void:
	var main = MainGameScript.new()
	get_root().add_child(main)
	_assert_true(main.has_method("apply_zoom"), "MainGame has apply_zoom")


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
