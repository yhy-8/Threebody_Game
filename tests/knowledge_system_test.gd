extends Node
## Knowledge lifecycle, discovery, projects, inheritance, policies, preservation, and persistence.

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
	var paused: Dictionary = GameState.toggle_knowledge_research("symbolic_record")
	_expect(
		paused.get("success", false)
		and GameState.entities.external_reserved_workers == 0
		and "symbolic_record" in GameState.research_project_system.get_unfinished_project_ids(),
		"暂停研究没有释放人员，或错误释放了仍应占用的项目槽",
	)
	var resumed: Dictionary = GameState.toggle_knowledge_research("symbolic_record")
	_expect(
		resumed.get("success", false)
		and GameState.entities.external_reserved_workers == 2,
		"继续研究没有重新校验并占用真实劳动力",
	)
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
	var retention_before: Dictionary = GameState.knowledge_policy_system.get_retention_context()
	_expect(is_zero_approx(float(retention_before.get("education_coverage", -1.0))), "没有实际制度与教学却获得免费传承率")
	var idle_before_policy: int = GameState.entities.get_idle_population()
	var policy_result: Dictionary = GameState.adopt_knowledge_policy("designated_storytellers")
	_expect(policy_result.get("success", false), "已具备口述能力却无法筹建指定讲述者制度")
	_expect(
		GameState.entities.get_idle_population() == idle_before_policy - 1
		and "designated_storytellers" not in GameState.knowledge_policy_system.active_policy_ids,
		"制度筹建没有占用组织人员，或未经实施时间直接生效",
	)
	GameState.knowledge_policy_system.update_day(3.0)
	GameState._refresh_external_workforce_reservation()
	_expect(
		"designated_storytellers" in GameState.knowledge_policy_system.active_policy_ids
		and float(GameState.knowledge_policy_system.get_retention_context().get("education_coverage", 0.0)) > 0.0,
		"制度完成筹建后没有进入持续占岗的运行状态",
	)
	_expect(GameState.knowledge_system.get_node_state("celestial_motion") == before_state, "制度错误地直接改变了知识节点状态")
	var teachable_ids: Array = GameState.education_system.get_teachable_node_views().map(func(view): return view["id"])
	_expect("oral_tradition" not in teachable_ids and "simple_counting" in teachable_ids, "教学课程把传承制度本身当成了知识内容")
	var plan: Dictionary = GameState.education_system.derive_plan(
		"simple_counting", "oral", "routine", GameState.entities
	)
	_expect(not plan.is_empty(), "模拟层无法从课程、组织方式和投入级别推导教学计划")
	var forged := plan.duplicate(true)
	forged["method_id"] = "professional"
	_expect(not GameState.education_system.validate_plan(forged, GameState.entities).get("success", true), "教学后端允许 UI 绕过专业教育能力和设施")
	var idle_before: int = GameState.entities.get_idle_population()
	var teaching: Dictionary = GameState.start_teaching_plan(plan)
	_expect(teaching.get("success", false), "合法教学计划无法开始")
	_expect(
		GameState.entities.get_idle_population() == idle_before - int(plan["teacher_count"]) - int(plan["student_count"]),
		"教师与学习者没有和生产岗位竞争劳动力",
	)
	GameState.education_system.plans[str(plan["plan_id"])]["pause_reason"] = "测试设施停运"
	_expect(
		GameState.education_system.get_reserved_workers() > 0
		and GameState.education_system.get_running_workers() == 0,
		"设施受阻的等待人员仍被算作实际教学覆盖",
	)
	GameState.education_system.plans[str(plan["plan_id"])]["pause_reason"] = ""
	var pause_teaching: Dictionary = GameState.toggle_teaching_plan(str(plan["plan_id"]))
	_expect(
		pause_teaching.get("success", false)
		and GameState.entities.get_idle_population() == idle_before,
		"暂停教学没有让教师与学习者回到闲置人口",
	)
	var resume_teaching: Dictionary = GameState.toggle_teaching_plan(str(plan["plan_id"]))
	_expect(
		resume_teaching.get("success", false)
		and GameState.entities.get_idle_population()
		== idle_before - int(plan["teacher_count"]) - int(plan["student_count"]),
		"继续教学没有重新占用真实教师与学习者",
	)
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


func _test_persistence() -> void:
	var saved := GameState.to_dict()
	_expect(saved.has("knowledge") and saved.has("research_projects") and saved.has("education") and saved.has("preservation_plan"), "知识体系存档区段不完整")
	_expect(GameState.from_dict(saved), "知识体系存档无法读取")
	_expect(GameState.knowledge_system.get_node_state("symbolic_record") == KnowledgeSystemScript.KnowledgeState.APPLIED, "知识节点状态存档往返失败")
	_expect(GameState.knowledge_policy_system.active_policy_ids.has("designated_storytellers"), "知识政策存档往返失败")
	_expect(not GameState.education_system.plans.is_empty(), "教学计划存档往返失败")


func _expect(p_condition: bool, p_message: String) -> void:
	if p_condition:
		return
	_failures += 1
	push_error(p_message)
