class_name DiscoverySystem
extends RefCounted
## Converts observations, experiments, production, events, and ruins into contributions.

const STATE_VERSION := 1

var knowledge_system
var processed_source_ids: Dictionary = {}
var observation_metrics: Dictionary = {}
var production_metrics: Dictionary = {}
var _completed_milestones: Dictionary = {}


func _init(p_knowledge_system) -> void:
	knowledge_system = p_knowledge_system


func update_day(p_game_day: float, p_delta_days: float, p_context: Dictionary) -> void:
	var day := int(floor(p_game_day))
	_apply_milestones("celestial_motion", "sky_cycles", [1, 3, 7], day, "natural:sky")
	_apply_milestones("symbolic_record", "oral_repetition", [2, 5], day, "practice:memory")
	_apply_milestones("cultivation", "plant_cycles", [3, 8], day, "natural:plants")
	_apply_milestones("fired_clay", "heat_trials", [2, 6], day, "practice:fire")

	var active_types: Array = p_context.get("active_building_types", [])
	if "farm" in active_types:
		record_production_experience("system:farm", "cultivation", p_delta_days)
	if "iron_mine" in active_types or "copper_mine" in active_types:
		record_production_experience("system:mining", "metallurgy", p_delta_days)


func record_observation(p_observer_id: String, p_phenomenon_id: String, p_measurement: Dictionary, p_quality: float) -> Dictionary:
	var target_map := {
		"celestial_motion": "celestial_motion",
		"plant_growth": "cultivation",
		"material_heating": "fired_clay",
	}
	var node_id := str(target_map.get(p_phenomenon_id, ""))
	if node_id.is_empty():
		return {"success": false, "message": "该现象尚未关联知识方向"}
	var sequence := int(observation_metrics.get(p_phenomenon_id, 0)) + 1
	observation_metrics[p_phenomenon_id] = sequence
	var evidence_type := {
		"celestial_motion": "sky_cycles",
		"plant_growth": "plant_cycles",
		"material_heating": "heat_trials",
	}[p_phenomenon_id] as String
	return submit_contribution({
		"source_id": "observation:%s:%s:%d" % [p_observer_id, p_phenomenon_id, sequence],
		"source_type": "observation",
		"target_node_id": node_id,
		"clue_strength": clampf(p_quality, 0.0, 1.0) * 0.2,
		"evidence": {evidence_type: maxf(0.0, float(p_measurement.get("duration", 1.0)) * p_quality)},
		"tags": [p_phenomenon_id],
	})


func record_experiment(p_experiment_id: String, p_result: Dictionary, p_reproducibility: float) -> Dictionary:
	var node_id := str(p_result.get("target_node_id", ""))
	if node_id.is_empty():
		return {"success": false, "message": "实验结果没有目标知识方向"}
	return submit_contribution({
		"source_id": "experiment:%s" % p_experiment_id,
		"source_type": "experiment",
		"target_node_id": node_id,
		"clue_strength": clampf(p_reproducibility, 0.0, 1.0) * 0.25,
		"evidence": p_result.get("evidence", {}),
		"tags": ["experiment"],
	})


func record_production_experience(p_building_id: String, p_process_id: String, p_amount: float) -> Dictionary:
	var target_map := {
		"cultivation": "cultivation",
		"metallurgy": "metallurgy",
		"electricity": "electricity",
	}
	var node_id := str(target_map.get(p_process_id, ""))
	if node_id.is_empty():
		return {"success": false, "message": "生产过程尚未关联知识方向"}
	var previous := float(production_metrics.get(p_process_id, 0.0))
	var current := previous + maxf(0.0, p_amount)
	production_metrics[p_process_id] = current
	var milestone := int(floor(current))
	if milestone <= int(floor(previous)):
		return {"success": false, "message": "生产经验尚未达到新里程碑"}
	return submit_contribution({
		"source_id": "production:%s:%s:%d" % [p_building_id, p_process_id, milestone],
		"source_type": "production",
		"target_node_id": node_id,
		"clue_strength": 0.1,
		"evidence": {"production_experience": 1.0},
		"tags": [p_process_id],
	})


