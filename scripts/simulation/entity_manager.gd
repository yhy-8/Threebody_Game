class_name EntityManager
extends RefCounted
## 实体管理器 — 管理建筑、资源和人口


const RESOURCE_DISPLAY_NAMES: Dictionary = {
	"iron": "铁矿",
	"copper": "铜矿",
	"rare_mineral": "稀有矿物",
	"algae_fuel": "藻类燃料",
	"fossil_fuel": "化石燃料",
	"electricity": "电力",
	"food": "食物",
}

const RESOURCE_COLORS: Dictionary = {
	"iron": Color(0.706, 0.706, 0.784),
	"copper": Color(0.863, 0.627, 0.392),
	"rare_mineral": Color(0.706, 0.471, 1.0),
	"algae_fuel": Color(0.392, 0.784, 0.471),
	"fossil_fuel": Color(0.627, 0.549, 0.392),
	"electricity": Color(1.0, 0.863, 0.314),
	"food": Color(0.392, 1.0, 0.588),
}

const RESOURCE_GROUPS: Dictionary = {
	"矿物": ["iron", "copper", "rare_mineral"],
	"能源": ["algae_fuel", "fossil_fuel", "electricity"],
	"食物": ["food"],
}


# ── GameResource ──────────────────────────────────────

class GameResource:
	var name: String
	var display_name: String
	var amount: float
	var max_storage: float

	func _init(p_name: String, p_amount: float = 0.0, p_max_storage: float = 10000.0) -> void:
		name = p_name
		display_name = RESOURCE_DISPLAY_NAMES.get(p_name, p_name)
		amount = p_amount
		max_storage = p_max_storage

	func add(p_amount: float) -> void:
		if p_amount <= 0.0:
			return
		amount = min(max_storage, amount + p_amount)

	func consume(p_amount: float) -> bool:
		if p_amount < 0.0:
			return false
		if p_amount == 0.0:
			return true
		if amount >= p_amount:
			amount -= p_amount
			return true
		return false


# ── PopulationManager ─────────────────────────────────

