extends Control
## Planet-zone browser, construction screen, and workforce management.

const EntityManagerScript = preload("res://scripts/simulation/entity_manager.gd")

var view_mode: String = "temperature"
var selected_zone_id: int = -1
var _refresh_elapsed: float = 0.0


func _ready() -> void:
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


func _refresh_data() -> void:
	if not GameState.game_started:
		return
	%ZoneMap.set_data(GameState.planet_zones.get_all_zones_summary())
	_refresh_detail()


func _on_zone_selected(p_zone_id: int) -> void:
	selected_zone_id = p_zone_id
	%ZoneMap.set_selected_zone(p_zone_id)
	_refresh_detail()


func _refresh_detail() -> void:
	if not GameState.game_started:
		return
	var detail: VBoxContainer = %DetailVBox
	_clear_children(detail)
	var average: Dictionary = GameState.planet_zones.get_average_environment()
	detail.add_child(_section_label("全球概览"))
	detail.add_child(_label("自转角度：%.1f°" % GameState.planet_zones.rotation_angle))
	detail.add_child(_label("平均温度：%.1f℃" % average.get("temperature", 0.0)))
	detail.add_child(_label("平均辐射：%.2f" % average.get("radiation", 0.0)))
	detail.add_child(_label("总人口：%d    闲置：%d" % [
		GameState.entities.population.total, GameState.entities.get_idle_population(),
	]))
	detail.add_child(_label("库存人口：%d / %d" % [
		GameState.entities.population.stored_population,
		GameState.entities.population.storage_capacity,
	]))
	detail.add_child(_make_breeder_row())

	if selected_zone_id < 0:
		detail.add_child(_section_label("区域详情"))
		detail.add_child(_label("← 点击左侧网格选择区域"))
		return

	var zone = GameState.planet_zones.get_zone(selected_zone_id)
	if zone == null:
		return
	detail.add_child(_section_label("区域 #%d" % selected_zone_id))
	detail.add_child(_label("纬度：%.0f° — %.0f°" % [zone.lat_bottom, zone.lat_top]))
	detail.add_child(_label("经度：%.0f° — %.0f°" % [zone.lon_left, zone.lon_right]))
	detail.add_child(_label("地形：%s" % zone.terrain_type))
	detail.add_child(_label("温度 %.1f℃  |  辐射 %.2f  |  光照 %.0f%%" % [
		zone.temperature, zone.radiation, zone.light_intensity * 100.0,
	]))
	detail.add_child(_label("工作效率：%.0f%%" % (zone.get_work_efficiency() * 100.0)))
	detail.add_child(_label("资源禀赋：铁 %.2f  铜 %.2f  稀有 %.2f" % [
		zone.resource_deposits.get("iron", 0.0),
		zone.resource_deposits.get("copper", 0.0),
		zone.resource_deposits.get("rare_mineral", 0.0),
	]))
	detail.add_child(_label("肥沃度 %.0f%%  |  藻类密度 %.0f%%" % [zone.fertility * 100.0, zone.algae_density * 100.0]))

	detail.add_child(_section_label("建筑"))
	var buildings: Array = GameState.entities.get_buildings_in_zone(selected_zone_id)
	if buildings.is_empty():
		detail.add_child(_label("暂无建筑"))
	for building in buildings:
		detail.add_child(_make_building_card(building, zone))

	var build_button := Button.new()
	build_button.text = "+ 建造新建筑"
	build_button.pressed.connect(_open_build_menu)
	detail.add_child(build_button)


func _make_breeder_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := _label("生育分配：%d 人" % GameState.entities.population.breeders)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var minus := Button.new()
	minus.text = "−"
	minus.tooltip_text = "Shift: 5人，Ctrl: 全部取消"
	minus.pressed.connect(_change_breeders.bind(-1))
	row.add_child(minus)
	var plus := Button.new()
	plus.text = "+"
	plus.tooltip_text = "Shift: 5人，Ctrl: 分配所有闲置人口"
	plus.pressed.connect(_change_breeders.bind(1))
	row.add_child(plus)
	return row


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
		var worker_row := HBoxContainer.new()
		var worker_label := _label("工人：%d / %d" % [building.assigned_workers, building.worker_capacity])
		worker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		worker_row.add_child(worker_label)
		var minus := Button.new()
		minus.text = "−"
		minus.tooltip_text = "Shift: 5人，Ctrl: 全部撤回"
		minus.pressed.connect(_change_workers.bind(building.id, -1))
		worker_row.add_child(minus)
		var plus := Button.new()
		plus.text = "+"
		plus.tooltip_text = "Shift: 5人，Ctrl: 填满岗位"
		plus.pressed.connect(_change_workers.bind(building.id, 1))
		worker_row.add_child(plus)
		box.add_child(worker_row)

	var output: Dictionary = building.get_output(
		GameState.entities.population.automation_multiplier, zone.get_work_efficiency()
	)
	if not output.is_empty():
		var parts: Array[String] = []
		for resource_name in output:
			parts.append("%s +%.1f/天" % [
				EntityManagerScript.RESOURCE_DISPLAY_NAMES.get(resource_name, resource_name), output[resource_name],
			])
		box.add_child(_label("产出：" + "  ".join(parts)))
	if not building.consumption.is_empty():
		var parts: Array[String] = []
		for resource_name in building.consumption:
			parts.append("%s %.1f/天" % [
				EntityManagerScript.RESOURCE_DISPLAY_NAMES.get(resource_name, resource_name), building.consumption[resource_name],
			])
		box.add_child(_label("消耗：" + "  ".join(parts)))
	return card


func _change_breeders(p_direction: int) -> void:
	var amount := _modified_amount()
	var result: Dictionary
	if p_direction > 0:
		if Input.is_key_pressed(KEY_CTRL):
			amount = GameState.entities.get_idle_population()
		result = GameState.entities.assign_breeders(amount)
	else:
		if Input.is_key_pressed(KEY_CTRL):
			amount = GameState.entities.population.breeders
		result = GameState.entities.unassign_breeders(amount)
	_show_message(result.get("message", "人口分配已更新"), result.get("success", false))
	_refresh_detail()


func _change_workers(p_building_id: int, p_direction: int) -> void:
	var building = GameState.entities.get_building(p_building_id)
	if building == null:
		return
	var amount := _modified_amount()
	var result: Dictionary
	if p_direction > 0:
		if Input.is_key_pressed(KEY_CTRL):
			amount = min(building.worker_capacity - building.assigned_workers, GameState.entities.get_idle_population())
		result = GameState.entities.assign_worker_to_building(p_building_id, amount)
	else:
		if Input.is_key_pressed(KEY_CTRL):
			amount = building.assigned_workers
		result = GameState.entities.unassign_worker_from_building(p_building_id, amount)
	_show_message(result.get("message", "工人分配已更新"), result.get("success", false))
	_refresh_detail()


func _modified_amount() -> int:
	return 5 if Input.is_key_pressed(KEY_SHIFT) else 1


func _open_build_menu() -> void:
	if selected_zone_id < 0:
		return
	%BuildTitle.text = "在区域 #%d 建造新建筑" % selected_zone_id
	_clear_children(%BuildList)
	for decision in GameState.decision_manager.get_construction_decisions():
		var availability: Dictionary = GameState.decision_manager.can_execute(
			decision.id, GameState.entities, GameState.tech_tree
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
	_refresh_data()


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
