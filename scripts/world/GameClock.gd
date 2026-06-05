extends RefCounted
class_name GameClock

const SECONDS_PER_DAY := 120.0   # 2 分钟现实时间 = 一游戏天
const MORNING_THRESHOLD := 0.0    # 一天起点即"早上"

var day: int = 1
var time_of_day: float = 0.0      # 0..1
var _elapsed: float = 0.0
var _morning_pending: bool = true # 启动即有一个早上事件待消费
var _last_day_for_morning: int = 0


func advance(delta: float) -> void:
	_elapsed += delta
	var new_day: int = 1 + int(_elapsed / SECONDS_PER_DAY)
	time_of_day = fmod(_elapsed, SECONDS_PER_DAY) / SECONDS_PER_DAY
	if new_day != day:
		day = new_day
		_morning_pending = true


func consume_morning_event() -> bool:
	if _morning_pending and _last_day_for_morning != day:
		_morning_pending = false
		_last_day_for_morning = day
		return true
	# 启动首日特例：_last_day_for_morning 初始 0 != day(1) 时第一次也命中上面分支。
	return false


func time_label() -> String:
	var minutes_total: int = int(time_of_day * 24.0 * 60.0)
	var hh: int = minutes_total / 60
	var mm: int = minutes_total % 60
	return "Day %d · %02d:%02d" % [day, hh, mm]
