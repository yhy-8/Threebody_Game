class_name EducationSystem
extends RefCounted
## Teaching plans reserve real people and improve transmission; no separate population pool.

const STATE_VERSION := 1
const WORKDAY_HOURS := 8.0
const METHOD_DEFINITIONS: Dictionary = {
	"oral": {
		"name": "集体讲述与复述",
		"description": "低材料需求，适合概念与生存经验；深度和班级规模有限。",
		"required_capabilities": ["oral_teaching"],
		"class_size": 4,
		"living_factor": 0.9,
		"practice_factor": 0.05,
		"depth_limit": 0.7,
		"suitable_living_weight": 0.25,
	},
	"apprenticeship": {
		"name": "师徒示范与练习",
		"description": "覆盖人数少，但适合工具、工艺和现场判断等隐性知识。",
		"required_capabilities": ["hand_tools"],
		"class_size": 2,
		"living_factor": 0.75,
		"practice_factor": 0.8,
		"depth_limit": 1.0,
		"suitable_practice_weight": 0.35,
	},
	"record_assisted": {
		"name": "记录辅助传习",
		"description": "依靠可复查的符号记录扩大覆盖，不能替代工艺示范。",
		"required_capabilities": ["symbolic_recording"],
		"class_size": 7,
		"living_factor": 1.0,
		"practice_factor": 0.12,
		"depth_limit": 0.9,
		"suitable_record_weight": 0.2,
	},
	"organized": {
		"name": "固定课程",
		"description": "以固定时间、课程和教学场所扩大稳定覆盖。",
		"required_capabilities": ["organized_education"],
		"class_size": 10,
		"living_factor": 1.15,
		"practice_factor": 0.18,
		"depth_limit": 1.0,
	},
	"professional": {
		"name": "专业院校训练",
		"description": "小班深度训练，要求实际运行的知识院设施。",
		"required_capabilities": ["professional_education"],
		"required_building_types": ["academy"],
		"class_size": 6,
		"living_factor": 1.3,
		"practice_factor": 0.35,
		"depth_limit": 1.0,
	},
}
const INTENSITY_DEFINITIONS: Array[Dictionary] = [
	{
		"id": "maintenance", "name": "维持性传承", "population_share": 0.03,
		"hours_per_day": 2.0, "learning_factor": 0.8, "depth_limit": 1.0,
		"emergency": false, "description": "占用较少人口，降低日常生产冲击。",
	},
	{
		"id": "routine", "name": "常规培养", "population_share": 0.08,
		"hours_per_day": 4.0, "learning_factor": 1.0, "depth_limit": 1.0,
		"emergency": false, "description": "在覆盖速度与劳动占用之间取中值。",
	},
	{
		"id": "intensive", "name": "重点培养", "population_share": 0.15,
		"hours_per_day": 6.0, "learning_factor": 1.1, "depth_limit": 1.0,
		"emergency": false, "description": "快速扩大掌握群体，显著挤占劳动岗位。",
	},
	{
		"id": "emergency", "name": "危机抢救教学", "population_share": 0.20,
		"hours_per_day": 8.0, "learning_factor": 0.85, "depth_limit": 0.55,
		"emergency": true, "description": "短期覆盖最大，但疲劳和压缩课程限制掌握深度。",
	},
]

var knowledge_system
var plans: Dictionary = {}
var completed_plan_ids: Array[String] = []


func _init(p_knowledge_system) -> void:
	knowledge_system = p_knowledge_system


func get_teachable_node_views() -> Array:
	var result: Array = []
	for view_value in knowledge_system.get_visible_nodes():
		var view: Dictionary = view_value
		if not bool(view.get("teachable", true)):
			continue
		if int(view.get("state", 0)) not in [knowledge_system.KnowledgeState.MASTERED, knowledge_system.KnowledgeState.APPLIED]:
			continue
		result.append(view)
	return result


func get_available_methods(p_node_id: String, p_entities) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for method_id in METHOD_DEFINITIONS:
		var definition: Dictionary = METHOD_DEFINITIONS[method_id]
		if not _method_suits_node(method_id, p_node_id):
			continue
		if not _requirements_available(definition, p_entities):
			continue
		var view := definition.duplicate(true)
		view["id"] = method_id
		result.append(view)
	return result


func get_intensities() -> Array[Dictionary]:
	return INTENSITY_DEFINITIONS.duplicate(true)


