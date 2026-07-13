extends Node
## 游戏状态 — 持有并协调所有模拟子系统

signal state_updated()
signal research_completed(tech_id: String, tech_name: String)

# Preload all simulation scripts — their return values are GDScript resources used for .new()
const ThreeBodySimScript = preload("res://scripts/simulation/three_body.gd")
const EntityManagerScript = preload("res://scripts/simulation/entity_manager.gd")
const TechTreeScript = preload("res://scripts/simulation/tech_tree.gd")
const DecisionManagerScript = preload("res://scripts/simulation/decision_manager.gd")
const PlanetZoneManagerScript = preload("res://scripts/simulation/planet_zones.gd")

# ── 子系统引用 ──
var environment       ## ThreeBodySimulation
var entities          ## EntityManager
var tech_tree         ## TechTree
var decision_manager  ## DecisionManager
var planet_zones      ## PlanetZoneManager

# ── 游戏状态 ────────────────────────────────────────
var game_time: float = 0.0
var time_scale: float = 1.0
var paused: bool = false
var game_over: bool = false
var game_started: bool = false
var universe_name: String = "未命名宇宙"
var last_autosave_day: int = -1

# ── 配置 ────────────────────────────────────────────
var config: Dictionary = {}
var _env_config: Dictionary = {}
var _research_config: Dictionary = {}
var _storage_damage_config: Dictionary = {}
var _time_scale_min: float = 0.1
var _time_scale_max: float = 10.0

# ── UI 显示数据 ─────────────────────────────────────
var research_output_rate: Dictionary = {
	"basic": 0.0,
	"applied": 0.0,
	"theoretical": 0.0,
}
var current_screen: String = ""


func new_game(p_universe_name: String, p_config: Dictionary = {}) -> void:
	reset()
	universe_name = p_universe_name
	if p_config.is_empty():
		p_config = _default_config()
	config = p_config
	_env_config = config.get("environment", {})
	_research_config = config.get("research", {})
	_storage_damage_config = config.get("storage_damage", {})
	var sim_config: Dictionary = config.get("simulation", {})
	_time_scale_min = sim_config.get("time_scale_min", 0.1)
	_time_scale_max = sim_config.get("time_scale_max", 10.0)

	environment = ThreeBodySimScript.new()
	entities = EntityManagerScript.new(config)
	tech_tree = TechTreeScript.new(config)
	decision_manager = DecisionManagerScript.new(config)
	planet_zones = PlanetZoneManagerScript.new(_env_config)

	game_started = true
	game_over = false
	game_time = 0.0
	_init_zone_temperatures()


func reset() -> void:
	time_scale = 1.0
	paused = false
	game_over = false
	game_started = false
	game_time = 0.0
	environment = null
	entities = null
	tech_tree = null
	decision_manager = null
	planet_zones = null


func toggle_pause() -> void:
	paused = not paused
	EventBus.game_paused.emit(paused)


func set_time_scale(p_scale: float) -> void:
	time_scale = clamp(p_scale, _time_scale_min, _time_scale_max)
	EventBus.time_scale_changed.emit(time_scale)


func update(p_dt: float) -> void:
	if paused or game_over or not game_started:
		return
	if environment == null:
		return

	var dehydrated: bool = false
	if decision_manager != null:
		dehydrated = (decision_manager.current_state == decision_manager.CivilizationState.DEHYDRATED)

	environment.time_scale = time_scale
	environment.update(p_dt)

	var stars_data: Array = environment.get_stars_data()
	var planet_position: Vector3 = environment.get_planet_position()

	planet_zones.update(p_dt, time_scale, stars_data, planet_position)

	var avg_env: Dictionary = planet_zones.get_average_environment()
	var raw_env: Dictionary = environment.get_environment_params()

	var env_params: Dictionary = {
		"light_intensity": avg_env.get("light_intensity", raw_env.get("light_intensity", 0.0)),
		"heat_level": avg_env.get("light_intensity", 0.0) * 6.0,
		"temperature": avg_env.get("temperature", raw_env.get("temperature", -273.15)),
		"radiation": avg_env.get("radiation", raw_env.get("radiation", 0.0)),
		"stability": raw_env.get("stability", 0.0),
	}

	var game_days_dt: float = p_dt * time_scale
	entities.update(env_params, planet_zones, game_days_dt, dehydrated)

	_process_research_output(game_days_dt)

	if dehydrated:
		_process_storage_damage(game_days_dt)

	decision_manager.update_cooldowns(p_dt, time_scale)

	game_time += game_days_dt
	state_updated.emit()


