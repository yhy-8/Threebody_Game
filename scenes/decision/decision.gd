extends Control
## Civilization policy screen. Construction belongs to the selected zone screen.

const DecisionManagerScript = preload("res://scripts/simulation/decision_manager.gd")
const EntityManagerScript = preload("res://scripts/simulation/entity_manager.gd")

var _refresh_elapsed: float = 0.0
var _policy_controls: Dictionary = {}


func _ready() -> void:
	EventBus.screen_changed.emit("decision")
	%BackButton.pressed.connect(_on_back_pressed)
	_build_policy_cards()
	_refresh_display()


func _process(p_delta: float) -> void:
	_refresh_elapsed += p_delta
	if _refresh_elapsed >= 0.25:
		_refresh_elapsed = 0.0
		_refresh_display()


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
	var decision_manager = GameState.decision_manager
	var population = GameState.entities.population
	var state_name := "正常浸泡状态"
	if decision_manager.current_state == DecisionManagerScript.CivilizationState.DEHYDRATED:
		state_name = "全民脱水状态"
	%StateLabel.text = "文明状态：%s    活跃人口 %d    库存 %d / %d" % [
		state_name, population.total, population.stored_population, population.storage_capacity,
	]
	%StabilityBar.value = GameState.entities.social_stability * 100.0
	%StabilityBar.tooltip_text = "社会安定度 %.0f%%" % %StabilityBar.value
	%HealthBar.value = GameState.entities.population_health * 100.0
	%HealthBar.tooltip_text = "人口健康 %.0f%%" % %HealthBar.value
	%StatusValues.text = "社会安定 %.0f%%    人口健康 %.0f%%" % [
		%StabilityBar.value, %HealthBar.value,
	]

	_update_policy_cards()


func _build_policy_cards() -> void:
	_clear_children(%PolicyVBox)
	_policy_controls.clear()
	for decision in GameState.decision_manager.get_policy_decisions():
		%PolicyVBox.add_child(_make_policy_card(decision))


func _update_policy_cards() -> void:
	for decision in GameState.decision_manager.get_policy_decisions():
		if not _policy_controls.has(decision.id):
			continue
		var controls: Dictionary = _policy_controls[decision.id]
		var active: bool = decision.id in GameState.decision_manager.active_policies
		controls["title"].text = "%s%s" % [decision.name, "  [生效中]" if active else ""]
		controls["title"].add_theme_color_override("font_color", Color(0.55, 1.0, 0.68) if active else Color(0.9, 0.9, 1.0))
		var availability: Dictionary = GameState.decision_manager.can_execute(decision.id, GameState.entities, GameState.tech_tree)
		controls["button"].text = "结束政策" if active else "执行政策"
		controls["button"].disabled = not availability.get("success", false)
		controls["button"].tooltip_text = availability.get("message", "")


func _make_policy_card(decision) -> PanelContainer:
	var card := PanelContainer.new()
	var row := HBoxContainer.new()
	card.add_child(row)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_box)

	var active: bool = decision.id in GameState.decision_manager.active_policies
	var title := Label.new()
	title.text = "%s%s" % [decision.name, "  [生效中]" if active else ""]
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.55, 1.0, 0.68) if active else Color(0.9, 0.9, 1.0))
	text_box.add_child(title)

	var description := Label.new()
	description.text = decision.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(description)

	var effect_parts: Array[String] = []
	for effect_name in decision.effects:
		effect_parts.append("%s: %s" % [_effect_display_name(effect_name), decision.effects[effect_name]])
	if not effect_parts.is_empty():
		var effects := Label.new()
		effects.text = "效果：" + "  |  ".join(effect_parts)
		effects.add_theme_color_override("font_color", Color(0.78, 0.72, 0.5))
		text_box.add_child(effects)

	if not decision.resource_cost.is_empty():
		var cost_parts: Array[String] = []
		for resource_name in decision.resource_cost:
			cost_parts.append("%s %.0f" % [
				EntityManagerScript.RESOURCE_DISPLAY_NAMES.get(resource_name, resource_name),
				decision.resource_cost[resource_name],
			])
		var costs := Label.new()
		costs.text = "启用消耗：" + "  |  ".join(cost_parts)
		text_box.add_child(costs)

	var availability: Dictionary = GameState.decision_manager.can_execute(
		decision.id, GameState.entities, GameState.tech_tree
	)
	var button := Button.new()
	button.custom_minimum_size = Vector2(130.0, 56.0)
	button.text = "结束政策" if active else "执行政策"
	button.disabled = not availability.get("success", false)
	button.tooltip_text = availability.get("message", "")
	button.pressed.connect(_on_policy_pressed.bind(decision.id))
	row.add_child(button)
	_policy_controls[decision.id] = {"title": title, "button": button}
	return card


func _effect_display_name(p_name: String) -> String:
	return {
		"civilization": "文明", "consumption": "消耗", "production": "产出",
		"growth": "人口增长", "food": "食物", "food_consumption": "食物消耗",
		"efficiency": "效率", "stability": "安定度", "health": "健康",
	}.get(p_name, p_name)


func _on_policy_pressed(p_decision_id: String) -> void:
	var result: Dictionary = GameState.decision_manager.execute_decision(
		p_decision_id, GameState.entities, GameState.tech_tree, GameState.planet_zones
	)
	%MessageLabel.text = result.get("message", "")
	%MessageLabel.modulate = Color(0.55, 1.0, 0.65) if result.get("success", false) else Color(1.0, 0.5, 0.4)
	GameState.entities.set_policy_effects(GameState.decision_manager.active_policies)
	_refresh_display()


func _clear_children(p_node: Node) -> void:
	for child in p_node.get_children():
		p_node.remove_child(child)
		child.queue_free()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")
