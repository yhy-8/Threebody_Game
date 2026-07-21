class_name SaveBrowser
extends Control
## 可复用的存档浏览器：按宇宙分组显示全部存档，并提供加载与删除。

signal close_requested
signal save_selected(filepath: String)

var _save_list: Array = []
var _selected_index: int = -1
var _item_group: ButtonGroup
var _pending_delete_universe: String = ""

@onready var _summary_label: Label = %SummaryLabel
@onready var _empty_label: Label = %EmptyLabel
@onready var _item_list: VBoxContainer = %ItemList
@onready var _load_button: Button = %LoadButton
@onready var _delete_button: Button = %DeleteButton
@onready var _confirm_overlay: Control = %ConfirmOverlay
@onready var _confirm_label: Label = %ConfirmLabel
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	%BackButton.pressed.connect(_on_back_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_delete_button.pressed.connect(_on_delete_pressed)
	%DeleteConfirmButton.pressed.connect(_on_delete_confirmed)
	%DeleteCancelButton.pressed.connect(_close_delete_confirmation)
	visible = false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _confirm_overlay.visible:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_close_delete_confirmation()
		elif event is InputEventKey and event.pressed:
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_on_load_pressed()
		elif event.keycode == KEY_DELETE:
			get_viewport().set_input_as_handled()
			_on_delete_pressed()


func open_browser() -> void:
	visible = true
	_confirm_overlay.visible = false
	_pending_delete_universe = ""
	_status_label.text = "选择一个存档，然后点击“加载”"
	_status_label.modulate = Color.WHITE
	_refresh_saves()


func close_browser() -> void:
	visible = false
	close_requested.emit()


func get_visible_save_count() -> int:
	return _save_list.size()


func _refresh_saves() -> void:
	_clear_children(_item_list)
	_save_list.clear()
	_selected_index = -1
	_item_group = ButtonGroup.new()
	_load_button.disabled = true
	_delete_button.disabled = true

	var grouped_saves: Dictionary = SaveManager.scan_saves()
	var universe_names: Array = grouped_saves.keys()
	universe_names.sort_custom(func(a, b): return str(a).naturalnocasecmp_to(str(b)) < 0)
	var total_saves := 0
	for universe_name in universe_names:
		var universe_saves: Array = grouped_saves[universe_name]
		universe_saves.sort_custom(func(a, b): return a.save_time > b.save_time)
		total_saves += universe_saves.size()
		_add_universe_header(str(universe_name), universe_saves.size())
		for save in universe_saves:
			_add_save_item(save)

	_summary_label.text = "共 %d 个宇宙 · %d 个可用存档" % [universe_names.size(), total_saves]
	_empty_label.visible = total_saves == 0
	%SaveScroll.visible = total_saves > 0


func _add_universe_header(universe_name: String, save_count: int) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 42.0
	var header := Label.new()
	header.text = "宇宙：%s  ·  %d 个存档" % [universe_name, save_count]
	header.add_theme_color_override("font_color", Color(0.64, 0.76, 1.0))
	header.add_theme_font_size_override("font_size", 19)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(header)
	var delete_universe_button := Button.new()
	delete_universe_button.text = "删除此宇宙"
	delete_universe_button.tooltip_text = "删除“%s”的全部 %d 个存档" % [universe_name, save_count]
	delete_universe_button.custom_minimum_size = Vector2(150.0, 38.0)
	delete_universe_button.pressed.connect(_on_delete_universe_pressed.bind(universe_name, save_count))
	row.add_child(delete_universe_button)
	_item_list.add_child(row)


func _add_save_item(save) -> void:
	var index := _save_list.size()
	_save_list.append(save)
	var button := Button.new()
	button.name = "SaveItem%d" % index
	button.toggle_mode = true
	button.button_group = _item_group
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0.0, 82.0)
	button.text = "  %s\n  第 %d 天  ·  %s%s" % [
		save.save_name,
		int(save.game_day),
		save.save_time,
		"  ·  旧格式" if save.is_legacy else "",
	]
	button.tooltip_text = "%s / %s\n%s" % [save.universe_name, save.save_name, save.filepath]
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(_on_save_item_pressed.bind(index))
	button.gui_input.connect(_on_save_item_gui_input.bind(index))
	_item_list.add_child(button)


func _on_save_item_pressed(index: int) -> void:
	_selected_index = index
	_load_button.disabled = false
	_delete_button.disabled = false
	var save = _save_list[index]
	_status_label.text = "已选择：%s / %s" % [save.universe_name, save.save_name]
	_status_label.modulate = Color.WHITE


func _on_save_item_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		_selected_index = index
		_on_load_pressed()


func _on_load_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _save_list.size():
		return
	var save = _save_list[_selected_index]
	save_selected.emit(save.filepath)


func _on_delete_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _save_list.size():
		return
	var save = _save_list[_selected_index]
	_pending_delete_universe = ""
	_confirm_label.text = "确认删除存档“%s”？\n宇宙：%s · 第 %d 天" % [
		save.save_name, save.universe_name, int(save.game_day),
	]
	_confirm_overlay.visible = true


func _on_delete_universe_pressed(universe_name: String, save_count: int) -> void:
	_pending_delete_universe = universe_name
	_confirm_label.text = "确认删除整个宇宙“%s”？\n其下 %d 个存档都会被删除，此操作不可撤销。" % [
		universe_name, save_count,
	]
	_confirm_overlay.visible = true


func _on_delete_confirmed() -> void:
	if not _pending_delete_universe.is_empty():
		var universe_name := _pending_delete_universe
		var universe_deleted := SaveManager.delete_universe(universe_name)
		_pending_delete_universe = ""
		_confirm_overlay.visible = false
		_status_label.text = "已删除宇宙：%s" % universe_name if universe_deleted else "删除失败：宇宙存档不可用"
		_status_label.modulate = Color(0.65, 1.0, 0.72) if universe_deleted else Color(1.0, 0.5, 0.42)
		_refresh_saves()
		return
	if _selected_index < 0 or _selected_index >= _save_list.size():
		_close_delete_confirmation()
		return
	var save = _save_list[_selected_index]
	var deleted := SaveManager.delete_save(save.filepath)
	_confirm_overlay.visible = false
	_status_label.text = "已删除：%s" % save.save_name if deleted else "删除失败：存档文件不可用"
	_status_label.modulate = Color(0.65, 1.0, 0.72) if deleted else Color(1.0, 0.5, 0.42)
	_refresh_saves()


func _close_delete_confirmation() -> void:
	_confirm_overlay.visible = false
	_pending_delete_universe = ""


func _on_back_pressed() -> void:
	close_browser()


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
