extends Node
## 1920×1080 逻辑画布关键控件边界回归测试。

var _failures: int = 0


func _ready() -> void:
	_expect(get_viewport().get_visible_rect().size.x >= 1920.0, "测试视口宽度不足 1920")
	_expect(get_viewport().get_visible_rect().size.y >= 1080.0, "测试视口高度不足 1080")
	await _check_pause_menu()
	await _check_main_screen()
	await _check_start_and_settings()
	await _check_game_subscreens()
	if _failures == 0:
		print("UI_LAYOUT_TEST_OK")
	get_tree().quit(_failures)


func _check_pause_menu() -> void:
	var scene := await _spawn("res://scenes/game/game_menu.tscn")
	var panel: Control = scene.get_node("CenterPanel")
	var status: Control = scene.get_node("CenterPanel/MenuVBox/SaveStatusPanel")
	var load_button: Control = scene.get_node("CenterPanel/MenuVBox/LoadButton")
	var save_panel: Control = scene.get_node("SaveOverlay/SavePanel")
	var save_input: Control = scene.get_node("SaveOverlay/SavePanel/SaveNameInput")
	var save_row: Control = scene.get_node("SaveOverlay/SavePanel/SaveButtonRow")
	var browser_panel: Control = scene.get_node("SaveBrowser/BrowserPanel")
	_expect(_inside_viewport(panel), "暂停菜单卡片超出视口")
	_expect(_ends_before(status, load_button, true), "暂停菜单保存提示与加载按钮重叠")
	_expect(_inside_viewport(save_panel), "保存命名面板超出视口")
	_expect(_ends_before(save_input, save_row, true), "保存名称输入框与按钮行重叠")
	_expect(_inside_viewport(browser_panel), "暂停菜单存档浏览器超出视口")
	await _discard(scene)


func _check_main_screen() -> void:
	var scene := await _spawn("res://scenes/game/main_screen.tscn")
	var toolbar: Control = scene.get_node("Toolbar")
	var content: Control = scene.get_node("PanelContainer")
	var observation: Control = scene.get_node("PanelContainer/ObservationPanel")
	var left_hud: Control = scene.get_node("PanelContainer/LeftHud")
	var right_hud: Control = scene.get_node("PanelContainer/RightHud")
	var bottom_status: Control = scene.get_node("BottomStatus")
	var hint: Control = scene.get_node("HintPanel")
	var developer_panel: Control = scene.get_node("DeveloperOverlay/DeveloperPanel")
	var capital_overlay: Control = scene.get_node("CapitalOverlay")
	_expect(_ends_before(toolbar, content, true), "主界面工具栏与内容面板重叠")
	_expect(_ends_before(content, bottom_status, true), "主界面观测内容与全局状态栏重叠")
	_expect(_ends_before(bottom_status, hint, true), "主界面全局状态栏与底部提示重叠")
	_expect(observation.size.x > left_hud.size.x and observation.size.x > right_hud.size.x, "主界面中央观测画面不是视觉主体")
	_expect(_inside_viewport(developer_panel), "开发者工具面板超出视口")
	_expect(_inside_viewport(capital_overlay), "首都候选层超出视口")
	_expect(capital_overlay.visible and scene.get_node("CapitalOverlay/CapitalVBox/CapitalSplit/CandidateScroll/CapitalCandidateList").get_child_count() > 0, "新局主界面没有显示可操作的首都候选")
	scene.get_node("CapitalOverlay/CapitalVBox/ConfirmCapitalButton").pressed.emit()
	await get_tree().process_frame
	_expect(not capital_overlay.visible and GameState.settlement_system.capital_zone_id >= 0, "主界面确认首都后没有解除第 0 天选择层")
	if not GameState.paused:
		GameState.toggle_pause()
	var guidance_overlay: Control = scene.get_node("GuidanceControlOverlay")
	var world_before_guidance: String = JSON.stringify({"entities": GameState.entities.get_state(), "zones": GameState.planet_zones.get_state()})
	scene.get_node("Toolbar/GuidanceControlButton").pressed.emit()
	await get_tree().process_frame
	_expect(guidance_overlay.visible and _inside_viewport(scene.get_node("GuidanceControlOverlay/Panel")), "局内引导手册无法打开或超出视口")
	var defer_button: Button = scene.get_node("GuidanceControlOverlay/Panel/VBox/DeferGuidanceGroupButton")
	defer_button.pressed.emit()
	await get_tree().process_frame
	_expect(GameState.opening_guidance.group_deferred and not scene.get_node("GuidancePanel").visible, "暂缓整组引导后任务卡仍常驻")
	defer_button.pressed.emit()
	await get_tree().process_frame
	_expect(not GameState.opening_guidance.group_deferred, "局内引导手册无法恢复已暂缓任务")
	var guidance_mode: OptionButton = scene.get_node("GuidanceControlOverlay/Panel/VBox/GuidanceModeOption")
	guidance_mode.select(2)
	guidance_mode.item_selected.emit(2)
	_expect(GameState.opening_guidance.mode == GameState.opening_guidance.GuidanceMode.OFF, "局内引导手册无法关闭教学呈现")
	guidance_mode.select(0)
	guidance_mode.item_selected.emit(0)
	_expect(world_before_guidance == JSON.stringify({"entities": GameState.entities.get_state(), "zones": GameState.planet_zones.get_state()}), "引导暂缓、关闭或恢复改变了世界状态")
	scene.get_node("GuidanceControlOverlay/Panel/VBox/CloseGuidanceControlButton").pressed.emit()
	await _discard(scene)


