class_name TechTree
extends RefCounted
## 科技树管理器 — 5层19节点 + 3种科技点数

signal research_finished(tech_id: String, tech_name: String)


const RESEARCH_BASIC: String = "basic"
const RESEARCH_APPLIED: String = "applied"
const RESEARCH_THEORETICAL: String = "theoretical"

const RESEARCH_NAMES: Dictionary = {
	"basic": "基础科研",
	"applied": "应用科研",
	"theoretical": "理论科研",
}

const RESEARCH_COLORS: Dictionary = {
	"basic": Color(0.471, 0.784, 1.0),
	"applied": Color(1.0, 0.784, 0.392),
	"theoretical": Color(0.784, 0.471, 1.0),
}


class TechNode:
	var id: String
	var name: String
	var description: String
	var effect_description: String
	var research_cost: Dictionary
	var resource_cost: Dictionary
	var requirements: Dictionary
	var prerequisites: Array
	var unlocked: bool
	var researching: bool
	var tier: int
	var column: int
	var category: String

	func _init(p_id: String, p_name: String, p_description: String,
			p_effect_description: String, p_research_cost: Dictionary = {},
			p_resource_cost: Dictionary = {}, p_requirements: Dictionary = {},
			p_prerequisites: Array = [], p_tier: int = 0, p_column: int = 0,
			p_category: String = "basic") -> void:
		id = p_id
		name = p_name
		description = p_description
		effect_description = p_effect_description
		research_cost = p_research_cost
		resource_cost = p_resource_cost
		requirements = p_requirements
		prerequisites = p_prerequisites
		unlocked = false
		researching = false
		tier = p_tier
		column = p_column
		category = p_category


var nodes: Dictionary = {}
var research_points: Dictionary = {
	"basic": 0.0,
	"applied": 0.0,
	"theoretical": 0.0,
}
var researching_tech_id: String = ""
var research_progress: Dictionary = {}
var _config: Dictionary = {}


func _init(p_config: Dictionary = {}) -> void:
	_config = p_config
	_init_default_techs(p_config)


