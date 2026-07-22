extends Node
## 游戏状态 — 持有并协调所有模拟子系统

signal state_updated()
signal research_completed(tech_id: String, tech_name: String)
signal developer_mode_changed(enabled: bool)
signal scenario_phase_changed(new_phase: String, transition_day: float)

const SETTINGS_PATH := "res://settings.json"
const SAVE_SCHEMA_VERSION := 7
const FIXED_SIMULATION_STEP_DAYS := 0.02
const MAX_SIMULATION_SUBSTEPS := 512
const DIFFICULTY_CONFIG_PATH := "res://resources/configs/scenario_difficulties.tres"

# Preload all simulation scripts — their return values are GDScript resources used for .new()
const ThreeBodySimScript = preload("res://scripts/simulation/three_body.gd")
const EntityManagerScript = preload("res://scripts/simulation/entity_manager.gd")
const TechTreeScript = preload("res://scripts/simulation/tech_tree.gd")
const DecisionManagerScript = preload("res://scripts/simulation/decision_manager.gd")
const PlanetZoneManagerScript = preload("res://scripts/simulation/planet_zones.gd")
const ScenarioManagerScript = preload("res://scripts/simulation/scenario_manager.gd")
const ObservationNetworkScript = preload("res://scripts/simulation/observation_network.gd")
const SatelliteNetworkScript = preload("res://scripts/simulation/satellite_network.gd")
const HazardForecastServiceScript = preload("res://scripts/simulation/hazard_forecast_service.gd")
const KnowledgeSystemScript = preload("res://scripts/simulation/knowledge_system.gd")
const DiscoverySystemScript = preload("res://scripts/simulation/discovery_system.gd")
const ResearchProjectSystemScript = preload("res://scripts/simulation/research_project_system.gd")
const EngineeringProjectSystemScript = preload("res://scripts/simulation/engineering_project_system.gd")
const KnowledgePolicySystemScript = preload("res://scripts/simulation/knowledge_policy_system.gd")
const EducationSystemScript = preload("res://scripts/simulation/education_system.gd")
const PreservationAllocatorScript = preload("res://scripts/simulation/preservation_allocator.gd")
const KnowledgeInheritanceScript = preload("res://scripts/simulation/knowledge_inheritance.gd")
const SettlementSystemScript = preload("res://scripts/simulation/settlement_system.gd")
const RegionalLogisticsSystemScript = preload("res://scripts/simulation/regional_logistics_system.gd")
const RegionMovementSystemScript = preload("res://scripts/simulation/region_movement_system.gd")
const ExplorationSystemScript = preload("res://scripts/simulation/exploration_system.gd")
const OpeningGuidanceControllerScript = preload("res://scripts/guidance/opening_guidance_controller.gd")

# ── 子系统引用 ──
var environment       ## ThreeBodySimulation
var entities          ## EntityManager
var tech_tree         ## TechTree
var decision_manager  ## DecisionManager
var planet_zones      ## PlanetZoneManager
var scenario_manager  ## ScenarioManager
var observation_network  ## ObservationNetwork
var satellite_network  ## SatelliteNetwork
var hazard_forecast_service  ## HazardForecastService
var knowledge_system  ## KnowledgeSystem
var discovery_system  ## DiscoverySystem
var research_project_system  ## ResearchProjectSystem
var engineering_project_system  ## EngineeringProjectSystem
var knowledge_policy_system  ## KnowledgePolicySystem
var education_system  ## EducationSystem
var preservation_allocator  ## PreservationAllocator
var knowledge_inheritance  ## KnowledgeInheritance
var settlement_system  ## SettlementSystem
var regional_logistics  ## RegionalLogisticsSystem
var region_movement_system  ## RegionMovementSystem
var exploration_system  ## ExplorationSystem
var opening_guidance  ## OpeningGuidanceController

# ── 游戏状态 ────────────────────────────────────────
var game_time: float = 0.0
var time_scale: float = 1.0
var paused: bool = false
var game_over: bool = false
var game_started: bool = false
var universe_name: String = "未命名宇宙"
var observed_zone_id: int = 0
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


func new_game(p_universe_name: String, p_config: Dictionary = {}, p_scenario_snapshot: Dictionary = {}, p_opening_options: Dictionary = {}) -> bool:
	var resolved_scenario := p_scenario_snapshot.duplicate(true)
	if resolved_scenario.is_empty():
		resolved_scenario = _load_default_scenario_snapshot()
	if resolved_scenario.is_empty():
		return false
	var seed: int
	if resolved_scenario.has("scenario_seed"):
		seed = int(str(resolved_scenario["scenario_seed"]))
	else:
		seed = hash("%s:%d" % [p_universe_name, Time.get_ticks_usec()])

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
	scenario_manager = ScenarioManagerScript.new()
	if not scenario_manager.create_scenario(resolved_scenario, seed, environment):
		reset()
		return false
	entities = EntityManagerScript.new(config)
	tech_tree = TechTreeScript.new(config)
	decision_manager = DecisionManagerScript.new(config)
	planet_zones = PlanetZoneManagerScript.new(_env_config)
	observation_network = ObservationNetworkScript.new()
	satellite_network = SatelliteNetworkScript.new()
	hazard_forecast_service = HazardForecastServiceScript.new()
	if not _initialize_knowledge_systems():
		reset()
		return false

	game_started = true
	game_over = false
	game_time = 0.0
	time_scale = clampf(float(_runtime_settings.get("time_scale", 1.0)), _time_scale_min, _time_scale_max)
	environment.time_scale = 1.0
	_connect_scenario_signals()
	_connect_tech_tree_signals()
	_init_zone_temperatures()
	if not _initialize_regional_systems_new(p_opening_options):
		reset()
		return false
	_update_observation_systems(0.0, 0.0)
	EventBus.game_started.emit(universe_name)
	return true


