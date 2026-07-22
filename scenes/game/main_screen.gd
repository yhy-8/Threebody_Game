extends Control
## 游戏主界面 — 区域地表观测 + 边缘 HUD + 工具栏

const EntityManagerScript = preload("res://scripts/simulation/entity_manager.gd")
const TechTreeScript = preload("res://scripts/simulation/tech_tree.gd")
const SPEED_OPTIONS: Array[float] = [1.0, 2.0, 3.0, 5.0]
const DEVELOPER_RESOURCE_IDS: Array[String] = [
	"iron", "copper", "rare_mineral", "algae_fuel", "fossil_fuel", "electricity", "food",
]
const DEVELOPER_RESEARCH_IDS: Array[String] = ["basic", "applied", "theoretical"]

var _developer_inputs: Dictionary = {}
var _alert_active: bool = false
var _capital_selected_zone_id: int = -1
var _selectable_zone_ids: Array[int] = []
var _active_guidance_task_id: String = ""
var _last_guidance_phase: int = -1
var _compact_hint_deadline_msec: int = 0


func _ready() -> void:
	EventBus.screen_changed.emit("main_screen")
	_setup_buttons()
	_setup_developer_tools()

	# Start a new game if not already started
	if not GameState.game_started:
		GameState.new_game("新宇宙")

	_setup_zone_selector()
	# Listen for state updates
	GameState.state_updated.connect(_on_state_updated)
	_refresh_panels()


func _on_state_updated() -> void:
	_refresh_panels()


func _process(_p_delta: float) -> void:
	if _alert_active:
		var pulse := 0.08 + 0.07 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008))
		%AlertOverlay.color = Color(0.55, 0.0, 0.02, pulse)
	if GameState.opening_guidance != null and GameState.opening_guidance.mode == GameState.opening_guidance.GuidanceMode.COMPACT:
		if Time.get_ticks_msec() >= _compact_hint_deadline_msec:
			%GuidancePanel.visible = false


func _setup_buttons() -> void:
	%MenuButton.pressed.connect(_on_menu_pressed)
	%PauseButton.pressed.connect(_on_pause_pressed)
	%SpeedSlider.value_changed.connect(_on_speed_slider_changed)
	%TechTreeButton.pressed.connect(_on_tech_tree_pressed)
	%KnowledgePolicyButton.pressed.connect(_on_knowledge_policy_pressed)
	%GuidanceControlButton.pressed.connect(_open_guidance_controls)
	%DecisionButton.pressed.connect(_on_decision_pressed)
	%ZoneViewButton.pressed.connect(_on_zone_view_pressed)
	%StarmapButton.pressed.connect(_on_starmap_pressed)
	%DeveloperToolsButton.pressed.connect(_open_developer_tools)
	%CloseButton.pressed.connect(_close_developer_tools)
	%ApplyDeveloperButton.pressed.connect(_apply_developer_values)
	%FillResourcesButton.pressed.connect(_fill_developer_resources)
	%UnlockTechButton.pressed.connect(_unlock_all_technologies)
	%PreviousZoneButton.pressed.connect(_change_observed_zone.bind(-1))
	%NextZoneButton.pressed.connect(_change_observed_zone.bind(1))
	%ObservedZoneOption.item_selected.connect(_on_observed_zone_selected)
	%ConfirmCapitalButton.pressed.connect(_on_confirm_capital)
	%RecordObservationButton.pressed.connect(_on_record_observation)
	%SkipGuidanceButton.pressed.connect(_on_skip_guidance)
	%CloseGuidanceControlButton.pressed.connect(_close_guidance_controls)
	%DeferGuidanceGroupButton.pressed.connect(_toggle_guidance_group_deferred)
	%GuidanceModeOption.item_selected.connect(_on_guidance_mode_selected)
	%GuidanceModeOption.add_item("完整引导", 0)
	%GuidanceModeOption.add_item("精简提示", 1)
	%GuidanceModeOption.add_item("关闭引导", 2)
	_sync_speed_slider()


