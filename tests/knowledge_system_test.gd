extends Node
## Knowledge lifecycle, discovery, projects, inheritance, policies, preservation, and migration.

const KnowledgeSystemScript = preload("res://scripts/simulation/knowledge_system.gd")

var _failures: int = 0


func _ready() -> void:
	GameState.reset()
	_expect(GameState.new_game("知识体系测试"), "无法创建知识体系测试宇宙")
	_expect(GameState.confirm_capital(int(GameState.settlement_system.candidate_views[0].get("zone_id", -1))).get("success", false), "无法确认知识测试首都")
	GameState.paused = true
	_test_initial_visibility()
	_test_discovery_research_and_engineering()
	_test_policy_education_and_preservation()
	_test_degradation_and_restore()
	_test_legacy_migration()
	_test_persistence()
	GameState.reset()
	if _failures == 0:
		print("KNOWLEDGE_SYSTEM_TEST_OK")
	get_tree().quit(_failures)


func _test_initial_visibility() -> void:
	_expect(GameState.knowledge_system.graph.is_valid(), "数据驱动知识图校验失败")
	_expect(GameState.knowledge_system.graph.nodes.size() >= 25, "知识图没有覆盖设计中的主要领域")
	for root_id in ["oral_tradition", "simple_counting", "stone_tools", "controlled_fire"]:
		_expect(GameState.knowledge_system.get_node_state(root_id) == KnowledgeSystemScript.KnowledgeState.APPLIED, "原始文明缺少起始能力：%s" % root_id)
	_expect(GameState.knowledge_system.get_node_state("fusion_physics") == KnowledgeSystemScript.KnowledgeState.HIDDEN, "新开局提前泄露远端聚变知识")
	var visible_ids: Array = GameState.knowledge_system.get_visible_nodes().map(func(view): return view["id"])
	_expect("fusion_physics" not in visible_ids and "symbolic_record" in visible_ids, "可见知识没有遵守渐进显露边界")
	var rumor_view: Dictionary = GameState.knowledge_system.get_node_view("symbolic_record")
	_expect(rumor_view.get("display_name", "") != "符号记录" and not rumor_view.has("capability_tags"), "模糊方向泄露了具体名称或效果")


func _test_discovery_research_and_engineering() -> void:
	var accepted: bool = GameState.knowledge_system.apply_discovery(
		"symbolic_record", "test:oral_evidence", 0.25, {"oral_repetition": 2.0}
	)
	var duplicate: bool = GameState.knowledge_system.apply_discovery(
		"symbolic_record", "test:oral_evidence", 0.25, {"oral_repetition": 2.0}
	)
	_expect(accepted and not duplicate, "一次性发现来源可以重复领取")
	_expect(GameState.knowledge_system.get_node_state("symbolic_record") == KnowledgeSystemScript.KnowledgeState.RESEARCHABLE, "线索、证据与前置满足后未进入可研究状态")
	var start: Dictionary = GameState.start_knowledge_research("symbolic_record")
	_expect(start.get("success", false), "知识研究项目无法开始")
	_expect(GameState.entities.external_reserved_workers == 2, "研究人员没有占用真实劳动力")
	GameState.research_project_system.update_day(1.0, {"basic": 100.0}, GameState.entities)
	GameState._refresh_external_workforce_reservation()
	_expect(GameState.knowledge_system.get_node_state("symbolic_record") == KnowledgeSystemScript.KnowledgeState.MASTERED, "完成研究后没有停在理论掌握状态")
	_expect(not GameState.knowledge_system.has_capability("symbolic_recording"), "理论掌握错误地跳过工程化直接授予能力")
	var engineering: Dictionary = GameState.start_knowledge_engineering("symbolic_record", "standardize_marks")
	_expect(engineering.get("success", false), "理论掌握后无法启动独立工程项目")
	GameState.engineering_project_system.update_day(1.0, {"applied": 100.0}, GameState.entities)
	GameState._refresh_external_workforce_reservation()
	_expect(GameState.knowledge_system.get_node_state("symbolic_record") == KnowledgeSystemScript.KnowledgeState.APPLIED, "工程项目完成后未进入应用状态")
	_expect(GameState.knowledge_system.has_capability("symbolic_recording"), "工程化没有授予稳定能力标签")


