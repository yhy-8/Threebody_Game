extends Control
## Technology tree screen: research interaction, status display, and tooltip details.

const TechTreeScript = preload("res://scripts/simulation/tech_tree.gd")
const EntityManagerScript = preload("res://scripts/simulation/entity_manager.gd")

var _refresh_elapsed: float = 0.0
var _hovered_node_id: String = ""


func _ready() -> void:
	EventBus.screen_changed.emit("tech_tree")
	%BackButton.pressed.connect(_on_back_pressed)
	%TechTreeContainer.node_clicked.connect(_on_node_clicked)
	%TechTreeContainer.node_hovered.connect(_on_node_hovered)
	_refresh_display()


func _process(p_delta: float) -> void:
	_refresh_elapsed += p_delta
	if _refresh_elapsed >= 0.2:
		_refresh_elapsed = 0.0
		_refresh_display()
		if not _hovered_node_id.is_empty():
			_update_tooltip(_hovered_node_id)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		GameState.toggle_pause()
		%MessageLabel.text = "模拟已暂停" if GameState.paused else "模拟已继续"
		%MessageLabel.modulate = Color(0.72, 0.82, 1.0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _refresh_display() -> void:
	if not GameState.game_started:
		return

	var point_parts: Array[String] = []
	for research_type in ["basic", "applied", "theoretical"]:
		var amount: float = GameState.tech_tree.research_points.get(research_type, 0.0)
		var display_name: String = TechTreeScript.RESEARCH_NAMES.get(research_type, research_type)
		point_parts.append("%s %.1f" % [display_name, amount])
	%PointsLabel.text = "    ".join(point_parts)

	var progress: Dictionary = GameState.tech_tree.get_research_progress()
	if progress.is_empty():
		%ResearchLabel.text = "当前未研究任何科技"
	else:
		%ResearchLabel.text = "研究中：%s  %.0f%%" % [
			progress.get("tech_name", ""), progress.get("overall_percent", 0.0) * 100.0,
		]
	%TechTreeContainer.queue_redraw()


func _on_node_clicked(node_id: String) -> void:
	var node = GameState.tech_tree.get_node(node_id)
	if node == null:
		return

	var result: Dictionary
	if node.unlocked:
		result = {"success": false, "message": "「%s」已经研发完毕" % node.name}
	elif node.researching:
		result = GameState.tech_tree.cancel_research()
	else:
		result = GameState.tech_tree.start_research(node_id, GameState.entities)

	%MessageLabel.text = result.get("message", "")
	%MessageLabel.modulate = Color(0.55, 1.0, 0.65) if result.get("success", false) else Color(1.0, 0.5, 0.4)
	_refresh_display()
	_update_tooltip(node_id)


func _on_node_hovered(node_id: String, local_position: Vector2) -> void:
	_hovered_node_id = node_id
	%TooltipPanel.visible = not node_id.is_empty()
	if node_id.is_empty():
		return
	_update_tooltip(node_id)
	var canvas: Control = %TechTreeContainer
	var desired: Vector2 = canvas.global_position + local_position + Vector2(18.0, 18.0)
	var panel_size: Vector2 = %TooltipPanel.size
	desired.x = min(desired.x, size.x - panel_size.x - 12.0)
	desired.y = min(desired.y, size.y - panel_size.y - 12.0)
	%TooltipPanel.global_position = desired


func _update_tooltip(node_id: String) -> void:
	var node = GameState.tech_tree.get_node(node_id)
	if node == null:
		%TooltipPanel.visible = false
		return

	var lines: Array[String] = []
	lines.append("[font_size=20][b]%s[/b][/font_size]" % node.name)
	lines.append(node.description)
	lines.append("[color=#9fe6ac]效果：%s[/color]" % node.effect_description)
	lines.append("")
	lines.append("[b]科研需求[/b]")
	for research_type in node.research_cost:
		var current: float = GameState.tech_tree.research_points.get(research_type, 0.0)
		var display_name: String = TechTreeScript.RESEARCH_NAMES.get(research_type, research_type)
		lines.append("• %s %.1f / %d" % [display_name, current, node.research_cost[research_type]])

	if not node.resource_cost.is_empty():
		lines.append("[b]物质消耗[/b]")
		for resource_name in node.resource_cost:
			var display_name: String = EntityManagerScript.RESOURCE_DISPLAY_NAMES.get(resource_name, resource_name)
			var current: float = GameState.entities.get_resource(resource_name)
			lines.append("• %s %.0f / %.0f" % [display_name, current, node.resource_cost[resource_name]])

	if not node.prerequisites.is_empty():
		lines.append("[b]前置科技[/b]")
		for prerequisite_id in node.prerequisites:
			var prerequisite = GameState.tech_tree.get_node(prerequisite_id)
			if prerequisite != null:
				lines.append("• %s %s" % ["✓" if prerequisite.unlocked else "✗", prerequisite.name])

	lines.append("")
	if node.unlocked:
		lines.append("[color=#70ff8a]★ 已解锁[/color]")
	elif node.researching:
		var progress: Dictionary = GameState.tech_tree.get_research_progress()
		lines.append("[color=#ffd05c]研究中 %.0f%%（点击取消）[/color]" % [progress.get("overall_percent", 0.0) * 100.0])
	else:
		var availability: Dictionary = GameState.tech_tree.can_start_research(node_id, GameState.entities)
		lines.append("[color=#8fdbff]点击开始研究[/color]" if availability.get("success", false)
			else "[color=#ff8a7a]%s[/color]" % availability.get("message", "尚未满足条件"))
	%TooltipLabel.text = "\n".join(lines)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")