func reset() -> void:
	time_scale = 1.0
	paused = false
	game_over = false
	game_started = false
	game_time = 0.0
	observed_zone_id = 0
	last_autosave_day = -1
	_simulation_accumulator = 0.0
	_autosave_elapsed_seconds = 0.0
	environment = null
	entities = null
	tech_tree = null
	decision_manager = null
	planet_zones = null
	scenario_manager = null
	observation_network = null
	satellite_network = null
	hazard_forecast_service = null
	knowledge_system = null
	discovery_system = null
	research_project_system = null
	engineering_project_system = null
	knowledge_policy_system = null
	education_system = null
	preservation_allocator = null
	knowledge_inheritance = null
	settlement_system = null
	regional_logistics = null
	region_movement_system = null
	exploration_system = null
	opening_guidance = null
	research_output_rate = {"basic": 0.0, "applied": 0.0, "theoretical": 0.0}


func toggle_pause() -> void:
	if settlement_system != null and settlement_system.capital_zone_id < 0:
		paused = true
		EventBus.game_paused.emit(paused)
		state_updated.emit()
		return
	paused = not paused
	if opening_guidance != null:
		opening_guidance.handle_domain_event("time_control_used", {"source_id": "time-control:first"})
	EventBus.game_paused.emit(paused)
	state_updated.emit()


func set_time_scale(p_scale: float) -> void:
	time_scale = clamp(p_scale, _time_scale_min, _time_scale_max)
	EventBus.time_scale_changed.emit(time_scale)


func set_observed_zone(p_zone_id: int) -> bool:
	if planet_zones == null or planet_zones.get_zone(p_zone_id) == null:
		return false
	if not developer_mode and settlement_system != null:
		var knowledge: Dictionary = settlement_system.get_zone_knowledge(p_zone_id)
		var required_level := SettlementSystemScript.ZoneKnowledgeLevel.OBSERVED if settlement_system.capital_zone_id < 0 else SettlementSystemScript.ZoneKnowledgeLevel.FAMILIAR
		if int(knowledge.get("level", SettlementSystemScript.ZoneKnowledgeLevel.UNKNOWN)) < required_level:
			return false
	if observed_zone_id == p_zone_id:
		return true
	observed_zone_id = p_zone_id
	state_updated.emit()
	return true


func set_developer_mode(p_enabled: bool) -> void:
	if developer_mode == p_enabled:
		return
	developer_mode = p_enabled
	developer_mode_changed.emit(developer_mode)
	state_updated.emit()


func can_access_starmap() -> bool:
	return developer_mode or (
		knowledge_system != null and knowledge_system.has_capability("telescope")
	) or (tech_tree != null and tech_tree.is_unlocked("telescope"))


func apply_developer_values(p_values: Dictionary) -> bool:
	if not developer_mode or not game_started or entities == null or tech_tree == null:
		return false

	var resources_before: Dictionary = {}
	for resource_id in entities.resources:
		resources_before[resource_id] = entities.get_resource(str(resource_id))
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
	if regional_logistics != null and settlement_system != null and settlement_system.capital_zone_id >= 0:
		regional_logistics.reconcile_after_simulation(resources_before, entities, entities.buildings)
		settlement_system.reconcile_population_total(entities.population.total, region_movement_system.get_reserved_population())

	state_updated.emit()
	return true


func developer_fill_resources(p_amount: float = 100000.0) -> bool:
	if not developer_mode or entities == null:
		return false
	var resources_before: Dictionary = {}
	for resource_id in entities.resources:
		resources_before[resource_id] = entities.get_resource(str(resource_id))
	for resource in entities.resources.values():
		resource.amount = maxf(0.0, p_amount)
	if regional_logistics != null and settlement_system != null and settlement_system.capital_zone_id >= 0:
		regional_logistics.reconcile_after_simulation(resources_before, entities, entities.buildings)
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
	if knowledge_system != null:
		knowledge_system.developer_unlock_all()
		_sync_technology_effects_from_knowledge()
	if hazard_forecast_service != null:
		hazard_forecast_service.invalidate()
		_update_observation_systems(game_time, 0.0)
	state_updated.emit()
	return true


func start_knowledge_research(p_node_id: String) -> Dictionary:
	if research_project_system == null or entities == null:
		return {"success": false, "message": "知识研究系统尚未初始化"}
	var result: Dictionary = research_project_system.start_project(p_node_id, {}, entities)
	_refresh_external_workforce_reservation()
	state_updated.emit()
	return result


func toggle_knowledge_research(p_node_id: String) -> Dictionary:
	if research_project_system == null:
		return {"success": false, "message": "知识研究系统尚未初始化"}
	var result: Dictionary = research_project_system.toggle_pause(p_node_id)
	_refresh_external_workforce_reservation()
	state_updated.emit()
	return result


func start_knowledge_engineering(p_node_id: String, p_project_id: String) -> Dictionary:
	if engineering_project_system == null or entities == null:
		return {"success": false, "message": "知识工程系统尚未初始化"}
	var result: Dictionary = engineering_project_system.start_project(p_node_id, p_project_id, entities)
	_refresh_external_workforce_reservation()
	state_updated.emit()
	return result


func start_teaching_plan(p_plan: Dictionary) -> Dictionary:
	if education_system == null or entities == null:
		return {"success": false, "message": "教学系统尚未初始化"}
	var result: Dictionary = education_system.start_plan(p_plan, entities)
	_refresh_external_workforce_reservation()
	state_updated.emit()
	return result


func adopt_knowledge_policy(p_policy_id: String) -> Dictionary:
	if knowledge_policy_system == null:
		return {"success": false, "message": "知识政策系统尚未初始化"}
	var result: Dictionary = knowledge_policy_system.adopt_policy(p_policy_id)
	state_updated.emit()
	return result


func _refresh_external_workforce_reservation() -> void:
	if entities == null:
		return
	var reserved := 0
	if research_project_system != null:
		reserved += research_project_system.get_reserved_workers()
	if engineering_project_system != null:
		reserved += engineering_project_system.get_reserved_workers()
	if education_system != null:
		reserved += education_system.get_reserved_workers()
	if region_movement_system != null:
		reserved += region_movement_system.get_reserved_population()
	entities.set_external_reserved_workers(reserved)


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


func _connect_scenario_signals() -> void:
	if scenario_manager != null and not scenario_manager.phase_changed.is_connected(_on_scenario_phase_changed):
		scenario_manager.phase_changed.connect(_on_scenario_phase_changed)