func _setup_zone_selector() -> void:
	%ObservedZoneOption.clear()
	_selectable_zone_ids.clear()
	if GameState.planet_zones == null:
		return
	for summary_value in GameState.get_public_zone_summaries():
		var summary: Dictionary = summary_value
		if not bool(summary.get("known", false)):
			continue
		var zone_id := int(summary.get("id", -1))
		%ObservedZoneOption.add_item("区域 #%02d · %s · %s" % [
			zone_id, summary.get("terrain", "未知"), summary.get("knowledge_name", "未知"),
		], zone_id)
		_selectable_zone_ids.append(zone_id)
	_select_zone_option(GameState.observed_zone_id)
	%ObservedZoneOption.tooltip_text = "只切换地表观察点；不会迁都、移动人口或改变建造目标。"


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.is_action_pressed("ui_cancel"):
		if %DeveloperOverlay.visible:
			get_viewport().set_input_as_handled()
			_close_developer_tools()
		elif %GuidanceControlOverlay.visible:
			get_viewport().set_input_as_handled()
			_close_guidance_controls()
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
	var entities_data: Dictionary = state["entities"]
	var resources_data: Dictionary = entities_data["resources"]
	var pop_data: Dictionary = entities_data["population"]
	var telescope_unlocked: bool = GameState.tech_tree.is_unlocked("telescope")
	var awaiting_capital: bool = GameState.settlement_system != null and GameState.settlement_system.capital_zone_id < 0
	%CapitalOverlay.visible = awaiting_capital
	%PauseButton.disabled = awaiting_capital
	%SpeedSlider.editable = not awaiting_capital
	for navigation_button in [%TechTreeButton, %KnowledgePolicyButton, %DecisionButton, %ZoneViewButton, %StarmapButton]:
		navigation_button.disabled = awaiting_capital
	if awaiting_capital:
		_refresh_capital_selection()
	else:
		_refresh_zone_selector_if_needed()
	%StarmapButton.disabled = not GameState.can_access_starmap()
	if awaiting_capital:
		%StarmapButton.disabled = true
	if GameState.developer_mode and not telescope_unlocked:
		%StarmapButton.text = "[开发者] 星图"
		%StarmapButton.tooltip_text = "开发者模式已绕过望远镜解锁条件"
	else:
		%StarmapButton.text = "星图" if not %StarmapButton.disabled else "[锁定] 星图"
		%StarmapButton.tooltip_text = "研发「望远镜」后解锁" if %StarmapButton.disabled else "进入3D星图"
	%DeveloperModeLabel.visible = GameState.developer_mode
	%DeveloperToolsButton.visible = GameState.developer_mode
	%PauseButton.text = "等待首都" if awaiting_capital else ("继续" if GameState.paused else "暂停")
	_sync_speed_slider()

	var resource_lines: Array[String] = []
	for group_name in ["矿物", "能源", "食物"]:
		resource_lines.append("— %s —" % group_name)
		for key in EntityManagerScript.RESOURCE_GROUPS.get(group_name, []):
			resource_lines.append("%s  %.1f" % [
				EntityManagerScript.RESOURCE_DISPLAY_NAMES.get(key, key),
				float(resources_data.get(key, 0.0)),
			])
	%ResourceSummary.text = "\n".join(resource_lines)
	%ResourceSummary.tooltip_text = "全局库存由各区域建筑产出与消耗共同改变；区域资源禀赋和工人效率会影响产量。"

	var rates: Dictionary = GameState.research_output_rate
	var research_lines: Array[String] = []
	for rtype in ["basic", "applied", "theoretical"]:
		research_lines.append("%s %.2f/天" % [TechTreeScript.RESEARCH_NAMES.get(rtype, rtype), rates.get(rtype, 0.0)])
	%CivilizationSummary.text = "人口  %d\n空闲  %d\n库存人口  %d / %d\n生育岗位  %d\n安定度  %.0f%%\n\n%s" % [
		pop_data.get("total", 0), GameState.entities.get_idle_population(),
		pop_data.get("stored_population", 0), pop_data.get("storage_capacity", 0),
		pop_data.get("breeders", 0), GameState.entities.social_stability * 100.0,
		"\n".join(research_lines),
	]
	%CivilizationSummary.tooltip_text = "人口会被生育、生产、教学与研究岗位占用；食物不足、危险环境和政策会影响健康与安定。"

	var zone = GameState.planet_zones.get_zone(GameState.observed_zone_id)
	if zone == null:
		return
	_select_zone_option(GameState.observed_zone_id)
	%RegionObservationView.set_observed_zone(GameState.observed_zone_id)
	%RegionObservationView.refresh_from_state(state)
	var zone_knowledge: Dictionary = GameState.get_zone_knowledge(GameState.observed_zone_id)
	var public_data: Dictionary = zone_knowledge.get("public_data", {})
	var live_visible := bool(zone_knowledge.get("live_visible", false))
	var buildings: Array = GameState.entities.get_buildings_in_zone(GameState.observed_zone_id) if live_visible else []
	if live_visible:
		%RegionInfoLabel.text = "区域 #%02d · %s\n地形  %s  ·  %.0f° / %.0f°\n温度  %.1f℃  ·  近地气温 %.1f℃\n辐射  %.2f  ·  光照 %.0f%%\n大气  %s\n人口  %d  ·  建筑 %d 座" % [
			zone.zone_id, zone_knowledge.get("level_name", "未知"), public_data.get("terrain", "未知"),
			public_data.get("latitude", zone.lat_center), public_data.get("longitude", zone.lon_center),
			public_data.get("temperature", 0.0), public_data.get("air_temperature", public_data.get("temperature", 0.0)),
			public_data.get("radiation", 0.0), float(public_data.get("light_intensity", 0.0)) * 100.0,
			public_data.get("atmosphere_state", "未知"), GameState.settlement_system.get_population(zone.zone_id), buildings.size(),
		]
	elif zone_knowledge.get("terrain_known", false):
		%RegionInfoLabel.text = "区域 #%02d · 实时未知\n地形记录  %s  ·  %.0f° / %.0f°\n\n当前无人覆盖。\n温度、辐射、光照与大气状态未知。" % [
			zone.zone_id, public_data.get("terrain", "未知"), public_data.get("latitude", zone.lat_center),
			public_data.get("longitude", zone.lon_center),
		]
	else:
		%RegionInfoLabel.text = "区域 #%02d · 未知\n\n文明尚未观察或踏足此地。" % zone.zone_id
	%RegionInfoLabel.tooltip_text = "这里只展示文明在当前认知等级下已知的区域信息。"
	%RecordObservationButton.disabled = not live_visible or GameState.settlement_system.get_population(zone.zone_id) <= 0
	var sky_lines: Array[String] = []
	for source_index in range(3):
		var observation: Dictionary = %RegionObservationView.get_body_altitude_azimuth(source_index)
		if observation.is_empty():
			continue
		sky_lines.append("恒星 %d  高度 %+.1f°  方位 %.1f°%s" % [
			source_index + 1,
			observation.get("altitude_degrees", 0.0),
			observation.get("azimuth_degrees", 0.0),
			"" if observation.get("above_horizon", false) else "（地平线下）",
		])
	%SkyInfoLabel.text = "\n".join(sky_lines)
	%SkyInfoLabel.tooltip_text = "方位角从当地正北起算并向东增加；高度小于 0° 的恒星被真实地平线遮挡。"

	var scenario: Dictionary = state.get("scenario", {})
	var rule_text: String
	if scenario.get("simulation_phase", "") == "STABLE_EPHEMERIS":
		var days_left: float = scenario.get("days_until_chaos", 0.0)
		var days_per_year: float = maxf(1.0, float(scenario.get("days_per_year", 1.0)))
		rule_text = "稳定纪元 %.1f 年" % (days_left / days_per_year)
	else:
		rule_text = "真实三体混沌"
	var forecast: Dictionary = state.get("hazard_forecast", {})
	var forecast_names := ["无文明预警", "定性天象预警", "区域风险预测", "伤亡区间预测", "高精度概率预测"]
	var forecast_level := clampi(int(forecast.get("level", 0)), 0, forecast_names.size() - 1)
	%GlobalResourceLabel.text = "食物 %.0f  ·  电力 %.0f  ·  铁 %.0f" % [
		resources_data.get("food", 0.0), resources_data.get("electricity", 0.0), resources_data.get("iron", 0.0),
	]
	%GlobalCivilizationLabel.text = "人口 %d  ·  空闲 %d  ·  %s" % [
		pop_data.get("total", 0), GameState.entities.get_idle_population(), forecast_names[forecast_level],
	]
	%GlobalTimeLabel.text = "第 %.1f 天  ·  %dx  ·  %s  ·  %s" % [
		state.get("game_time", 0.0), int(GameState.time_scale), "已暂停" if GameState.paused else "运行中", rule_text,
	]
	_update_alert(public_data)
	_refresh_guidance()


