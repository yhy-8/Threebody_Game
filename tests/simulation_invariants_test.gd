extends Node
## 人口、效率、资源守恒与劳动力不变量回归测试。

const EntityScript = preload("res://scripts/simulation/entity_manager.gd")
const DecisionScript = preload("res://scripts/simulation/decision_manager.gd")

var _failures: int = 0


func _ready() -> void:
	_test_efficiency_step_invariance()
	_test_resource_conservation()
	_test_population_invariants()
	_test_policy_control_boundaries()
	_test_storage_loss_step_invariance()
	if _failures == 0:
		print("SIMULATION_INVARIANTS_TEST_OK")
	get_tree().quit(_failures)


func _base_config() -> Dictionary:
	return {"population": {"food_per_person_per_day": 0.0, "base_growth_per_breeder": 0.0, "natural_growth_rate": 0.0}}


func _test_efficiency_step_invariance() -> void:
	var once = EntityScript.new(_base_config())
	var split = EntityScript.new(_base_config())
	once.update({"heat_level": 1.0}, null, 1.0, false)
	for _index in 10:
		split.update({"heat_level": 1.0}, null, 0.1, false)
	_expect(is_equal_approx(once.global_efficiency, split.global_efficiency), "全局效率仍依赖更新次数")


func _test_resource_conservation() -> void:
	var entities = EntityScript.new(_base_config())
	entities.resources["algae_fuel"].amount = 0.0
	entities.resources["electricity"].amount = 0.0
	var generator = EntityScript.GameBuilding.new(1, "藻电站", "algae_power_plant", -1, 3, {"electricity": 5.0}, {"algae_fuel": 3.0})
	generator.assigned_workers = 3
	entities.add_building(generator)
	entities.update({"heat_level": 0.5}, null, 1.0, false)
	_expect(is_zero_approx(entities.get_resource("electricity")), "燃料为零时仍免费发电")

	var manual_mine = EntityScript.GameBuilding.new(2, "铁矿", "iron_mine", -1, 5, {"iron": 2.0}, {})
	manual_mine.assigned_workers = 5
	entities.add_building(manual_mine)
	entities.resources["iron"].amount = 0.0
	entities.update({"heat_level": 0.5}, null, 1.0, false)
	_expect(entities.get_resource("iron") > 0.0, "不耗电建筑被缺电错误停产")
	var before: float = entities.get_resource("iron")
	_expect(not entities.consume_resource("iron", -10.0), "负数消费被接受")
	entities.produce_resource("iron", -10.0)
	_expect(is_equal_approx(before, entities.get_resource("iron")), "负数参数增加或减少了资源")


func _test_population_invariants() -> void:
	var entities = EntityScript.new(_base_config())
	var building = EntityScript.GameBuilding.new(1, "矿场", "iron_mine", -1, 5, {"iron": 1.0}, {})
	building.assigned_workers = 5
	entities.add_building(building)
	entities.population.breeders = 20
	entities.prepare_population_reduction(1)
	entities.population.total = 1
	entities.enforce_population_invariants()
	_expect(entities.population.breeders + entities.get_total_building_workers() <= 1, "减员后仍有幽灵劳动力")
	_expect(not entities.store_population_from_idle(1).get("success", false), "公共入库 API 重复占用了在岗人口")


func _test_policy_control_boundaries() -> void:
	var decisions = DecisionScript.new()
	var policy_ids: Array = decisions.get_policy_decisions().map(func(decision): return decision.id)
	_expect("boom" not in policy_ids and "industrial_drive" not in policy_ids, "文明政策仍提供无机制支撑的永久生育或免费产出倍增")
	var entities = EntityScript.new(_base_config())
	entities.set_policy_effects(["rationing"])
	_expect(
		is_equal_approx(entities.population.policy_food_multiplier, 0.75)
		and is_equal_approx(entities.policy_efficiency_multiplier, 0.9)
		and is_equal_approx(entities.population.policy_growth_multiplier, 1.0),
		"应急配给没有按口粮—效率取舍结算，或仍在凭空修改人口增长",
	)
	entities.update({"heat_level": 0.5}, null, 1.0, false)
	_expect(entities.social_stability < 1.0 and entities.population_health < 1.0, "应急配给没有结算健康与安定代价")


func _test_storage_loss_step_invariance() -> void:
	var schedules: Array = [[1.0], [] , []]
	for _index in 10:
		schedules[1].append(0.1)
	for _index in 1000:
		schedules[2].append(0.001)
	var results: Array = []
	for schedule in schedules:
		GameState.new_game("__损耗分步测试")
		GameState.confirm_capital(int(GameState.settlement_system.candidate_views[0].get("zone_id", -1)))
		var storage = EntityScript.GameBuilding.new(1, "脱水仓", "storage_vault", 0, 0, {}, {}, 0.0, 0.0, false, true, 100.0, 100.0, 100)
		GameState.entities.add_building(storage)
		GameState.planet_zones.add_building_to_zone(0, 1)
		GameState.entities.population.total = 1
		GameState.entities.population.storage_capacity = 100
		GameState.entities.population.stored_population = 10
		var zone = GameState.planet_zones.get_zone(0)
		zone.temperature = -180.0
		zone.radiation = 0.0
		for step in schedule:
			GameState._process_storage_damage(step)
		results.append([
			GameState.entities.population.stored_population,
			GameState.entities.population.stored_loss_accumulator,
		])
	_expect(results[0][0] == results[1][0] and results[1][0] == results[2][0], "库存人口损耗随分步变化")
	_expect(is_equal_approx(results[0][1], results[1][1]) and is_equal_approx(results[1][1], results[2][1]), "库存损耗小数余量随分步变化")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
