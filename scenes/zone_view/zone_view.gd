extends Control
## Planet-zone browser, construction screen, and workforce management.

const EntityManagerScript = preload("res://scripts/simulation/entity_manager.gd")

var view_mode: String = "temperature"
var selected_zone_id: int = -1
var _refresh_elapsed: float = 0.0
var _detail_structure_signature: String = ""
var _detail_labels: Dictionary = {}
var _breeder_controls: Dictionary = {}
var _building_controls: Dictionary = {}


func _ready() -> void:
	EventBus.screen_changed.emit("zone_view")
	%BackButton.pressed.connect(_on_back_pressed)
	%ModeTemp.pressed.connect(_set_mode.bind("temperature"))
	%ModeRadiation.pressed.connect(_set_mode.bind("radiation"))
	%ModeLight.pressed.connect(_set_mode.bind("light"))
	%ZoneMap.zone_selected.connect(_on_zone_selected)
	%CloseBuildButton.pressed.connect(_close_build_menu)
	_refresh_data()


func _process(p_delta: float) -> void:
	_refresh_elapsed += p_delta
	if _refresh_elapsed >= 0.25:
		_refresh_elapsed = 0.0
		_refresh_data()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		GameState.toggle_pause()
		_show_message("模拟已暂停" if GameState.paused else "模拟已继续", true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if %BuildOverlay.visible:
			_close_build_menu()
		else:
			_on_back_pressed()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		var modes := ["temperature", "radiation", "light"]
		_set_mode(modes[(modes.find(view_mode) + 1) % modes.size()])
		get_viewport().set_input_as_handled()


func _set_mode(p_mode: String) -> void:
	view_mode = p_mode
	%ZoneMap.set_view_mode(p_mode)
	%ModeTemp.button_pressed = p_mode == "temperature"
	%ModeRadiation.button_pressed = p_mode == "radiation"
	%ModeLight.button_pressed = p_mode == "light"


func _refresh_data(p_force_detail_rebuild: bool = false) -> void:
	if not GameState.game_started:
		return
	%ZoneMap.set_data(GameState.planet_zones.get_all_zones_summary())
	var signature := _get_detail_structure_signature()
	if p_force_detail_rebuild or signature != _detail_structure_signature:
		_rebuild_detail()
	else:
		_update_detail_values()


func _on_zone_selected(p_zone_id: int) -> void:
	selected_zone_id = p_zone_id
	%ZoneMap.set_selected_zone(p_zone_id)
	_rebuild_detail()


func _get_detail_structure_signature() -> String:
	var building_ids: Array[String] = []
	if selected_zone_id >= 0:
		for building in GameState.entities.get_buildings_in_zone(selected_zone_id):
			building_ids.append(str(building.id))
	return "%d:%s" % [selected_zone_id, ",".join(building_ids)]


func _rebuild_detail() -> void:
	if not GameState.game_started:
		return
	var detail: VBoxContainer = %DetailVBox
	_clear_children(detail)
	_detail_labels.clear()
	_breeder_controls.clear()
	_building_controls.clear()
	detail.add_child(_section_label("全球概览"))
	_add_detail_label(detail, "rotation")
	_add_detail_label(detail, "average_temperature")
	_add_detail_label(detail, "average_radiation")
	_add_detail_label(detail, "population")
	_add_detail_label(detail, "stored_population")
	detail.add_child(_make_breeder_row())

	if selected_zone_id < 0:
		detail.add_child(_section_label("区域详情"))
		detail.add_child(_label("← 点击左侧网格选择区域"))
		_detail_structure_signature = _get_detail_structure_signature()
		_update_detail_values()
		return

	var zone = GameState.planet_zones.get_zone(selected_zone_id)
	if zone == null:
		return
	detail.add_child(_section_label("区域 #%d" % selected_zone_id))
	for key in ["latitude", "longitude", "terrain", "zone_environment", "work_efficiency", "deposits", "fertility"]:
		_add_detail_label(detail, key)

	detail.add_child(_section_label("建筑"))
	var buildings: Array = GameState.entities.get_buildings_in_zone(selected_zone_id)
	if buildings.is_empty():
		detail.add_child(_label("暂无建筑"))
	for building in buildings:
		detail.add_child(_make_building_card(building, zone))

	var build_button := Button.new()
	build_button.text = "+ 建造新建筑"
	build_button.custom_minimum_size.y = 52.0
	build_button.pressed.connect(_open_build_menu)
	detail.add_child(build_button)
	_detail_structure_signature = _get_detail_structure_signature()
	_update_detail_values()


func _add_detail_label(parent: Node, key: String) -> Label:
	var label := _label("")
	_detail_labels[key] = label
	parent.add_child(label)
	return label


func _make_breeder_row() -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := _label("")
	_breeder_controls["label"] = label
	box.add_child(label)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 6)
	box.add_child(actions)
	_breeder_controls["remove_buttons"] = [
		_add_allocation_button(actions, "BreederClear", "清空", "取消全部生育人口", _change_breeders.bind("clear", 0)),
		_add_allocation_button(actions, "BreederMinus10", "−10", "减少最多 10 人", _change_breeders.bind("remove", 10)),
		_add_allocation_button(actions, "BreederMinus1", "−1", "减少 1 人", _change_breeders.bind("remove", 1)),
	]
	_breeder_controls["add_buttons"] = [
		_add_allocation_button(actions, "BreederPlus1", "+1", "增加 1 人", _change_breeders.bind("add", 1)),
		_add_allocation_button(actions, "BreederPlus10", "+10", "增加最多 10 人", _change_breeders.bind("add", 10)),
		_add_allocation_button(actions, "BreederFill", "最大", "分配全部闲置人口", _change_breeders.bind("fill", 0)),
	]
	return box


