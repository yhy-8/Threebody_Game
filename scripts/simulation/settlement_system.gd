class_name SettlementSystem
extends RefCounted
## Capital, settlements, regional population, and information-bounded zone knowledge.

const CapitalSelectionServiceScript = preload("res://scripts/simulation/capital_selection_service.gd")
const PlanetZoneManagerScript = preload("res://scripts/simulation/planet_zones.gd")
const STATE_VERSION := 3
const LOCAL_FOOD_PER_PERSON_PER_DAY := 0.04
const OUTPOST_MINIMUM_POPULATION := 5
const OUTPOST_RESERVE_DAYS := 7.0
const DYNAMIC_PUBLIC_FIELDS: Array[String] = [
	"temperature", "air_temperature", "radiation", "light_intensity", "atmosphere_state", "updated_game_day",
]

enum ZoneKnowledgeLevel { UNKNOWN, OBSERVED, FAMILIAR, SURVEYED, MONITORED }

const LEVEL_NAMES: Dictionary = {
	ZoneKnowledgeLevel.UNKNOWN: "未知",
	ZoneKnowledgeLevel.OBSERVED: "远观",
	ZoneKnowledgeLevel.FAMILIAR: "熟悉",
	ZoneKnowledgeLevel.SURVEYED: "已勘探",
	ZoneKnowledgeLevel.MONITORED: "持续监测",
}

var capital_zone_id: int = -1
var visible_zone_ids: Array[int] = []
var zone_knowledge: Dictionary = {}
var region_population: Dictionary = {}
var settlements: Dictionary = {}
var candidate_views: Array = []
var selection_service


func _init() -> void:
	selection_service = CapitalSelectionServiceScript.new()
	_initialize_empty_zones()


func initialize_new(p_zone_manager, p_population: int, p_scenario_rules: Dictionary) -> bool:
	_initialize_empty_zones()
	capital_zone_id = -1
	visible_zone_ids.clear()
	settlements.clear()
	var public_views: Array = []
	for zone in p_zone_manager.zones:
		# The opening choice stays away from clipped polar rows so its first live view is a full 3x3 block.
		if zone.lat_index <= 0 or zone.lat_index >= PlanetZoneManagerScript.LATITUDE_DIVISIONS - 1:
			continue
		public_views.append(_build_observed_view(zone, 0.32, 0.0))
	var ranked: Array = selection_service.rank_candidates(selection_service.build_candidate_views(public_views, p_scenario_rules))
	candidate_views = ranked.slice(0, mini(6, ranked.size()))
	if candidate_views.is_empty():
		return false
	region_population[-1] = maxi(0, p_population)
	return true


func confirm_capital(p_zone_id: int, p_zone_manager, p_population: int, p_game_day: float) -> Dictionary:
	if capital_zone_id >= 0:
		return {"success": false, "message": "文明发源地已经确认；迁都需要独立操作"}
	var candidate: Dictionary = get_candidate_view(p_zone_id)
	if candidate.is_empty():
		return {"success": false, "message": "请选择公开候选区域"}
	var validation: Dictionary = selection_service.validate_selection(p_zone_id, candidate.get("known", {}))
	if not validation.get("success", false):
		return validation
	capital_zone_id = p_zone_id
	_initialize_empty_zone_knowledge()
	region_population.erase(-1)
	region_population[p_zone_id] = maxi(0, p_population)
	settlements[p_zone_id] = _default_settlement(p_zone_id, p_population, "文明发源地")
	refresh_visibility(p_zone_manager, p_game_day)
	return {"success": true, "message": "区域 #%d 已确认为文明发源地" % p_zone_id, "visible_zone_ids": visible_zone_ids.duplicate()}


func get_candidate_view(p_zone_id: int) -> Dictionary:
	for candidate_value in candidate_views:
		var candidate: Dictionary = candidate_value
		if int(candidate.get("zone_id", -1)) == p_zone_id:
			return candidate.duplicate(true)
	return {}


