extends Node
## 游戏状态 — 持有并协调所有模拟子系统

signal state_updated()
signal research_completed(tech_id: String, tech_name: String)
signal developer_mode_changed(enabled: bool)

const SETTINGS_PATH := "res://settings.json"
const SAVE_SCHEMA_VERSION := 2
const FIXED_SIMULATION_STEP_DAYS := 0.02
const MAX_SIMULATION_SUBSTEPS := 512

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
var developer_mode: bool = false
var settings_return_scene: String = "res://scenes/main_menu/initial_menu.tscn"
var _simulation_accumulator: float = 0.0
var _autosave_elapsed_seconds: float = 0.0
var _runtime_settings: Dictionary = {}

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


func _ready() -> void:
	EventBus.screen_changed.connect(_on_screen_changed)
	_load_runtime_settings()
	_apply_runtime_settings()


func _process(p_delta: float) -> void:
	# GameState is an Autoload, so the simulation keeps advancing while the
	# player browses the technology, policy, zone, and starmap scenes.
	update(min(p_delta, 0.1))


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
	time_scale = clampf(float(_runtime_settings.get("time_scale", 1.0)), _time_scale_min, _time_scale_max)
	environment.time_scale = 1.0
	_connect_tech_tree_signals()
	_init_zone_temperatures()
	EventBus.game_started.emit(universe_name)


func reset() -> void:
	time_scale = 1.0
	paused = false
	game_over = false
	game_started = false
	game_time = 0.0
	last_autosave_day = -1
	_simulation_accumulator = 0.0
	_autosave_elapsed_seconds = 0.0
	environment = null
	entities = null
	tech_tree = null
	decision_manager = null
	planet_zones = null
	research_output_rate = {"basic": 0.0, "applied": 0.0, "theoretical": 0.0}


func toggle_pause() -> void:
	paused = not paused
	EventBus.game_paused.emit(paused)


func set_time_scale(p_scale: float) -> void:
	time_scale = clamp(p_scale, _time_scale_min, _time_scale_max)
	EventBus.time_scale_changed.emit(time_scale)


func set_developer_mode(p_enabled: bool) -> void:
	if developer_mode == p_enabled:
		return
	developer_mode = p_enabled
	developer_mode_changed.emit(developer_mode)
	state_updated.emit()


func can_access_starmap() -> bool:
	return developer_mode or (tech_tree != null and tech_tree.is_unlocked("telescope"))


func apply_developer_values(p_values: Dictionary) -> bool:
	if not developer_mode or not game_started or entities == null or tech_tree == null:
		return false

	var population_values: Dictionary = p_values.get("population", {})
	entities.population.total = maxi(0, int(population_values.get("total", entities.population.total)))
	entities.population.stored_population = maxi(0, int(population_values.get("stored", entities.population.stored_population)))
	entities.population.breeders = clampi(
		int(population_values.get("breeders", entities.population.breeders)),
		0,
		entities.population.total,
	)

	var resource_values: Dictionary = p_values.get("resources", {})
	for resource_id in resource_values:
		if entities.resources.has(resource_id):
			entities.resources[resource_id].amount = maxf(0.0, float(resource_values[resource_id]))

	var research_values: Dictionary = p_values.get("research", {})
	for research_id in research_values:
		if tech_tree.research_points.has(research_id):
			tech_tree.research_points[research_id] = maxf(0.0, float(research_values[research_id]))

	state_updated.emit()
	return true


func developer_fill_resources(p_amount: float = 100000.0) -> bool:
	if not developer_mode or entities == null:
		return false
	for resource in entities.resources.values():
		resource.amount = maxf(0.0, p_amount)
	state_updated.emit()
	return true


func developer_unlock_all_technologies() -> bool:
	if not developer_mode or tech_tree == null:
		return false
	for tech_node in tech_tree.nodes.values():
		tech_node.unlocked = true
		tech_node.researching = false
	tech_tree.researching_tech_id = ""
	tech_tree.research_progress.clear()
	state_updated.emit()
	return true


func _load_runtime_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK:
		return
	var data = json.get_data()
	if data is Dictionary:
		_runtime_settings = data.duplicate(true)
		developer_mode = data.get("developer_mode", false)


func reload_runtime_settings() -> void:
	_runtime_settings.clear()
	_load_runtime_settings()
	_apply_runtime_settings()


