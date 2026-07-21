extends Node
## 共享存档浏览器：扫描、可见选择、两处入口复用与加载信号回归测试。

var _failures: int = 0


func _ready() -> void:
	var universe_name := "__存档浏览器回归_%d" % Time.get_ticks_usec()
	GameState.new_game(universe_name)
	_expect(SaveManager.save_game(GameState, "可见存档", universe_name), "无法创建浏览器测试存档")
	var save_path := SaveManager.get_current_save_path()

	var packed: PackedScene = load("res://scenes/shared/save_browser.tscn")
	var browser := packed.instantiate()
	add_child(browser)
	await get_tree().process_frame
	browser.open_browser()
	await get_tree().process_frame
	_expect(browser.get_visible_save_count() > 0, "存档浏览器没有显示扫描到的存档")

	var target_button: Button = null
	for child in browser.get_node("BrowserPanel/SaveScroll/ItemList").get_children():
		if child is Button and child.tooltip_text.begins_with(universe_name + " /"):
			target_button = child
			break
	_expect(target_button != null, "新建测试存档没有对应的可点击卡片")
	var selected_paths: Array[String] = []
	browser.save_selected.connect(func(filepath: String): selected_paths.append(filepath))
	if target_button != null:
		target_button.pressed.emit()
		browser.get_node("BrowserPanel/Toolbar/LoadButton").pressed.emit()
	_expect(selected_paths.size() == 1 and selected_paths[0] == save_path, "选择卡片后没有发出正确的加载路径")
	if target_button != null:
		browser._on_delete_pressed()
		var enter_event := InputEventKey.new()
		enter_event.keycode = KEY_ENTER
		enter_event.pressed = true
		browser._input(enter_event)
		_expect(selected_paths.size() == 1, "删除确认层打开时 Enter 穿透并加载了底层存档")
		browser._close_delete_confirmation()

	var start_menu := (load("res://scenes/main_menu/start_game_menu.tscn") as PackedScene).instantiate()
	add_child(start_menu)
	await get_tree().process_frame
	var start_browser: Node = start_menu.get_node("SaveBrowser")
	_expect(start_browser.get_script() == browser.get_script(), "主菜单没有复用共享存档浏览器")
	start_menu.queue_free()
	await get_tree().process_frame

	var pause_menu := (load("res://scenes/game/game_menu.tscn") as PackedScene).instantiate()
	add_child(pause_menu)
	await get_tree().process_frame
	var pause_browser: Node = pause_menu.get_node("SaveBrowser")
	_expect(pause_browser.get_script() == browser.get_script(), "暂停菜单没有复用共享存档浏览器")
	pause_browser.open_browser()
	await get_tree().process_frame
	_expect(pause_browser.visible and pause_browser.get_visible_save_count() > 0, "暂停菜单加载入口没有打开可见存档列表")

	_expect(SaveManager.delete_save(save_path), "测试存档清理失败")
	if _failures == 0:
		print("SAVE_BROWSER_TEST_OK")
	get_tree().quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