func _init_default_techs(p_config: Dictionary) -> void:
	var tech_config: Dictionary = p_config.get("technology", {})

	if not tech_config.is_empty():
		for tech_id in tech_config:
			var tdata: Dictionary = tech_config[tech_id]
			var node: TechNode = TechNode.new(
				tech_id,
				tdata.get("name", tech_id),
				tdata.get("description", ""),
				tdata.get("effect_description", ""),
				tdata.get("research_cost", {}),
				tdata.get("resource_cost", {}),
				tdata.get("requirements", {}),
				tdata.get("prerequisites", []),
				tdata.get("tier", 0),
				tdata.get("column", 0),
				tdata.get("category", "basic"),
			)
			add_node(node)
		return

	# ── Tier 0 ────────────────────────────────────────
	add_node(_make_node("telescope", "望远镜", "基础光学设备，能初步观测星空。", "解锁星图功能，可观测三体恒星运动。",
		{"basic": 80}, {"iron": 50}, {"population": 50}, [], 0, 0, "basic"))
	add_node(_make_node("survival_shelter", "维生庇护所", "基础的地下掩体设计，提供临时保护。", "允许建造庇护所，降低极端环境下人口损失。",
		{"basic": 60}, {"iron": 80}, {"population": 30}, [], 0, 1, "basic"))
	add_node(_make_node("basic_metallurgy", "基础冶金", "掌握金属冶炼的基本工艺。", "解锁铜矿和稀有矿物的开采，以及实验室建造。",
		{"basic": 100}, {"iron": 100}, {"population": 60}, [], 0, 2, "basic"))
	add_node(_make_node("basic_agriculture", "基础农业", "系统化的农作物种植技术。", "解锁农场建造，提高食物产出。",
		{"basic": 50}, {"iron": 30}, {"population": 20}, [], 0, 3, "basic"))

	# ── Tier 1 ────────────────────────────────────────
	add_node(_make_node("computer", "计算机技术", "强大的计算能力，能进行复杂数值分析。", "解锁轨道预测功能。",
		{"basic": 200, "applied": 50}, {"iron": 150, "copper": 50}, {"population": 200},
		["telescope"], 1, 0, "applied"))
	add_node(_make_node("observatory", "天文观测站", "系统化的星空观测设施。", "增强星图精度，显示恒星质量和轨道参数。",
		{"basic": 150}, {"iron": 100, "copper": 50}, {"population": 100},
		["telescope"], 1, 1, "basic"))
	add_node(_make_node("deep_shelter", "深地庇护所", "深入地下的大型避难工程。", "建筑防护等级+2，极端环境下保护更多人口。",
		{"basic": 120, "applied": 30}, {"iron": 400, "copper": 100}, {"population": 150},
		["survival_shelter"], 1, 2, "applied"))
	add_node(_make_node("laboratory", "实验室", "系统化的科学研究设施。", "解锁实验室建造，产出应用科研点。",
		{"basic": 180}, {"iron": 200, "copper": 80}, {"population": 120},
		["basic_metallurgy"], 1, 3, "applied"))
	add_node(_make_node("basic_electrification", "基础电气化", "掌握电力的产生和使用。", "解锁藻类发电站，开始使用电力网络。",
		{"basic": 100}, {"iron": 150, "copper": 50}, {"population": 80},
		["basic_metallurgy"], 1, 4, "basic"))
	add_node(_make_node("fossil_fuel_extraction", "化石燃料开采", "从地底提取高能量的化石燃料。", "解锁化石燃料矿井。",
		{"basic": 120}, {"iron": 120, "copper": 30}, {"population": 100},
		["basic_metallurgy"], 1, 5, "basic"))

	# ── Tier 2 ────────────────────────────────────────
	add_node(_make_node("power_plant", "火力发电站", "大规模化石燃料电力生产设施。", "解锁火力发电站建造，提供稳定的大量电力。",
		{"applied": 140}, {"iron": 200, "copper": 100}, {"population": 150},
		["basic_electrification", "fossil_fuel_extraction"], 2, 0, "basic"))
	add_node(_make_node("chaos_prediction", "混沌预测模型", "基于非线性动力学的三体运动预测。", "星图中显示三体未来数十天的运动轨迹预测。",
		{"applied": 200, "theoretical": 50}, {"algae_fuel": 300}, {"population": 300},
		["computer"], 2, 1, "theoretical"))
	add_node(_make_node("automation", "自动化控制", "机器替代人工的生产控制系统。", "所有建筑产出效率+30%。",
		{"applied": 150}, {"iron": 200, "copper": 150}, {"population": 200},
		["computer", "basic_electrification"], 2, 2, "applied"))
	add_node(_make_node("radiation_armor", "防辐射装甲", "高密度辐射屏蔽材料。", "建筑辐射抗性+50%。",
		{"applied": 100, "basic": 80}, {"iron": 300, "rare_mineral": 20}, {"population": 150},
		["deep_shelter"], 2, 3, "applied"))
	add_node(_make_node("applied_physics", "应用物理", "系统化的物理工程学研究。", "解锁高级建筑研究分支。",
		{"applied": 200}, {"rare_mineral": 30}, {"population": 250},
		["laboratory"], 2, 4, "applied"))
	add_node(_make_node("material_science", "材料科学", "微观结构与材料性能研究。", "解锁高强度合金，建筑耐久度+50%。",
		{"applied": 180}, {"iron": 300, "copper": 100}, {"population": 200},
		["laboratory"], 2, 5, "applied"))

	# ── Tier 3 ────────────────────────────────────────
	add_node(_make_node("academy", "科学院", "最高等级的科研机构，汇聚顶尖科学家。", "解锁科学院建造，产出理论科研点。",
		{"applied": 300, "theoretical": 100}, {"iron": 1500, "copper": 500, "rare_mineral": 100}, {"population": 500},
		["applied_physics", "power_plant"], 3, 0, "theoretical"))
	add_node(_make_node("high_alloy", "高强度合金", "极端条件下仍保持结构完整性的特种合金。", "所有建筑耐久度上限翻倍，热/辐射抗性+30%。",
		{"applied": 250}, {"iron": 800, "copper": 200, "rare_mineral": 50}, {"population": 300},
		["material_science"], 3, 1, "applied"))

	# ── Tier 4 ────────────────────────────────────────
	add_node(_make_node("nuclear_fusion", "可控核聚变", "人造恒星级别的能量来源。", "规划效果：聚变反应堆尚未进入当前可建造原型。",
		{"theoretical": 500, "applied": 300}, {"iron": 3000, "copper": 1000, "rare_mineral": 500}, {"population": 800},
		["academy"], 4, 0, "theoretical"))


func _make_node(p_id: String, p_name: String, p_desc: String, p_effect: String,
		p_research_cost: Dictionary, p_resource_cost: Dictionary, p_requirements: Dictionary,
		p_prerequisites: Array, p_tier: int, p_column: int, p_category: String) -> TechNode:
	return TechNode.new(p_id, p_name, p_desc, p_effect,
		p_research_cost, p_resource_cost, p_requirements,
		p_prerequisites, p_tier, p_column, p_category)


