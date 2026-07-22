extends Control
## Knowledge institutions, teaching jobs, carrier priorities, and shelter allocation facts.

const DOMAIN_NAMES: Dictionary = {
	"memory": "社会记忆", "measurement": "数学测量", "materials": "工具材料", "energy": "工程能源",
	"astronomy": "天文航天", "life": "生命环境", "survival": "生存庇护", "natural_law": "自然规律", "engineering": "复杂工程",
}
const TEACHING_INTENSITIES: Array[Dictionary] = [
	{"id": "light", "name": "轻度维持", "population_share": 0.03, "hours": 2.0, "emergency": false},
	{"id": "normal", "name": "常规传承", "population_share": 0.08, "hours": 4.0, "emergency": false},
	{"id": "strong", "name": "重点普及", "population_share": 0.15, "hours": 6.0, "emergency": false},
	{"id": "crisis", "name": "危机抢救", "population_share": 0.20, "hours": 8.0, "emergency": true},
]

var _domain_sliders: Dictionary = {}


func _ready() -> void:
	EventBus.screen_changed.emit("knowledge_policy")
	%BackButton.pressed.connect(_on_back_pressed)
	%PrioritySlider.value_changed.connect(_on_priority_changed)
	%TeacherWeight.value_changed.connect(_on_carrier_changed.bind("teachers"))
	%LearnerWeight.value_changed.connect(_on_carrier_changed.bind("learners"))
	%RecordWeight.value_changed.connect(_on_carrier_changed.bind("records"))
	%ArtifactWeight.value_changed.connect(_on_carrier_changed.bind("artifacts"))
	%CrisisPosture.item_selected.connect(_on_crisis_posture_selected)
	%TeachingNodeOption.item_selected.connect(_on_teaching_selection_changed)
	%TeachingMethodOption.item_selected.connect(_on_teaching_selection_changed)
	%TeachingIntensityOption.item_selected.connect(_on_teaching_selection_changed)
	%StartTeachingButton.pressed.connect(_on_start_teaching)
	%PreviewPreservationButton.pressed.connect(_on_preview_preservation)
	EventBus.game_paused.connect(_on_global_pause_changed)
	_setup_static_controls()
	_rebuild_policy_list()
	_rebuild_teaching_nodes()
	_refresh_status()


func _on_global_pause_changed(p_paused: bool) -> void:
	_show_message("模拟已暂停" if p_paused else "模拟已继续", true)


func _setup_static_controls() -> void:
	var policy = GameState.knowledge_policy_system
	%PrioritySlider.value = policy.knowledge_priority
	%TeacherWeight.value = policy.carrier_weights["teachers"]
	%LearnerWeight.value = policy.carrier_weights["learners"]
	%RecordWeight.value = policy.carrier_weights["records"]
	%ArtifactWeight.value = policy.carrier_weights["artifacts"]
	var has_oral_teaching: bool = GameState.knowledge_system.has_capability("oral_teaching")
	var has_records: bool = GameState.knowledge_system.has_capability("symbolic_recording")
	var has_artifacts: bool = GameState.knowledge_system.has_capability("hand_tools")
	_set_control_pair_visible(%TeacherLabel, %TeacherWeight, has_oral_teaching)
	_set_control_pair_visible(%LearnerLabel, %LearnerWeight, has_oral_teaching)
	_set_control_pair_visible(%RecordLabel, %RecordWeight, has_records)
	_set_control_pair_visible(%ArtifactLabel, %ArtifactWeight, has_artifacts)
	%CrisisPosture.clear()
	for item in [["生命优先", "life_first"], ["均衡", "balanced"], ["知识优先", "knowledge_first"], ["自定义", "custom"]]:
		%CrisisPosture.add_item(item[0])
		%CrisisPosture.set_item_metadata(%CrisisPosture.item_count - 1, item[1])
		if item[1] == policy.crisis_posture:
			%CrisisPosture.select(%CrisisPosture.item_count - 1)
	for child in %DomainWeights.get_children():
		child.queue_free()
	_domain_sliders.clear()
	var visible_domains: Array[String] = []
	for view_value in GameState.knowledge_system.get_visible_nodes():
		var domain := str((view_value as Dictionary).get("domain", ""))
		if not domain.is_empty() and domain not in visible_domains:
			visible_domains.append(domain)
	visible_domains.sort()
	for domain in visible_domains:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var label := Label.new()
		label.text = DOMAIN_NAMES.get(domain, domain)
		label.custom_minimum_size.x = 116.0
		row.add_child(label)
		var slider := HSlider.new()
		slider.custom_minimum_size.x = 190.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.min_value = 0.0
		slider.max_value = 5.0
		slider.step = 0.1
		slider.value = policy.domain_weights[domain]
		slider.value_changed.connect(_on_domain_weight_changed.bind(domain))
		row.add_child(slider)
		%DomainWeights.add_child(row)
		_domain_sliders[domain] = slider
	%DomainTitle.visible = not visible_domains.is_empty()
	%DomainWeights.visible = not visible_domains.is_empty()
	var preservation_available := not _get_shelter_snapshots().is_empty()
	%CrisisLabel.visible = preservation_available
	%CrisisPosture.visible = preservation_available
	%PreservationSection.visible = preservation_available
	%PreservationSection.get_node("ArchiveVolumeLabel").visible = has_records
	%ArchiveVolume.visible = has_records
	%PreservationSection.get_node("ArtifactMassLabel").visible = has_artifacts
	%ArtifactMass.visible = has_artifacts


