extends Node
## Opening lock, information boundaries, local inventory, and physical expedition regression coverage.

const OpeningGuidanceControllerScript = preload("res://scripts/guidance/opening_guidance_controller.gd")
const EntityManagerScript = preload("res://scripts/simulation/entity_manager.gd")

var _failures: int = 0


func _ready() -> void:
	GameState.reset()
	_expect(GameState.new_game("__开局区域回归", {}, {}, {"guidance_mode": 0}), "新游戏初始化失败")
	_test_awaiting_capital_and_candidate_boundary()
	_test_guidance_is_presentation_only()
	_test_capital_and_local_inventory()
	_test_physical_expedition()
	_test_mid_operation_persistence()
	GameState.reset()
	if _failures == 0:
		print("OPENING_REGION_SYSTEM_TEST_OK")
	get_tree().quit(_failures)


func _test_awaiting_capital_and_candidate_boundary() -> void:
	_expect(GameState.paused and is_equal_approx(GameState.game_time, 0.0), "首都确认前没有锁定在第 0 天")
	_expect(GameState.settlement_system.capital_zone_id == -1, "新局提前指定了首都")
	var candidate: Dictionary = GameState.settlement_system.candidate_views[0]
	var public_view: Dictionary = candidate.get("known", {}).duplicate(true)
	_expect(not public_view.has("resource_deposits") and not public_view.has("fertility"), "首都候选公开视图泄露隐藏资源")
	var before_rank: Array = GameState.settlement_system.selection_service.rank_candidates(
		GameState.settlement_system.selection_service.build_candidate_views([public_view], GameState.scenario_manager.get_rule_state(0.0))
	)
	var zone = GameState.planet_zones.get_zone(int(candidate["zone_id"]))
	zone.resource_deposits["rare_mineral"] = 1.0 - float(zone.resource_deposits.get("rare_mineral", 0.0))
	var after_rank: Array = GameState.settlement_system.selection_service.rank_candidates(
		GameState.settlement_system.selection_service.build_candidate_views([public_view], GameState.scenario_manager.get_rule_state(0.0))
	)
	_expect(before_rank == after_rank, "修改隐藏矿藏影响了只读公开候选排名")
	var json_state = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	_expect(json_state is Dictionary and GameState.from_dict(json_state), "等待首都状态无法完成 JSON 存档往返")
	_expect(GameState.paused and GameState.settlement_system.capital_zone_id == -1, "读取待选首都存档后错误推进或自动选址")


func _test_guidance_is_presentation_only() -> void:
	var world_before: String = JSON.stringify({"entities": GameState.entities.get_state(), "zones": GameState.planet_zones.get_state()})
	for mode in [0, 1, 2]:
		var controller = OpeningGuidanceControllerScript.new()
		_expect(controller.initialize(mode), "引导模式初始化失败：%d" % mode)
		controller.get_active_task_views()
	var world_after: String = JSON.stringify({"entities": GameState.entities.get_state(), "zones": GameState.planet_zones.get_state()})
	_expect(world_before == world_after, "切换或读取引导模式修改了世界状态")
	var guidance = OpeningGuidanceControllerScript.new()
	guidance.initialize(0)
	_expect(guidance.handle_domain_event("capital_confirmed", {"source_id": "test:capital"}), "真实领域事件没有完成引导任务")
	_expect(not guidance.handle_domain_event("capital_confirmed", {"source_id": "test:capital"}), "重复领域事件重复结算了引导任务")
	_expect(guidance.phase == guidance.OpeningPhase.RULES_TIME, "确认首都后没有进入真实时间控制教学")
	_expect(guidance.handle_domain_event("time_control_used", {"source_id": "test:time"}), "实际使用时间控制没有推进引导")
	_expect(guidance.defer_group("等待更多食物") and guidance.get_active_task_views().is_empty(), "暂缓整组引导后仍显示任务")
	var deferred_state: Dictionary = guidance.get_state()
	var restored_guidance = OpeningGuidanceControllerScript.new()
	_expect(restored_guidance.initialize(0, deferred_state) and restored_guidance.group_deferred, "暂缓引导状态没有保存")
	restored_guidance.resume_guidance()
	_expect(not restored_guidance.group_deferred and not restored_guidance.get_active_task_views().is_empty(), "恢复引导没有从真实进度继续")


func _test_capital_and_local_inventory() -> void:
	var capital_id := int(GameState.settlement_system.candidate_views[0].get("zone_id", -1))
	var result: Dictionary = GameState.confirm_capital(capital_id)
	_expect(result.get("success", false), "合法候选无法确认为首都")
	_expect(not GameState.paused and GameState.settlement_system.get_population(capital_id) == GameState.entities.population.total, "首都确认后人口没有落在发源地")
	var local: Dictionary = GameState.regional_logistics.get_local_inventory(capital_id)
	for resource_id in GameState.entities.resources:
		_expect(is_equal_approx(float(local.get(resource_id, -1.0)), GameState.entities.get_resource(resource_id)), "初始资源没有全部进入首都地方库存：%s" % resource_id)
	_expect(GameState.opening_guidance.completed_task_ids.has("opening:capital"), "首都真实确认事件没有推进引导")


