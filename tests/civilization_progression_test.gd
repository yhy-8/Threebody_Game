extends Node
## 文明目标、事件抉择、区域修复/补员与新存档段的回归测试。

const ObjectivesScript = preload("res://scripts/simulation/civilization_objectives.gd")

var _failures: int = 0


func _ready() -> void:
	GameState.set_process(false)
	_test_objective_evaluation()
	_test_event_trigger_and_resolution()
	_test_zone_operations()
	_test_save_roundtrip()
	if _failures == 0:
		print("CIVILIZATION_PROGRESSION_TEST_OK")
	GameState.reset()
	get_tree().quit(_failures)


func _test_objective_evaluation() -> void:
	var objectives = ObjectivesScript.new()
	var context := {
		"food_stock": 500.0, "food_net": 2.0, "food_days": 250.0,
		"has_food_production": true, "population": 110, "teaching_plan_count": 0,
		"knowledge_advanced": 4, "power_generation": 0.0,
		"capabilities": {}, "shelter_capacity": 0,
		"chaos_started": false, "days_since_chaos": 0.0,
	}
	objectives.food_security_streak = 5.0
	var current: Dictionary = objectives.get_current_view(context, 10.0)
	_expect(str(current.get("id", "")) == "food_security", "首个文明目标不是食物安全")
	_expect(bool(current.get("complete", false)), "满足食物条件后目标没有完成")
	var completed: Array = objectives.update(context, 10.0)
	_expect("food_security" in completed, "目标完成没有写入完成记录")
	var after: Dictionary = objectives.get_current_view(context, 11.0)
	_expect(str(after.get("id", "")) == "first_lesson", "完成食物目标后没有推进到下一目标")
	var industrial_context := context.duplicate(true)
	industrial_context["power_generation"] = 8.0
	industrial_context["capabilities"] = {"laboratory": true}
	industrial_context["knowledge_advanced"] = 9
	var industrial: Array = objectives.get_all_views(industrial_context, 12.0)
	var industrial_view: Dictionary = {}
	for value in industrial:
		var view: Dictionary = value
		if str(view.get("id", "")) == "industrial_base":
			industrial_view = view
	_expect(bool(industrial_view.get("complete", false)), "电力与实验室条件满足时工业目标未完成")
	_expect(str(objectives.get_era(industrial_context).get("id", "")) == "industry", "文明纪元没有随工业条件推进")
	var state: Dictionary = objectives.get_state()
	var restored = ObjectivesScript.new()
	_expect(restored.load_state(state), "文明目标状态无法载入")
	_expect(restored.completed_ids == objectives.completed_ids, "文明目标完成记录往返不一致")


func _test_event_trigger_and_resolution() -> void:
	var started := GameState.new_game("事件测试宇宙")
	_expect(started, "无法创建事件测试局")
	var capital := int(GameState.settlement_system.candidate_views[0].get("zone_id", 0))
	GameState.confirm_capital(capital)
	var context: Dictionary = GameState.get_civilization_context()
	context["min_populated_temperature"] = 20.0
	context["food_days"] = 30.0
	context["population"] = 100
	context["knowledge_advanced"] = 4
	context["teaching_plan_count"] = 0
	context["damaged_building_count"] = 0
	context["power_shortage"] = false
	var triggered: bool = GameState.civilization_events.evaluate(context, 10.0)
	_expect(triggered, "满足条件时没有触发社会抉择")
	var pending: Dictionary = GameState.get_pending_civilization_event()
	_expect(not pending.is_empty(), "事件触发后没有待决事件")
	_expect(str(pending.get("event_id", "")) == "night_sky", "首个事件不是夜空观测")
	var food_before: float = GameState.entities.get_resource("food")
	var result: Dictionary = GameState.resolve_civilization_event("record_sky")
	_expect(result.get("success", false), "事件选项执行失败：%s" % result.get("message", ""))
	_expect(GameState.entities.get_resource("food") < food_before, "事件选项没有扣除真实食物")
	_expect(GameState.get_pending_civilization_event().is_empty(), "事件解决后仍停留在待决状态")
	_expect("night_sky" in GameState.civilization_events.triggered_ids, "事件完成记录没有保存")

	var civic_context := context.duplicate(true)
	civic_context["game_day"] = 31.0
	civic_context["teaching_plan_count"] = 1
	civic_context["population"] = 100
	civic_context["food_stock"] = 100.0
	civic_context["food_days"] = 20.0
	_expect(GameState.civilization_events.evaluate(civic_context, 31.0), "公共工程事件没有按天数触发")
	var civic_pending: Dictionary = GameState.get_pending_civilization_event()
	_expect(str(civic_pending.get("event_id", "")) == "civic_works", "第 31 天触发的不是可重复公共工程事件")
	var civic_result: Dictionary = GameState.resolve_civilization_event("keep_working")
	_expect(civic_result.get("success", false), "公共工程事件无法解决")
	_expect(not GameState.civilization_events.evaluate(civic_context, 40.0), "可重复事件在冷却期内再次触发")
	_expect(GameState.civilization_events.evaluate(civic_context, 80.0), "可重复事件冷却结束后没有再次触发")


