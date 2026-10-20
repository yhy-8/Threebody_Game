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
var _objectives_button: Button
var _event_button: Button
var _hazard_button: Button
var _objectives_modal: Dictionary = {}
var _event_modal: Dictionary = {}
var _hazard_modal: Dictionary = {}
var _selected_hazard_priority: String = "balanced"
var _hazard_ui_elapsed: float = 0.0


func _ready() -> void:
	EventBus.screen_changed.emit("main_screen")
	_setup_buttons()
	_setup_developer_tools()
	_setup_progression_ui()

	# Start a new game if not already started
	if not GameState.game_started:
		GameState.new_game("新宇宙")

	_setup_zone_selector()
	# Listen for state updates
	GameState.state_updated.connect(_on_state_updated)
	_refresh_panels()


func _on_state_updated() -> void:
	_refresh_panels()


func _process(p_delta: float) -> void:
	if _alert_active:
		var pulse := 0.08 + 0.07 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008))
		%AlertOverlay.color = Color(0.55, 0.0, 0.02, pulse)
	if GameState.opening_guidance != null and GameState.opening_guidance.mode == GameState.opening_guidance.GuidanceMode.COMPACT:
		if Time.get_ticks_msec() >= _compact_hint_deadline_msec:
			%GuidancePanel.visible = false
	if _hazard_modal.get("backdrop", null) != null and _hazard_modal["backdrop"].visible:
		_hazard_ui_elapsed += p_delta
		if _hazard_ui_elapsed >= 1.0:
			_hazard_ui_elapsed = 0.0
			_rebuild_hazard_content()


