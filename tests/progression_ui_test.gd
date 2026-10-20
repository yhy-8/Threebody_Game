extends Node
## 主界面文明目标、事件抉择与危机响应面板的可操作性与边界回归。

var _failures: int = 0


func _ready() -> void:
	GameState.set_process(false)
	await _run()
	if _failures == 0:
		print("PROGRESSION_UI_TEST_OK")
	GameState.reset()
	get_tree().quit(_failures)


func _run() -> void:
	var packed: PackedScene = load("res://scenes/game/main_screen.tscn")
	var scene: Node = packed.instantiate()
	add_child(scene)
	await get_tree().process_frame
	scene.get_node("CapitalOverlay/CapitalVBox/ConfirmCapitalButton").pressed.emit()
	await get_tree().process_frame
	var toolbar: Control = scene.get_node("Toolbar")
	_expect(_inside_viewport(toolbar), "新增目标/抉择/危机按钮后工具栏超出视口")
	var objectives_button: Button = scene.get_node_or_null("Toolbar/ObjectivesButton")
	_expect(objectives_button != null, "主界面缺少文明目标按钮")
	if objectives_button != null:
		objectives_button.pressed.emit()
		await get_tree().process_frame
		var overlay: Control = scene.get_node_or_null("ObjectivesOverlay")
		_expect(overlay != null and overlay.visible, "文明目标面板无法打开")
		if overlay != null:
			_expect(_inside_viewport(overlay.find_child("Panel", true, false)), "文明目标面板超出视口")
			var body: Node = overlay.find_child("Panel", true, false).find_child("VBoxContainer", true, false)
			_expect(body == null or body.get_child_count() > 0, "文明目标面板没有内容")
			var go_button: Button = overlay.find_child("ObjectiveGoButton", true, false)
			_expect(go_button != null and str(go_button.text).contains("前往"), "当前目标没有提供前往操作界面的入口")
			overlay.visible = false

	var context: Dictionary = GameState.get_civilization_context()
	context["min_populated_temperature"] = 20.0
	context["food_days"] = 30.0
	context["population"] = 100
	context["knowledge_advanced"] = 4
	context["teaching_plan_count"] = 0
	context["damaged_building_count"] = 0
	context["power_shortage"] = false
	GameState.civilization_events.evaluate(context, 10.0)
	var event_button: Button = scene.get_node_or_null("Toolbar/CivilizationEventButton")
	_expect(event_button != null, "主界面缺少事件抉择按钮")
	if event_button != null:
		event_button.pressed.emit()
		await get_tree().process_frame
		var overlay: Control = scene.get_node_or_null("CivilizationEventOverlay")
		_expect(overlay != null and overlay.visible, "事件抉择面板无法打开")
		if overlay != null:
			_expect(_inside_viewport(overlay.find_child("Panel", true, false)), "事件抉择面板超出视口")
			var choice_button: Button = null
			for button in overlay.find_children("*", "Button", true, false):
				if str(button.text).contains("夜间观测"):
					choice_button = button
					break
			_expect(choice_button != null, "事件面板没有显示真实选项")
			if choice_button != null:
				choice_button.pressed.emit()
				await get_tree().process_frame
				_expect(GameState.get_pending_civilization_event().is_empty(), "点击事件选项后没有完成抉择")
			overlay.visible = false

	var hazard_button: Button = scene.get_node_or_null("Toolbar/HazardResponseButton")
	_expect(hazard_button != null, "主界面缺少危机响应按钮")
	if hazard_button != null:
		hazard_button.pressed.emit()
		await get_tree().process_frame
		var overlay: Control = scene.get_node_or_null("HazardResponseOverlay")
		_expect(overlay != null and overlay.visible, "危机响应面板无法打开")
		if overlay != null:
			_expect(_inside_viewport(overlay.find_child("Panel", true, false)), "危机响应面板超出视口")
			var commit_button: Button = null
			for button in overlay.find_children("*", "Button", true, false):
				if str(button.text).contains("确认并承诺"):
					commit_button = button
					break
			_expect(commit_button != null, "危机面板没有响应预案确认入口")
			if commit_button != null:
				_expect(commit_button.disabled, "没有庇护设施时仍可确认会凭空保护人口的预案")
			overlay.visible = false

	scene.queue_free()
	await get_tree().process_frame


func _inside_viewport(p_control: Control) -> bool:
	return get_viewport().get_visible_rect().encloses(p_control.get_global_rect())


func _expect(p_condition: bool, p_message: String) -> void:
	if p_condition:
		return
	_failures += 1
	push_error(p_message)