func _refresh_zone_selector_if_needed() -> void:
	var visible_ids: Array[int] = []
	for summary_value in GameState.get_public_zone_summaries():
		var summary: Dictionary = summary_value
		if bool(summary.get("known", false)):
			visible_ids.append(int(summary.get("id", -1)))
	if visible_ids != _selectable_zone_ids:
		_setup_zone_selector()


func _update_alert(p_public_zone: Dictionary) -> void:
	var causes: Array[String] = []
	var temperature := float(p_public_zone.get("temperature", 20.0))
	var radiation := float(p_public_zone.get("radiation", 0.0))
	if temperature < -80.0:
		causes.append("极端低温 %.1f℃" % temperature)
	elif temperature > 60.0:
		causes.append("极端高温 %.1f℃" % temperature)
	if radiation > 5.0:
		causes.append("高辐射 %.2f" % radiation)
	if GameState.entities.social_stability < 0.55:
		causes.append("社会安定度 %.0f%%" % (GameState.entities.social_stability * 100.0))
	_alert_active = not causes.is_empty()
	%AlertOverlay.visible = _alert_active
	%AlertBanner.visible = _alert_active
	%AlertBanner.text = "⚠ " + " · ".join(causes)
	%AlertBanner.tooltip_text = "警报来源：" + "；".join(causes)
	var alert_color := Color(1.0, 0.34, 0.34) if _alert_active else Color(0.76, 0.82, 0.96)
	%RegionInfoLabel.add_theme_color_override("font_color", alert_color)