func _setup_buttons() -> void:
	%MenuButton.pressed.connect(_on_menu_pressed)
	%PauseButton.pressed.connect(_on_pause_pressed)
	%SpeedSlider.value_changed.connect(_on_speed_slider_changed)
	%TechTreeButton.pressed.connect(_on_tech_tree_pressed)
	%EventsButton.pressed.connect(_open_event_log)
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
	%CloseEventsButton.pressed.connect(_close_event_log)
	%GameOverEventsButton.pressed.connect(_open_event_log)
	%GameOverMenuButton.pressed.connect(_return_to_main_menu)
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
		if _hazard_modal.get("backdrop", null) != null and _hazard_modal["backdrop"].visible:
			get_viewport().set_input_as_handled()
			_hazard_modal["backdrop"].visible = false
		elif _event_modal.get("backdrop", null) != null and _event_modal["backdrop"].visible:
			get_viewport().set_input_as_handled()
			_event_modal["backdrop"].visible = false
		elif _objectives_modal.get("backdrop", null) != null and _objectives_modal["backdrop"].visible:
			get_viewport().set_input_as_handled()
			_objectives_modal["backdrop"].visible = false
		elif %DeveloperOverlay.visible:
			get_viewport().set_input_as_handled()
			_close_developer_tools()
		elif %GuidanceControlOverlay.visible:
			get_viewport().set_input_as_handled()
			_close_guidance_controls()
		elif %EventLogOverlay.visible:
			get_viewport().set_input_as_handled()
			_close_event_log()
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
	var management: Dictionary = GameState.get_management_snapshot()
	var resource_flow: Dictionary = management.get("resource_flow", {})
	var power: Dictionary = management.get("power", {})
	var telescope_unlocked: bool = GameState.tech_tree.is_unlocked("telescope")
	var awaiting_capital: bool = GameState.settlement_system != null and GameState.settlement_system.capital_zone_id < 0
	%CapitalOverlay.visible = awaiting_capital
	%PauseButton.disabled = awaiting_capital
	%SpeedSlider.editable = not awaiting_capital
	for navigation_button in [%TechTreeButton, %DecisionButton, %ZoneViewButton, %StarmapButton]:
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
			if key == "electricity":
				var priority_note := ""
				if GameState.entities.is_power_priority_active():
					priority_note = " · 维生优先 %.0f 天" % GameState.entities.power_priority_days_remaining
				resource_lines.append("电力  %.1f / %.1f kW（余量 %+.1f）%s" % [
					power.get("generation", 0.0),
					power.get("consumption", 0.0),
					float(power.get("generation", 0.0)) - float(power.get("consumption", 0.0)),
					priority_note,
				])
				continue
			var flow: Dictionary = resource_flow.get(key, {})
			resource_lines.append("%s  %.1f（%+.1f/天）" % [
				EntityManagerScript.RESOURCE_DISPLAY_NAMES.get(key, key),
				float(resources_data.get(key, 0.0)),
				float(flow.get("net", 0.0)),
			])
	var food_net := float((resource_flow.get("food", {}) as Dictionary).get("net", 0.0))
	if food_net < -0.001:
		resource_lines.append("口粮可维持约 %.1f 天" % (
			float(resources_data.get("food", 0.0)) / -food_net
		))
	var objectives_view: Dictionary = GameState.get_objectives_view()
	if not objectives_view.is_empty():
		var current_objective: Dictionary = objectives_view.get("current", {})
		resource_lines.append("— 文明进程 —")
		resource_lines.append("%s · %s" % [
			objectives_view.get("era", {}).get("name", "求生纪元"),
			current_objective.get("title", "阶段目标"),
		])
		resource_lines.append("进度 %.0f%% · %d/%d" % [
			float(current_objective.get("progress", 0.0)) * 100.0,
			int(objectives_view.get("completed_count", 0)),
			int(objectives_view.get("total_count", 0)),
		])
	%ResourceSummary.text = "\n".join(resource_lines)
	%ResourceSummary.tooltip_text = "括号内为最近模拟步的实际净流量；电力显示实时发电/负荷，不再伪装成库存。"

	var rates: Dictionary = GameState.research_output_rate
	var research_lines: Array[String] = []
	for rtype in ["basic", "applied", "theoretical"]:
		research_lines.append("%s %.2f/天" % [TechTreeScript.RESEARCH_NAMES.get(rtype, rtype), rates.get(rtype, 0.0)])
	var building_workers: int = GameState.entities.get_total_building_workers()
	var external_workers := int(management.get("external_reserved_workers", 0))
	%CivilizationSummary.text = "人口  %d\n空闲  %d\n生产/施工  %d\n研究/教学/在途  %d\n库存人口  %d / %d\n生育岗位  %d\n安定度  %.0f%%\n\n%s" % [
		pop_data.get("total", 0), GameState.entities.get_idle_population(),
		building_workers, external_workers,
		pop_data.get("stored_population", 0), pop_data.get("storage_capacity", 0),
		pop_data.get("breeders", 0), GameState.entities.social_stability * 100.0,
		"\n".join(research_lines),
	]
	%CivilizationSummary.tooltip_text = "人口会被生育、生产、教学与研究岗位占用；食物不足、危险环境和政策会影响健康与安定。安定度与健康低于 100% 时会降低实际生产效率。"

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
	%GlobalResourceLabel.text = "食物 %.0f（%+.1f/天） · 电力 %.0f/%.0f kW · 铁 %.0f" % [
		resources_data.get("food", 0.0), food_net,
		power.get("generation", 0.0), power.get("consumption", 0.0),
		resources_data.get("iron", 0.0),
	]
	%GlobalCivilizationLabel.text = "人口 %d  ·  空闲 %d  ·  %s" % [
		pop_data.get("total", 0), GameState.entities.get_idle_population(), forecast_names[forecast_level],
	]
	%GlobalTimeLabel.text = "第 %.1f 天  ·  %dx  ·  %s  ·  %s" % [
		state.get("game_time", 0.0), int(GameState.time_scale), "已暂停" if GameState.paused else "运行中", rule_text,
	]
	var latest_event: Dictionary = management.get("latest_event", {})
	if GameState.notifications_enabled() and not latest_event.is_empty():
		%LatestEventLabel.text = "第 %.1f 天 · %s：%s" % [
			latest_event.get("game_day", 0.0),
			latest_event.get("title", "事件"),
			latest_event.get("detail", ""),
		]
	else:
		%LatestEventLabel.text = "通知显示已关闭；完整事件仍可在「事件」中查看"
	%LatestEventLabel.tooltip_text = str(latest_event.get("detail", ""))
	%GameOverOverlay.visible = GameState.game_over and not %EventLogOverlay.visible
	%GameOverReason.text = GameState.game_over_reason
	_update_alert(public_data)
	_refresh_progression_buttons(management, objectives_view)
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
	var food_stock: float = GameState.entities.get_resource("food")
	var food_flow: Dictionary = GameState.entities.get_resource_flow_snapshot().get("food", {})
	var food_net: float = float(food_flow.get("net", 0.0))
	if food_stock <= 0.01:
		causes.append("食物耗尽")
	elif food_net < -0.001 and food_stock / -food_net < 5.0:
		causes.append("口粮仅可维持 %.1f 天" % (food_stock / -food_net))
	var power: Dictionary = GameState.entities.get_electricity_balance()
	if (
		float(power.get("consumption", 0.0)) > 0.01
		and float(power.get("generation", 0.0)) + 0.01 < float(power.get("consumption", 0.0))
	):
		causes.append("电力缺口 %.1f kW" % (
			float(power.get("consumption", 0.0)) - float(power.get("generation", 0.0))
		))
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
	for control in [%PauseButton, %TechTreeButton, %ZoneViewButton, %RecordObservationButton, %GuidanceControlButton]:
		control.self_modulate = Color.WHITE