func get_zone_knowledge(p_zone_id: int) -> Dictionary:
	if not zone_knowledge.has(p_zone_id):
		return _public_knowledge_record(_knowledge_record(ZoneKnowledgeLevel.UNKNOWN, {"zone_id": p_zone_id}, 0.0, 0.0, ["地形", "环境", "资源", "路线"], false))
	return _public_knowledge_record(zone_knowledge[p_zone_id])


func is_zone_visible(p_zone_id: int) -> bool:
	return p_zone_id in visible_zone_ids


func get_public_zone_summaries(p_zone_manager, p_entities) -> Array:
	var result: Array = []
	for zone_id in range(p_zone_manager.zones.size()):
		var zone = p_zone_manager.get_zone(zone_id)
		var record := get_zone_knowledge(zone_id)
		var level := int(record.get("level", ZoneKnowledgeLevel.UNKNOWN))
		var public_data: Dictionary = record.get("public_data", {})
		var known_environment := bool(record.get("live_visible", false))
		result.append({
			"id": zone_id,
			"lat_i": zone.lat_index,
			"lon_i": zone.lon_index,
			"known": known_environment,
			"knowledge_level": level,
			"knowledge_name": LEVEL_NAMES.get(level, "未知"),
			"temp": public_data.get("temperature", 0.0),
			"rad": public_data.get("radiation", 0.0),
			"light": public_data.get("light_intensity", 0.0),
			"atmosphere_state": public_data.get("atmosphere_state", "未知"),
			"terrain": public_data.get("terrain", "未知"),
			"terrain_known": public_data.has("terrain"),
			"buildings": p_entities.get_buildings_in_zone(zone_id).size() if known_environment else 0,
			"stale": record.get("stale", false),
		})
	return result


func refresh_known_environment(p_zone_manager, p_game_day: float) -> void:
	refresh_visibility(p_zone_manager, p_game_day)
	for zone_id in zone_knowledge:
		var record: Dictionary = zone_knowledge[zone_id]
		if not bool(record.get("live_visible", false)):
			continue
		var zone = p_zone_manager.get_zone(int(zone_id))
		var public_data: Dictionary = record.get("public_data", {})
		public_data["temperature"] = zone.temperature
		public_data["air_temperature"] = zone.air_temperature
		public_data["radiation"] = zone.radiation
		public_data["light_intensity"] = zone.light_intensity
		public_data["atmosphere_state"] = zone.get_atmosphere_state()
		public_data["updated_game_day"] = p_game_day
		record["updated_game_day"] = p_game_day
		record["stale"] = false
		record["stale_reason"] = ""


func refresh_visibility(p_zone_manager, p_game_day: float) -> void:
	var covered: Dictionary = {}
	for zone_key in region_population:
		var occupied_zone_id := int(zone_key)
		if occupied_zone_id < 0 or get_population(occupied_zone_id) <= 0:
			continue
		covered[occupied_zone_id] = true
		for neighbor_id in p_zone_manager.get_zone_neighborhood(occupied_zone_id):
			covered[int(neighbor_id)] = true
	visible_zone_ids.clear()
	for zone_id in range(PlanetZoneManagerScript.TOTAL_ZONES):
		var record: Dictionary = zone_knowledge[zone_id]
		var live_visible := covered.has(zone_id)
		record["live_visible"] = live_visible
		if not live_visible:
			_strip_dynamic_public_data(record)
			continue
		visible_zone_ids.append(zone_id)
		var zone = p_zone_manager.get_zone(zone_id)
		var current_level := int(record.get("knowledge_level", ZoneKnowledgeLevel.UNKNOWN))
		var minimum_level := ZoneKnowledgeLevel.FAMILIAR if get_population(zone_id) > 0 else ZoneKnowledgeLevel.OBSERVED
		if current_level < minimum_level:
			record["knowledge_level"] = minimum_level
		var refreshed_view := (
			_build_familiar_view(zone, 0.58, p_game_day)
			if get_population(zone_id) > 0
			else _build_observed_view(zone, 0.42, p_game_day)
		)
		for key in refreshed_view:
			record["public_data"][key] = refreshed_view[key]
		record["confidence"] = maxf(float(record.get("confidence", 0.0)), 0.58 if get_population(zone_id) > 0 else 0.42)
		record["updated_game_day"] = p_game_day
		record["stale"] = false
		record["stale_reason"] = ""


