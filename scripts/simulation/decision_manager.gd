class_name DecisionManager
extends RefCounted
## 决策管理器 — 管理建筑建造和政策执行

const _EM = preload("res://scripts/simulation/entity_manager.gd")


enum CivilizationState { NORMAL, DEHYDRATED }


class Decision:
	var id: String
	var name: String
	var description: String
	var category: String
	var resource_cost: Dictionary
	var tech_requirement: String
	var effects: Dictionary
	var cooldown: float
	var requires_zone: bool
	var building_type: String
	var worker_capacity: int
	var per_worker_output: Dictionary
	var consumption: Dictionary
	var build_time: float
	var storage_capacity: int

	func _init(p_id: String, p_name: String, p_description: String,
			p_category: String, p_resource_cost: Dictionary = {},
			p_tech_requirement: String = "", p_effects: Dictionary = {},
			p_cooldown: float = 0.0, p_requires_zone: bool = false,
			p_building_type: String = "", p_worker_capacity: int = 0,
			p_per_worker_output: Dictionary = {}, p_consumption: Dictionary = {},
			p_build_time: float = 3.0, p_storage_capacity: int = 0) -> void:
		id = p_id
		name = p_name
		description = p_description
		category = p_category
		resource_cost = p_resource_cost
		tech_requirement = p_tech_requirement
		effects = p_effects
		cooldown = p_cooldown
		requires_zone = p_requires_zone
		building_type = p_building_type
		worker_capacity = p_worker_capacity
		per_worker_output = p_per_worker_output
		consumption = p_consumption
		build_time = p_build_time
		storage_capacity = p_storage_capacity