func _apply_guidance_highlight(p_semantic_target: String) -> void:
	var target: Control = null
	if p_semantic_target == "time.controls":
		target = %PauseButton
	elif p_semantic_target in ["population.assignment", "region.construction", "region.food_security", "exploration.plan"]:
		target = %ZoneViewButton
	elif p_semantic_target == "knowledge.teaching_plans":
		target = %TechTreeButton
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


func _open_event_log() -> void:
	var lines: Array[String] = []
	var severity_colors := {
		"critical": "#ff6868",
		"important": "#ffd078",
		"info": "#a8c8ff",
	}
	for event_value in GameState.get_recent_events(100):
		var event: Dictionary = event_value
		var color: String = severity_colors.get(str(event.get("severity", "info")), "#d0d8ef")
		lines.append("[color=%s][b]第 %.1f 天 · %s[/b][/color]\n%s" % [
			color,
			event.get("game_day", 0.0),
			event.get("title", "事件"),
			event.get("detail", ""),
		])
	%EventLogText.text = "\n\n".join(lines) if not lines.is_empty() else "尚无文明事件。"
	%EventLogOverlay.visible = true
	%GameOverOverlay.visible = false


func _close_event_log() -> void:
	%EventLogOverlay.visible = false
	%GameOverOverlay.visible = GameState.game_over


func _return_to_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/initial_menu.tscn")


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


# ── 文明进程、事件抉择与危机响应 ─────────────────────────

func _setup_progression_ui() -> void:
	var toolbar: HBoxContainer = $Toolbar
	_objectives_button = Button.new()
	_objectives_button.name = "ObjectivesButton"
	_objectives_button.text = "目标"
	_objectives_button.custom_minimum_size = Vector2(76.0, 48.0)
	_objectives_button.tooltip_text = "查看文明阶段、当前目标与全部里程碑"
	_objectives_button.pressed.connect(_open_objectives)
	toolbar.add_child(_objectives_button)

	_event_button = Button.new()
	_event_button.name = "CivilizationEventButton"
	_event_button.text = "抉择"
	_event_button.custom_minimum_size = Vector2(76.0, 48.0)
	_event_button.tooltip_text = "处理由真实文明状态触发的社会抉择"
	_event_button.pressed.connect(_open_event)
	toolbar.add_child(_event_button)

	_hazard_button = Button.new()
	_hazard_button.name = "HazardResponseButton"
	_hazard_button.text = "危机"
	_hazard_button.custom_minimum_size = Vector2(84.0, 48.0)
	_hazard_button.tooltip_text = "查看区域环境压力、庇护容量并确认响应预案"
	_hazard_button.pressed.connect(_open_hazard)
	toolbar.add_child(_hazard_button)

	_objectives_modal = _create_modal("ObjectivesOverlay", Vector2(980.0, 720.0))
	_event_modal = _create_modal("CivilizationEventOverlay", Vector2(900.0, 640.0))
	_hazard_modal = _create_modal("HazardResponseOverlay", Vector2(1000.0, 740.0))


func _create_modal(p_name: String, p_size: Vector2) -> Dictionary:
	var backdrop := ColorRect.new()
	backdrop.name = p_name
	backdrop.color = Color(0.0, 0.0, 0.0, 0.62)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.visible = false
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = p_size
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 26)
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.custom_minimum_size = Vector2(104.0, 46.0)
	close_button.pressed.connect(func(): backdrop.visible = false)
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, p_size.y - 136.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)

	var message := Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(0.0, 40.0)
	message.add_theme_font_size_override("font_size", 17)
	root.add_child(message)

	return {
		"backdrop": backdrop,
		"title": title,
		"body": body,
		"message": message,
	}


