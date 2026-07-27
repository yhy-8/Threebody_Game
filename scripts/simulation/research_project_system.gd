class_name ResearchProjectSystem
extends RefCounted
## Continuous research projects: staffing, facilities, work, and partial progress.

signal project_started(node_id: String)
signal project_completed(node_id: String)
signal project_paused(node_id: String, reason: String)

const STATE_VERSION := 2
const MAX_ACTIVE_SLOTS := 2

var knowledge_system
var projects: Dictionary = {}


func _init(p_knowledge_system) -> void:
	knowledge_system = p_knowledge_system


func start_project(p_node_id: String, p_allocation: Dictionary, p_entities) -> Dictionary:
	if projects.has(p_node_id) and not bool(projects[p_node_id].get("completed", false)):
		var project: Dictionary = projects[p_node_id]
		if bool(project.get("manual_paused", false)) and p_entities.get_idle_population() < int(project.get("workers", 0)):
			return {"success": false, "message": "闲置人口不足，无法恢复该研究项目"}
		project["manual_paused"] = false
		project["pause_reason"] = ""
		knowledge_system.begin_research(p_node_id)
		return {"success": true, "message": "继续研究该知识方向"}
	if get_unfinished_project_ids().size() >= MAX_ACTIVE_SLOTS:
		return {"success": false, "message": "研究槽已满"}
	var view: Dictionary = knowledge_system.get_node_view(p_node_id)
	if view.is_empty():
		return {"success": false, "message": "知识方向尚不可见"}
	var requirements: Dictionary = view.get("research_requirements", {})
	var default_workers := maxi(1, int(requirements.get("workers", 1)))
	var workers := maxi(1, int(p_allocation.get("workers", default_workers)))
	if p_entities.get_idle_population() < workers:
		return {"success": false, "message": "闲置人口不足（研究需要 %d 人）" % workers}
	var facility_check := _check_facilities(requirements.get("facility_types", []), p_entities)
	if not facility_check.get("success", false):
		return facility_check
	var consumed := _consume_cost(requirements.get("material_cost", {}), p_entities)
	if not consumed.get("success", false):
		return consumed
	var begin: Dictionary = knowledge_system.begin_research(p_node_id)
	if not begin.get("success", false):
		_refund_cost(consumed.get("consumed", {}), p_entities)
		return begin
	projects[p_node_id] = {
		"node_id": p_node_id,
		"workers": workers,
		"minimum_workers": default_workers,
		"maximum_workers": maxi(default_workers, default_workers * 3),
		"facility_types": (requirements.get("facility_types", []) as Array).duplicate(),
		"throughput_type": str(requirements.get("throughput_type", "basic")),
		"work_required": maxf(0.001, float(requirements.get("work_required", 1.0))),
		"work_completed": 0.0,
		"manual_paused": false,
		"pause_reason": "",
		"failed_attempts": 0,
		"accident_ids": [],
		"consumed_materials": consumed.get("consumed", {}).duplicate(),
		"completed": false,
	}
	project_started.emit(p_node_id)
	return {"success": true, "message": "已安排 %d 人研究「%s」" % [workers, view.get("display_name", p_node_id)]}


func toggle_pause(p_node_id: String, p_entities) -> Dictionary:
	if not projects.has(p_node_id) or bool(projects[p_node_id].get("completed", false)):
		return {"success": false, "message": "没有该研究项目"}
	var project: Dictionary = projects[p_node_id]
	if bool(project.get("manual_paused", false)) and p_entities.get_idle_population() < int(project.get("workers", 0)):
		return {"success": false, "message": "闲置人口不足，无法继续该研究项目"}
	project["manual_paused"] = not bool(project.get("manual_paused", false))
	if project["manual_paused"]:
		knowledge_system.pause_research(p_node_id)
		project_paused.emit(p_node_id, "玩家暂停")
		return {"success": true, "message": "研究已暂停，进度与证据保留"}
	project["pause_reason"] = ""
	knowledge_system.begin_research(p_node_id)
	return {"success": true, "message": "研究已继续"}


func set_workers(p_node_id: String, p_workers: int, p_entities) -> Dictionary:
	if not projects.has(p_node_id) or bool(projects[p_node_id].get("completed", false)):
		return {"success": false, "message": "没有可调整的研究项目"}
	var project: Dictionary = projects[p_node_id]
	var minimum_workers := maxi(1, int(project.get("minimum_workers", 1)))
	var maximum_workers := maxi(minimum_workers, int(project.get("maximum_workers", minimum_workers * 3)))
	var target := clampi(p_workers, minimum_workers, maximum_workers)
	var current := int(project.get("workers", minimum_workers))
	var additional := maxi(0, target - current)
	if additional > p_entities.get_idle_population():
		return {"success": false, "message": "闲置人口不足；最多还能增加 %d 人" % p_entities.get_idle_population()}
	project["workers"] = target
	return {"success": true, "message": "研究人员已调整为 %d 人" % target}


