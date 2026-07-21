class_name HazardForecastService
extends RefCounted
## 仅根据文明公开知识与观测生成预测；禁止接收 ScenarioManager 或未来真实状态。

enum ForecastLevel {
	NONE,
	QUALITATIVE_WARNING,
	REGIONAL_RISK,
	QUANTITATIVE_IMPACT,
	HIGH_PRECISION_PROBABILISTIC,
}

var current_snapshot: Dictionary = {}
var _next_forecast_id: int = 1


func build_forecast(p_game_day: float, p_capabilities: Dictionary, p_observation_data: Dictionary,
		p_infrastructure: Dictionary, p_census_snapshot: Dictionary) -> Dictionary:
	var level := ForecastLevel.NONE
	var baseline: float = p_observation_data.get("baseline_days", 0.0)
	var quality: float = p_observation_data.get("data_quality", 0.0)
	var calibration: float = p_observation_data.get("calibration", 0.0)
	var stations: int = p_observation_data.get("station_count", 0)
	var coverage: float = p_infrastructure.get("spatial_coverage", 0.0)
	if p_capabilities.get("hazard_warning", false) and baseline >= 1.0:
		level = ForecastLevel.QUALITATIVE_WARNING
	if p_capabilities.get("regional_hazard_projection", false) and stations > 0 and baseline >= 30.0 and quality >= 0.2:
		level = ForecastLevel.REGIONAL_RISK
	if p_capabilities.get("casualty_estimation", false) and level >= ForecastLevel.REGIONAL_RISK and p_census_snapshot.get("complete", false):
		level = ForecastLevel.QUANTITATIVE_IMPACT
	if p_capabilities.get("knowledge_loss_projection", false) and level >= ForecastLevel.QUANTITATIVE_IMPACT and coverage >= 0.6 and calibration >= 0.65:
		level = ForecastLevel.HIGH_PRECISION_PROBABILISTIC

	var confidence := clampf(quality * 0.65 + calibration * 0.2 + coverage * 0.15, 0.0, 0.95)
	var measurement: Dictionary = p_observation_data.get("latest_measurement", {})
	var snapshot: Dictionary = {
		"forecast_id": "forecast:%05d" % _next_forecast_id,
		"generated_game_day": p_game_day,
		"source_observation_version": int(p_observation_data.get("data_version", 0)),
		"source_satellite_version": int(p_infrastructure.get("network_version", 0)),
		"model_capability_version": 1,
		"level": level,
		"confidence": confidence,
		"valid_until_game_day": p_game_day + maxf(1.0, 30.0 * maxf(0.15, confidence)),
		"known_fields": [],
		"assumptions": ["仅使用已记录观测；规则层稳定纪元日期不参与文明预测"],
		"stale": false,
	}
	if level >= ForecastLevel.QUALITATIVE_WARNING:
		var radiation: float = measurement.get("radiation", 0.0)
		var stability: float = measurement.get("stability", 1.0)
		snapshot["risk_trend"] = "rising" if radiation > 2.0 or stability < 0.5 else "uncertain"
		snapshot["known_fields"].append("risk_trend")
	if level >= ForecastLevel.REGIONAL_RISK:
		var width := lerpf(240.0, 45.0, confidence)
		snapshot["time_window"] = {"earliest": p_game_day + 1.0, "latest": p_game_day + width}
		snapshot["possible_zone_ids"] = measurement.get("possible_zone_ids", []).duplicate()
		snapshot["known_fields"].append_array(["time_window", "possible_zone_ids"])
	if level >= ForecastLevel.QUANTITATIVE_IMPACT:
		var exposed: int = maxi(0, int(p_census_snapshot.get("exposed_population", 0)))
		var uncertainty := 1.0 - confidence
		snapshot["casualty_range"] = {
			"minimum": int(exposed * 0.02 * uncertainty),
			"maximum": int(exposed * (0.2 + 0.5 * uncertainty)),
		}
		snapshot["known_fields"].append("casualty_range")
	if level >= ForecastLevel.HIGH_PRECISION_PROBABILISTIC:
		snapshot["knowledge_loss_ranges"] = p_census_snapshot.get("knowledge_carrier_ranges", {}).duplicate(true)
		snapshot["known_fields"].append("knowledge_loss_ranges")
	_next_forecast_id += 1
	current_snapshot = snapshot
	return snapshot.duplicate(true)


func get_public_snapshot() -> Dictionary:
	return current_snapshot.duplicate(true)


func invalidate() -> void:
	if not current_snapshot.is_empty():
		current_snapshot["stale"] = true
		current_snapshot["valid_until_game_day"] = -1.0


func is_stale(p_game_day: float, p_observation_version: int, p_satellite_version: int) -> bool:
	if current_snapshot.is_empty():
		return true
	var stale := (
		p_game_day > float(current_snapshot.get("valid_until_game_day", -1.0))
		or p_observation_version != int(current_snapshot.get("source_observation_version", -1))
		or p_satellite_version != int(current_snapshot.get("source_satellite_version", -1))
	)
	current_snapshot["stale"] = stale
	return stale


func compare_plans(p_plans: Array, p_forecast_snapshot: Dictionary) -> Array:
	var result: Array = []
	for plan in p_plans:
		if plan is Dictionary:
			var view := {"plan_id": plan.get("plan_id", ""), "known_fields": p_forecast_snapshot.get("known_fields", []).duplicate()}
			for field in ["casualty_range", "knowledge_loss_ranges", "possible_zone_ids"]:
				if p_forecast_snapshot.has(field):
					view[field] = p_forecast_snapshot[field]
			result.append(view)
	return result


func get_state() -> Dictionary:
	return {"next_forecast_id": _next_forecast_id, "current_snapshot": current_snapshot.duplicate(true)}


func load_state(p_state: Dictionary) -> void:
	_next_forecast_id = maxi(1, int(p_state.get("next_forecast_id", 1)))
	current_snapshot = p_state.get("current_snapshot", {}).duplicate(true)
