extends Node
## Regional exposure, real shelter capacity, crisis settlement, extinction, and persistence.

const EntityManagerScript = preload("res://scripts/simulation/entity_manager.gd")

var _failures: int = 0


func _ready() -> void:
	_test_starvation_can_end_civilization()
	var unprotected_loss := _run_exposure_case(false)
	var protected_loss := _run_exposure_case(true)
	_expect(unprotected_loss > 0, "极端环境中的无保护活动人口仍然不会死亡")
	_expect(protected_loss < unprotected_loss, "已运行且配员的庇护所没有降低同场危机伤亡")
	_test_response_lock_single_report_and_persistence()
	_test_forecast_change_event_deduplication()
	_test_game_state_extinction_reason_and_persistence()
	GameState.reset()
	if _failures == 0:
		print("HAZARD_GAMEPLAY_TEST_OK")
	get_tree().quit(_failures)


func _test_starvation_can_end_civilization() -> void:
	var entities = EntityManagerScript.new({
		"initial_entities": {"population": 2, "resources": []},
		"population": {
			"food_per_person_per_day": 1.0,
			"base_growth_per_breeder": 0.0,
			"natural_growth_rate": 0.0,
			"starvation_threshold": 1.0,
			"starvation_rate": 1.0,
		},
	})
	entities.resources["food"].amount = 0.0
	entities.update({"heat_level": 0.5}, null, 1.0, false)
	_expect(entities.population.total == 0, "饥饿结算仍强制保留最后一名人口")


func _run_exposure_case(p_with_shelter: bool) -> int:
	_prepare_game("__区域暴露测试")
	var capital_id: int = GameState.settlement_system.capital_zone_id
	var zone = GameState.planet_zones.get_zone(capital_id)
	zone.temperature = -180.0
	zone.radiation = 0.0
	if p_with_shelter:
		var shelter = EntityManagerScript.GameBuilding.new(
			9001, "测试深地庇护所", "deep_shelter", capital_id,
			8, {}, {"electricity": 3.0}, 0.0, 0.0, false, true,
			100.0, 100.0, 100
		)
		shelter.assigned_workers = 8
		shelter.last_run_ratio = 1.0
		GameState.entities.add_building(shelter)
		GameState.planet_zones.add_building_to_zone(capital_id, shelter.id)
		var committed: Dictionary = GameState.commit_hazard_response("population")
		_expect(committed.get("success", false), "真实运行庇护设施存在时无法确认人口优先预案")
	var before: int = GameState.entities.population.total
	GameState.environmental_hazard_system.process_population_exposure(
		1.0, GameState.planet_zones, GameState.settlement_system, GameState.entities
	)
	return before - GameState.entities.population.total


