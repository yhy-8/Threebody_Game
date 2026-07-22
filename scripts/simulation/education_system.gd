class_name EducationSystem
extends RefCounted
## Teaching plans reserve real people and improve transmission; no separate population pool.

const STATE_VERSION := 1

var knowledge_system
var plans: Dictionary = {}
var completed_plan_ids: Array[String] = []


func _init(p_knowledge_system) -> void:
	knowledge_system = p_knowledge_system


func validate_plan(p_plan: Dictionary, p_entities) -> Dictionary:
	var plan_id := str(p_plan.get("plan_id", ""))
	var node_id := str(p_plan.get("node_id", p_plan.get("curriculum_id", "")))
	if plan_id.is_empty() or node_id.is_empty():
		return {"success": false, "message": "教学计划缺少稳定 ID 或课程"}
	if knowledge_system.get_node_state(node_id) not in [knowledge_system.KnowledgeState.MASTERED, knowledge_system.KnowledgeState.APPLIED]:
		return {"success": false, "message": "没有掌握该课程的教师"}
	var teachers := maxi(0, int(p_plan.get("teacher_count", 0)))
	var students := maxi(0, int(p_plan.get("student_count", 0)))
	if teachers <= 0 or students <= 0:
		return {"success": false, "message": "教师和学习者都必须来自实际人口"}
	if p_entities.get_idle_population() < teachers + students:
		return {"success": false, "message": "教学需要 %d 名闲置人口" % (teachers + students)}
	var hours := float(p_plan.get("hours_per_day", 4.0))
	if hours <= 0.0 or hours > 16.0:
		return {"success": false, "message": "每日教学时长必须在 0~16 小时"}
	return {"success": true, "message": ""}


func start_plan(p_plan: Dictionary, p_entities) -> Dictionary:
	var validation := validate_plan(p_plan, p_entities)
	if not validation.get("success", false):
		return validation
	var plan_id := str(p_plan["plan_id"])
	if plans.has(plan_id):
		return {"success": false, "message": "教学计划 ID 已存在"}
	var stored := p_plan.duplicate(true)
	stored["node_id"] = str(p_plan.get("node_id", p_plan.get("curriculum_id", "")))
	stored["paused"] = false
	stored["pause_reason"] = ""
	stored["progress_days"] = 0.0
	plans[plan_id] = stored
	return {"success": true, "message": "教学计划已开始，教师与学习者会占用劳动力"}


func pause_plan(p_plan_id: String) -> bool:
	if not plans.has(p_plan_id):
		return false
	plans[p_plan_id]["paused"] = true
	return true


func cancel_plan(p_plan_id: String) -> bool:
	if not plans.has(p_plan_id):
		return false
	plans.erase(p_plan_id)
	return true


func preview_plan(p_plan: Dictionary) -> Dictionary:
	var teachers := maxi(0, int(p_plan.get("teacher_count", 0)))
	var students := maxi(0, int(p_plan.get("student_count", 0)))
	var hours := clampf(float(p_plan.get("hours_per_day", 4.0)), 0.0, 16.0)
	var emergency := bool(p_plan.get("emergency_course", false))
	return {
		"reserved_workers": teachers + students,
		"coverage_people": students,
		"expected_living_gain_per_day": teachers * hours / maxf(1.0, float(students)) * (0.0008 if not emergency else 0.0012),
		"depth_limit": 0.55 if emergency else 1.0,
		"production_hours_lost": (teachers + students) * hours,
	}


func update_day(p_delta_days: float, _p_context: Dictionary) -> Array:
	var results: Array = []
	for plan_id in plans:
		var plan: Dictionary = plans[plan_id]
		if bool(plan.get("paused", false)):
			continue
		var preview := preview_plan(plan)
		var node_id := str(plan.get("node_id", ""))
		var runtime: Dictionary = knowledge_system.runtime_nodes.get(node_id, {})
		var depth_limit := float(preview.get("depth_limit", 1.0))
		var remaining := maxf(0.0, depth_limit - float(runtime.get("living_transmission", 0.0)))
		var living_gain := minf(remaining, float(preview.get("expected_living_gain_per_day", 0.0)) * p_delta_days)
		var practice_gain := living_gain * (0.5 if not plan.get("practice_building_ids", []).is_empty() else 0.1)
		var result := {"plan_id": plan_id, "node_id": node_id, "living_gain": living_gain, "practice_gain": practice_gain}
		knowledge_system.apply_teaching_result(result)
		plan["progress_days"] = float(plan.get("progress_days", 0.0)) + p_delta_days
		results.append(result)
	return results


func get_reserved_workers() -> int:
	var total := 0
	for plan_value in plans.values():
		var plan: Dictionary = plan_value
		if not bool(plan.get("paused", false)):
			total += maxi(0, int(plan.get("teacher_count", 0))) + maxi(0, int(plan.get("student_count", 0)))
	return total


func get_state() -> Dictionary:
	return {"state_version": STATE_VERSION, "plans": plans.duplicate(true), "completed_plan_ids": completed_plan_ids.duplicate()}


func load_state(p_data: Dictionary) -> bool:
	if not p_data.get("plans", {}) is Dictionary:
		return false
	plans = (p_data.get("plans", {}) as Dictionary).duplicate(true)
	completed_plan_ids.assign(p_data.get("completed_plan_ids", []))
	return true
