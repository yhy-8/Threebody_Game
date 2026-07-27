class_name EnvironmentalHazardSystem
extends RefCounted
## Current-state environmental hazards, standing response plans, regional exposure, and single-settlement reports.

const STATE_VERSION := 1
const QUIET_DAYS_TO_RESOLVE := 1.0
const MINIMUM_HAZARD_DAYS := 0.5
const MAX_COMPLETED_REPORTS := 24
const DEFAULT_UNPLANNED_SHELTER_FRACTION := 0.15

const RESPONSE_PROFILES: Dictionary = {
	"population": {
		"name": "人口生存优先",
		"description": "把全部可运行庇护容量留给人口；危机期间生产收缩最大，档案和样机保护较弱。",
		"people_capacity_fraction": 1.0,
		"knowledge_protection": 0.2,
	},
	"balanced": {
		"name": "人口与知识均衡",
		"description": "以部分空间保存档案和关键样机；人口保护、生产损失与知识保护居中。",
		"people_capacity_fraction": 0.78,
		"knowledge_protection": 0.58,
	},
	"knowledge": {
		"name": "知识重建优先",
		"description": "为档案、教师资料和工程样机保留较多空间；可容纳人口减少，但灾后知识断层风险最低。",
		"people_capacity_fraction": 0.55,
		"knowledge_protection": 0.86,
	},
}

var active_hazard: Dictionary = {}
var response_plan: Dictionary = {}
var completed_reports: Array = []
var regional_loss_accumulators: Dictionary = {}
var latest_assessment: Dictionary = {}
var latest_exposure: Dictionary = {}
var _next_hazard_number: int = 1
var _next_plan_number: int = 1


func get_response_profiles() -> Array:
	var result: Array = []
	for profile_id in RESPONSE_PROFILES:
		var view: Dictionary = RESPONSE_PROFILES[profile_id].duplicate(true)
		view["id"] = profile_id
		result.append(view)
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		var order := {"population": 0, "balanced": 1, "knowledge": 2}
		return int(order.get(a.get("id", ""), 99)) < int(order.get(b.get("id", ""), 99))
	)
	return result


func commit_response_plan(p_priority: String, p_game_day: float, p_forecast: Dictionary,
		p_entities, p_settlement_system) -> Dictionary:
	if not active_hazard.is_empty():
		return {"success": false, "message": "环境危机已经开始；当前预案已锁定，危机结束后才能修订"}
	if not RESPONSE_PROFILES.has(p_priority):
		return {"success": false, "message": "未知的危机保存优先级"}
	var allocations: Dictionary = _build_current_allocations(p_priority, p_entities, p_settlement_system)
	var total_capacity: int = 0
	for allocation in allocations.values():
		total_capacity += int(allocation.get("operating_shelter_capacity", 0))
	if total_capacity <= 0:
		return {"success": false, "message": "没有已完工、已供能并已配员的庇护设施"}
	var profile: Dictionary = RESPONSE_PROFILES[p_priority]
	response_plan = {
		"state_version": STATE_VERSION,
		"plan_id": "hazard-plan:%05d" % _next_plan_number,
		"priority": p_priority,
		"priority_name": profile["name"],
		"committed_game_day": p_game_day,
		"forecast_id": str(p_forecast.get("forecast_id", "")),
		"forecast_level": int(p_forecast.get("level", 0)),
		"people_capacity_fraction": float(profile["people_capacity_fraction"]),
		"knowledge_protection": float(profile["knowledge_protection"]),
		"allocations_at_commit": allocations,
		"locked_by_hazard_id": "",
	}
	_next_plan_number += 1
	var view: Dictionary = get_response_plan_view(p_entities, p_settlement_system)
	return {
		"success": true,
		"message": "已确认「%s」；实际保护仍取决于危机发生时的设施、供电、配员和所在区域" % profile["name"],
		"plan": view,
	}


func get_response_plan_view(p_entities, p_settlement_system) -> Dictionary:
	if response_plan.is_empty():
		return {
			"committed": false,
			"priority": "",
			"priority_name": "尚未确认",
			"people_capacity_fraction": DEFAULT_UNPLANNED_SHELTER_FRACTION,
			"knowledge_protection": 0.0,
			"allocations": _build_current_allocations("", p_entities, p_settlement_system),
		}
	var view: Dictionary = response_plan.duplicate(true)
	view["committed"] = true
	view["allocations"] = _build_current_allocations(str(response_plan.get("priority", "")), p_entities, p_settlement_system)
	return view


