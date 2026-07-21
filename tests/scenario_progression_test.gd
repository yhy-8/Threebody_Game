extends Node
## 难度配置、稳定星历切换、存档迁移与文明预测信息边界回归。

const DifficultyConfigScript = preload("res://resources/configs/scenario_difficulty_config.gd")
const DifficultyPresetScript = preload("res://resources/configs/difficulty_preset.gd")
const ForecastScript = preload("res://scripts/simulation/hazard_forecast_service.gd")
const ObservationScript = preload("res://scripts/simulation/observation_network.gd")
const SatelliteScript = preload("res://scripts/simulation/satellite_network.gd")
const StableEphemerisScript = preload("res://scripts/simulation/stable_ephemeris_provider.gd")

var _failures := 0
var _transition_count := 0


func _ready() -> void:
	_test_difficulty_config()
	_test_stable_transition_and_persistence()
	_test_extreme_and_legacy()
	_test_public_forecast_boundary()
	if _failures == 0:
		print("SCENARIO_PROGRESSION_TEST_OK")
	get_tree().quit(_failures)


func _test_difficulty_config() -> void:
	var config = load("res://resources/configs/scenario_difficulties.tres")
	_expect(config != null and config.validate().is_empty(), "默认难度配置无法加载或校验失败")
	_expect(config.get_selectable_presets().size() == 4, "标准难度没有完全由配置生成")
	for preset in config.get_selectable_presets():
		if preset.stable_years <= 0.0:
			continue
		var provider = StableEphemerisScript.new()
		provider.create(24680, preset.stable_years * config.days_per_year)
		_expect(provider.validate_stable_window().is_empty(), "%s 难度的稳定期存在提前碰撞" % preset.display_name)
	var custom_ok: Dictionary = config.create_snapshot(&"custom", 12.5)
	_expect(custom_ok.get("success", false), "合法自定义年数被拒绝")
	_expect(is_equal_approx(custom_ok.get("snapshot", {}).get("chaos_start_day", -1.0), 12.5 * config.days_per_year), "自定义混沌日换算错误")
	_expect(not config.create_snapshot(&"custom", -1.0).get("success", false), "负自定义年数未被拒绝")
	_expect(not config.create_snapshot(&"custom", config.custom_max_years + 1.0).get("success", false), "超上限自定义年数未被拒绝")

	var duplicate_config = DifficultyConfigScript.new()
	var first = DifficultyPresetScript.new()
	first.id = &"same"
	first.display_name = "一"
	first.stable_years = 1.0
	var second = DifficultyPresetScript.new()
	second.id = &"same"
	second.display_name = "二"
	second.stable_years = 2.0
	duplicate_config.default_preset_id = &"missing"
	var invalid_presets: Array[Resource] = [first, second]
	duplicate_config.presets = invalid_presets
	var errors: PackedStringArray = duplicate_config.validate()
	_expect(errors.size() >= 2, "重复 ID 或缺失默认项未被配置校验捕获")