func _initialize_knowledge_systems() -> bool:
	knowledge_system = KnowledgeSystemScript.new()
	if not knowledge_system.graph.is_valid():
		push_error("知识图配置无效：%s" % "; ".join(knowledge_system.graph.validation_errors))
		return false
	if not knowledge_system.initialize_new_civilization():
		return false
	discovery_system = DiscoverySystemScript.new(knowledge_system)
	research_project_system = ResearchProjectSystemScript.new(knowledge_system)
	engineering_project_system = EngineeringProjectSystemScript.new(knowledge_system)
	knowledge_policy_system = KnowledgePolicySystemScript.new(knowledge_system)
	education_system = EducationSystemScript.new(knowledge_system)
	preservation_allocator = PreservationAllocatorScript.new()
	knowledge_inheritance = KnowledgeInheritanceScript.new(knowledge_system)
	if not knowledge_system.capability_changed.is_connected(_on_knowledge_capability_changed):
		knowledge_system.capability_changed.connect(_on_knowledge_capability_changed)
	_sync_technology_effects_from_knowledge()
	return true


func _initialize_regional_systems_new(p_opening_options: Dictionary) -> bool:
	settlement_system = SettlementSystemScript.new()
	if not settlement_system.initialize_new(planet_zones, entities.population.total, scenario_manager.get_rule_state(0.0)):
		return false
	regional_logistics = RegionalLogisticsSystemScript.new()
	region_movement_system = RegionMovementSystemScript.new()
	exploration_system = ExplorationSystemScript.new()
	opening_guidance = OpeningGuidanceControllerScript.new()
	if not opening_guidance.initialize(_resolve_guidance_mode(p_opening_options)):
		return false
	paused = true
	var first_candidate: Dictionary = settlement_system.candidate_views[0]
	observed_zone_id = int(first_candidate.get("zone_id", 0))
	return true


func _resolve_guidance_mode(p_opening_options: Dictionary) -> int:
	var value = p_opening_options.get("guidance_mode", _runtime_settings.get("guidance_mode", "full"))
	if value is int or value is float:
		return clampi(int(value), OpeningGuidanceControllerScript.GuidanceMode.FULL, OpeningGuidanceControllerScript.GuidanceMode.OFF)
	match str(value).to_lower():
		"compact": return OpeningGuidanceControllerScript.GuidanceMode.COMPACT
		"off": return OpeningGuidanceControllerScript.GuidanceMode.OFF
		_: return OpeningGuidanceControllerScript.GuidanceMode.FULL


func confirm_capital(p_zone_id: int) -> Dictionary:
	if settlement_system == null or regional_logistics == null:
		return {"success": false, "message": "区域系统尚未初始化"}
	var result: Dictionary = settlement_system.confirm_capital(p_zone_id, planet_zones, entities.population.total, game_time)
	if not result.get("success", false):
		return result
	regional_logistics.initialize_at_capital(p_zone_id, entities)
	settlement_system.refresh_settlement_status(regional_logistics, entities, knowledge_system, game_time)
	observed_zone_id = p_zone_id
	paused = false
	if opening_guidance != null:
		opening_guidance.handle_domain_event("capital_confirmed", {"source_id": "capital:%d" % p_zone_id})
	EventBus.game_paused.emit(false)
	state_updated.emit()
	return result


func get_public_zone_summaries() -> Array:
	if settlement_system == null or planet_zones == null or entities == null:
		return []
	return settlement_system.get_public_zone_summaries(planet_zones, entities)


func get_zone_knowledge(p_zone_id: int) -> Dictionary:
	if settlement_system == null:
		return {}
	return settlement_system.get_zone_knowledge(p_zone_id)


func start_region_expedition(p_origin_zone_id: int, p_target_zone_id: int, p_population_count: int = 5) -> Dictionary:
	if exploration_system == null or region_movement_system == null or regional_logistics == null:
		return {"success": false, "message": "勘探系统尚未初始化"}
	var validation: Dictionary = exploration_system.can_plan_expedition(p_origin_zone_id, p_target_zone_id, planet_zones, settlement_system)
	if not validation.get("success", false):
		return validation
	var result: Dictionary = region_movement_system.start_operation(
		"exploration", p_origin_zone_id, p_target_zone_id, p_population_count, {}, planet_zones,
		settlement_system, regional_logistics, entities, true
	)
	if result.get("success", false) and opening_guidance != null:
		opening_guidance.handle_domain_event("expedition_departed", {"source_id": str(result.get("operation_id", ""))})
	_refresh_external_workforce_reservation()
	state_updated.emit()
	return result


func start_region_migration(p_origin_zone_id: int, p_target_zone_id: int, p_population_count: int, p_cargo: Dictionary = {}) -> Dictionary:
	if region_movement_system == null or regional_logistics == null:
		return {"success": false, "message": "迁徙系统尚未初始化"}
	var result: Dictionary = region_movement_system.start_operation(
		"migration", p_origin_zone_id, p_target_zone_id, p_population_count, p_cargo, planet_zones,
		settlement_system, regional_logistics, entities, false
	)
	_refresh_external_workforce_reservation()
	state_updated.emit()
	return result


func plan_region_route(p_origin_zone_id: int, p_target_zone_id: int) -> Dictionary:
	if region_movement_system == null:
		return {"success": false, "message": "区域行动系统尚未初始化"}
	return region_movement_system.plan_route(p_origin_zone_id, p_target_zone_id, planet_zones, settlement_system, false)


func start_region_transport(p_origin_zone_id: int, p_target_zone_id: int, p_crew_count: int, p_cargo: Dictionary) -> Dictionary:
	if region_movement_system == null or regional_logistics == null:
		return {"success": false, "message": "运输系统尚未初始化"}
	if p_cargo.is_empty():
		return {"success": false, "message": "运输行动必须配置实际载荷"}
	var result: Dictionary = region_movement_system.start_operation(
		"transport", p_origin_zone_id, p_target_zone_id, p_crew_count, p_cargo, planet_zones,
		settlement_system, regional_logistics, entities, true
	)
	_refresh_external_workforce_reservation()
	state_updated.emit()
	return result


func cancel_region_operation(p_operation_id: String) -> Dictionary:
	if region_movement_system == null or settlement_system == null or regional_logistics == null:
		return {"success": false, "message": "区域行动系统尚未初始化"}
	var result: Dictionary = region_movement_system.cancel_operation(p_operation_id, settlement_system, regional_logistics)
	_refresh_external_workforce_reservation()
	state_updated.emit()
	return result