func _apply_runtime_settings() -> void:
	var fullscreen: bool = _runtime_settings.get("fullscreen", false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if _runtime_settings.get("vsync", true) else DisplayServer.VSYNC_DISABLED
	)
	var master_volume: float = clampf(float(_runtime_settings.get("master_volume", 0.8)), 0.0, 1.0)
	var master_bus: int = AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_volume_db(master_bus, linear_to_db(master_volume))
	if game_started:
		set_time_scale(float(_runtime_settings.get("time_scale", time_scale)))


func _on_screen_changed(p_screen_name: String) -> void:
	current_screen = p_screen_name


func _connect_tech_tree_signals() -> void:
	if tech_tree != null and not tech_tree.research_finished.is_connected(_on_research_finished):
		tech_tree.research_finished.connect(_on_research_finished)


func _on_research_finished(p_tech_id: String, p_tech_name: String) -> void:
	entities.apply_technology_effects(tech_tree)
	research_completed.emit(p_tech_id, p_tech_name)


func update(p_dt: float) -> void:
	if paused or game_over or not game_started:
		return
	if environment == null:
		return
	if p_dt <= 0.0:
		return
	if environment.has_collision():
		game_over = true
		paused = true
		EventBus.game_over.emit("天体发生碰撞，文明毁灭")
		state_updated.emit()
		return

	_simulation_accumulator += p_dt * time_scale
	var substeps: int = 0
	while _simulation_accumulator + 1e-9 >= FIXED_SIMULATION_STEP_DAYS and substeps < MAX_SIMULATION_SUBSTEPS:
		_advance_simulation(FIXED_SIMULATION_STEP_DAYS)
		_simulation_accumulator -= FIXED_SIMULATION_STEP_DAYS
		substeps += 1
		if game_over:
			break
	_process_autosave(p_dt)
	if substeps > 0:
		state_updated.emit()


func _advance_simulation(p_game_days_dt: float) -> void:

	var dehydrated: bool = false
	if decision_manager != null:
		dehydrated = (decision_manager.current_state == decision_manager.CivilizationState.DEHYDRATED)

	environment.time_scale = 1.0
	environment.update(p_game_days_dt)
	if environment.has_collision():
		game_over = true
		paused = true
		EventBus.game_over.emit("天体发生碰撞，文明毁灭")
		return

	var stars_data: Array = environment.get_stars_data()
	var planet_position: Vector3 = environment.get_planet_position()

	planet_zones.update(p_game_days_dt, 1.0, stars_data, planet_position)

	var avg_env: Dictionary = planet_zones.get_average_environment()
	var raw_env: Dictionary = environment.get_environment_params()

	var env_params: Dictionary = {
		"light_intensity": avg_env.get("light_intensity", raw_env.get("light_intensity", 0.0)),
		"heat_level": avg_env.get("light_intensity", 0.0) * 6.0,
		"temperature": avg_env.get("temperature", raw_env.get("temperature", -273.15)),
		"radiation": avg_env.get("radiation", raw_env.get("radiation", 0.0)),
		"stability": raw_env.get("stability", 0.0),
	}

	entities.set_policy_effects(decision_manager.active_policies)
	entities.apply_technology_effects(tech_tree)
	entities.update(env_params, planet_zones, p_game_days_dt, dehydrated)

	_process_research_output(p_game_days_dt)

	if dehydrated:
		_process_storage_damage(p_game_days_dt)

	decision_manager.update_cooldowns(p_game_days_dt, 1.0)

	game_time += p_game_days_dt


func _process_autosave(p_real_dt: float) -> void:
	var interval_minutes: int = int(_runtime_settings.get("auto_save_interval", 0))
	if interval_minutes <= 0:
		return
	_autosave_elapsed_seconds += p_real_dt
	if _autosave_elapsed_seconds < float(interval_minutes) * 60.0:
		return
	_autosave_elapsed_seconds = 0.0
	if SaveManager.save_game(self, "自动存档_Day%d" % maxi(1, int(game_time)), universe_name):
		last_autosave_day = int(game_time)


