class_name KnowledgePolicySystem
extends RefCounted
## Separate policy tree describing how civilization teaches, records, and preserves.

const STATE_VERSION := 1
const POLICY_DEFINITIONS: Dictionary = {
	"designated_storytellers": {
		"name": "指定讲述者", "branch": "education", "prerequisite_policy_ids": [],
		"required_capabilities": ["oral_teaching"], "effects": {"education_retention": 0.08},
	},
	"apprenticeship": {
		"name": "师徒制", "branch": "education", "prerequisite_policy_ids": ["designated_storytellers"],
		"required_capabilities": ["hand_tools"], "effects": {"practice_retention": 0.12},
	},
	"fixed_curriculum": {
		"name": "固定课程", "branch": "education", "prerequisite_policy_ids": ["designated_storytellers"],
		"required_capabilities": ["organized_education"], "effects": {"education_retention": 0.18},
	},
	"scribal_records": {
		"name": "专职抄写与术语", "branch": "recording", "prerequisite_policy_ids": [],
		"required_capabilities": ["symbolic_recording"], "effects": {"record_retention": 0.14},
	},
	"organized_archives": {
		"name": "公共档案目录", "branch": "recording", "prerequisite_policy_ids": ["scribal_records"],
		"required_capabilities": ["organized_archives"], "effects": {"record_retention": 0.25},
	},
	"shelter_rosters": {
		"name": "避难名册", "branch": "preservation", "prerequisite_policy_ids": [],
		"required_capabilities": ["survival_shelter"], "effects": {"preservation_readiness": 0.12},
	},
	"archive_prepacking": {
		"name": "档案预打包", "branch": "preservation", "prerequisite_policy_ids": ["shelter_rosters"],
		"required_capabilities": ["symbolic_recording"], "effects": {"preservation_readiness": 0.18},
	},
	"knowledge_audit": {
		"name": "知识缺口审计", "branch": "recovery", "prerequisite_policy_ids": [],
		"required_capabilities": ["symbolic_recording"], "effects": {"recovery_rate": 0.15},
	},
}

var knowledge_system
var knowledge_priority: float = 50.0
var carrier_weights: Dictionary = {"teachers": 1.0, "learners": 1.0, "records": 1.0, "artifacts": 1.0}
var domain_weights: Dictionary = {}
var node_minimums: Dictionary = {}
var active_policy_ids: Array[String] = []
var active_programs: Array = []
var crisis_posture: String = "balanced"
var policy_history: Array = []


func _init(p_knowledge_system) -> void:
	knowledge_system = p_knowledge_system
	for domain in knowledge_system.graph.get_domains():
		domain_weights[domain] = 1.0


func adopt_policy(p_policy_id: String) -> Dictionary:
	if not POLICY_DEFINITIONS.has(p_policy_id):
		return {"success": false, "message": "知识政策不存在"}
	if p_policy_id in active_policy_ids:
		return {"success": false, "message": "知识政策已经采用"}
	var definition: Dictionary = POLICY_DEFINITIONS[p_policy_id]
	for prerequisite_id in definition.get("prerequisite_policy_ids", []):
		if prerequisite_id not in active_policy_ids:
			return {"success": false, "message": "缺少前置制度：%s" % prerequisite_id}
	for capability in definition.get("required_capabilities", []):
		if not knowledge_system.has_capability(str(capability)):
			return {"success": false, "message": "文明尚不具备实施能力：%s" % capability}
	active_policy_ids.append(p_policy_id)
	policy_history.append({"policy_id": p_policy_id, "action": "adopt"})
	return {"success": true, "message": "已采用「%s」" % definition.get("name", p_policy_id)}


func set_knowledge_priority(p_value: float) -> void:
	knowledge_priority = clampf(p_value, 0.0, 100.0)


func set_carrier_weight(p_carrier_id: String, p_value: float) -> bool:
	if not carrier_weights.has(p_carrier_id):
		return false
	carrier_weights[p_carrier_id] = clampf(p_value, 0.0, 5.0)
	return true


func set_domain_weight(p_domain_id: String, p_value: float) -> bool:
	if not domain_weights.has(p_domain_id):
		return false
	domain_weights[p_domain_id] = clampf(p_value, 0.0, 5.0)
	return true


func set_node_minimum(p_node_id: String, p_target: float) -> bool:
	if knowledge_system.get_node_state(p_node_id) == knowledge_system.KnowledgeState.HIDDEN:
		return false
	node_minimums[p_node_id] = clampf(p_target, 0.0, 1.0)
	return true


func set_crisis_posture(p_posture_id: String) -> bool:
	if p_posture_id not in ["life_first", "balanced", "knowledge_first", "custom"]:
		return false
	crisis_posture = p_posture_id
	return true


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
			result.append(view)
	return result


func get_retention_context() -> Dictionary:
	var education := knowledge_priority / 100.0 * 0.35
	var records := knowledge_priority / 100.0 * 0.25
	var practice := knowledge_priority / 100.0 * 0.2
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
		"knowledge_priority": knowledge_priority,
		"carrier_weights": carrier_weights.duplicate(),
		"domain_weights": domain_weights.duplicate(),
		"node_minimums": node_minimums.duplicate(),
		"active_policy_ids": active_policy_ids.duplicate(),
		"active_programs": active_programs.duplicate(true),
		"crisis_posture": crisis_posture,
		"policy_history": policy_history.duplicate(true),
	}


func load_state(p_data: Dictionary) -> bool:
	for key in ["carrier_weights", "domain_weights", "node_minimums"]:
		if p_data.has(key) and not p_data[key] is Dictionary:
			return false
	knowledge_priority = clampf(float(p_data.get("knowledge_priority", 50.0)), 0.0, 100.0)
	for key in carrier_weights:
		carrier_weights[key] = clampf(float(p_data.get("carrier_weights", {}).get(key, 1.0)), 0.0, 5.0)
	for key in domain_weights:
		domain_weights[key] = clampf(float(p_data.get("domain_weights", {}).get(key, 1.0)), 0.0, 5.0)
	node_minimums = (p_data.get("node_minimums", {}) as Dictionary).duplicate()
	active_policy_ids.clear()
	for policy_id in p_data.get("active_policy_ids", []):
		if POLICY_DEFINITIONS.has(policy_id):
			active_policy_ids.append(policy_id)
	active_programs = (p_data.get("active_programs", []) as Array).duplicate(true)
	crisis_posture = str(p_data.get("crisis_posture", "balanced"))
	if crisis_posture not in ["life_first", "balanced", "knowledge_first", "custom"]:
		crisis_posture = "balanced"
	policy_history = (p_data.get("policy_history", []) as Array).duplicate(true)
	return true
