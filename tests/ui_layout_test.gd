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
	_expect(_inside_viewport(panel), "暂停菜单卡片超出视口")
	_expect(_ends_before(status, load_button, true), "暂停菜单保存提示与加载按钮重叠")
	_expect(_inside_viewport(save_panel), "保存命名面板超出视口")
	_expect(_ends_before(save_input, save_row, true), "保存名称输入框与按钮行重叠")
	await _discard(scene)


func _check_main_screen() -> void:
	var scene := await _spawn("res://scenes/game/main_screen.tscn")
	var toolbar: Control = scene.get_node("Toolbar")
	var content: Control = scene.get_node("PanelContainer")
	var hint: Control = scene.get_node("HintPanel")
	var developer_panel: Control = scene.get_node("DeveloperOverlay/DeveloperPanel")
	_expect(_ends_before(toolbar, content, true), "主界面工具栏与内容面板重叠")
	_expect(_ends_before(content, hint, true), "主界面内容与底部提示重叠")
	_expect(_inside_viewport(developer_panel), "开发者工具面板超出视口")
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