class PopulationManager:
	var total: int
	var breeders: int
	var stored_population: int
	var storage_capacity: int
	var automation_multiplier: float
	var base_growth_per_breeder: float
	var natural_growth_rate: float
	var food_per_person_per_day: float
	var _starvation_threshold: float
	var _starvation_rate: float
	var _dehydrate_food_rate: float
	var _growth_accumulator: float
	var _starvation_loss_accumulator: float
	var stored_loss_accumulator: float
	var exposed_loss_accumulator: float
	var policy_growth_multiplier: float
	var policy_food_multiplier: float

	func _init(p_initial_population: int = 100, p_config: Dictionary = {}) -> void:
		total = p_initial_population
		breeders = 0
		stored_population = 0
		storage_capacity = 0
		automation_multiplier = 1.0
		_growth_accumulator = 0.0
		_starvation_loss_accumulator = 0.0
		stored_loss_accumulator = 0.0
		exposed_loss_accumulator = 0.0

		var pop_config: Dictionary = p_config.get("population", {})
		base_growth_per_breeder = pop_config.get("base_growth_per_breeder", 0.05)
		natural_growth_rate = pop_config.get("natural_growth_rate", 0.001)
		food_per_person_per_day = pop_config.get("food_per_person_per_day", 0.1)
		_starvation_threshold = pop_config.get("starvation_threshold", 0.5)
		_starvation_rate = pop_config.get("starvation_rate", 0.01)
		_dehydrate_food_rate = pop_config.get("dehydrate_food_consumption_rate", 0.2)
		policy_growth_multiplier = 1.0
		policy_food_multiplier = 1.0

	func get_idle(p_total_building_workers: int) -> int:
		return max(0, total - breeders - p_total_building_workers)

	func get_storable_amount() -> int:
		return max(0, storage_capacity - stored_population)

	func store_population(count: int) -> Dictionary:
		if count < 0:
			return {"success": false, "message": "人口数量不能为负数"}
		var available: int = get_storable_amount()
		if count > available:
			var msg: String = "库存容量不足（可存入 %d 人）" % available
			return {"success": false, "message": msg}
		if count > total:
			var msg: String = "活跃人口不足（当前 %d 人）" % total
			return {"success": false, "message": msg}
		stored_population += count
		total -= count
		return {"success": true, "message": ""}

	func retrieve_population(count: int) -> Dictionary:
		if count < 0:
			return {"success": false, "message": "人口数量不能为负数"}
		if count > stored_population:
			var msg: String = "库存中只有 %d 人" % stored_population
			return {"success": false, "message": msg}
		stored_population -= count
		total += count
		return {"success": true, "message": ""}

	func update(p_dt_days: float, p_food_available: float, p_dehydrated: bool = false) -> Dictionary:
		var consumption_rate: float = _dehydrate_food_rate if p_dehydrated else 1.0
		var food_needed: float = total * food_per_person_per_day * p_dt_days * consumption_rate * policy_food_multiplier
		var food_consumed: float = min(food_needed, p_food_available)
		var food_satisfaction: float = food_consumed / max(food_needed, 0.001)

		var population_loss: int = 0
		if food_satisfaction < _starvation_threshold:
			var starvation: float = (_starvation_threshold - food_satisfaction) * total * _starvation_rate * p_dt_days
			_starvation_loss_accumulator += starvation
			population_loss = mini(maxi(0, total - 1), int(_starvation_loss_accumulator))
			if population_loss > 0:
				total -= population_loss
				_starvation_loss_accumulator -= population_loss

		var growth: float = breeders * base_growth_per_breeder * p_dt_days * food_satisfaction * policy_growth_multiplier
		var idle: int = max(0, total - breeders)
		growth += idle * natural_growth_rate * p_dt_days * food_satisfaction * policy_growth_multiplier

		_growth_accumulator += growth
		var int_growth: int = int(_growth_accumulator)
		if int_growth > 0:
			total += int_growth
			_growth_accumulator -= int_growth

		var result: Dictionary
		result = {
			"food_consumed": food_consumed,
			"growth": growth,
			"population_loss": population_loss,
		}
		return result

	func get_state() -> Dictionary:
		var result: Dictionary
		result = {
			"total": total,
			"breeders": breeders,
			"stored_population": stored_population,
			"storage_capacity": storage_capacity,
			"automation_multiplier": automation_multiplier,
			"growth_accumulator": _growth_accumulator,
			"starvation_loss_accumulator": _starvation_loss_accumulator,
			"stored_loss_accumulator": stored_loss_accumulator,
			"exposed_loss_accumulator": exposed_loss_accumulator,
			"policy_growth_multiplier": policy_growth_multiplier,
			"policy_food_multiplier": policy_food_multiplier,
		}
		return result

	func load_state(data: Dictionary) -> void:
		total = data.get("total", 100)
		breeders = data.get("breeders", 0)
		stored_population = data.get("stored_population", 0)
		storage_capacity = data.get("storage_capacity", 0)
		if "assignments" in data:
			var assignments: Dictionary = data["assignments"]
			breeders += assignments.get("breeding", 0)
		automation_multiplier = data.get("automation_multiplier", 1.0)
		_growth_accumulator = data.get("growth_accumulator", 0.0)
		_starvation_loss_accumulator = maxf(0.0, float(data.get("starvation_loss_accumulator", 0.0)))
		stored_loss_accumulator = maxf(0.0, float(data.get("stored_loss_accumulator", 0.0)))
		exposed_loss_accumulator = maxf(0.0, float(data.get("exposed_loss_accumulator", 0.0)))
		policy_growth_multiplier = data.get("policy_growth_multiplier", 1.0)
		policy_food_multiplier = data.get("policy_food_multiplier", 1.0)


# ── GameBuilding ──────────────────────────────────────

