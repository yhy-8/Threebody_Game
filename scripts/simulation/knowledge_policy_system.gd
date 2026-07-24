class_name KnowledgePolicySystem
extends RefCounted
## Separate policy tree describing how civilization teaches, records, and preserves.

const STATE_VERSION := 2
const POLICY_DEFINITIONS: Dictionary = {
	"designated_storytellers": {
		"name": "指定讲述者", "branch": "education", "prerequisite_policy_ids": [],
		"description": "建立轮值讲述、交叉复述和公开纠错职责。",
		"required_capabilities": ["oral_teaching"], "setup_days": 3.0, "setup_workers": 1,
		"operating_workers": 1, "effects": {"education_retention": 0.08},
	},
	"apprenticeship": {
		"name": "师徒制", "branch": "education", "prerequisite_policy_ids": ["designated_storytellers"],
		"description": "把工艺示范、跟做和独立操作纳入固定岗位关系。",
		"required_capabilities": ["hand_tools"], "setup_days": 5.0, "setup_workers": 2,
		"operating_workers": 1, "effects": {"practice_retention": 0.12},
	},
	"fixed_curriculum": {
		"name": "固定课程", "branch": "education", "prerequisite_policy_ids": ["designated_storytellers"],
		"description": "制定课程次序、复核标准和固定教学时段。",
		"required_capabilities": ["organized_education"], "setup_days": 20.0, "setup_workers": 3,
		"operating_workers": 2, "effects": {"education_retention": 0.18},
	},
	"scribal_records": {
		"name": "专职抄写与术语", "branch": "recording", "prerequisite_policy_ids": [],
		"description": "安排抄写、校对和术语维护岗位，减少记录漂移。",
		"required_capabilities": ["symbolic_recording"], "setup_days": 10.0, "setup_workers": 2,
		"operating_workers": 2, "effects": {"record_retention": 0.14},
	},
	"organized_archives": {
		"name": "公共档案目录", "branch": "recording", "prerequisite_policy_ids": ["scribal_records"],
		"description": "建立可检索目录、借阅追踪和定期完整性检查。",
		"required_capabilities": ["organized_archives"], "setup_days": 30.0, "setup_workers": 4,
		"operating_workers": 3, "effects": {"record_retention": 0.25},
	},
	"shelter_rosters": {
		"name": "避难名册", "branch": "preservation", "prerequisite_policy_ids": [],
		"description": "持续维护人员、岗位与避难容量清单。",
		"required_capabilities": ["survival_shelter"], "setup_days": 5.0, "setup_workers": 1,
		"operating_workers": 1, "effects": {"preservation_readiness": 0.12},
	},
	"archive_prepacking": {
		"name": "档案预打包", "branch": "preservation", "prerequisite_policy_ids": ["shelter_rosters"],
		"description": "提前整理档案批次、搬运次序和环境要求。",
		"required_capabilities": ["symbolic_recording"], "setup_days": 12.0, "setup_workers": 3,
		"operating_workers": 1, "effects": {"preservation_readiness": 0.18},
	},
	"knowledge_audit": {
		"name": "知识缺口审计", "branch": "recovery", "prerequisite_policy_ids": [],
		"description": "定期核对掌握者、记录、样机与实践岗位之间的断点。",
		"required_capabilities": ["symbolic_recording"], "setup_days": 10.0, "setup_workers": 2,
		"operating_workers": 1, "effects": {"recovery_rate": 0.15},
	},
}

var knowledge_system
var active_policy_ids: Array[String] = []
var active_programs: Array = []
var policy_history: Array = []


func _init(p_knowledge_system) -> void:
	knowledge_system = p_knowledge_system


func adopt_policy(p_policy_id: String, p_entities) -> Dictionary:
	if not POLICY_DEFINITIONS.has(p_policy_id):
		return {"success": false, "message": "知识政策不存在"}
	if p_policy_id in active_policy_ids:
		return {"success": false, "message": "知识政策已经采用"}
	if _find_program(p_policy_id) >= 0:
		return {"success": false, "message": "该制度正在筹建"}
	var definition: Dictionary = POLICY_DEFINITIONS[p_policy_id]
	for prerequisite_id in definition.get("prerequisite_policy_ids", []):
		if prerequisite_id not in active_policy_ids:
			return {"success": false, "message": "缺少前置制度：%s" % prerequisite_id}
	for capability in definition.get("required_capabilities", []):
		if not knowledge_system.has_capability(str(capability)):
			return {"success": false, "message": "文明尚不具备实施能力：%s" % capability}
	var setup_workers := maxi(0, int(definition.get("setup_workers", 0)))
	if p_entities == null or p_entities.get_idle_population() < setup_workers:
		return {"success": false, "message": "筹建需要 %d 名闲置组织人员" % setup_workers}
	active_programs.append({
		"policy_id": p_policy_id,
		"progress_days": 0.0,
		"required_days": maxf(0.01, float(definition.get("setup_days", 1.0))),
		"workers": setup_workers,
	})
	policy_history.append({"policy_id": p_policy_id, "action": "start_setup"})
	return {
		"success": true,
		"message": "开始筹建「%s」：%d 人，预计 %.0f 天" % [
			definition.get("name", p_policy_id), setup_workers, definition.get("setup_days", 1.0),
		],
	}


