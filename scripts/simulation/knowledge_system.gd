class_name KnowledgeSystem
extends RefCounted
## Single authority for knowledge visibility, lifecycle, capabilities, and loss.

signal knowledge_state_changed(node_id: String, old_state: int, new_state: int)
signal branch_revealed(parent_id: String, child_id: String)
signal evidence_changed(node_id: String, evidence_type: String, amount: float)
signal knowledge_degraded(node_id: String, missing_factors: Array)
signal capability_changed(capability_id: String, level: int)

const KnowledgeGraphScript = preload("res://scripts/simulation/knowledge_graph.gd")
const STATE_VERSION := 1
const DEFAULT_INSIGHT_THRESHOLD := 0.5
const MAINTENANCE_THRESHOLD := 0.15

enum KnowledgeState {
	HIDDEN,
	RUMOR,
	INSIGHT,
	RESEARCHABLE,
	RESEARCHING,
	MASTERED,
	APPLIED,
	DEGRADED,
}

const STATE_NAMES: Dictionary = {
	KnowledgeState.HIDDEN: "未知",
	KnowledgeState.RUMOR: "模糊方向",
	KnowledgeState.INSIGHT: "已理解问题",
	KnowledgeState.RESEARCHABLE: "可研究",
	KnowledgeState.RESEARCHING: "研究中",
	KnowledgeState.MASTERED: "理论掌握",
	KnowledgeState.APPLIED: "工程化",
	KnowledgeState.DEGRADED: "知识衰退",
}

var graph
var runtime_nodes: Dictionary = {}
var known_source_ids: Dictionary = {}
var capability_levels: Dictionary = {}


func _init(p_graph = null) -> void:
	graph = p_graph if p_graph != null else KnowledgeGraphScript.new()
	_initialize_empty_runtime()


func _initialize_empty_runtime() -> void:
	runtime_nodes.clear()
	known_source_ids.clear()
	for node_id in graph.nodes:
		runtime_nodes[node_id] = _default_runtime_state()
	_rebuild_capabilities()


func initialize_new_civilization() -> bool:
	if not graph.is_valid():
		return false
	_initialize_empty_runtime()
	for node_id in graph.nodes:
		var definition: Dictionary = graph.nodes[node_id]
		if bool(definition.get("initial_applied", false)):
			_set_peak_state(node_id, KnowledgeState.APPLIED, "origin:%s" % node_id)
	for node_id in graph.nodes:
		var definition: Dictionary = graph.nodes[node_id]
		var initial_clue := float(definition.get("initial_clue", 0.0))
		if initial_clue > 0.0:
			add_clue(node_id, "origin:rumor:%s" % node_id, initial_clue)
	_rebuild_capabilities()
	return true


func _default_runtime_state() -> Dictionary:
	return {
		"state": KnowledgeState.HIDDEN,
		"clue_strength": 0.0,
		"evidence": {},
		"research_progress": 0.0,
		"engineering_progress": {},
		"living_transmission": 0.0,
		"record_integrity": 0.0,
		"practice_level": 0.0,
		"known_source_ids": [],
		"previous_peak_state": KnowledgeState.HIDDEN,
		"degradation_factors": [],
	}


func add_clue(p_node_id: String, p_source_id: String, p_strength: float) -> bool:
	return apply_discovery(p_node_id, p_source_id, maxf(0.0, p_strength), {})


func add_evidence(p_node_id: String, p_type: String, p_amount: float, p_source_id: String) -> bool:
	if p_type.is_empty() or p_amount <= 0.0:
		return false
	return apply_discovery(p_node_id, p_source_id, 0.0, {p_type: p_amount})


func apply_discovery(p_node_id: String, p_source_id: String, p_clue_strength: float, p_evidence: Dictionary) -> bool:
	if not runtime_nodes.has(p_node_id) or p_source_id.is_empty() or known_source_ids.has(p_source_id):
		return false
	known_source_ids[p_source_id] = p_node_id
	var runtime: Dictionary = runtime_nodes[p_node_id]
	runtime["known_source_ids"].append(p_source_id)
	runtime["clue_strength"] = clampf(float(runtime.get("clue_strength", 0.0)) + maxf(0.0, p_clue_strength), 0.0, 1.0)
	var evidence: Dictionary = runtime.get("evidence", {})
	for evidence_type in p_evidence:
		var amount := maxf(0.0, float(p_evidence[evidence_type]))
		if amount <= 0.0:
			continue
		evidence[evidence_type] = float(evidence.get(evidence_type, 0.0)) + amount
		evidence_changed.emit(p_node_id, str(evidence_type), amount)
	runtime["evidence"] = evidence
	_evaluate_state(p_node_id)
	return true