class GameBuilding:
	var id: int
	var building_name: String
	var building_type: String
	var level: int
	var zone_id: int
	var worker_capacity: int
	var assigned_workers: int
	var per_worker_output: Dictionary
	var consumption: Dictionary
	var durability: float
	var max_durability: float
	var build_time: float
	var build_progress: float
	var under_construction: bool
	var heat_resistance: float
	var cold_resistance: float
	var radiation_resistance: float
	var storage_capacity: int
	var active: bool
	var destroyed: bool
	var last_run_ratio: float
	var last_output_rate: Dictionary

	func _init(p_id: int, p_name: String, p_building_type: String,
			p_zone_id: int = -1, p_worker_capacity: int = 0,
			p_per_worker_output: Dictionary = {}, p_consumption: Dictionary = {},
			p_build_time: float = 0.0, p_build_progress: float = 0.0,
			p_under_construction: bool = false, p_active: bool = true,
			p_durability: float = 100.0, p_max_durability: float = 100.0,
			p_storage_capacity: int = 0) -> void:
		id = p_id
		building_name = p_name
		building_type = p_building_type
		level = 1
		zone_id = p_zone_id
		worker_capacity = p_worker_capacity
		assigned_workers = 0
		per_worker_output = p_per_worker_output
		consumption = p_consumption
		durability = p_durability
		max_durability = p_max_durability
		build_time = p_build_time
		build_progress = p_build_progress
		under_construction = p_under_construction
		active = p_active
		destroyed = false
		last_run_ratio = 0.0
		last_output_rate = {}
		heat_resistance = 60.0
		cold_resistance = -80.0
		radiation_resistance = 5.0
		storage_capacity = p_storage_capacity

	func get_output(p_automation_multiplier: float = 1.0, p_zone_efficiency: float = 1.0) -> Dictionary:
		if not active or destroyed or under_construction:
			return {}
		if worker_capacity <= 0:
			return {}
		var effective_workers: int = min(assigned_workers, worker_capacity)
		if effective_workers <= 0:
			return {}
		var durability_ratio: float = durability / max_durability if max_durability > 0.0 else 0.0
		var output: Dictionary = {}
		for resource in per_worker_output:
			var per_worker: float = per_worker_output[resource]
			output[resource] = effective_workers * per_worker * durability_ratio * p_automation_multiplier * p_zone_efficiency
		return output

	func get_consumption() -> Dictionary:
		if not active or destroyed or under_construction:
			return {}
		return consumption.duplicate()

	func get_saturation() -> float:
		if worker_capacity <= 0:
			return 1.0
		return min(1.0, float(assigned_workers) / float(worker_capacity))

	func take_damage(p_amount: float) -> void:
		durability = max(0.0, durability - p_amount)
		if durability <= 0.0:
			active = false
			destroyed = true

	func repair(p_amount: float) -> void:
		if destroyed:
			return
		durability = min(max_durability, durability + p_amount)
		if durability > 0.0:
			active = true

	func apply_environment_damage(p_zone_temp: float, p_zone_radiation: float, p_dt: float,
			p_heat_coeff: float = 0.02, p_cold_coeff: float = 0.01, p_rad_coeff: float = 0.03) -> void:
		if under_construction:
			return
		var damage: float = 0.0
		if p_zone_temp > heat_resistance:
			damage += (p_zone_temp - heat_resistance) * p_heat_coeff * p_dt
		if p_zone_temp < cold_resistance:
			damage += (cold_resistance - p_zone_temp) * p_cold_coeff * p_dt
		if p_zone_radiation > radiation_resistance:
			damage += (p_zone_radiation - radiation_resistance) * p_rad_coeff * p_dt
		if damage > 0.0:
			take_damage(damage)

	func advance_construction(p_dt: float) -> void:
		if not under_construction:
			return
		if build_time <= 0.0:
			under_construction = false
			build_progress = build_time
			active = true
			return
		var speed: float
		if worker_capacity > 0:
			var workers: int = min(assigned_workers, worker_capacity)
			speed = float(workers) / float(worker_capacity)
		else:
			speed = 1.0
		build_progress += speed * p_dt
		if build_progress >= build_time:
			under_construction = false
			build_progress = build_time
			active = true


# ── EntityManager ─────────────────────────────────────

var buildings: Array = []
var resources: Dictionary = {}
var population: PopulationManager
var global_efficiency: float = 1.0
var policy_efficiency_multiplier: float = 1.0
var policy_output_multiplier: float = 1.0
var social_stability: float = 1.0
var population_health: float = 1.0
var external_reserved_workers: int = 0
var _active_policy_ids: Array = []
var _config: Dictionary = {}
var _next_building_id: int = 1


func _init(p_config: Dictionary = {}) -> void:
	_config = p_config
	var initial_pop: int = 100
	if p_config.has("initial_entities"):
		var ie: Dictionary = p_config["initial_entities"]
		initial_pop = ie.get("population", 100)
	population = PopulationManager.new(initial_pop, p_config)
	_init_defaults(p_config)
	_next_building_id = 1


func _init_defaults(p_config: Dictionary) -> void:
	var default_res: Dictionary = {
		"iron": 200.0, "copper": 30.0, "rare_mineral": 0.0,
		"algae_fuel": 100.0, "fossil_fuel": 0.0, "electricity": 0.0,
		"food": 300.0,
	}
	var max_storage_map: Dictionary = {
		"iron": 5000.0, "copper": 3000.0, "rare_mineral": 1000.0,
		"algae_fuel": 3000.0, "fossil_fuel": 3000.0, "electricity": 500.0,
		"food": 8000.0,
	}

	if p_config.has("initial_entities") and p_config["initial_entities"].has("resources"):
		var res_list: Array = p_config["initial_entities"]["resources"]
		for res_item in res_list:
			var ri: Dictionary = res_item
			var res_name: String = ri.get("name", "")
			if res_name in default_res:
				default_res[res_name] = ri.get("amount", default_res[res_name])
				if ri.has("max_storage"):
					max_storage_map[res_name] = ri["max_storage"]

	for key in default_res:
		var res: GameResource = GameResource.new(key, default_res[key], max_storage_map.get(key, 1000.0))
		resources[key] = res