const _DEFAULT_BUILDINGS: Dictionary = {
	"algae_collector": {
		"name": "建造藻类采集场", "description": "采集行星原生藻类，干燥后作为初级燃料。",
		"resource_cost": {"iron": 20}, "tech_requirement": "", "requires_zone": true,
		"worker_capacity": 5, "per_worker_output": {"algae_fuel": 3.0},
		"consumption": {}, "build_time": 2.0, "storage_capacity": 0,
	},
	"algae_foraging": {
		"name": "搭建藻类采集与粗加工营地", "description": "依靠人工采集、清洗、晾晒与火烤处理当地藻类，不需要电力或工业设备。",
		"resource_cost": {}, "tech_requirement": "", "requires_zone": true,
		"worker_capacity": 16, "per_worker_output": {"food": 1.5},
		"consumption": {}, "build_time": 0.75, "storage_capacity": 0,
	},
	"iron_mine": {
		"name": "建造铁矿场", "description": "在指定区域开采铁矿石。",
		"resource_cost": {"iron": 30}, "tech_requirement": "", "requires_zone": true,
		"worker_capacity": 5, "per_worker_output": {"iron": 2.0},
		"consumption": {}, "build_time": 3.0, "storage_capacity": 0,
	},
	"copper_mine": {
		"name": "建造铜矿场", "description": "开采铜矿，用于制造电气设备和高级设施。",
		"resource_cost": {"iron": 40, "copper": 10}, "tech_requirement": "basic_metallurgy", "requires_zone": true,
		"worker_capacity": 5, "per_worker_output": {"copper": 1.5},
		"consumption": {}, "build_time": 3.0, "storage_capacity": 0,
	},
	"rare_mine": {
		"name": "建造稀有矿场", "description": "开采稀有矿物，用于高级科技和建筑。",
		"resource_cost": {"iron": 60, "copper": 20}, "tech_requirement": "basic_metallurgy", "requires_zone": true,
		"worker_capacity": 3, "per_worker_output": {"rare_mineral": 0.5},
		"consumption": {}, "build_time": 4.0, "storage_capacity": 0,
	},
	"farm": {
		"name": "建造农场", "description": "在指定区域建造一座农场，持续产出食物。",
		"resource_cost": {"iron": 50}, "tech_requirement": "basic_agriculture", "requires_zone": true,
		"worker_capacity": 8, "per_worker_output": {"food": 3.0},
		"consumption": {}, "build_time": 3.0, "storage_capacity": 0,
	},
	"fossil_mine": {
		"name": "建造化石燃料矿井", "description": "开采地下化石燃料沉积层。",
		"resource_cost": {"iron": 80, "copper": 20}, "tech_requirement": "fossil_fuel_extraction", "requires_zone": true,
		"worker_capacity": 5, "per_worker_output": {"fossil_fuel": 4.0},
		"consumption": {}, "build_time": 4.0, "storage_capacity": 0,
	},
	"algae_power_plant": {
		"name": "建造藻类燃烧发电站", "description": "燃烧干燥藻类发电，初级电力来源。",
		"resource_cost": {"iron": 60, "copper": 15}, "tech_requirement": "basic_electrification", "requires_zone": true,
		"worker_capacity": 3, "per_worker_output": {"electricity": 5.0},
		"consumption": {"algae_fuel": 3.0}, "build_time": 3.0, "storage_capacity": 0,
	},
	"fossil_power_plant": {
		"name": "建造化石燃料发电站", "description": "大规模化石燃料发电设施，中级电力来源。",
		"resource_cost": {"iron": 200, "copper": 100}, "tech_requirement": "power_plant", "requires_zone": true,
		"worker_capacity": 3, "per_worker_output": {"electricity": 15.0},
		"consumption": {"fossil_fuel": 5.0}, "build_time": 5.0, "storage_capacity": 0,
	},
	"shelter": {
		"name": "建造庇护所", "description": "保护居民免受极端环境伤害的地下工事。",
		"resource_cost": {"iron": 100}, "tech_requirement": "survival_shelter", "requires_zone": true,
		"worker_capacity": 0, "per_worker_output": {},
		"consumption": {"electricity": 1.0}, "build_time": 5.0, "storage_capacity": 20,
	},
	"laboratory": {
		"name": "建造实验室", "description": "科学研究设施，产出应用科研点。",
		"resource_cost": {"iron": 200, "copper": 80}, "tech_requirement": "laboratory", "requires_zone": true,
		"worker_capacity": 5, "per_worker_output": {},
		"consumption": {"electricity": 8.0}, "build_time": 6.0, "storage_capacity": 0,
	},
	"academy": {
		"name": "建造科学院", "description": "最高级别的科研机构，产出理论科研点。",
		"resource_cost": {"iron": 1500, "copper": 500, "rare_mineral": 100}, "tech_requirement": "academy", "requires_zone": true,
		"worker_capacity": 8, "per_worker_output": {},
		"consumption": {"electricity": 25.0, "food": 5.0}, "build_time": 10.0, "storage_capacity": 0,
	},
	"deep_shelter": {
		"name": "建造深地庇护所", "description": "深入地下的巨型避难系统。",
		"resource_cost": {"iron": 400, "copper": 100}, "tech_requirement": "deep_shelter", "requires_zone": true,
		"worker_capacity": 0, "per_worker_output": {},
		"consumption": {"electricity": 3.0}, "build_time": 8.0, "storage_capacity": 100,
	},
	"radiation_shield": {
		"name": "建造辐射屏蔽站", "description": "为所在区域提供辐射防护。",
		"resource_cost": {"iron": 300, "rare_mineral": 20}, "tech_requirement": "radiation_armor", "requires_zone": true,
		"worker_capacity": 0, "per_worker_output": {},
		"consumption": {"electricity": 5.0}, "build_time": 7.0, "storage_capacity": 0,
	},
	"storage_vault": {
		"name": "建造脱水仓", "description": "专用脱水人口存储设施。",
		"resource_cost": {"iron": 80, "copper": 20}, "tech_requirement": "survival_shelter", "requires_zone": true,
		"worker_capacity": 0, "per_worker_output": {},
		"consumption": {"electricity": 0.5}, "build_time": 3.0, "storage_capacity": 100,
	},
	"large_storage_vault": {
		"name": "建造大型脱水仓", "description": "大规模脱水人口存储设施。",
		"resource_cost": {"iron": 200, "copper": 60}, "tech_requirement": "deep_shelter", "requires_zone": true,
		"worker_capacity": 0, "per_worker_output": {},
		"consumption": {"electricity": 2.0}, "build_time": 6.0, "storage_capacity": 500,
	},
	"research_institute": {
		"name": "建造研究院", "description": "基础科研设施，产出基础科研点。",
		"resource_cost": {"iron": 150, "copper": 30}, "tech_requirement": "basic_metallurgy", "requires_zone": true,
		"worker_capacity": 5, "per_worker_output": {},
		"consumption": {"electricity": 5.0}, "build_time": 4.0, "storage_capacity": 0,
	},
	"observatory_station": {
		"name": "建造天文观测站", "description": "持续积累带时间戳的测角资料；只有实际运转的观测站才能提高轨道预测层级。",
		"resource_cost": {"iron": 250, "copper": 100}, "tech_requirement": "observatory", "requires_zone": true,
		"worker_capacity": 4, "per_worker_output": {},
		"consumption": {"electricity": 8.0}, "build_time": 7.0, "storage_capacity": 0,
	},
}

const _DEFAULT_STORAGE_CAPACITY: Dictionary = {
	"shelter": 20,
	"deep_shelter": 100,
	"storage_vault": 100,
	"large_storage_vault": 500,
}


