extends Node
## 区域人口批量分配、详情控件稳定性与游戏子界面空格暂停回归测试。

var _failures: int = 0


func _ready() -> void:
	GameState.new_game("__子界面交互回归")
	GameState.entities.population.total = 100
	GameState.entities.population.breeders = 0
	GameState.entities.resources["iron"].amount = 1000.0
	var build_result: Dictionary = GameState.decision_manager.execute_decision(
		"build_algae_collector", GameState.entities, GameState.tech_tree,
		GameState.planet_zones, 0
	)
	_expect(build_result.get("success", false), "无法创建工人分配测试建筑")
	var building_id: int = build_result.get("building_id", -1)

	var zone_scene := await _spawn("res://scenes/zone_view/zone_view.tscn")
	zone_scene._on_zone_selected(0)
	await get_tree().process_frame
	var breeder_plus_ten: Button = zone_scene.find_child("BreederPlus10", true, false)
	var breeder_fill: Button = zone_scene.find_child("BreederFill", true, false)
	var breeder_clear: Button = zone_scene.find_child("BreederClear", true, false)
	_expect(breeder_plus_ten != null and breeder_fill != null and breeder_clear != null, "生育人口批量按钮不完整")
	if breeder_plus_ten != null:
		breeder_plus_ten.pressed.emit()
		_expect(GameState.entities.population.breeders == 10, "+10 没有一次分配 10 名生育人口")
	if breeder_fill != null:
		breeder_fill.pressed.emit()
		_expect(GameState.entities.population.breeders == 100, "最大分配没有使用全部闲置人口")
	if breeder_clear != null:
		breeder_clear.pressed.emit()
		_expect(GameState.entities.population.breeders == 0, "清空没有撤回全部生育人口")

	var worker_plus_ten: Button = zone_scene.find_child("Worker%dPlus10" % building_id, true, false)
	var worker_clear: Button = zone_scene.find_child("Worker%dClear" % building_id, true, false)
	_expect(worker_plus_ten != null and worker_clear != null, "建筑工人批量按钮不完整")
	if worker_plus_ten != null:
		worker_plus_ten.pressed.emit()
		var building = GameState.entities.get_building(building_id)
		_expect(building.assigned_workers == building.worker_capacity, "+10 没有按岗位容量自动填入可用人数")
		var stable_button_id := worker_plus_ten.get_instance_id()
		zone_scene._process(0.3)
		await get_tree().process_frame
		var refreshed_button: Button = zone_scene.find_child("Worker%dPlus10" % building_id, true, false)
		_expect(refreshed_button != null and refreshed_button.get_instance_id() == stable_button_id, "周期刷新仍在重建右侧按钮")
	if worker_clear != null:
		worker_clear.pressed.emit()
		_expect(GameState.entities.get_building(building_id).assigned_workers == 0, "清空没有撤回全部建筑工人")

	await _check_space_pause(zone_scene, "区域界面")
	await _discard(zone_scene)
	for entry in [
		["res://scenes/tech_tree/tech_tree.tscn", "科技树"],
		["res://scenes/decision/decision.tscn", "政策界面"],
		["res://scenes/starmap/starmap_view.tscn", "星图"],
	]:
		var scene := await _spawn(entry[0])
		await _check_space_pause(scene, entry[1])
		await _discard(scene)

	if _failures == 0:
		print("SUBSCREEN_INTERACTION_TEST_OK")
	get_tree().quit(_failures)


func _check_space_pause(scene: Node, screen_name: String) -> void:
	GameState.paused = false
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = true
	scene._input(event)
	_expect(GameState.paused, "%s 中空格没有暂停模拟" % screen_name)
	scene._input(event)
	_expect(not GameState.paused, "%s 中再次按空格没有继续模拟" % screen_name)
	await get_tree().process_frame


func _spawn(path: String) -> Node:
	var scene := (load(path) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	return scene


func _discard(scene: Node) -> void:
	scene.queue_free()
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)

