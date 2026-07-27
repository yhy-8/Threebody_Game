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
	%ResponsePriorityOption.item_selected.connect(_on_response_priority_changed)
	%CommitResponseButton.pressed.connect(_on_commit_response)
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
	var preservation_available := false
	for building in GameState.entities.buildings:
		if (
			not building.destroyed
			and not building.under_construction
			and building.building_type in ["shelter", "deep_shelter"]
		):
			preservation_available = true
			break
	%PreservationSection.visible = preservation_available
	%ResponsePriorityOption.clear()
	if not preservation_available or GameState.environmental_hazard_system == null:
		return
	var committed_priority := str(
		GameState.environmental_hazard_system.response_plan.get("priority", "balanced")
	)
	for profile_value in GameState.environmental_hazard_system.get_response_profiles():
		var profile: Dictionary = profile_value
		%ResponsePriorityOption.add_item(str(profile.get("name", profile.get("id", ""))))
		%ResponsePriorityOption.set_item_metadata(
			%ResponsePriorityOption.item_count - 1, str(profile.get("id", ""))
		)
		if str(profile.get("id", "")) == committed_priority:
			%ResponsePriorityOption.select(%ResponsePriorityOption.item_count - 1)
	_refresh_preservation_preview()


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
	_rebuild_teaching_plan_list()
	_refresh_preservation_preview()


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


func _rebuild_teaching_plan_list() -> void:
	for child in %TeachingPlansList.get_children():
		child.queue_free()
	if GameState.education_system.plans.is_empty():
		var empty_label := Label.new()
		empty_label.text = "当前没有教学计划。"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		%TeachingPlansList.add_child(empty_label)
		return
	for plan_id in GameState.education_system.plans:
		var plan: Dictionary = GameState.education_system.plans[plan_id]
		var card := PanelContainer.new()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var node_view: Dictionary = GameState.knowledge_system.get_node_view(str(plan.get("node_id", "")))
		var method: Dictionary = GameState.education_system.METHOD_DEFINITIONS.get(
			str(plan.get("method_id", "")), {}
		)
		var plan_status := "运行中"
		if bool(plan.get("paused", false)):
			plan_status = "已暂停"
		elif not str(plan.get("pause_reason", "")).is_empty():
			plan_status = "受阻：%s" % plan.get("pause_reason", "")
		label.text = "%s · %s · %s\n教师 %d · 学习者 %d · 已运行 %.1f 天" % [
			node_view.get("display_name", plan.get("node_id", "")),
			method.get("name", plan.get("method_id", "")),
			plan_status,
			plan.get("teacher_count", 0),
			plan.get("student_count", 0),
			plan.get("progress_days", 0.0),
		]
		row.add_child(label)
		var pause_button := Button.new()
		pause_button.text = "继续" if bool(plan.get("paused", false)) else "暂停"
		pause_button.pressed.connect(_toggle_teaching_plan.bind(str(plan_id)))
		row.add_child(pause_button)
		var cancel_button := Button.new()
		cancel_button.text = "取消"
		cancel_button.tooltip_text = "取消不会回滚已经形成的传承进度"
		cancel_button.pressed.connect(_cancel_teaching_plan.bind(str(plan_id)))
		row.add_child(cancel_button)
		%TeachingPlansList.add_child(card)


func _toggle_teaching_plan(p_plan_id: String) -> void:
	var result: Dictionary = GameState.toggle_teaching_plan(p_plan_id)
	_show_message(str(result.get("message", "")), bool(result.get("success", false)))
	_refresh_status()


func _cancel_teaching_plan(p_plan_id: String) -> void:
	var result: Dictionary = GameState.cancel_teaching_plan(p_plan_id)
	_show_message(str(result.get("message", "")), bool(result.get("success", false)))
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


func _on_response_priority_changed(_p_index: int) -> void:
	_refresh_preservation_preview()


func _selected_response_priority() -> String:
	if %ResponsePriorityOption.selected < 0:
		return ""
	return str(%ResponsePriorityOption.get_item_metadata(%ResponsePriorityOption.selected))


func _refresh_preservation_preview() -> void:
	if (
		not is_node_ready()
		or not %PreservationSection.visible
		or GameState.environmental_hazard_system == null
	):
		return
	var system = GameState.environmental_hazard_system
	var priority := _selected_response_priority()
	var response_preview: Dictionary = system.preview_response_priority(
		priority, GameState.entities, GameState.settlement_system
	)
	var profile: Dictionary = response_preview.get("profile", {})
	var plan_view: Dictionary = system.get_response_plan_view(
		GameState.entities, GameState.settlement_system
	)
	var preview_allocations: Dictionary = response_preview.get("allocations", {})
	var lines: Array[String] = [
		str(profile.get("description", "选择危机期间人口与知识载体的保存优先级。")),
		"",
		"当前可验证容量（只计已完工、供能、配员设施）",
	]
	var total_population := 0
	var total_capacity := 0
	var total_protected := 0
	for allocation_value in preview_allocations.values():
		var allocation: Dictionary = allocation_value
		total_population += int(allocation.get("population", 0))
		total_capacity += int(allocation.get("operating_shelter_capacity", 0))
		total_protected += int(allocation.get("planned_protected_people", 0))
		lines.append("区域 #%d：人口 %d · 运行容量 %d · 计划保护 %d" % [
			allocation.get("zone_id", -1),
			allocation.get("population", 0),
			allocation.get("operating_shelter_capacity", 0),
			allocation.get("planned_protected_people", 0),
		])
	lines.append("合计：人口 %d · 运行容量 %d · 按此优先级保护 %d" % [
		total_population, total_capacity, total_protected,
	])
	if bool(plan_view.get("committed", false)):
		lines.append("已确认预案：%s（提交于第 %.1f 天）" % [
			plan_view.get("priority_name", ""),
			plan_view.get("committed_game_day", 0.0),
		])
	else:
		lines.append("尚未确认预案；临时避险只能利用少量可用容量。")
	var active_hazard: Dictionary = system.active_hazard
	if not active_hazard.is_empty():
		lines.append("环境危机进行中：预案已经锁定，结束前不能改写。")
	%PreservationPreview.text = "\n".join(lines)
	%CommitResponseButton.disabled = total_capacity <= 0 or not active_hazard.is_empty()
	%CommitResponseButton.text = "危机中已锁定" if not active_hazard.is_empty() else "确认并承诺该预案"


func _on_commit_response() -> void:
	var result: Dictionary = GameState.commit_hazard_response(_selected_response_priority())
	_show_message(str(result.get("message", "")), bool(result.get("success", false)))
	_refresh_preservation_preview()


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