func preview_response_priority(p_priority: String, p_entities, p_settlement_system) -> Dictionary:
	if not RESPONSE_PROFILES.has(p_priority):
		return {}
	return {
		"profile": (RESPONSE_PROFILES[p_priority] as Dictionary).duplicate(true),
		"allocations": _build_current_allocations(p_priority, p_entities, p_settlement_system),
	}


func begin_step(p_game_day: float, p_delta_days: float, p_zone_manager,
		p_settlement_system, p_entities) -> Dictionary:
	latest_assessment = _assess_populated_zones(p_zone_manager, p_settlement_system)
	var started: Dictionary = {}
	if (
		active_hazard.is_empty()
		and float(latest_assessment.get("trigger_score", 0.0)) > 0.0
		and int(latest_assessment.get("exposed_population", 0)) > 0
	):
		var hazard_id := "environment:%05d" % _next_hazard_number
		_next_hazard_number += 1
		active_hazard = {
			"state_version": STATE_VERSION,
			"hazard_id": hazard_id,
			"source_id": hazard_id,
			"started_game_day": p_game_day,
			"elapsed_days": 0.0,
			"quiet_days": 0.0,
			"starting_population": p_entities.population.total + p_entities.population.stored_population,
			"casualties": 0,
			"stored_casualties": 0,
			"destroyed_buildings": 0,
			"peak_trigger_score": float(latest_assessment.get("trigger_score", 0.0)),
			"peak_loss_rate": float(latest_assessment.get("maximum_loss_rate", 0.0)),
			"affected_zone_ids": (latest_assessment.get("affected_zone_ids", []) as Array).duplicate(),
			"response_plan_id": str(response_plan.get("plan_id", "")),
			"response_priority": str(response_plan.get("priority", "")),
		}
		if not response_plan.is_empty():
			response_plan["locked_by_hazard_id"] = hazard_id
		started = active_hazard.duplicate(true)
	if not active_hazard.is_empty():
		active_hazard["elapsed_days"] = float(active_hazard.get("elapsed_days", 0.0)) + p_delta_days
		active_hazard["peak_trigger_score"] = maxf(
			float(active_hazard.get("peak_trigger_score", 0.0)),
			float(latest_assessment.get("trigger_score", 0.0))
		)
		active_hazard["peak_loss_rate"] = maxf(
			float(active_hazard.get("peak_loss_rate", 0.0)),
			float(latest_assessment.get("maximum_loss_rate", 0.0))
		)
		for zone_id in latest_assessment.get("affected_zone_ids", []):
			if zone_id not in active_hazard["affected_zone_ids"]:
				active_hazard["affected_zone_ids"].append(zone_id)
	return {
		"started": not started.is_empty(),
		"started_hazard": started,
		"active": not active_hazard.is_empty(),
		"assessment": latest_assessment.duplicate(true),
	}


func get_workforce_multiplier(p_entities, p_settlement_system) -> float:
	if active_hazard.is_empty() or p_entities == null or p_settlement_system == null:
		return 1.0
	var allocations: Dictionary = _build_current_allocations(str(response_plan.get("priority", "")), p_entities, p_settlement_system)
	var sheltered_people: int = 0
	for allocation in allocations.values():
		sheltered_people += int(allocation.get("planned_protected_people", 0))
	var active_population: int = maxi(1, p_entities.population.total)
	var sheltered_fraction: float = clampf(float(sheltered_people) / float(active_population), 0.0, 1.0)
	return clampf(1.0 - sheltered_fraction * 0.85, 0.15, 1.0)