func add_building(p_building: GameBuilding) -> void:
	buildings.append(p_building)


func remove_building(p_building_id: int) -> void:
	var to_remove: Array = []
	for b in buildings:
		var building: GameBuilding = b as GameBuilding
		if building.id == p_building_id:
			to_remove.append(b)
	for b in to_remove:
		buildings.erase(b)


func get_building(p_building_id: int) -> GameBuilding:
	for b in buildings:
		var building: GameBuilding = b as GameBuilding
		if building.id == p_building_id:
			return building
	return null


func get_buildings_in_zone(p_zone_id: int) -> Array:
	var result: Array = []
	for b in buildings:
		var building: GameBuilding = b as GameBuilding
		if building.zone_id == p_zone_id:
			result.append(building)
	return result


func get_resource(p_name: String) -> float:
	if p_name == "population":
		return float(population.total)
	if resources.has(p_name):
		var res: GameResource = resources[p_name] as GameResource
		return res.amount
	return 0.0


func consume_resource(p_name: String, p_amount: float) -> bool:
	if p_amount < 0.0:
		return false
	if p_name == "population":
		return false
	if resources.has(p_name):
		var res: GameResource = resources[p_name] as GameResource
		return res.consume(p_amount)
	return false


func produce_resource(p_name: String, p_amount: float) -> void:
	if p_amount <= 0.0:
		return
	if resources.has(p_name):
		var res: GameResource = resources[p_name] as GameResource
		res.add(p_amount)


func get_building_count() -> int:
	var count: int = 0
	for b in buildings:
		var building: GameBuilding = b as GameBuilding
		if not building.destroyed:
			count += 1
	return count


func get_active_building_count() -> int:
	var count: int = 0
	for b in buildings:
		var building: GameBuilding = b as GameBuilding
		if building.active and not building.destroyed:
			count += 1
	return count


func get_buildings_by_type(p_building_type: String) -> Array:
	var result: Array = []
	for b in buildings:
		var building: GameBuilding = b as GameBuilding
		if building.building_type == p_building_type and building.active and not building.destroyed:
			result.append(building)
	return result


func get_total_building_workers() -> int:
	var total: int = 0
	for b in buildings:
		var building: GameBuilding = b as GameBuilding
		if not building.destroyed and (building.active or building.under_construction):
			total += building.assigned_workers
	return total


func get_idle_population() -> int:
	return population.get_idle(get_total_building_workers() + external_reserved_workers)


func set_external_reserved_workers(p_count: int) -> void:
	external_reserved_workers = clampi(p_count, 0, population.total)


func store_population_from_idle(p_count: int) -> Dictionary:
	if p_count < 0:
		return {"success": false, "message": "人口数量不能为负数"}
	var idle: int = get_idle_population()
	if p_count > idle:
		return {"success": false, "message": "闲置人口不足（需要 %d，仅剩 %d）" % [p_count, idle]}
	return population.store_population(p_count)


func prepare_population_reduction(p_target_total: int) -> void:
	# 明确撤岗顺序：闲置人口先离开；仍超额时先撤生育岗位，再按建筑 ID 倒序撤岗。
	p_target_total = maxi(0, p_target_total)
	var excess: int = maxi(0, population.breeders + get_total_building_workers() + external_reserved_workers - p_target_total)
	var reserved_reduction := mini(external_reserved_workers, excess)
	external_reserved_workers -= reserved_reduction
	excess -= reserved_reduction
	var breeder_reduction: int = mini(population.breeders, excess)
	population.breeders -= breeder_reduction
	excess -= breeder_reduction
	if excess <= 0:
		return
	var ordered_buildings: Array = buildings.duplicate()
	ordered_buildings.sort_custom(func(a, b): return a.id > b.id)
	for building in ordered_buildings:
		if excess <= 0:
			break
		var remove_count: int = mini(building.assigned_workers, excess)
		building.assigned_workers -= remove_count
		excess -= remove_count


func enforce_population_invariants() -> void:
	population.total = maxi(0, population.total)
	population.breeders = maxi(0, population.breeders)
	population.stored_population = clampi(population.stored_population, 0, population.storage_capacity)
	for building in buildings:
		building.assigned_workers = clampi(building.assigned_workers, 0, building.worker_capacity)
	prepare_population_reduction(population.total)


func set_policy_effects(p_policy_ids: Array) -> void:
	_active_policy_ids = p_policy_ids.duplicate()
	population.policy_growth_multiplier = 3.0 if "boom" in _active_policy_ids else 1.0
	population.policy_food_multiplier = 0.5 if "rationing" in _active_policy_ids else 1.0
	policy_efficiency_multiplier = 0.8 if "rationing" in _active_policy_ids else 1.0
	policy_output_multiplier = 2.5 if "industrial_drive" in _active_policy_ids else 1.0