func pause_region_operation(p_operation_id: String) -> Dictionary:
	if region_movement_system == null:
		return {"success": false, "message": "区域行动系统尚未初始化"}
	var result: Dictionary = region_movement_system.pause_operation(p_operation_id)
	state_updated.emit()
	return result


func resume_region_operation(p_operation_id: String) -> Dictionary:
	if region_movement_system == null:
		return {"success": false, "message": "区域行动系统尚未初始化"}
	var result: Dictionary = region_movement_system.resume_operation(p_operation_id)
	state_updated.emit()
	return result


func get_settlement_view(p_zone_id: int) -> Dictionary:
	if settlement_system == null or regional_logistics == null:
		return {}
	settlement_system.refresh_settlement_status(regional_logistics, entities, knowledge_system, game_time)
	return settlement_system.get_settlement(p_zone_id)


func get_outpost_upgrade_status(p_zone_id: int) -> Dictionary:
	if settlement_system == null or regional_logistics == null or region_movement_system == null:
		return {"success": false, "message": "聚落系统尚未初始化"}
	var route_available := false
	if settlement_system.capital_zone_id >= 0:
		route_available = region_movement_system.plan_route(
			settlement_system.capital_zone_id, p_zone_id, planet_zones, settlement_system, false
		).get("success", false)
	return settlement_system.get_outpost_upgrade_requirements(
		p_zone_id, regional_logistics, entities, knowledge_system, route_available, game_time
	)


func upgrade_outpost(p_zone_id: int) -> Dictionary:
	var status := get_outpost_upgrade_status(p_zone_id)
	if not status.get("success", false):
		return status
	var result: Dictionary = settlement_system.upgrade_outpost(
		p_zone_id, regional_logistics, entities, knowledge_system, true, game_time
	)
	state_updated.emit()
	return result


func start_capital_relocation(p_target_zone_id: int) -> Dictionary:
	if settlement_system == null or region_movement_system == null or regional_logistics == null:
		return {"success": false, "message": "迁都系统尚未初始化"}
	var origin_zone_id: int = settlement_system.capital_zone_id
	if p_target_zone_id == origin_zone_id:
		return {"success": false, "message": "目标区域已是首都"}
	var target: Dictionary = settlement_system.get_settlement(p_target_zone_id)
	if str(target.get("type", "")) != "settlement":
		return {"success": false, "message": "迁都目标必须是已升级的常设聚落"}
	if knowledge_system == null or not knowledge_system.has_capability("symbolic_recording"):
		return {"success": false, "message": "迁都需要符号记录能力来转移档案与命令"}
	for operation in region_movement_system.operations.values():
		if str(operation.get("type", "")) == "capital_relocation" and int(operation.get("status", -1)) not in [
			RegionMovementSystemScript.OperationStatus.ARRIVED,
			RegionMovementSystemScript.OperationStatus.CANCELLED,
		]:
			return {"success": false, "message": "已有一次迁都行动在进行中"}
	var result: Dictionary = region_movement_system.start_operation(
		"capital_relocation", origin_zone_id, p_target_zone_id, 10, {"iron": 25.0}, planet_zones,
		settlement_system, regional_logistics, entities, false
	)
	if result.get("success", false):
		var operation_id := str(result.get("operation_id", ""))
		region_movement_system.operations[operation_id]["carries_civil_records"] = true
		region_movement_system.operations[operation_id]["coordination_efficiency_on_arrival"] = 0.85
		result["message"] = "迁都队已出发：10 名组织人员、25 铁材与文明档案将实际运往目标聚落；到达前首都不变"
	_refresh_external_workforce_reservation()
	state_updated.emit()
	return result


func execute_regional_construction(p_decision_id: String, p_zone_id: int) -> Dictionary:
	if settlement_system == null or regional_logistics == null:
		return {"success": false, "message": "地方建设系统尚未初始化"}
	var zone_knowledge: Dictionary = settlement_system.get_zone_knowledge(p_zone_id)
	if int(zone_knowledge.get("level", 0)) < SettlementSystemScript.ZoneKnowledgeLevel.FAMILIAR:
		return {"success": false, "message": "需要先熟悉或勘探该区域才能施工"}
	var decision = decision_manager.available_decisions.get(p_decision_id)
	if decision == null or decision.category != "construction":
		return {"success": false, "message": "未知建设项目"}
	var local_check: Dictionary = regional_logistics.can_pay_local_cost(p_zone_id, decision.resource_cost)
	if not local_check.get("success", false):
		return local_check
	var result: Dictionary = decision_manager.execute_decision(p_decision_id, entities, tech_tree, planet_zones, p_zone_id)
	if result.get("success", false):
		regional_logistics.commit_local_cost(p_zone_id, decision.resource_cost)
		if opening_guidance != null:
			opening_guidance.handle_domain_event("construction_started", {"source_id": "building:%d" % int(result.get("building_id", -1))})
	state_updated.emit()
	return result


func assign_regional_building_workers(p_building_id: int, p_count: int) -> Dictionary:
	var building = entities.get_building(p_building_id) if entities != null else null
	if building == null or settlement_system == null:
		return {"success": false, "message": "建筑或区域系统不可用"}
	var local_assigned := 0
	for local_building in entities.get_buildings_in_zone(building.zone_id):
		local_assigned += local_building.assigned_workers
	var local_idle := maxi(0, settlement_system.get_population(building.zone_id) - local_assigned)
	if p_count > local_idle:
		return {"success": false, "message": "当地闲置人口不足（仅剩 %d）" % local_idle}
	var result: Dictionary = entities.assign_worker_to_building(p_building_id, p_count)
	if result.get("success", false) and opening_guidance != null:
		opening_guidance.handle_domain_event("population_assignment_changed", {"source_id": "workers:%d:%d" % [p_building_id, building.assigned_workers]})
	_refresh_external_workforce_reservation()
	state_updated.emit()
	return result


func unassign_regional_building_workers(p_building_id: int, p_count: int) -> Dictionary:
	if entities == null:
		return {"success": false, "message": "人口系统不可用"}
	var result: Dictionary = entities.unassign_worker_from_building(p_building_id, p_count)
	if result.get("success", false) and opening_guidance != null:
		opening_guidance.handle_domain_event("population_assignment_changed", {"source_id": "workers:%d:%d" % [p_building_id, entities.get_building(p_building_id).assigned_workers]})
	state_updated.emit()
	return result


