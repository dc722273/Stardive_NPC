extends SceneTree

const PASS_MARKER := "GAME_CLOCK_ORACLE: PASS"
const FAIL_MARKER := "GAME_CLOCK_ORACLE: FAIL"

const GameClockScript := preload("res://scripts/world/GameClock.gd")

var failures: Array = []


func _initialize() -> void:
	_run()
	_finish()


func _run() -> void:
	var clock = GameClockScript.new()
	# 第 0 帧：第一个早上事件应可被消费一次。
	clock.advance(0.0)
	_assert_true(clock.consume_morning_event(), "first morning event fires")
	_assert_true(not clock.consume_morning_event(), "morning event consumed once (edge-triggered)")
	_assert_true(clock.day == 1, "starts at day 1, got %d" % clock.day)
	# 推进一整天：进入第 2 天，新早上事件。
	clock.advance(clock.SECONDS_PER_DAY)
	_assert_true(clock.day == 2, "advances to day 2, got %d" % clock.day)
	_assert_true(clock.consume_morning_event(), "morning event fires on new day")
	# time_of_day 在 [0,1)。
	_assert_true(clock.time_of_day >= 0.0 and clock.time_of_day < 1.0, "time_of_day in [0,1), got %.2f" % clock.time_of_day)


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