func _process_research_output(p_game_days_dt: float) -> void:
	var dehydrated: bool = false
	if decision_manager != null:
		dehydrated = (decision_manager.current_state == decision_manager.CivilizationState.DEHYDRATED)
	var dehydrate_mult: float = _research_config.get("dehydrate_multiplier", 0.1) if dehydrated else 1.0
	var pop_divisor: float = _research_config.get("basic_population_divisor", 500.0)
	var institute_output: float = _research_config.get("institute_output_per_day", 1.0)
	var lab_output: float = _research_config.get("laboratory_output_per_day", 2.0)
	var academy_output: float = _research_config.get("academy_output_per_day", 1.0)
	var alpha: float = _research_config.get("ema_alpha", 0.05)
	var auto_mult: float = _research_config.get("automation_multiplier", 1.3)

	var frame_output: Dictionary = {
		"basic": 0.0,
		"applied": 0.0,
		"theoretical": 0.0,
	}

	# 基础科研：人口产出
	var pop: float = entities.get_resource("population")
	var basic_rate: float = pop / pop_divisor
	var basic_output: float = basic_rate * dehydrate_mult * p_game_days_dt
	tech_tree.produce_research("basic", basic_output)
	frame_output["basic"] = basic_rate * dehydrate_mult

	# 研究院产出
	var institutes: Array = entities.get_buildings_by_type("research_institute")
	for inst in institutes:
		var building = inst
		var durability_ratio: float = building.durability / building.max_durability if building.max_durability > 0.0 else 0.0
		var worker_ratio: float = building.get_saturation()
		var zone_eff: float = 1.0
		if building.zone_id >= 0:
			var zone = planet_zones.get_zone(building.zone_id)
			if zone != null:
				zone_eff = zone.get_work_efficiency()
		var efficiency: float = durability_ratio * worker_ratio * zone_eff * dehydrate_mult
		frame_output["basic"] = frame_output["basic"] + institute_output * efficiency
		tech_tree.produce_research("basic", institute_output * efficiency * p_game_days_dt)

	# 实验室产出
	var labs: Array = entities.get_buildings_by_type("laboratory")
	for lab_item in labs:
		var building = lab_item
		var durability_ratio: float = building.durability / building.max_durability if building.max_durability > 0.0 else 0.0
		var worker_ratio: float = building.get_saturation()
		var zone_eff: float = 1.0
		if building.zone_id >= 0:
			var zone = planet_zones.get_zone(building.zone_id)
			if zone != null:
				zone_eff = zone.get_work_efficiency()
		var efficiency: float = durability_ratio * worker_ratio * zone_eff * dehydrate_mult
		frame_output["applied"] = frame_output["applied"] + lab_output * efficiency
		tech_tree.produce_research("applied", lab_output * efficiency * p_game_days_dt)

	# 科学院产出
	var academies: Array = entities.get_buildings_by_type("academy")
	for acad_item in academies:
		var building = acad_item
		var durability_ratio: float = building.durability / building.max_durability if building.max_durability > 0.0 else 0.0
		var worker_ratio: float = building.get_saturation()
		var zone_eff: float = 1.0
		if building.zone_id >= 0:
			var zone = planet_zones.get_zone(building.zone_id)
			if zone != null:
				zone_eff = zone.get_work_efficiency()
		var efficiency: float = durability_ratio * worker_ratio * zone_eff * dehydrate_mult
		frame_output["theoretical"] = frame_output["theoretical"] + academy_output * efficiency
		tech_tree.produce_research("theoretical", academy_output * efficiency * p_game_days_dt)

	# EMA 平滑
	for rtype in frame_output:
		research_output_rate[rtype] = (
			alpha * frame_output[rtype]
			+ (1.0 - alpha) * research_output_rate[rtype]
		)

	# 自动化科技解锁
	if tech_tree.researching_tech_id.is_empty():
		var auto_node = tech_tree.get_node("automation")
		if auto_node != null and auto_node.unlocked and entities.population.automation_multiplier < auto_mult:
			entities.population.automation_multiplier = auto_mult