func derive_plan(p_node_id: String, p_method_id: String, p_intensity_id: String, p_entities) -> Dictionary:
	if p_entities == null or not _is_teachable_node(p_node_id):
		return {}
	if knowledge_system.get_node_state(p_node_id) not in [knowledge_system.KnowledgeState.MASTERED, knowledge_system.KnowledgeState.APPLIED]:
		return {}
	if not METHOD_DEFINITIONS.has(p_method_id):
		return {}
	var method: Dictionary = METHOD_DEFINITIONS[p_method_id]
	if not _method_suits_node(p_method_id, p_node_id) or not _requirements_available(method, p_entities):
		return {}
	var intensity := _get_intensity(p_intensity_id)
	if intensity.is_empty():
		return {}
	var idle: int = p_entities.get_idle_population()
	if idle < 2:
		return {}
	var students := maxi(1, int(floor(p_entities.population.total * float(intensity["population_share"]))))
	var class_size := maxi(1, int(method["class_size"]))
	var teachers := maxi(1, int(ceil(float(students) / float(class_size))))
	while students > 0 and students + teachers > idle:
		students -= 1
		teachers = maxi(1, int(ceil(float(students) / float(class_size))))
	if students <= 0 or students + teachers > idle:
		return {}
	var facility_ids: Array = []
	for building_type in method.get("required_building_types", []):
		var matching_ids := _get_operating_building_ids(str(building_type), p_entities)
		if matching_ids.is_empty():
			return {}
		facility_ids.append(matching_ids[0])
	return {
		"plan_id": _next_plan_id(p_node_id),
		"node_id": p_node_id,
		"curriculum_id": p_node_id,
		"method_id": p_method_id,
		"intensity_id": p_intensity_id,
		"teacher_count": teachers,
		"student_count": students,
		"hours_per_day": float(intensity["hours_per_day"]),
		"material_allocation": {},
		"facility_ids": facility_ids,
		"practice_building_ids": [],
		"emergency_course": bool(intensity["emergency"]),
	}


func start_strategy(p_node_id: String, p_method_id: String, p_intensity_id: String, p_entities) -> Dictionary:
	var plan := derive_plan(p_node_id, p_method_id, p_intensity_id, p_entities)
	if plan.is_empty():
		return {"success": false, "message": "当前人口、能力或设施不足，无法形成该教学计划"}
	return start_plan(plan, p_entities)