func add_node(p_node: TechNode) -> void:
	nodes[p_node.id] = p_node


func get_node(p_node_id: String) -> TechNode:
	if nodes.has(p_node_id):
		return nodes[p_node_id] as TechNode
	return null


func is_unlocked(p_node_id: String) -> bool:
	var node: TechNode = get_node(p_node_id)
	if node != null:
		return node.unlocked
	return false


func produce_research(p_point_type: String, p_amount: float) -> void:
	if not research_points.has(p_point_type) or p_amount <= 0.0:
		return

	var remaining: float = p_amount

	if not researching_tech_id.is_empty():
		var node: TechNode = get_node(researching_tech_id)
		if node != null and node.researching:
			var needed: int = node.research_cost.get(p_point_type, 0)
			var already: float = research_progress.get(p_point_type, 0.0)
			var gap: float = max(0.0, float(needed) - already)
			if gap > 0.0 and remaining > 0.0:
				var inject: float = min(remaining, gap)
				research_progress[p_point_type] = already + inject
				remaining -= inject
				_check_research_completion()

	if remaining > 0.0:
		research_points[p_point_type] = research_points[p_point_type] + remaining


func can_start_research(p_node_id: String, p_entities) -> Dictionary:
	var node: TechNode = get_node(p_node_id)
	if node == null:
		return {"success": false, "message": "找不到该科技节点"}
	if node.unlocked:
		return {"success": false, "message": "该科技已经解锁完毕"}
	if node.researching:
		return {"success": false, "message": "该科技正在研究中"}
	if not researching_tech_id.is_empty():
		var current: TechNode = get_node(researching_tech_id)
		var current_name: String = current.name if current != null else researching_tech_id
		return {"success": false, "message": "正在研究「%s」，一次只能研究一个科技" % current_name}

	for pre_id in node.prerequisites:
		var pre_node: TechNode = get_node(pre_id)
		if pre_node == null or not pre_node.unlocked:
			var pre_name: String = pre_node.name if pre_node != null else pre_id
			return {"success": false, "message": "前置科技「%s」尚未研发完成" % pre_name}

	for res_name in node.resource_cost:
		var required: float = node.resource_cost[res_name]
		if required < 0.0:
			return {"success": false, "message": "科技资源成本无效"}
		var current_amt: float = p_entities.get_resource(res_name)
		if current_amt < required:
			var display_name: String = "资源"
			return {"success": false, "message": "资源「%s」不足（需求：%d，当前：%d）" % [res_name, int(required), int(current_amt)]}

	for req_res in node.requirements:
		var req_amt: float = node.requirements[req_res]
		var current_amt: float = p_entities.get_resource(req_res)
		if current_amt < req_amt:
			return {"success": false, "message": "%s不足（最低要求：%d，当前：%d）" % [req_res, int(req_amt), int(current_amt)]}

	return {"success": true, "message": ""}


func start_research(p_node_id: String, p_entities) -> Dictionary:
	var can: Dictionary = can_start_research(p_node_id, p_entities)
	if not can["success"]:
		return can

	var node: TechNode = get_node(p_node_id)

	var consumed: Dictionary = {}
	for res_name in node.resource_cost:
		var cost: float = node.resource_cost[res_name]
		if not p_entities.consume_resource(res_name, cost):
			for rollback_name in consumed:
				p_entities.produce_resource(rollback_name, consumed[rollback_name])
			return {"success": false, "message": "资源状态已变化，研究未开始"}
		consumed[res_name] = cost

	node.researching = true
	researching_tech_id = p_node_id
	research_progress.clear()
	for rtype in node.research_cost:
		research_progress[rtype] = 0.0
		var available: float = maxf(0.0, float(research_points.get(rtype, 0.0)))
		var inject: float = minf(available, float(node.research_cost[rtype]))
		if inject > 0.0:
			research_progress[rtype] = inject
			research_points[rtype] = available - inject

	_check_research_completion()
	if node.unlocked:
		return {"success": true, "message": "已使用库存科研点完成「%s」" % node.name}

	return {"success": true, "message": "开始研究「%s」" % node.name}


