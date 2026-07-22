extends Control
## Knowledge institutions, teaching jobs, carrier priorities, and shelter allocation facts.

const DOMAIN_NAMES: Dictionary = {
	"memory": "社会记忆", "measurement": "数学测量", "materials": "工具材料", "energy": "工程能源",
	"astronomy": "天文航天", "life": "生命环境", "survival": "生存庇护", "natural_law": "自然规律", "engineering": "复杂工程",
}

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
	%StartTeachingButton.pressed.connect(_on_start_teaching)
	%PreviewPreservationButton.pressed.connect(_on_preview_preservation)
	_setup_static_controls()
	_rebuild_policy_list()
	_rebuild_teaching_nodes()
	_refresh_status()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		GameState.toggle_pause()
		_show_message("模拟已暂停" if GameState.paused else "模拟已继续", true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _setup_static_controls() -> void:
	var policy = GameState.knowledge_policy_system
	%PrioritySlider.value = policy.knowledge_priority
	%TeacherWeight.value = policy.carrier_weights["teachers"]
	%LearnerWeight.value = policy.carrier_weights["learners"]
	%RecordWeight.value = policy.carrier_weights["records"]
	%ArtifactWeight.value = policy.carrier_weights["artifacts"]
	%CrisisPosture.clear()
	for item in [["生命优先", "life_first"], ["均衡", "balanced"], ["知识优先", "knowledge_first"], ["自定义", "custom"]]:
		%CrisisPosture.add_item(item[0])
		%CrisisPosture.set_item_metadata(%CrisisPosture.item_count - 1, item[1])
		if item[1] == policy.crisis_posture:
			%CrisisPosture.select(%CrisisPosture.item_count - 1)
	for child in %DomainWeights.get_children():
		child.queue_free()
	_domain_sliders.clear()
	for domain in policy.domain_weights:
		var label := Label.new()
		label.text = DOMAIN_NAMES.get(domain, domain)
		%DomainWeights.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 5.0
		slider.step = 0.1
		slider.value = policy.domain_weights[domain]
		slider.value_changed.connect(_on_domain_weight_changed.bind(domain))
		%DomainWeights.add_child(slider)
		_domain_sliders[domain] = slider


func _rebuild_policy_list() -> void:
	for child in %PolicyList.get_children():
		child.queue_free()
	for policy_value in GameState.knowledge_policy_system.get_visible_policies():
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
	%StartTeachingButton.disabled = %TeachingNodeOption.item_count == 0


func _refresh_status() -> void:
	var retention: Dictionary = GameState.knowledge_policy_system.get_retention_context()
	%PriorityValue.text = "%.0f / 100" % GameState.knowledge_policy_system.knowledge_priority
	%RetentionLabel.text = "制度保留条件\n教学覆盖 %.0f%%\n记录维护 %.0f%%\n实践维持 %.0f%%\n\n当前教学计划 %d 项，占用 %d 人" % [
		float(retention.get("education_coverage", 0.0)) * 100.0,
		float(retention.get("record_retention", 0.0)) * 100.0,
		float(retention.get("practice_retention", 0.0)) * 100.0,
		GameState.education_system.plans.size(), GameState.education_system.get_reserved_workers(),
	]


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
	if %TeachingNodeOption.selected < 0:
		return
	var node_id := str(%TeachingNodeOption.get_item_metadata(%TeachingNodeOption.selected))
	var sequence: int = GameState.education_system.plans.size() + GameState.education_system.completed_plan_ids.size() + 1
	var plan := {
		"plan_id": "plan:%s:%03d" % [node_id, sequence],
		"node_id": node_id,
		"curriculum_id": node_id,
		"teacher_count": int(%TeacherCount.value),
		"student_count": int(%StudentCount.value),
		"hours_per_day": %TeachingHours.value,
		"material_allocation": {},
		"facility_ids": [],
		"practice_building_ids": [],
		"emergency_course": %EmergencyCourse.button_pressed,
	}
	var preview: Dictionary = GameState.education_system.preview_plan(plan)
	var result: Dictionary = GameState.start_teaching_plan(plan)
	_show_message("%s（每日损失 %.0f 工时）" % [result.get("message", ""), preview.get("production_hours_lost", 0.0)], result.get("success", false))
	_refresh_status()


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
	var forecast_text := "未知（文明尚不能量化结果）"
	if preview.has("casualty_range"):
		forecast_text = str(preview["casualty_range"])
	elif preview.has("risk_trend"):
		forecast_text = "定性风险：%s" % preview["risk_trend"]
	%PreservationPreview.text = "确定装载事实\n床位 %.0f / %.0f\n生命保障 %.0f / %.0f\n干燥档案 %.1f / %.1f m³\n重物 %.0f / %.0f kg\n容量瓶颈：%s\n预计伤亡：%s" % [
		occupancy.get("berths", 0.0), capacity.get("berths", 0.0),
		occupancy.get("life_support_people", 0.0), capacity.get("life_support_people", 0.0),
		occupancy.get("dry_archive_volume_m3", 0.0), capacity.get("dry_archive_volume_m3", 0.0),
		occupancy.get("heavy_storage_mass_kg", 0.0), capacity.get("heavy_storage_mass_kg", 0.0),
		"无" if preview.get("capacity_bottlenecks", []).is_empty() else ", ".join(preview["capacity_bottlenecks"]),
		forecast_text,
	]


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