func reveal_candidate(p_node_id: String, p_source_id: String, p_strength: float = 0.2) -> bool:
	return add_clue(p_node_id, p_source_id, p_strength)


func begin_research(p_node_id: String) -> Dictionary:
	if not runtime_nodes.has(p_node_id):
		return {"success": false, "message": "知识节点不存在"}
	var state := get_node_state(p_node_id)
	if state != KnowledgeState.RESEARCHABLE:
		return {"success": false, "message": "该方向尚未达到可研究状态"}
	_set_state(p_node_id, KnowledgeState.RESEARCHING)
	return {"success": true, "message": "开始研究「%s」" % graph.nodes[p_node_id].get("name", p_node_id)}


func set_research_progress(p_node_id: String, p_progress: float) -> void:
	if not runtime_nodes.has(p_node_id):
		return
	runtime_nodes[p_node_id]["research_progress"] = clampf(p_progress, 0.0, 1.0)


func pause_research(p_node_id: String) -> bool:
	if get_node_state(p_node_id) != KnowledgeState.RESEARCHING:
		return false
	_set_state(p_node_id, KnowledgeState.RESEARCHABLE)
	return true


func mark_mastered(p_node_id: String) -> bool:
	if not runtime_nodes.has(p_node_id):
		return false
	var state := get_node_state(p_node_id)
	if state not in [KnowledgeState.RESEARCHING, KnowledgeState.RESEARCHABLE, KnowledgeState.INSIGHT]:
		return false
	var runtime: Dictionary = runtime_nodes[p_node_id]
	runtime["research_progress"] = 1.0
	runtime["living_transmission"] = maxf(float(runtime.get("living_transmission", 0.0)), 0.55)
	runtime["record_integrity"] = maxf(float(runtime.get("record_integrity", 0.0)), 0.35)
	runtime["practice_level"] = maxf(float(runtime.get("practice_level", 0.0)), 0.25)
	_set_peak_state(p_node_id, KnowledgeState.MASTERED, "research:%s" % p_node_id)
	_reveal_children(p_node_id)
	_rebuild_capabilities()
	return true


func mark_applied(p_node_id: String, p_project_id: String) -> bool:
	if not runtime_nodes.has(p_node_id):
		return false
	var state := get_node_state(p_node_id)
	if state != KnowledgeState.MASTERED and state != KnowledgeState.APPLIED:
		return false
	var runtime: Dictionary = runtime_nodes[p_node_id]
	runtime["engineering_progress"][p_project_id] = 1.0
	runtime["practice_level"] = maxf(float(runtime.get("practice_level", 0.0)), 0.6)
	_set_peak_state(p_node_id, KnowledgeState.APPLIED, "engineering:%s" % p_project_id)
	_reveal_children(p_node_id)
	_rebuild_capabilities()
	return true


func set_engineering_progress(p_node_id: String, p_project_id: String, p_progress: float) -> void:
	if runtime_nodes.has(p_node_id):
		runtime_nodes[p_node_id]["engineering_progress"][p_project_id] = clampf(p_progress, 0.0, 1.0)


func get_node_state(p_node_id: String) -> int:
	if not runtime_nodes.has(p_node_id):
		return KnowledgeState.HIDDEN
	return int(runtime_nodes[p_node_id].get("state", KnowledgeState.HIDDEN))


func get_visible_nodes() -> Array:
	var result: Array = []
	for node_id in graph.nodes:
		if get_node_state(node_id) != KnowledgeState.HIDDEN:
			result.append(get_node_view(node_id))
	return result