func apply_survey_result(p_zone_id: int, p_public_observations: Dictionary, p_confidence: float, p_game_day: float, p_source_id: String) -> bool:
	if p_zone_id < 0 or p_zone_id >= PlanetZoneManagerScript.TOTAL_ZONES or p_source_id.is_empty():
		return false
	var current: Dictionary = zone_knowledge[p_zone_id]
	if p_source_id in current.get("source_ids", []):
		return false
	var source_ids: Array = current.get("source_ids", []).duplicate()
	source_ids.append(p_source_id)
	var public_data: Dictionary = current.get("public_data", {})
	for key in p_public_observations:
		public_data[key] = p_public_observations[key]
	zone_knowledge[p_zone_id] = _knowledge_record(
		ZoneKnowledgeLevel.SURVEYED, public_data, clampf(p_confidence, 0.0, 1.0), p_game_day,
		["超出当前测量精度的储量", "未来环境与轨道"], is_zone_visible(p_zone_id)
	)
	zone_knowledge[p_zone_id]["source_ids"] = source_ids
	if not is_zone_visible(p_zone_id):
		_strip_dynamic_public_data(zone_knowledge[p_zone_id])
	return true


func mark_knowledge_stale(p_zone_id: int, p_reason: String) -> bool:
	if not zone_knowledge.has(p_zone_id):
		return false
	zone_knowledge[p_zone_id]["stale"] = true
	zone_knowledge[p_zone_id]["stale_reason"] = p_reason
	return true


func get_population(p_zone_id: int) -> int:
	return maxi(0, int(region_population.get(p_zone_id, 0)))


func move_population(p_origin: int, p_destination: int, p_count: int) -> bool:
	if p_count <= 0 or get_population(p_origin) < p_count:
		return false
	region_population[p_origin] = get_population(p_origin) - p_count
	region_population[p_destination] = get_population(p_destination) + p_count
	if settlements.has(p_origin):
		settlements[p_origin]["population"] = region_population[p_origin]
	if settlements.has(p_destination):
		settlements[p_destination]["population"] = region_population[p_destination]
	return true


func embark_population(p_origin: int, p_count: int) -> bool:
	if p_count <= 0 or get_population(p_origin) < p_count:
		return false
	region_population[p_origin] = get_population(p_origin) - p_count
	if settlements.has(p_origin):
		settlements[p_origin]["population"] = region_population[p_origin]
	return true


func disembark_population(p_destination: int, p_count: int) -> bool:
	if p_destination < 0 or p_count <= 0:
		return false
	region_population[p_destination] = get_population(p_destination) + p_count
	if not settlements.has(p_destination):
		settlements[p_destination] = _default_settlement(p_destination, region_population[p_destination], "区域聚落 #%d" % p_destination)
	else:
		settlements[p_destination]["population"] = region_population[p_destination]
	return true


func reconcile_population_total(p_civilization_total: int, p_in_transit_population: int) -> void:
	var target_regional_total := maxi(0, p_civilization_total - maxi(0, p_in_transit_population))
	var current_regional_total := 0
	for value in region_population.values():
		current_regional_total += maxi(0, int(value))
	var difference := target_regional_total - current_regional_total
	if difference > 0:
		var growth_zone := capital_zone_id if capital_zone_id >= 0 else -1
		region_population[growth_zone] = get_population(growth_zone) + difference
	elif difference < 0:
		var remaining_loss := -difference
		var populated_zone_ids: Array = region_population.keys()
		populated_zone_ids.sort_custom(func(a, b): return get_population(int(a)) > get_population(int(b)))
		for zone_key in populated_zone_ids:
			var zone_id := int(zone_key)
			var loss := mini(remaining_loss, get_population(zone_id))
			region_population[zone_id] = get_population(zone_id) - loss
			remaining_loss -= loss
			if remaining_loss <= 0:
				break
	for zone_key in settlements:
		settlements[zone_key]["population"] = get_population(int(zone_key))


