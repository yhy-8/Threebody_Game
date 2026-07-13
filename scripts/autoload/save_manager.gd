extends Node
## 存档管理 — 存档扫描/加载/保存/删除

const SAVE_DIR := "res://saves/"

var _current_save_path: String = ""


class SaveInfo:
	var filepath: String
	var save_name: String
	var universe_name: String
	var save_time: String
	var game_day: float
	var is_legacy: bool

	func _init(p_filepath: String, p_save_name: String, p_universe_name: String,
			p_save_time: String, p_game_day: float, p_is_legacy: bool = false) -> void:
		filepath = p_filepath
		save_name = p_save_name
		universe_name = p_universe_name
		save_time = p_save_time
		game_day = p_game_day
		is_legacy = p_is_legacy


## 返回 {universe_name: [SaveInfo, ...]}
func scan_saves() -> Dictionary:
	var saves := {}
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return saves
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".sav"):
			var path := SAVE_DIR.path_join(file_name)
			var info := _read_save_info(path)
			if info != null:
				var uni_name := info.universe_name
				if not saves.has(uni_name):
					saves[uni_name] = []
				saves[uni_name].append(info)
		file_name = dir.get_next()
	dir.list_dir_end()
	return saves


## 返回 [{name, count, latest_time}]
func scan_universes() -> Array:
	var all_saves := scan_saves()
	var result: Array = []
	for uni_name in all_saves:
		var save_list: Array = all_saves[uni_name]
		var latest := ""
		for s in save_list:
			if s.save_time > latest:
				latest = s.save_time
		result.append({
			"name": uni_name,
			"count": save_list.size(),
			"latest_time": latest
		})
	return result


func universe_exists(name: String) -> bool:
	var normalized := name.to_lower().strip_edges()
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return false
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".sav"):
			var path := SAVE_DIR.path_join(file_name)
			var info := _read_save_info(path)
			if info != null and info.universe_name.to_lower().strip_edges() == normalized:
				dir.list_dir_end()
				return true
		file_name = dir.get_next()
	dir.list_dir_end()
	return false


func find_latest_save() -> SaveInfo:
	var all_saves := scan_saves()
	var latest: SaveInfo = null
	for uni_name in all_saves:
		for s: SaveInfo in all_saves[uni_name]:
			if latest == null or s.save_time > latest.save_time:
				latest = s
	return latest


func save_game(simulator, save_name: String, universe_name: String) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR.path_join(universe_name + ".sav")
	# TODO: Phase 5 — 序列化 simulator 状态
	return true


func load_game(filepath: String, _simulator = null) -> bool:
	if not FileAccess.file_exists(filepath):
		return false
	# TODO: Phase 5 — 反序列化到 simulator
	var info := _read_save_info(filepath)
	if info != null:
		EventBus.game_loaded.emit(info.universe_name)
		return true
	return false


func delete_save(filepath: String) -> bool:
	if not FileAccess.file_exists(filepath):
		return false
	return DirAccess.remove_absolute(filepath)


func delete_universe(universe_name: String) -> bool:
	var all_saves := scan_saves()
	var saves_in_uni: Array = all_saves.get(universe_name, [])
	if saves_in_uni.is_empty():
		return false
	for s: SaveInfo in saves_in_uni:
		DirAccess.remove_absolute(s.filepath)
	return true


func _read_save_info(path: String) -> SaveInfo:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return null
	var data = json.get_data()
	if not data is Dictionary:
		return null
	return SaveInfo.new(
		path,
		data.get("save_name", "未知存档"),
		data.get("universe_name", "未知宇宙"),
		data.get("save_time", ""),
		float(data.get("game_day", 0.0)),
		data.get("is_legacy", false)
	)
