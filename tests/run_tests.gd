extends SceneTree

## Godot headless 测试聚合入口。实例化所有 RefCounted 测试 suite，
## 各自 run() -> Array(failures)，汇总后统一打印 GODOT_TESTS: PASS/FAIL。
## 新增 LLM 接线的 deterministic 单测都接进这里，纳入回归门（不再是孤立脚本）。

const TestCoreBehaviorsScript := preload("res://tests/test_core_behaviors.gd")
const TestLLMConfigScript := preload("res://tests/test_llm_config.gd")
const TestLLMTransportScript := preload("res://tests/test_llm_transport.gd")
const TestDailyPlannerLLMScript := preload("res://tests/test_daily_planner_llm.gd")
const TestFeedbackBuilderLLMScript := preload("res://tests/test_feedback_builder_llm.gd")
const TestPlannerQueueLLMScript := preload("res://tests/test_planner_queue_llm.gd")


func _initialize() -> void:
	var suites := {
		"core": TestCoreBehaviorsScript.new(),
		"llm_config": TestLLMConfigScript.new(),
		"llm_transport": TestLLMTransportScript.new(),
		"daily_planner_llm": TestDailyPlannerLLMScript.new(),
		"feedback_builder_llm": TestFeedbackBuilderLLMScript.new(),
		"planner_queue_llm": TestPlannerQueueLLMScript.new(),
	}

	var all_failures: Array = []
	for suite_name in suites.keys():
		var suite = suites[suite_name]
		var result = suite.run()
		if result is Array:
			for failure in result:
				all_failures.append("[%s] %s" % [suite_name, str(failure)])

	if all_failures.is_empty():
		print("GODOT_TESTS: PASS")
		quit(0)
		return

	print("GODOT_TESTS: FAIL")
	for failure in all_failures:
		push_error(str(failure))
	quit(1)