func refresh_settlement_status(p_logistics, p_entities, p_knowledge_system, p_game_day: float) -> void:
	for zone_key in settlements:
		var zone_id := int(zone_key)
		var settlement: Dictionary = settlements[zone_key]
		var metrics := _calculate_support_metrics(zone_id, p_logistics, p_entities)
		var communication_level := 0
		if zone_id == capital_zone_id:
			communication_level = 2
		elif p_knowledge_system != null and p_knowledge_system.has_capability("symbolic_recording"):
			communication_level = 1
		if p_logistics != null and capital_zone_id >= 0 and p_logistics.has_connection("road", zone_id, capital_zone_id):
			communication_level = 2
		var population := get_population(zone_id)
		var daily_need := population * LOCAL_FOOD_PER_PERSON_PER_DAY
		var reserve_days := float(metrics["food_reserve"]) / daily_need if daily_need > 0.0 else 0.0
		var supply_status := "无人驻留"
		if population > 0:
			if float(metrics["food_output_per_day"]) + 1e-6 >= daily_need and int(metrics["shelter_capacity"]) >= population:
				supply_status = "当地自给"
			elif reserve_days >= OUTPOST_RESERVE_DAYS:
				supply_status = "储备充足"
			elif reserve_days >= 3.0:
				supply_status = "需要补给"
			else:
				supply_status = "补给告急"
		settlement["population"] = population
		settlement["supply_status"] = supply_status
		settlement["communication_level"] = communication_level
		settlement["shelter_capacity"] = metrics["shelter_capacity"]
		settlement["storage_capacity"] = metrics["storage_capacity"]
		settlement["food_output_per_day"] = metrics["food_output_per_day"]
		settlement["food_reserve_days"] = reserve_days
		settlement["support_capacity"] = mini(int(metrics["shelter_capacity"]), int(floor(float(metrics["food_output_per_day"]) / LOCAL_FOOD_PER_PERSON_PER_DAY)))
		settlement["status_updated_game_day"] = p_game_day


func get_settlement(p_zone_id: int) -> Dictionary:
	if not settlements.has(p_zone_id):
		return {}
	return (settlements[p_zone_id] as Dictionary).duplicate(true)


func get_outpost_upgrade_requirements(p_zone_id: int, p_logistics, p_entities, p_knowledge_system, p_route_available: bool, p_game_day: float) -> Dictionary:
	refresh_settlement_status(p_logistics, p_entities, p_knowledge_system, p_game_day)
	var settlement := get_settlement(p_zone_id)
	if settlement.is_empty():
		return {"success": false, "message": "该区域尚未建立前哨", "missing": ["前哨"]}
	if str(settlement.get("type", "")) != "outpost":
		return {"success": false, "message": "该驻点已是常设聚落", "missing": []}
	var missing: Array[String] = []
	var population := int(settlement.get("population", 0))
	if population < OUTPOST_MINIMUM_POPULATION:
		missing.append("当地人口至少 %d（当前 %d）" % [OUTPOST_MINIMUM_POPULATION, population])
	if int(settlement.get("shelter_capacity", 0)) < population:
		missing.append("已完工庇护容量覆盖当地人口")
	var daily_need := population * LOCAL_FOOD_PER_PERSON_PER_DAY
	if float(settlement.get("food_output_per_day", 0.0)) + 1e-6 < daily_need:
		missing.append("实际运行的当地食物产出覆盖日需")
	if float(settlement.get("food_reserve_days", 0.0)) + 1e-6 < OUTPOST_RESERVE_DAYS:
		missing.append("当地食物储备至少 %.0f 天" % OUTPOST_RESERVE_DAYS)
	if not p_route_available:
		missing.append("与首都之间可确认的步行路线")
	if p_knowledge_system == null or not p_knowledge_system.has_capability("symbolic_recording"):
		missing.append("符号记录与管理能力")
	return {
		"success": missing.is_empty(),
		"message": "已满足常设聚落条件" if missing.is_empty() else "尚缺：%s" % "；".join(missing),
		"missing": missing,
		"settlement": settlement,
	}


