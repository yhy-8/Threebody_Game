class_name CivilizationObjectives
extends RefCounted
## Long-term civilization milestones evaluated from real simulation state.
## Objectives never grant free resources; completion only records progress and
## a small, explainable social-confidence effect applied by GameState.

const STATE_VERSION := 1

const ERAS: Array[String] = ["survival", "knowledge", "industry", "planetary", "interstellar"]

const ERA_NAMES: Dictionary = {
	"survival": "求生纪元",
	"knowledge": "知识纪元",
	"industry": "工业纪元",
	"planetary": "行星纪元",
	"interstellar": "星际纪元",
}

const ERA_NOTES: Dictionary = {
	"survival": "先让食物、人口与基本劳动稳定下来。",
	"knowledge": "文明已经能把经验变成可复述、可验证的知识。",
	"industry": "电力、实验设施与规模生产开始互相支撑。",
	"planetary": "文明能系统观测天空，并为主要人口提供长期庇护。",
	"interstellar": "聚变与重工业让文明拥有跨时代的能量基础。",
}

const OBJECTIVES: Array[Dictionary] = [
	{
		"id": "food_security",
		"target_scene": "res://scenes/zone_view/zone_view.tscn",
		"era": "survival",
		"title": "站稳脚跟",
		"description": "建立持续运行的食物来源，并把口粮储备提高到至少 15 天。",
		"target_text": "食物净流量 ≥ 0，且储备可维持 ≥ 15 天",
		"hint": "再建一座藻类采集营地，或研究「栽培试验」后建造农场。",
	},
	{
		"id": "first_lesson",
		"target_scene": "res://scenes/tech_tree/tech_tree.tscn",
		"era": "survival",
		"title": "把经验交给下一代",
		"description": "让一项真实的教学计划开始运行；教师和学习者都会占用当前劳动力。",
		"target_text": "运行至少 1 项教学计划",
		"hint": "在知识图 → 知识政策中，选择已掌握的知识、组织方式与投入强度。",
	},
	{
		"id": "knowledge_foundation",
		"target_scene": "res://scenes/tech_tree/tech_tree.tscn",
		"era": "knowledge",
		"title": "知识的基础",
		"description": "完成至少 8 项知识的理论掌握或工程化，使文明不再只依赖零散经验。",
		"target_text": "掌握或工程化 8 项知识",
		"hint": "研究节点需要证据与前置知识；生产、观察与实验都会留下线索。",
	},
	{
		"id": "industrial_base",
		"target_scene": "res://scenes/tech_tree/tech_tree.tscn",
		"era": "industry",
		"title": "电与实验",
		"description": "让电力网络真实供电，并完成实验室的工程化，使应用研究可以持续进行。",
		"target_text": "发电 ≥ 5 kW，且具备可运行的实验室能力",
		"hint": "研究「电与电路」后建造藻类发电站；研究「对照实验」并建成实验室。",
	},
	{
		"id": "shelter_network",
		"target_scene": "res://scenes/zone_view/zone_view.tscn",
		"era": "industry",
		"title": "为最坏的日子做准备",
		"description": "让已完工、已配员且获得供能的庇护设施容纳至少 20% 的人口（下限 25 人）。",
		"target_text": "运行中的庇护容量 ≥ max(25, 人口的 20%)",
		"hint": "庇护所需要持续供电与运行人员；只在危机按钮里确认预案还不够。",
	},
	{
		"id": "frontier_settlements",
		"target_scene": "res://scenes/zone_view/zone_view.tscn",
		"era": "industry",
		"title": "走出摇篮",
		"description": "在本区域之外建立至少一处前哨或常设聚落，并让它保持实际人口与补给。",
		"target_text": "至少 2 处有人聚落（首都之外建立前哨）",
		"hint": "在区域界面选择相邻区域，派出一支携带口粮的迁徙队；到达后仍需后续补给与建设。",
	},
	{
		"id": "population_center",
		"target_scene": "res://scenes/zone_view/zone_view.tscn",
		"era": "industry",
		"title": "人口中心",
		"description": "让文明人口达到 300 人，同时保持食物与庇护能力不被增长拖垮。",
		"target_text": "总人口 ≥ 300",
		"hint": "人口增长依赖食物满足度、生育岗位与自然增长；盲目扩张会先耗尽口粮。",
	},
	{
		"id": "sky_watch",
		"target_scene": "res://scenes/tech_tree/tech_tree.tscn",
		"era": "planetary",
		"title": "把天空变成记录",
		"description": "掌握系统天文观测，并让一座天文观测站持续运行。",
		"target_text": "具备天文观测能力，且有运行中的观测站",
		"hint": "先完成光学观测，再研究系统天文观测；观测站需要电力和运行人员。",
	},
	{
		"id": "deep_knowledge",
		"target_scene": "res://scenes/tech_tree/tech_tree.tscn",
		"era": "planetary",
		"title": "知识的纵深",
		"description": "让至少 16 项知识达到理论掌握或工程化，形成可以互相支撑的知识体系。",
		"target_text": "掌握或工程化 16 项知识",
		"hint": "后期知识需要实验室、观测站、计算与高成本工程；不要只停留在单一领域。",
	},
	{
		"id": "fusion_theory",
		"target_scene": "res://scenes/tech_tree/tech_tree.tscn",
		"era": "interstellar",
		"title": "聚变之路",
		"description": "完成受控聚变的理论与工程化准备，证明文明能够在地面复现恒星能量。",
		"target_text": "完成「受控聚变」工程化",
		"hint": "需要知识院、高强度合金与自动控制；这是稳定纪元里最长的科技链之一。",
	},
	{
		"id": "survive_chaos",
		"era": "planetary",
		"title": "穿越乱纪元",
		"description": "在真实三体混沌开始后继续维持文明至少 100 个游戏日。",
		"target_text": "混沌纪元开始后存续 ≥ 100 天",
		"hint": "提前准备食物、庇护、电力与知识保存；混沌开始后不能靠规则倒计时获得灾害真值。",
	},
	{
		"id": "fusion_era",
		"target_scene": "res://scenes/zone_view/zone_view.tscn",
		"era": "interstellar",
		"title": "点亮聚变",
		"description": "完成受控聚变工程，并让聚变反应堆真实发电。",
		"target_text": "聚变反应堆完工、配员、供料并发电",
		"hint": "受控聚变需要知识院、高强度合金和自动控制；聚变堆需要rare矿物持续供料。",
	},
]

