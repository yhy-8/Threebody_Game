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
	EventBus.game_paused.connect(_on_global_pause_changed)
	if GameState.game_started:
		selected_zone_id = GameState.observed_zone_id
		%ZoneMap.set_selected_zone(selected_zone_id)
	_refresh_data()


func _process(p_delta: float) -> void:
	_refresh_elapsed += p_delta
	if _refresh_elapsed >= 0.25:
		_refresh_elapsed = 0.0
		_refresh_data()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and %BuildOverlay.visible:
		get_viewport().set_input_as_handled()
		_close_build_menu()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		var modes := ["temperature", "radiation", "light"]
		_set_mode(modes[(modes.find(view_mode) + 1) % modes.size()])
		get_viewport().set_input_as_handled()


func _on_global_pause_changed(p_paused: bool) -> void:
	_show_message("模拟已暂停" if p_paused else "模拟已继续", true)


func _set_mode(p_mode: String) -> void:
	view_mode = p_mode
	%ZoneMap.set_view_mode(p_mode)
	%ModeTemp.button_pressed = p_mode == "temperature"
	%ModeRadiation.button_pressed = p_mode == "radiation"
	%ModeLight.button_pressed = p_mode == "light"


func _refresh_data(p_force_detail_rebuild: bool = false) -> void:
	if not GameState.game_started:
		return
	%ZoneMap.set_data(GameState.get_public_zone_summaries())
	var signature := _get_detail_structure_signature()
	if p_force_detail_rebuild or signature != _detail_structure_signature:
		_rebuild_detail()
	else:
		_update_detail_values()


func _on_zone_selected(p_zone_id: int) -> void:
	selected_zone_id = p_zone_id
	GameState.set_observed_zone(p_zone_id)
	%ZoneMap.set_selected_zone(p_zone_id)
	_rebuild_detail()


func _get_detail_structure_signature() -> String:
	var building_ids: Array[String] = []
	if selected_zone_id >= 0:
		var knowledge: Dictionary = GameState.get_zone_knowledge(selected_zone_id)
		if int(knowledge.get("level", 0)) >= GameState.settlement_system.ZoneKnowledgeLevel.FAMILIAR:
			for building in GameState.entities.get_buildings_in_zone(selected_zone_id):
				building_ids.append(str(building.id))
	var operation_parts: Array[String] = []
	if GameState.region_movement_system != null:
		for operation_id in GameState.region_movement_system.operations:
			var operation: Dictionary = GameState.region_movement_system.operations[operation_id]
			operation_parts.append("%s:%d:%d" % [operation_id, int(operation.get("status", -1)), int(operation.get("current_zone_id", -1))])
	var settlement_type := "none"
	if selected_zone_id >= 0 and GameState.settlement_system != null:
		settlement_type = str(GameState.settlement_system.get_settlement(selected_zone_id).get("type", "none"))
	return "%d:%s:%s:%s" % [selected_zone_id, settlement_type, ",".join(building_ids), ",".join(operation_parts)]


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
	_add_operation_cards(detail)

	if selected_zone_id < 0:
		detail.add_child(_section_label("区域详情"))
		detail.add_child(_label("← 点击左侧网格选择区域"))
		_detail_structure_signature = _get_detail_structure_signature()
		_update_detail_values()
		return

	var zone = GameState.planet_zones.get_zone(selected_zone_id)
	if zone == null:
		return
	var knowledge: Dictionary = GameState.get_zone_knowledge(selected_zone_id)
	var level := int(knowledge.get("level", 0))
	detail.add_child(_section_label("区域 #%d · %s" % [selected_zone_id, knowledge.get("level_name", "未知")]))
	if level == GameState.settlement_system.ZoneKnowledgeLevel.UNKNOWN:
		detail.add_child(_label("文明尚未观察或踏足此地。地形、环境、资源和路线均保持未知。"))
		_add_expedition_button_if_available(detail)
		_detail_structure_signature = _get_detail_structure_signature()
		_update_detail_values()
		return
	for key in ["latitude", "longitude", "terrain", "zone_environment", "work_efficiency", "deposits", "fertility"]:
		_add_detail_label(detail, key)
	_add_detail_label(detail, "local_inventory")
	_add_settlement_controls(detail)
	_add_expedition_button_if_available(detail)
	_add_migration_button_if_available(detail, level)

	detail.add_child(_section_label("建筑"))
	var buildings: Array = GameState.entities.get_buildings_in_zone(selected_zone_id) if level >= GameState.settlement_system.ZoneKnowledgeLevel.FAMILIAR else []
	if buildings.is_empty():
		detail.add_child(_label("暂无建筑"))
	for building in buildings:
		detail.add_child(_make_building_card(building, zone))

	var build_button := Button.new()
	build_button.text = "+ 建造新建筑"
	build_button.disabled = level < GameState.settlement_system.ZoneKnowledgeLevel.FAMILIAR
	build_button.tooltip_text = "需要先熟悉或勘探该区域" if build_button.disabled else "建设会消耗该区域的地方库存"
	build_button.custom_minimum_size.y = 52.0
	build_button.pressed.connect(_open_build_menu)
	detail.add_child(build_button)
	_detail_structure_signature = _get_detail_structure_signature()
	_update_detail_values()


