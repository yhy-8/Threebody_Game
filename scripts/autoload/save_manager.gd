extends Node
## 存档管理 — 存档扫描/加载/保存/删除

const SAVE_DIRECTORY := "res://saves/"

var _current_save_path: String = ""


func ensure_save_directory() -> bool:
	var absolute_dir := get_save_directory()
	var ready := DirAccess.dir_exists_absolute(absolute_dir)
	if not ready:
		ready = DirAccess.make_dir_recursive_absolute(absolute_dir) == OK
	return ready


func get_save_directory() -> String:
	return ProjectSettings.globalize_path(SAVE_DIRECTORY)


func get_current_save_path() -> String:
	return _current_save_path


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
	if not ensure_save_directory():
		return saves
	var save_dir := get_save_directory()
	var dir := DirAccess.open(save_dir)
	if dir == null:
		return saves
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".sav"):
			var path := save_dir.path_join(file_name)
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
	var save_dir := get_save_directory()
	var dir := DirAccess.open(save_dir)
	if dir == null:
		return false
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".sav"):
			var path := save_dir.path_join(file_name)
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
	var source = simulator if simulator != null else GameState
	if source == null or not source.has_method("to_dict"):
		return false
	if not ensure_save_directory():
		return false
	var safe_universe := universe_name.validate_filename()
	var safe_save := save_name.validate_filename()
	var save_time := Time.get_datetime_string_from_system(false, true)
	var timestamp := save_time.replace("-", "").replace(":", "").replace(" ", "_")
	var unique_suffix := str(Time.get_ticks_usec())
	var path := get_save_directory().path_join("%s__%s_%s__%s.sav" % [safe_universe, timestamp, unique_suffix, safe_save])
	while FileAccess.file_exists(path):
		unique_suffix += "_1"
		path = get_save_directory().path_join("%s__%s_%s__%s.sav" % [safe_universe, timestamp, unique_suffix, safe_save])
	var state: Dictionary = source.to_dict()
	var state_payload: String = JSON.stringify(state)
	var data: Dictionary = {
		"save_name": save_name,
		"universe_name": universe_name,
		"save_time": save_time,
		"game_day": source.game_time,
		"is_legacy": false,
		"state": state,
		"state_payload": state_payload,
		"state_checksum": state_payload.sha256_text(),
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_current_save_path = path
	return true


func load_game(filepath: String, simulator = null) -> bool:
	if not _is_safe_save_path(filepath):
		return false
	if not FileAccess.file_exists(filepath):
		return false
	var file := FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK:
		return false
	var data = json.get_data()
	if not _is_valid_save_document(data):
		return false
	var target = simulator if simulator != null else GameState
	if target == null or not target.has_method("from_dict"):
		return false
	if target.has_method("validate_serialized_state") and not target.validate_serialized_state(data["state"]):
		return false
	var load_result = target.from_dict(data["state"])
	if load_result is bool and not load_result:
		return false
	_current_save_path = filepath
	EventBus.game_loaded.emit(data.get("universe_name", target.universe_name))
	return true


func delete_save(filepath: String) -> bool:
	if not _is_safe_save_path(filepath):
		return false
	if not FileAccess.file_exists(filepath):
		return false
	return DirAccess.remove_absolute(filepath) == OK


func delete_universe(universe_name: String) -> bool:
	var all_saves := scan_saves()
	var saves_in_uni: Array = all_saves.get(universe_name, [])
	if saves_in_uni.is_empty():
		return false
	for s: SaveInfo in saves_in_uni:
		if not delete_save(s.filepath):
			return false
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
	if not _is_valid_save_document(data):
		return null
	return SaveInfo.new(
		path,
		data.get("save_name", "未知存档"),
		data.get("universe_name", "未知宇宙"),
		data.get("save_time", ""),
		float(data.get("game_day", 0.0)),
		data.get("is_legacy", false)
	)


func _is_valid_save_document(data) -> bool:
	if not data is Dictionary or not data.get("state", null) is Dictionary:
		return false
	var state: Dictionary = data["state"]
	if data.has("state_payload"):
		var payload: String = str(data["state_payload"])
		if payload.is_empty() or not data.has("state_checksum") or payload.sha256_text() != str(data["state_checksum"]):
			return false
		var payload_json := JSON.new()
		if payload_json.parse(payload) != OK or not payload_json.get_data() is Dictionary:
			return false
		state = payload_json.get_data()
		data["state"] = state
	if not GameState.validate_serialized_state(state):
		return false
	return true


func _is_safe_save_path(filepath: String) -> bool:
	if filepath.is_empty() or not filepath.to_lower().ends_with(".sav"):
		return false
	var base: String = get_save_directory().simplify_path()
	var resolved: String = ProjectSettings.globalize_path(filepath).simplify_path()
	return resolved.begins_with(base + "/") and resolved.get_base_dir() == base
