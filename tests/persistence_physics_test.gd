extends Node
## 存档完整往返、路径边界、唯一命名与固定步长物理回归测试。

var _failures: int = 0
var _created_paths: Array[String] = []


func _ready() -> void:
	_test_persistence_roundtrip()
	_test_fixed_step_and_prediction()
	for path in _created_paths:
		if FileAccess.file_exists(path):
			SaveManager.delete_save(path)
	if _failures == 0:
		print("PERSISTENCE_PHYSICS_TEST_OK")
	get_tree().quit(_failures)


func _test_persistence_roundtrip() -> void:
	var universe := "__往返回归_%d" % Time.get_ticks_usec()
	GameState.new_game(universe)
	GameState.time_scale = 5.0
	GameState.paused = true
	GameState.game_time = 12.5
	GameState._simulation_accumulator = 0.007
	GameState.last_autosave_day = 11
	GameState.config["test_marker"] = "roundtrip"
	GameState.entities.population.stored_loss_accumulator = 0.375
	var zone = GameState.planet_zones.get_zone(0)
	zone.temperature = 33.0
	zone.radiation = 4.25
	zone.light_intensity = 0.61
	var rng_state: int = GameState.environment.rng.state
	_expect(SaveManager.save_game(GameState, "同名", universe), "第一次保存失败")
	var first_path: String = SaveManager.get_current_save_path()
	_created_paths.append(first_path)
	_expect(SaveManager.save_game(GameState, "同名", universe), "第二次保存失败")
	var second_path: String = SaveManager.get_current_save_path()
	_created_paths.append(second_path)
	_expect(first_path != second_path and FileAccess.file_exists(first_path) and FileAccess.file_exists(second_path), "同秒同名存档发生覆盖")

	GameState.time_scale = 1.0
	GameState.paused = false
	GameState.game_time = 0.0
	zone.radiation = 0.0
	zone.light_intensity = 0.0
	_expect(SaveManager.load_game(first_path), "有效存档加载失败")
	_expect(is_equal_approx(GameState.time_scale, 5.0) and GameState.paused and is_equal_approx(GameState.game_time, 12.5), "倍率、暂停或时间没有恢复")
	zone = GameState.planet_zones.get_zone(0)
	_expect(is_equal_approx(zone.radiation, 4.25) and is_equal_approx(zone.light_intensity, 0.61), "区域辐射或光照没有恢复")
	_expect(GameState.config.get("test_marker", "") == "roundtrip", "自定义配置没有随档恢复")
	_expect(is_equal_approx(GameState.entities.population.stored_loss_accumulator, 0.375), "人口损耗余量没有恢复")
	_expect(GameState.environment.rng.state == rng_state, "模拟随机数状态没有恢复")
	GameState.paused = false
	GameState._runtime_settings["auto_save_interval"] = 1
	GameState._autosave_elapsed_seconds = 59.95
	GameState.update(0.1)
	var autosave_path: String = SaveManager.get_current_save_path()
	_created_paths.append(autosave_path)
	_expect(FileAccess.file_exists(autosave_path) and GameState.last_autosave_day >= 0, "自动存档间隔没有实际调用方")
	var time_before_invalid: float = GameState.game_time
	_expect(not GameState.from_dict({}) and is_equal_approx(GameState.game_time, time_before_invalid), "无效状态部分覆盖了当前游戏")
	_expect(not SaveManager.delete_save("/tmp/threebody_outside.sav"), "存档目录外路径未被拒绝")

	var tampered_path: String = SaveManager.get_save_directory().path_join("__tampered_%d.sav" % Time.get_ticks_usec())
	var tampered := FileAccess.open(tampered_path, FileAccess.WRITE)
	if tampered != null:
		var payload: String = JSON.stringify(GameState.to_dict())
		tampered.store_string(JSON.stringify({
			"save_name": "篡改档", "universe_name": "__篡改档", "save_time": "2026-01-01 00:00:00",
			"game_day": 0.0, "state": GameState.to_dict(), "state_payload": payload, "state_checksum": "bad",
		}))
		tampered.close()
		_created_paths.append(tampered_path)
		_expect(not SaveManager.scan_saves().has("__篡改档"), "校验失败存档仍显示在浏览器")


func _test_fixed_step_and_prediction() -> void:
	GameState.new_game("__固定步长回归")
	var initial: Dictionary = GameState.to_dict()
	GameState.update(1.0)
	var once_positions: Array = _positions()
	var once_time: float = GameState.game_time
	_expect(GameState.from_dict(initial), "无法恢复物理测试初态")
	for _index in 10:
		GameState.update(0.1)
	_expect(_positions_close(once_positions, _positions()) and is_equal_approx(once_time, GameState.game_time), "渲染分帧改变了物理结果")
	_expect(GameState.from_dict(initial), "无法再次恢复物理测试初态")
	GameState.set_time_scale(5.0)
	GameState.update(0.2)
	_expect(_positions_close(once_positions, _positions()) and is_equal_approx(once_time, GameState.game_time), "时间倍率改变了相同游戏时长的物理结果")

	var before_positions: Array = _positions()
	var before_rng: int = GameState.environment.rng.state
	var predicted: Array = GameState.environment.predict_trajectories(20, 0.25)
	_expect(predicted.size() == GameState.environment.stars.size() and predicted[0].size() == 20, "多体预测没有生成完整轨迹")
	_expect(_positions_close(before_positions, _positions()) and GameState.environment.rng.state == before_rng, "轨道预测修改了真实状态或随机数序列")


func _positions() -> Array:
	var result: Array = []
	for star in GameState.environment.stars:
		result.append(star.position)
	return result


func _positions_close(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	for index in first.size():
		if first[index].distance_to(second[index]) > 1e-7:
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