func get_node_view(p_node_id: String) -> Dictionary:
	if not graph.nodes.has(p_node_id):
		return {}
	var state := get_node_state(p_node_id)
	if state == KnowledgeState.HIDDEN:
		return {}
	var definition: Dictionary = graph.nodes[p_node_id]
	var runtime: Dictionary = runtime_nodes[p_node_id]
	var result: Dictionary = {
		"id": p_node_id,
		"domain": definition.get("domain", ""),
		"teachable": bool(definition.get("teachable", true)),
		"state": state,
		"state_name": STATE_NAMES.get(state, "未知"),
		"tier": int(definition.get("tier", 0)),
		"column": int(definition.get("column", 0)),
		"clue_strength": float(runtime.get("clue_strength", 0.0)),
		"living_transmission": float(runtime.get("living_transmission", 0.0)),
		"record_integrity": float(runtime.get("record_integrity", 0.0)),
		"practice_level": float(runtime.get("practice_level", 0.0)),
	}
	if state == KnowledgeState.RUMOR:
		result["display_name"] = definition.get("rumor_label", "未知方向")
		result["description"] = definition.get("unknown_hint", "仍缺少足够线索。")
		result["source_ids"] = runtime.get("known_source_ids", []).duplicate()
		return result
	result["display_name"] = definition.get("name", p_node_id)
	result["description"] = definition.get("description", "")
	result["hypothesis"] = definition.get("hypothesis", "")
	result["evidence"] = (runtime.get("evidence", {}) as Dictionary).duplicate()
	result["missing_evidence"] = _get_missing_evidence(p_node_id)
	result["prerequisite_ids"] = (definition.get("prerequisite_ids", []) as Array).duplicate()
	result["research_progress"] = float(runtime.get("research_progress", 0.0))
	result["degradation_factors"] = (runtime.get("degradation_factors", []) as Array).duplicate()
	if state >= KnowledgeState.RESEARCHABLE or state == KnowledgeState.DEGRADED:
		result["research_requirements"] = (definition.get("research_requirements", {}) as Dictionary).duplicate(true)
		result["engineering_projects"] = (definition.get("engineering_projects", []) as Array).duplicate(true)
		result["engineering_progress"] = (runtime.get("engineering_progress", {}) as Dictionary).duplicate()
		result["theory_capability_tags"] = (definition.get("theory_capability_tags", []) as Array).duplicate()
		result["capability_tags"] = (definition.get("capability_tags", []) as Array).duplicate()
	return result


func has_capability(p_capability_id: String, p_minimum_level: int = 1) -> bool:
	return int(capability_levels.get(p_capability_id, 0)) >= p_minimum_level


func get_capabilities() -> Dictionary:
	return capability_levels.duplicate()


func apply_teaching_result(p_result: Dictionary) -> bool:
	var node_id := str(p_result.get("node_id", ""))
	if not runtime_nodes.has(node_id):
		return false
	var runtime: Dictionary = runtime_nodes[node_id]
	runtime["living_transmission"] = clampf(
		float(runtime.get("living_transmission", 0.0)) + float(p_result.get("living_gain", 0.0)), 0.0, 1.0
	)
	runtime["practice_level"] = clampf(
		float(runtime.get("practice_level", 0.0)) + float(p_result.get("practice_gain", 0.0)), 0.0, 1.0
	)
	_try_restore(node_id)
	return true


func apply_generation_turnover(p_context: Dictionary) -> Dictionary:
	var education_coverage := clampf(float(p_context.get("education_coverage", 0.0)), 0.0, 1.0)
	var record_retention := clampf(float(p_context.get("record_retention", 0.0)), 0.0, 1.0)
	var practice_retention := clampf(float(p_context.get("practice_retention", 0.0)), 0.0, 1.0)
	var degraded_nodes: Array = []
	for node_id in runtime_nodes:
		var runtime: Dictionary = runtime_nodes[node_id]
		if int(runtime.get("previous_peak_state", KnowledgeState.HIDDEN)) < KnowledgeState.MASTERED:
			continue
		runtime["living_transmission"] = float(runtime.get("living_transmission", 0.0)) * (0.72 + 0.28 * education_coverage)
		runtime["record_integrity"] = float(runtime.get("record_integrity", 0.0)) * (0.78 + 0.22 * record_retention)
		runtime["practice_level"] = float(runtime.get("practice_level", 0.0)) * (0.70 + 0.30 * practice_retention)
		if _evaluate_degradation(node_id):
			degraded_nodes.append(node_id)
	return {"degraded_node_ids": degraded_nodes}


