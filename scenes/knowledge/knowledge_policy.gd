extends Control
## Knowledge institutions, teaching jobs, and shelter allocation facts.

var _refresh_elapsed: float = 0.0
var _policy_signature: String = ""


func _ready() -> void:
	EventBus.screen_changed.emit("knowledge_policy")
	%BackButton.pressed.connect(_on_back_pressed)
	%TeachingNodeOption.item_selected.connect(_on_teaching_target_changed)
	%TeachingMethodOption.item_selected.connect(_on_teaching_selection_changed)
	%TeachingIntensityOption.item_selected.connect(_on_teaching_selection_changed)
	%StartTeachingButton.pressed.connect(_on_start_teaching)
	%PreviewPreservationButton.pressed.connect(_on_preview_preservation)
	EventBus.game_paused.connect(_on_global_pause_changed)
	_setup_preservation_controls()
	_refresh_policy_display(true)
	_rebuild_teaching_nodes()
	_refresh_status()


func _process(p_delta: float) -> void:
	_refresh_elapsed += p_delta
	if _refresh_elapsed < 0.25:
		return
	_refresh_elapsed = 0.0
	_refresh_policy_display()
	_refresh_status()


func _on_global_pause_changed(p_paused: bool) -> void:
	_show_message("模拟已暂停" if p_paused else "模拟已继续", true)


func _setup_preservation_controls() -> void:
	var has_records: bool = GameState.knowledge_system.has_capability("symbolic_recording")
	var has_artifacts: bool = GameState.knowledge_system.has_capability("hand_tools")
	var preservation_available := not _get_shelter_snapshots().is_empty()
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
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var status := "已运行"
		if definition.get("pending", false):
			status = "筹建 %.0f / %.0f 天" % [definition.get("progress_days", 0.0), definition.get("required_days", 0.0)]
		elif not definition.get("active", false):
			status = "筹建需 %d 人 × %.0f 天；运行维护 %d 人" % [
				definition.get("setup_workers", 0), definition.get("setup_days", 0.0),
				definition.get("operating_workers", 0),
			]
		text.text = "%s · %s\n%s\n%s" % [
			definition.get("name", ""), _branch_name(str(definition.get("branch", ""))),
			definition.get("description", ""), status,
		]
		row.add_child(text)
		var button := Button.new()
		button.custom_minimum_size = Vector2(112.0, 52.0)
		button.text = "已运行" if definition.get("active", false) else ("筹建中" if definition.get("pending", false) else "筹建制度")
		button.disabled = definition.get("active", false) or definition.get("pending", false)
		button.pressed.connect(_on_adopt_policy.bind(str(definition.get("id", ""))))
		row.add_child(button)
		%PolicyList.add_child(card)


func _rebuild_teaching_nodes() -> void:
	%TeachingNodeOption.clear()
	for view_value in GameState.education_system.get_teachable_node_views():
		var view: Dictionary = view_value
		%TeachingNodeOption.add_item(str(view.get("display_name", view.get("id", ""))))
		%TeachingNodeOption.set_item_metadata(%TeachingNodeOption.item_count - 1, view.get("id", ""))
	_rebuild_teaching_methods()
	%TeachingIntensityOption.clear()
	for intensity in GameState.education_system.get_intensities():
		%TeachingIntensityOption.add_item(str(intensity["name"]))
		%TeachingIntensityOption.set_item_metadata(%TeachingIntensityOption.item_count - 1, intensity["id"])
	%TeachingIntensityOption.select(1)
	%TeachingSection.visible = %TeachingNodeOption.item_count > 0 and %TeachingMethodOption.item_count > 0
	%ActionPanel.visible = %TeachingSection.visible or %PreservationSection.visible
	_refresh_teaching_preview()


func _rebuild_teaching_methods() -> void:
	%TeachingMethodOption.clear()
	if %TeachingNodeOption.selected < 0:
		return
	var node_id := str(%TeachingNodeOption.get_item_metadata(%TeachingNodeOption.selected))
	for method in GameState.education_system.get_available_methods(node_id, GameState.entities):
		%TeachingMethodOption.add_item(str(method["name"]))
		%TeachingMethodOption.set_item_metadata(%TeachingMethodOption.item_count - 1, method["id"])