func _change_observed_zone(p_direction: int) -> void:
	if _selectable_zone_ids.is_empty():
		return
	var current_index := _selectable_zone_ids.find(GameState.observed_zone_id)
	GameState.set_observed_zone(_selectable_zone_ids[wrapi(current_index + p_direction, 0, _selectable_zone_ids.size())])


func _on_observed_zone_selected(p_index: int) -> void:
	GameState.set_observed_zone(%ObservedZoneOption.get_item_id(p_index))


func _select_zone_option(p_zone_id: int) -> void:
	for index in range(%ObservedZoneOption.item_count):
		if %ObservedZoneOption.get_item_id(index) == p_zone_id:
			%ObservedZoneOption.select(index)
			return


func _refresh_capital_selection() -> void:
	if not %CapitalOverlay.visible or GameState.settlement_system == null:
		return
	if %CapitalCandidateList.get_child_count() == 0:
		for candidate_value in GameState.settlement_system.candidate_views:
			var candidate: Dictionary = candidate_value
			var known: Dictionary = candidate.get("known", {})
			var zone_id := int(candidate.get("zone_id", -1))
			var button := Button.new()
			button.text = "区域 #%02d  %s  %.1f℃  光照 %.0f%%" % [zone_id, known.get("terrain", "未知"), known.get("temperature", 0.0), float(known.get("light_intensity", 0.0)) * 100.0]
			button.custom_minimum_size = Vector2(0.0, 52.0)
			button.pressed.connect(_select_capital_candidate.bind(zone_id))
			%CapitalCandidateList.add_child(button)
	if _capital_selected_zone_id < 0 and not GameState.settlement_system.candidate_views.is_empty():
		_select_capital_candidate(int(GameState.settlement_system.candidate_views[0].get("zone_id", -1)))


func _select_capital_candidate(p_zone_id: int) -> void:
	var candidate: Dictionary = GameState.settlement_system.get_candidate_view(p_zone_id)
	if candidate.is_empty():
		return
	_capital_selected_zone_id = p_zone_id
	GameState.set_observed_zone(p_zone_id)
	var known: Dictionary = candidate.get("known", {})
	%CapitalDetailLabel.text = "区域 #%02d · %s\n温度 %.1f℃ · 辐射 %.2f · 光照 %.0f%%\n\n有利：%s\n困难：%s\n\n仍未知：%s\n可信度：%.0f%%\n%s" % [
		p_zone_id, known.get("terrain", "未知"), known.get("temperature", 0.0), known.get("radiation", 0.0), float(known.get("light_intensity", 0.0)) * 100.0,
		"；".join(candidate.get("reasons", [])), "；".join(candidate.get("known_difficulties", [])), "、".join(candidate.get("unknown_fields", [])),
		float(candidate.get("confidence", 0.0)) * 100.0, candidate.get("rule_note", ""),
	]


func _on_confirm_capital() -> void:
	var result: Dictionary = GameState.confirm_capital(_capital_selected_zone_id)
	%CapitalMessageLabel.text = result.get("message", "")
	if result.get("success", false):
		%CapitalOverlay.visible = false
		_setup_zone_selector()


func _on_record_observation() -> void:
	var result: Dictionary = GameState.record_local_observation(GameState.observed_zone_id)
	%RecordObservationButton.tooltip_text = result.get("message", "")