func _rebuild_policy_list() -> void:
	for child in %PolicyList.get_children():
		child.queue_free()
	var visible_policies: Array = GameState.knowledge_policy_system.get_visible_policies()
	%PolicyPanel.visible = not visible_policies.is_empty()
	for policy_value in visible_policies:
		var definition: Dictionary = policy_value
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0.0, 86.0)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var text := Label.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.text = "%s\n%s" % [definition.get("name", ""), _branch_name(str(definition.get("branch", "")))]
		row.add_child(text)
		var button := Button.new()
		button.custom_minimum_size = Vector2(112.0, 52.0)
		button.text = "已采用" if definition.get("active", false) else "采用"
		button.disabled = definition.get("active", false)
		button.pressed.connect(_on_adopt_policy.bind(str(definition.get("id", ""))))
		row.add_child(button)
		%PolicyList.add_child(card)


func _rebuild_teaching_nodes() -> void:
	%TeachingNodeOption.clear()
	for view_value in GameState.knowledge_system.get_visible_nodes():
		var view: Dictionary = view_value
		if int(view.get("state", 0)) not in [GameState.knowledge_system.KnowledgeState.MASTERED, GameState.knowledge_system.KnowledgeState.APPLIED]:
			continue
		%TeachingNodeOption.add_item(str(view.get("display_name", view.get("id", ""))))
		%TeachingNodeOption.set_item_metadata(%TeachingNodeOption.item_count - 1, view.get("id", ""))
	_rebuild_teaching_methods()
	%TeachingIntensityOption.clear()
	for intensity in TEACHING_INTENSITIES:
		%TeachingIntensityOption.add_item(str(intensity["name"]))
		%TeachingIntensityOption.set_item_metadata(%TeachingIntensityOption.item_count - 1, intensity["id"])
	%TeachingIntensityOption.select(1)
	%TeachingSection.visible = %TeachingNodeOption.item_count > 0 and %TeachingMethodOption.item_count > 0
	%ActionPanel.visible = %TeachingSection.visible or %PreservationSection.visible
	_refresh_teaching_preview()


func _rebuild_teaching_methods() -> void:
	%TeachingMethodOption.clear()
	var methods: Array[Dictionary] = []
	if GameState.knowledge_system.has_capability("oral_teaching"):
		methods.append({"id": "oral", "name": "口耳相传", "class_size": 4})
	if GameState.knowledge_system.has_capability("symbolic_recording"):
		methods.append({"id": "record_assisted", "name": "记录辅助传习", "class_size": 7})
	if GameState.knowledge_system.has_capability("organized_education"):
		methods.append({"id": "organized", "name": "固定课程", "class_size": 10})
	if GameState.knowledge_system.has_capability("professional_education") and _has_operating_academy():
		methods.append({"id": "professional", "name": "专业院校教育", "class_size": 16})
	for method in methods:
		%TeachingMethodOption.add_item(str(method["name"]))
		%TeachingMethodOption.set_item_metadata(%TeachingMethodOption.item_count - 1, method)