func _refresh_status() -> void:
	var retention: Dictionary = GameState.knowledge_policy_system.get_retention_context()
	var lines: Array[String] = ["制度运行结果（只来自已完成筹建且持续占岗的制度）"]
	if GameState.knowledge_system.has_capability("oral_teaching"):
		lines.append("教学覆盖 %.0f%%" % (float(retention.get("education_coverage", 0.0)) * 100.0))
	if GameState.knowledge_system.has_capability("symbolic_recording"):
		lines.append("记录维护 %.0f%%" % (float(retention.get("record_retention", 0.0)) * 100.0))
	if GameState.knowledge_system.has_capability("hand_tools"):
		lines.append("实践维持 %.0f%%" % (float(retention.get("practice_retention", 0.0)) * 100.0))
	lines.append("")
	lines.append("制度岗位 %d 人 · 教学计划 %d 项 / %d 人" % [
		GameState.knowledge_policy_system.get_reserved_workers(),
		GameState.education_system.plans.size(), GameState.education_system.get_reserved_workers(),
	])
	%InstitutionStatusLabel.text = "\n".join(lines)
	_refresh_teaching_preview()


func _on_adopt_policy(p_policy_id: String) -> void:
	var result: Dictionary = GameState.adopt_knowledge_policy(p_policy_id)
	_show_message(result.get("message", ""), result.get("success", false))
	_refresh_policy_display(true)
	_refresh_status()


func _on_start_teaching() -> void:
	var plan := _derive_teaching_plan()
	if plan.is_empty():
		_show_message("当前人口、能力或设施不足，无法形成该教学计划", false)
		return
	var preview: Dictionary = GameState.education_system.preview_plan(plan)
	var result: Dictionary = GameState.start_teaching_strategy(
		str(plan.get("node_id", "")), str(plan.get("method_id", "")), str(plan.get("intensity_id", ""))
	)
	_show_message("%s（整日岗位机会成本 %.0f 人时/天）" % [result.get("message", ""), preview.get("production_hours_lost", 0.0)], result.get("success", false))
	_refresh_status()


func _on_teaching_target_changed(_p_index: int) -> void:
	_rebuild_teaching_methods()
	_refresh_teaching_preview()


func _on_teaching_selection_changed(_p_index: int) -> void:
	_refresh_teaching_preview()


func _derive_teaching_plan() -> Dictionary:
	if %TeachingNodeOption.selected < 0 or %TeachingMethodOption.selected < 0 or %TeachingIntensityOption.selected < 0:
		return {}
	var node_id := str(%TeachingNodeOption.get_item_metadata(%TeachingNodeOption.selected))
	var method_id := str(%TeachingMethodOption.get_item_metadata(%TeachingMethodOption.selected))
	var intensity_id := str(%TeachingIntensityOption.get_item_metadata(%TeachingIntensityOption.selected))
	return GameState.education_system.derive_plan(node_id, method_id, intensity_id, GameState.entities)


func _refresh_teaching_preview() -> void:
	if not is_node_ready() or not %TeachingSection.visible:
		return
	var plan := _derive_teaching_plan()
	if plan.is_empty():
		%TeachingAllocationPreview.text = "当前人口、能力或设施不足，无法形成该课程与组织方式。"
		%StartTeachingButton.disabled = true
		return
	var preview: Dictionary = GameState.education_system.preview_plan(plan)
	%TeachingAllocationPreview.text = "系统按目标组织 %d 名教师与 %d 名学习者，每日授课 %.0f 小时（共 %.0f 人时）；由于当前人口岗位按整日分配，将锁定 %d 人，等效生产机会成本 %.0f 人时/天。" % [
		plan["teacher_count"], plan["student_count"], plan["hours_per_day"],
		preview.get("scheduled_instruction_hours", 0.0), preview.get("reserved_workers", 0),
		preview.get("production_hours_lost", 0.0),
	]
	%StartTeachingButton.disabled = false


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


func _refresh_policy_display(p_force: bool = false) -> void:
	var parts: Array[String] = []
	for view_value in GameState.knowledge_policy_system.get_visible_policies():
		var view: Dictionary = view_value
		parts.append("%s:%s:%s:%d" % [
			view.get("id", ""), view.get("active", false), view.get("pending", false),
			int(floor(float(view.get("progress_days", 0.0)))),
		])
	var signature := "|".join(parts)
	if p_force or signature != _policy_signature:
		_policy_signature = signature
		_rebuild_policy_list()