func assign_worker_to_building(p_building_id: int, p_count: int) -> Dictionary:
	if p_count <= 0:
		return {"success": false, "message": "分配人数必须大于零"}
	var b: GameBuilding = get_building(p_building_id)
	if b == null:
		return {"success": false, "message": "建筑不存在"}
	if b.destroyed:
		return {"success": false, "message": "建筑已损毁"}
	var idle: int = get_idle_population()
	if p_count > idle:
		var msg: String = "闲置人口不足（需要 %d，仅剩 %d）" % [p_count, idle]
		return {"success": false, "message": msg}
	var space: int = b.worker_capacity - b.assigned_workers
	if p_count > space:
		var msg: String = "建筑容量不足（仅剩 %d 个空余岗位）" % space
		return {"success": false, "message": msg}
	b.assigned_workers += p_count
	return {"success": true, "message": ""}


func unassign_worker_from_building(p_building_id: int, p_count: int) -> Dictionary:
	if p_count <= 0:
		return {"success": false, "message": "撤回人数必须大于零"}
	var b: GameBuilding = get_building(p_building_id)
	if b == null:
		return {"success": false, "message": "建筑不存在"}
	if p_count > b.assigned_workers:
		var msg: String = "当前建筑只有 %d 人" % b.assigned_workers
		return {"success": false, "message": msg}
	b.assigned_workers -= p_count
	return {"success": true, "message": ""}


func assign_breeders(p_count: int) -> Dictionary:
	if p_count <= 0:
		return {"success": false, "message": "分配人数必须大于零"}
	var idle: int = get_idle_population()
	if p_count > idle:
		var msg: String = "闲置人口不足（需要 %d，仅剩 %d）" % [p_count, idle]
		return {"success": false, "message": msg}
	population.breeders += p_count
	return {"success": true, "message": ""}


func unassign_breeders(p_count: int) -> Dictionary:
	if p_count <= 0:
		return {"success": false, "message": "撤回人数必须大于零"}
	if p_count > population.breeders:
		var msg: String = "当前只有 %d 人在生育" % population.breeders
		return {"success": false, "message": msg}
	population.breeders -= p_count
	return {"success": true, "message": ""}


func get_electricity_balance() -> Dictionary:
	var generation: float = 0.0
	var consumption: float = 0.0
	var effective_automation := (
		population.automation_multiplier * global_efficiency
		* policy_efficiency_multiplier * policy_output_multiplier
	)
	for b in buildings:
		var building: GameBuilding = b as GameBuilding
		if not building.active or building.destroyed:
			continue
		var output: Dictionary = _get_full_output_rate(building, effective_automation)
		var base_ratio: float = _get_base_run_ratio(building, null, false)
		generation += output.get("electricity", 0.0) * base_ratio * _get_input_affordability(building, base_ratio, false)
		var cons: Dictionary = building.get_consumption()
		consumption += cons.get("electricity", 0.0) * base_ratio
	var result: Dictionary
	result = {"generation": generation, "consumption": consumption}
	return result