func upgrade_outpost(p_zone_id: int, p_logistics, p_entities, p_knowledge_system, p_route_available: bool, p_game_day: float) -> Dictionary:
	var requirements := get_outpost_upgrade_requirements(p_zone_id, p_logistics, p_entities, p_knowledge_system, p_route_available, p_game_day)
	if not requirements.get("success", false):
		return requirements
	settlements[p_zone_id]["type"] = "settlement"
	settlements[p_zone_id]["upgraded_game_day"] = p_game_day
	settlements[p_zone_id]["name"] = "常设聚落 #%d" % p_zone_id
	return {"success": true, "message": "区域 #%d 的前哨已升级为常设聚落" % p_zone_id}


func complete_capital_relocation(p_target_zone_id: int, p_game_day: float) -> bool:
	if not settlements.has(p_target_zone_id) or str(settlements[p_target_zone_id].get("type", "")) != "settlement":
		return false
	var old_capital := capital_zone_id
	if settlements.has(old_capital):
		settlements[old_capital]["type"] = "settlement"
		settlements[old_capital]["name"] = "旧都聚落 #%d" % old_capital
	capital_zone_id = p_target_zone_id
	settlements[p_target_zone_id]["type"] = "capital"
	settlements[p_target_zone_id]["name"] = "文明首都 #%d" % p_target_zone_id
	settlements[p_target_zone_id]["capital_since_game_day"] = p_game_day
	return true


func get_state() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"capital_zone_id": capital_zone_id,
		"visible_zone_ids": visible_zone_ids.duplicate(),
		"zone_knowledge": zone_knowledge.duplicate(true),
		"region_population": region_population.duplicate(),
		"settlements": settlements.duplicate(true),
		"candidate_views": candidate_views.duplicate(true),
	}


func load_state(p_data: Dictionary) -> bool:
	if int(p_data.get("state_version", -1)) != STATE_VERSION:
		return false
	for key in ["zone_knowledge", "region_population", "settlements"]:
		if not p_data.get(key, {}) is Dictionary:
			return false
	capital_zone_id = int(p_data.get("capital_zone_id", -1))
	if capital_zone_id < -1 or capital_zone_id >= PlanetZoneManagerScript.TOTAL_ZONES:
		return false
	if not p_data.get("visible_zone_ids", null) is Array:
		return false
	visible_zone_ids.clear()
	for zone_value in p_data["visible_zone_ids"]:
		visible_zone_ids.append(int(zone_value))
	zone_knowledge.clear()
	for zone_key in p_data.get("zone_knowledge", {}):
		zone_knowledge[int(zone_key)] = (p_data["zone_knowledge"][zone_key] as Dictionary).duplicate(true)
	region_population.clear()
	for zone_key in p_data.get("region_population", {}):
		region_population[int(zone_key)] = maxi(0, int(p_data["region_population"][zone_key]))
	settlements.clear()
	for zone_key in p_data.get("settlements", {}):
		settlements[int(zone_key)] = (p_data["settlements"][zone_key] as Dictionary).duplicate(true)
	candidate_views = (p_data.get("candidate_views", []) as Array).duplicate(true)
	return true


func _initialize_empty_zones() -> void:
	_initialize_empty_zone_knowledge()
	region_population.clear()
	for zone_id in range(PlanetZoneManagerScript.TOTAL_ZONES):
		region_population[zone_id] = 0


func _initialize_empty_zone_knowledge() -> void:
	zone_knowledge.clear()
	visible_zone_ids.clear()
	for zone_id in range(PlanetZoneManagerScript.TOTAL_ZONES):
		zone_knowledge[zone_id] = _knowledge_record(
			ZoneKnowledgeLevel.UNKNOWN, {"zone_id": zone_id}, 0.0, 0.0,
			["地形", "环境", "资源", "路线"], false
		)