func _process_research_output(p_game_days_dt: float) -> void:
	var dehydrated: bool = false
	if decision_manager != null:
		dehydrated = (decision_manager.current_state == decision_manager.CivilizationState.DEHYDRATED)
	var dehydrate_mult: float = _research_config.get("dehydrate_multiplier", 0.1) if dehydrated else 1.0
	var policy_research_mult: float = 1.0
	if decision_manager != null:
		if "rationing" in decision_manager.active_policies:
			policy_research_mult *= 0.8
		if "industrial_drive" in decision_manager.active_policies:
			policy_research_mult *= 2.5
	dehydrate_mult *= policy_research_mult
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
		var output_rate: float = entities.get_research_building_rate(building, institute_output)
		frame_output["basic"] = frame_output["basic"] + output_rate
		tech_tree.produce_research("basic", output_rate * p_game_days_dt)

	# 实验室产出
	var labs: Array = entities.get_buildings_by_type("laboratory")
	for lab_item in labs:
		var building = lab_item
		var output_rate: float = entities.get_research_building_rate(building, lab_output)
		frame_output["applied"] = frame_output["applied"] + output_rate
		tech_tree.produce_research("applied", output_rate * p_game_days_dt)

	# 科学院产出
	var academies: Array = entities.get_buildings_by_type("academy")
	for acad_item in academies:
		var building = acad_item
		var output_rate: float = entities.get_research_building_rate(building, academy_output)
		frame_output["theoretical"] = frame_output["theoretical"] + output_rate
		tech_tree.produce_research("theoretical", output_rate * p_game_days_dt)

	# EMA 平滑
	var step_alpha: float = clampf(alpha * p_game_days_dt, 0.0, 1.0)
	for rtype in frame_output:
		research_output_rate[rtype] = (
			step_alpha * frame_output[rtype]
			+ (1.0 - step_alpha) * research_output_rate[rtype]
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
		pop.stored_loss_accumulator = 0.0
		return

	var total_stored: int = pop.stored_population
	if total_stored <= 0:
		return

	var total_capacity: int = 0
	for b in active_storage_buildings:
		var building = b
		total_capacity += building.storage_capacity

	var weighted_loss_rate: float = 0.0

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
		var protection: Dictionary = entities.get_zone_protection(building.zone_id)
		loss_rate *= 1.0 - maxf(float(protection.get("environment", 0.0)), float(protection.get("radiation", 0.0)))
		weighted_loss_rate += fraction * maxf(0.0, loss_rate)

	if weighted_loss_rate > 0.0:
		var effective_stored: float = maxf(0.0, float(pop.stored_population) - pop.stored_loss_accumulator)
		pop.stored_loss_accumulator += effective_stored * (1.0 - exp(-weighted_loss_rate * p_game_days_dt))
		var stored_loss: int = mini(pop.stored_population, int(pop.stored_loss_accumulator))
		if stored_loss > 0:
			pop.stored_population -= stored_loss
			pop.stored_loss_accumulator -= stored_loss

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
		var average_protection: Dictionary = entities.get_average_protection(planet_zones)
		exposed_loss_rate *= 1.0 - maxf(
			float(average_protection.get("environment", 0.0)),
			float(average_protection.get("radiation", 0.0))
		)
		if exposed_loss_rate > 0.0:
			var effective_exposed: float = maxf(0.0, float(exposed) - pop.exposed_loss_accumulator)
			pop.exposed_loss_accumulator += effective_exposed * (1.0 - exp(-exposed_loss_rate * p_game_days_dt))
			var loss: int = mini(maxi(0, pop.total - 1), int(pop.exposed_loss_accumulator))
			if loss > 0:
				pop.total -= loss
				pop.exposed_loss_accumulator -= loss
				entities.enforce_population_invariants()


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
			"trail": s.trail.map(func(point: Vector3): return {"x": point.x, "y": point.y, "z": point.z}),
		})

	var result: Dictionary
	result = {
		"schema_version": SAVE_SCHEMA_VERSION,
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
		"simulation_accumulator": _simulation_accumulator,
		"last_autosave_day": last_autosave_day,
		"research_output_rate": research_output_rate.duplicate(),
		"config": config.duplicate(true),
		"rng_state": str(environment.rng.state),
	}
	return result