func _add_expedition_button_if_available(p_parent: VBoxContainer) -> void:
	if GameState.settlement_system == null or GameState.settlement_system.capital_zone_id < 0:
		return
	var origin_zone_id: int = _find_populated_neighbor(selected_zone_id)
	if origin_zone_id < 0:
		return
	var button := Button.new()
	var route_plan: Dictionary = GameState.region_movement_system.plan_route(origin_zone_id, selected_zone_id, GameState.planet_zones, GameState.settlement_system, true)
	button.text = "派出 5 人地面勘探队"
	button.tooltip_text = route_plan.get("cost_explanation", route_plan.get("message", "无法规划路线"))
	button.disabled = not route_plan.get("success", false)
	button.pressed.connect(_start_expedition.bind(origin_zone_id, selected_zone_id))
	p_parent.add_child(button)


func _find_populated_neighbor(p_target_zone_id: int) -> int:
	for neighbor_value in GameState.planet_zones.get_zone_neighbors(p_target_zone_id):
		var neighbor_id := int(neighbor_value)
		var knowledge: Dictionary = GameState.get_zone_knowledge(neighbor_id)
		if GameState.settlement_system.get_population(neighbor_id) > 0 and int(knowledge.get("level", 0)) >= GameState.settlement_system.ZoneKnowledgeLevel.FAMILIAR:
			return neighbor_id
	return -1


func _start_expedition(p_origin_zone_id: int, p_target_zone_id: int) -> void:
	var result: Dictionary = GameState.start_region_expedition(p_origin_zone_id, p_target_zone_id, 5)
	_show_message(result.get("message", ""), result.get("success", false))
	_refresh_data(true)


func _add_migration_button_if_available(p_parent: VBoxContainer, p_level: int) -> void:
	var capital_id: int = GameState.settlement_system.capital_zone_id
	if selected_zone_id == capital_id or p_level < GameState.settlement_system.ZoneKnowledgeLevel.FAMILIAR:
		return
	var route_plan: Dictionary = GameState.plan_region_route(capital_id, selected_zone_id)
	var button := Button.new()
	button.text = "迁入 5 人并携带 10 食物"
	button.disabled = not route_plan.get("success", false)
	button.tooltip_text = "%s；载荷会留在目标地地方库存" % route_plan.get("cost_explanation", route_plan.get("message", "无法规划路线"))
	button.pressed.connect(_start_migration.bind(capital_id, selected_zone_id))
	p_parent.add_child(button)
	var transport_button := Button.new()
	transport_button.text = "运输 10 食物（2 人往返）"
	transport_button.disabled = not route_plan.get("success", false)
	transport_button.tooltip_text = "%s；人员返程，载荷留在目标地" % route_plan.get("cost_explanation", route_plan.get("message", "无法规划路线"))
	transport_button.pressed.connect(_start_transport.bind(capital_id, selected_zone_id))
	p_parent.add_child(transport_button)


