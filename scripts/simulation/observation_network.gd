class_name ObservationNetwork
extends RefCounted
## 只保存文明实际取得的观测质量，不持有场景种子或未来星历。

var data_version: int = 0
var baseline_days: float = 0.0
var data_quality: float = 0.0
var calibration: float = 0.0
var station_count: int = 0
var last_observation_day: float = -1.0
var latest_public_measurement: Dictionary = {}
var _version_day_accumulator: float = 0.0


func update(p_game_day: float, p_dt: float, p_has_telescope: bool, p_entities, p_public_measurement: Dictionary) -> void:
	station_count = 0
	var staffed_ratio := 0.0
	if p_entities != null:
		for station in p_entities.get_buildings_by_type("observatory_station"):
			if station.under_construction or station.destroyed:
				continue
			station_count += 1
			staffed_ratio += station.last_run_ratio
	if not p_has_telescope:
		data_quality = 0.0
		calibration = 0.0
		return

	baseline_days += p_dt
	_version_day_accumulator += p_dt
	var average_station_ratio := staffed_ratio / float(station_count) if station_count > 0 else 0.0
	calibration = clampf(average_station_ratio * minf(1.0, baseline_days / 90.0), 0.0, 1.0)
	data_quality = clampf(0.08 + 0.52 * calibration + 0.08 * mini(station_count, 3), 0.0, 0.75)
	latest_public_measurement = p_public_measurement.duplicate(true)
	last_observation_day = p_game_day
	if _version_day_accumulator >= 1.0:
		var elapsed_whole_days := int(_version_day_accumulator)
		data_version += elapsed_whole_days
		_version_day_accumulator -= elapsed_whole_days


func get_public_data() -> Dictionary:
	return {
		"data_version": data_version,
		"baseline_days": baseline_days,
		"data_quality": data_quality,
		"calibration": calibration,
		"station_count": station_count,
		"last_observation_day": last_observation_day,
		"latest_measurement": latest_public_measurement.duplicate(true),
	}


func get_state() -> Dictionary:
	var result := get_public_data()
	result["version_day_accumulator"] = _version_day_accumulator
	return result


func load_state(p_state: Dictionary) -> void:
	data_version = maxi(0, int(p_state.get("data_version", 0)))
	baseline_days = maxf(0.0, float(p_state.get("baseline_days", 0.0)))
	data_quality = clampf(float(p_state.get("data_quality", 0.0)), 0.0, 1.0)
	calibration = clampf(float(p_state.get("calibration", 0.0)), 0.0, 1.0)
	station_count = maxi(0, int(p_state.get("station_count", 0)))
	last_observation_day = float(p_state.get("last_observation_day", -1.0))
	latest_public_measurement = p_state.get("latest_measurement", {}).duplicate(true)
	_version_day_accumulator = clampf(float(p_state.get("version_day_accumulator", 0.0)), 0.0, 1.0)