func assign_regional_breeders(p_count: int) -> Dictionary:
	if entities == null or settlement_system == null or settlement_system.capital_zone_id < 0:
		return {"success": false, "message": "首都人口系统不可用"}
	var capital_id: int = settlement_system.capital_zone_id
	var local_workers: int = 0
	for building in entities.get_buildings_in_zone(capital_id):
		local_workers += building.assigned_workers
	var local_idle: int = maxi(0, settlement_system.get_population(capital_id) - local_workers - entities.population.breeders)
	if p_count > local_idle:
		return {"success": false, "message": "首都闲置人口不足（仅剩 %d）" % local_idle}
	var result: Dictionary = entities.assign_breeders(p_count)
	if result.get("success", false) and opening_guidance != null:
		opening_guidance.handle_domain_event("population_assignment_changed", {"source_id": "breeders:%d" % entities.population.breeders})
	state_updated.emit()
	return result


func unassign_regional_breeders(p_count: int) -> Dictionary:
	if entities == null:
		return {"success": false, "message": "人口系统不可用"}
	var result: Dictionary = entities.unassign_breeders(p_count)
	if result.get("success", false) and opening_guidance != null:
		opening_guidance.handle_domain_event("population_assignment_changed", {"source_id": "breeders:%d" % entities.population.breeders})
	state_updated.emit()
	return result


func record_local_observation(p_zone_id: int) -> Dictionary:
	if discovery_system == null or settlement_system == null:
		return {"success": false, "message": "观测系统尚未初始化"}
	var knowledge: Dictionary = settlement_system.get_zone_knowledge(p_zone_id)
	if int(knowledge.get("level", 0)) < SettlementSystemScript.ZoneKnowledgeLevel.FAMILIAR:
		return {"success": false, "message": "当地无人长期活动，无法形成连续观测"}
	var result: Dictionary = discovery_system.record_observation(
		"zone-%d" % p_zone_id, "celestial_motion", {"duration": 1.0}, 0.55
	)
	if result.get("success", false) and opening_guidance != null:
		var sequence := int(discovery_system.observation_metrics.get("celestial_motion", 0))
		opening_guidance.handle_domain_event("observation_recorded", {"source_id": "observation:zone-%d:%d" % [p_zone_id, sequence]})
	state_updated.emit()
	return result


func _on_knowledge_capability_changed(_p_capability_id: String, _p_level: int) -> void:
	_sync_technology_effects_from_knowledge()
	if hazard_forecast_service != null:
		hazard_forecast_service.invalidate()


func _sync_technology_effects_from_knowledge() -> void:
	if knowledge_system == null or tech_tree == null:
		return
	for node_id in knowledge_system.graph.nodes:
		if knowledge_system.get_node_state(node_id) != KnowledgeSystemScript.KnowledgeState.APPLIED:
			continue
		for effect_id in knowledge_system.graph.nodes[node_id].get("technology_effect_ids", []):
			var effect_node = tech_tree.get_node(str(effect_id))
			if effect_node != null:
				effect_node.unlocked = true
				effect_node.researching = false
	entities.apply_technology_effects(tech_tree)


func _on_scenario_phase_changed(p_phase: String, p_transition_day: float) -> void:
	scenario_phase_changed.emit(p_phase, p_transition_day)
	EventBus.scenario_phase_changed.emit(p_phase, p_transition_day)


func _on_research_finished(p_tech_id: String, p_tech_name: String) -> void:
	entities.apply_technology_effects(tech_tree)
	if hazard_forecast_service != null:
		hazard_forecast_service.invalidate()
		_update_observation_systems(game_time, 0.0)
	research_completed.emit(p_tech_id, p_tech_name)


func update(p_dt: float) -> void:
	if paused or game_over or not game_started:
		return
	if settlement_system != null and settlement_system.capital_zone_id < 0:
		paused = true
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
	scenario_manager.update(game_time, p_game_days_dt)
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
	_refresh_external_workforce_reservation()
	var resources_before: Dictionary = {}
	for resource_id in entities.resources:
		resources_before[resource_id] = entities.get_resource(str(resource_id))
	entities.update(env_params, planet_zones, p_game_days_dt, dehydrated)
	if regional_logistics != null and settlement_system != null and settlement_system.capital_zone_id >= 0:
		regional_logistics.reconcile_after_simulation(resources_before, entities, entities.buildings)
	if region_movement_system != null:
		region_movement_system.update(
			p_game_days_dt, settlement_system, regional_logistics, entities,
			exploration_system, planet_zones, game_time + p_game_days_dt
		)
		_refresh_external_workforce_reservation()
	if settlement_system != null:
		var in_transit: int = region_movement_system.get_reserved_population() if region_movement_system != null else 0
		settlement_system.reconcile_population_total(entities.population.total, in_transit)
		settlement_system.refresh_known_environment(planet_zones, game_time + p_game_days_dt)
		if regional_logistics != null:
			settlement_system.refresh_settlement_status(regional_logistics, entities, knowledge_system, game_time + p_game_days_dt)
	if exploration_system != null:
		exploration_system.update_staleness(game_time + p_game_days_dt, settlement_system)

	_process_research_output(p_game_days_dt)
	_update_knowledge_evolution(game_time + p_game_days_dt, p_game_days_dt)

	if dehydrated:
		_process_storage_damage(p_game_days_dt)

	decision_manager.update_cooldowns(p_game_days_dt, 1.0)

	game_time += p_game_days_dt
	_update_observation_systems(game_time, p_game_days_dt, env_params)


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

	if research_project_system != null:
		research_project_system.update_day(p_game_days_dt, frame_output, entities)
	if engineering_project_system != null:
		engineering_project_system.update_day(p_game_days_dt, frame_output, entities)
	_refresh_external_workforce_reservation()

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