func process_population_exposure(p_delta_days: float, p_zone_manager, p_settlement_system,
		p_entities) -> Dictionary:
	var zone_reports: Array = []
	var total_loss: int = 0
	var population_at_risk: int = 0
	var rate_weighted_population: float = 0.0
	var total_population_before: int = maxi(0, p_entities.population.total)
	var plan_priority: String = str(response_plan.get("priority", ""))
	var people_capacity_fraction: float = (
		float(RESPONSE_PROFILES[plan_priority]["people_capacity_fraction"])
		if RESPONSE_PROFILES.has(plan_priority)
		else DEFAULT_UNPLANNED_SHELTER_FRACTION
	)
	for zone_key in p_settlement_system.region_population.keys():
		var zone_id: int = int(zone_key)
		var zone_population: int = p_settlement_system.get_population(zone_id)
		if zone_id < 0 or zone_population <= 0:
			continue
		var zone = p_zone_manager.get_zone(zone_id)
		if zone == null:
			continue
		var rates: Dictionary = _environment_loss_rates(zone.temperature, zone.radiation)
		var raw_rate: float = float(rates["temperature_rate"]) + float(rates["radiation_rate"])
		if raw_rate <= 0.0:
			continue
		var shelter: Dictionary = p_entities.get_zone_shelter_status(zone_id)
		var protected_capacity: int = int(floor(
			float(shelter.get("capacity", 0)) * people_capacity_fraction
		))
		var protected_people: int = mini(zone_population, maxi(0, protected_capacity))
		var exposed_people: int = zone_population - protected_people
		var environment_protection: float = float(shelter.get("environment_protection", 0.0))
		var shelter_radiation_protection: float = float(shelter.get("shelter_radiation_protection", 0.0))
		var area_radiation_protection: float = float(shelter.get("area_radiation_protection", 0.0))
		var exposed_rate: float = (
			float(rates["temperature_rate"])
			+ float(rates["radiation_rate"]) * (1.0 - area_radiation_protection)
		)
		var protected_rate: float = (
			float(rates["temperature_rate"]) * (1.0 - environment_protection)
			+ float(rates["radiation_rate"]) * (
				1.0 - maxf(area_radiation_protection, shelter_radiation_protection)
			)
		)
		var effective_rate: float = (
			(float(exposed_people) * exposed_rate + float(protected_people) * protected_rate)
			/ float(zone_population)
		)
		var accumulator_key: String = str(zone_id)
		var accumulator: float = maxf(0.0, float(regional_loss_accumulators.get(accumulator_key, 0.0)))
		accumulator += float(zone_population) * (1.0 - exp(-effective_rate * p_delta_days))
		var loss: int = mini(zone_population, int(accumulator))
		if loss > 0:
			accumulator -= float(loss)
			p_entities.prepare_population_reduction(p_entities.population.total - loss)
			p_entities.population.total -= loss
			p_settlement_system.apply_population_loss(zone_id, loss)
			p_entities.enforce_population_invariants()
			total_loss += loss
		regional_loss_accumulators[accumulator_key] = accumulator
		population_at_risk += zone_population
		rate_weighted_population += effective_rate * float(zone_population)
		zone_reports.append({
			"zone_id": zone_id,
			"population_before": zone_population,
			"protected_people": protected_people,
			"exposed_people": exposed_people,
			"loss": loss,
			"temperature": zone.temperature,
			"radiation": zone.radiation,
			"temperature_loss_rate": rates["temperature_rate"],
			"radiation_loss_rate": rates["radiation_rate"],
			"effective_loss_rate": effective_rate,
			"operating_shelter_capacity": int(shelter.get("capacity", 0)),
		})
	if population_at_risk > 0:
		var average_rate: float = rate_weighted_population / float(population_at_risk)
		p_entities.population_health = maxf(
			0.0,
			p_entities.population_health - average_rate * p_delta_days * 0.35
		)
	latest_exposure = {
		"population_before": total_population_before,
		"population_at_risk": population_at_risk,
		"total_loss": total_loss,
		"zone_reports": zone_reports,
	}
	return latest_exposure.duplicate(true)


func end_step(p_game_day: float, p_delta_days: float, p_exposure_report: Dictionary,
		p_stored_losses: int, p_destroyed_buildings: int) -> Dictionary:
	if active_hazard.is_empty():
		return {}
	active_hazard["casualties"] = int(active_hazard.get("casualties", 0)) + int(p_exposure_report.get("total_loss", 0))
	active_hazard["stored_casualties"] = int(active_hazard.get("stored_casualties", 0)) + maxi(0, p_stored_losses)
	active_hazard["casualties"] = int(active_hazard["casualties"]) + maxi(0, p_stored_losses)
	active_hazard["destroyed_buildings"] = int(active_hazard.get("destroyed_buildings", 0)) + maxi(0, p_destroyed_buildings)
	if float(latest_assessment.get("trigger_score", 0.0)) <= 0.0:
		active_hazard["quiet_days"] = float(active_hazard.get("quiet_days", 0.0)) + p_delta_days
	else:
		active_hazard["quiet_days"] = 0.0
	if (
		float(active_hazard.get("elapsed_days", 0.0)) >= MINIMUM_HAZARD_DAYS
		and float(active_hazard.get("quiet_days", 0.0)) >= QUIET_DAYS_TO_RESOLVE
	):
		return _resolve_active_hazard(p_game_day)
	return {}