func update_day(p_delta_days: float) -> Array[String]:
	var completed: Array[String] = []
	for index in range(active_programs.size() - 1, -1, -1):
		var program: Dictionary = active_programs[index]
		program["progress_days"] = float(program.get("progress_days", 0.0)) + maxf(0.0, p_delta_days)
		if float(program["progress_days"]) + 0.000001 < float(program.get("required_days", 1.0)):
			continue
		var policy_id := str(program.get("policy_id", ""))
		if POLICY_DEFINITIONS.has(policy_id) and policy_id not in active_policy_ids:
			active_policy_ids.append(policy_id)
			policy_history.append({"policy_id": policy_id, "action": "activate"})
			completed.append(policy_id)
		active_programs.remove_at(index)
	return completed


func get_reserved_workers() -> int:
	var total := 0
	for program_value in active_programs:
		total += maxi(0, int((program_value as Dictionary).get("workers", 0)))
	for policy_id in active_policy_ids:
		total += maxi(0, int(POLICY_DEFINITIONS[policy_id].get("operating_workers", 0)))
	return total


func get_visible_policies() -> Array:
	var result: Array = []
	for policy_id in POLICY_DEFINITIONS:
		var definition: Dictionary = POLICY_DEFINITIONS[policy_id]
		var visible := true
		for capability in definition.get("required_capabilities", []):
			if not knowledge_system.has_capability(str(capability)):
				visible = false
				break
		if visible and policy_id not in active_policy_ids:
			for prerequisite_id in definition.get("prerequisite_policy_ids", []):
				if prerequisite_id not in active_policy_ids:
					visible = false
					break
		if visible:
			var view := definition.duplicate(true)
			view["id"] = policy_id
			view["active"] = policy_id in active_policy_ids
			var program_index := _find_program(policy_id)
			view["pending"] = program_index >= 0
			if program_index >= 0:
				var program: Dictionary = active_programs[program_index]
				view["progress_days"] = float(program.get("progress_days", 0.0))
				view["required_days"] = float(program.get("required_days", 1.0))
			result.append(view)
	return result


func get_retention_context() -> Dictionary:
	var education := 0.0
	var records := 0.0
	var practice := 0.0
	for policy_id in active_policy_ids:
		var effects: Dictionary = POLICY_DEFINITIONS[policy_id].get("effects", {})
		education += float(effects.get("education_retention", 0.0))
		records += float(effects.get("record_retention", 0.0))
		practice += float(effects.get("practice_retention", 0.0))
	return {
		"education_coverage": clampf(education, 0.0, 1.0),
		"record_retention": clampf(records, 0.0, 1.0),
		"practice_retention": clampf(practice, 0.0, 1.0),
	}


func get_state() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"active_policy_ids": active_policy_ids.duplicate(),
		"active_programs": active_programs.duplicate(true),
		"policy_history": policy_history.duplicate(true),
	}


func load_state(p_data: Dictionary) -> bool:
	if (
		int(p_data.get("state_version", -1)) != STATE_VERSION
		or not p_data.get("active_policy_ids", null) is Array
		or not p_data.get("active_programs", null) is Array
		or not p_data.get("policy_history", null) is Array
	):
		return false
	var loaded_policy_ids: Array[String] = []
	for policy_value in p_data.get("active_policy_ids", []):
		var policy_id := str(policy_value)
		if not POLICY_DEFINITIONS.has(policy_id) or policy_id in loaded_policy_ids:
			return false
		loaded_policy_ids.append(policy_id)
	var loaded_programs: Array = []
	var pending_policy_ids: Array[String] = []
	for program_value in p_data.get("active_programs", []):
		if not program_value is Dictionary:
			return false
		var program: Dictionary = program_value
		var policy_id := str(program.get("policy_id", ""))
		if (
			not POLICY_DEFINITIONS.has(policy_id)
			or policy_id in loaded_policy_ids
			or policy_id in pending_policy_ids
		):
			return false
		var definition: Dictionary = POLICY_DEFINITIONS[policy_id]
		var progress_days := float(program.get("progress_days", -1.0))
		var required_days := float(program.get("required_days", -1.0))
		if (
			progress_days < 0.0
			or required_days <= 0.0
			or progress_days >= required_days
			or not is_equal_approx(required_days, float(definition.get("setup_days", 1.0)))
			or int(program.get("workers", -1)) != int(definition.get("setup_workers", 0))
		):
			return false
		pending_policy_ids.append(policy_id)
		loaded_programs.append(program.duplicate(true))
	for history_value in p_data.get("policy_history", []):
		if not history_value is Dictionary:
			return false
		var history: Dictionary = history_value
		if not POLICY_DEFINITIONS.has(str(history.get("policy_id", ""))):
			return false
	active_policy_ids = loaded_policy_ids
	active_programs = loaded_programs
	policy_history = (p_data.get("policy_history", []) as Array).duplicate(true)
	return true


func _find_program(p_policy_id: String) -> int:
	for index in range(active_programs.size()):
		if str((active_programs[index] as Dictionary).get("policy_id", "")) == p_policy_id:
			return index
	return -1