func _add_settlement_controls(p_parent: VBoxContainer) -> void:
	var settlement: Dictionary = GameState.get_settlement_view(selected_zone_id)
	if settlement.is_empty():
		return
	p_parent.add_child(_section_label("驻点与补给"))
	_add_detail_label(p_parent, "settlement_status")
	var settlement_type := str(settlement.get("type", "outpost"))
	if settlement_type == "outpost":
		var upgrade_status: Dictionary = GameState.get_outpost_upgrade_status(selected_zone_id)
		var upgrade_button := Button.new()
		upgrade_button.text = "升级为常设聚落"
		upgrade_button.disabled = not upgrade_status.get("success", false)
		upgrade_button.tooltip_text = str(upgrade_status.get("message", ""))
		upgrade_button.pressed.connect(_upgrade_selected_outpost)
		p_parent.add_child(upgrade_button)
	elif settlement_type == "settlement" and selected_zone_id != GameState.settlement_system.capital_zone_id:
		var relocate_button := Button.new()
		relocate_button.text = "迁都至该聚落"
		relocate_button.tooltip_text = "转移 10 名组织人员、25 铁材与文明档案；到达后将有一段协调损失"
		relocate_button.pressed.connect(_relocate_capital_to_selected_zone)
		p_parent.add_child(relocate_button)


func _upgrade_selected_outpost() -> void:
	var result: Dictionary = GameState.upgrade_outpost(selected_zone_id)
	_show_message(result.get("message", ""), result.get("success", false))
	_refresh_data(true)


func _relocate_capital_to_selected_zone() -> void:
	var result: Dictionary = GameState.start_capital_relocation(selected_zone_id)
	_show_message(result.get("message", ""), result.get("success", false))
	_refresh_data(true)


func _start_migration(p_origin_zone_id: int, p_target_zone_id: int) -> void:
	var result: Dictionary = GameState.start_region_migration(p_origin_zone_id, p_target_zone_id, 5, {"food": 10.0})
	_show_message(result.get("message", ""), result.get("success", false))
	_refresh_data(true)


func _start_transport(p_origin_zone_id: int, p_target_zone_id: int) -> void:
	var result: Dictionary = GameState.start_region_transport(p_origin_zone_id, p_target_zone_id, 2, {"food": 10.0})
	_show_message(result.get("message", ""), result.get("success", false))
	_refresh_data(true)


func _add_detail_label(parent: Node, key: String) -> Label:
	var label := _label("")
	_detail_labels[key] = label
	parent.add_child(label)
	return label