func _test_stable_transition_and_persistence() -> void:
	var config = load("res://resources/configs/scenario_difficulties.tres")
	var result: Dictionary = config.create_snapshot(&"custom", 0.01)
	var snapshot: Dictionary = result["snapshot"]
	snapshot["scenario_seed"] = "424242"
	_expect(GameState.new_game("__稳定转换", {}, snapshot), "稳定场景创建失败")
	_expect(GameState.scenario_manager.simulation_phase == "STABLE_EPHEMERIS", "非零稳定期没有进入规定星历")
	_expect(GameState.scenario_manager.ephemeris.validate_stable_window().is_empty(), "稳定窗口存在提前碰撞")
	GameState.game_time = 1.25
	GameState.scenario_manager.update(0.0, 1.25)
	var stable_positions := _positions()
	var stable_save: Dictionary = GameState.to_dict()
	_expect(GameState.from_dict(stable_save), "稳定纪元存档无法读取")
	_expect(GameState.scenario_manager.simulation_phase == "STABLE_EPHEMERIS" and _positions_close(stable_positions, _positions()), "稳定纪元读取后阶段或星历不一致")
	GameState.scenario_phase_changed.connect(_on_transition, CONNECT_ONE_SHOT)
	var transition_day: float = GameState.scenario_manager.chaos_start_day
	var expected: Array = GameState.scenario_manager.ephemeris.snapshot_at(transition_day)
	GameState.game_time = transition_day - GameState.FIXED_SIMULATION_STEP_DAYS
	GameState._advance_simulation(GameState.FIXED_SIMULATION_STEP_DAYS)
	_expect(GameState.scenario_manager.simulation_phase == "CHAOTIC_NBODY" and _transition_count == 1, "到期没有且仅有一次切换事件")
	for index in expected.size():
		_expect(GameState.environment.stars[index].position.distance_to(expected[index]["position"]) < 1e-8, "转换帧位置不连续")
		_expect(GameState.environment.stars[index].velocity.distance_to(expected[index]["velocity"]) < 1e-8, "转换帧速度不连续")

	var saved: Dictionary = GameState.to_dict()
	var saved_scenario: Dictionary = saved["scenario"].duplicate(true)
	var original_custom_max: float = config.custom_max_years
	config.custom_max_years = original_custom_max + 100.0
	_expect(GameState.from_dict(saved), "场景状态保存后无法读取")
	_expect(GameState.scenario_manager.get_state() == saved_scenario, "难度快照或转换状态没有完整恢复")
	_expect(is_equal_approx(GameState.scenario_manager.stable_years, 0.01), "项目难度配置修改覆盖了已有存档快照")
	config.custom_max_years = original_custom_max
	_expect(GameState.observation_network != null and GameState.satellite_network != null and GameState.hazard_forecast_service != null, "观测或预测状态没有随存档恢复")


func _test_extreme_and_legacy() -> void:
	var config = load("res://resources/configs/scenario_difficulties.tres")
	var result: Dictionary = config.create_snapshot(&"extreme")
	var snapshot: Dictionary = result["snapshot"]
	snapshot["scenario_seed"] = "998877"
	_expect(GameState.new_game("__极限一", {}, snapshot), "极限场景创建失败")
	var first_positions := _positions()
	_expect(GameState.scenario_manager.simulation_phase == "CHAOTIC_NBODY" and GameState.scenario_manager.chaos_started, "极限难度未从第 0 天进入 N 体模拟")
	_expect(GameState.new_game("__极限二", {}, snapshot), "同种子极限场景重建失败")
	_expect(_positions_close(first_positions, _positions()), "相同场景种子没有生成相同初态")

	var legacy: Dictionary = GameState.to_dict()
	var legacy_positions := _positions()
	legacy.erase("scenario")
	legacy.erase("observation_network")
	legacy.erase("satellite_network")
	legacy.erase("hazard_forecasts")
	legacy["schema_version"] = 2
	_expect(GameState.from_dict(legacy), "旧存档迁移失败")
	_expect(GameState.scenario_manager.difficulty_id == "legacy" and GameState.scenario_manager.simulation_phase == "CHAOTIC_NBODY", "旧存档被错误补发稳定纪元")
	_expect(_positions_close(legacy_positions, _positions()), "旧存档天体状态在迁移时被重置")