func _update_knowledge_evolution(p_game_day: float, p_delta_days: float) -> void:
	if knowledge_system == null:
		return
	var active_building_types: Array[String] = []
	for building in entities.buildings:
		if building.active and not building.destroyed and not building.under_construction and building.building_type not in active_building_types:
			active_building_types.append(building.building_type)
	discovery_system.update_day(p_game_day, p_delta_days, {"active_building_types": active_building_types})
	var teaching_results: Array = education_system.update_day(p_delta_days, {})
	if opening_guidance != null:
		for teaching_result_value in teaching_results:
			var teaching_result: Dictionary = teaching_result_value
			opening_guidance.handle_domain_event("teaching_plan_progressed", {
				"source_id": "teaching-progress:%s" % str(teaching_result.get("plan_id", "")),
			})
	var retention_context: Dictionary = knowledge_policy_system.get_retention_context()
	var teaching_workers: int = education_system.get_reserved_workers()
	retention_context["education_coverage"] = clampf(
		float(retention_context.get("education_coverage", 0.0))
		+ float(teaching_workers) / maxf(1.0, float(entities.population.total)),
		0.0, 1.0
	)
	knowledge_inheritance.update_day(p_game_day, retention_context)


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
		"observed_zone_id": observed_zone_id,
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
		"knowledge": knowledge_system.get_state(),
		"research_projects": research_project_system.get_state(),
		"engineering_projects": engineering_project_system.get_state(),
		"discoveries": discovery_system.get_state(),
		"inheritance": knowledge_inheritance.get_state(),
		"knowledge_policy": knowledge_policy_system.get_state(),
		"education": education_system.get_state(),
		"preservation_plan": preservation_allocator.get_state(),
		"settlement": settlement_system.get_state(),
		"regional_logistics": regional_logistics.get_state(),
		"region_operations": region_movement_system.get_state(),
		"exploration": exploration_system.get_state(),
		"opening_guidance": opening_guidance.get_state(),
		"decision": decision_manager.get_state(),
		"planet_zones": {
			"rotation_angle": planet_zones.rotation_angle,
			"zones_summary": get_public_zone_summaries(),
		},
		"scenario": scenario_manager.get_rule_state(game_time),
		"hazard_forecast": hazard_forecast_service.get_public_snapshot(),
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
		"observed_zone_id": observed_zone_id,
		"stars": stars_data,
		"entities": entities.get_state(),
		"technology": tech_tree.get_state(),
		"knowledge": knowledge_system.get_state(),
		"research_projects": research_project_system.get_state(),
		"engineering_projects": engineering_project_system.get_state(),
		"discoveries": discovery_system.get_state(),
		"inheritance": knowledge_inheritance.get_state(),
		"knowledge_policy": knowledge_policy_system.get_state(),
		"education": education_system.get_state(),
		"preservation_plan": preservation_allocator.get_state(),
		"settlement": settlement_system.get_state(),
		"regional_logistics": regional_logistics.get_state(),
		"region_operations": region_movement_system.get_state(),
		"exploration": exploration_system.get_state(),
		"opening_guidance": opening_guidance.get_state(),
		"decision": decision_manager.get_state(),
		"planet_zones": planet_zones.get_state(),
		"time_scale": time_scale,
		"simulation_accumulator": _simulation_accumulator,
		"last_autosave_day": last_autosave_day,
		"research_output_rate": research_output_rate.duplicate(),
		"config": config.duplicate(true),
		"rng_state": str(environment.rng.state),
		"scenario": scenario_manager.get_state(),
		"observation_network": observation_network.get_state(),
		"satellite_network": satellite_network.get_state(),
		"hazard_forecasts": hazard_forecast_service.get_state(),
	}
	return result


func validate_serialized_state(data) -> bool:
	if not data is Dictionary or int(data.get("schema_version", -1)) != SAVE_SCHEMA_VERSION:
		return false
	for required_section in [
		"entities", "technology", "knowledge", "research_projects", "engineering_projects",
		"discoveries", "inheritance", "knowledge_policy", "education", "preservation_plan",
		"settlement", "regional_logistics", "region_operations", "exploration", "opening_guidance",
		"decision", "planet_zones", "config", "research_output_rate", "scenario",
		"observation_network", "satellite_network", "hazard_forecasts",
	]:
		if not data.get(required_section, null) is Dictionary:
			return false
	for required_value in [
		"time", "paused", "game_over", "universe_name", "observed_zone_id", "time_scale",
		"simulation_accumulator", "last_autosave_day", "rng_state",
	]:
		if not data.has(required_value):
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
		if not star_data.get("trail", null) is Array:
			return false
		for star_value in ["mass", "radius", "is_planet"]:
			if not star_data.has(star_value):
				return false
		for vector_data in [star_data["position"], star_data["velocity"]]:
			for axis in ["x", "y", "z"]:
				if not vector_data.has(axis):
					return false
		for channel in ["r", "g", "b", "a"]:
			if not star_data["color"].has(channel):
				return false
		for point_data in star_data["trail"]:
			if not point_data is Dictionary or not point_data.has("x") or not point_data.has("y") or not point_data.has("z"):
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
	if (
		not zones_data is Dictionary
		or int(zones_data.get("climate_model_version", -1)) != PlanetZoneManagerScript.CLIMATE_MODEL_VERSION
		or not zones_data.get("zones", null) is Array
		or zones_data["zones"].size() != PlanetZoneManagerScript.TOTAL_ZONES
	):
		return false
	for climate_value in [
		"rotation_angle", "light_norm_divisor", "dark_side_scatter",
		"reference_mean_insolation", "climate_calibration_offset_c",
	]:
		if not zones_data.has(climate_value):
			return false
	for zone_data in zones_data.get("zones", []):
		if not zone_data is Dictionary:
			return false
		if (
			not zone_data.get("building_ids", null) is Array
			or not zone_data.get("resource_deposits", null) is Dictionary
			or not zone_data.has("air_temperature")
			or not zone_data.has("nitrogen_gas_fraction")
			or not zone_data.has("oxygen_gas_fraction")
		):
			return false
		for zone_value in [
			"zone_id", "terrain_type", "temperature", "radiation", "light_intensity",
			"fertility", "algae_density",
		]:
			if not zone_data.has(zone_value):
				return false
	var decision_data = data.get("decision", null)
	if not decision_data is Dictionary:
		return false
	if (
		not decision_data.get("active_policies", []) is Array
		or not decision_data.get("cooldowns", {}) is Dictionary
		or not decision_data.get("enacted_history", []) is Array
	):
		return false
	for section in ["simulation", "environment", "research", "storage_damage", "damage_rates", "dehydrate", "population"]:
		if not data["config"].get(section, null) is Dictionary:
			return false
	if not ScenarioManagerScript.new().validate_state(data["scenario"]):
		return false
	if not data["knowledge"].get("nodes", null) is Dictionary:
		return false
	if (
		(not data["observed_zone_id"] is int and not data["observed_zone_id"] is float)
		or not is_equal_approx(float(data["observed_zone_id"]), floor(float(data["observed_zone_id"])))
		or int(data["observed_zone_id"]) < 0
		or int(data["observed_zone_id"]) >= PlanetZoneManagerScript.TOTAL_ZONES
	):
		return false
	if not _validate_regional_serialized_sections(data):
		return false
	return true


