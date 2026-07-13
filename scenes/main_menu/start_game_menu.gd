extends Control
## 开始游戏菜单 — 新建宇宙 / 继续游戏 / 加载存档 / 删除

enum State { MAIN, NAMING, LOAD_UNIVERSE, LOAD_SAVE }

const ITEM_HEIGHT := 70
const ITEM_GAP := 8

var state: State = State.MAIN
var universe_list: Array = []
var save_list: Array = []
var scroll_offset: float = 0.0
var selected_universe_idx: int = -1
var selected_save_idx: int = -1
var confirm_delete: bool = false
var message_text: String = ""
var message_timer: float = 0.0
var message_color: Color = Color(1.0, 0.78, 0.39)

@onready var main_vbox: VBoxContainer = %MainVBox
@onready var naming_container: Control = %NamingContainer
@onready var name_input: LineEdit = %NameInput
@onready var load_container: Control = %LoadContainer
@onready var list_title: Label = %ListTitle
@onready var list_subtitle: Label = %ListSubtitle
@onready var item_container: Control = %ItemContainer
@onready var toolbar: HBoxContainer = %Toolbar
@onready var back_btn: Button = %BackBtn
@onready var action_btn: Button = %ActionBtn
@onready var delete_btn: Button = %DeleteBtn
@onready var toolbar_hint: Label = %ToolbarHint
@onready var message_label: Label = %MessageLabel
@onready var confirm_overlay: Control = %ConfirmOverlay
@onready var confirm_label: Label = %ConfirmLabel
@onready var delete_confirm_btn: Button = %DeleteConfirmBtn
@onready var delete_cancel_btn: Button = %DeleteCancelBtn


func _ready() -> void:
	_setup_main_buttons()
	_setup_naming_buttons()
	_setup_toolbar_buttons()
	_setup_delete_confirm_buttons()
	item_container.gui_input.connect(_on_item_gui_input)
	_refresh_ui()


func _input(event: InputEvent) -> void:
	if not visible or not is_inside_tree():
		return
	if event is InputEventKey and event.pressed:
		match state:
			State.LOAD_UNIVERSE, State.LOAD_SAVE:
				if event.keycode == KEY_ESCAPE:
					_on_back_from_load()
				elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
					_on_action_pressed()
				elif event.keycode == KEY_DELETE:
					_on_delete_pressed()
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
	queue_redraw()


# ── Main menu buttons ────────────────────────────

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
	state = State.LOAD_UNIVERSE
	universe_list = SaveManager.scan_universes()
	scroll_offset = 0.0
	selected_universe_idx = -1
	confirm_delete = false
	_refresh_ui()


func _on_back_to_initial() -> void:
	if state != State.MAIN:
		state = State.MAIN
		confirm_delete = false
		_refresh_ui()
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu/initial_menu.tscn")


# ── Naming sub-state ─────────────────────────────

func _setup_naming_buttons() -> void:
	%ConfirmNameBtn.pressed.connect(_on_confirm_name)
	%CancelNameBtn.pressed.connect(_on_cancel_name)


func _on_confirm_name() -> void:
	var name := name_input.text.strip_edges()
	if name.is_empty():
		_show_message("请输入宇宙名称", Color(1.0, 0.59, 0.39))
		return
	if SaveManager.universe_exists(name):
		_show_message("宇宙名称已存在，请重新命名", Color(1.0, 0.39, 0.39))
		return
	_do_start_new_game(name)


func _on_cancel_name() -> void:
	state = State.MAIN
	_refresh_ui()


func _do_start_new_game(universe_name: String) -> void:
	GameState.new_game(universe_name)
	get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")


# ── Load toolbar ─────────────────────────────────

func _setup_toolbar_buttons() -> void:
	back_btn.pressed.connect(_on_back_from_load)
	action_btn.pressed.connect(_on_action_pressed)
	delete_btn.pressed.connect(_on_delete_pressed)


func _on_back_from_load() -> void:
	if state == State.LOAD_SAVE:
		state = State.LOAD_UNIVERSE
		universe_list = SaveManager.scan_universes()
		scroll_offset = 0.0
		confirm_delete = false
	else:
		state = State.MAIN
		confirm_delete = false
	_refresh_ui()


