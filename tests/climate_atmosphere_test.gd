extends Node
## 稳定期温度、辐照响应、大气液化反馈与存档回归。

const ZoneScript = preload("res://scripts/simulation/planet_zones.gd")

var _failures := 0


func _ready() -> void:
	_test_stable_start_and_rotation()
	_test_scenario_stable_window()
	_test_distance_response()
	_test_atmosphere_condensation_and_recovery()
	if _failures == 0:
		print("CLIMATE_ATMOSPHERE_TEST_OK")
	get_tree().quit(_failures)


func _test_stable_start_and_rotation() -> void:
	var zones = ZoneScript.new()
	var stars := _stars_at_distance(325.0)
	zones.initialize_temperatures(stars, Vector3.ZERO)
	var initial_range := _temperature_range(zones)
	var initial_average := float(zones.get_average_environment().get("temperature", -273.15))
	_expect(absf(initial_average - 20.0) < 0.1, "开局面积加权均温没有校准到适生范围")
	_expect(initial_range <= 65.0, "开局昼夜或两极温差过大：%.1f℃" % initial_range)
	for _step in 240:
		zones.update(0.25, 1.0, stars, Vector3.ZERO)
	var evolved_average := float(zones.get_average_environment().get("temperature", -273.15))
	var evolved_range := _temperature_range(zones)
	_expect(evolved_average >= 5.0 and evolved_average <= 35.0, "稳定辐照下的 60 天均温偏离适生区：%.1f℃" % evolved_average)
	_expect(evolved_range <= 75.0, "稳定辐照下的区域温差失控：%.1f℃" % evolved_range)
	_expect(float(zones.get_average_environment().get("atmosphere_pressure_fraction", 0.0)) > 0.99, "稳定期开局发生了不应有的大气塌缩")


func _test_scenario_stable_window() -> void:
	var difficulty_config = load("res://resources/configs/scenario_difficulties.tres")
	var snapshot: Dictionary = difficulty_config.create_snapshot(&"normal")["snapshot"]
	snapshot["scenario_seed"] = "20260722"
	_expect(GameState.new_game("__稳定期气候", {}, snapshot), "稳定期气候测试无法创建场景")
	var game_day := 0.0
	for _step in 240:
		GameState.scenario_manager.update(game_day, 0.25)
		GameState.planet_zones.update(
			0.25, 1.0, GameState.environment.get_stars_data(), GameState.environment.get_planet_position()
		)
		game_day += 0.25
	var average := float(GameState.planet_zones.get_average_environment().get("temperature", -273.15))
	var temperature_range := _temperature_range(GameState.planet_zones)
	_expect(average >= 5.0 and average <= 35.0, "规定稳定星历运行 60 天后均温偏离适生区：%.1f℃" % average)
	_expect(temperature_range <= 75.0, "规定稳定星历运行 60 天后区域温差失控：%.1f℃" % temperature_range)


func _test_distance_response() -> void:
	var zones = ZoneScript.new()
	zones.initialize_temperatures(_stars_at_distance(300.0), Vector3.ZERO)
	var initial_average := float(zones.get_average_environment().get("temperature", 0.0))
	var distant_stars := _stars_at_distance(600.0)
	for _step in 120:
		zones.update(0.25, 1.0, distant_stars, Vector3.ZERO)
	var cooled_average := float(zones.get_average_environment().get("temperature", 0.0))
	_expect(cooled_average < initial_average - 15.0, "恒星距离变化没有通过四次方根辐射平衡影响全球温度")


func _test_atmosphere_condensation_and_recovery() -> void:
	var zones = ZoneScript.new({
		"surface_response_rate": 0.0,
		"air_surface_exchange_rate": 0.0,
		"surface_diffusion_rate": 0.0,
	})
	var stars := _stars_at_distance(325.0)
	zones.initialize_temperatures(stars, Vector3.ZERO)
	for zone in zones.zones:
		zone.temperature = -220.0
		zone.air_temperature = -220.0
	zones.update(4.0, 1.0, stars, Vector3.ZERO)
	var collapsed: Dictionary = zones.get_zone_environment(0)
	_expect(float(collapsed.get("nitrogen_gas_fraction", 1.0)) < 0.1, "极冷时氮气没有凝结")
	_expect(float(collapsed.get("oxygen_gas_fraction", 1.0)) < 0.1, "极冷时氧气没有凝结")
	_expect(float(collapsed.get("atmosphere_pressure_fraction", 1.0)) < 0.1, "气体凝结没有降低大气质量与输运能力")

	var saved: Dictionary = zones.get_state()
	var restored = ZoneScript.new()
	_expect(restored.load_state(saved), "当前气候格式无法恢复")
	var restored_zone: Dictionary = restored.get_zone_environment(0)
	_expect(is_equal_approx(float(restored_zone.get("atmosphere_pressure_fraction", 1.0)), float(collapsed.get("atmosphere_pressure_fraction", 0.0))), "大气相态存档往返不完整")

	for zone in zones.zones:
		zone.temperature = 20.0
		zone.air_temperature = 20.0
	zones.update(10.0, 1.0, stars, Vector3.ZERO)
	var recovered: Dictionary = zones.get_zone_environment(0)
	_expect(float(recovered.get("atmosphere_pressure_fraction", 0.0)) > 0.99, "回暖后氮氧大气没有再气化")


func _stars_at_distance(distance: float) -> Array:
	return [
		{"position": Vector3(distance, 0.0, 0.0), "mass": 1000.0, "is_planet": false},
		{"position": Vector3.ZERO, "mass": 1.0, "is_planet": true},
	]


func _temperature_range(zones) -> float:
	var minimum := INF
	var maximum := -INF
	for zone in zones.zones:
		minimum = minf(minimum, zone.temperature)
		maximum = maxf(maximum, zone.temperature)
	return maximum - minimum


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