var current_state: CivilizationState = CivilizationState.NORMAL
var available_decisions: Dictionary = {}
var active_policies: Array = []
var cooldowns: Dictionary = {}
var enacted_history: Array = []
var _next_building_id: int = 1
var _config: Dictionary = {}
var _building_storage_capacity: Dictionary = {}
var _dehydrate_keep_fraction: float = 0.01


func _init(p_config: Dictionary = {}) -> void:
	_config = p_config
	_build_decisions(p_config)

	var buildings_config: Dictionary = p_config.get("buildings", {})
	if not buildings_config.is_empty():
		_building_storage_capacity.clear()
		for btype in buildings_config:
			var bdata: Dictionary = buildings_config[btype]
			var cap: int = bdata.get("storage_capacity", 0)
			if cap > 0:
				_building_storage_capacity[btype] = cap
	else:
		_building_storage_capacity = _DEFAULT_STORAGE_CAPACITY.duplicate()

	_dehydrate_keep_fraction = p_config.get("population", {}).get("dehydrate_keep_fraction", 0.01)


func _build_decisions(p_config: Dictionary) -> void:
	available_decisions.clear()
	var buildings_config: Dictionary = p_config.get("buildings", {})
	var building_defs: Dictionary = buildings_config if not buildings_config.is_empty() else _DEFAULT_BUILDINGS

	for btype in building_defs:
		var bdata: Dictionary = building_defs[btype]
		var decision_id: String = "build_" + btype
		var decision: Decision = Decision.new(
			decision_id,
			bdata.get("name", decision_id),
			bdata.get("description", ""),
			"construction",
			bdata.get("resource_cost", {}),
			bdata.get("tech_requirement", ""),
			bdata.get("effects", {}),
			0.0,
			bdata.get("requires_zone", true),
			btype,
			bdata.get("worker_capacity", 0),
			bdata.get("per_worker_output", {}),
			bdata.get("consumption", {}),
			bdata.get("build_time", 3.0),
			bdata.get("storage_capacity", 0),
		)
		available_decisions[decision_id] = decision

	# 政策类
	var dehydrate_dec: Decision = Decision.new(
		"dehydrate", "全民脱水",
		"应对极端恶劣环境，将人口脱水存入库存。",
		"policy", {}, "", {
			"civilization": "进入脱水状态",
			"consumption": "-80%",
			"production": "-90%",
		}
	)
	available_decisions["dehydrate"] = dehydrate_dec

	var rehydrate_dec: Decision = Decision.new(
		"rehydrate", "浸泡复苏",
		"将库存中的脱水人口全部唤醒，恢复正常运作。",
		"policy", {}, "", {
			"civilization": "恢复正常状态",
		}
	)
	available_decisions["rehydrate"] = rehydrate_dec

	available_decisions["boom"] = Decision.new(
		"boom", "大生育计划",
		"消耗500食物，人口增长速度提高200%。再次点击可结束计划。",
		"policy", {"food": 500}, "", {
			"growth": "+200%", "food": "启用时消耗500",
		}
	)
	available_decisions["rationing"] = Decision.new(
		"rationing", "配给制",
		"食物消耗减少50%，但生产效率降低20%，社会安定度持续下降。",
		"policy", {}, "", {
			"food_consumption": "-50%", "efficiency": "-20%", "stability": "下降",
		}
	)
	available_decisions["industrial_drive"] = Decision.new(
		"industrial_drive", "工业强心剂",
		"所有建筑与科研产出提高150%，人口健康和社会安定度持续下降。",
		"policy", {}, "", {
			"production": "+150%", "health": "下降", "stability": "大幅下降",
		}
	)


func get_next_building_id() -> int:
	var bid: int = _next_building_id
	_next_building_id += 1
	return bid


func get_construction_decisions() -> Array:
	var result: Array = []
	for d in available_decisions.values():
		var dec: Decision = d as Decision
		if dec.category == "construction":
			result.append(dec)
	return result


func get_visible_construction_decisions(p_tech_tree) -> Array:
	var result: Array = []
	for decision in get_construction_decisions():
		if decision.tech_requirement.is_empty():
			result.append(decision)
		elif p_tech_tree != null and p_tech_tree.is_unlocked(decision.tech_requirement):
			result.append(decision)
	return result


func get_policy_decisions() -> Array:
	var result: Array = []
	for d in available_decisions.values():
		var dec: Decision = d as Decision
		if dec.category == "policy":
			result.append(dec)
	return result