var completed_ids: Array[String] = []
var completion_days: Dictionary = {}
var current_objective_id: String = ""
var food_security_streak: float = 0.0


func reset() -> void:
	completed_ids.clear()
	completion_days.clear()
	current_objective_id = ""
	food_security_streak = 0.0


func advance(p_context: Dictionary, p_delta_days: float) -> void:
	var food_ok := (
		float(p_context.get("food_net", -1.0)) >= -0.001
		and float(p_context.get("food_days", 0.0)) >= 15.0
		and bool(p_context.get("has_food_production", false))
	)
	if food_ok:
		food_security_streak += maxf(0.0, p_delta_days)
	else:
		food_security_streak = 0.0


func get_definition(p_objective_id: String) -> Dictionary:
	for definition in OBJECTIVES:
		if str(definition.get("id", "")) == p_objective_id:
			return definition.duplicate(true)
	return {}


func get_current_view(p_context: Dictionary, p_game_day: float) -> Dictionary:
	var objective_id := current_objective_id
	if objective_id.is_empty() or objective_id in completed_ids:
		objective_id = _first_incomplete_id()
		current_objective_id = objective_id
	if objective_id.is_empty():
		return {
			"id": "",
			"title": "当前阶段目标已全部完成",
			"description": "文明已经完成当前版本的全部阶段目标；继续经营、观测并准备混沌纪元的挑战。",
			"progress": 1.0,
			"complete": true,
			"target_text": "",
			"hint": "你可以继续发展，等待更高层级的挑战。",
			"era": get_era(p_context).get("id", "survival"),
			"era_name": get_era(p_context).get("name", "求生纪元"),
		}
	var definition: Dictionary = get_definition(objective_id)
	var evaluation: Dictionary = _evaluate(objective_id, p_context)
	var view := definition.duplicate(true)
	view["progress"] = clampf(float(evaluation.get("progress", 0.0)), 0.0, 1.0)
	view["complete"] = bool(evaluation.get("complete", false))
	view["detail"] = str(evaluation.get("detail", ""))
	view["completed_day"] = float(completion_days.get(objective_id, -1.0))
	var era: Dictionary = get_era(p_context)
	view["era"] = era.get("id", "survival")
	view["era_name"] = era.get("name", "求生纪元")
	view["era_note"] = era.get("note", "")
	return view