func _check_start_and_settings() -> void:
	var start_scene := await _spawn("res://scenes/main_menu/start_game_menu.tscn")
	start_scene.get_node("MainVBox").visible = false
	start_scene.get_node("NamingContainer").visible = true
	await get_tree().process_frame
	var input: Control = start_scene.get_node("NamingContainer/NameInput")
	var row: Control = start_scene.get_node("NamingContainer/NamingButtonRow")
	var confirm: Control = start_scene.get_node("NamingContainer/NamingButtonRow/ConfirmNameBtn")
	var cancel: Control = start_scene.get_node("NamingContainer/NamingButtonRow/CancelNameBtn")
	_expect(_ends_before(input, row, true), "宇宙命名输入框与按钮行重叠")
	_expect(_ends_before(confirm, cancel, false), "宇宙命名确认与取消按钮重叠")
	start_scene.get_node("NamingContainer").visible = false
	start_scene.get_node("DifficultyContainer").visible = true
	await get_tree().process_frame
	var difficulty_option: Control = start_scene.get_node("DifficultyContainer/DifficultyOption")
	var difficulty_description: Control = start_scene.get_node("DifficultyContainer/DifficultyDescription")
	var difficulty_buttons: Control = start_scene.get_node("DifficultyContainer/DifficultyButtonRow")
	_expect(_inside_viewport(start_scene.get_node("DifficultyContainer")), "难度选择步骤超出视口")
	_expect(_ends_before(difficulty_option, difficulty_description, true), "难度选项与说明重叠")
	_expect(_ends_before(difficulty_description, difficulty_buttons, true), "难度说明与按钮行重叠")
	start_scene.get_node("DifficultyContainer").visible = false
	start_scene.get_node("GuidanceContainer").visible = true
	await get_tree().process_frame
	var guidance_option: Control = start_scene.get_node("GuidanceContainer/GuidanceOption")
	var guidance_buttons: Control = start_scene.get_node("GuidanceContainer/GuidanceButtonRow")
	_expect(_inside_viewport(start_scene.get_node("GuidanceContainer")), "引导模式步骤超出视口")
	_expect(_ends_before(guidance_option, guidance_buttons, true), "引导模式选项与按钮行重叠")
	await _discard(start_scene)

	var settings_scene := await _spawn("res://scenes/main_menu/settings_screen.tscn")
	var tabs: Control = settings_scene.get_node("TabBar")
	var content: Control = settings_scene.get_node("ContentPanel")
	var buttons: Control = settings_scene.get_node("BottomBar")
	_expect(_ends_before(tabs, content, true), "设置标签栏与内容面板重叠")
	_expect(_ends_before(content, buttons, true), "设置内容面板与底部按钮重叠")
	await _discard(settings_scene)


func _check_game_subscreens() -> void:
	var scene_paths := [
		"res://scenes/tech_tree/tech_tree.tscn",
		"res://scenes/knowledge/knowledge_policy.tscn",
		"res://scenes/zone_view/zone_view.tscn",
		"res://scenes/decision/decision.tscn",
		"res://scenes/starmap/starmap_view.tscn",
	]
	for scene_path in scene_paths:
		var scene := await _spawn(scene_path)
		var toolbar: Control = scene.get_node("Toolbar")
		_expect(_inside_viewport(toolbar), "%s 工具栏超出视口" % scene_path)
		if scene_path.ends_with("starmap_view.tscn"):
			var bodies: Node = scene.get_node("Viewport3D/SubViewport/StarMap3D/CelestialBodies")
			_expect(bodies.get_child_count() == 4, "3D 星图没有创建完整的三颗恒星与一颗行星")
			_expect(bodies.get_node_or_null("Planet/PlanetGrid") != null, "3D 星图行星经纬网缺失")
			for star_index in range(3):
				_expect(bodies.get_node_or_null("Star%d/Corona" % star_index) != null, "3D 星图恒星日冕缺失")
				_expect(bodies.get_node_or_null("Star%d/StellarLight" % star_index) != null, "3D 星图恒星动态光源缺失")
			var game_over_panel: Control = scene.get_node("GameOverOverlay/GameOverPanel")
			_expect(_inside_viewport(game_over_panel), "星图游戏结束面板超出视口")
		await _discard(scene)


func _spawn(p_path: String) -> Node:
	var packed: PackedScene = load(p_path)
	var scene := packed.instantiate()
	add_child(scene)
	await get_tree().process_frame
	return scene


func _discard(p_scene: Node) -> void:
	p_scene.queue_free()
	await get_tree().process_frame


func _inside_viewport(p_control: Control) -> bool:
	var viewport_rect := get_viewport().get_visible_rect()
	var rect := p_control.get_global_rect()
	return viewport_rect.encloses(rect)


func _ends_before(p_first: Control, p_second: Control, p_vertical: bool) -> bool:
	var first_rect := p_first.get_global_rect()
	var second_rect := p_second.get_global_rect()
	if p_vertical:
		return first_rect.end.y <= second_rect.position.y
	return first_rect.end.x <= second_rect.position.x


func _expect(p_condition: bool, p_message: String) -> void:
	if p_condition:
		return
	_failures += 1
	push_error(p_message)
