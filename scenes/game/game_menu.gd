extends Control
## 游戏内暂停菜单


func _ready() -> void:
	EventBus.screen_changed.emit("game_menu")
	%ResumeButton.pressed.connect(_on_resume_pressed)
	%SaveButton.pressed.connect(_on_save_pressed)
	%LoadButton.pressed.connect(_on_load_pressed)
	%SettingsButton.pressed.connect(_on_settings_pressed)
	%MainMenuButton.pressed.connect(_on_main_menu_pressed)
	%SaveConfirmButton.pressed.connect(_on_save_confirmed)
	%SaveCancelButton.pressed.connect(_close_save_panel)
	%SaveNameInput.text_submitted.connect(func(_text: String): _on_save_confirmed())
	%SaveBrowser.close_requested.connect(_on_browser_closed)
	%SaveBrowser.save_selected.connect(_on_save_selected)


func _input(event: InputEvent) -> void:
	if %SaveBrowser.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if %SaveOverlay.visible:
			_close_save_panel()
		else:
			_on_resume_pressed()


func _on_resume_pressed() -> void:
	if GameState.paused:
		GameState.toggle_pause()
	get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")


func _on_save_pressed() -> void:
	var day := maxi(1, int(GameState.game_time))
	%UniverseInfoLabel.text = "宇宙：%s  |  第 %d 天" % [GameState.universe_name, day]
	%SaveNameInput.text = "%s_Day%d" % [GameState.universe_name, day]
	%SaveDialogStatus.text = "Enter 保存  |  Esc 关闭"
	%SaveDialogStatus.modulate = Color.WHITE
	_refresh_recent_saves()
	%SaveOverlay.visible = true
	%SaveNameInput.grab_focus()
	%SaveNameInput.select_all()


func _on_save_confirmed() -> void:
	var save_name: String = %SaveNameInput.text.strip_edges()
	if save_name.is_empty():
		%SaveDialogStatus.text = "请输入存档名称"
		%SaveDialogStatus.modulate = Color(1.0, 0.55, 0.42)
		return
	var success := SaveManager.save_game(GameState, save_name, GameState.universe_name)
	%SaveStatusLabel.text = "已保存：%s" % save_name if success else "保存失败，请检查目录权限"
	%SaveStatusLabel.modulate = Color(0.55, 1.0, 0.65) if success else Color(1.0, 0.5, 0.4)
	%SaveDialogStatus.text = "保存成功：%s" % save_name if success else "保存失败：无法写入 res://saves/"
	%SaveDialogStatus.modulate = Color(0.55, 1.0, 0.65) if success else Color(1.0, 0.5, 0.4)
	if success:
		_refresh_recent_saves()


func _refresh_recent_saves() -> void:
	var saves: Array = SaveManager.scan_saves().get(GameState.universe_name, [])
	saves.sort_custom(func(a, b): return a.save_time > b.save_time)
	var lines: Array[String] = ["最近存档："]
	if saves.is_empty():
		lines.append("暂无")
	else:
		for index in range(mini(3, saves.size())):
			var save = saves[index]
			lines.append("• %s  (%s)" % [save.save_name, save.save_time])
	%RecentSavesLabel.text = "\n".join(lines)


func _close_save_panel() -> void:
	%SaveOverlay.visible = false


func _on_load_pressed() -> void:
	%SaveBrowser.open_browser()


func _on_browser_closed() -> void:
	%LoadButton.grab_focus()


func _on_save_selected(filepath: String) -> void:
	if SaveManager.load_game(filepath):
		get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")
	else:
		%SaveStatusLabel.text = "加载失败：存档文件不可用"
		%SaveStatusLabel.modulate = Color(1.0, 0.5, 0.4)


func _on_settings_pressed() -> void:
	GameState.settings_return_scene = "res://scenes/game/game_menu.tscn"
	get_tree().change_scene_to_file("res://scenes/main_menu/settings_screen.tscn")


func _on_main_menu_pressed() -> void:
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/main_menu/initial_menu.tscn")
