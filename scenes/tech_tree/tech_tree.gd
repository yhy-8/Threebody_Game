extends Control
## Knowledge-evolution screen: discovery, research, engineering, and inheritance risk.

const KnowledgeSystemScript = preload("res://scripts/simulation/knowledge_system.gd")

var _refresh_elapsed: float = 0.0
var _hovered_node_id: String = ""


func _ready() -> void:
	EventBus.screen_changed.emit("knowledge_tree")
	%BackButton.pressed.connect(_on_back_pressed)
	%KnowledgePolicyButton.pressed.connect(_on_knowledge_policy_pressed)
	%TechTreeContainer.node_clicked.connect(_on_node_clicked)
	%TechTreeContainer.node_hovered.connect(_on_node_hovered)
	%DomainFilter.item_selected.connect(_on_domain_selected)
	%SearchInput.text_changed.connect(_on_search_changed)
	%RiskViewButton.toggled.connect(_on_risk_toggled)
	EventBus.game_paused.connect(_on_global_pause_changed)
	_setup_filters()
	_refresh_display()


func _process(p_delta: float) -> void:
	_refresh_elapsed += p_delta
	if _refresh_elapsed >= 0.2:
		_refresh_elapsed = 0.0
		_refresh_display()
		if not _hovered_node_id.is_empty():
			_update_tooltip(_hovered_node_id)


func _on_global_pause_changed(p_paused: bool) -> void:
	_show_message("模拟已暂停" if p_paused else "模拟已继续", true)


func _setup_filters() -> void:
	%DomainFilter.clear()
	%DomainFilter.add_item("全部领域")
	%DomainFilter.set_item_metadata(0, "all")
	var names := {
		"memory": "社会记忆", "measurement": "数学测量", "materials": "工具材料", "energy": "工程能源",
		"astronomy": "天文航天", "life": "生命环境", "survival": "生存庇护", "natural_law": "自然规律", "engineering": "复杂工程",
	}
	for domain in GameState.knowledge_system.graph.get_domains():
		%DomainFilter.add_item(names.get(domain, domain))
		%DomainFilter.set_item_metadata(%DomainFilter.item_count - 1, domain)


func _refresh_display() -> void:
	if not GameState.game_started or GameState.knowledge_system == null:
		return
	var rates: Dictionary = GameState.research_output_rate
	%PointsLabel.text = "研究吞吐：基础 %.2f/天 · 应用 %.2f/天 · 理论 %.2f/天" % [
		rates.get("basic", 0.0), rates.get("applied", 0.0), rates.get("theoretical", 0.0),
	]
	var research_ids: Array = GameState.research_project_system.get_active_project_ids()
	var engineering_ids: Array = GameState.engineering_project_system.get_active_project_ids()
	%ResearchLabel.text = "研究 %d/%d · 工程 %d/%d · 知识岗位 %d 人%s" % [
		research_ids.size(), GameState.research_project_system.MAX_ACTIVE_SLOTS,
		engineering_ids.size(), GameState.engineering_project_system.MAX_ACTIVE_SLOTS,
		GameState.entities.external_reserved_workers,
		" · 已暂停" if GameState.paused else "",
	]
	%TechTreeContainer.queue_redraw()


func _on_node_clicked(p_node_id: String) -> void:
	var view: Dictionary = GameState.knowledge_system.get_node_view(p_node_id)
	if view.is_empty():
		return
	var state := int(view.get("state", 0))
	var result: Dictionary
	match state:
		KnowledgeSystemScript.KnowledgeState.RUMOR:
			result = {"success": false, "message": "这仍是模糊方向；继续真实观察、生产或实验以积累线索。"}
		KnowledgeSystemScript.KnowledgeState.INSIGHT:
			var missing: Dictionary = view.get("missing_evidence", {})
			result = {"success": false, "message": "已理解问题，但仍缺少证据：%s" % _format_missing(missing)}
		KnowledgeSystemScript.KnowledgeState.RESEARCHABLE:
			result = GameState.start_knowledge_research(p_node_id)
		KnowledgeSystemScript.KnowledgeState.RESEARCHING:
			result = GameState.toggle_knowledge_research(p_node_id)
		KnowledgeSystemScript.KnowledgeState.MASTERED:
			result = _start_or_toggle_engineering(p_node_id, view)
		KnowledgeSystemScript.KnowledgeState.APPLIED:
			result = {"success": false, "message": "该知识已完成理论与工程化。"}
		KnowledgeSystemScript.KnowledgeState.DEGRADED:
			result = {"success": false, "message": "知识已衰退；需要教师、记录或实践恢复至少两项传承条件。"}
		_:
			result = {"success": false, "message": "当前状态不能操作"}
	_show_message(result.get("message", ""), result.get("success", false))
	_refresh_display()
	_update_tooltip(p_node_id)