func _test_response_lock_single_report_and_persistence() -> void:
	_prepare_game("__危机报告测试")
	var capital_id: int = GameState.settlement_system.capital_zone_id
	var shelter = EntityManagerScript.GameBuilding.new(
		9101, "测试庇护所", "shelter", capital_id,
		4, {}, {"electricity": 1.0}, 0.0, 0.0, false, true,
		100.0, 100.0, 20
	)
	shelter.assigned_workers = 4
	shelter.last_run_ratio = 1.0
	GameState.entities.add_building(shelter)
	GameState.planet_zones.add_building_to_zone(capital_id, shelter.id)
	var committed: Dictionary = GameState.commit_hazard_response("balanced")
	_expect(committed.get("success", false), "均衡危机预案无法确认")
	var saved: Dictionary = GameState.to_dict()
	_expect(
		saved.has("environmental_hazards")
		and saved.has("event_log")
		and GameState.from_dict(saved),
		"危机预案与事件日志无法完成严格存档往返",
	)
	_expect(
		GameState.environmental_hazard_system.response_plan.get("priority", "") == "balanced",
		"读档后已承诺危机预案丢失",
	)
	var zone = GameState.planet_zones.get_zone(capital_id)
	zone.temperature = -100.0
	var started: Dictionary = GameState.environmental_hazard_system.begin_step(
		GameState.game_time, 0.5, GameState.planet_zones,
		GameState.settlement_system, GameState.entities
	)
	_expect(started.get("started", false), "达到公开阈值后环境危机没有开始")
	_expect(
		not GameState.commit_hazard_response("population").get("success", false),
		"危机进行中仍可改写已承诺预案",
	)
	var exposure: Dictionary = GameState.environmental_hazard_system.process_population_exposure(
		0.5, GameState.planet_zones, GameState.settlement_system, GameState.entities
	)
	var first_end: Dictionary = GameState.environmental_hazard_system.end_step(
		GameState.game_time + 0.5, 0.5, exposure, 0, 0
	)
	_expect(first_end.is_empty(), "危机尚未进入安静期就提前结算")
	zone.temperature = 20.0
	GameState.environmental_hazard_system.begin_step(
		GameState.game_time + 0.5, 1.0, GameState.planet_zones,
		GameState.settlement_system, GameState.entities
	)
	var report: Dictionary = GameState.environmental_hazard_system.end_step(
		GameState.game_time + 1.5, 1.0, {}, 0, 0
	)
	_expect(not report.is_empty(), "危机结束后没有形成实际结算报告")
	_expect(
		GameState.environmental_hazard_system.end_step(
			GameState.game_time + 2.5, 1.0, {}, 0, 0
		).is_empty(),
		"同一场危机被重复结算",
	)
	_expect(
		GameState.environmental_hazard_system.completed_reports.size() == 1,
		"单次危机没有且仅有一份完成报告",
	)


func _test_forecast_change_event_deduplication() -> void:
	_prepare_game("__预测事件测试")
	var before: int = GameState.event_log.size()
	GameState._record_public_forecast_event({
		"forecast_id": "test:1", "level": 1, "risk_trend": "rising", "confidence": 0.3,
	})
	GameState._record_public_forecast_event({
		"forecast_id": "test:2", "level": 1, "risk_trend": "rising", "confidence": 0.4,
	})
	GameState._record_public_forecast_event({
		"forecast_id": "test:3", "level": 1, "risk_trend": "uncertain", "confidence": 0.4,
	})
	GameState._record_public_forecast_event({
		"forecast_id": "test:4", "level": 1, "risk_trend": "rising", "confidence": 0.5,
	})
	_expect(
		GameState.event_log.size() == before + 3,
		"预测事件没有抑制连续重复，或趋势再次变化时被历史去重错误吞掉",
	)


func _test_game_state_extinction_reason_and_persistence() -> void:
	_prepare_game("__文明失败测试")
	GameState.entities.population.total = 0
	GameState.entities.population.stored_population = 0
	GameState._check_civilization_failure()
	_expect(GameState.game_over and GameState.paused, "人口归零后游戏没有进入暂停的文明终结状态")
	_expect(
		GameState.game_over_reason.contains("全部活动与脱水人口"),
		"文明终结界面没有保留可解释的真实失败原因",
	)
	_expect(
		not GameState.event_log.is_empty()
		and GameState.event_log[-1].get("title", "") == "文明终结",
		"文明终结没有进入持久事件记录",
	)
	var saved: Dictionary = GameState.to_dict()
	_expect(
		GameState.from_dict(saved)
		and GameState.game_over
		and GameState.game_over_reason.contains("全部活动与脱水人口"),
		"文明终结状态与原因无法完成严格存档往返",
	)


func _prepare_game(p_name: String) -> void:
	GameState.reset()
	_expect(GameState.new_game(p_name), "无法创建危机测试宇宙")
	var capital_id := int(GameState.settlement_system.candidate_views[0].get("zone_id", -1))
	_expect(GameState.confirm_capital(capital_id).get("success", false), "无法确认危机测试首都")
	GameState.paused = true


func _expect(p_condition: bool, p_message: String) -> void:
	if p_condition:
		return
	_failures += 1
	push_error(p_message)