func _test_policy_education_and_preservation() -> void:
	var before_state: int = GameState.knowledge_system.get_node_state("celestial_motion")
	GameState.knowledge_policy_system.set_knowledge_priority(100.0)
	_expect(GameState.knowledge_system.get_node_state("celestial_motion") == before_state, "知识重视度凭空改变了知识状态")
	var policy_result: Dictionary = GameState.adopt_knowledge_policy("designated_storytellers")
	_expect(policy_result.get("success", false), "已具备口述能力却无法采用指定讲述者制度")
	var plan := {
		"plan_id": "plan:test:oral",
		"node_id": "oral_tradition",
		"teacher_count": 1,
		"student_count": 4,
		"hours_per_day": 4.0,
		"practice_building_ids": [],
		"emergency_course": false,
	}
	var idle_before: int = GameState.entities.get_idle_population()
	var teaching: Dictionary = GameState.start_teaching_plan(plan)
	_expect(teaching.get("success", false), "合法教学计划无法开始")
	_expect(GameState.entities.get_idle_population() == idle_before - 5, "教师与学习者没有和生产岗位竞争劳动力")
	_expect("opening:first_teaching_plan" not in GameState.opening_guidance.completed_task_ids, "教学计划仅创建就被误判为已运行")
	GameState._update_knowledge_evolution(GameState.game_time, 0.1)
	_expect("opening:first_teaching_plan" in GameState.opening_guidance.completed_task_ids, "教学计划真实运行后没有推进引导")

	var shelter := [{
		"shelter_id": "s:test", "usable_volume_m3": 100.0, "berths": 10,
		"life_support_people": 10, "food_water_person_days": 300.0,
		"dry_archive_volume_m3": 20.0, "heavy_storage_mass_kg": 1000.0,
		"continuous_power_kw": 5.0, "environment_control_level": 0.5,
	}]
	var preservation_plan := {
		"plan_id": "p:test",
		"people": [{"id": "people:test", "count": 5, "role": "teacher", "supply_days": 30.0}],
		"records": [{"id": "record:test", "dry_volume_m3": 8.0}],
		"artifacts": [{"id": "artifact:test", "volume_m3": 1.0, "mass_kg": 100.0}],
		"unplaced_objects": [],
	}
	var preview: Dictionary = GameState.preservation_allocator.preview_plan(preservation_plan, shelter, {})
	_expect(not preview.has("casualty_range") and not preview.has("possible_zone_ids"), "无预测预览字典泄露了伤亡或受灾区域")
	_expect(is_equal_approx(preview["occupancy"]["life_support_people"], 5.0), "档案或样机错误占用了人口生命保障名额")
	var duplicate_plan := preservation_plan.duplicate(true)
	duplicate_plan["records"][0]["id"] = "people:test"
	_expect(not GameState.preservation_allocator.validate_plan(duplicate_plan, shelter).get("success", true), "同一对象可在保存方案中重复占位")


func _test_degradation_and_restore() -> void:
	var shock := {
		"source_id": "test:knowledge_shock",
		"node_ids": ["symbolic_record"],
		"living_loss": 1.0,
		"record_loss": 1.0,
		"practice_loss": 1.0,
	}
	GameState.knowledge_system.apply_knowledge_shock(shock)
	_expect(GameState.knowledge_system.get_node_state("symbolic_record") == KnowledgeSystemScript.KnowledgeState.DEGRADED, "活态、记录与实践断裂后知识未退化")
	_expect(not GameState.knowledge_system.has_capability("symbolic_recording"), "退化知识仍提供工程能力")
	GameState.knowledge_system.apply_teaching_result({"node_id": "symbolic_record", "living_gain": 0.3, "practice_gain": 0.3})
	_expect(GameState.knowledge_system.get_node_state("symbolic_record") == KnowledgeSystemScript.KnowledgeState.APPLIED, "教师与实践共同恢复后未回到原峰值状态")


func _test_legacy_migration() -> void:
	var migrated = KnowledgeSystemScript.new()
	migrated.migrate_legacy_technology({"unlocked": ["telescope", "computer"]})
	_expect(migrated.get_node_state("optical_observation") == KnowledgeSystemScript.KnowledgeState.APPLIED, "旧望远镜科技没有迁移到光学观测")
	_expect(migrated.get_node_state("measurement") == KnowledgeSystemScript.KnowledgeState.APPLIED, "旧科技迁移没有补齐最低基础知识链")
	_expect(migrated.has_capability("telescope") and migrated.has_capability("computer"), "旧存档迁移丢失已有设施能力")


func _test_persistence() -> void:
	var saved := GameState.to_dict()
	_expect(saved.has("knowledge") and saved.has("research_projects") and saved.has("education") and saved.has("preservation_plan"), "知识体系存档区段不完整")
	_expect(GameState.from_dict(saved), "知识体系存档无法读取")
	_expect(GameState.knowledge_system.get_node_state("symbolic_record") == KnowledgeSystemScript.KnowledgeState.APPLIED, "知识节点状态存档往返失败")
	_expect(GameState.knowledge_policy_system.active_policy_ids.has("designated_storytellers"), "知识政策存档往返失败")
	_expect(GameState.education_system.plans.has("plan:test:oral"), "教学计划存档往返失败")


func _expect(p_condition: bool, p_message: String) -> void:
	if p_condition:
		return
	_failures += 1
	push_error(p_message)