func _check_policy_conditions(p_policy_id: String, p_entities = null) -> Dictionary:
	if p_policy_id == "dehydrate":
		if current_state == CivilizationState.DEHYDRATED:
			return {"success": false, "message": "当前已经是脱水状态"}
		if p_entities != null and p_entities.population.total <= 0:
			return {"success": false, "message": "没有活跃人口可以脱水"}
	elif p_policy_id == "rehydrate":
		if current_state != CivilizationState.DEHYDRATED:
			return {"success": false, "message": "目前不在脱水状态，无需浸泡"}
	elif p_policy_id in ["boom", "rationing", "industrial_drive"]:
		if current_state == CivilizationState.DEHYDRATED and p_policy_id not in active_policies:
			return {"success": false, "message": "脱水状态下无法开启该政策"}
	return {"success": true, "message": ""}


func can_execute(p_decision_id: String, p_entities, p_tech_tree = null,
		p_zone_manager = null, p_zone_id: int = -1) -> Dictionary:
	var decision: Decision = available_decisions.get(p_decision_id)
	if decision == null:
		return {"success": false, "message": "未知的决策"}

	if cooldowns.has(p_decision_id) and cooldowns[p_decision_id] > 0.0:
		var remaining: float = cooldowns[p_decision_id]
		return {"success": false, "message": "冷却中（剩余 %.0f 天）" % remaining}

	if not decision.tech_requirement.is_empty():
		if p_tech_tree == null:
			return {"success": false, "message": "无法验证前置科技"}
		if not p_tech_tree.is_unlocked(decision.tech_requirement):
			var tech_node = p_tech_tree.get_node(decision.tech_requirement)
			var tech_name: String = tech_node.name if tech_node != null else decision.tech_requirement
			return {"success": false, "message": "需要先研发科技「%s」" % tech_name}

	var is_active_policy := decision.category == "policy" and p_decision_id in active_policies
	if not is_active_policy:
		for res_name in decision.resource_cost:
			var cost: float = decision.resource_cost[res_name]
			var current: float = p_entities.get_resource(res_name)
			if current < cost:
				return {"success": false, "message": "资源「%s」不足（需求：%d，当前：%d）" % [res_name, int(cost), int(current)]}

	if decision.category == "policy":
		return _check_policy_conditions(p_decision_id, p_entities)
	if decision.category == "construction" and decision.requires_zone:
		if p_zone_manager == null:
			return {"success": false, "message": "区域管理器不可用"}
		if p_zone_id < 0:
			return {"success": false, "message": "需要选择一个建造区域"}
		if p_zone_manager.get_zone(p_zone_id) == null:
			return {"success": false, "message": "建造区域不存在"}

	return {"success": true, "message": ""}


func execute_decision(p_decision_id: String, p_entities, p_tech_tree = null,
		p_zone_manager = null, p_zone_id: int = -1) -> Dictionary:
	var can: Dictionary = can_execute(p_decision_id, p_entities, p_tech_tree, p_zone_manager, p_zone_id)
	if not can["success"]:
		return {"success": false, "message": can["message"], "building_id": -1}

	var decision: Decision = available_decisions[p_decision_id] as Decision

	if decision.category == "construction":
		var construction_result: Dictionary = _execute_construction(decision, p_entities, p_zone_manager, p_zone_id)
		if construction_result.get("success", false):
			_commit_decision(p_decision_id, decision)
		return construction_result
	elif decision.category == "policy":
		var is_active_policy := p_decision_id in active_policies
		if not is_active_policy and not _consume_costs_atomically(decision, p_entities):
			return {"success": false, "message": "资源状态已变化，决策未执行", "building_id": -1}
		var policy_result: Dictionary = _execute_policy(p_decision_id, p_entities)
		if policy_result.get("success", false):
			_commit_decision(p_decision_id, decision)
		return policy_result

	return {"success": false, "message": "未知决策类型", "building_id": -1}


func _commit_decision(p_decision_id: String, p_decision: Decision) -> void:
	if p_decision.cooldown > 0.0:
		cooldowns[p_decision_id] = p_decision.cooldown
	enacted_history.append(p_decision_id)


func _consume_costs_atomically(p_decision: Decision, p_entities) -> bool:
	var consumed: Dictionary = {}
	for res_name in p_decision.resource_cost:
		var cost: float = float(p_decision.resource_cost[res_name])
		if cost < 0.0 or not p_entities.consume_resource(res_name, cost):
			for rollback_name in consumed:
				p_entities.produce_resource(rollback_name, consumed[rollback_name])
			return false
		consumed[res_name] = cost
	return true


