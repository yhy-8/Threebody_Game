extends Control
## 游戏主界面 — HUD + 三面板 + 工具栏

const EntityManagerScript = preload("res://scripts/simulation/entity_manager.gd")
const TechTreeScript = preload("res://scripts/simulation/tech_tree.gd")
const SPEED_OPTIONS: Array[float] = [1.0, 2.0, 3.0, 5.0]
const DEVELOPER_RESOURCE_IDS: Array[String] = [
	"iron", "copper", "rare_mineral", "algae_fuel", "fossil_fuel", "electricity", "food",
]
const DEVELOPER_RESEARCH_IDS: Array[String] = ["basic", "applied", "theoretical"]

var _developer_inputs: Dictionary = {}


func _ready() -> void:
	EventBus.screen_changed.emit("main_screen")
	_setup_buttons()
	_setup_developer_tools()

	# Start a new game if not already started
	if not GameState.game_started:
		GameState.new_game("新宇宙")

	# Listen for state updates
	GameState.state_updated.connect(_on_state_updated)
	_refresh_panels()


func _on_state_updated() -> void:
	_refresh_panels()


func _setup_buttons() -> void:
	%MenuButton.pressed.connect(_on_menu_pressed)
	%PauseButton.pressed.connect(_on_pause_pressed)
	%SpeedSlider.value_changed.connect(_on_speed_slider_changed)
	%TechTreeButton.pressed.connect(_on_tech_tree_pressed)
	%DecisionButton.pressed.connect(_on_decision_pressed)
	%ZoneViewButton.pressed.connect(_on_zone_view_pressed)
	%StarmapButton.pressed.connect(_on_starmap_pressed)
	%DeveloperToolsButton.pressed.connect(_open_developer_tools)
	%CloseButton.pressed.connect(_close_developer_tools)
	%ApplyDeveloperButton.pressed.connect(_apply_developer_values)
	%FillResourcesButton.pressed.connect(_fill_developer_resources)
	%UnlockTechButton.pressed.connect(_unlock_all_technologies)
	_sync_speed_slider()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if %DeveloperOverlay.visible:
			_close_developer_tools()
		else:
			_on_menu_pressed()
	elif event.keycode == KEY_SPACE:
		_on_pause_pressed()
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD]:
		_change_speed(1)
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
		_change_speed(-1)
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_1, KEY_2, KEY_3, KEY_5]:
		var shortcut_scale := {KEY_1: 1.0, KEY_2: 2.0, KEY_3: 3.0, KEY_5: 5.0}[event.keycode] as float
		_set_speed(shortcut_scale)
		get_viewport().set_input_as_handled()


func _refresh_panels() -> void:
	if not GameState.game_started:
		return

	var state: Dictionary = GameState.get_state()
	var env_params: Dictionary = state["environment"]["params"]
	var entities_data: Dictionary = state["entities"]
	var resources_data: Dictionary = entities_data["resources"]
	var pop_data: Dictionary = entities_data["population"]
	var telescope_unlocked: bool = GameState.tech_tree.is_unlocked("telescope")
	%StarmapButton.disabled = not GameState.can_access_starmap()
	if GameState.developer_mode and not telescope_unlocked:
		%StarmapButton.text = "[开发者] 星图"
		%StarmapButton.tooltip_text = "开发者模式已绕过望远镜解锁条件"
	else:
		%StarmapButton.text = "星图" if not %StarmapButton.disabled else "[锁定] 星图"
		%StarmapButton.tooltip_text = "研发「望远镜」后解锁" if %StarmapButton.disabled else "进入3D星图"
	%DeveloperModeLabel.visible = GameState.developer_mode
	%DeveloperToolsButton.visible = GameState.developer_mode
	%PauseButton.text = "继续" if GameState.paused else "暂停"
	_sync_speed_slider()

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
	env_vbox.add_child(_make_label("时间: %.0fx" % GameState.time_scale))
	if GameState.paused:
		env_vbox.add_child(_make_label("[已暂停]"))


func _get_or_create_vbox(panel: Panel) -> VBoxContainer:
	for child in panel.get_children():
		if child is VBoxContainer:
			return child
	var vbox := VBoxContainer.new()
	vbox.name = "ContentVBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 20.0
	vbox.offset_top = 56.0
	vbox.offset_right = -20.0
	vbox.offset_bottom = -20.0
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
	if not GameState.paused:
		GameState.toggle_pause()
	get_tree().change_scene_to_file("res://scenes/game/game_menu.tscn")


func _on_pause_pressed() -> void:
	GameState.toggle_pause()
	%PauseButton.text = "继续" if GameState.paused else "暂停"


func _on_speed_slider_changed(p_index: float) -> void:
	var index := clampi(roundi(p_index), 0, SPEED_OPTIONS.size() - 1)
	_set_speed(SPEED_OPTIONS[index])


