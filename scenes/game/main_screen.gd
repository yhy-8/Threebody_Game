extends Control
## 游戏主界面 — HUD + 三面板 + 工具栏

const EntityManagerScript = preload("res://scripts/simulation/entity_manager.gd")
const TechTreeScript = preload("res://scripts/simulation/tech_tree.gd")


func _ready() -> void:
	EventBus.screen_changed.emit("main_screen")
	_setup_buttons()

	# Start a new game if not already started
	if not GameState.game_started:
		GameState.new_game("新宇宙")

	# Always kick off the simulation timer on scene load
	_start_simulation_timer()

	# Listen for state updates
	GameState.state_updated.connect(_on_state_updated)


func _start_simulation_timer() -> void:
	var timer := Timer.new()
	timer.name = "SimulationTimer"
	timer.wait_time = 0.016  # ~60fps
	timer.timeout.connect(_on_simulation_tick)
	add_child(timer)
	timer.start()


func _on_simulation_tick() -> void:
	GameState.update(0.016)


func _on_state_updated() -> void:
	_refresh_panels()


func _setup_buttons() -> void:
	%MenuButton.pressed.connect(_on_menu_pressed)
	%PauseButton.pressed.connect(_on_pause_pressed)
	%Speed1x.pressed.connect(func(): GameState.set_time_scale(1.0))
	%Speed2x.pressed.connect(func(): GameState.set_time_scale(2.0))
	%Speed3x.pressed.connect(func(): GameState.set_time_scale(3.0))
	%Speed5x.pressed.connect(func(): GameState.set_time_scale(5.0))
	%TechTreeButton.pressed.connect(_on_tech_tree_pressed)
	%DecisionButton.pressed.connect(_on_decision_pressed)
	%ZoneViewButton.pressed.connect(_on_zone_view_pressed)
	%StarmapButton.pressed.connect(_on_starmap_pressed)


func _refresh_panels() -> void:
	if not GameState.game_started:
		return

	var state: Dictionary = GameState.get_state()
	var env_params: Dictionary = state["environment"]["params"]
	var entities_data: Dictionary = state["entities"]
	var resources_data: Dictionary = entities_data["resources"]
	var pop_data: Dictionary = entities_data["population"]

	# ── 资源面板 ──
	var res_list: VBoxContainer = %ResourceList
	_clear_children(res_list)
	for group_name in ["矿物", "能源", "食物"]:
		var group_label := Label.new()
		group_label.text = "— %s —" % group_name
		group_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		res_list.add_child(group_label)

		var keys: Array = EntityManagerScript.RESOURCE_GROUPS.get(group_name, [])
		for key in keys:
			var amount: float = resources_data.get(key, 0.0)
			var display_name: String = EntityManagerScript.RESOURCE_DISPLAY_NAMES.get(key, key)
			var label := Label.new()
			label.text = "%s: %.1f" % [display_name, amount]
			res_list.add_child(label)

	# ── 文明面板 ──
	var civ_panel: Panel = %PanelContainer.get_child(1)  # second panel
	var civ_children: Array = civ_panel.find_children("*", "Label")
	if civ_children.size() >= 1:
		civ_children[0].text = "— 文明 —"
	# Add population info
	var civ_vbox := _get_or_create_vbox(civ_panel)
	_clear_children(civ_vbox)
	civ_vbox.add_child(_make_label("人口: %d" % pop_data.get("total", 0)))
	civ_vbox.add_child(_make_label("库存: %d / %d" % [pop_data.get("stored_population", 0), pop_data.get("storage_capacity", 0)]))
	civ_vbox.add_child(_make_label("空闲: %d" % GameState.entities.get_idle_population()))
	civ_vbox.add_child(_make_label("生育: %d" % pop_data.get("breeders", 0)))

	# Research rates
	civ_vbox.add_child(_make_label(""))
	civ_vbox.add_child(_make_label("— 科研产出 —"))
	var rates: Dictionary = GameState.research_output_rate
	for rtype in ["basic", "applied", "theoretical"]:
		var name: String = TechTreeScript.RESEARCH_NAMES.get(rtype, rtype)
		civ_vbox.add_child(_make_label("%s: %.2f/天" % [name, rates.get(rtype, 0.0)]))

	# ── 环境面板 ──
	var env_panel: Panel = %PanelContainer.get_child(2)  # third panel
	var env_vbox := _get_or_create_vbox(env_panel)
	_clear_children(env_vbox)
	env_vbox.add_child(_make_label("温度: %.1f°C" % env_params.get("temperature", 0.0)))
	env_vbox.add_child(_make_label("辐射: %.2f" % env_params.get("radiation", 0.0)))
	env_vbox.add_child(_make_label("光照: %.2f" % env_params.get("light_intensity", 0.0)))
	env_vbox.add_child(_make_label("稳定性: %.2f" % env_params.get("stability", 0.0)))
	env_vbox.add_child(_make_label(""))
	env_vbox.add_child(_make_label("第%.1f天" % state["game_time"]))
	env_vbox.add_child(_make_label("时间: %dx" % GameState.time_scale))
	if GameState.paused:
		env_vbox.add_child(_make_label("[已暂停]"))


func _get_or_create_vbox(panel: Panel) -> VBoxContainer:
	for child in panel.get_children():
		if child is VBoxContainer:
			return child
	var vbox := VBoxContainer.new()
	vbox.name = "ContentVBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	return vbox


func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _on_menu_pressed() -> void:
	EventBus.game_paused.emit(true)
	get_tree().change_scene_to_file("res://scenes/game/game_menu.tscn")


func _on_pause_pressed() -> void:
	GameState.toggle_pause()


func _on_tech_tree_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/tech_tree/tech_tree.tscn")


func _on_decision_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/decision/decision.tscn")


func _on_zone_view_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/zone_view/zone_view.tscn")


func _on_starmap_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/starmap/starmap_view.tscn")
