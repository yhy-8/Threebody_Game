class_name OpeningGuidanceController
extends RefCounted
## Serializable, event-driven onboarding presentation; never mutates simulation domains.

const GUIDANCE_VERSION := 2

enum GuidanceMode { FULL, COMPACT, OFF }
enum OpeningPhase { AWAITING_CAPITAL, SURVIVAL, KNOWLEDGE, CONSTRUCTION, OBSERVATION, EXPLORATION, COMPLETE, RULES_TIME, AUTONOMY }

const MODE_NAMES: Dictionary = {GuidanceMode.FULL: "完整引导", GuidanceMode.COMPACT: "精简提示", GuidanceMode.OFF: "关闭引导"}
const TASKS: Array[Dictionary] = [
	{"id": "opening:capital", "phase": OpeningPhase.AWAITING_CAPITAL, "event": "capital_confirmed", "target": "settlement.capital_selection", "skippable": false, "text": "比较候选区域的已知环境与未知项，确认文明发源地。"},
	{"id": "opening:time_controls", "phase": OpeningPhase.RULES_TIME, "event": "time_control_used", "target": "time.controls", "skippable": true, "text": "对照规则倒计与文明当前观测，亲自暂停或继续一次模拟。"},
	{"id": "opening:survival_allocation", "phase": OpeningPhase.SURVIVAL, "event": "population_assignment_changed", "target": "population.assignment", "skippable": true, "text": "完成一次真实人口或生存岗位调整。"},
	{"id": "opening:first_teaching_plan", "phase": OpeningPhase.KNOWLEDGE, "event": "teaching_plan_progressed", "target": "knowledge.teaching_plans", "skippable": true, "text": "让一项教学计划真实运行；掌握者与学习者会占用生产劳动。"},
	{"id": "opening:first_construction", "phase": OpeningPhase.CONSTRUCTION, "event": "construction_started", "target": "region.construction", "skippable": true, "text": "让一项合法建设进入施工，而不领取额外材料。"},
	{"id": "opening:first_observation", "phase": OpeningPhase.OBSERVATION, "event": "observation_recorded", "target": "observation.record", "skippable": true, "text": "记录一次当地天空观察；看见天体不等于能预测灾害。"},
	{"id": "opening:first_expedition", "phase": OpeningPhase.EXPLORATION, "event": "expedition_departed", "target": "exploration.plan", "skippable": true, "text": "配置真实队员和补给，让第一支勘探队出发，或暂缓此步。"},
	{"id": "opening:autonomy", "phase": OpeningPhase.AUTONOMY, "event": "guidance_closed", "target": "guidance.handbook", "skippable": true, "text": "开局循环已经结束。记住顶部‘引导’可重新打开手册，然后进入自主发展。"}
]

var mode: int = GuidanceMode.FULL
var phase: int = OpeningPhase.AWAITING_CAPITAL
var completed_task_ids: Array[String] = []
var skipped_task_ids: Array[String] = []
var dismissed_hint_ids: Array[String] = []
var deferred_task_reasons: Dictionary = {}
var handbook_seen_concept_ids: Array[String] = []
var processed_source_ids: Array[String] = []
var group_deferred: bool = false
var group_deferred_reason: String = ""


func initialize(p_mode: int, p_restored_state: Dictionary = {}) -> bool:
	if p_mode < GuidanceMode.FULL or p_mode > GuidanceMode.OFF:
		return false
	mode = p_mode
	if not p_restored_state.is_empty():
		return load_state(p_restored_state)
	phase = OpeningPhase.AWAITING_CAPITAL
	completed_task_ids.clear()
	skipped_task_ids.clear()
	dismissed_hint_ids.clear()
	deferred_task_reasons.clear()
	handbook_seen_concept_ids.clear()
	processed_source_ids.clear()
	group_deferred = false
	group_deferred_reason = ""
	return true


func handle_domain_event(p_event_id: String, p_payload: Dictionary) -> bool:
	var source_id := str(p_payload.get("source_id", ""))
	if source_id.is_empty() or source_id in processed_source_ids:
		return false
	processed_source_ids.append(source_id)
	var changed := false
	for task in TASKS:
		var task_id := str(task["id"])
		if task.get("event", "") == p_event_id and task_id not in completed_task_ids and task_id not in skipped_task_ids:
			completed_task_ids.append(task_id)
			deferred_task_reasons.erase(task_id)
			changed = true
	_recalculate_phase()
	return changed


