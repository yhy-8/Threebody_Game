extends Node
## 科研点生命周期与建造事务回归测试。

const EntityScript = preload("res://scripts/simulation/entity_manager.gd")
const TechScript = preload("res://scripts/simulation/tech_tree.gd")
const DecisionScript = preload("res://scripts/simulation/decision_manager.gd")
const ZoneScript = preload("res://scripts/simulation/planet_zones.gd")

var _failures: int = 0


func _ready() -> void:
	_test_research_lifecycle()
	_test_construction_transaction()
	if _failures == 0:
		print("RESEARCH_CONSTRUCTION_TEST_OK")
	get_tree().quit(_failures)


func _test_research_lifecycle() -> void:
	var entities = EntityScript.new()
	var tech = TechScript.new()
	var completions: Array[String] = []
	tech.research_finished.connect(func(tech_id: String, _name: String): completions.append(tech_id))
	tech.research_points["basic"] = 100.0
	var instant: Dictionary = tech.start_research("telescope", entities)
	_expect(instant.get("success", false) and tech.is_unlocked("telescope"), "库存科研点没有在开题时投入")
	_expect(is_equal_approx(tech.research_points["basic"], 20.0), "即时完成后的科研点不守恒")
	_expect(completions == ["telescope"], "科研完成信号没有发射")

	tech.research_points["basic"] = 30.0
	var partial: Dictionary = tech.start_research("survival_shelter", entities)
	_expect(partial.get("success", false) and is_equal_approx(tech.research_progress["basic"], 30.0), "部分库存科研点未注入")
	tech.produce_research("basic", 10.0)
	var cancelled: Dictionary = tech.cancel_research()
	_expect(cancelled.get("success", false) and is_equal_approx(tech.research_points["basic"], 40.0), "取消研究没有守恒退回科研点")
	entities.resources["iron"].amount = 500.0
	_expect(tech.start_research("survival_shelter", entities).get("success", false), "取消后无法重新开始研究")
	tech.produce_research("basic", 20.0)
	_expect(tech.is_unlocked("survival_shelter") and is_zero_approx(tech.research_points["basic"]), "重新研究完成后的点数不守恒")

	entities.population.total = 300
	entities.resources["iron"].amount = 500.0
	entities.resources["copper"].amount = 100.0
	tech.research_points["basic"] = 200.0
	tech.research_points["applied"] = 50.0
	_expect(tech.start_research("computer", entities).get("success", false) and tech.is_unlocked("computer"), "多类型科研库存无法完成研究")


func _test_construction_transaction() -> void:
	var entities = EntityScript.new()
	var tech = TechScript.new()
	var decisions = DecisionScript.new()
	var zones = ZoneScript.new()
	var initial_iron: float = entities.get_resource("iron")
	var initial_history: int = decisions.enacted_history.size()
	var initial_id: int = decisions._next_building_id
	for invalid_zone in [-1, 72, 999]:
		var failed: Dictionary = decisions.execute_decision("build_algae_collector", entities, tech, zones, invalid_zone)
		_expect(not failed.get("success", false), "非法区域建造成功：%d" % invalid_zone)
		_expect(is_equal_approx(entities.get_resource("iron"), initial_iron), "非法区域建造扣除了资源")
		_expect(entities.buildings.is_empty() and decisions.enacted_history.size() == initial_history and decisions._next_building_id == initial_id, "失败建造污染了历史、ID 或建筑列表")
	var missing_manager: Dictionary = decisions.execute_decision("build_algae_collector", entities, tech, null, 0)
	_expect(not missing_manager.get("success", false) and is_equal_approx(entities.get_resource("iron"), initial_iron), "区域管理器为空时仍发生状态写入")
	var bypass: Dictionary = decisions.can_execute("build_copper_mine", entities, null, zones, 0)
	_expect(not bypass.get("success", false), "省略科技树绕过了科技门槛")
	var success: Dictionary = decisions.execute_decision("build_algae_collector", entities, tech, zones, 0)
	_expect(success.get("success", false), "合法建造失败")
	_expect(entities.buildings.size() == 1 and success.get("building_id", -1) in zones.get_zone(0).building_ids, "合法建筑没有同时注册到实体与区域")
	_expect(is_equal_approx(entities.get_resource("iron"), initial_iron - 20.0), "合法建造成本结算错误")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