func _start_or_toggle_engineering(p_node_id: String, p_view: Dictionary) -> Dictionary:
	var project_definitions: Array = p_view.get("engineering_projects", [])
	if project_definitions.is_empty():
		return {"success": false, "message": "该节点是理论知识，没有独立工程化项目；其后续分支已经显露。"}
	for project_value in project_definitions:
		var project: Dictionary = project_value
		var project_id := str(project.get("id", ""))
		var existing: Dictionary = GameState.engineering_project_system.get_project(p_node_id, project_id)
		if not existing.is_empty() and not existing.get("completed", false):
			return GameState.engineering_project_system.toggle_pause(p_node_id, project_id)
	return GameState.start_knowledge_engineering(p_node_id, str(project_definitions[0].get("id", "")))


func _on_node_hovered(p_node_id: String, p_local_position: Vector2) -> void:
	_hovered_node_id = p_node_id
	%TooltipPanel.visible = not p_node_id.is_empty()
	if p_node_id.is_empty():
		return
	_update_tooltip(p_node_id)
	var desired: Vector2 = %TechTreeContainer.global_position + p_local_position + Vector2(18.0, 18.0)
	desired.x = minf(desired.x, size.x - %TooltipPanel.size.x - 12.0)
	desired.y = minf(desired.y, size.y - %TooltipPanel.size.y - 12.0)
	%TooltipPanel.global_position = desired


func _update_tooltip(p_node_id: String) -> void:
	var view: Dictionary = GameState.knowledge_system.get_node_view(p_node_id)
	if view.is_empty():
		%TooltipPanel.visible = false
		return
	var lines: Array[String] = []
	lines.append("[font_size=20][b]%s[/b][/font_size]  [color=#9eb8e8]%s[/color]" % [view.get("display_name", ""), view.get("state_name", "")])
	lines.append(str(view.get("description", "")))
	if view.has("hypothesis"):
		lines.append("[color=#b8d8ff]当前假说：%s[/color]" % view.get("hypothesis", ""))
	if int(view.get("state", 0)) == KnowledgeSystemScript.KnowledgeState.RUMOR:
		lines.append("")
		lines.append("线索强度 %.0f%%；未知效果不会在此阶段泄露。" % (float(view.get("clue_strength", 0.0)) * 100.0))
		%TooltipLabel.text = "\n".join(lines)
		return
	var missing: Dictionary = view.get("missing_evidence", {})
	if not missing.is_empty():
		lines.append("[b]尚缺证据[/b]  %s" % _format_missing(missing))
	if view.has("research_requirements"):
		var requirement: Dictionary = view.get("research_requirements", {})
		lines.append("[b]研究[/b]  %.1f 工作量 · %d 人 · %s吞吐" % [
			requirement.get("work_required", 0.0), requirement.get("workers", 0), requirement.get("throughput_type", "basic"),
		])
	var engineering: Array = view.get("engineering_projects", [])
	if not engineering.is_empty():
		lines.append("[b]工程化路径[/b]")
		for project_value in engineering:
			var project: Dictionary = project_value
			lines.append("• %s：%.1f 工作量，%d 人" % [project.get("name", ""), project.get("work_required", 0.0), project.get("workers", 0)])
	lines.append("")
	lines.append("[b]传承状态[/b]  活态 %.0f%% · 记录 %.0f%% · 实践 %.0f%%" % [
		float(view.get("living_transmission", 0.0)) * 100.0,
		float(view.get("record_integrity", 0.0)) * 100.0,
		float(view.get("practice_level", 0.0)) * 100.0,
	])
	match int(view.get("state", 0)):
		KnowledgeSystemScript.KnowledgeState.RESEARCHABLE:
			lines.append("[color=#8fdbff]点击安排研究[/color]")
		KnowledgeSystemScript.KnowledgeState.RESEARCHING:
			lines.append("[color=#ffd05c]研究 %.0f%%；点击暂停/继续[/color]" % (float(view.get("research_progress", 0.0)) * 100.0))
		KnowledgeSystemScript.KnowledgeState.MASTERED:
			lines.append("[color=#70e8ff]理论已掌握；点击启动工程化[/color]")
		KnowledgeSystemScript.KnowledgeState.APPLIED:
			lines.append("[color=#70ff8a]理论与工程能力均可用[/color]")
		KnowledgeSystemScript.KnowledgeState.DEGRADED:
			lines.append("[color=#ff7770]缺失：%s[/color]" % ", ".join(view.get("degradation_factors", [])))
	%TooltipLabel.text = "\n".join(lines)


func _format_missing(p_missing: Dictionary) -> String:
	if p_missing.is_empty():
		return "前置知识或条件"
	var parts: Array[String] = []
	for evidence_type in p_missing:
		parts.append("%s %.1f" % [evidence_type, p_missing[evidence_type]])
	return "、".join(parts)


func _show_message(p_text: String, p_success: bool) -> void:
	%MessageLabel.text = p_text
	%MessageLabel.modulate = Color(0.55, 1.0, 0.65) if p_success else Color(1.0, 0.5, 0.4)


func _on_domain_selected(p_index: int) -> void:
	%TechTreeContainer.set_domain_filter(str(%DomainFilter.get_item_metadata(p_index)))


func _on_search_changed(p_text: String) -> void:
	%TechTreeContainer.set_search_text(p_text)


func _on_risk_toggled(p_enabled: bool) -> void:
	%TechTreeContainer.set_risk_view(p_enabled)


func _on_knowledge_policy_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/knowledge/knowledge_policy.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")