func _on_action_pressed() -> void:
	match state:
		State.LOAD_UNIVERSE:
			if selected_universe_idx >= 0 and selected_universe_idx < universe_list.size():
				var uni = universe_list[selected_universe_idx]
				var all_saves := SaveManager.scan_saves()
				var arr: Array = all_saves.get(uni["name"], [])
				save_list.assign(arr)
				state = State.LOAD_SAVE
				scroll_offset = 0.0
				selected_save_idx = -1
				confirm_delete = false
				_refresh_ui()
		State.LOAD_SAVE:
			if selected_save_idx >= 0 and selected_save_idx < save_list.size():
				var save = save_list[selected_save_idx]
				_do_load_game(save.filepath)


func _on_delete_pressed() -> void:
	if state == State.LOAD_UNIVERSE:
		if selected_universe_idx >= 0 and selected_universe_idx < universe_list.size():
			confirm_delete = true
			_refresh_ui()
	elif state == State.LOAD_SAVE:
		if selected_save_idx >= 0 and selected_save_idx < save_list.size():
			confirm_delete = true
			_refresh_ui()


func _do_load_game(filepath: String) -> void:
	if SaveManager.load_game(filepath):
		get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")
	else:
		_show_message("加载存档失败", Color(1.0, 0.39, 0.39))


# ── Delete confirm ───────────────────────────────

func _setup_delete_confirm_buttons() -> void:
	delete_confirm_btn.pressed.connect(_on_confirm_delete)
	delete_cancel_btn.pressed.connect(_on_cancel_delete)


func _on_confirm_delete() -> void:
	if state == State.LOAD_UNIVERSE:
		if selected_universe_idx >= 0 and selected_universe_idx < universe_list.size():
			var uni = universe_list[selected_universe_idx]
			SaveManager.delete_universe(uni["name"])
			universe_list = SaveManager.scan_universes()
			selected_universe_idx = -1
	elif state == State.LOAD_SAVE:
		if selected_save_idx >= 0 and selected_save_idx < save_list.size():
			var save = save_list[selected_save_idx]
			SaveManager.delete_save(save.filepath)
			save_list.remove_at(selected_save_idx)
			selected_save_idx = -1
			if save_list.is_empty():
				state = State.LOAD_UNIVERSE
				universe_list = SaveManager.scan_universes()
	confirm_delete = false
	_refresh_ui()


func _on_cancel_delete() -> void:
	confirm_delete = false
	_refresh_ui()


# ── Message ──────────────────────────────────────

func _show_message(text: String, color: Color) -> void:
	message_text = text
	message_color = color
	message_timer = 2.5
	message_label.text = text
	message_label.add_theme_color_override("font_color", color)
	message_label.visible = true


# ── UI Refresh ───────────────────────────────────

func _refresh_ui() -> void:
	main_vbox.visible = (state == State.MAIN)
	naming_container.visible = (state == State.NAMING)
	load_container.visible = (state == State.LOAD_UNIVERSE or state == State.LOAD_SAVE)
	confirm_overlay.visible = confirm_delete

	if state == State.LOAD_UNIVERSE:
		action_btn.text = "进入"
		delete_btn.visible = true
		toolbar_hint.text = "滚轮滚动 | Enter确认 | Delete删除"
	elif state == State.LOAD_SAVE:
		action_btn.text = "加载"
		delete_btn.visible = true
		toolbar_hint.text = "滚轮滚动 | Enter确认 | Delete删除"
	else:
		toolbar_hint.text = ""

	if state == State.LOAD_UNIVERSE:
		list_title.text = "选择宇宙"
		list_subtitle.text = "共 %d 个宇宙档案" % universe_list.size()
	elif state == State.LOAD_SAVE:
		var uni_name := ""
		if selected_universe_idx >= 0 and selected_universe_idx < universe_list.size():
			uni_name = universe_list[selected_universe_idx]["name"]
		list_title.text = "宇宙: " + uni_name
		list_subtitle.text = "共 %d 个存档" % save_list.size()

	_update_confirm_text()
	queue_redraw()