func _process_storage_damage(p_game_days_dt: float) -> void:
	var pop = entities.population
	var sdc: Dictionary = _storage_damage_config

	var active_storage_buildings: Array = []
	for b in entities.buildings:
		var building = b
		if building.active and not building.destroyed and not building.under_construction and building.storage_capacity > 0:
			active_storage_buildings.append(building)

	if active_storage_buildings.is_empty() and pop.stored_population > 0:
		pop.stored_population = 0
		return

	var total_stored: int = pop.stored_population
	if total_stored <= 0:
		return

	var total_capacity: int = 0
	for b in active_storage_buildings:
		var building = b
		total_capacity += building.storage_capacity

	var total_loss: float = 0.0

	var ext_cold: float = sdc.get("extreme_cold_threshold", -80.0)
	var ext_heat: float = sdc.get("extreme_heat_threshold", 100.0)
	var ext_base: float = sdc.get("extreme_base_loss_rate", 0.005)
	var ext_coeff: float = sdc.get("extreme_excess_coefficient", 0.04)
	var mild_cold: float = sdc.get("mild_cold_threshold", -10.0)
	var mild_heat: float = sdc.get("mild_heat_threshold", 60.0)
	var mild_coeff: float = sdc.get("mild_loss_coefficient", 0.002)
	var rad_high: float = sdc.get("radiation_high_threshold", 5.0)
	var rad_low: float = sdc.get("radiation_low_threshold", 2.0)
	var rad_high_base: float = sdc.get("radiation_high_base_rate", 0.003)
	var rad_high_coeff: float = sdc.get("radiation_high_excess_coefficient", 0.02)
	var rad_low_coeff: float = sdc.get("radiation_low_coefficient", 0.001)

	for b in active_storage_buildings:
		var building = b
		if total_capacity <= 0:
			break
		var fraction: float = float(building.storage_capacity) / float(total_capacity)
		var stored_here: float = float(total_stored) * fraction

		if building.zone_id < 0:
			continue

		var zone = planet_zones.get_zone(building.zone_id)
		if zone == null:
			continue

		var loss_rate: float = 0.0
		if zone.temperature < ext_cold:
			var excess: float = (ext_cold - zone.temperature) / 100.0
			loss_rate += ext_base + excess * ext_coeff
		elif zone.temperature > ext_heat:
			var excess: float = (zone.temperature - ext_heat) / 100.0
			loss_rate += ext_base + excess * ext_coeff
		elif zone.temperature < mild_cold:
			var factor: float = (mild_cold - zone.temperature) / 70.0
			loss_rate += factor * mild_coeff
		elif zone.temperature > mild_heat:
			var factor: float = (zone.temperature - mild_heat) / 40.0
			loss_rate += factor * mild_coeff

		if zone.radiation > rad_high:
			var excess: float = (zone.radiation - rad_high) / 10.0
			loss_rate += rad_high_base + excess * rad_high_coeff
		elif zone.radiation > rad_low:
			var factor: float = (zone.radiation - rad_low) / 3.0
			loss_rate += factor * rad_low_coeff

		total_loss += stored_here * loss_rate * p_game_days_dt

	if total_loss > 0.0:
		pop.stored_population = max(0, int(float(pop.stored_population) - total_loss))

	# 暴露人口损耗
	var exposed: int = max(0, pop.total - max(1, int(float(pop.total + pop.stored_population) * 0.01)))
	if exposed > 0:
		var avg_env: Dictionary = planet_zones.get_average_environment()
		var exposed_loss_rate: float = 0.0
		var temp: float = avg_env.get("temperature", 20.0)
		var rad: float = avg_env.get("radiation", 0.0)
		if temp < ext_cold or temp > ext_heat:
			exposed_loss_rate = sdc.get("exposed_extreme_loss_rate", 0.1)
		elif temp < mild_cold or temp > mild_heat:
			exposed_loss_rate = sdc.get("exposed_harsh_loss_rate", 0.02)
		if rad > rad_high:
			exposed_loss_rate += sdc.get("exposed_radiation_high_rate", 0.05)
		elif rad > rad_low:
			exposed_loss_rate += sdc.get("exposed_radiation_low_rate", 0.01)
		if exposed_loss_rate > 0.0:
			var loss: int = int(float(exposed) * exposed_loss_rate * p_game_days_dt)
			if loss > 0:
				pop.total = max(1, pop.total - loss)