func update(p_env_params: Dictionary, p_zone_manager = null, p_dt: float = 0.016, p_dehydrated: bool = false) -> void:
	var heat: float = p_env_params.get("heat_level", 0.5)
	if heat > 0.8:
		global_efficiency = max(0.5, global_efficiency - 0.01 * p_dt)
	elif heat < 0.2:
		global_efficiency = max(0.3, global_efficiency - 0.02 * p_dt)
	else:
		global_efficiency = min(1.0, global_efficiency + 0.01 * p_dt)

	if "rationing" in _active_policy_ids:
		social_stability = max(0.35, social_stability - 0.01 * p_dt)
	if "industrial_drive" in _active_policy_ids:
		social_stability = max(0.2, social_stability - 0.015 * p_dt)
		population_health = max(0.25, population_health - 0.012 * p_dt)
	if "rationing" not in _active_policy_ids and "industrial_drive" not in _active_policy_ids:
		social_stability = min(1.0, social_stability + 0.003 * p_dt)
	if "industrial_drive" not in _active_policy_ids:
		population_health = min(1.0, population_health + 0.002 * p_dt)

	population.storage_capacity = 0
	for b in buildings:
		var building: GameBuilding = b as GameBuilding
		if building.active and not building.destroyed and not building.under_construction:
			population.storage_capacity += building.storage_capacity
	if population.stored_population > population.storage_capacity:
		var overflow: int = population.stored_population - population.storage_capacity
		population.retrieve_population(overflow)

	_process_buildings(p_dt, p_zone_manager, p_dehydrated)

	if p_zone_manager != null:
		var damage_config: Dictionary = _config.get("damage_rates", {})
		var heat_coeff: float = damage_config.get("heat_damage_coefficient", 0.02)
		var cold_coeff: float = damage_config.get("cold_damage_coefficient", 0.01)
		var rad_coeff: float = damage_config.get("radiation_damage_coefficient", 0.03)
		for b in buildings:
			var building: GameBuilding = b as GameBuilding
			if building.destroyed or building.zone_id < 0:
				continue
			var zone = p_zone_manager.get_zone(building.zone_id)
			if zone != null:
				var protection: Dictionary = get_zone_protection(building.zone_id)
				var environment_factor: float = 1.0 - float(protection.get("environment", 0.0))
				var effective_radiation: float = zone.radiation * (1.0 - float(protection.get("radiation", 0.0)))
				building.apply_environment_damage(
					lerpf(20.0, zone.temperature, environment_factor), effective_radiation,
					p_dt, heat_coeff, cold_coeff, rad_coeff
				)

	for b in buildings:
		var building: GameBuilding = b as GameBuilding
		if building.under_construction:
			building.advance_construction(p_dt)

	var food_available: float = get_resource("food")
	var pop_result: Dictionary = population.update(p_dt, food_available, p_dehydrated)
	var food_consumed: float = pop_result.get("food_consumed", 0.0)
	if food_consumed > 0.0:
		consume_resource("food", food_consumed)
	if pop_result.get("population_loss", 0) > 0:
		enforce_population_invariants()


func _process_buildings(p_dt: float, p_zone_manager = null, p_dehydrated: bool = false) -> void:
	var base_ratios: Dictionary = {}
	var generated_power: float = 0.0
	var demanded_power: float = 0.0
	for building in buildings:
		building.last_run_ratio = 0.0
		building.last_output_rate = {}

	# 发电设施先按可支付燃料逐座结算，后续用电设施只能分享真实发电量。
	for building in buildings:
		var full_output: Dictionary = _get_full_output_rate(building, _get_effective_automation(), _get_zone_yield(building, p_zone_manager))
		if not full_output.has("electricity"):
			continue
		var base_ratio: float = _get_base_run_ratio(building, p_zone_manager, p_dehydrated)
		base_ratio *= _get_input_affordability(building, p_dt * base_ratio, false)
		building.last_run_ratio = clampf(base_ratio, 0.0, 1.0)
		_consume_non_electric_inputs(building, p_dt * building.last_run_ratio)
		_record_building_outputs(building, full_output, p_dt, true)
		generated_power += float(building.last_output_rate.get("electricity", 0.0))

	# 再计算非发电设施的潜在运行率和即时电力需求。
	for building in buildings:
		var full_output: Dictionary = _get_full_output_rate(building, _get_effective_automation(), _get_zone_yield(building, p_zone_manager))
		if full_output.has("electricity"):
			continue
		var base_ratio: float = _get_base_run_ratio(building, p_zone_manager, p_dehydrated)
		base_ratio *= _get_input_affordability(building, p_dt * base_ratio, false)
		base_ratios[building.id] = base_ratio
		if building.consumption.has("electricity"):
			demanded_power += float(building.consumption["electricity"]) * base_ratio

	var power_ratio: float = minf(1.0, generated_power / demanded_power) if demanded_power > 0.0 else 1.0
	var consumed_power: float = 0.0
	for building in buildings:
		var full_output: Dictionary = _get_full_output_rate(building, _get_effective_automation(), _get_zone_yield(building, p_zone_manager))
		if full_output.has("electricity"):
			continue
		var run_ratio: float = float(base_ratios.get(building.id, 0.0))
		if building.consumption.has("electricity"):
			run_ratio *= power_ratio
		run_ratio *= _get_input_affordability(building, p_dt * run_ratio, false)
		building.last_run_ratio = clampf(run_ratio, 0.0, 1.0)
		_consume_non_electric_inputs(building, p_dt * building.last_run_ratio)
		if building.consumption.has("electricity"):
			consumed_power += float(building.consumption["electricity"]) * building.last_run_ratio
		_record_building_outputs(building, full_output, p_dt, false)
	if resources.has("electricity"):
		resources["electricity"].amount = clampf(generated_power - consumed_power, 0.0, resources["electricity"].max_storage)


func _consume_non_electric_inputs(p_building: GameBuilding, p_scaled_days: float) -> void:
	for resource in p_building.consumption:
		if resource == "electricity":
			continue
		var amount: float = float(p_building.consumption[resource]) * p_scaled_days
		if amount > 0.0:
			consume_resource(resource, amount)