func _test_zone_operations() -> void:
	var capital := int(GameState.settlement_system.capital_zone_id)
	var build: Dictionary = GameState.execute_regional_construction("build_algae_foraging", capital)
	_expect(build.get("success", false), "测试营地建造失败")
	var buildings: Array = GameState.entities.get_buildings_in_zone(capital)
	_expect(not buildings.is_empty(), "测试区域没有建筑")
	var building = buildings[0]
	var auto_result: Dictionary = GameState.auto_assign_zone_workers(capital)
	_expect(auto_result.get("success", false), "一键补员失败")
	_expect(building.assigned_workers == building.worker_capacity, "一键补员没有填满岗位")
	building.under_construction = false
	building.durability = 40.0
	var iron_before: float = GameState.entities.get_resource("iron")
	var repair: Dictionary = GameState.repair_regional_building(building.id)
	_expect(repair.get("success", false), "设施修复失败：%s" % repair.get("message", ""))
	_expect(is_equal_approx(float(building.durability), float(building.max_durability)), "修复后耐久没有恢复")
	_expect(GameState.entities.get_resource("iron") < iron_before, "修复没有消耗真实铁材")
	var solar_decision = GameState.decision_manager.available_decisions.get("build_solar_array")
	_expect(solar_decision != null, "建筑目录缺少太阳能阵列")
	var fusion_decision = GameState.decision_manager.available_decisions.get("build_fusion_reactor")
	_expect(fusion_decision != null and fusion_decision.tech_requirement == "nuclear_fusion", "聚变反应堆没有接入终局科技")


func _test_save_roundtrip() -> void:
	GameState.civilization_objectives.completed_ids.assign(["food_security"])
	GameState.civilization_objectives.completion_days["food_security"] = 3.5
	GameState.civilization_objectives.food_security_streak = 7.5
	var data: Dictionary = GameState.to_dict()
	_expect(GameState.validate_serialized_state(data), "新存档段没有通过严格校验")
	var universe: String = GameState.universe_name
	var loaded: bool = GameState.from_dict(data)
	_expect(loaded, "新存档段无法读档")
	_expect(GameState.universe_name == universe, "读档后宇宙名不一致")
	_expect("food_security" in GameState.civilization_objectives.completed_ids, "文明目标完成记录未能随存档恢复")
	_expect(
		is_equal_approx(GameState.civilization_objectives.food_security_streak, 7.5),
		"连续食物盈余进度未能随存档恢复",
	)
	_expect(GameState.civilization_events != null, "事件系统没有随存档恢复")
	_expect("night_sky" in GameState.civilization_events.triggered_ids, "事件触发记录未能随存档恢复")


func _expect(p_condition: bool, p_message: String) -> void:
	if p_condition:
		return
	_failures += 1
	push_error(p_message)