func _add_operation_cards(p_parent: VBoxContainer) -> void:
	if GameState.region_movement_system == null:
		return
	var active_operations: Array = []
	for operation in GameState.region_movement_system.operations.values():
		if int(operation.get("status", -1)) in [
			GameState.region_movement_system.OperationStatus.TRAVELLING,
			GameState.region_movement_system.OperationStatus.RETURNING,
			GameState.region_movement_system.OperationStatus.STRANDED,
			GameState.region_movement_system.OperationStatus.PAUSED,
		]:
			active_operations.append(operation)
	if active_operations.is_empty():
		return
	p_parent.add_child(_section_label("进行中的区域行动"))
	for operation_value in active_operations:
		var operation: Dictionary = operation_value
		var row := HBoxContainer.new()
		var status_names := ["前往目标", "返程", "补给耗尽", "已到达", "已取消", "已暂停"]
		var label := _label("%s · %d 人 · 当前 #%d · %.1f 天\n%s" % [
			operation.get("type", "行动"), operation.get("population_count", 0), operation.get("current_zone_id", -1),
			operation.get("elapsed_days", 0.0), status_names[clampi(int(operation.get("status", 0)), 0, status_names.size() - 1)],
		])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var pause_button := Button.new()
		var is_paused: bool = int(operation.get("status", -1)) == GameState.region_movement_system.OperationStatus.PAUSED
		pause_button.text = "继续" if is_paused else "暂停"
		pause_button.disabled = int(operation.get("status", -1)) == GameState.region_movement_system.OperationStatus.STRANDED
		pause_button.tooltip_text = "补给耗尽的队伍需先就地终止；暂停期间不消耗口粮" if pause_button.disabled else "暂停期间不推进路程，也不消耗口粮"
		if is_paused:
			pause_button.pressed.connect(_resume_operation.bind(str(operation.get("operation_id", ""))))
		else:
			pause_button.pressed.connect(_pause_operation.bind(str(operation.get("operation_id", ""))))
		row.add_child(pause_button)
		var cancel_button := Button.new()
		cancel_button.text = "就地终止"
		cancel_button.tooltip_text = "人员与未消耗物资留在当前区域；已消耗口粮不会返还"
		cancel_button.pressed.connect(_cancel_operation.bind(str(operation.get("operation_id", ""))))
		row.add_child(cancel_button)
		p_parent.add_child(row)


func _cancel_operation(p_operation_id: String) -> void:
	var result: Dictionary = GameState.cancel_region_operation(p_operation_id)
	_show_message(result.get("message", ""), result.get("success", false))
	_refresh_data(true)


func _pause_operation(p_operation_id: String) -> void:
	var result: Dictionary = GameState.pause_region_operation(p_operation_id)
	_show_message(result.get("message", ""), result.get("success", false))
	_refresh_data(true)


func _resume_operation(p_operation_id: String) -> void:
	var result: Dictionary = GameState.resume_region_operation(p_operation_id)
	_show_message(result.get("message", ""), result.get("success", false))
	_refresh_data(true)


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
			result = GameState.assign_regional_breeders(amount) if amount > 0 else {"success": false, "message": "没有闲置人口可分配"}
		"remove":
			amount = mini(amount, breeders)
			result = GameState.unassign_regional_breeders(amount) if amount > 0 else {"success": false, "message": "当前没有生育人口"}
		"fill":
			result = GameState.assign_regional_breeders(idle) if idle > 0 else {"success": false, "message": "没有闲置人口可分配"}
		"clear":
			result = GameState.unassign_regional_breeders(breeders) if breeders > 0 else {"success": false, "message": "当前没有生育人口"}
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
			result = GameState.assign_regional_building_workers(p_building_id, amount) if amount > 0 else {"success": false, "message": "没有空余岗位或闲置人口"}
		"remove":
			amount = mini(amount, building.assigned_workers)
			result = GameState.unassign_regional_building_workers(p_building_id, amount) if amount > 0 else {"success": false, "message": "当前建筑没有工人"}
		"fill":
			amount = mini(building.worker_capacity - building.assigned_workers, idle)
			result = GameState.assign_regional_building_workers(p_building_id, amount) if amount > 0 else {"success": false, "message": "没有空余岗位或闲置人口"}
		"clear":
			amount = building.assigned_workers
			result = GameState.unassign_regional_building_workers(p_building_id, amount) if amount > 0 else {"success": false, "message": "当前建筑没有工人"}
	var message: String = result.get("message", "")
	if result.get("success", false) and message.is_empty():
		message = "%s工人已更新：%d / %d" % [building.building_name, building.assigned_workers, building.worker_capacity]
	_show_message(message, result.get("success", false))
	_update_detail_values()