func _init_zone_temperatures() -> void:
	var stars_data: Array = environment.get_stars_data()
	var planet_position: Vector3 = environment.get_planet_position()

	planet_zones.light_to_temp_scale = 500.0
	planet_zones.initialize_temperatures(stars_data, planet_position)

	var total_weight: float = 0.0
	var avg_raw_light: float = 0.0
	var avg_terrain_mod: float = 0.0
	var max_raw_light: float = 0.0

	for z_item in planet_zones.zones:
		var z = z_item
		var w: float = z.area_weight
		var terrain_mod: float = PlanetZoneManagerScript.TERRAIN_THERMAL_MODIFIER.get(z.terrain_type, 0.0)
		var raw_light: float = (z.temperature - planet_zones.base_temperature - terrain_mod) / 500.0
		avg_raw_light += raw_light * w
		avg_terrain_mod += terrain_mod * w
		total_weight += w
		if raw_light > max_raw_light:
			max_raw_light = raw_light

	if total_weight > 0.0:
		avg_raw_light /= total_weight
		avg_terrain_mod /= total_weight

	var target_avg_temp: float = _env_config.get("target_start_temp", 20.0)
	if avg_raw_light > 1e-6:
		planet_zones.light_to_temp_scale = (
			(target_avg_temp - planet_zones.base_temperature - avg_terrain_mod) / avg_raw_light
		)
	else:
		planet_zones.light_to_temp_scale = 500.0

	var target_peak: float = _env_config.get("target_peak_light", 0.85)
	if max_raw_light > 1e-6:
		planet_zones.light_norm_divisor = max_raw_light / target_peak
	else:
		planet_zones.light_norm_divisor = 1.0

	planet_zones.initialize_temperatures(stars_data, planet_position)


func get_state() -> Dictionary:
	if environment == null:
		return {"game_started": false}

	var avg_env: Dictionary = planet_zones.get_average_environment()
	var raw_env: Dictionary = environment.get_environment_params()

	var stars_render_data: Array = []
	for star in environment.stars:
		var s = star
		var trail_data: Array = []
		for t in s.trail:
			var tv: Vector3 = t as Vector3
			trail_data.append({"x": tv.x, "y": tv.y, "z": tv.z})
		stars_render_data.append({
			"position": {"x": s.position.x, "y": s.position.y, "z": s.position.z},
			"velocity": {"x": s.velocity.x, "y": s.velocity.y, "z": s.velocity.z},
			"color": s.color,
			"radius": s.radius,
			"mass": s.mass,
			"is_planet": s.is_planet,
			"trail": trail_data,
		})

	var result: Dictionary
	result = {
		"game_time": game_time,
		"paused": paused,
		"game_over": game_over,
		"game_started": game_started,
		"universe_name": universe_name,
		"research_output_rate": research_output_rate.duplicate(),
		"environment": {
			"stars": stars_render_data,
			"params": {
				"light_intensity": avg_env.get("light_intensity", 0.0),
				"heat_level": avg_env.get("light_intensity", 0.0) * 6.0,
				"temperature": avg_env.get("temperature", -273.15),
				"radiation": avg_env.get("radiation", 0.0),
				"stability": raw_env.get("stability", 0.0),
			},
		},
		"entities": entities.get_state(),
		"technology": tech_tree.get_state(),
		"decision": decision_manager.get_state(),
		"planet_zones": {
			"rotation_angle": planet_zones.rotation_angle,
			"zones_summary": planet_zones.get_all_zones_summary(),
		},
	}
	return result


func to_dict() -> Dictionary:
	var stars_data: Array = []
	for star in environment.stars:
		var s = star
		stars_data.append({
			"mass": s.mass,
			"position": {"x": s.position.x, "y": s.position.y, "z": s.position.z},
			"velocity": {"x": s.velocity.x, "y": s.velocity.y, "z": s.velocity.z},
			"color": {"r": s.color.r, "g": s.color.g, "b": s.color.b, "a": s.color.a},
			"radius": s.radius,
			"is_planet": s.is_planet,
		})

	var result: Dictionary
	result = {
		"time": game_time,
		"paused": paused,
		"game_over": game_over,
		"universe_name": universe_name,
		"stars": stars_data,
		"entities": entities.get_state(),
		"technology": tech_tree.get_state(),
		"decision": decision_manager.get_state(),
		"planet_zones": planet_zones.get_state(),
		"time_scale": time_scale,
	}
	return result