func force_resolve(p_game_day: float, p_reason: String) -> Dictionary:
	if active_hazard.is_empty():
		return {}
	active_hazard["forced_resolution_reason"] = p_reason
	return _resolve_active_hazard(p_game_day)


func get_public_state(p_entities = null, p_settlement_system = null) -> Dictionary:
	var response_view: Dictionary = {}
	if p_entities != null and p_settlement_system != null:
		response_view = get_response_plan_view(p_entities, p_settlement_system)
	return {
		"active_hazard": active_hazard.duplicate(true),
		"latest_assessment": latest_assessment.duplicate(true),
		"latest_exposure": latest_exposure.duplicate(true),
		"response_plan": response_view,
		"latest_completed_report": (
			(completed_reports[-1] as Dictionary).duplicate(true)
			if not completed_reports.is_empty()
			else {}
		),
	}


func get_state() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"active_hazard": active_hazard.duplicate(true),
		"response_plan": response_plan.duplicate(true),
		"completed_reports": completed_reports.duplicate(true),
		"regional_loss_accumulators": regional_loss_accumulators.duplicate(),
		"latest_assessment": latest_assessment.duplicate(true),
		"latest_exposure": latest_exposure.duplicate(true),
		"next_hazard_number": _next_hazard_number,
		"next_plan_number": _next_plan_number,
	}


func load_state(p_state: Dictionary) -> bool:
	if (
		int(p_state.get("state_version", -1)) != STATE_VERSION
		or not p_state.get("active_hazard", null) is Dictionary
		or not p_state.get("response_plan", null) is Dictionary
		or not p_state.get("completed_reports", null) is Array
		or not p_state.get("regional_loss_accumulators", null) is Dictionary
	):
		return false
	active_hazard = (p_state["active_hazard"] as Dictionary).duplicate(true)
	response_plan = (p_state["response_plan"] as Dictionary).duplicate(true)
	completed_reports = (p_state["completed_reports"] as Array).duplicate(true)
	regional_loss_accumulators = (p_state["regional_loss_accumulators"] as Dictionary).duplicate()
	latest_assessment = (p_state.get("latest_assessment", {}) as Dictionary).duplicate(true)
	latest_exposure = (p_state.get("latest_exposure", {}) as Dictionary).duplicate(true)
	_next_hazard_number = maxi(1, int(p_state.get("next_hazard_number", 1)))
	_next_plan_number = maxi(1, int(p_state.get("next_plan_number", 1)))
	return true


func _build_current_allocations(p_priority: String, p_entities, p_settlement_system) -> Dictionary:
	var fraction: float = (
		float(RESPONSE_PROFILES[p_priority]["people_capacity_fraction"])
		if RESPONSE_PROFILES.has(p_priority)
		else DEFAULT_UNPLANNED_SHELTER_FRACTION
	)
	var allocations: Dictionary = {}
	for zone_key in p_settlement_system.region_population.keys():
		var zone_id: int = int(zone_key)
		var population: int = p_settlement_system.get_population(zone_id)
		if zone_id < 0 or population <= 0:
			continue
		var shelter: Dictionary = p_entities.get_zone_shelter_status(zone_id)
		var capacity: int = maxi(0, int(shelter.get("capacity", 0)))
		allocations[zone_id] = {
			"zone_id": zone_id,
			"population": population,
			"operating_shelter_capacity": capacity,
			"planned_protected_people": mini(population, int(floor(float(capacity) * fraction))),
			"environment_protection": float(shelter.get("environment_protection", 0.0)),
			"radiation_protection": maxf(
				float(shelter.get("shelter_radiation_protection", 0.0)),
				float(shelter.get("area_radiation_protection", 0.0))
			),
		}
	return allocations