func _refresh_progression_buttons(p_management: Dictionary, p_objectives_view: Dictionary) -> void:
	if _objectives_button == null:
		return
	_objectives_button.text = "目标 %d/%d" % [
		int(p_objectives_view.get("completed_count", 0)),
		int(p_objectives_view.get("total_count", 0)),
	]
	var pending: Dictionary = GameState.get_pending_civilization_event()
	var has_pending := not pending.is_empty()
	_event_button.text = "抉择!" if has_pending else "抉择"
	_event_button.modulate = Color(1.0, 0.86, 0.5) if has_pending else Color.WHITE
	_event_button.tooltip_text = (
		"待决事件：%s" % str(pending.get("title", ""))
		if has_pending
		else "当前没有待决事件；真实社会压力出现时这里会亮起"
	)
	var hazard: Dictionary = p_management.get("hazard", {})
	var active: Dictionary = hazard.get("active_hazard", {})
	var assessment: Dictionary = hazard.get("latest_assessment", {})
	var stressed := (
		not active.is_empty()
		or float(assessment.get("trigger_score", 0.0)) > 0.0
	)
	_hazard_button.text = "危机中" if not active.is_empty() else ("预警!" if stressed else "危机")
	_hazard_button.modulate = (
		Color(1.0, 0.52, 0.45) if not active.is_empty()
		else (Color(1.0, 0.84, 0.45) if stressed else Color.WHITE)
	)


func _open_objectives() -> void:
	if _objectives_modal.is_empty():
		return
	var view: Dictionary = GameState.get_objectives_view()
	var body: VBoxContainer = _objectives_modal["body"]
	_clear_children(body)
	_objectives_modal["title"].text = "文明进程 · %s" % str(view.get("era", {}).get("name", "求生纪元"))
	_objectives_modal["message"].text = str(view.get("era", {}).get("note", ""))
	if view.is_empty():
		body.add_child(_body_label("文明尚未建立，暂无阶段目标。", Color(0.8, 0.84, 0.95)))
		_objectives_modal["backdrop"].visible = true
		return
	var current: Dictionary = view.get("current", {})
	body.add_child(_section_label("当前目标"))
	body.add_child(_objective_card(current, true))
	var completed_ids: Array = []
	for value in view.get("all", []):
		var objective: Dictionary = value
		if bool(objective.get("complete", false)):
			completed_ids.append(str(objective.get("id", "")))
	body.add_child(_section_label("全部里程碑（已完成 %d / %d）" % [
		completed_ids.size(), int(view.get("total_count", 0)),
	]))
	for value in view.get("all", []):
		var objective: Dictionary = value
		if bool(objective.get("complete", false)) and str(objective.get("id", "")) == str(current.get("id", "")):
			continue
		body.add_child(_objective_card(objective, false))
	_objectives_modal["backdrop"].visible = true


