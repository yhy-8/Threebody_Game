extends Control
## 开始游戏菜单 — 新建宇宙 / 继续游戏 / 加载存档

enum State { MAIN, NAMING }

var state: State = State.MAIN
var message_timer: float = 0.0

@onready var main_vbox: VBoxContainer = %MainVBox
@onready var naming_container: Control = %NamingContainer
@onready var name_input: LineEdit = %NameInput
@onready var message_label: Label = %MessageLabel
@onready var save_browser: Control = %SaveBrowser


func _ready() -> void:
	EventBus.screen_changed.emit("start_game_menu")
	_setup_main_buttons()
	%ConfirmNameBtn.pressed.connect(_on_confirm_name)
	%CancelNameBtn.pressed.connect(_on_cancel_name)
	save_browser.close_requested.connect(_on_browser_closed)
	save_browser.save_selected.connect(_do_load_game)
	_refresh_ui()


func _input(event: InputEvent) -> void:
	if not visible or not is_inside_tree() or save_browser.visible:
		return
	if event is InputEventKey and event.pressed:
		match state:
			State.NAMING:
				if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
					_on_confirm_name()
				elif event.keycode == KEY_ESCAPE:
					_on_cancel_name()
			State.MAIN:
				if event.keycode == KEY_ESCAPE:
					_on_back_to_initial()


func _process(dt: float) -> void:
	if message_timer > 0.0:
		message_timer -= dt
		if message_timer <= 0.0:
			message_label.visible = false


func _setup_main_buttons() -> void:
	for child in main_vbox.get_children():
		if child is Button:
			match child.name:
				"NewGameBtn": child.pressed.connect(_on_new_game)
				"ContinueBtn": child.pressed.connect(_on_continue_game)
				"LoadBtn": child.pressed.connect(_on_load_game)
				"BackBtn": child.pressed.connect(_on_back_to_initial)


func _on_new_game() -> void:
	state = State.NAMING
	name_input.text = ""
	name_input.grab_focus()
	_refresh_ui()


func _on_continue_game() -> void:
	var latest := SaveManager.find_latest_save()
	if latest != null:
		_do_load_game(latest.filepath)
	else:
		_show_message("没有可用的存档", Color(1.0, 0.59, 0.39))


func _on_load_game() -> void:
	main_vbox.visible = false
	naming_container.visible = false
	save_browser.open_browser()


func _on_browser_closed() -> void:
	state = State.MAIN
	_refresh_ui()


func _on_back_to_initial() -> void:
	if state != State.MAIN:
		state = State.MAIN
		_refresh_ui()
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu/initial_menu.tscn")


func _on_confirm_name() -> void:
	var universe_name := name_input.text.strip_edges()
	if universe_name.is_empty():
		_show_message("请输入宇宙名称", Color(1.0, 0.59, 0.39))
		return
	if SaveManager.universe_exists(universe_name):
		_show_message("宇宙名称已存在，请重新命名", Color(1.0, 0.39, 0.39))
		return
	_do_start_new_game(universe_name)


func _on_cancel_name() -> void:
	state = State.MAIN
	_refresh_ui()


func _do_start_new_game(universe_name: String) -> void:
	GameState.new_game(universe_name)
	if not SaveManager.save_game(GameState, "初始存档", universe_name):
		_show_message("创建存档失败：%s" % SaveManager.get_save_directory(), Color(1.0, 0.39, 0.39))
		return
	get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")


func _do_load_game(filepath: String) -> void:
	if SaveManager.load_game(filepath):
		get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")
	else:
		_show_message("加载存档失败", Color(1.0, 0.39, 0.39))


func _show_message(text: String, color: Color) -> void:
	message_timer = 2.5
	message_label.text = text
	message_label.add_theme_color_override("font_color", color)
	message_label.visible = true


func _refresh_ui() -> void:
	main_vbox.visible = state == State.MAIN
	naming_container.visible = state == State.NAMING
	save_browser.visible = false