func _assess_populated_zones(p_zone_manager, p_settlement_system) -> Dictionary:
	var affected_zone_ids: Array[int] = []
	var trigger_score: float = 0.0
	var maximum_loss_rate: float = 0.0
	var exposed_population: int = 0
	var dominant_cause: String = ""
	for zone_key in p_settlement_system.region_population.keys():
		var zone_id: int = int(zone_key)
		var population: int = p_settlement_system.get_population(zone_id)
		if zone_id < 0 or population <= 0:
			continue
		var zone = p_zone_manager.get_zone(zone_id)
		if zone == null:
			continue
		var rates: Dictionary = _environment_loss_rates(zone.temperature, zone.radiation)
		var loss_rate: float = float(rates["temperature_rate"]) + float(rates["radiation_rate"])
		maximum_loss_rate = maxf(maximum_loss_rate, loss_rate)
		var zone_trigger: float = 0.0
		var zone_cause: String = ""
		if zone.temperature < -45.0:
			zone_trigger = maxf(zone_trigger, (-45.0 - zone.temperature) / 35.0)
			zone_cause = "严寒"
		elif zone.temperature > 75.0:
			zone_trigger = maxf(zone_trigger, (zone.temperature - 75.0) / 25.0)
			zone_cause = "高温"
		if zone.radiation > 3.0:
			var radiation_trigger: float = (zone.radiation - 3.0) / 2.0
			if radiation_trigger > zone_trigger:
				zone_cause = "高辐射"
			zone_trigger = maxf(zone_trigger, radiation_trigger)
		if zone_trigger > 0.0:
			affected_zone_ids.append(zone_id)
			exposed_population += population
			if zone_trigger > trigger_score:
				trigger_score = zone_trigger
				dominant_cause = zone_cause
	return {
		"trigger_score": trigger_score,
		"maximum_loss_rate": maximum_loss_rate,
		"affected_zone_ids": affected_zone_ids,
		"exposed_population": exposed_population,
		"dominant_cause": dominant_cause,
	}


func _environment_loss_rates(p_temperature: float, p_radiation: float) -> Dictionary:
	var temperature_rate := 0.0
	if p_temperature < -80.0:
		temperature_rate = 0.1 + minf(0.18, (-80.0 - p_temperature) / 400.0)
	elif p_temperature < -10.0:
		temperature_rate = lerpf(0.0, 0.02, (-10.0 - p_temperature) / 70.0)
	elif p_temperature > 100.0:
		temperature_rate = 0.1 + minf(0.18, (p_temperature - 100.0) / 300.0)
	elif p_temperature > 60.0:
		temperature_rate = lerpf(0.0, 0.02, (p_temperature - 60.0) / 40.0)
	var radiation_rate := 0.0
	if p_radiation > 5.0:
		radiation_rate = 0.05 + minf(0.2, (p_radiation - 5.0) / 50.0)
	elif p_radiation > 2.0:
		radiation_rate = lerpf(0.0, 0.01, (p_radiation - 2.0) / 3.0)
	return {
		"temperature_rate": maxf(0.0, temperature_rate),
		"radiation_rate": maxf(0.0, radiation_rate),
	}


func _resolve_active_hazard(p_game_day: float) -> Dictionary:
	var report := active_hazard.duplicate(true)
	report["resolved_game_day"] = p_game_day
	var starting_population := maxi(1, int(report.get("starting_population", 1)))
	var casualty_fraction := clampf(float(report.get("casualties", 0)) / float(starting_population), 0.0, 1.0)
	var physical_shock := clampf(
		float(report.get("peak_trigger_score", 0.0)) * 0.08
		+ float(report.get("destroyed_buildings", 0)) * 0.01,
		0.0, 0.75
	)
	var knowledge_protection := (
		float(response_plan.get("knowledge_protection", 0.0))
		if str(response_plan.get("plan_id", "")) == str(report.get("response_plan_id", ""))
		else 0.0
	)
	report["casualty_fraction"] = casualty_fraction
	report["knowledge_loss_vector"] = {
		"source_id": str(report.get("source_id", "")),
		"living_loss": casualty_fraction,
		"record_loss": physical_shock * (1.0 - knowledge_protection),
		"practice_loss": physical_shock * (1.0 - knowledge_protection * 0.65),
	}
	report["response_priority_name"] = (
		str(RESPONSE_PROFILES[str(report.get("response_priority", ""))]["name"])
		if RESPONSE_PROFILES.has(str(report.get("response_priority", "")))
		else "未确认预案"
	)
	completed_reports.append(report.duplicate(true))
	while completed_reports.size() > MAX_COMPLETED_REPORTS:
		completed_reports.pop_front()
	if not response_plan.is_empty():
		response_plan["locked_by_hazard_id"] = ""
	active_hazard.clear()
	return report