func _execute_construction(p_decision: Decision, p_entities,
		p_zone_manager, p_zone_id: int) -> Dictionary:
	var building_id: int = _next_building_id

	var storage_cap: int = p_decision.storage_capacity
	if storage_cap <= 0:
		storage_cap = _building_storage_capacity.get(p_decision.building_type, 0)

	var BuildingClass = _EM.GameBuilding
	var building = BuildingClass.new(
		building_id,
		p_decision.name.replace("建造", ""),
		p_decision.building_type,
		p_zone_id if p_decision.requires_zone else -1,
		p_decision.worker_capacity,
		p_decision.per_worker_output.duplicate(),
		p_decision.consumption.duplicate(),
		p_decision.build_time,
		0.0,
		true,
		false,
		100.0,
		100.0,
		storage_cap,
	)

	if not _consume_costs_atomically(p_decision, p_entities):
		return {"success": false, "message": "资源状态已变化，建造未开始", "building_id": -1}
	if p_decision.requires_zone and not p_zone_manager.add_building_to_zone(p_zone_id, building_id):
		for res_name in p_decision.resource_cost:
			p_entities.produce_resource(res_name, float(p_decision.resource_cost[res_name]))
		return {"success": false, "message": "区域注册失败，资源已退回", "building_id": -1}
	p_entities.add_building(building)
	_next_building_id += 1

	var msg: String = "开始建造 " + building.building_name
	return {
		"success": true,
		"message": msg,
		"building_id": building_id,
	}


func _execute_policy(p_policy_id: String, p_entities) -> Dictionary:
	if p_policy_id == "dehydrate":
		current_state = CivilizationState.DEHYDRATED
		var pop = p_entities.population
		var keep: int = max(1, int(pop.total * _dehydrate_keep_fraction))
		var to_store: int = pop.total - keep
		if to_store <= 0:
			return {"success": true, "message": "人口过少，无需脱水", "building_id": -1}

		var can_store: int = pop.get_storable_amount()
		var actual_store: int = min(to_store, can_store)
		if actual_store > 0:
			p_entities.prepare_population_reduction(pop.total - actual_store)
			var stored_result: Dictionary = p_entities.store_population_from_idle(actual_store)
			if not stored_result.get("success", false):
				current_state = CivilizationState.NORMAL
				return {"success": false, "message": stored_result.get("message", "人口脱水失败"), "building_id": -1}

		var exposed: int = to_store - actual_store
		if exposed > 0:
			return {"success": true, "message": "脱水启动：%d人入库，%d人暴露" % [actual_store, exposed], "building_id": -1}
		return {"success": true, "message": "脱水启动：%d人入库" % actual_store, "building_id": -1}

	elif p_policy_id == "rehydrate":
		current_state = CivilizationState.NORMAL
		var pop = p_entities.population
		var stored: int = pop.stored_population
		if stored > 0:
			pop.retrieve_population(stored)
		return {"success": true, "message": "浸泡复苏完成：%d人苏醒" % stored, "building_id": -1}

	elif p_policy_id in ["boom", "rationing", "industrial_drive"]:
		var decision: Decision = available_decisions[p_policy_id] as Decision
		if p_policy_id in active_policies:
			active_policies.erase(p_policy_id)
			return {"success": true, "message": "已结束政策「%s」" % decision.name, "building_id": -1}
		active_policies.append(p_policy_id)
		return {"success": true, "message": "已开启政策「%s」" % decision.name, "building_id": -1}

	return {"success": false, "message": "未知政策", "building_id": -1}


func update_cooldowns(p_dt: float, p_time_scale: float) -> void:
	var game_days: float = p_dt * p_time_scale
	var expired: Array = []
	for did in cooldowns:
		cooldowns[did] = cooldowns[did] - game_days
		if cooldowns[did] <= 0.0:
			expired.append(did)
	for did in expired:
		cooldowns.erase(did)


func get_state() -> Dictionary:
	var state_str: String = "normal"
	if current_state == CivilizationState.DEHYDRATED:
		state_str = "dehydrated"
	var result: Dictionary
	result = {
		"current_state": state_str,
		"active_policies": active_policies.duplicate(),
		"cooldowns": cooldowns.duplicate(),
		"enacted_history": enacted_history.duplicate(),
		"next_building_id": _next_building_id,
	}
	return result


func load_state(data: Dictionary) -> void:
	var state_str: String = data.get("current_state", "normal")
	if state_str == "dehydrated":
		current_state = CivilizationState.DEHYDRATED
	else:
		current_state = CivilizationState.NORMAL

	active_policies = data.get("active_policies", [])
	cooldowns = data.get("cooldowns", {})
	enacted_history = data.get("enacted_history", [])
	_next_building_id = data.get("next_building_id", 1)