func cancel_research() -> Dictionary:
	if researching_tech_id.is_empty():
		return {"success": false, "message": "当前没有正在进行的研究"}

	var node: TechNode = get_node(researching_tech_id)
	if node == null:
		researching_tech_id = ""
		research_progress.clear()
		return {"success": false, "message": "研究节点不存在"}

	for rtype in research_progress:
		var amount: float = research_progress[rtype]
		if amount > 0.0 and research_points.has(rtype):
			research_points[rtype] = research_points[rtype] + amount

	var name: String = node.name
	node.researching = false
	researching_tech_id = ""
	research_progress.clear()

	return {"success": true, "message": "已取消研究「%s」，科技点数已退回" % name}


func _check_research_completion() -> void:
	if researching_tech_id.is_empty():
		return
	var node: TechNode = get_node(researching_tech_id)
	if node == null:
		return

	for rtype in node.research_cost:
		var required: int = node.research_cost[rtype]
		var accumulated: float = research_progress.get(rtype, 0.0)
		if accumulated < float(required):
			return

	_complete_research(node)


func _complete_research(p_node: TechNode) -> void:
	var completed_id: String = p_node.id
	var completed_name: String = p_node.name
	p_node.unlocked = true
	p_node.researching = false
	researching_tech_id = ""
	research_progress.clear()
	research_finished.emit(completed_id, completed_name)


func is_researchable(p_node_id: String) -> bool:
	var node: TechNode = get_node(p_node_id)
	if node == null or node.unlocked or node.researching:
		return false
	for pre_id in node.prerequisites:
		var pre: TechNode = get_node(pre_id)
		if pre == null or not pre.unlocked:
			return false
	return true


func get_max_tier() -> int:
	if nodes.is_empty():
		return 0
	var max_t: int = 0
	for n in nodes.values():
		var node: TechNode = n as TechNode
		if node.tier > max_t:
			max_t = node.tier
	return max_t


func get_nodes_by_tier(p_tier: int) -> Array:
	var result: Array = []
	for n in nodes.values():
		var node: TechNode = n as TechNode
		if node.tier == p_tier:
			result.append(node)
	result.sort_custom(func(a: TechNode, b: TechNode): return a.column < b.column)
	return result


func get_prerequisites_for(p_node_id: String) -> Array:
	var node: TechNode = get_node(p_node_id)
	if node != null:
		return node.prerequisites
	return []


func get_dependents_of(p_node_id: String) -> Array:
	var deps: Array = []
	for nid in nodes:
		var node: TechNode = nodes[nid] as TechNode
		if p_node_id in node.prerequisites:
			deps.append(nid)
	return deps


func get_research_progress() -> Dictionary:
	if researching_tech_id.is_empty():
		return {}

	var node: TechNode = get_node(researching_tech_id)
	if node == null:
		return {}

	var progress_dict: Dictionary = {}
	var total_current: float = 0.0
	var total_required: float = 0.0

	for rtype in node.research_cost:
		var required: int = node.research_cost[rtype]
		var current: float = research_progress.get(rtype, 0.0)
		progress_dict[rtype] = {"current": current, "required": required}
		total_current += current
		total_required += float(required)

	var overall: float = total_current / max(total_required, 0.001)

	var result: Dictionary
	result = {
		"tech_id": researching_tech_id,
		"tech_name": node.name,
		"progress": progress_dict,
		"overall_percent": min(1.0, overall),
	}
	return result


func get_state() -> Dictionary:
	var unlocked_list: Array = []
	var researching_list: Array = []
	for nid in nodes:
		var node: TechNode = nodes[nid] as TechNode
		if node.unlocked:
			unlocked_list.append(nid)
		if node.researching:
			researching_list.append(nid)

	var result: Dictionary
	result = {
		"unlocked": unlocked_list,
		"researching": researching_list,
		"research_points": research_points.duplicate(),
		"researching_tech_id": researching_tech_id,
		"research_progress": research_progress.duplicate(),
	}
	return result


func load_state(data: Dictionary) -> void:
	var unlocked_list: Array = data.get("unlocked", [])
	var researching_list: Array = data.get("researching", [])
	var points: Dictionary = data.get("research_points", {})

	for node_id in unlocked_list:
		if nodes.has(node_id):
			var node: TechNode = nodes[node_id] as TechNode
			node.unlocked = true

	for node_id in researching_list:
		if nodes.has(node_id):
			var node: TechNode = nodes[node_id] as TechNode
			node.researching = true

	for rtype in points:
		if research_points.has(rtype):
			research_points[rtype] = points[rtype]

	researching_tech_id = data.get("researching_tech_id", "")
	research_progress = data.get("research_progress", {})