func _make_building_card(building, zone) -> PanelContainer:
	var card := PanelContainer.new()
	var box := VBoxContainer.new()
	card.add_child(box)
	var status := "运行中"
	if building.destroyed:
		status = "已损毁"
	elif building.under_construction:
		status = "建造中 %.0f%%" % (building.build_progress / max(building.build_time, 0.001) * 100.0)
	box.add_child(_label("%s  [%s]" % [building.building_name, status]))
	box.add_child(_label("耐久：%.0f / %.0f" % [building.durability, building.max_durability]))

	if building.worker_capacity > 0:
		var worker_label := _label("")
		box.add_child(worker_label)
		var worker_actions := HBoxContainer.new()
		worker_actions.alignment = BoxContainer.ALIGNMENT_END
		worker_actions.add_theme_constant_override("separation", 6)
		box.add_child(worker_actions)
		_building_controls[building.id] = {
			"status": box.get_child(0),
			"durability": box.get_child(1),
			"workers": worker_label,
			"remove_buttons": [
				_add_allocation_button(worker_actions, "Worker%dClear" % building.id, "清空", "撤回全部工人", _change_workers.bind(building.id, "clear", 0)),
				_add_allocation_button(worker_actions, "Worker%dMinus10" % building.id, "−10", "撤回最多 10 人", _change_workers.bind(building.id, "remove", 10)),
				_add_allocation_button(worker_actions, "Worker%dMinus1" % building.id, "−1", "撤回 1 人", _change_workers.bind(building.id, "remove", 1)),
			],
			"add_buttons": [
				_add_allocation_button(worker_actions, "Worker%dPlus1" % building.id, "+1", "分配 1 人", _change_workers.bind(building.id, "add", 1)),
				_add_allocation_button(worker_actions, "Worker%dPlus10" % building.id, "+10", "分配最多 10 人", _change_workers.bind(building.id, "add", 10)),
				_add_allocation_button(worker_actions, "Worker%dFill" % building.id, "填满", "用闲置人口填满岗位", _change_workers.bind(building.id, "fill", 0)),
			],
		}
	else:
		_building_controls[building.id] = {"status": box.get_child(0), "durability": box.get_child(1)}

	if not building.per_worker_output.is_empty():
		var output_label := _label("")
		box.add_child(output_label)
		_building_controls[building.id]["output"] = output_label
	if not building.consumption.is_empty():
		var parts: Array[String] = []
		for resource_name in building.consumption:
			parts.append("%s %.1f/天" % [
				EntityManagerScript.RESOURCE_DISPLAY_NAMES.get(resource_name, resource_name), building.consumption[resource_name],
			])
		var consumption_label := _label("消耗：" + "  ".join(parts))
		box.add_child(consumption_label)
		_building_controls[building.id]["consumption"] = consumption_label
	return card


