class_name PreservationAllocator
extends RefCounted
## Multi-dimensional shelter allocation; capacity facts and forecasts remain separate.

const STATE_VERSION := 1

var plans: Dictionary = {}
var committed_plan_ids: Array[String] = []
var resolved_source_ids: Array[String] = []
var results: Dictionary = {}


func preview_plan(p_plan: Dictionary, p_shelters: Array, p_forecast_snapshot = null) -> Dictionary:
	var occupancy := _calculate_occupancy(p_plan)
	var capacity := _calculate_capacity(p_shelters)
	var bottlenecks: Array[String] = []
	for dimension in capacity:
		if float(occupancy.get(dimension, 0.0)) > float(capacity[dimension]) + 0.000001:
			bottlenecks.append(dimension)
	var result: Dictionary = {
		"plan_id": p_plan.get("plan_id", ""),
		"occupancy": occupancy,
		"capacity": capacity,
		"capacity_bottlenecks": bottlenecks,
		"included_people": (p_plan.get("people", []) as Array).duplicate(true),
		"included_records": (p_plan.get("records", []) as Array).duplicate(true),
		"included_artifacts": (p_plan.get("artifacts", []) as Array).duplicate(true),
		"unplaced_objects": (p_plan.get("unplaced_objects", []) as Array).duplicate(true),
		"forecast_available": p_forecast_snapshot is Dictionary and int(p_forecast_snapshot.get("level", 0)) > 0,
	}
	if p_forecast_snapshot is Dictionary:
		var known_fields: Array = p_forecast_snapshot.get("known_fields", [])
		for field in ["risk_trend", "time_window", "possible_zone_ids", "casualty_range", "knowledge_loss_ranges", "confidence"]:
			if field in known_fields and p_forecast_snapshot.has(field):
				result[field] = p_forecast_snapshot[field]
	return result


func validate_plan(p_plan: Dictionary, p_shelters: Array) -> Dictionary:
	var plan_id := str(p_plan.get("plan_id", ""))
	if plan_id.is_empty():
		return {"success": false, "message": "保存方案缺少稳定 ID"}
	var object_ids: Dictionary = {}
	for collection_name in ["people", "records", "artifacts"]:
		var collection = p_plan.get(collection_name, [])
		if not collection is Array:
			return {"success": false, "message": "%s 列表格式无效" % collection_name}
		for object_value in collection:
			if not object_value is Dictionary:
				return {"success": false, "message": "保存对象格式无效"}
			var object_id := str(object_value.get("id", ""))
			if object_id.is_empty() or object_ids.has(object_id):
				return {"success": false, "message": "保存对象 ID 缺失或重复：%s" % object_id}
			object_ids[object_id] = true
	var preview := preview_plan(p_plan, p_shelters, null)
	if not preview.get("capacity_bottlenecks", []).is_empty():
		return {
			"success": false,
			"message": "避难容量不足：%s" % ", ".join(preview["capacity_bottlenecks"]),
			"preview": preview,
		}
	return {"success": true, "message": "", "preview": preview}


func store_plan(p_plan: Dictionary) -> Dictionary:
	var plan_id := str(p_plan.get("plan_id", ""))
	if plan_id.is_empty():
		return {"success": false, "message": "保存方案缺少稳定 ID"}
	plans[plan_id] = p_plan.duplicate(true)
	return {"success": true, "message": "保存方案已记录"}


func commit_plan(p_plan_id: String) -> Dictionary:
	if not plans.has(p_plan_id):
		return {"success": false, "message": "保存方案不存在"}
	if p_plan_id not in committed_plan_ids:
		committed_plan_ids.append(p_plan_id)
	plans[p_plan_id]["confirmed"] = true
	return {"success": true, "message": "保存方案已确认；确认不会提前结算灾害"}