func apply_knowledge_shock(p_shock: Dictionary) -> Dictionary:
	var affected: Array = p_shock.get("node_ids", runtime_nodes.keys())
	var living_loss := clampf(float(p_shock.get("living_loss", 0.0)), 0.0, 1.0)
	var record_loss := clampf(float(p_shock.get("record_loss", 0.0)), 0.0, 1.0)
	var practice_loss := clampf(float(p_shock.get("practice_loss", 0.0)), 0.0, 1.0)
	var degraded: Array = []
	for node_id in affected:
		if not runtime_nodes.has(node_id):
			continue
		var runtime: Dictionary = runtime_nodes[node_id]
		runtime["living_transmission"] = float(runtime.get("living_transmission", 0.0)) * (1.0 - living_loss)
		runtime["record_integrity"] = float(runtime.get("record_integrity", 0.0)) * (1.0 - record_loss)
		runtime["practice_level"] = float(runtime.get("practice_level", 0.0)) * (1.0 - practice_loss)
		if _evaluate_degradation(str(node_id)):
			degraded.append(node_id)
	return {"degraded_node_ids": degraded, "source_id": p_shock.get("source_id", "")}


func developer_unlock_all() -> void:
	for node_id in graph.nodes:
		_set_peak_state(node_id, KnowledgeState.APPLIED, "developer:unlock_all")
		var runtime: Dictionary = runtime_nodes[node_id]
		runtime["research_progress"] = 1.0
		for project_value in graph.nodes[node_id].get("engineering_projects", []):
			var project: Dictionary = project_value
			runtime["engineering_progress"][str(project.get("id", ""))] = 1.0
	_rebuild_capabilities()


func get_state() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"graph_data_version": graph.data_version,
		"nodes": runtime_nodes.duplicate(true),
		"known_source_ids": known_source_ids.duplicate(),
	}


func load_state(p_data: Dictionary) -> bool:
	if (
		int(p_data.get("state_version", -1)) != STATE_VERSION
		or int(p_data.get("graph_data_version", -1)) != graph.data_version
		or not p_data.get("nodes", null) is Dictionary
	):
		return false
	_initialize_empty_runtime()
	for node_id in p_data.get("nodes", {}):
		if not runtime_nodes.has(node_id) or not p_data["nodes"][node_id] is Dictionary:
			continue
		var loaded: Dictionary = p_data["nodes"][node_id]
		var runtime: Dictionary = _default_runtime_state()
		for key in runtime:
			if loaded.has(key):
				runtime[key] = loaded[key]
		runtime["state"] = clampi(int(runtime["state"]), KnowledgeState.HIDDEN, KnowledgeState.DEGRADED)
		runtime["previous_peak_state"] = clampi(int(runtime["previous_peak_state"]), KnowledgeState.HIDDEN, KnowledgeState.APPLIED)
		runtime_nodes[node_id] = runtime
	known_source_ids = (p_data.get("known_source_ids", {}) as Dictionary).duplicate()
	_rebuild_capabilities()
	return true


func _evaluate_state(p_node_id: String) -> void:
	var runtime: Dictionary = runtime_nodes[p_node_id]
	var state := int(runtime.get("state", KnowledgeState.HIDDEN))
	if state >= KnowledgeState.RESEARCHING:
		return
	if state == KnowledgeState.HIDDEN and float(runtime.get("clue_strength", 0.0)) > 0.0:
		_set_state(p_node_id, KnowledgeState.RUMOR)
		state = KnowledgeState.RUMOR
	var threshold := float(graph.nodes[p_node_id].get("insight_threshold", DEFAULT_INSIGHT_THRESHOLD))
	if state == KnowledgeState.RUMOR and float(runtime.get("clue_strength", 0.0)) >= threshold:
		_set_state(p_node_id, KnowledgeState.INSIGHT)
		state = KnowledgeState.INSIGHT
	if state == KnowledgeState.INSIGHT and _prerequisites_mastered(p_node_id) and _get_missing_evidence(p_node_id).is_empty():
		_set_state(p_node_id, KnowledgeState.RESEARCHABLE)


func _get_missing_evidence(p_node_id: String) -> Dictionary:
	var requirements: Dictionary = graph.nodes[p_node_id].get("evidence_requirements", {})
	var current: Dictionary = runtime_nodes[p_node_id].get("evidence", {})
	var missing: Dictionary = {}
	for evidence_type in requirements:
		var gap := float(requirements[evidence_type]) - float(current.get(evidence_type, 0.0))
		if gap > 0.000001:
			missing[evidence_type] = gap
	return missing


func _prerequisites_mastered(p_node_id: String) -> bool:
	for prerequisite_id in graph.nodes[p_node_id].get("prerequisite_ids", []):
		var state := get_node_state(prerequisite_id)
		if state not in [KnowledgeState.MASTERED, KnowledgeState.APPLIED]:
			return false
	return true