func _test_physical_expedition() -> void:
	var capital_id: int = GameState.settlement_system.capital_zone_id
	var target_id := int(GameState.planet_zones.get_zone_neighbors(capital_id)[0])
	var route: Dictionary = GameState.plan_region_route(capital_id, target_id)
	_expect(route.get("success", false) and route.get("cost_explanation", "").contains("口粮"), "路线没有给出可解释的时间与补给成本")
	var people_before: int = GameState.settlement_system.get_population(capital_id)
	var food_before: float = GameState.entities.get_resource("food")
	var start: Dictionary = GameState.start_region_expedition(capital_id, target_id, 5)
	_expect(start.get("success", false), "相邻区域勘探队无法出发：%s" % start.get("message", ""))
	_expect(GameState.settlement_system.get_population(capital_id) == people_before - 5, "出发人口仍留在首都劳动力中")
	_expect(GameState.region_movement_system.get_reserved_population() == 5, "在途人口没有占用真实劳动力")
	_expect(GameState.settlement_system.get_population(target_id) == 0, "勘探队到达前已成为目标地人口")
	_expect(is_equal_approx(GameState.entities.get_resource("food"), food_before), "仅装载补给就错误销毁了文明总食物")
	var operation_id: String = str(start.get("operation_id", ""))
	GameState.region_movement_system.update(2.0, GameState.settlement_system, GameState.regional_logistics, GameState.entities, GameState.exploration_system, GameState.planet_zones, GameState.game_time + 2.0)
	var surveyed: Dictionary = GameState.get_zone_knowledge(target_id)
	_expect(int(surveyed.get("level", 0)) == GameState.settlement_system.ZoneKnowledgeLevel.SURVEYED, "实际抵达目标后没有生成勘探记录")
	var estimates: Dictionary = surveyed.get("public_data", {}).get("resource_estimates", {})
	_expect(estimates.get("iron", {}) is Dictionary and estimates["iron"].has("lower") and estimates["iron"].has("upper"), "勘探结果没有使用估计区间")
	_expect(not estimates["iron"].has("exact"), "勘探结果泄露精确地下储量")
	GameState.region_movement_system.update(2.0, GameState.settlement_system, GameState.regional_logistics, GameState.entities, GameState.exploration_system, GameState.planet_zones, GameState.game_time + 4.0)
	_expect(int(GameState.region_movement_system.operations[operation_id].get("status", -1)) == GameState.region_movement_system.OperationStatus.ARRIVED, "勘探队没有完成真实往返")
	_expect(GameState.settlement_system.get_population(capital_id) == people_before, "返程人员没有回到出发地")
	_expect(GameState.entities.get_resource("food") < food_before, "往返过程没有实际消耗口粮")
	var transport_people_before: int = GameState.settlement_system.get_population(capital_id)
	var transport: Dictionary = GameState.start_region_transport(capital_id, target_id, 2, {"food": 10.0})
	_expect(transport.get("success", false), "真实运输行动无法出发")
	GameState.region_movement_system.update(2.0, GameState.settlement_system, GameState.regional_logistics, GameState.entities, GameState.exploration_system, GameState.planet_zones, GameState.game_time + 6.0)
	_expect(GameState.regional_logistics.get_local_amount(target_id, "food") >= 9.99, "运输队抵达后没有把载荷卸入目标地")
	GameState.region_movement_system.update(2.0, GameState.settlement_system, GameState.regional_logistics, GameState.entities, GameState.exploration_system, GameState.planet_zones, GameState.game_time + 8.0)
	_expect(GameState.settlement_system.get_population(capital_id) == transport_people_before, "运输队人员没有返回出发地")
	var migration: Dictionary = GameState.start_region_migration(capital_id, target_id, 5, {"food": 10.0})
	_expect(migration.get("success", false), "真实迁徙行动无法出发")
	_expect(GameState.settlement_system.get_population(target_id) == 0, "迁徙者到达前已成为目标地劳动力")
	GameState.region_movement_system.update(2.0, GameState.settlement_system, GameState.regional_logistics, GameState.entities, GameState.exploration_system, GameState.planet_zones, GameState.game_time + 6.0)
	_expect(GameState.settlement_system.get_population(target_id) == 5, "迁徙者抵达后没有进入目标地区人口")
	_expect(GameState.regional_logistics.get_local_amount(target_id, "food") >= 9.99, "迁徙载荷没有进入目标地地方库存")
	_expect(GameState.settlement_system.get_settlement(target_id).get("type", "") == "outpost", "首批迁入者没有建立前哨记录")
	var shelter = EntityManagerScript.GameBuilding.new(9101, "测试前哨庇护所", "shelter", target_id, 0, {}, {}, 0.0, 0.0, false, true, 100.0, 100.0, 20)
	var food_site = EntityManagerScript.GameBuilding.new(9102, "测试前哨食物点", "algae_food_synth", target_id, 5, {"food": 2.5})
	food_site.assigned_workers = 1
	food_site.last_output_rate = {"food": 2.5}
	GameState.entities.add_building(shelter)
	GameState.entities.add_building(food_site)
	GameState.set_developer_mode(true)
	_expect(GameState.developer_unlock_all_technologies(), "测试无法准备符号记录能力")
	GameState.set_developer_mode(false)
	var upgrade_status: Dictionary = GameState.get_outpost_upgrade_status(target_id)
	_expect(upgrade_status.get("success", false), "真实庇护、食物、储备、路线与管理条件齐备后仍不能升级前哨：%s" % upgrade_status.get("message", ""))
	_expect(GameState.upgrade_outpost(target_id).get("success", false), "前哨升级命令失败")
	_expect(GameState.settlement_system.get_settlement(target_id).get("type", "") == "settlement", "前哨升级后未成为常设聚落")
	var old_capital_id: int = GameState.settlement_system.capital_zone_id
	var relocation: Dictionary = GameState.start_capital_relocation(target_id)
	_expect(relocation.get("success", false), "符合条件的常设聚落无法发起迁都：%s" % relocation.get("message", ""))
	_expect(GameState.settlement_system.capital_zone_id == old_capital_id, "迁都队到达前就切换了首都")
	GameState.region_movement_system.update(2.0, GameState.settlement_system, GameState.regional_logistics, GameState.entities, GameState.exploration_system, GameState.planet_zones, GameState.game_time + 10.0)
	_expect(GameState.settlement_system.capital_zone_id == target_id, "迁都队实际到达后没有切换首都")
	_expect(GameState.entities.global_efficiency <= 0.850001, "迁都到达后没有承担协调损失")