func _test_public_forecast_boundary() -> void:
	var observation = ObservationScript.new()
	observation.baseline_days = 120.0
	observation.data_quality = 0.8
	observation.calibration = 0.8
	observation.station_count = 1
	observation.data_version = 7
	observation.latest_public_measurement = {"radiation": 3.0, "stability": 0.4, "possible_zone_ids": [1, 2]}
	var satellites = SatelliteScript.new()
	_expect(satellites.deploy_satellite("sat-a", 0.9, 0.8), "合法卫星未能部署到观测网络")
	var public_observation: Dictionary = observation.get_public_data()
	var public_infrastructure: Dictionary = satellites.get_public_infrastructure()
	var census := {"complete": true, "exposed_population": 100, "knowledge_carrier_ranges": {"archives": [0, 2]}}

	var low_service = ForecastScript.new()
	var low: Dictionary = low_service.build_forecast(10.0, {"hazard_warning": true}, public_observation, {"network_version": 0}, census)
	_expect(low.get("level", -1) == ForecastScript.ForecastLevel.QUALITATIVE_WARNING, "低能力预测层级错误")
	_expect(not low.has("possible_zone_ids") and not low.has("casualty_range") and not low.has("knowledge_loss_ranges"), "低能力预测泄露了区域、伤亡或知识损失")
	var low_plans: Array = low_service.compare_plans([{"plan_id": "a"}, {"plan_id": "b"}], low)
	_expect(low_plans.size() == 2 and not low_plans[0].has("casualty_range") and not low_plans[1].has("possible_zone_ids"), "切换危机方案泄露了低能力预测未知字段")

	var theory_without_data = ForecastScript.new().build_forecast(
		10.0,
		{"hazard_warning": true, "regional_hazard_projection": true, "casualty_estimation": true},
		{"baseline_days": 0.0, "data_quality": 0.0, "calibration": 0.0, "station_count": 0, "data_version": 0},
		public_infrastructure,
		census,
	)
	_expect(theory_without_data.get("level", -1) == ForecastScript.ForecastLevel.NONE, "只有理论而无观测数据时生成了精确预测")

	var capabilities := {
		"hazard_warning": true,
		"regional_hazard_projection": true,
		"casualty_estimation": true,
		"knowledge_loss_projection": true,
	}
	var first_service = ForecastScript.new()
	var second_service = ForecastScript.new()
	var first: Dictionary = first_service.build_forecast(10.0, capabilities, public_observation, public_infrastructure, census)
	var second: Dictionary = second_service.build_forecast(10.0, capabilities, public_observation, public_infrastructure, census)
	_expect(first == second, "相同公开输入没有生成可复现预测")
	_expect(first.get("level", -1) == ForecastScript.ForecastLevel.HIGH_PRECISION_PROBABILISTIC, "完整观测基础设施未提升预测层级")
	_expect(first.has("casualty_range") and first.has("knowledge_loss_ranges"), "高层预测缺少已授权字段")
	_expect(not first.has("scenario_seed") and not first.has("chaos_start_day") and not first.has("future_positions"), "文明预测快照泄露了规则日期、种子或未来真值")

	var config = load("res://resources/configs/scenario_difficulties.tres")
	var game_snapshot: Dictionary = config.create_snapshot(&"normal")["snapshot"]
	game_snapshot["scenario_seed"] = "13579"
	_expect(GameState.new_game("__观测闭环", {}, game_snapshot), "观测闭环测试场景创建失败")
	for tech_id in ["telescope", "computer", "observatory"]:
		GameState.tech_tree.get_node(tech_id).unlocked = true
	var BuildingClass = preload("res://scripts/simulation/entity_manager.gd").GameBuilding
	var station = BuildingClass.new(9001, "测试天文观测站", "observatory_station", 0, 4, {}, {"electricity": 8.0})
	station.assigned_workers = 4
	station.last_run_ratio = 1.0
	GameState.entities.add_building(station)
	GameState.observation_network.update(31.0, 31.0, true, GameState.entities, {"radiation": 1.0, "stability": 0.8, "possible_zone_ids": [0]})
	var operational: Dictionary = GameState.hazard_forecast_service.build_forecast(
		31.0,
		GameState._get_forecast_capabilities(),
		GameState.observation_network.get_public_data(),
		GameState.satellite_network.get_public_infrastructure(),
		GameState._get_public_census_snapshot(),
	)
	_expect(operational.get("level", -1) >= ForecastScript.ForecastLevel.REGIONAL_RISK, "实际运行的观测站没有接入轨道预测能力")


func _on_transition(_phase: String, _day: float) -> void:
	_transition_count += 1


func _positions() -> Array:
	var result: Array = []
	for star in GameState.environment.stars:
		result.append(star.position)
	return result


func _positions_close(p_first: Array, p_second: Array) -> bool:
	if p_first.size() != p_second.size():
		return false
	for index in p_first.size():
		if p_first[index].distance_to(p_second[index]) > 1e-8:
			return false
	return true


func _expect(p_condition: bool, p_message: String) -> void:
	if p_condition:
		return
	_failures += 1
	push_error(p_message)