func validate_plan(p_plan: Dictionary, p_entities) -> Dictionary:
	var plan_id := str(p_plan.get("plan_id", ""))
	var node_id := str(p_plan.get("node_id", p_plan.get("curriculum_id", "")))
	if plan_id.is_empty() or node_id.is_empty():
		return {"success": false, "message": "教学计划缺少稳定 ID 或课程"}
	if not _is_teachable_node(node_id):
		return {"success": false, "message": "教学制度本身不是课程目标"}
	if knowledge_system.get_node_state(node_id) not in [knowledge_system.KnowledgeState.MASTERED, knowledge_system.KnowledgeState.APPLIED]:
		return {"success": false, "message": "没有掌握该课程的教师"}
	var method_id := str(p_plan.get("method_id", ""))
	var intensity_id := str(p_plan.get("intensity_id", ""))
	if not METHOD_DEFINITIONS.has(method_id):
		return {"success": false, "message": "教学组织方式无效"}
	var method: Dictionary = METHOD_DEFINITIONS[method_id]
	if not _method_suits_node(method_id, node_id):
		return {"success": false, "message": "该组织方式不适合课程的传承结构"}
	if not _requirements_available(method, p_entities):
		return {"success": false, "message": "缺少教学方式所需能力或运行设施"}
	var intensity := _get_intensity(intensity_id)
	if intensity.is_empty():
		return {"success": false, "message": "教学投入级别无效"}
	var teachers := maxi(0, int(p_plan.get("teacher_count", 0)))
	var students := maxi(0, int(p_plan.get("student_count", 0)))
	if teachers <= 0 or students <= 0:
		return {"success": false, "message": "教师和学习者都必须来自实际人口"}
	if students > teachers * int(method["class_size"]):
		return {"success": false, "message": "学习者人数超过该组织方式允许的师生比"}
	if p_entities.get_idle_population() < teachers + students:
		return {"success": false, "message": "教学需要 %d 名闲置人口" % (teachers + students)}
	var hours := float(p_plan.get("hours_per_day", 4.0))
	if not is_equal_approx(hours, float(intensity["hours_per_day"])):
		return {"success": false, "message": "每日课时必须由投入级别推导"}
	if bool(p_plan.get("emergency_course", false)) != bool(intensity["emergency"]):
		return {"success": false, "message": "危机课程标记与投入级别不一致"}
	for required_type in method.get("required_building_types", []):
		var operating_ids := _get_operating_building_ids(str(required_type), p_entities)
		var has_required_facility := false
		for facility_id in p_plan.get("facility_ids", []):
			if int(facility_id) in operating_ids:
				has_required_facility = true
				break
		if not has_required_facility:
			return {"success": false, "message": "计划没有绑定实际运行的教学设施"}
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
	var hours := clampf(float(p_plan.get("hours_per_day", 4.0)), 0.0, WORKDAY_HOURS)
	var method: Dictionary = METHOD_DEFINITIONS.get(str(p_plan.get("method_id", "")), {})
	var intensity := _get_intensity(str(p_plan.get("intensity_id", "")))
	var living_factor := float(method.get("living_factor", 0.0)) * float(intensity.get("learning_factor", 0.0))
	var depth_limit := minf(float(method.get("depth_limit", 0.0)), float(intensity.get("depth_limit", 0.0)))
	return {
		"reserved_workers": teachers + students,
		"coverage_people": students,
		"scheduled_instruction_hours": (teachers + students) * hours,
		"expected_living_gain_per_day": teachers * hours / maxf(1.0, float(students)) * 0.0008 * living_factor,
		"practice_factor": float(method.get("practice_factor", 0.0)),
		"depth_limit": depth_limit,
		"production_hours_lost": (teachers + students) * WORKDAY_HOURS,
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
		var practice_gain := living_gain * float(preview.get("practice_factor", 0.0))
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
	if int(p_data.get("state_version", -1)) != STATE_VERSION or not p_data.get("plans", {}) is Dictionary:
		return false
	plans = (p_data.get("plans", {}) as Dictionary).duplicate(true)
	completed_plan_ids.assign(p_data.get("completed_plan_ids", []))
	return true


func _is_teachable_node(p_node_id: String) -> bool:
	if not knowledge_system.graph.nodes.has(p_node_id):
		return false
	return bool(knowledge_system.graph.nodes[p_node_id].get("teachable", true))


func _method_suits_node(p_method_id: String, p_node_id: String) -> bool:
	if not knowledge_system.graph.nodes.has(p_node_id):
		return false
	var profile: Dictionary = knowledge_system.graph.nodes[p_node_id].get("inheritance_profile", {})
	var definition: Dictionary = METHOD_DEFINITIONS[p_method_id]
	if definition.has("suitable_living_weight") and float(profile.get("living_weight", 0.0)) < float(definition["suitable_living_weight"]):
		return false
	if definition.has("suitable_record_weight") and float(profile.get("record_weight", 0.0)) < float(definition["suitable_record_weight"]):
		return false
	if definition.has("suitable_practice_weight") and float(profile.get("practice_weight", 0.0)) < float(definition["suitable_practice_weight"]):
		return false
	return true


func _requirements_available(p_definition: Dictionary, p_entities) -> bool:
	for capability in p_definition.get("required_capabilities", []):
		if not knowledge_system.has_capability(str(capability)):
			return false
	for building_type in p_definition.get("required_building_types", []):
		if _get_operating_building_ids(str(building_type), p_entities).is_empty():
			return false
	return true


func _get_operating_building_ids(p_building_type: String, p_entities) -> Array[int]:
	var result: Array[int] = []
	if p_entities == null:
		return result
	for building in p_entities.buildings:
		if (
			building.building_type == p_building_type
			and building.active
			and not building.destroyed
			and not building.under_construction
		):
			result.append(building.id)
	return result


func _get_intensity(p_intensity_id: String) -> Dictionary:
	for definition in INTENSITY_DEFINITIONS:
		if str(definition["id"]) == p_intensity_id:
			return definition
	return {}


func _next_plan_id(p_node_id: String) -> String:
	var sequence := plans.size() + completed_plan_ids.size() + 1
	var candidate := "plan:%s:%03d" % [p_node_id, sequence]
	while plans.has(candidate) or candidate in completed_plan_ids:
		sequence += 1
		candidate = "plan:%s:%03d" % [p_node_id, sequence]
	return candidate