func _objective_card(p_objective: Dictionary, p_is_current: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0.0, 112.0 if p_is_current else 96.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var complete := bool(p_objective.get("complete", false))
	var header := Label.new()
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.text = "%s %s%s" % [
		"✓" if complete else ("◆" if p_is_current else "·"),
		str(p_objective.get("title", "")),
		"（当前）" if p_is_current and not complete else "",
	]
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override(
		"font_color",
		Color(0.55, 0.95, 0.65) if complete else (Color(1.0, 0.86, 0.45) if p_is_current else Color(0.78, 0.84, 0.96))
	)
	box.add_child(header)

	var description := Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.text = str(p_objective.get("description", ""))
	description.add_theme_font_size_override("font_size", 16)
	description.add_theme_color_override("font_color", Color(0.72, 0.78, 0.92))
	box.add_child(description)

	var progress := ProgressBar.new()
	progress.min_value = 0.0
	progress.max_value = 1.0
	progress.value = float(p_objective.get("progress", 0.0))
	progress.show_percentage = true
	progress.custom_minimum_size = Vector2(0.0, 22.0)
	box.add_child(progress)

	var footer := Label.new()
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var completed_day := float(p_objective.get("completed_day", -1.0))
	if complete and completed_day >= 0.0:
		footer.text = "已于第 %.1f 天完成 · %s" % [
			completed_day, str(p_objective.get("target_text", "")),
		]
	else:
		footer.text = "%s · %s\n提示：%s" % [
			str(p_objective.get("target_text", "")),
			str(p_objective.get("detail", "")),
			str(p_objective.get("hint", "")),
		]
	footer.add_theme_font_size_override("font_size", 15)
	footer.add_theme_color_override("font_color", Color(0.65, 0.72, 0.88))
	box.add_child(footer)
	var target_scene := str(p_objective.get("target_scene", ""))
	if p_is_current and not complete and not target_scene.is_empty():
		var go_button := Button.new()
		go_button.name = "ObjectiveGoButton"
		go_button.custom_minimum_size = Vector2(150.0, 42.0)
		go_button.text = (
			"前往知识图 →"
			if target_scene.contains("tech_tree")
			else "前往区域/建筑 →"
		)
		go_button.tooltip_text = "打开与该目标直接相关的操作界面；不会自动执行任何命令。"
		go_button.pressed.connect(func(): get_tree().change_scene_to_file(target_scene))
		box.add_child(go_button)
	return card


func _open_event() -> void:
	if _event_modal.is_empty():
		return
	_event_modal["message"].text = ""
	_rebuild_event_content()
	_event_modal["backdrop"].visible = true


func _rebuild_event_content() -> void:
	var body: VBoxContainer = _event_modal["body"]
	_clear_children(body)
	var pending: Dictionary = GameState.get_pending_civilization_event()
	if pending.is_empty():
		_event_modal["title"].text = "社会抉择"
		body.add_child(_body_label(
			"当前没有待决事件。\n\n当食物、寒冷、设备磨损、知识传承或电力等真实状态出现压力时，文明会提出需要玩家决定的事项。",
			Color(0.74, 0.80, 0.94)
		))
		return
	_event_modal["title"].text = "社会抉择 · %s" % str(pending.get("title", ""))
	body.add_child(_body_label(str(pending.get("description", "")), Color(0.82, 0.87, 0.98)))
	body.add_child(_section_label("可选方案"))
	for value in pending.get("choices", []):
		var choice: Dictionary = value
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 70.0)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var unavailable_reason := _event_choice_unavailable_reason(choice)
		button.text = "%s\n%s%s" % [
			str(choice.get("label", "")),
			GameState.civilization_events.describe_effects(choice),
			"（%s）" % unavailable_reason if not unavailable_reason.is_empty() else "",
		]
		button.tooltip_text = (
			unavailable_reason
			if not unavailable_reason.is_empty()
			else str(choice.get("result", ""))
		)
		button.disabled = not unavailable_reason.is_empty()
		button.pressed.connect(_resolve_civilization_event.bind(str(choice.get("id", ""))))
		body.add_child(button)


func _event_choice_unavailable_reason(p_choice: Dictionary) -> String:
	var effects: Dictionary = p_choice.get("effects", {})
	var resources: Dictionary = effects.get("resource", {})
	for resource_id in resources:
		var amount := float(resources[resource_id])
		if amount < 0.0 and GameState.entities.get_resource(str(resource_id)) + 1e-6 < -amount:
			return "资源不足：%s 需要 %.1f，当前 %.1f" % [
				str(resource_id), -amount, GameState.entities.get_resource(str(resource_id)),
			]
	var breeders := int(effects.get("breeders", 0))
	if breeders > 0 and GameState.entities.get_idle_population() < breeders:
		return "闲置人口不足，需要 %d 人" % breeders
	var policy_id := str(effects.get("policy", ""))
	if (
		not policy_id.is_empty()
		and GameState.decision_manager != null
		and policy_id in GameState.decision_manager.active_policies
	):
		return "该政策已在运行"
	return ""


func _resolve_civilization_event(p_choice_id: String) -> void:
	var result: Dictionary = GameState.resolve_civilization_event(p_choice_id)
	if _event_modal.is_empty():
		return
	_event_modal["message"].text = str(result.get("message", ""))
	_event_modal["message"].add_theme_color_override(
		"font_color",
		Color(0.55, 0.95, 0.65) if bool(result.get("success", false)) else Color(1.0, 0.55, 0.45)
	)
	_rebuild_event_content()
	_refresh_panels()