func _validate_regional_serialized_sections(p_data: Dictionary) -> bool:
	var settlement_data: Dictionary = p_data["settlement"]
	if not settlement_data.get("zone_knowledge", null) is Dictionary:
		return false
	if not settlement_data.get("region_population", null) is Dictionary or not settlement_data.get("settlements", null) is Dictionary:
		return false
	if not settlement_data.get("candidate_views", []) is Array or not settlement_data.get("familiar_zone_ids", []) is Array:
		return false
	var capital_value = settlement_data.get("capital_zone_id", -1)
	if (not capital_value is int and not capital_value is float) or not is_equal_approx(float(capital_value), floor(float(capital_value))):
		return false
	if int(capital_value) < -1 or int(capital_value) >= PlanetZoneManagerScript.TOTAL_ZONES:
		return false
	for record in settlement_data["zone_knowledge"].values():
		if not record is Dictionary or not record.get("public_data", null) is Dictionary:
			return false
	var logistics_data: Dictionary = p_data["regional_logistics"]
	for key in ["local_inventories", "operation_reserves", "network_connections"]:
		if not logistics_data.get(key, null) is Dictionary:
			return false
	for inventory in logistics_data["local_inventories"].values():
		if not inventory is Dictionary:
			return false
	var operation_data: Dictionary = p_data["region_operations"]
	if not operation_data.get("operations", null) is Dictionary:
		return false
	for operation in operation_data["operations"].values():
		if not operation is Dictionary or not operation.get("route", null) is Array or not operation.get("cargo", null) is Dictionary:
			return false
	if not p_data["exploration"].get("survey_log", null) is Array:
		return false
	var guidance_data: Dictionary = p_data["opening_guidance"]
	for key in ["completed_task_ids", "skipped_task_ids", "dismissed_hint_ids", "handbook_seen_concept_ids", "processed_source_ids"]:
		if not guidance_data.get(key, null) is Array:
			return false
	if not guidance_data.get("deferred_task_reasons", null) is Dictionary:
		return false
	return true


func from_dict(data: Dictionary) -> bool:
	if not validate_serialized_state(data):
		return false
	reset()
	game_time = float(data["time"])
	paused = bool(data["paused"])
	game_over = bool(data["game_over"])
	universe_name = str(data["universe_name"])
	observed_zone_id = int(data["observed_zone_id"])
	game_started = true
	time_scale = clampf(float(data["time_scale"]), 0.1, 10.0)
	_simulation_accumulator = clampf(float(data["simulation_accumulator"]), 0.0, FIXED_SIMULATION_STEP_DAYS)
	last_autosave_day = int(data["last_autosave_day"])
	var saved_rates: Dictionary = data["research_output_rate"]
	for research_type in research_output_rate:
		research_output_rate[research_type] = maxf(0.0, float(saved_rates.get(research_type, 0.0)))

	config = (data["config"] as Dictionary).duplicate(true)
	_env_config = config.get("environment", {})
	_research_config = config.get("research", {})
	_storage_damage_config = config.get("storage_damage", {})
	var sim_config: Dictionary = config.get("simulation", {})
	_time_scale_min = sim_config.get("time_scale_min", 0.1)
	_time_scale_max = sim_config.get("time_scale_max", 10.0)
	time_scale = clampf(time_scale, _time_scale_min, _time_scale_max)

	environment = ThreeBodySimScript.new()
	environment.stars.clear()

	var stars_data: Array = data["stars"]
	for sd in stars_data:
		var s: Dictionary = sd
		var pos: Dictionary = s["position"]
		var vel: Dictionary = s["velocity"]
		var col: Dictionary = s["color"]
		var StarDataClass = ThreeBodySimScript.StarData
		var star = StarDataClass.new(
			float(s["mass"]),
			Vector3(float(pos["x"]), float(pos["y"]), float(pos["z"])),
			Vector3(float(vel["x"]), float(vel["y"]), float(vel["z"])),
			Color(float(col["r"]), float(col["g"]), float(col["b"]), float(col["a"])),
			float(s["radius"]),
			bool(s["is_planet"]),
		)
		for point_data in s["trail"]:
			var point: Dictionary = point_data
			star.trail.append(Vector3(float(point["x"]), float(point["y"]), float(point["z"])))
		environment.stars.append(star)

	environment.time_scale = 1.0
	environment.rng.state = int(str(data["rng_state"]))

	scenario_manager = ScenarioManagerScript.new()
	if not scenario_manager.load_state(data["scenario"], environment, game_time):
		return false
	_connect_scenario_signals()

	entities = EntityManagerScript.new(config)
	entities.load_state(data["entities"])

	tech_tree = TechTreeScript.new(config)
	tech_tree.load_state(data["technology"])
	_connect_tech_tree_signals()
	if not _initialize_knowledge_systems() or not knowledge_system.load_state(data["knowledge"]):
		return false
	if not research_project_system.load_state(data["research_projects"]):
		return false
	if not engineering_project_system.load_state(data["engineering_projects"]):
		return false
	if not discovery_system.load_state(data["discoveries"]):
		return false
	if not knowledge_inheritance.load_state(data["inheritance"]):
		return false
	if not knowledge_policy_system.load_state(data["knowledge_policy"]):
		return false
	if not education_system.load_state(data["education"]):
		return false
	if not preservation_allocator.load_state(data["preservation_plan"]):
		return false
	_sync_technology_effects_from_knowledge()

	decision_manager = DecisionManagerScript.new(config)
	decision_manager.load_state(data["decision"])

	planet_zones = PlanetZoneManagerScript.new(_env_config)
	if not planet_zones.load_state(data["planet_zones"]):
		return false
	settlement_system = SettlementSystemScript.new()
	if not settlement_system.load_state(data["settlement"]):
		return false
	regional_logistics = RegionalLogisticsSystemScript.new()
	if not regional_logistics.load_state(data["regional_logistics"]):
		return false
	region_movement_system = RegionMovementSystemScript.new()
	if not region_movement_system.load_state(data["region_operations"]):
		return false
	exploration_system = ExplorationSystemScript.new()
	if not exploration_system.load_state(data["exploration"]):
		return false
	opening_guidance = OpeningGuidanceControllerScript.new()
	if not opening_guidance.initialize(int(data["opening_guidance"]["mode"]), data["opening_guidance"]):
		return false
	if settlement_system.capital_zone_id < 0:
		paused = true
	observation_network = ObservationNetworkScript.new()
	observation_network.load_state(data["observation_network"])
	satellite_network = SatelliteNetworkScript.new()
	satellite_network.load_state(data["satellite_network"])
	hazard_forecast_service = HazardForecastServiceScript.new()
	hazard_forecast_service.load_state(data["hazard_forecasts"])
	_refresh_external_workforce_reservation()
	entities.apply_technology_effects(tech_tree)
	entities.enforce_population_invariants()
	return true