func validate_serialized_state(data) -> bool:
	if not data is Dictionary:
		return false
	if not data.get("stars", []) is Array or data.get("stars", []).is_empty():
		return false
	for star_data in data.get("stars", []):
		if not star_data is Dictionary:
			return false
		if not star_data.get("position", null) is Dictionary:
			return false
		if not star_data.get("velocity", null) is Dictionary:
			return false
		if not star_data.get("color", null) is Dictionary:
			return false
		if star_data.has("trail") and not star_data["trail"] is Array:
			return false
	var entities_data = data.get("entities", null)
	if not entities_data is Dictionary:
		return false
	if not entities_data.get("resources", null) is Dictionary:
		return false
	if not entities_data.get("population", null) is Dictionary:
		return false
	if not entities_data.get("buildings", null) is Array:
		return false
	for building_data in entities_data.get("buildings", []):
		if not building_data is Dictionary:
			return false
		if not building_data.get("per_worker_output", {}) is Dictionary or not building_data.get("consumption", {}) is Dictionary:
			return false
	var technology_data = data.get("technology", null)
	if not technology_data is Dictionary:
		return false
	if not technology_data.get("unlocked", []) is Array or not technology_data.get("researching", []) is Array:
		return false
	if not technology_data.get("research_points", {}) is Dictionary or not technology_data.get("research_progress", {}) is Dictionary:
		return false
	var zones_data = data.get("planet_zones", null)
	if not zones_data is Dictionary or not zones_data.get("zones", null) is Array:
		return false
	for zone_data in zones_data.get("zones", []):
		if not zone_data is Dictionary:
			return false
		if not zone_data.get("building_ids", []) is Array or not zone_data.get("resource_deposits", {}) is Dictionary:
			return false
	var decision_data = data.get("decision", data.get("policy", null))
	if not decision_data is Dictionary:
		return false
	if data.has("decision") and (
			not decision_data.get("active_policies", []) is Array
			or not decision_data.get("cooldowns", {}) is Dictionary
			or not decision_data.get("enacted_history", []) is Array
	):
		return false
	if data.has("config"):
		if not data["config"] is Dictionary:
			return false
		for section in ["simulation", "environment", "research", "storage_damage", "damage_rates", "dehydrate", "population", "technology", "buildings"]:
			if data["config"].has(section) and not data["config"][section] is Dictionary:
				return false
	return true


func from_dict(data: Dictionary) -> bool:
	if not validate_serialized_state(data):
		return false
	reset()
	game_time = data.get("time", 0.0)
	paused = data.get("paused", false)
	game_over = data.get("game_over", false)
	universe_name = data.get("universe_name", "未命名宇宙")
	game_started = true
	time_scale = clampf(float(data.get("time_scale", 1.0)), 0.1, 10.0)
	_simulation_accumulator = clampf(float(data.get("simulation_accumulator", 0.0)), 0.0, FIXED_SIMULATION_STEP_DAYS)
	last_autosave_day = int(data.get("last_autosave_day", -1))
	var saved_rates: Dictionary = data.get("research_output_rate", {})
	for research_type in research_output_rate:
		research_output_rate[research_type] = maxf(0.0, float(saved_rates.get(research_type, 0.0)))

	var saved_config = data.get("config", {})
	config = saved_config.duplicate(true) if saved_config is Dictionary and not saved_config.is_empty() else _default_config()
	_env_config = config.get("environment", {})
	_research_config = config.get("research", {})
	_storage_damage_config = config.get("storage_damage", {})
	var sim_config: Dictionary = config.get("simulation", {})
	_time_scale_min = sim_config.get("time_scale_min", 0.1)
	_time_scale_max = sim_config.get("time_scale_max", 10.0)
	time_scale = clampf(time_scale, _time_scale_min, _time_scale_max)

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
			for point_data in s.get("trail", []):
				if point_data is Dictionary:
					star.trail.append(Vector3(point_data.get("x", 0.0), point_data.get("y", 0.0), point_data.get("z", 0.0)))
			environment.stars.append(star)

	environment.time_scale = 1.0
	if data.has("rng_state"):
		environment.rng.state = int(str(data["rng_state"]))

	entities = EntityManagerScript.new(config)
	if data.has("entities"):
		entities.load_state(data["entities"])

	tech_tree = TechTreeScript.new(config)
	if data.has("technology"):
		tech_tree.load_state(data["technology"])
	_connect_tech_tree_signals()

	decision_manager = DecisionManagerScript.new(config)
	if data.has("decision"):
		decision_manager.load_state(data["decision"])
	elif data.has("policy"):
		var policy_data: Dictionary = data["policy"]
		decision_manager.load_state({"current_state": policy_data.get("current_state", "normal")})

	planet_zones = PlanetZoneManagerScript.new(_env_config)
	if data.has("planet_zones"):
		planet_zones.load_state(data["planet_zones"])
	entities.apply_technology_effects(tech_tree)
	entities.enforce_population_invariants()
	return true


func _default_config() -> Dictionary:
	var result: Dictionary
	result = {
		"simulation": {"time_scale_min": 0.1, "time_scale_max": 10.0},
		"environment": {
			"rotation_speed": 15.0, "thermal_inertia": 0.08,
			"diffusion_rate": 0.15, "dark_side_scatter": 0.05,
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
