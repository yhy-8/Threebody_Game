extends Control
## 设置界面 — 游戏/显示/音频/控制 四个标签页

enum Tab { GAME, DISPLAY, AUDIO, CONTROLS }

var current_tab: Tab = Tab.GAME

# Settings data
var time_scale_val: float = 1.0
var auto_save_interval: int = 5
var enable_tutorial: bool = true
var show_notifications: bool = true
var developer_mode: bool = false
var fullscreen: bool = false
var vsync: bool = true
var quality_level: int = 2
var particle_effects: bool = true
var show_fps: bool = false
var master_volume: float = 0.8
var music_volume: float = 0.7
var sfx_volume: float = 0.9
var ambient_volume: float = 0.6
var mute_when_unfocused: bool = true
var mouse_sensitivity: float = 1.0
var invert_mouse_y: bool = false
var enable_edge_scrolling: bool = true
var edge_scroll_speed: float = 1.0

@onready var tab_game_btn: Button = %TabGameBtn
@onready var tab_display_btn: Button = %TabDisplayBtn
@onready var tab_audio_btn: Button = %TabAudioBtn
@onready var tab_controls_btn: Button = %TabControlsBtn
@onready var tab_content: Control = %TabContent
@onready var apply_btn: Button = %ApplyBtn


func _ready() -> void:
	EventBus.screen_changed.emit("settings")
	tab_game_btn.pressed.connect(func(): _switch_tab(Tab.GAME))
	tab_display_btn.pressed.connect(func(): _switch_tab(Tab.DISPLAY))
	tab_audio_btn.pressed.connect(func(): _switch_tab(Tab.AUDIO))
	tab_controls_btn.pressed.connect(func(): _switch_tab(Tab.CONTROLS))
	apply_btn.pressed.connect(_on_apply)
	%BackBtn.pressed.connect(_on_back)
	_load_settings()
	_switch_tab(Tab.GAME)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()


func _switch_tab(tab: Tab) -> void:
	current_tab = tab
	for child in tab_content.get_children():
		child.queue_free()
	match tab:
		Tab.GAME: _build_game_tab()
		Tab.DISPLAY: _build_display_tab()
		Tab.AUDIO: _build_audio_tab()
		Tab.CONTROLS: _build_controls_tab()
	_refresh_tab_highlight()


func _refresh_tab_highlight() -> void:
	for btn in [tab_game_btn, tab_display_btn, tab_audio_btn, tab_controls_btn]:
		btn.flat = true
	match current_tab:
		Tab.GAME: tab_game_btn.flat = false
		Tab.DISPLAY: tab_display_btn.flat = false
		Tab.AUDIO: tab_audio_btn.flat = false
		Tab.CONTROLS: tab_controls_btn.flat = false


func _make_slider(label: String, min_v: float, max_v: float, value: float, decimals: int, suffix: String, callback: Callable) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 56)

	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.value = value
	slider.step = pow(0.1, decimals)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float): callback.call(v))
	hbox.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.name = "ValueLabel"
	val_lbl.custom_minimum_size = Vector2(110, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var fmt := "%." + str(decimals) + "f%s"
	val_lbl.text = fmt % [value, suffix]
	slider.value_changed.connect(func(v: float): val_lbl.text = fmt % [v, suffix])
	hbox.add_child(val_lbl)

	return hbox


func _make_checkbox(label: String, checked: bool, callback: Callable) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = label
	cb.button_pressed = checked
	cb.custom_minimum_size = Vector2(0, 48)
	cb.toggled.connect(func(v: bool): callback.call(v))
	return cb


func _build_game_tab() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.add_child(_make_slider("时间流逝速度", 0.1, 10.0, time_scale_val, 1, "x", func(v): time_scale_val = v))
	vbox.add_child(_make_slider("自动保存间隔", 1.0, 30.0, float(auto_save_interval), 0, "分钟", func(v): auto_save_interval = int(v)))
	var developer_toggle := _make_checkbox("开发者模式（显示调试工具并绕过界面门槛）", developer_mode, func(v): developer_mode = v)
	developer_toggle.tooltip_text = "开关本身不修改当前局；开发者工具执行的数值或科技修改会随存档保存"
	vbox.add_child(developer_toggle)
	tab_content.add_child(vbox)


func _build_display_tab() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_child(_make_checkbox("全屏模式", fullscreen, func(v): fullscreen = v))
	vbox.add_child(_make_checkbox("垂直同步", vsync, func(v): vsync = v))
	tab_content.add_child(vbox)


func _build_audio_tab() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_child(_make_slider("主音量", 0.0, 1.0, master_volume, 2, "", func(v): master_volume = v))
	tab_content.add_child(vbox)


func _build_controls_tab() -> void:
	var vbox := VBoxContainer.new()
	var unavailable := Label.new()
	unavailable.text = "当前版本没有可配置的控制项；未接线的选项已隐藏。"
	vbox.add_child(unavailable)
	tab_content.add_child(vbox)


func _load_settings() -> void:
	var path := "res://settings.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	var data = json.get_data()
	if not data is Dictionary:
		return
	time_scale_val = data.get("time_scale", 1.0)
	auto_save_interval = data.get("auto_save_interval", 5)
	enable_tutorial = data.get("enable_tutorial", true)
	show_notifications = data.get("show_notifications", true)
	developer_mode = data.get("developer_mode", false)
	fullscreen = data.get("fullscreen", false)
	vsync = data.get("vsync", true)
	quality_level = data.get("quality_level", 2)
	particle_effects = data.get("particle_effects", true)
	show_fps = data.get("show_fps", false)
	master_volume = data.get("master_volume", 0.8)
	music_volume = data.get("music_volume", 0.7)
	sfx_volume = data.get("sfx_volume", 0.9)
	ambient_volume = data.get("ambient_volume", 0.6)
	mute_when_unfocused = data.get("mute_when_unfocused", true)
	mouse_sensitivity = data.get("mouse_sensitivity", 1.0)
	invert_mouse_y = data.get("invert_mouse_y", false)
	enable_edge_scrolling = data.get("enable_edge_scrolling", true)
	edge_scroll_speed = data.get("edge_scroll_speed", 1.0)


func _save_settings() -> bool:
	var data := {
		"time_scale": time_scale_val,
		"auto_save_interval": auto_save_interval,
		"enable_tutorial": enable_tutorial,
		"show_notifications": show_notifications,
		"developer_mode": developer_mode,
		"fullscreen": fullscreen,
		"vsync": vsync,
		"quality_level": quality_level,
		"particle_effects": particle_effects,
		"show_fps": show_fps,
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"ambient_volume": ambient_volume,
		"mute_when_unfocused": mute_when_unfocused,
		"mouse_sensitivity": mouse_sensitivity,
		"invert_mouse_y": invert_mouse_y,
		"enable_edge_scrolling": enable_edge_scrolling,
		"edge_scroll_speed": edge_scroll_speed,
	}
	var file := FileAccess.open("res://settings.json", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var succeeded: bool = file.get_error() == OK
	file.close()
	return succeeded


func _on_apply() -> void:
	var saved: bool = _save_settings()
	GameState.set_developer_mode(developer_mode)
	get_window().mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	if saved:
		GameState.reload_runtime_settings()
		apply_btn.text = "已应用并保存"
	else:
		apply_btn.text = "保存失败"


func _on_back() -> void:
	get_tree().change_scene_to_file(GameState.settings_return_scene)
