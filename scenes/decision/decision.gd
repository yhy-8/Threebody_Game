extends Control
## 政策/决策界面

const EntityManagerScript = preload("res://scripts/simulation/entity_manager.gd")
const DecisionManagerScript = preload("res://scripts/simulation/decision_manager.gd")


func _ready() -> void:
	%BackButton.pressed.connect(_on_back_pressed)
	_refresh_display()


func _refresh_display() -> void:
	if not GameState.game_started:
		return

	var state_label: Label = %StateLabel
	var dm = GameState.decision_manager
	var state_str := "正常"
	if dm.current_state == DecisionManagerScript.CivilizationState.DEHYDRATED:
		state_str = "脱水"
	state_label.text = "文明状态: %s    库存: %d / %d 人" % [
		state_str,
		GameState.entities.population.stored_population,
		GameState.entities.population.storage_capacity,
	]

	# Build decision buttons
	var vbox: VBoxContainer = %DecisionVBox
	_clear_children(vbox)

	var tt = GameState.tech_tree
	var ents = GameState.entities

	# Construction decisions
	var section_label := Label.new()
	section_label.text = "— 建造 —"
	vbox.add_child(section_label)

	for dec in dm.get_construction_decisions():
		var can_exec: Dictionary = dm.can_execute(dec.id, ents, tt)
		var btn := Button.new()
		btn.text = "%s [%s]" % [dec.name, dec.description]
		btn.disabled = not can_exec["success"]
		btn.tooltip_text = can_exec["message"] if not can_exec["success"] else dec.description
		btn.pressed.connect(_on_build_pressed.bind(dec.id))
		vbox.add_child(btn)

	# Policy decisions
	var policy_label := Label.new()
	policy_label.text = "— 政策 —"
	vbox.add_child(policy_label)

	for dec in dm.get_policy_decisions():
		var can_exec: Dictionary = dm.can_execute(dec.id, ents, tt)
		var btn := Button.new()
		btn.text = dec.name
		btn.disabled = not can_exec["success"]
		btn.tooltip_text = can_exec["message"] if not can_exec["success"] else dec.description
		btn.pressed.connect(_on_policy_pressed.bind(dec.id))
		vbox.add_child(btn)


func _on_build_pressed(decision_id: String) -> void:
	var result: Dictionary = GameState.decision_manager.execute_decision(
		decision_id, GameState.entities, GameState.tech_tree,
		GameState.planet_zones, 0  # zone 0 by default for now
	)
	print(result["message"])
	_refresh_display()


func _on_policy_pressed(decision_id: String) -> void:
	var result: Dictionary = GameState.decision_manager.execute_decision(
		decision_id, GameState.entities
	)
	print(result["message"])
	_refresh_display()


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")
