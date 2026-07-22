class_name ExplorationSystem
extends RefCounted
## Converts a completed physical expedition into bounded, serializable public observations.

const STATE_VERSION := 1

var survey_log: Array[Dictionary] = []


func can_plan_expedition(p_origin_zone_id: int, p_target_zone_id: int, p_planet_zones, p_settlement_system) -> Dictionary:
	if p_origin_zone_id < 0 or p_target_zone_id < 0 or p_origin_zone_id == p_target_zone_id:
		return {"success": false, "message": "出发地或目标区域无效"}
	if p_target_zone_id not in p_planet_zones.get_zone_neighbors(p_origin_zone_id):
		return {"success": false, "message": "早期勘探只能前往相邻区域"}
	if p_settlement_system.get_population(p_origin_zone_id) <= 0:
		return {"success": false, "message": "出发区域没有可用人口"}
	return {"success": true, "message": ""}


func complete_survey(p_operation: Dictionary, p_planet_zones, p_settlement_system, p_game_day: float) -> Dictionary:
	var target_zone_id := int(p_operation.get("destination_zone_id", -1))
	var zone = p_planet_zones.get_zone(target_zone_id)
	if zone == null:
		return {"success": false, "message": "勘探目标不存在"}
	var source_id := "survey:%s" % str(p_operation.get("operation_id", "unknown"))
	var observations := {
		"zone_id": target_zone_id,
		"latitude": zone.lat_center,
		"longitude": zone.lon_center,
		"terrain": zone.terrain_type,
		"temperature": snappedf(zone.temperature, 0.5),
		"air_temperature": snappedf(zone.air_temperature, 0.5),
		"radiation": snappedf(zone.radiation, 0.05),
		"light_intensity": snappedf(zone.light_intensity, 0.01),
		"atmosphere_state": zone.get_atmosphere_state(),
		"route_familiarity": "勘探队完成一次地面往返",
		"resource_estimates": {
			"iron": _estimate_interval(float(zone.resource_deposits.get("iron", 0.0)), 0.2),
			"copper": _estimate_interval(float(zone.resource_deposits.get("copper", 0.0)), 0.2),
			"rare_mineral": _estimate_interval(float(zone.resource_deposits.get("rare_mineral", 0.0)), 0.2),
			"fertility": _estimate_interval(float(zone.fertility), 0.2),
			"algae_density": _estimate_interval(float(zone.algae_density), 0.2),
		},
	}
	var applied: bool = bool(p_settlement_system.apply_survey_result(target_zone_id, observations, 0.72, p_game_day, source_id))
	if not applied:
		return {"success": false, "message": "该勘探结果已经记录"}
	var record := {
		"source_id": source_id,
		"operation_id": p_operation.get("operation_id", ""),
		"zone_id": target_zone_id,
		"game_day": p_game_day,
		"observations": observations,
	}
	survey_log.append(record)
	return {"success": true, "message": "区域 #%d 的勘探估计已记录" % target_zone_id, "record": record.duplicate(true)}


func update_staleness(p_game_day: float, p_settlement_system) -> void:
	for zone_key in p_settlement_system.zone_knowledge:
		var zone_id := int(zone_key)
		var record: Dictionary = p_settlement_system.zone_knowledge[zone_key]
		if int(record.get("knowledge_level", 0)) < p_settlement_system.ZoneKnowledgeLevel.SURVEYED:
			continue
		if p_game_day - float(record.get("updated_game_day", 0.0)) >= 90.0:
			p_settlement_system.mark_knowledge_stale(zone_id, "上次地面勘探已超过 90 天")


func get_state() -> Dictionary:
	return {"state_version": STATE_VERSION, "survey_log": survey_log.duplicate(true)}


func load_state(p_data: Dictionary) -> bool:
	if not p_data.get("survey_log", []) is Array:
		return false
	survey_log.assign(p_data.get("survey_log", []))
	return true


func _estimate_interval(p_value: float, p_step: float) -> Dictionary:
	var safe_step := maxf(0.01, p_step)
	var lower := clampf(floor(p_value / safe_step) * safe_step, 0.0, 1.0)
	var upper := clampf(lower + safe_step, 0.0, 1.0)
	return {"lower": lower, "upper": upper, "label": "%.0f%%—%.0f%%" % [lower * 100.0, upper * 100.0]}
