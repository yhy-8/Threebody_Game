class_name EngineeringProjectSystem
extends RefCounted
## Separate prototype, testing, and process-maturity projects after theory mastery.

signal project_started(node_id: String, project_id: String)
signal project_completed(node_id: String, project_id: String)

const STATE_VERSION := 1
const MAX_ACTIVE_SLOTS := 2

var knowledge_system
var projects: Dictionary = {}


func _init(p_knowledge_system) -> void:
	knowledge_system = p_knowledge_system


func start_project(p_node_id: String, p_project_id: String, p_entities) -> Dictionary:
	var key := "%s:%s" % [p_node_id, p_project_id]
	if projects.has(key):
		var existing: Dictionary = projects[key]
		if bool(existing.get("completed", false)):
			return {"success": false, "message": "工程项目已经完成"}
		existing["manual_paused"] = false
		return {"success": true, "message": "工程项目已继续"}
	if get_active_project_ids().size() >= MAX_ACTIVE_SLOTS:
		return {"success": false, "message": "工程槽已满"}
	if knowledge_system.get_node_state(p_node_id) != knowledge_system.KnowledgeState.MASTERED:
		return {"success": false, "message": "尚未掌握该项目所需理论"}
	var definition: Dictionary = knowledge_system.graph.get_definition(p_node_id)
	var project_definition: Dictionary = {}
	for value in definition.get("engineering_projects", []):
		if str(value.get("id", "")) == p_project_id:
			project_definition = value
			break
	if project_definition.is_empty():
		return {"success": false, "message": "工程项目不存在"}
	var workers := maxi(1, int(project_definition.get("workers", 1)))
	if p_entities.get_idle_population() < workers:
		return {"success": false, "message": "闲置人口不足（工程需要 %d 人）" % workers}
	var consumed := _consume_cost(project_definition.get("material_cost", {}), p_entities)
	if not consumed.get("success", false):
		return consumed
	projects[key] = {
		"node_id": p_node_id,
		"project_id": p_project_id,
		"workers": workers,
		"work_required": maxf(0.001, float(project_definition.get("work_required", 1.0))),
		"work_completed": 0.0,
		"prototype_count": 0,
		"test_cycles": 0,
		"process_maturity": 0.0,
		"capability_tags": (project_definition.get("capability_tags", []) as Array).duplicate(),
		"consumed_materials": consumed.get("consumed", {}).duplicate(),
		"manual_paused": false,
		"pause_reason": "",
		"completed": false,
	}
	project_started.emit(p_node_id, p_project_id)
	return {"success": true, "message": "工程项目「%s」已开始" % project_definition.get("name", p_project_id)}


func toggle_pause(p_node_id: String, p_project_id: String) -> Dictionary:
	var key := "%s:%s" % [p_node_id, p_project_id]
	if not projects.has(key) or bool(projects[key].get("completed", false)):
		return {"success": false, "message": "没有可暂停的工程项目"}
	projects[key]["manual_paused"] = not bool(projects[key].get("manual_paused", false))
	return {"success": true, "message": "工程已暂停" if projects[key]["manual_paused"] else "工程已继续"}


func update_day(p_delta_days: float, p_throughput: Dictionary, _p_entities) -> void:
	for key in projects.keys():
		var project: Dictionary = projects[key]
		if bool(project.get("completed", false)) or bool(project.get("manual_paused", false)):
			continue
		var worker_rate := int(project.get("workers", 0)) * 0.045
		var facility_rate := maxf(0.0, float(p_throughput.get("applied", 0.0)))
		project["work_completed"] = float(project.get("work_completed", 0.0)) + (worker_rate + facility_rate) * p_delta_days
		var progress := clampf(float(project["work_completed"]) / float(project["work_required"]), 0.0, 1.0)
		project["process_maturity"] = progress
		project["test_cycles"] = int(floor(progress * 5.0))
		project["prototype_count"] = 1 if progress >= 0.35 else 0
		knowledge_system.set_engineering_progress(str(project["node_id"]), str(project["project_id"]), progress)
		if progress >= 1.0:
			project["completed"] = true
			knowledge_system.mark_applied(str(project["node_id"]), str(project["project_id"]))
			project_completed.emit(str(project["node_id"]), str(project["project_id"]))


func get_active_project_ids() -> Array:
	var result: Array = []
	for key in projects:
		var project: Dictionary = projects[key]
		if not bool(project.get("completed", false)) and not bool(project.get("manual_paused", false)):
			result.append(key)
	return result


func get_reserved_workers() -> int:
	var total := 0
	for project_value in projects.values():
		var project: Dictionary = project_value
		if not bool(project.get("completed", false)) and not bool(project.get("manual_paused", false)):
			total += int(project.get("workers", 0))
	return total


func get_project(p_node_id: String, p_project_id: String) -> Dictionary:
	return (projects.get("%s:%s" % [p_node_id, p_project_id], {}) as Dictionary).duplicate(true)


func get_state() -> Dictionary:
	return {"state_version": STATE_VERSION, "projects": projects.duplicate(true)}


func load_state(p_data: Dictionary) -> bool:
	if not p_data.get("projects", {}) is Dictionary:
		return false
	projects = (p_data.get("projects", {}) as Dictionary).duplicate(true)
	return true


func _consume_cost(p_cost, p_entities) -> Dictionary:
	if not p_cost is Dictionary:
		return {"success": false, "message": "工程材料成本无效"}
	for resource_id in p_cost:
		if p_entities.get_resource(resource_id) < float(p_cost[resource_id]):
			return {"success": false, "message": "工程材料不足：%s" % resource_id}
	var consumed: Dictionary = {}
	for resource_id in p_cost:
		var amount := maxf(0.0, float(p_cost[resource_id]))
		if amount > 0.0 and p_entities.consume_resource(resource_id, amount):
			consumed[resource_id] = amount
	return {"success": true, "message": "", "consumed": consumed}