func get_all_views(p_context: Dictionary, p_game_day: float) -> Array:
	var result: Array = []
	for definition in OBJECTIVES:
		var objective_id := str(definition.get("id", ""))
		var evaluation: Dictionary = _evaluate(objective_id, p_context)
		var view := definition.duplicate(true)
		view["progress"] = clampf(float(evaluation.get("progress", 0.0)), 0.0, 1.0)
		view["complete"] = objective_id in completed_ids or bool(evaluation.get("complete", false))
		view["detail"] = str(evaluation.get("detail", ""))
		view["completed_day"] = float(completion_days.get(objective_id, -1.0))
		view["is_current"] = objective_id == current_objective_id
		result.append(view)
	return result


func update(p_context: Dictionary, p_game_day: float) -> Array:
	var newly_completed: Array = []
	for definition in OBJECTIVES:
		var objective_id := str(definition.get("id", ""))
		if objective_id in completed_ids:
			continue
		var evaluation: Dictionary = _evaluate(objective_id, p_context)
		if bool(evaluation.get("complete", false)):
			completed_ids.append(objective_id)
			completion_days[objective_id] = p_game_day
			newly_completed.append(objective_id)
	if current_objective_id.is_empty() or current_objective_id in completed_ids:
		current_objective_id = _first_incomplete_id()
	return newly_completed


func get_era(p_context: Dictionary) -> Dictionary:
	var capabilities: Dictionary = p_context.get("capabilities", {})
	var power: float = float(p_context.get("power_generation", 0.0))
	var advanced: int = int(p_context.get("knowledge_advanced", 0))
	var era := "survival"
	if capabilities.has("nuclear_fusion") or bool(p_context.get("fusion_reactor_running", false)):
		era = "interstellar"
	elif (
		capabilities.has("observatory")
		and int(p_context.get("shelter_capacity", 0)) >= 100
		and advanced >= 12
	):
		era = "planetary"
	elif power >= 5.0 and capabilities.has("laboratory"):
		era = "industry"
	elif advanced >= 6:
		era = "knowledge"
	return {
		"id": era,
		"name": ERA_NAMES.get(era, era),
		"note": ERA_NOTES.get(era, ""),
	}


func get_progress_summary(p_context: Dictionary, p_game_day: float) -> String:
	var era: Dictionary = get_era(p_context)
	var current: Dictionary = get_current_view(p_context, p_game_day)
	if bool(current.get("complete", false)) and str(current.get("id", "")).is_empty():
		return "%s · 阶段目标已完成" % era.get("name", "")
	return "%s · %s（%.0f%%）" % [
		era.get("name", ""),
		current.get("title", ""),
		float(current.get("progress", 0.0)) * 100.0,
	]


func get_state() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"completed_ids": completed_ids.duplicate(),
		"completion_days": completion_days.duplicate(),
		"current_objective_id": current_objective_id,
		"food_security_streak": food_security_streak,
	}


func load_state(p_data: Dictionary) -> bool:
	if (
		int(p_data.get("state_version", -1)) != STATE_VERSION
		or not p_data.get("completed_ids", null) is Array
		or not p_data.get("completion_days", null) is Dictionary
	):
		return false
	completed_ids.assign(p_data["completed_ids"])
	completion_days = (p_data["completion_days"] as Dictionary).duplicate()
	current_objective_id = str(p_data.get("current_objective_id", ""))
	food_security_streak = maxf(0.0, float(p_data.get("food_security_streak", 0.0)))
	return true


func _first_incomplete_id() -> String:
	for definition in OBJECTIVES:
		var objective_id := str(definition.get("id", ""))
		if objective_id not in completed_ids:
			return objective_id
	return ""