func _add_allocation_button(parent: HBoxContainer, button_name: String, text: String,
		tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(58.0, 42.0)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _change_breeders(p_action: String, p_amount: int) -> void:
	if p_action in ["add", "remove"]:
		if Input.is_key_pressed(KEY_CTRL):
			p_action = "fill" if p_action == "add" else "clear"
		elif Input.is_key_pressed(KEY_SHIFT):
			p_amount = maxi(p_amount, 10)
	var breeders: int = GameState.entities.population.breeders
	var idle: int = GameState.entities.get_idle_population()
	var amount := p_amount
	var result: Dictionary
	match p_action:
		"add":
			amount = mini(amount, idle)
			result = GameState.entities.assign_breeders(amount) if amount > 0 else {"success": false, "message": "没有闲置人口可分配"}
		"remove":
			amount = mini(amount, breeders)
			result = GameState.entities.unassign_breeders(amount) if amount > 0 else {"success": false, "message": "当前没有生育人口"}
		"fill":
			result = GameState.entities.assign_breeders(idle) if idle > 0 else {"success": false, "message": "没有闲置人口可分配"}
		"clear":
			result = GameState.entities.unassign_breeders(breeders) if breeders > 0 else {"success": false, "message": "当前没有生育人口"}
	var message: String = result.get("message", "")
	if result.get("success", false) and message.is_empty():
		message = "生育人口已更新：%d 人" % GameState.entities.population.breeders
	_show_message(message, result.get("success", false))
	_update_detail_values()


func _change_workers(p_building_id: int, p_action: String, p_amount: int) -> void:
	var building = GameState.entities.get_building(p_building_id)
	if building == null:
		return
	if p_action in ["add", "remove"]:
		if Input.is_key_pressed(KEY_CTRL):
			p_action = "fill" if p_action == "add" else "clear"
		elif Input.is_key_pressed(KEY_SHIFT):
			p_amount = maxi(p_amount, 10)
	var idle: int = GameState.entities.get_idle_population()
	var amount := p_amount
	var result: Dictionary
	match p_action:
		"add":
			amount = mini(amount, mini(building.worker_capacity - building.assigned_workers, idle))
			result = GameState.entities.assign_worker_to_building(p_building_id, amount) if amount > 0 else {"success": false, "message": "没有空余岗位或闲置人口"}
		"remove":
			amount = mini(amount, building.assigned_workers)
			result = GameState.entities.unassign_worker_from_building(p_building_id, amount) if amount > 0 else {"success": false, "message": "当前建筑没有工人"}
		"fill":
			amount = mini(building.worker_capacity - building.assigned_workers, idle)
			result = GameState.entities.assign_worker_to_building(p_building_id, amount) if amount > 0 else {"success": false, "message": "没有空余岗位或闲置人口"}
		"clear":
			amount = building.assigned_workers
			result = GameState.entities.unassign_worker_from_building(p_building_id, amount) if amount > 0 else {"success": false, "message": "当前建筑没有工人"}
	var message: String = result.get("message", "")
	if result.get("success", false) and message.is_empty():
		message = "%s工人已更新：%d / %d" % [building.building_name, building.assigned_workers, building.worker_capacity]
	_show_message(message, result.get("success", false))
	_update_detail_values()


func _update_detail_values() -> void:
	if not GameState.game_started or _detail_labels.is_empty():
		return
	var average: Dictionary = GameState.planet_zones.get_average_environment()
	_detail_labels["rotation"].text = "自转角度：%.1f°" % GameState.planet_zones.rotation_angle
	_detail_labels["average_temperature"].text = "平均温度：%.1f℃" % average.get("temperature", 0.0)
	_detail_labels["average_radiation"].text = "平均辐射：%.2f" % average.get("radiation", 0.0)
	_detail_labels["population"].text = "总人口：%d    闲置：%d" % [GameState.entities.population.total, GameState.entities.get_idle_population()]
	_detail_labels["stored_population"].text = "库存人口：%d / %d" % [GameState.entities.population.stored_population, GameState.entities.population.storage_capacity]
	var breeders: int = GameState.entities.population.breeders
	var idle: int = GameState.entities.get_idle_population()
	_breeder_controls["label"].text = "生育分配：%d 人" % breeders
	_set_buttons_disabled(_breeder_controls["remove_buttons"], breeders <= 0)
	_set_buttons_disabled(_breeder_controls["add_buttons"], idle <= 0)

	if selected_zone_id < 0:
		return
	var zone = GameState.planet_zones.get_zone(selected_zone_id)
	if zone == null:
		return
	_detail_labels["latitude"].text = "纬度：%.0f° — %.0f°" % [zone.lat_bottom, zone.lat_top]
	_detail_labels["longitude"].text = "经度：%.0f° — %.0f°" % [zone.lon_left, zone.lon_right]
	_detail_labels["terrain"].text = "地形：%s" % zone.terrain_type
	_detail_labels["zone_environment"].text = "温度 %.1f℃  |  辐射 %.2f  |  光照 %.0f%%" % [zone.temperature, zone.radiation, zone.light_intensity * 100.0]
	_detail_labels["work_efficiency"].text = "工作效率：%.0f%%" % (zone.get_work_efficiency() * 100.0)
	_detail_labels["deposits"].text = "资源禀赋：铁 %.2f  铜 %.2f  稀有 %.2f" % [zone.resource_deposits.get("iron", 0.0), zone.resource_deposits.get("copper", 0.0), zone.resource_deposits.get("rare_mineral", 0.0)]
	_detail_labels["fertility"].text = "肥沃度 %.0f%%  |  藻类密度 %.0f%%" % [zone.fertility * 100.0, zone.algae_density * 100.0]

	for building in GameState.entities.get_buildings_in_zone(selected_zone_id):
		if not _building_controls.has(building.id):
			continue
		var controls: Dictionary = _building_controls[building.id]
		var status := "运行中"
		if building.destroyed:
			status = "已损毁"
		elif building.under_construction:
			status = "建造中 %.0f%%" % (building.build_progress / max(building.build_time, 0.001) * 100.0)
		controls["status"].text = "%s  [%s]" % [building.building_name, status]
		controls["durability"].text = "耐久：%.0f / %.0f" % [building.durability, building.max_durability]
		if controls.has("workers"):
			controls["workers"].text = "工人：%d / %d" % [building.assigned_workers, building.worker_capacity]
			_set_buttons_disabled(controls["remove_buttons"], building.assigned_workers <= 0)
			_set_buttons_disabled(controls["add_buttons"], idle <= 0 or building.assigned_workers >= building.worker_capacity)
		if controls.has("output"):
			var output: Dictionary = building.get_output(GameState.entities.population.automation_multiplier, zone.get_work_efficiency())
			controls["output"].text = "产出：%s" % (_format_resource_rates(output, true) if not output.is_empty() else "待分配工人或建筑尚未运行")


func _set_buttons_disabled(buttons: Array, disabled: bool) -> void:
	for button in buttons:
		button.disabled = disabled


func _format_resource_rates(rates: Dictionary, show_plus: bool) -> String:
	var parts: Array[String] = []
	for resource_name in rates:
		parts.append("%s %s%.1f/天" % [EntityManagerScript.RESOURCE_DISPLAY_NAMES.get(resource_name, resource_name), "+" if show_plus else "", rates[resource_name]])
	return "  ".join(parts)


func _open_build_menu() -> void:
	if selected_zone_id < 0:
		return
	%BuildTitle.text = "在区域 #%d 建造新建筑" % selected_zone_id
	_clear_children(%BuildList)
	for decision in GameState.decision_manager.get_construction_decisions():
		var availability: Dictionary = GameState.decision_manager.can_execute(
			decision.id, GameState.entities, GameState.tech_tree,
			GameState.planet_zones, selected_zone_id
		)
		var button := Button.new()
		var cost_parts: Array[String] = []
		for resource_name in decision.resource_cost:
			cost_parts.append("%s %.0f" % [
				EntityManagerScript.RESOURCE_DISPLAY_NAMES.get(resource_name, resource_name),
				decision.resource_cost[resource_name],
			])
		button.text = "%s\n%s\n消耗：%s" % [decision.name, decision.description, "  |  ".join(cost_parts)]
		button.custom_minimum_size.y = 78.0
		button.disabled = not availability.get("success", false)
		button.tooltip_text = availability.get("message", "") if button.disabled else decision.description
		button.pressed.connect(_construct_building.bind(decision.id))
		%BuildList.add_child(button)
	%BuildOverlay.visible = true


func _close_build_menu() -> void:
	%BuildOverlay.visible = false


func _construct_building(p_decision_id: String) -> void:
	var result: Dictionary = GameState.decision_manager.execute_decision(
		p_decision_id, GameState.entities, GameState.tech_tree,
		GameState.planet_zones, selected_zone_id
	)
	_show_message(result.get("message", ""), result.get("success", false))
	if result.get("success", false):
		_close_build_menu()
	_refresh_data(true)


func _show_message(p_text: String, p_success: bool) -> void:
	%MessageLabel.text = p_text
	%MessageLabel.modulate = Color(0.55, 1.0, 0.65) if p_success else Color(1.0, 0.52, 0.4)


func _section_label(p_text: String) -> Label:
	var label := Label.new()
	label.text = "── %s ──" % p_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.55, 0.72, 1.0))
	return label


func _label(p_text: String) -> Label:
	var label := Label.new()
	label.text = p_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _clear_children(p_node: Node) -> void:
	for child in p_node.get_children():
		p_node.remove_child(child)
		child.queue_free()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")
