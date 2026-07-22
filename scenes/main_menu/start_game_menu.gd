extends Control
## 开始游戏菜单 — 新建宇宙 / 继续游戏 / 加载存档

enum State { MAIN, NAMING, DIFFICULTY, GUIDANCE }

const DIFFICULTY_CONFIG_PATH := "res://resources/configs/scenario_difficulties.tres"

var state: State = State.MAIN
var message_timer: float = 0.0
var _pending_universe_name: String = ""
var _difficulty_config
var _difficulty_ids: Array[StringName] = []
var _pending_scenario_snapshot: Dictionary = {}

@onready var main_vbox: VBoxContainer = %MainVBox
@onready var naming_container: Control = %NamingContainer
@onready var difficulty_container: Control = %DifficultyContainer
@onready var guidance_container: Control = %GuidanceContainer
@onready var name_input: LineEdit = %NameInput
@onready var message_label: Label = %MessageLabel
@onready var save_browser: Control = %SaveBrowser


func _ready() -> void:
	EventBus.screen_changed.emit("start_game_menu")
	_setup_main_buttons()
	%ConfirmNameBtn.pressed.connect(_on_confirm_name)
	%CancelNameBtn.pressed.connect(_on_cancel_name)
	%DifficultyOption.item_selected.connect(_on_difficulty_selected)
	%ConfirmDifficultyBtn.pressed.connect(_on_confirm_difficulty)
	%BackToNameBtn.pressed.connect(_on_back_to_naming)
	%ConfirmGuidanceBtn.pressed.connect(_on_confirm_guidance)
	%BackToDifficultyBtn.pressed.connect(_on_back_to_difficulty)
	%GuidanceOption.add_item("完整引导", 0)
	%GuidanceOption.add_item("精简提示", 1)
	%GuidanceOption.add_item("关闭引导", 2)
	%GuidanceOption.select(_default_guidance_index())
	save_browser.close_requested.connect(_on_browser_closed)
	save_browser.save_selected.connect(_do_load_game)
	_load_difficulty_config()
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
			State.DIFFICULTY:
				if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
					_on_confirm_difficulty()
				elif event.keycode == KEY_ESCAPE:
					_on_back_to_naming()
			State.GUIDANCE:
				if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
					_on_confirm_guidance()
				elif event.keycode == KEY_ESCAPE:
					_on_back_to_difficulty()
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
	if _difficulty_config == null:
		_show_message("场景难度配置不可用，无法创建宇宙", Color(1.0, 0.39, 0.39))
		return
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
	difficulty_container.visible = false
	guidance_container.visible = false
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
	_pending_universe_name = universe_name
	state = State.DIFFICULTY
	_refresh_ui()


func _on_cancel_name() -> void:
	state = State.MAIN
	_refresh_ui()


func _on_back_to_naming() -> void:
	state = State.NAMING
	_refresh_ui()
	name_input.grab_focus()


func _on_confirm_difficulty() -> void:
	if _difficulty_config == null or _difficulty_ids.is_empty():
		_show_message("场景难度配置不可用", Color(1.0, 0.39, 0.39))
		return
	if SaveManager.universe_exists(_pending_universe_name):
		_show_message("宇宙名称已存在，请返回重新命名", Color(1.0, 0.39, 0.39))
		return
	var selected_index: int = %DifficultyOption.selected
	if selected_index < 0 or selected_index >= _difficulty_ids.size():
		_show_message("请选择难度", Color(1.0, 0.59, 0.39))
		return
	var difficulty_id := _difficulty_ids[selected_index]
	var custom_years := NAN
	if difficulty_id == &"custom":
		var text: String = %CustomYearsInput.text.strip_edges()
		if not text.is_valid_float():
			_show_message("请输入有效的自定义稳定年数", Color(1.0, 0.59, 0.39))
			return
		custom_years = text.to_float()
	var result: Dictionary = _difficulty_config.create_snapshot(difficulty_id, custom_years)
	if not result.get("success", false):
		_show_message("；".join(result.get("errors", PackedStringArray(["难度配置无效"]))), Color(1.0, 0.39, 0.39))
		return
	_pending_scenario_snapshot = result["snapshot"].duplicate(true)
	state = State.GUIDANCE
	_refresh_ui()


func _on_back_to_difficulty() -> void:
	state = State.DIFFICULTY
	_refresh_ui()


func _on_confirm_guidance() -> void:
	if _pending_scenario_snapshot.is_empty():
		_show_message("场景快照不可用，请返回重新选择难度", Color(1.0, 0.39, 0.39))
		return
	var guidance_mode: int = %GuidanceOption.get_item_id(%GuidanceOption.selected)
	_do_start_new_game(_pending_universe_name, _pending_scenario_snapshot, guidance_mode)


func _do_start_new_game(universe_name: String, p_scenario_snapshot: Dictionary, p_guidance_mode: int) -> void:
	if not GameState.new_game(universe_name, {}, p_scenario_snapshot, {"guidance_mode": p_guidance_mode}):
		_show_message("场景初始化失败，请检查难度配置", Color(1.0, 0.39, 0.39))
		return
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
	difficulty_container.visible = state == State.DIFFICULTY
	guidance_container.visible = state == State.GUIDANCE
	save_browser.visible = false


func _default_guidance_index() -> int:
	if not FileAccess.file_exists(GameState.SETTINGS_PATH):
		return 0
	var file := FileAccess.open(GameState.SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return 0
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return 0
	return {"full": 0, "compact": 1, "off": 2}.get(str(parsed.get("guidance_mode", "full")), 0)


func _load_difficulty_config() -> void:
	_difficulty_config = load(DIFFICULTY_CONFIG_PATH)
	if _difficulty_config == null or not _difficulty_config.has_method("validate"):
		_difficulty_config = null
		return
	var errors: PackedStringArray = _difficulty_config.validate()
	if not errors.is_empty():
		push_error("场景难度配置无效：%s" % "; ".join(errors))
		_difficulty_config = null
		return
	%DifficultyOption.clear()
	_difficulty_ids.clear()
	var selected_index := 0
	for preset in _difficulty_config.get_selectable_presets():
		_difficulty_ids.append(preset.id)
		%DifficultyOption.add_item("%s（%.0f 年）" % [preset.display_name, preset.stable_years])
		if preset.id == _difficulty_config.default_preset_id:
			selected_index = _difficulty_ids.size() - 1
	if _difficulty_config.custom_enabled:
		_difficulty_ids.append(&"custom")
		%DifficultyOption.add_item(_difficulty_config.custom_display_name)
	%DifficultyOption.select(selected_index)
	_on_difficulty_selected(selected_index)


func _on_difficulty_selected(p_index: int) -> void:
	if _difficulty_config == null or p_index < 0 or p_index >= _difficulty_ids.size():
		return
	var difficulty_id := _difficulty_ids[p_index]
	var is_custom := difficulty_id == &"custom"
	%CustomYearsRow.visible = is_custom
	if is_custom:
		%DifficultyDescription.text = "%s\n允许范围：%.0f 至 %.0f 年。" % [
			_difficulty_config.custom_description,
			_difficulty_config.custom_min_years,
			_difficulty_config.custom_max_years,
		]
		%CustomYearsInput.placeholder_text = "%.0f - %.0f" % [_difficulty_config.custom_min_years, _difficulty_config.custom_max_years]
	else:
		var preset = _difficulty_config.get_preset(difficulty_id)
		%DifficultyDescription.text = preset.description