func get_active_task_views() -> Array:
	if mode == GuidanceMode.OFF or group_deferred:
		return []
	var result: Array = []
	for task in TASKS:
		var task_id := str(task["id"])
		if task_id in completed_task_ids or task_id in skipped_task_ids:
			continue
		if int(task["phase"]) != phase:
			continue
		var view := task.duplicate(true)
		view["compact"] = mode == GuidanceMode.COMPACT
		view["deferred_reason"] = deferred_task_reasons.get(task_id, "")
		result.append(view)
	return result


func set_mode(p_mode: int) -> bool:
	if p_mode < GuidanceMode.FULL or p_mode > GuidanceMode.OFF:
		return false
	mode = p_mode
	return true


func skip_task(p_task_id: String) -> bool:
	for task in TASKS:
		if task["id"] == p_task_id and bool(task.get("skippable", false)):
			if p_task_id not in skipped_task_ids:
				skipped_task_ids.append(p_task_id)
			_recalculate_phase()
			return true
	return false


func defer_task(p_task_id: String, p_reason: String) -> bool:
	for task in TASKS:
		if task["id"] == p_task_id and bool(task.get("skippable", false)):
			deferred_task_reasons[p_task_id] = p_reason
			return true
	return false


func defer_group(p_reason: String = "玩家选择稍后继续") -> bool:
	if phase == OpeningPhase.COMPLETE:
		return false
	group_deferred = true
	group_deferred_reason = p_reason.strip_edges()
	if group_deferred_reason.is_empty():
		group_deferred_reason = "玩家选择稍后继续"
	return true


func resume_guidance() -> void:
	if mode == GuidanceMode.OFF:
		mode = GuidanceMode.FULL
	group_deferred = false
	group_deferred_reason = ""
	_recalculate_phase()


func get_state() -> Dictionary:
	return {
		"guidance_version": GUIDANCE_VERSION,
		"mode": mode,
		"phase": phase,
		"completed_task_ids": completed_task_ids.duplicate(),
		"skipped_task_ids": skipped_task_ids.duplicate(),
		"dismissed_hint_ids": dismissed_hint_ids.duplicate(),
		"deferred_task_reasons": deferred_task_reasons.duplicate(),
		"handbook_seen_concept_ids": handbook_seen_concept_ids.duplicate(),
		"processed_source_ids": processed_source_ids.duplicate(),
		"group_deferred": group_deferred,
		"group_deferred_reason": group_deferred_reason,
	}


func load_state(p_data: Dictionary) -> bool:
	if int(p_data.get("guidance_version", GUIDANCE_VERSION)) <= 0:
		return false
	mode = clampi(int(p_data.get("mode", GuidanceMode.FULL)), GuidanceMode.FULL, GuidanceMode.OFF)
	phase = clampi(int(p_data.get("phase", OpeningPhase.AWAITING_CAPITAL)), OpeningPhase.AWAITING_CAPITAL, OpeningPhase.AUTONOMY)
	completed_task_ids.assign(p_data.get("completed_task_ids", []))
	skipped_task_ids.assign(p_data.get("skipped_task_ids", []))
	dismissed_hint_ids.assign(p_data.get("dismissed_hint_ids", []))
	deferred_task_reasons = (p_data.get("deferred_task_reasons", {}) as Dictionary).duplicate()
	handbook_seen_concept_ids.assign(p_data.get("handbook_seen_concept_ids", []))
	processed_source_ids.assign(p_data.get("processed_source_ids", []))
	group_deferred = bool(p_data.get("group_deferred", false))
	group_deferred_reason = str(p_data.get("group_deferred_reason", ""))
	_recalculate_phase()
	return true


func _recalculate_phase() -> void:
	for task in TASKS:
		var task_id := str(task["id"])
		if task_id not in completed_task_ids and task_id not in skipped_task_ids:
			phase = int(task["phase"])
			return
	phase = OpeningPhase.COMPLETE