func from_dict(data: Dictionary) -> void:
	reset()
	game_time = data.get("time", 0.0)
	paused = data.get("paused", false)
	game_over = data.get("game_over", false)
	universe_name = data.get("universe_name", "未命名宇宙")
	game_started = true

	environment = ThreeBodySimScript.new()
	environment.stars.clear()

	var stars_data: Array = data.get("stars", [])
	if not stars_data.is_empty():
		for sd in stars_data:
			var s: Dictionary = sd
			var pos: Dictionary = s["position"]
			var vel: Dictionary = s["velocity"]
			var col: Dictionary = s["color"]
			# Access inner class via the preloaded script
			var StarDataClass = ThreeBodySimScript.StarData
			var star = StarDataClass.new(
				s.get("mass", 1000.0),
				Vector3(pos.get("x", 0.0), pos.get("y", 0.0), pos.get("z", 0.0)),
				Vector3(vel.get("x", 0.0), vel.get("y", 0.0), vel.get("z", 0.0)),
				Color(col.get("r", 1.0), col.get("g", 1.0), col.get("b", 1.0), col.get("a", 1.0)),
				s.get("radius", 20.0),
				s.get("is_planet", false),
			)
			environment.stars.append(star)

	environment.time_scale = data.get("time_scale", 1.0)

	if config.is_empty():
		config = _default_config()
		_env_config = config.get("environment", {})

	entities = EntityManagerScript.new(config)
	if data.has("entities"):
		entities.load_state(data["entities"])

	tech_tree = TechTreeScript.new(config)
	if data.has("technology"):
		tech_tree.load_state(data["technology"])

	decision_manager = DecisionManagerScript.new(config)
	if data.has("decision"):
		decision_manager.load_state(data["decision"])
	elif data.has("policy"):
		var policy_data: Dictionary = data["policy"]
		decision_manager.load_state({"current_state": policy_data.get("current_state", "normal")})

	planet_zones = PlanetZoneManagerScript.new(_env_config)
	if data.has("planet_zones"):
		planet_zones.load_state(data["planet_zones"])


func _default_config() -> Dictionary:
	var result: Dictionary
	result = {
		"simulation": {"time_scale_min": 0.1, "time_scale_max": 10.0},
		"environment": {
			"rotation_speed": 15.0, "thermal_inertia": 0.08,
			"diffusion_rate": 0.15, "dark_side_scatter": 0.25,
			"target_start_temp": 20.0, "target_peak_light": 0.85,
		},
		"research": {
			"basic_population_divisor": 500.0, "institute_output_per_day": 1.0,
			"laboratory_output_per_day": 2.0, "academy_output_per_day": 1.0,
			"dehydrate_multiplier": 0.1, "ema_alpha": 0.05, "automation_multiplier": 1.3,
		},
		"storage_damage": {
			"extreme_cold_threshold": -80, "extreme_heat_threshold": 100,
			"extreme_base_loss_rate": 0.005, "extreme_excess_coefficient": 0.04,
			"mild_cold_threshold": -10, "mild_heat_threshold": 60,
			"mild_loss_coefficient": 0.002,
			"radiation_high_threshold": 5, "radiation_low_threshold": 2,
			"radiation_high_base_rate": 0.003, "radiation_high_excess_coefficient": 0.02,
			"radiation_low_coefficient": 0.001,
			"exposed_extreme_loss_rate": 0.1, "exposed_harsh_loss_rate": 0.02,
			"exposed_radiation_high_rate": 0.05, "exposed_radiation_low_rate": 0.01,
		},
		"damage_rates": {
			"heat_damage_coefficient": 0.02,
			"cold_damage_coefficient": 0.01,
			"radiation_damage_coefficient": 0.03,
		},
		"dehydrate": {
			"output_multiplier": 0.1,
			"exempt_types": ["storage_vault", "large_storage_vault", "shelter", "deep_shelter"],
		},
		"population": {
			"food_per_person_per_day": 0.1,
			"base_growth_per_breeder": 0.05,
			"natural_growth_rate": 0.001,
			"starvation_threshold": 0.5,
			"starvation_rate": 0.01,
			"dehydrate_food_consumption_rate": 0.2,
			"dehydrate_keep_fraction": 0.01,
		},
	}
	return result
