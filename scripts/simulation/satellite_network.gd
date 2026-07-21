class_name SatelliteNetwork
extends RefCounted
## 卫星观测基础设施状态；只有已部署且在线的卫星贡献覆盖率。

var satellites: Array[Dictionary] = []
var network_version: int = 0


func deploy_satellite(p_satellite_id: String, p_sensor_quality: float, p_coverage: float) -> bool:
	if p_satellite_id.is_empty() or not is_finite(p_sensor_quality) or not is_finite(p_coverage):
		return false
	for satellite in satellites:
		if satellite.get("id", "") == p_satellite_id:
			return false
	satellites.append({
		"id": p_satellite_id,
		"sensor_quality": clampf(p_sensor_quality, 0.0, 1.0),
		"coverage": clampf(p_coverage, 0.0, 1.0),
		"online": true,
	})
	network_version += 1
	return true


func set_online(p_satellite_id: String, p_online: bool) -> bool:
	for satellite in satellites:
		if satellite.get("id", "") == p_satellite_id:
			if satellite.get("online", false) != p_online:
				satellite["online"] = p_online
				network_version += 1
			return true
	return false


func get_public_infrastructure() -> Dictionary:
	var coverage_product := 1.0
	var weighted_quality := 0.0
	var weight := 0.0
	var online_count := 0
	for satellite in satellites:
		if not satellite.get("online", false):
			continue
		online_count += 1
		var coverage: float = satellite.get("coverage", 0.0)
		coverage_product *= 1.0 - coverage
		weighted_quality += float(satellite.get("sensor_quality", 0.0)) * coverage
		weight += coverage
	return {
		"network_version": network_version,
		"online_satellites": online_count,
		"spatial_coverage": clampf(1.0 - coverage_product, 0.0, 1.0),
		"sensor_quality": weighted_quality / weight if weight > 0.0 else 0.0,
	}


func get_state() -> Dictionary:
	return {"network_version": network_version, "satellites": satellites.duplicate(true)}


func load_state(p_state: Dictionary) -> void:
	network_version = maxi(0, int(p_state.get("network_version", 0)))
	satellites.clear()
	for value in p_state.get("satellites", []):
		if value is Dictionary and not String(value.get("id", "")).is_empty():
			satellites.append(value.duplicate(true))