func _record_building_outputs(p_building: GameBuilding, p_full_output: Dictionary,
		p_dt: float, p_include_electricity: bool) -> void:
	for resource in p_full_output:
		var output_rate: float = float(p_full_output[resource]) * p_building.last_run_ratio
		p_building.last_output_rate[resource] = output_rate
		if resource != "electricity" or p_include_electricity:
			if resource != "electricity":
				produce_resource(resource, output_rate * p_dt)


func _get_effective_automation() -> float:
	return population.automation_multiplier * global_efficiency * policy_efficiency_multiplier * policy_output_multiplier


func get_research_building_rate(p_building: GameBuilding, p_base_rate: float) -> float:
	return maxf(0.0, p_base_rate) * p_building.last_run_ratio * _get_effective_automation()


func _get_full_output_rate(p_building: GameBuilding, p_automation: float, p_zone_yield: float = 1.0) -> Dictionary:
	var output: Dictionary = {}
	for resource in p_building.per_worker_output:
		output[resource] = (
			float(p_building.worker_capacity) * float(p_building.per_worker_output[resource])
			* p_automation * p_zone_yield
		)
	return output


func _get_base_run_ratio(p_building: GameBuilding, p_zone_manager, p_dehydrated: bool) -> float:
	if not p_building.active or p_building.destroyed or p_building.under_construction:
		return 0.0
	var ratio: float = p_building.get_saturation()
	if p_building.worker_capacity > 0 and p_building.assigned_workers <= 0:
		return 0.0
	if p_building.max_durability > 0.0:
		ratio *= clampf(p_building.durability / p_building.max_durability, 0.0, 1.0)
	if p_zone_manager != null and p_building.zone_id >= 0:
		var zone = p_zone_manager.get_zone(p_building.zone_id)
		if zone != null:
			ratio *= zone.get_work_efficiency()
	var dehydrate_config: Dictionary = _config.get("dehydrate", {})
	var exempt_types: Array = dehydrate_config.get("exempt_types", ["storage_vault", "large_storage_vault", "shelter", "deep_shelter"])
	if p_dehydrated and p_building.building_type not in exempt_types:
		ratio *= float(dehydrate_config.get("output_multiplier", 0.1))
	return clampf(ratio, 0.0, 1.0)


func _get_input_affordability(p_building: GameBuilding, p_scaled_days: float, p_include_electricity: bool) -> float:
	if p_scaled_days <= 0.0:
		return 1.0
	var affordability: float = 1.0
	for resource in p_building.consumption:
		if resource == "electricity" and not p_include_electricity:
			continue
		var required: float = float(p_building.consumption[resource]) * p_scaled_days
		if required > 0.0:
			affordability = minf(affordability, get_resource(resource) / required)
	return clampf(affordability, 0.0, 1.0)


func _get_zone_yield(p_building: GameBuilding, p_zone_manager) -> float:
	if p_zone_manager == null or p_building.zone_id < 0:
		return 1.0
	var zone = p_zone_manager.get_zone(p_building.zone_id)
	if zone == null:
		return 0.0
	match p_building.building_type:
		"iron_mine": return maxf(0.0, float(zone.resource_deposits.get("iron", 0.0)))
		"copper_mine": return maxf(0.0, float(zone.resource_deposits.get("copper", 0.0)))
		"rare_mine": return maxf(0.0, float(zone.resource_deposits.get("rare_mineral", 0.0)))
		"farm": return maxf(0.0, zone.fertility)
		"algae_collector", "algae_food_synth": return maxf(0.0, zone.algae_density)
	return 1.0


func get_zone_protection(p_zone_id: int) -> Dictionary:
	var environment_protection: float = 0.0
	var radiation_protection: float = 0.0
	for building in get_buildings_in_zone(p_zone_id):
		if building.last_run_ratio <= 0.0:
			continue
		if building.building_type == "shelter":
			environment_protection = maxf(environment_protection, 0.2 * building.last_run_ratio)
		elif building.building_type == "deep_shelter":
			environment_protection = maxf(environment_protection, 0.5 * building.last_run_ratio)
		elif building.building_type == "radiation_shield":
			radiation_protection = maxf(radiation_protection, 0.5 * building.last_run_ratio)
	return {"environment": environment_protection, "radiation": radiation_protection}