func _refresh_status() -> void:
	var retention: Dictionary = GameState.knowledge_policy_system.get_retention_context()
	%PriorityValue.text = "%.0f / 100" % GameState.knowledge_policy_system.knowledge_priority
	var lines: Array[String] = ["制度保留条件"]
	if GameState.knowledge_system.has_capability("oral_teaching"):
		lines.append("教学覆盖 %.0f%%" % (float(retention.get("education_coverage", 0.0)) * 100.0))
	if GameState.knowledge_system.has_capability("symbolic_recording"):
		lines.append("记录维护 %.0f%%" % (float(retention.get("record_retention", 0.0)) * 100.0))
	if GameState.knowledge_system.has_capability("hand_tools"):
		lines.append("实践维持 %.0f%%" % (float(retention.get("practice_retention", 0.0)) * 100.0))
	lines.append("")
	lines.append("当前教学计划 %d 项，占用 %d 人" % [GameState.education_system.plans.size(), GameState.education_system.get_reserved_workers()])
	%RetentionLabel.text = "\n".join(lines)
	_refresh_teaching_preview()


func _on_priority_changed(p_value: float) -> void:
	GameState.knowledge_policy_system.set_knowledge_priority(p_value)
	_refresh_status()


func _on_carrier_changed(p_value: float, p_carrier_id: String) -> void:
	GameState.knowledge_policy_system.set_carrier_weight(p_carrier_id, p_value)


func _on_domain_weight_changed(p_value: float, p_domain_id: String) -> void:
	GameState.knowledge_policy_system.set_domain_weight(p_domain_id, p_value)


func _on_crisis_posture_selected(p_index: int) -> void:
	GameState.knowledge_policy_system.set_crisis_posture(str(%CrisisPosture.get_item_metadata(p_index)))


func _on_adopt_policy(p_policy_id: String) -> void:
	var result: Dictionary = GameState.adopt_knowledge_policy(p_policy_id)
	_show_message(result.get("message", ""), result.get("success", false))
	_rebuild_policy_list()
	_refresh_status()


func _on_start_teaching() -> void:
	var plan := _derive_teaching_plan()
	if plan.is_empty():
		_show_message("当前没有足够闲置人口开展教学", false)
		return
	var preview: Dictionary = GameState.education_system.preview_plan(plan)
	var result: Dictionary = GameState.start_teaching_plan(plan)
	_show_message("%s（每日损失 %.0f 工时）" % [result.get("message", ""), preview.get("production_hours_lost", 0.0)], result.get("success", false))
	_refresh_status()


func _on_teaching_selection_changed(_p_index: int) -> void:
	_refresh_teaching_preview()


func _derive_teaching_plan() -> Dictionary:
	if %TeachingNodeOption.selected < 0 or %TeachingMethodOption.selected < 0 or %TeachingIntensityOption.selected < 0:
		return {}
	var idle: int = GameState.entities.get_idle_population()
	if idle < 2:
		return {}
	var node_id := str(%TeachingNodeOption.get_item_metadata(%TeachingNodeOption.selected))
	var method: Dictionary = %TeachingMethodOption.get_item_metadata(%TeachingMethodOption.selected)
	var intensity_id := str(%TeachingIntensityOption.get_item_metadata(%TeachingIntensityOption.selected))
	var intensity: Dictionary = TEACHING_INTENSITIES[0]
	for candidate in TEACHING_INTENSITIES:
		if candidate["id"] == intensity_id:
			intensity = candidate
			break
	var students := maxi(1, int(floor(GameState.entities.population.total * float(intensity["population_share"]))))
	var class_size := maxi(1, int(method.get("class_size", 4)))
	var teachers := maxi(1, int(ceil(float(students) / class_size)))
	while students > 0 and students + teachers > idle:
		students -= 1
		teachers = maxi(1, int(ceil(float(students) / class_size)))
	if students <= 0 or students + teachers > idle:
		return {}
	var sequence: int = GameState.education_system.plans.size() + GameState.education_system.completed_plan_ids.size() + 1
	return {
		"plan_id": "plan:%s:%03d" % [node_id, sequence],
		"node_id": node_id,
		"curriculum_id": node_id,
		"method_id": method.get("id", "oral"),
		"intensity_id": intensity_id,
		"teacher_count": teachers,
		"student_count": students,
		"hours_per_day": float(intensity["hours"]),
		"material_allocation": {},
		"facility_ids": _get_operating_academy_ids() if method.get("id", "") == "professional" else [],
		"practice_building_ids": [],
		"emergency_course": bool(intensity["emergency"]),
	}