func _refresh_guidance() -> void:
	_clear_guidance_highlight()
	%GuidancePanel.visible = false
	_active_guidance_task_id = ""
	if GameState.opening_guidance == null or GameState.settlement_system.capital_zone_id < 0:
		return
	var tasks: Array = GameState.opening_guidance.get_active_task_views()
	if tasks.is_empty():
		return
	var task: Dictionary = tasks[0]
	var current_phase: int = GameState.opening_guidance.phase
	if GameState.opening_guidance.mode == GameState.opening_guidance.GuidanceMode.COMPACT:
		if current_phase != _last_guidance_phase:
			_last_guidance_phase = current_phase
			_compact_hint_deadline_msec = Time.get_ticks_msec() + 7000
		if Time.get_ticks_msec() >= _compact_hint_deadline_msec:
			return
	else:
		_last_guidance_phase = current_phase
	_active_guidance_task_id = str(task.get("id", ""))
	%GuidanceLabel.text = ("提示：" if task.get("compact", false) else "开局任务：") + str(task.get("text", ""))
	%SkipGuidanceButton.visible = bool(task.get("skippable", false))
	%SkipGuidanceButton.text = "进入自主发展" if _active_guidance_task_id == "opening:autonomy" else "跳过此步"
	%GuidancePanel.visible = true
	_apply_guidance_highlight(str(task.get("target", "")))


func _on_skip_guidance() -> void:
	if not _active_guidance_task_id.is_empty():
		if _active_guidance_task_id == "opening:autonomy":
			GameState.opening_guidance.handle_domain_event("guidance_closed", {"source_id": "guidance:autonomy"})
		else:
			GameState.opening_guidance.skip_task(_active_guidance_task_id)
		_refresh_guidance()


func _open_guidance_controls() -> void:
	if GameState.opening_guidance == null:
		return
	for index in range(%GuidanceModeOption.item_count):
		if %GuidanceModeOption.get_item_id(index) == GameState.opening_guidance.mode:
			%GuidanceModeOption.select(index)
			break
	var completed_count: int = GameState.opening_guidance.completed_task_ids.size()
	var skipped_count: int = GameState.opening_guidance.skipped_task_ids.size()
	var total_count: int = GameState.opening_guidance.TASKS.size()
	var active_tasks: Array = GameState.opening_guidance.get_active_task_views()
	var current_text := "当前无教学任务"
	if GameState.opening_guidance.group_deferred:
		current_text = "开局任务已暂缓：%s" % GameState.opening_guidance.group_deferred_reason
	elif not active_tasks.is_empty():
		current_text = str(active_tasks[0].get("text", ""))
	%GuidanceControlSummary.text = "已完成 %d / %d · 已跳过 %d\n\n%s\n\n切换模式只改变提示呈现，不执行命令，也不改变世界。" % [completed_count, total_count, skipped_count, current_text]
	%DeferGuidanceGroupButton.text = "恢复开局任务" if GameState.opening_guidance.group_deferred else "暂缓整组引导"
	%DeferGuidanceGroupButton.disabled = (
		GameState.opening_guidance.phase == GameState.opening_guidance.OpeningPhase.COMPLETE
		or (GameState.opening_guidance.mode == GameState.opening_guidance.GuidanceMode.OFF and not GameState.opening_guidance.group_deferred)
	)
	%GuidanceControlOverlay.visible = true


func _close_guidance_controls() -> void:
	%GuidanceControlOverlay.visible = false


func _on_guidance_mode_selected(p_index: int) -> void:
	if GameState.opening_guidance == null:
		return
	var mode: int = %GuidanceModeOption.get_item_id(p_index)
	GameState.opening_guidance.set_mode(mode)
	_last_guidance_phase = -1
	_refresh_guidance()
	_open_guidance_controls()


func _toggle_guidance_group_deferred() -> void:
	if GameState.opening_guidance == null:
		return
	if GameState.opening_guidance.group_deferred:
		GameState.opening_guidance.resume_guidance()
	else:
		GameState.opening_guidance.defer_group("玩家选择稍后继续")
	_last_guidance_phase = -1
	_refresh_guidance()
	_open_guidance_controls()


func _clear_guidance_highlight() -> void:
	for control in [%PauseButton, %KnowledgePolicyButton, %ZoneViewButton, %RecordObservationButton, %GuidanceControlButton]:
		control.self_modulate = Color.WHITE


func _apply_guidance_highlight(p_semantic_target: String) -> void:
	var target: Control = null
	if p_semantic_target == "time.controls":
		target = %PauseButton
	elif p_semantic_target in ["population.assignment", "region.construction", "region.food_security", "exploration.plan"]:
		target = %ZoneViewButton
	elif p_semantic_target == "knowledge.teaching_plans":
		target = %KnowledgePolicyButton
	elif p_semantic_target == "observation.record":
		target = %RecordObservationButton
	elif p_semantic_target == "guidance.handbook":
		target = %GuidanceControlButton
	if target != null:
		target.self_modulate = Color(1.0, 0.86, 0.42)


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


func _on_knowledge_policy_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/knowledge/knowledge_policy.tscn")


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