func _evaluate(p_objective_id: String, p_context: Dictionary) -> Dictionary:
	var capabilities: Dictionary = p_context.get("capabilities", {})
	var advanced: int = int(p_context.get("knowledge_advanced", 0))
	var power: float = float(p_context.get("power_generation", 0.0))
	var population: int = int(p_context.get("population", 0))
	var shelter_capacity: int = int(p_context.get("shelter_capacity", 0))
	match p_objective_id:
		"food_security":
			var food_days: float = float(p_context.get("food_days", 0.0))
			var food_net: float = float(p_context.get("food_net", 0.0))
			var food_progress: float = clampf(food_days / 15.0, 0.0, 1.0)
			if food_net < -0.001:
				food_progress *= 0.6
			food_progress = minf(food_progress, clampf(food_security_streak / 5.0, 0.0, 1.0))
			return {
				"progress": food_progress,
				"complete": (
					food_net >= -0.001 and food_days >= 15.0
					and bool(p_context.get("has_food_production", false))
					and food_security_streak >= 5.0
				),
				"detail": "当前净流量 %+.2f/天，储备约 %.1f 天，连续盈余 %.1f / 5 天" % [
					food_net, food_days, food_security_streak,
				],
			}
		"first_lesson":
			var teaching: int = int(p_context.get("teaching_plan_count", 0))
			return {
				"progress": 1.0 if teaching > 0 else 0.0,
				"complete": teaching > 0,
				"detail": "当前教学计划 %d 项" % teaching,
			}
		"knowledge_foundation":
			return {
				"progress": clampf(float(advanced) / 8.0, 0.0, 1.0),
				"complete": advanced >= 8,
				"detail": "已掌握或工程化 %d / 8 项知识" % advanced,
			}
		"industrial_base":
			var power_progress: float = clampf(power / 5.0, 0.0, 1.0)
			var lab_ready: bool = capabilities.has("laboratory")
			return {
				"progress": (power_progress * 0.5) + (0.5 if lab_ready else 0.0),
				"complete": power >= 5.0 and lab_ready,
				"detail": "发电 %.1f kW；实验室能力%s" % [power, "已具备" if lab_ready else "未具备"],
			}
		"shelter_network":
			var target: int = maxi(25, int(ceil(float(population) * 0.2)))
			return {
				"progress": clampf(float(shelter_capacity) / float(maxi(1, target)), 0.0, 1.0),
				"complete": shelter_capacity >= target,
				"detail": "运行中庇护容量 %d / 目标 %d 人" % [shelter_capacity, target],
			}
		"frontier_settlements":
			var settlement_count: int = int(p_context.get("settlement_count", 0))
			return {
				"progress": clampf(float(settlement_count) / 2.0, 0.0, 1.0),
				"complete": settlement_count >= 2,
				"detail": "当前有人聚落 %d / 2 处" % settlement_count,
			}
		"population_center":
			return {
				"progress": clampf(float(population) / 300.0, 0.0, 1.0),
				"complete": population >= 300,
				"detail": "当前人口 %d / 300" % population,
			}
		"deep_knowledge":
			return {
				"progress": clampf(float(advanced) / 16.0, 0.0, 1.0),
				"complete": advanced >= 16,
				"detail": "已掌握或工程化 %d / 16 项知识" % advanced,
			}
		"sky_watch":
			var has_capability: bool = capabilities.has("observatory")
			var running: bool = bool(p_context.get("observatory_running", false))
			return {
				"progress": (0.5 if has_capability else 0.0) + (0.5 if running else 0.0),
				"complete": has_capability and running,
				"detail": "观测理论%s；观测站%s" % [
					"已具备" if has_capability else "未具备",
					"运行中" if running else "未运行",
				],
			}
		"fusion_theory":
			var fusion_capability: bool = capabilities.has("nuclear_fusion")
			return {
				"progress": 1.0 if fusion_capability else 0.0,
				"complete": fusion_capability,
				"detail": "受控聚变理论%s" % ("已工程化" if fusion_capability else "尚未工程化"),
			}
		"survive_chaos":
			var chaos_started: bool = bool(p_context.get("chaos_started", false))
			var days_since: float = float(p_context.get("days_since_chaos", 0.0))
			return {
				"progress": clampf(days_since / 100.0, 0.0, 1.0) if chaos_started else 0.0,
				"complete": chaos_started and days_since >= 100.0 and population > 0,
				"detail": "混沌已持续 %.1f / 100 天" % days_since if chaos_started else "尚未进入真实三体混沌",
			}
		"fusion_era":
			var fusion_capability: bool = capabilities.has("nuclear_fusion")
			var reactor_running: bool = bool(p_context.get("fusion_reactor_running", false))
			return {
				"progress": (0.5 if fusion_capability else 0.0) + (0.5 if reactor_running else 0.0),
				"complete": reactor_running,
				"detail": "聚变理论%s；反应堆%s" % [
					"已掌握" if fusion_capability else "未掌握",
					"运行中" if reactor_running else "未运行",
				],
			}
	return {"progress": 0.0, "complete": false, "detail": ""}