func _update_detail_values() -> void:
	if not GameState.game_started or _detail_labels.is_empty():
		return
	var average := _get_known_environment_average()
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
	var knowledge: Dictionary = GameState.get_zone_knowledge(selected_zone_id)
	if int(knowledge.get("level", 0)) == GameState.settlement_system.ZoneKnowledgeLevel.UNKNOWN:
		return
	var public_data: Dictionary = knowledge.get("public_data", {})
	_detail_labels["latitude"].text = "纬度中心：%.0f°" % public_data.get("latitude", zone.lat_center)
	_detail_labels["longitude"].text = "经度中心：%.0f°" % public_data.get("longitude", zone.lon_center)
	_detail_labels["terrain"].text = "地形：%s%s" % [public_data.get("terrain", "未知"), "（资料过时）" if knowledge.get("stale", false) else ""]
	_detail_labels["zone_environment"].text = "地表 %.1f℃  |  近地气温 %.1f℃  |  大气 %s\n辐射 %.2f  |  光照 %.0f%%" % [
		public_data.get("temperature", 0.0), public_data.get("air_temperature", public_data.get("temperature", 0.0)),
		public_data.get("atmosphere_state", "未知"), public_data.get("radiation", 0.0),
		float(public_data.get("light_intensity", 0.0)) * 100.0,
	]
	_detail_labels["work_efficiency"].text = "当地人口：%d  |  认知可信度 %.0f%%" % [GameState.settlement_system.get_population(selected_zone_id), float(knowledge.get("confidence", 0.0)) * 100.0]
	var estimates: Dictionary = public_data.get("resource_estimates", {})
	_detail_labels["deposits"].text = "矿藏估计：铁 %s  铜 %s  稀有 %s" % [_estimate_label(estimates, "iron"), _estimate_label(estimates, "copper"), _estimate_label(estimates, "rare_mineral")]
	_detail_labels["fertility"].text = "地表估计：肥沃度 %s  |  藻类 %s" % [_estimate_label(estimates, "fertility"), _estimate_label(estimates, "algae_density")]
	var local_inventory: Dictionary = GameState.regional_logistics.get_local_inventory(selected_zone_id)
	_detail_labels["local_inventory"].text = "地方库存：食物 %.1f  铁 %.1f  铜 %.1f" % [local_inventory.get("food", 0.0), local_inventory.get("iron", 0.0), local_inventory.get("copper", 0.0)]
	if _detail_labels.has("settlement_status"):
		var settlement: Dictionary = GameState.get_settlement_view(selected_zone_id)
		var type_names := {"capital": "首都", "settlement": "常设聚落", "outpost": "前哨"}
		_detail_labels["settlement_status"].text = "%s · %s\n庇护 %d 人 · 实际食物产出 %.2f/天 · 地方储备 %.1f 天 · 通信 %d 级" % [
			type_names.get(str(settlement.get("type", "outpost")), "驻点"), settlement.get("supply_status", "未评估"),
			settlement.get("shelter_capacity", 0), settlement.get("food_output_per_day", 0.0),
			settlement.get("food_reserve_days", 0.0), settlement.get("communication_level", 0),
		]

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


func _get_known_environment_average() -> Dictionary:
	var temperature_total := 0.0
	var radiation_total := 0.0
	var known_count := 0
	for summary_value in GameState.get_public_zone_summaries():
		var summary: Dictionary = summary_value
		if not bool(summary.get("known", false)):
			continue
		temperature_total += float(summary.get("temp", 0.0))
		radiation_total += float(summary.get("rad", 0.0))
		known_count += 1
	if known_count <= 0:
		return {"temperature": 0.0, "radiation": 0.0}
	return {"temperature": temperature_total / known_count, "radiation": radiation_total / known_count}


func _estimate_label(p_estimates: Dictionary, p_resource_id: String) -> String:
	if not p_estimates.has(p_resource_id) or not p_estimates[p_resource_id] is Dictionary:
		return "未知"
	return str(p_estimates[p_resource_id].get("label", "未知"))


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
		if availability.get("success", false):
			availability = GameState.regional_logistics.can_pay_local_cost(selected_zone_id, decision.resource_cost)
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
	var result: Dictionary = GameState.execute_regional_construction(p_decision_id, selected_zone_id)
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