func _build_observed_view(p_zone, p_confidence: float, p_game_day: float) -> Dictionary:
	return {
		"zone_id": p_zone.zone_id,
		"latitude": p_zone.lat_center,
		"longitude": p_zone.lon_center,
		"terrain": p_zone.terrain_type,
		"temperature": p_zone.temperature,
		"air_temperature": p_zone.air_temperature,
		"radiation": p_zone.radiation,
		"light_intensity": p_zone.light_intensity,
		"atmosphere_state": p_zone.get_atmosphere_state(),
		"surface_signs": _surface_signs(p_zone.terrain_type, p_zone.light_intensity),
		"confidence": p_confidence,
		"updated_game_day": p_game_day,
	}


func _build_familiar_view(p_zone, p_confidence: float, p_game_day: float) -> Dictionary:
	var view := _build_observed_view(p_zone, p_confidence, p_game_day)
	view["route_familiarity"] = "常用步行路径"
	view["surface_resource_signs"] = _surface_signs(p_zone.terrain_type, p_zone.light_intensity)
	return view


func _surface_signs(p_terrain: String, p_light: float) -> Array[String]:
	var signs: Array[String] = []
	if p_terrain in ["平原", "盆地", "丘陵"]:
		signs.append("可见植被或低地迹象")
	if p_terrain in ["山地", "峡谷", "高原"]:
		signs.append("裸露岩层与坡地")
	if p_light < 0.08:
		signs.append("当前光照微弱")
	return signs


func _knowledge_record(p_level: int, p_public_data: Dictionary, p_confidence: float, p_game_day: float,
		p_unknown_fields: Array, p_live_visible: bool) -> Dictionary:
	return {
		"knowledge_level": p_level,
		"live_visible": p_live_visible,
		"public_data": p_public_data.duplicate(true),
		"confidence": p_confidence,
		"updated_game_day": p_game_day,
		"unknown_fields": p_unknown_fields.duplicate(),
		"source_ids": [],
		"stale": false,
		"stale_reason": "",
	}


func _public_knowledge_record(p_record: Dictionary) -> Dictionary:
	var result := p_record.duplicate(true)
	var historical_level := int(result.get("knowledge_level", ZoneKnowledgeLevel.UNKNOWN))
	var live_visible := bool(result.get("live_visible", false))
	result["historical_level"] = historical_level
	result["level"] = historical_level if live_visible else ZoneKnowledgeLevel.UNKNOWN
	result["level_name"] = LEVEL_NAMES.get(result["level"], "未知")
	result["terrain_known"] = (result.get("public_data", {}) as Dictionary).has("terrain")
	return result


func _strip_dynamic_public_data(p_record: Dictionary) -> void:
	var public_data: Dictionary = p_record.get("public_data", {})
	for key in DYNAMIC_PUBLIC_FIELDS:
		public_data.erase(key)
	p_record["stale"] = true
	p_record["stale_reason"] = "当前没有人口覆盖，实时环境不可知"


func _default_settlement(p_zone_id: int, p_population: int, p_name: String) -> Dictionary:
	return {
		"settlement_id": "settlement:%02d" % p_zone_id,
		"zone_id": p_zone_id,
		"name": p_name,
		"type": "capital" if p_zone_id == capital_zone_id else "outpost",
		"population": maxi(0, p_population),
		"supply_status": "local",
		"communication_level": 0,
	}


func _calculate_support_metrics(p_zone_id: int, p_logistics, p_entities) -> Dictionary:
	var shelter_capacity := 0
	var storage_capacity := 0
	var food_output_per_day := 0.0
	if p_entities != null:
		for building in p_entities.get_buildings_in_zone(p_zone_id):
			if not building.active or building.destroyed or building.under_construction:
				continue
			storage_capacity += maxi(0, int(building.storage_capacity))
			if building.building_type in ["shelter", "deep_shelter"]:
				shelter_capacity += maxi(0, int(building.storage_capacity))
			food_output_per_day += maxf(0.0, float(building.last_output_rate.get("food", 0.0)))
	return {
		"shelter_capacity": shelter_capacity,
		"storage_capacity": storage_capacity,
		"food_output_per_day": food_output_per_day,
		"food_reserve": p_logistics.get_local_amount(p_zone_id, "food") if p_logistics != null else 0.0,
	}
