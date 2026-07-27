extends Node
## 区域禀赋、方向辐射、庇护与科技效果回归测试。

const EntityScript = preload("res://scripts/simulation/entity_manager.gd")
const ZoneScript = preload("res://scripts/simulation/planet_zones.gd")
const TechScript = preload("res://scripts/simulation/tech_tree.gd")

var _failures: int = 0


func _ready() -> void:
	_test_zone_yields()
	_test_directional_radiation()
	_test_protection_and_technology()
	if _failures == 0:
		print("ZONE_ECONOMY_TEST_OK")
	get_tree().quit(_failures)


func _test_zone_yields() -> void:
	var zones = ZoneScript.new()
	var poor = zones.get_zone(0)
	var rich = zones.get_zone(1)
	poor.temperature = 20.0
	rich.temperature = 20.0
	poor.resource_deposits["iron"] = 0.2
	rich.resource_deposits["iron"] = 0.8
	var entities = EntityScript.new({"population": {"food_per_person_per_day": 0.0, "natural_growth_rate": 0.0}})
	entities.resources["iron"].amount = 0.0
	var poor_mine = EntityScript.GameBuilding.new(1, "贫矿", "iron_mine", 0, 5, {"iron": 2.0}, {})
	var rich_mine = EntityScript.GameBuilding.new(2, "富矿", "iron_mine", 1, 5, {"iron": 2.0}, {})
	poor_mine.assigned_workers = 5
	rich_mine.assigned_workers = 5
	entities.add_building(poor_mine)
	entities.add_building(rich_mine)
	entities.update({"heat_level": 0.5}, zones, 1.0, false)
	_expect(is_equal_approx(poor_mine.last_output_rate["iron"], 2.0), "贫矿区产量系数未生效")
	_expect(is_equal_approx(rich_mine.last_output_rate["iron"], 8.0), "富矿区产量系数未生效")


func _test_directional_radiation() -> void:
	var zones = ZoneScript.new({"dark_side_scatter": 0.05})
	var stars: Array = [
		{"position": Vector3(100.0, 0.0, 0.0), "mass": 1000.0, "is_planet": false},
		{"position": Vector3.ZERO, "mass": 1.0, "is_planet": true},
	]
	zones.initialize_temperatures(stars, Vector3.ZERO)
	var front = zones.get_zone(24)
	var back = zones.get_zone(30)
	_expect(front.radiation > back.radiation * 10.0, "向光区与背光区辐射没有方向差异")
	_expect(back.radiation > 0.0 and back.light_intensity > 0.0, "背光区 5% 散射没有保留")
	var saved: Dictionary = zones.get_state()
	var restored = ZoneScript.new()
	restored.load_state(saved)
	_expect(is_equal_approx(restored.get_zone(24).radiation, front.radiation) and is_equal_approx(restored.get_zone(24).light_intensity, front.light_intensity), "区域环境存档往返不完整")


func _test_protection_and_technology() -> void:
	var zones = ZoneScript.new()
	zones.get_zone(0).temperature = 20.0
	var entities = EntityScript.new({"population": {"food_per_person_per_day": 0.0, "natural_growth_rate": 0.0}})
	var generator = EntityScript.GameBuilding.new(1, "藻电", "algae_power_plant", 0, 3, {"electricity": 5.0}, {"algae_fuel": 3.0})
	generator.assigned_workers = 3
	var shelter = EntityScript.GameBuilding.new(2, "深地庇护所", "deep_shelter", 0, 8, {}, {"electricity": 3.0}, 0.0, 0.0, false, true, 100.0, 100.0, 100)
	shelter.assigned_workers = 8
	var shield = EntityScript.GameBuilding.new(3, "屏蔽站", "radiation_shield", 0, 4, {}, {"electricity": 5.0})
	shield.assigned_workers = 4
	entities.add_building(generator)
	entities.add_building(shelter)
	entities.add_building(shield)
	entities.update({"heat_level": 0.5}, zones, 0.1, false)
	var protection: Dictionary = entities.get_zone_protection(0)
	_expect(
		is_equal_approx(protection["environment"], 0.92)
		and is_equal_approx(protection["radiation"], 0.72),
		"已配员且有电的庇护所或屏蔽站没有提供区域保护",
	)

	var tech = TechScript.new()
	tech.get_node("radiation_armor").unlocked = true
	tech.get_node("high_alloy").unlocked = true
	entities.apply_technology_effects(tech)
	_expect(is_equal_approx(generator.max_durability, 200.0), "高强度合金没有提高耐久上限")
	_expect(generator.heat_resistance > 60.0 and generator.radiation_resistance > 7.5, "建筑抗性科技没有接入模拟层")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