func resolve_event_discovery(p_event_id: String, _p_choices: Dictionary, p_outcome: Dictionary) -> Dictionary:
	return submit_contribution({
		"source_id": "event:%s" % p_event_id,
		"source_type": "event",
		"target_node_id": p_outcome.get("target_node_id", ""),
		"clue_strength": p_outcome.get("clue_strength", 0.0),
		"evidence": p_outcome.get("evidence", {}),
		"tags": p_outcome.get("tags", ["one_time"]),
	})


func analyze_ruin_artifact(p_artifact_id: String, p_analysis_method: String, p_facility_id: String) -> Dictionary:
	var artifact_parts := p_artifact_id.split(":")
	var node_id := artifact_parts[-1] if artifact_parts.size() > 1 else ""
	return submit_contribution({
		"source_id": "ruin:%s:%s:%s" % [p_artifact_id, p_analysis_method, p_facility_id],
		"source_type": "ruin",
		"target_node_id": node_id,
		"clue_strength": 0.35,
		"evidence": {"artifact_analysis": 1.0},
		"tags": ["ruin", "one_time"],
	})


func submit_contribution(p_contribution: Dictionary) -> Dictionary:
	var source_id := str(p_contribution.get("source_id", ""))
	var node_id := str(p_contribution.get("target_node_id", ""))
	if source_id.is_empty() or node_id.is_empty():
		return {"success": false, "message": "发现贡献缺少来源或目标"}
	if processed_source_ids.has(source_id):
		return {"success": false, "message": "该发现来源已经结算"}
	var evidence = p_contribution.get("evidence", {})
	if not evidence is Dictionary:
		return {"success": false, "message": "发现证据格式无效"}
	var accepted: bool = knowledge_system.apply_discovery(
		node_id, source_id, float(p_contribution.get("clue_strength", 0.0)), evidence
	)
	if not accepted:
		return {"success": false, "message": "知识系统拒绝了该发现贡献"}
	processed_source_ids[source_id] = p_contribution.duplicate(true)
	return {"success": true, "message": "已记录新的知识线索", "target_node_id": node_id}


func get_state() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"processed_source_ids": processed_source_ids.duplicate(true),
		"observation_metrics": observation_metrics.duplicate(),
		"production_metrics": production_metrics.duplicate(),
		"completed_milestones": _completed_milestones.duplicate(),
	}


func load_state(p_data: Dictionary) -> bool:
	for key in ["processed_source_ids", "observation_metrics", "production_metrics", "completed_milestones"]:
		if p_data.has(key) and not p_data[key] is Dictionary:
			return false
	processed_source_ids = (p_data.get("processed_source_ids", {}) as Dictionary).duplicate(true)
	observation_metrics = (p_data.get("observation_metrics", {}) as Dictionary).duplicate()
	production_metrics = (p_data.get("production_metrics", {}) as Dictionary).duplicate()
	_completed_milestones = (p_data.get("completed_milestones", {}) as Dictionary).duplicate()
	return true


func _apply_milestones(p_node_id: String, p_evidence_type: String, p_days: Array, p_current_day: int, p_source_prefix: String) -> void:
	for milestone_day in p_days:
		var key := "%s:%d" % [p_source_prefix, int(milestone_day)]
		if p_current_day < int(milestone_day) or _completed_milestones.has(key):
			continue
		var result := submit_contribution({
			"source_id": key,
			"source_type": "observation",
			"target_node_id": p_node_id,
			"clue_strength": 0.15,
			"evidence": {p_evidence_type: 1.0},
			"tags": ["natural", "milestone"],
		})
		if result.get("success", false):
			_completed_milestones[key] = true