func _reveal_children(p_parent_id: String) -> void:
	for child_id in graph.get_children(p_parent_id):
		if get_node_state(child_id) == KnowledgeState.HIDDEN:
			add_clue(child_id, "branch:%s:%s" % [p_parent_id, child_id], 0.55)
			branch_revealed.emit(p_parent_id, child_id)
		else:
			_evaluate_state(child_id)


func _set_peak_state(p_node_id: String, p_state: int, p_source_id: String) -> void:
	var runtime: Dictionary = runtime_nodes[p_node_id]
	if not p_source_id.is_empty() and p_source_id not in runtime["known_source_ids"]:
		runtime["known_source_ids"].append(p_source_id)
	runtime["previous_peak_state"] = maxi(int(runtime.get("previous_peak_state", KnowledgeState.HIDDEN)), p_state)
	runtime["degradation_factors"] = []
	_set_state(p_node_id, p_state)


func _set_state(p_node_id: String, p_new_state: int) -> void:
	var runtime: Dictionary = runtime_nodes[p_node_id]
	var old_state := int(runtime.get("state", KnowledgeState.HIDDEN))
	if old_state == p_new_state:
		return
	runtime["state"] = p_new_state
	knowledge_state_changed.emit(p_node_id, old_state, p_new_state)


func _evaluate_degradation(p_node_id: String) -> bool:
	var runtime: Dictionary = runtime_nodes[p_node_id]
	var state := int(runtime.get("state", KnowledgeState.HIDDEN))
	if state not in [KnowledgeState.MASTERED, KnowledgeState.APPLIED, KnowledgeState.DEGRADED]:
		return false
	var missing: Array[String] = []
	if float(runtime.get("living_transmission", 0.0)) < MAINTENANCE_THRESHOLD:
		missing.append("living_transmission")
	if float(runtime.get("record_integrity", 0.0)) < MAINTENANCE_THRESHOLD:
		missing.append("record_integrity")
	if int(runtime.get("previous_peak_state", KnowledgeState.HIDDEN)) >= KnowledgeState.APPLIED and float(runtime.get("practice_level", 0.0)) < MAINTENANCE_THRESHOLD:
		missing.append("practice_level")
	runtime["degradation_factors"] = missing
	if missing.size() >= 2 and state != KnowledgeState.DEGRADED:
		_set_state(p_node_id, KnowledgeState.DEGRADED)
		knowledge_degraded.emit(p_node_id, missing)
		_rebuild_capabilities()
		return true
	return false


func _try_restore(p_node_id: String) -> void:
	if get_node_state(p_node_id) != KnowledgeState.DEGRADED:
		return
	var runtime: Dictionary = runtime_nodes[p_node_id]
	var enough_living := float(runtime.get("living_transmission", 0.0)) >= MAINTENANCE_THRESHOLD
	var enough_record := float(runtime.get("record_integrity", 0.0)) >= MAINTENANCE_THRESHOLD
	var enough_practice := float(runtime.get("practice_level", 0.0)) >= MAINTENANCE_THRESHOLD
	if int(enough_living) + int(enough_record) + int(enough_practice) >= 2:
		runtime["degradation_factors"] = []
		_set_state(p_node_id, int(runtime.get("previous_peak_state", KnowledgeState.MASTERED)))
		_rebuild_capabilities()


func _rebuild_capabilities() -> void:
	var old_capabilities := capability_levels.duplicate()
	capability_levels.clear()
	for node_id in graph.nodes:
		var state := get_node_state(node_id)
		var definition: Dictionary = graph.nodes[node_id]
		if state in [KnowledgeState.MASTERED, KnowledgeState.APPLIED]:
			for capability in definition.get("theory_capability_tags", []):
				capability_levels[str(capability)] = 1
		if state == KnowledgeState.APPLIED:
			for capability in definition.get("capability_tags", []):
				capability_levels[str(capability)] = 1
	var changed_ids: Array = old_capabilities.keys()
	for capability in capability_levels:
		if capability not in changed_ids:
			changed_ids.append(capability)
	for capability in changed_ids:
		if int(old_capabilities.get(capability, 0)) != int(capability_levels.get(capability, 0)):
			capability_changed.emit(str(capability), int(capability_levels.get(capability, 0)))