func get_average_protection(p_zone_manager) -> Dictionary:
	if p_zone_manager == null or p_zone_manager.zones.is_empty():
		return {"environment": 0.0, "radiation": 0.0}
	var total_weight: float = 0.0
	var environment_total: float = 0.0
	var radiation_total: float = 0.0
	for zone in p_zone_manager.zones:
		var protection: Dictionary = get_zone_protection(zone.zone_id)
		environment_total += float(protection.get("environment", 0.0)) * zone.area_weight
		radiation_total += float(protection.get("radiation", 0.0)) * zone.area_weight
		total_weight += zone.area_weight
	return {
		"environment": environment_total / total_weight if total_weight > 0.0 else 0.0,
		"radiation": radiation_total / total_weight if total_weight > 0.0 else 0.0,
	}


func apply_technology_effects(p_tech_tree) -> void:
	var has_radiation_armor: bool = p_tech_tree != null and p_tech_tree.is_unlocked("radiation_armor")
	var has_high_alloy: bool = p_tech_tree != null and p_tech_tree.is_unlocked("high_alloy")
	for building in buildings:
		var target_max: float = 200.0 if has_high_alloy else 100.0
		if not is_equal_approx(building.max_durability, target_max):
			var durability_ratio: float = building.durability / building.max_durability if building.max_durability > 0.0 else 1.0
			building.max_durability = target_max
			building.durability = target_max * clampf(durability_ratio, 0.0, 1.0)
		building.heat_resistance = 78.0 if has_high_alloy else 60.0
		building.cold_resistance = -104.0 if has_high_alloy else -80.0
		building.radiation_resistance = 5.0 * (1.5 if has_radiation_armor else 1.0) * (1.3 if has_high_alloy else 1.0)


func get_state() -> Dictionary:
	var buildings_data: Array = []
	for b in buildings:
		var bd: GameBuilding = b as GameBuilding
		buildings_data.append({
			"id": bd.id,
			"name": bd.building_name,
			"type": bd.building_type,
			"zone_id": bd.zone_id,
			"durability": bd.durability,
			"max_durability": bd.max_durability,
			"active": bd.active,
			"destroyed": bd.destroyed,
			"worker_capacity": bd.worker_capacity,
			"assigned_workers": bd.assigned_workers,
			"per_worker_output": bd.per_worker_output.duplicate(),
			"consumption": bd.consumption.duplicate(),
			"build_time": bd.build_time,
			"build_progress": bd.build_progress,
			"under_construction": bd.under_construction,
			"storage_capacity": bd.storage_capacity,
			"heat_resistance": bd.heat_resistance,
			"cold_resistance": bd.cold_resistance,
			"radiation_resistance": bd.radiation_resistance,
			"last_run_ratio": bd.last_run_ratio,
		})

	var resources_data: Dictionary = {}
	for key in resources:
		var res: GameResource = resources[key] as GameResource
		resources_data[key] = res.amount

	var result: Dictionary
	result = {
		"buildings_count": get_building_count(),
		"active_buildings": get_active_building_count(),
		"resources": resources_data,
		"population": population.get_state(),
		"avg_efficiency": global_efficiency,
		"social_stability": social_stability,
		"population_health": population_health,
		"active_policy_ids": _active_policy_ids.duplicate(),
		"buildings": buildings_data,
	}
	return result


func load_state(data: Dictionary) -> void:
	buildings.clear()
	global_efficiency = data.get("avg_efficiency", 1.0)
	social_stability = data.get("social_stability", 1.0)
	population_health = data.get("population_health", 1.0)
	set_policy_effects(data.get("active_policy_ids", []))

	var resources_data: Dictionary = data.get("resources", {})
	for name in resources_data:
		if resources.has(name):
			var res: GameResource = resources[name] as GameResource
			res.amount = resources_data[name]

	if data.has("population"):
		population.load_state(data["population"])

	var buildings_data: Array = data.get("buildings", [])
	for b_data in buildings_data:
		var bd: Dictionary = b_data
		var building: GameBuilding = GameBuilding.new(
			bd.get("id", 0),
			bd.get("name", ""),
			bd.get("type", ""),
			bd.get("zone_id", -1),
			bd.get("worker_capacity", 0),
			bd.get("per_worker_output", {}),
			bd.get("consumption", {}),
			bd.get("build_time", 0.0),
			bd.get("build_progress", 0.0),
			bd.get("under_construction", false),
			bd.get("active", true),
			bd.get("durability", 100.0),
			bd.get("max_durability", 100.0),
			bd.get("storage_capacity", 0),
		)
		building.destroyed = bd.get("destroyed", false)
		building.assigned_workers = bd.get("assigned_workers", 0)
		building.heat_resistance = bd.get("heat_resistance", 60.0)
		building.cold_resistance = bd.get("cold_resistance", -80.0)
		building.radiation_resistance = bd.get("radiation_resistance", 5.0)
		building.last_run_ratio = bd.get("last_run_ratio", 0.0)
		buildings.append(building)
	enforce_population_invariants()