func _update_confirm_text() -> void:
	if not confirm_delete:
		return
	if state == State.LOAD_UNIVERSE and selected_universe_idx >= 0 and selected_universe_idx < universe_list.size():
		var uni = universe_list[selected_universe_idx]
		confirm_label.text = "确认删除宇宙 \"%s\" ？\n(含 %d 个存档)" % [uni["name"], uni["count"]]
	elif state == State.LOAD_SAVE and selected_save_idx >= 0 and selected_save_idx < save_list.size():
		var save = save_list[selected_save_idx]
		confirm_label.text = "确认删除存档 \"%s\" ？" % save.save_name


# ── Item list drawing ────────────────────────────

func _draw() -> void:
	if not load_container.visible:
		return
	var items: Array
	var selected_idx: int
	if state == State.LOAD_UNIVERSE:
		items = universe_list
		selected_idx = selected_universe_idx
	elif state == State.LOAD_SAVE:
		items = save_list
		selected_idx = selected_save_idx
	else:
		return

	var list_rect := item_container.get_global_rect()
	var list_y := list_rect.position.y
	var list_x := list_rect.position.x
	var list_w := list_rect.size.x
	# Clip
	var bottom_limit := toolbar.get_global_rect().position.y - 10.0

	for i in items.size():
		var iy := list_y + i * (ITEM_HEIGHT + ITEM_GAP) - scroll_offset
		if iy + ITEM_HEIGHT < list_y or iy > bottom_limit:
			continue

		var selected := (i == selected_idx)
		var bg_color: Color
		var border_color: Color
		if selected:
			bg_color = Color(0.196, 0.255, 0.471)
			border_color = Color(0.471, 0.627, 1.0)
		else:
			bg_color = Color(0.098, 0.118, 0.216)
			border_color = Color(0.196, 0.235, 0.353)

		draw_rect(Rect2(list_x, iy, list_w, ITEM_HEIGHT), bg_color, true)
		draw_rect(Rect2(list_x, iy, list_w, ITEM_HEIGHT), border_color, false)

		var name_color := Color(0.863, 0.902, 1.0) if selected else Color(0.706, 0.745, 0.863)
		var detail_color := Color(0.471, 0.549, 0.667)

		if state == State.LOAD_UNIVERSE:
			var uni = items[i]
			draw_string(ThemeDB.fallback_font, Vector2(list_x + 15, iy + 28), uni["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, name_color)
			var detail := "包含 %d 个存档  ·  最新: %s" % [uni["count"], uni["latest_time"]]
			draw_string(ThemeDB.fallback_font, Vector2(list_x + 15, iy + 52), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, detail_color)
		else:
			var save = items[i]
			draw_string(ThemeDB.fallback_font, Vector2(list_x + 15, iy + 28), save.save_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, name_color)
			var detail := "第%d天  ·  %s" % [save.game_day, save.save_time]
			if save.is_legacy:
				detail += "  ·  旧格式"
			draw_string(ThemeDB.fallback_font, Vector2(list_x + 15, iy + 52), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, detail_color)


func _on_item_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll_offset = max(0.0, scroll_offset - 40.0)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll_offset += 40.0
			return
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var items: Array
			if state == State.LOAD_UNIVERSE:
				items = universe_list
			elif state == State.LOAD_SAVE:
				items = save_list
			else:
				return
			var list_rect := item_container.get_global_rect()
			var list_y := list_rect.position.y
			var list_x := list_rect.position.x
			var list_w := list_rect.size.x
			var mx: float = event.global_position.x
			var my: float = event.global_position.y
			if mx < list_x or mx > list_x + list_w or my < list_y:
				return
			for i in items.size():
				var iy := list_y + i * (ITEM_HEIGHT + ITEM_GAP) - scroll_offset
				if my >= iy and my <= iy + ITEM_HEIGHT:
					if state == State.LOAD_UNIVERSE:
						selected_universe_idx = i
					else:
						selected_save_idx = i
					_refresh_ui()
					return