func resolve_plan(p_plan_id: String, p_hazard_outcome: Dictionary) -> Dictionary:
	if p_plan_id not in committed_plan_ids:
		return {"success": false, "message": "保存方案尚未确认"}
	var source_id := str(p_hazard_outcome.get("source_id", ""))
	if source_id.is_empty() or source_id in resolved_source_ids:
		return {"success": false, "message": "灾害结果来源缺失或已经结算"}
	var plan: Dictionary = plans[p_plan_id]
	var casualty_fraction := clampf(float(p_hazard_outcome.get("casualty_fraction", 0.0)), 0.0, 1.0)
	var record_loss_fraction := clampf(float(p_hazard_outcome.get("record_loss_fraction", 0.0)), 0.0, 1.0)
	var artifact_loss_fraction := clampf(float(p_hazard_outcome.get("artifact_loss_fraction", 0.0)), 0.0, 1.0)
	var included_people := 0
	var teacher_people := 0
	var learner_people := 0
	for person_value in plan.get("people", []):
		var person: Dictionary = person_value
		var count := maxi(0, int(person.get("count", 1)))
		included_people += count
		if person.get("role", "") in ["teacher", "expert"]:
			teacher_people += count
		elif person.get("role", "") in ["learner", "apprentice"]:
			learner_people += count
	var survivors := int(floor(included_people * (1.0 - casualty_fraction)))
	var result := {
		"success": true,
		"plan_id": p_plan_id,
		"source_id": source_id,
		"surviving_people": survivors,
		"actual_casualties": included_people - survivors,
		"surviving_teachers": int(floor(teacher_people * (1.0 - casualty_fraction))),
		"surviving_learners": int(floor(learner_people * (1.0 - casualty_fraction))),
		"surviving_record_fraction": 1.0 - record_loss_fraction,
		"surviving_artifact_fraction": 1.0 - artifact_loss_fraction,
		"occupancy": _calculate_occupancy(plan),
		"unplaced_objects": (plan.get("unplaced_objects", []) as Array).duplicate(true),
		"knowledge_loss_vector": {
			"source_id": source_id,
			"living_loss": casualty_fraction,
			"record_loss": record_loss_fraction,
			"practice_loss": artifact_loss_fraction,
		},
	}
	resolved_source_ids.append(source_id)
	results["%s:%s" % [p_plan_id, source_id]] = result.duplicate(true)
	return result


func get_state() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"plans": plans.duplicate(true),
		"committed_plan_ids": committed_plan_ids.duplicate(),
		"resolved_source_ids": resolved_source_ids.duplicate(),
		"results": results.duplicate(true),
	}


func load_state(p_data: Dictionary) -> bool:
	if not p_data.get("plans", {}) is Dictionary or not p_data.get("results", {}) is Dictionary:
		return false
	plans = (p_data.get("plans", {}) as Dictionary).duplicate(true)
	committed_plan_ids.assign(p_data.get("committed_plan_ids", []))
	resolved_source_ids.assign(p_data.get("resolved_source_ids", []))
	results = (p_data.get("results", {}) as Dictionary).duplicate(true)
	return true


func _calculate_occupancy(p_plan: Dictionary) -> Dictionary:
	var occupancy := {
		"berths": 0.0,
		"life_support_people": 0.0,
		"food_water_person_days": 0.0,
		"usable_volume_m3": 0.0,
		"dry_archive_volume_m3": 0.0,
		"heavy_storage_mass_kg": 0.0,
		"continuous_power_kw": 0.0,
	}
	for person_value in p_plan.get("people", []):
		var person: Dictionary = person_value
		var count := maxf(0.0, float(person.get("count", 1)))
		occupancy["berths"] += count
		occupancy["life_support_people"] += count
		occupancy["food_water_person_days"] += count * maxf(0.0, float(person.get("supply_days", 30.0)))
		occupancy["usable_volume_m3"] += count * maxf(0.0, float(person.get("volume_m3", 2.5)))
	for record_value in p_plan.get("records", []):
		var record: Dictionary = record_value
		var volume := maxf(0.0, float(record.get("dry_volume_m3", 0.0)))
		occupancy["dry_archive_volume_m3"] += volume
		occupancy["usable_volume_m3"] += volume
		occupancy["continuous_power_kw"] += maxf(0.0, float(record.get("power_kw", 0.0)))
	for artifact_value in p_plan.get("artifacts", []):
		var artifact: Dictionary = artifact_value
		occupancy["usable_volume_m3"] += maxf(0.0, float(artifact.get("volume_m3", 0.0)))
		occupancy["heavy_storage_mass_kg"] += maxf(0.0, float(artifact.get("mass_kg", 0.0)))
		occupancy["continuous_power_kw"] += maxf(0.0, float(artifact.get("power_kw", 0.0)))
	return occupancy


func _calculate_capacity(p_shelters: Array) -> Dictionary:
	var capacity := {
		"berths": 0.0,
		"life_support_people": 0.0,
		"food_water_person_days": 0.0,
		"usable_volume_m3": 0.0,
		"dry_archive_volume_m3": 0.0,
		"heavy_storage_mass_kg": 0.0,
		"continuous_power_kw": 0.0,
	}
	for shelter_value in p_shelters:
		if not shelter_value is Dictionary:
			continue
		var shelter: Dictionary = shelter_value
		for dimension in capacity:
			capacity[dimension] += maxf(0.0, float(shelter.get(dimension, 0.0)))
	return capacity