func update_day(p_delta_days: float, p_throughput: Dictionary, p_entities) -> void:
	for node_id in projects.keys():
		var project: Dictionary = projects[node_id]
		if bool(project.get("completed", false)) or bool(project.get("manual_paused", false)):
			continue
		var facility_check := _check_facilities(project.get("facility_types", []), p_entities)
		if not facility_check.get("success", false):
			var reason := str(facility_check.get("message", "设施不可用"))
			if project.get("pause_reason", "") != reason:
				project["pause_reason"] = reason
				project_paused.emit(node_id, reason)
			continue
		if (
			not str(project.get("pause_reason", "")).is_empty()
			and p_entities.get_idle_population() < int(project.get("workers", 0))
		):
			project["pause_reason"] = "设施已恢复，但闲置人口不足以重新组织研究"
			continue
		project["pause_reason"] = ""
		var throughput_type := str(project.get("throughput_type", "basic"))
		var institutional_rate := maxf(0.0, float(p_throughput.get(throughput_type, 0.0)))
		var worker_rate := int(project.get("workers", 0)) * 0.04
		project["work_completed"] = float(project.get("work_completed", 0.0)) + (institutional_rate + worker_rate) * p_delta_days
		var progress := clampf(float(project["work_completed"]) / float(project["work_required"]), 0.0, 1.0)
		knowledge_system.set_research_progress(node_id, progress)
		if progress >= 1.0:
			project["completed"] = true
			project["pause_reason"] = ""
			knowledge_system.mark_mastered(node_id)
			project_completed.emit(node_id)


func get_active_project_ids() -> Array:
	var result: Array = []
	for node_id in projects:
		var project: Dictionary = projects[node_id]
		if not bool(project.get("completed", false)) and not bool(project.get("manual_paused", false)):
			result.append(node_id)
	return result


func get_unfinished_project_ids() -> Array:
	var result: Array = []
	for node_id in projects:
		if not bool(projects[node_id].get("completed", false)):
			result.append(node_id)
	return result


func get_project_views(p_throughput: Dictionary) -> Array:
	var result: Array = []
	for node_id in projects:
		var project: Dictionary = projects[node_id]
		if bool(project.get("completed", false)):
			continue
		var view := project.duplicate(true)
		var node_view: Dictionary = knowledge_system.get_node_view(str(node_id))
		var throughput_type := str(project.get("throughput_type", "basic"))
		var rate := maxf(0.0, float(p_throughput.get(throughput_type, 0.0))) + int(project.get("workers", 0)) * 0.04
		var remaining := maxf(0.0, float(project.get("work_required", 0.0)) - float(project.get("work_completed", 0.0)))
		view["display_name"] = node_view.get("display_name", node_id)
		view["progress"] = clampf(float(project.get("work_completed", 0.0)) / maxf(0.001, float(project.get("work_required", 1.0))), 0.0, 1.0)
		view["daily_rate"] = rate
		view["eta_days"] = remaining / rate if rate > 0.0 and not bool(project.get("manual_paused", false)) and str(project.get("pause_reason", "")).is_empty() else -1.0
		result.append(view)
	result.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.get("node_id", "")) < str(b.get("node_id", "")))
	return result


func get_reserved_workers() -> int:
	var total := 0
	for node_id in projects:
		var project: Dictionary = projects[node_id]
		if not bool(project.get("completed", false)) and not bool(project.get("manual_paused", false)) and str(project.get("pause_reason", "")).is_empty():
			total += int(project.get("workers", 0))
	return total


func get_project(p_node_id: String) -> Dictionary:
	return (projects.get(p_node_id, {}) as Dictionary).duplicate(true)


func get_state() -> Dictionary:
	return {"state_version": STATE_VERSION, "projects": projects.duplicate(true)}


func load_state(p_data: Dictionary) -> bool:
	if int(p_data.get("state_version", -1)) != STATE_VERSION or not p_data.get("projects", {}) is Dictionary:
		return false
	projects = (p_data.get("projects", {}) as Dictionary).duplicate(true)
	return true


func _check_facilities(p_types: Array, p_entities) -> Dictionary:
	for facility_type in p_types:
		var operating := false
		for building in p_entities.get_buildings_by_type(str(facility_type)):
			if not building.under_construction and building.last_run_ratio > 0.0:
				operating = true
				break
		if not operating:
			return {"success": false, "message": "缺少可运行设施：%s" % facility_type}
	return {"success": true, "message": ""}


func _consume_cost(p_cost, p_entities) -> Dictionary:
	if not p_cost is Dictionary:
		return {"success": false, "message": "研究材料成本无效"}
	for resource_id in p_cost:
		if p_entities.get_resource(resource_id) < float(p_cost[resource_id]):
			return {"success": false, "message": "研究材料不足：%s" % resource_id}
	var consumed: Dictionary = {}
	for resource_id in p_cost:
		var amount := maxf(0.0, float(p_cost[resource_id]))
		if amount > 0.0 and p_entities.consume_resource(resource_id, amount):
			consumed[resource_id] = amount
	return {"success": true, "message": "", "consumed": consumed}


func _refund_cost(p_consumed: Dictionary, p_entities) -> void:
	for resource_id in p_consumed:
		p_entities.produce_resource(resource_id, float(p_consumed[resource_id]))