func _refresh_teaching_preview() -> void:
	if not is_node_ready() or not %TeachingSection.visible:
		return
	var plan := _derive_teaching_plan()
	if plan.is_empty():
		%TeachingAllocationPreview.text = "闲置人口不足，当前无法形成教学群体。"
		%StartTeachingButton.disabled = true
		return
	var preview: Dictionary = GameState.education_system.preview_plan(plan)
	%TeachingAllocationPreview.text = "系统将按宏观目标组织 %d 名教师与 %d 名学习者，每日 %.0f 小时；约占用 %.0f 人时/天。" % [
		plan["teacher_count"], plan["student_count"], plan["hours_per_day"], preview.get("production_hours_lost", 0.0),
	]
	%StartTeachingButton.disabled = false


func _has_operating_academy() -> bool:
	return not _get_operating_academy_ids().is_empty()


func _get_operating_academy_ids() -> Array:
	var result: Array = []
	for building in GameState.entities.buildings:
		if building.building_type == "academy" and building.active and not building.destroyed and not building.under_construction:
			result.append(building.id)
	return result


func _set_control_pair_visible(p_label: Control, p_control: Control, p_visible: bool) -> void:
	p_label.visible = p_visible
	p_control.visible = p_visible


func _on_preview_preservation() -> void:
	var plan := {
		"plan_id": "preview:current",
		"people": [{"id": "group:population", "count": int(%ShelterPeople.value), "role": "ordinary", "supply_days": 30.0}],
		"records": [{"id": "archive:knowledge", "dry_volume_m3": %ArchiveVolume.value, "power_kw": 0.0}],
		"artifacts": [{"id": "artifact:tools", "volume_m3": %ArtifactMass.value / 500.0, "mass_kg": %ArtifactMass.value, "power_kw": 0.0}],
		"unplaced_objects": [],
	}
	var shelters := _get_shelter_snapshots()
	var preview: Dictionary = GameState.preservation_allocator.preview_plan(plan, shelters, GameState.hazard_forecast_service.get_public_snapshot())
	var capacity: Dictionary = preview.get("capacity", {})
	var occupancy: Dictionary = preview.get("occupancy", {})
	var forecast_text := ""
	if preview.has("casualty_range"):
		forecast_text = str(preview["casualty_range"])
	elif preview.has("risk_trend"):
		forecast_text = "定性风险：%s" % preview["risk_trend"]
	var lines: Array[String] = [
		"确定装载事实",
		"床位 %.0f / %.0f" % [occupancy.get("berths", 0.0), capacity.get("berths", 0.0)],
		"生命保障 %.0f / %.0f" % [occupancy.get("life_support_people", 0.0), capacity.get("life_support_people", 0.0)],
	]
	if %ArchiveVolume.visible:
		lines.append("干燥档案 %.1f / %.1f m³" % [occupancy.get("dry_archive_volume_m3", 0.0), capacity.get("dry_archive_volume_m3", 0.0)])
	if %ArtifactMass.visible:
		lines.append("重物 %.0f / %.0f kg" % [occupancy.get("heavy_storage_mass_kg", 0.0), capacity.get("heavy_storage_mass_kg", 0.0)])
	lines.append("容量瓶颈：%s" % ("无" if preview.get("capacity_bottlenecks", []).is_empty() else ", ".join(preview["capacity_bottlenecks"])))
	if not forecast_text.is_empty():
		lines.append("预计影响：%s" % forecast_text)
	%PreservationPreview.text = "\n".join(lines)


func _get_shelter_snapshots() -> Array:
	var result: Array = []
	for building in GameState.entities.buildings:
		if building.destroyed or building.under_construction or building.building_type not in ["shelter", "deep_shelter"]:
			continue
		var deep: bool = building.building_type == "deep_shelter"
		result.append({
			"shelter_id": "building:%d" % building.id,
			"usable_volume_m3": 1200.0 if deep else 280.0,
			"berths": 200 if deep else 50,
			"life_support_people": 180 if deep else 40,
			"food_water_person_days": 5400.0 if deep else 1200.0,
			"dry_archive_volume_m3": 80.0 if deep else 12.0,
			"heavy_storage_mass_kg": 20000.0 if deep else 2500.0,
			"continuous_power_kw": 20.0 if deep else 3.0,
			"environment_control_level": 0.8 if deep else 0.35,
		})
	return result


func _branch_name(p_branch: String) -> String:
	return {"education": "教育与教学", "recording": "记录与复制", "preservation": "危机保存", "recovery": "灾后恢复"}.get(p_branch, p_branch)


func _show_message(p_text: String, p_success: bool) -> void:
	%MessageLabel.text = p_text
	%MessageLabel.modulate = Color(0.55, 1.0, 0.65) if p_success else Color(1.0, 0.5, 0.4)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/tech_tree/tech_tree.tscn")