func _test_mid_operation_persistence() -> void:
	var capital_id: int = GameState.settlement_system.capital_zone_id
	var neighbors: Array = GameState.planet_zones.get_zone_neighbors(capital_id)
	var target_id := int(neighbors[1] if neighbors.size() > 1 else neighbors[0])
	var start: Dictionary = GameState.start_region_expedition(capital_id, target_id, 3)
	_expect(start.get("success", false), "第二支勘探队无法出发")
	var operation_id := str(start.get("operation_id", ""))
	GameState.region_movement_system.update(1.0, GameState.settlement_system, GameState.regional_logistics, GameState.entities, GameState.exploration_system, GameState.planet_zones, GameState.game_time + 1.0)
	var elapsed_before: float = float(GameState.region_movement_system.operations[operation_id].get("elapsed_days", 0.0))
	var food_before_pause: float = GameState.entities.get_resource("food")
	_expect(GameState.pause_region_operation(operation_id).get("success", false), "行进中的队伍无法暂停")
	GameState.region_movement_system.update(1.0, GameState.settlement_system, GameState.regional_logistics, GameState.entities, GameState.exploration_system, GameState.planet_zones, GameState.game_time + 2.0)
	_expect(is_equal_approx(float(GameState.region_movement_system.operations[operation_id].get("elapsed_days", 0.0)), elapsed_before), "暂停后行程仍在推进")
	_expect(is_equal_approx(GameState.entities.get_resource("food"), food_before_pause), "暂停后仍在消耗行程口粮")
	var json_state = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	_expect(json_state is Dictionary and GameState.from_dict(json_state), "在途行动无法完成 JSON 存档往返")
	_expect(GameState.region_movement_system.operations.has(operation_id), "读取存档丢失在途行动")
	_expect(is_equal_approx(float(GameState.region_movement_system.operations[operation_id].get("elapsed_days", 0.0)), elapsed_before), "在途行动进度没有恢复")
	_expect(int(GameState.region_movement_system.operations[operation_id].get("status", -1)) == GameState.region_movement_system.OperationStatus.PAUSED, "在途行动的暂停状态没有恢复")
	_expect(GameState.entities.external_reserved_workers >= 3, "读取存档后在途人员不再占用劳动力")
	_expect(GameState.resume_region_operation(operation_id).get("success", false), "读档后无法继续暂停的行动")
	var valid_universe_name: String = GameState.universe_name
	var invalid_state: Dictionary = GameState.to_dict()
	invalid_state["settlement"]["zone_knowledge"] = []
	_expect(not GameState.from_dict(invalid_state) and GameState.universe_name == valid_universe_name, "非法区域存档在完整校验前部分覆盖了当前游戏")


func _expect(p_condition: bool, p_message: String) -> void:
	if p_condition:
		return
	_failures += 1
	push_error(p_message)