func _open_hazard() -> void:
	if _hazard_modal.is_empty():
		return
	var plan: Dictionary = {}
	if GameState.environmental_hazard_system != null:
		plan = GameState.environmental_hazard_system.get_response_plan_view(
			GameState.entities, GameState.settlement_system
		)
	_selected_hazard_priority = str(plan.get("priority", "balanced"))
	if _selected_hazard_priority.is_empty():
		_selected_hazard_priority = "balanced"
	_hazard_ui_elapsed = 0.0
	_hazard_modal["message"].text = ""
	_rebuild_hazard_content()
	_hazard_modal["backdrop"].visible = true


func _rebuild_hazard_content() -> void:
	if _hazard_modal.is_empty() or GameState.environmental_hazard_system == null:
		return
	var body: VBoxContainer = _hazard_modal["body"]
	_clear_children(body)
	_hazard_modal["title"].text = "环境危机与响应"
	var management: Dictionary = GameState.get_management_snapshot()
	var hazard: Dictionary = management.get("hazard", {})
	var active: Dictionary = hazard.get("active_hazard", {})
	var assessment: Dictionary = hazard.get("latest_assessment", {})
	var exposure: Dictionary = hazard.get("latest_exposure", {})

	body.add_child(_section_label("当前态势"))
	if not active.is_empty():
		body.add_child(_body_label(
			"危机进行中：%s\n开始于第 %.1f 天 · 已持续 %.1f 天 · 累计死亡 %d 人 · 损毁设施 %d 座" % [
				str(active.get("hazard_id", "")),
				float(active.get("started_game_day", 0.0)),
				float(active.get("elapsed_days", 0.0)),
				int(active.get("casualties", 0)),
				int(active.get("destroyed_buildings", 0)),
			],
			Color(1.0, 0.62, 0.52)
		))
	elif float(assessment.get("trigger_score", 0.0)) > 0.0:
		body.add_child(_body_label(
			"区域环境压力正在升高：%s。受影响区域 %s，暴露人口 %d 人。\n危机何时开始、持续多久仍取决于真实恒星与区域环境；文明只能根据当前观测做准备。" % [
				str(assessment.get("dominant_cause", "极端环境")),
				", ".join((assessment.get("affected_zone_ids", []) as Array).map(func(zone_id): return "#%d" % int(zone_id))),
				int(assessment.get("exposed_population", 0)),
			],
			Color(1.0, 0.84, 0.45)
		))
	else:
		body.add_child(_body_label(
			"当前没有被人口覆盖的区域越过危机阈值。\n温度低于 -45℃、高于 75℃，或辐射高于 3.0 时，环境压力会开始累积；真实三体混沌可能同时改变多个区域。",
			Color(0.74, 0.80, 0.94)
		))
	if not exposure.is_empty():
		body.add_child(_body_label(
			"最近一次暴露结算：风险人口 %d，死亡 %d。" % [
				int(exposure.get("population_at_risk", 0)), int(exposure.get("total_loss", 0)),
			],
			Color(0.76, 0.82, 0.94)
		))

	body.add_child(_section_label("文明预警能力"))
	var forecast: Dictionary = GameState.hazard_forecast_service.get_public_snapshot()
	var level_names := ["无文明预警", "定性天象预警", "区域风险预测", "伤亡区间预测", "高精度概率预测"]
	var forecast_level := clampi(int(forecast.get("level", 0)), 0, level_names.size() - 1)
	var forecast_lines: Array[String] = [
		"%s · 置信度 %.0f%%" % [level_names[forecast_level], float(forecast.get("confidence", 0.0)) * 100.0],
	]
	if forecast.is_empty():
		forecast_lines.append("文明尚未积累足够的连续观测；规则层倒计时不会转化为灾害真值。")
	elif bool(forecast.get("stale", false)):
		forecast_lines.append("该预测已过期，需要新的观测与校准。")
	elif forecast.has("risk_trend"):
		forecast_lines.append("风险趋势：%s" % ("上升" if str(forecast.get("risk_trend", "")) == "rising" else "不确定"))
	body.add_child(_body_label("\n".join(forecast_lines), Color(0.76, 0.86, 1.0)))

	body.add_child(_section_label("响应预案"))
	body.add_child(_body_label(
		"庇护容量只统计已完工、未损毁、已配员且获得供能的当地设施。预案会在危机开始时锁定；没有足够设施的承诺不会凭空保护人口。",
		Color(0.72, 0.78, 0.92)
	))
	var profiles: Array = GameState.environmental_hazard_system.get_response_profiles()
	for value in profiles:
		var profile: Dictionary = value
		var profile_id := str(profile.get("id", ""))
		var selected := profile_id == _selected_hazard_priority
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 72.0)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.text = "%s%s\n%s" % [
			"◆ " if selected else "· ",
			str(profile.get("name", profile_id)),
			str(profile.get("description", "")),
		]
		button.modulate = Color(1.0, 0.9, 0.55) if selected else Color.WHITE
		button.pressed.connect(_select_hazard_priority.bind(profile_id))
		body.add_child(button)

	var preview: Dictionary = GameState.environmental_hazard_system.preview_response_priority(
		_selected_hazard_priority, GameState.entities, GameState.settlement_system
	)
	var allocations: Dictionary = preview.get("allocations", {})
	var total_capacity := 0
	var total_protected := 0
	var allocation_lines: Array[String] = []
	for zone_key in allocations:
		var allocation: Dictionary = allocations[zone_key]
		total_capacity += int(allocation.get("operating_shelter_capacity", 0))
		total_protected += int(allocation.get("planned_protected_people", 0))
		allocation_lines.append("区域 #%d：人口 %d · 运行庇护 %d · 计划保护 %d" % [
			int(allocation.get("zone_id", -1)),
			int(allocation.get("population", 0)),
			int(allocation.get("operating_shelter_capacity", 0)),
			int(allocation.get("planned_protected_people", 0)),
		])
	body.add_child(_body_label(
		"可用运行庇护容量 %d · 当前方案计划保护 %d 人%s" % [
			total_capacity,
			total_protected,
			"\n" + "\n".join(allocation_lines) if not allocation_lines.is_empty() else "\n当前没有有人区域。",
		],
		Color(0.8, 0.86, 0.98)
	))

	var commit_button := Button.new()
	commit_button.custom_minimum_size = Vector2(0.0, 54.0)
	commit_button.text = "危机进行中，预案已锁定" if not active.is_empty() else "确认并承诺该响应预案"
	commit_button.disabled = not active.is_empty() or total_capacity <= 0
	commit_button.tooltip_text = (
		"没有已完工、配员且供能的庇护设施" if total_capacity <= 0 else "确认后，危机开始前都可以重新选择"
	)
	commit_button.pressed.connect(_commit_hazard_priority)
	body.add_child(commit_button)

	var report: Dictionary = hazard.get("latest_completed_report", {})
	body.add_child(_section_label("最近一次危机报告"))
	if report.is_empty():
		body.add_child(_body_label("尚未经历环境危机。", Color(0.72, 0.78, 0.92)))
	else:
		var loss_vector: Dictionary = report.get("knowledge_loss_vector", {})
		body.add_child(_body_label(
			"第 %.1f 天结束 · 死亡 %d 人 · 损毁设施 %d 座 · 知识冲击：活态 %.0f%% / 记录 %.0f%% / 实践 %.0f%%\n预案：%s" % [
				float(report.get("resolved_game_day", 0.0)),
				int(report.get("casualties", 0)),
				int(report.get("destroyed_buildings", 0)),
				float(loss_vector.get("living_loss", 0.0)) * 100.0,
				float(loss_vector.get("record_loss", 0.0)) * 100.0,
				float(loss_vector.get("practice_loss", 0.0)) * 100.0,
				str(report.get("response_priority_name", "未确认预案")),
			],
			Color(0.86, 0.8, 0.72)
		))


func _select_hazard_priority(p_priority: String) -> void:
	_selected_hazard_priority = p_priority
	_rebuild_hazard_content()


func _commit_hazard_priority() -> void:
	var result: Dictionary = GameState.commit_hazard_response(_selected_hazard_priority)
	_hazard_modal["message"].text = str(result.get("message", ""))
	_hazard_modal["message"].add_theme_color_override(
		"font_color",
		Color(0.55, 0.95, 0.65) if bool(result.get("success", false)) else Color(1.0, 0.55, 0.45)
	)
	_rebuild_hazard_content()
	_refresh_panels()


func _section_label(p_text: String) -> Label:
	var label := Label.new()
	label.text = "── %s ──" % p_text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.55, 0.76, 1.0))
	return label


func _body_label(p_text: String, p_color: Color = Color(0.8, 0.85, 0.96)) -> Label:
	var label := Label.new()
	label.text = p_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", p_color)
	return label


func _clear_children(p_node: Node) -> void:
	for child in p_node.get_children():
		p_node.remove_child(child)
		child.queue_free()