func _change_speed(p_direction: int) -> void:
	var current_index := _nearest_speed_index(GameState.time_scale)
	_set_speed(SPEED_OPTIONS[clampi(current_index + p_direction, 0, SPEED_OPTIONS.size() - 1)])


func _set_speed(p_scale: float) -> void:
	GameState.set_time_scale(p_scale)
	_sync_speed_slider()


func _sync_speed_slider() -> void:
	var index := _nearest_speed_index(GameState.time_scale)
	%SpeedSlider.set_value_no_signal(index)
	%SpeedValueLabel.text = "%dx" % int(SPEED_OPTIONS[index])
	%SpeedSlider.tooltip_text = "当前模拟速度：%dx" % int(SPEED_OPTIONS[index])


func _nearest_speed_index(p_scale: float) -> int:
	var nearest_index := 0
	var nearest_distance := INF
	for index in range(SPEED_OPTIONS.size()):
		var distance := absf(SPEED_OPTIONS[index] - p_scale)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	return nearest_index


func _on_tech_tree_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/tech_tree/tech_tree.tscn")


func _on_decision_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/decision/decision.tscn")


func _on_zone_view_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/zone_view/zone_view.tscn")


func _on_starmap_pressed() -> void:
	if not GameState.can_access_starmap():
		return
	get_tree().change_scene_to_file("res://scenes/starmap/starmap_view.tscn")


func _setup_developer_tools() -> void:
	_add_developer_section("人口")
	_add_developer_input("population_total", "当前人口", 1.0)
	_add_developer_input("population_stored", "库存人口", 1.0)
	_add_developer_input("population_breeders", "生育人口", 1.0)
	_add_developer_section("资源")
	for resource_id in DEVELOPER_RESOURCE_IDS:
		_add_developer_input("resource_%s" % resource_id, EntityManagerScript.RESOURCE_DISPLAY_NAMES[resource_id], 10.0)
	_add_developer_section("科研点")
	for research_id in DEVELOPER_RESEARCH_IDS:
		_add_developer_input("research_%s" % research_id, TechTreeScript.RESEARCH_NAMES[research_id], 10.0)


func _add_developer_section(p_title: String) -> void:
	var label := Label.new()
	label.text = "— %s —" % p_title
	label.add_theme_color_override("font_color", Color(0.55, 0.72, 1.0))
	label.add_theme_font_size_override("font_size", 20)
	%DeveloperFields.add_child(label)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 32)
	%DeveloperFields.add_child(spacer)


func _add_developer_input(p_id: String, p_label: String, p_step: float) -> void:
	var label := Label.new()
	label.text = p_label
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	%DeveloperFields.add_child(label)
	var input := SpinBox.new()
	input.custom_minimum_size = Vector2(300, 48)
	input.max_value = 1000000000.0
	input.step = p_step
	input.allow_greater = true
	input.update_on_text_changed = true
	%DeveloperFields.add_child(input)
	_developer_inputs[p_id] = input


func _open_developer_tools() -> void:
	if not GameState.developer_mode:
		return
	_sync_developer_inputs()
	%DeveloperOverlay.visible = true


func _close_developer_tools() -> void:
	%DeveloperOverlay.visible = false


func _sync_developer_inputs() -> void:
	if GameState.entities == null or GameState.tech_tree == null:
		return
	_developer_inputs["population_total"].value = GameState.entities.population.total
	_developer_inputs["population_stored"].value = GameState.entities.population.stored_population
	_developer_inputs["population_breeders"].value = GameState.entities.population.breeders
	for resource_id in DEVELOPER_RESOURCE_IDS:
		_developer_inputs["resource_%s" % resource_id].value = GameState.entities.get_resource(resource_id)
	for research_id in DEVELOPER_RESEARCH_IDS:
		_developer_inputs["research_%s" % research_id].value = GameState.tech_tree.research_points[research_id]


func _apply_developer_values() -> void:
	var values := {
		"population": {
			"total": int(_developer_inputs["population_total"].value),
			"stored": int(_developer_inputs["population_stored"].value),
			"breeders": int(_developer_inputs["population_breeders"].value),
		},
		"resources": {},
		"research": {},
	}
	for resource_id in DEVELOPER_RESOURCE_IDS:
		values["resources"][resource_id] = _developer_inputs["resource_%s" % resource_id].value
	for research_id in DEVELOPER_RESEARCH_IDS:
		values["research"][research_id] = _developer_inputs["research_%s" % research_id].value
	GameState.apply_developer_values(values)
	_sync_developer_inputs()


func _fill_developer_resources() -> void:
	GameState.developer_fill_resources()
	_sync_developer_inputs()


func _unlock_all_technologies() -> void:
	GameState.developer_unlock_all_technologies()