func _default_config() -> Dictionary:
	var result: Dictionary
	result = {
		"simulation": {"time_scale_min": 0.1, "time_scale_max": 10.0},
		"environment": {
			"rotation_speed": 15.0, "dark_side_scatter": 0.05,
			"target_start_temp": 20.0, "target_peak_light": 0.85,
			"surface_response_rate": 0.08, "air_surface_exchange_rate": 0.24,
			"atmosphere_diffusion_rate": 0.38, "surface_diffusion_rate": 0.035,
			"atmosphere_redistribution": 0.82, "greenhouse_warming_c": 33.0,
			"condensation_rate": 0.35, "evaporation_rate": 0.12,
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


func _load_default_scenario_snapshot() -> Dictionary:
	var difficulty_config = load(DIFFICULTY_CONFIG_PATH)
	if difficulty_config == null or not difficulty_config.has_method("validate"):
		push_error("无法加载场景难度配置：%s" % DIFFICULTY_CONFIG_PATH)
		return {}
	var errors: PackedStringArray = difficulty_config.validate()
	if not errors.is_empty():
		push_error("场景难度配置无效：%s" % "; ".join(errors))
		return {}
	var result: Dictionary = difficulty_config.create_snapshot(difficulty_config.default_preset_id)
	if not result.get("success", false):
		return {}
	return result["snapshot"]


func _update_observation_systems(p_game_day: float, p_dt: float, p_env_params: Dictionary = {}) -> void:
	if observation_network == null or satellite_network == null or hazard_forecast_service == null:
		return
	var has_telescope: bool = (
		knowledge_system != null and knowledge_system.has_capability("telescope")
	) or (tech_tree != null and tech_tree.is_unlocked("telescope"))
	var public_measurement := p_env_params.duplicate(true)
	if public_measurement.is_empty() and environment != null:
		public_measurement = environment.get_environment_params()
	public_measurement["possible_zone_ids"] = _get_current_public_risk_zones()
	observation_network.update(p_game_day, p_dt, has_telescope, entities, public_measurement)
	var observation_data: Dictionary = observation_network.get_public_data()
	var satellite_data: Dictionary = satellite_network.get_public_infrastructure()
	if not hazard_forecast_service.is_stale(
		p_game_day,
		observation_data.get("data_version", 0),
		satellite_data.get("network_version", 0),
	):
		return
	hazard_forecast_service.build_forecast(
		p_game_day,
		_get_forecast_capabilities(),
		observation_data,
		satellite_data,
		_get_public_census_snapshot(),
	)


func _get_forecast_capabilities() -> Dictionary:
	if tech_tree == null and knowledge_system == null:
		return {}
	return {
		"hazard_warning": (
			knowledge_system != null and knowledge_system.has_capability("hazard_warning")
		) or (tech_tree != null and tech_tree.is_unlocked("telescope")),
		"regional_hazard_projection": (
			knowledge_system != null and knowledge_system.has_capability("regional_hazard_projection")
		) or (tech_tree != null and tech_tree.is_unlocked("observatory") and tech_tree.is_unlocked("computer")),
		"casualty_estimation": knowledge_system != null and knowledge_system.has_capability("casualty_estimation"),
		"knowledge_loss_projection": knowledge_system != null and knowledge_system.has_capability("knowledge_loss_projection"),
	}


func _get_current_public_risk_zones() -> Array[int]:
	var result: Array[int] = []
	if planet_zones == null:
		return result
	var average: Dictionary = planet_zones.get_average_environment()
	var average_radiation: float = average.get("radiation", 0.0)
	for zone in planet_zones.zones:
		if zone.radiation >= average_radiation:
			result.append(zone.zone_id)
			if result.size() >= 12:
				break
	return result


func _get_public_census_snapshot() -> Dictionary:
	if entities == null:
		return {"complete": false}
	return {
		"complete": true,
		"population": entities.population.total,
		"exposed_population": maxi(0, entities.population.total - entities.population.storage_capacity),
		"knowledge_carrier_ranges": {},
	}


func get_public_orbit_prediction(p_requested_steps: int, p_dt: float) -> Array:
	if environment == null or hazard_forecast_service == null:
		return []
	var snapshot: Dictionary = hazard_forecast_service.get_public_snapshot()
	var level: int = snapshot.get("level", HazardForecastServiceScript.ForecastLevel.NONE)
	if level < HazardForecastServiceScript.ForecastLevel.REGIONAL_RISK:
		return []
	var allowed_steps := 24
	if (knowledge_system != null and knowledge_system.has_capability("chaos_prediction")) or (tech_tree != null and tech_tree.is_unlocked("chaos_prediction")):
		allowed_steps = 80
	var satellite_data: Dictionary = satellite_network.get_public_infrastructure()
	if satellite_data.get("spatial_coverage", 0.0) >= 0.6:
		allowed_steps = 160
	return environment.predict_trajectories(mini(maxi(0, p_requested_steps), allowed_steps), p_dt)
