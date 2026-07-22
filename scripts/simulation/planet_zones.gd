class_name PlanetZoneManager
extends RefCounted
## 行星区域管理器 — 72区域 + 自转 + 逐区环境计算


# ── 地形对资源禀赋的基础系数 ──────────────────────────────
const TERRAIN_RESOURCE_TABLE: Dictionary = {
	"平原": {"iron": 0.3, "copper": 0.2, "rare_mineral": 0.05, "fertility": 0.8, "algae": 0.4},
	"高原": {"iron": 0.4, "copper": 0.3, "rare_mineral": 0.30, "fertility": 0.3, "algae": 0.1},
	"山地": {"iron": 0.9, "copper": 0.5, "rare_mineral": 0.20, "fertility": 0.1, "algae": 0.0},
	"峡谷": {"iron": 0.5, "copper": 0.8, "rare_mineral": 0.15, "fertility": 0.2, "algae": 0.3},
	"盆地": {"iron": 0.2, "copper": 0.2, "rare_mineral": 0.05, "fertility": 0.9, "algae": 0.8},
	"丘陵": {"iron": 0.6, "copper": 0.4, "rare_mineral": 0.10, "fertility": 0.5, "algae": 0.2},
}

const TERRAIN_THERMAL_MODIFIER: Dictionary = {
	"平原": 0.0,
	"高原": -6.0,
	"山地": -10.0,
	"峡谷": -2.0,
	"盆地": 3.0,
	"丘陵": -3.0,
}

const TERRAIN_TYPES: Array[String] = ["平原", "高原", "山地", "峡谷", "盆地", "丘陵"]

const LATITUDE_DIVISIONS: int = 6
const LONGITUDE_DIVISIONS: int = 12
const TOTAL_ZONES: int = LATITUDE_DIVISIONS * LONGITUDE_DIVISIONS
const CLIMATE_MODEL_VERSION: int = 2
const KELVIN_OFFSET: float = 273.15
const REFERENCE_RADIATING_TEMPERATURE_K: float = 255.0
const NITROGEN_CONDENSATION_K: float = 77.36
const NITROGEN_TRIPLE_POINT_K: float = 63.15
const OXYGEN_CONDENSATION_K: float = 90.19
const OXYGEN_TRIPLE_POINT_K: float = 54.36


class PlanetZone:
	var zone_id: int
	var lat_index: int
	var lon_index: int
	var lat_center: float
	var lon_center: float
	var lat_bottom: float
	var lat_top: float
	var lon_left: float
	var lon_right: float
	var terrain_type: String
	var temperature: float
	var air_temperature: float
	var radiation: float
	var light_intensity: float
	var nitrogen_gas_fraction: float
	var oxygen_gas_fraction: float
	var resource_deposits: Dictionary
	var fertility: float
	var algae_density: float
	var building_ids: Array
	var area_weight: float

	func _init(p_zone_id: int, p_lat_index: int, p_lon_index: int,
			p_lat_center: float, p_lon_center: float,
			p_lat_bottom: float, p_lat_top: float,
			p_lon_left: float, p_lon_right: float,
			p_terrain_type: String, p_area_weight: float,
			p_resource_deposits: Dictionary, p_fertility: float, p_algae_density: float) -> void:
		zone_id = p_zone_id
		lat_index = p_lat_index
		lon_index = p_lon_index
		lat_center = p_lat_center
		lon_center = p_lon_center
		lat_bottom = p_lat_bottom
		lat_top = p_lat_top
		lon_left = p_lon_left
		lon_right = p_lon_right
		terrain_type = p_terrain_type
		temperature = -273.15
		air_temperature = -273.15
		radiation = 0.0
		light_intensity = 0.0
		nitrogen_gas_fraction = 1.0
		oxygen_gas_fraction = 1.0
		resource_deposits = p_resource_deposits
		fertility = p_fertility
		algae_density = p_algae_density
		building_ids = []
		area_weight = p_area_weight

	func get_work_efficiency() -> float:
		return _calc_work_efficiency(temperature)

	func get_atmospheric_mass_fraction() -> float:
		return clampf(0.01 + 0.78 * nitrogen_gas_fraction + 0.21 * oxygen_gas_fraction, 0.01, 1.0)

	func get_atmosphere_state() -> String:
		var mass_fraction := get_atmospheric_mass_fraction()
		if mass_fraction >= 0.95:
			return "稳定气态"
		if mass_fraction >= 0.70:
			return "局部液化"
		if mass_fraction >= 0.25:
			return "大气稀薄"
		return "局部塌缩"

	static func _calc_work_efficiency(temperature: float) -> float:
		if temperature >= -10.0 and temperature <= 40.0:
			return 1.0
		elif temperature < -80.0 or temperature > 100.0:
			return 0.0
		elif temperature < -10.0:
			return max(0.0, (temperature + 80.0) / 70.0)
		else:
			return max(0.0, (100.0 - temperature) / 60.0)


var zones: Array = []
var rotation_angle: float = 0.0
var rotation_speed: float
var dark_side_scatter: float
var light_norm_divisor: float = 1.0
var surface_response_rate: float
var air_surface_exchange_rate: float
var atmosphere_diffusion_rate: float
var surface_diffusion_rate: float
var atmosphere_redistribution: float
var greenhouse_warming_c: float
var condensation_rate: float
var evaporation_rate: float
var target_start_temperature: float
var target_peak_light: float
var reference_mean_insolation: float = 0.0
var climate_calibration_offset_c: float = 0.0
var _neighbor_cache: Dictionary = {}


func _init(env_config: Dictionary = {}) -> void:
	rotation_speed = env_config.get("rotation_speed", 15.0)
	dark_side_scatter = env_config.get("dark_side_scatter", 0.05)
	surface_response_rate = env_config.get("surface_response_rate", 0.08)
	air_surface_exchange_rate = env_config.get("air_surface_exchange_rate", 0.24)
	atmosphere_diffusion_rate = env_config.get("atmosphere_diffusion_rate", 0.38)
	surface_diffusion_rate = env_config.get("surface_diffusion_rate", 0.035)
	atmosphere_redistribution = env_config.get("atmosphere_redistribution", 0.82)
	greenhouse_warming_c = env_config.get("greenhouse_warming_c", 33.0)
	condensation_rate = env_config.get("condensation_rate", 0.35)
	evaporation_rate = env_config.get("evaporation_rate", 0.12)
	target_start_temperature = env_config.get("target_start_temp", 20.0)
	target_peak_light = env_config.get("target_peak_light", 0.85)
	_init_zones()
	_build_neighbor_cache()


func _init_zones() -> void:
	zones.clear()
	var lat_step: float = 180.0 / LATITUDE_DIVISIONS
	var lon_step: float = 360.0 / LONGITUDE_DIVISIONS

	var zone_id: int = 0
	for lat_i in LATITUDE_DIVISIONS:
		var lat_bottom: float = -90.0 + lat_i * lat_step
		var lat_top: float = lat_bottom + lat_step
		var lat_center: float = (lat_bottom + lat_top) / 2.0
		var area_weight: float = max(0.1, cos(deg_to_rad(lat_center)))

		for lon_i in LONGITUDE_DIVISIONS:
			var lon_left: float = lon_i * lon_step
			var lon_right: float = lon_left + lon_step
			var lon_center: float = (lon_left + lon_right) / 2.0

			var terrain: String = TERRAIN_TYPES[randi() % TERRAIN_TYPES.size()]
			var base: Dictionary = TERRAIN_RESOURCE_TABLE.get(terrain, TERRAIN_RESOURCE_TABLE["平原"])

			var resource_deposits: Dictionary = {}
			for mineral in ["iron", "copper", "rare_mineral"]:
				var base_val: float = base.get(mineral, 0.0)
				var jitter: float = base_val * randf_range(-0.3, 0.3)
				resource_deposits[mineral] = max(0.0, base_val + jitter)

			var base_fert: float = base.get("fertility", 0.5)
			var fertility: float = max(0.0, base_fert + base_fert * randf_range(-0.3, 0.3))

			var base_algae: float = base.get("algae", 0.3)
			var algae_dens: float = max(0.0, base_algae + base_algae * randf_range(-0.3, 0.3))

			var zone: PlanetZone = PlanetZone.new(
				zone_id, lat_i, lon_i,
				lat_center, lon_center,
				lat_bottom, lat_top,
				lon_left, lon_right,
				terrain, area_weight,
				resource_deposits, fertility, algae_dens
			)
			zones.append(zone)
			zone_id += 1


func _build_neighbor_cache() -> void:
	_neighbor_cache.clear()
	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		var lat_i: int = z.lat_index
		var lon_i: int = z.lon_index
		var neighbors: Array = []

		var left_lon: int = wrapi(lon_i - 1, 0, LONGITUDE_DIVISIONS)
		var right_lon: int = wrapi(lon_i + 1, 0, LONGITUDE_DIVISIONS)
		neighbors.append(lat_i * LONGITUDE_DIVISIONS + left_lon)
		neighbors.append(lat_i * LONGITUDE_DIVISIONS + right_lon)

		if lat_i > 0:
			neighbors.append((lat_i - 1) * LONGITUDE_DIVISIONS + lon_i)
		if lat_i < LATITUDE_DIVISIONS - 1:
			neighbors.append((lat_i + 1) * LONGITUDE_DIVISIONS + lon_i)

		_neighbor_cache[z.zone_id] = neighbors


func _apply_two_layer_diffusion(game_days_elapsed: float) -> void:
	if game_days_elapsed <= 0.0:
		return

	var surface_neighbor_averages: Array[float] = []
	var air_neighbor_averages: Array[float] = []
	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		var neighbor_ids: Array = _neighbor_cache.get(z.zone_id, [])
		var surface_total := 0.0
		var air_total := 0.0
		for neighbor_id in neighbor_ids:
			var neighbor: PlanetZone = zones[int(neighbor_id)] as PlanetZone
			surface_total += neighbor.temperature
			air_total += neighbor.air_temperature
		if neighbor_ids.is_empty():
			surface_neighbor_averages.append(z.temperature)
			air_neighbor_averages.append(z.air_temperature)
		else:
			surface_neighbor_averages.append(surface_total / float(neighbor_ids.size()))
			air_neighbor_averages.append(air_total / float(neighbor_ids.size()))

	var surface_factor := 1.0 - exp(-surface_diffusion_rate * game_days_elapsed)
	for zone_index in zones.size():
		var z: PlanetZone = zones[zone_index] as PlanetZone
		var transport_multiplier := sqrt(_get_atmospheric_mass_fraction(z))
		var air_factor := 1.0 - exp(-atmosphere_diffusion_rate * transport_multiplier * game_days_elapsed)
		z.temperature = lerpf(z.temperature, surface_neighbor_averages[zone_index], surface_factor)
		z.air_temperature = lerpf(z.air_temperature, air_neighbor_averages[zone_index], air_factor)


func _get_atmospheric_mass_fraction(zone: PlanetZone) -> float:
	return zone.get_atmospheric_mass_fraction()


func _get_atmosphere_state(zone: PlanetZone) -> String:
	return zone.get_atmosphere_state()


func _gas_fraction_target(air_temperature_c: float, triple_point_k: float, condensation_point_k: float) -> float:
	var air_temperature_k := air_temperature_c + KELVIN_OFFSET
	var normalized := clampf(
		(air_temperature_k - triple_point_k) / maxf(0.01, condensation_point_k - triple_point_k),
		0.0,
		1.0,
	)
	return normalized * normalized * (3.0 - 2.0 * normalized)


func _update_atmospheric_phase(zone: PlanetZone, game_days_elapsed: float) -> void:
	var nitrogen_target := _gas_fraction_target(
		zone.air_temperature, NITROGEN_TRIPLE_POINT_K, NITROGEN_CONDENSATION_K
	)
	var oxygen_target := _gas_fraction_target(
		zone.air_temperature, OXYGEN_TRIPLE_POINT_K, OXYGEN_CONDENSATION_K
	)
	var nitrogen_rate := condensation_rate if nitrogen_target < zone.nitrogen_gas_fraction else evaporation_rate
	var oxygen_rate := condensation_rate if oxygen_target < zone.oxygen_gas_fraction else evaporation_rate
	zone.nitrogen_gas_fraction = move_toward(
		zone.nitrogen_gas_fraction, nitrogen_target, nitrogen_rate * game_days_elapsed
	)
	zone.oxygen_gas_fraction = move_toward(
		zone.oxygen_gas_fraction, oxygen_target, oxygen_rate * game_days_elapsed
	)


func _get_zone_normal(zone: PlanetZone) -> Vector3:
	var lat_rad: float = deg_to_rad(zone.lat_center)
	var lon_rad: float = deg_to_rad(zone.lon_center + rotation_angle)
	var nx: float = cos(lat_rad) * cos(lon_rad)
	var ny: float = sin(lat_rad)
	var nz: float = cos(lat_rad) * sin(lon_rad)
	return Vector3(nx, ny, nz)


func update(dt: float, time_scale: float, stars_data: Array, planet_position: Vector3) -> void:
	var game_days_elapsed: float = dt * time_scale
	rotation_angle += rotation_speed * game_days_elapsed
	rotation_angle = fmod(rotation_angle, 360.0)

	var active_stars: Array = _collect_active_stars(stars_data, planet_position)
	_compute_zone_environments(active_stars, game_days_elapsed)


func initialize_temperatures(stars_data: Array, planet_position: Vector3) -> void:
	var active_stars: Array = _collect_active_stars(stars_data, planet_position)
	var forcing := _calculate_forcing(active_stars)
	_calibrate_reference_climate(forcing)
	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		z.nitrogen_gas_fraction = 1.0
		z.oxygen_gas_fraction = 1.0
		var target := _get_radiative_target(
			z, float(forcing["lights"][z.zone_id]), float(forcing["mean_light"])
		)
		z.temperature = target
		z.air_temperature = target

	# 在固定开局光照下做小步长气候旋转，避免用线性绝对零度初值制造假极端区。
	for _spinup_step in 48:
		_advance_climate(forcing, 0.25, false)
	_recenter_initial_climate()


func _collect_active_stars(stars_data: Array, planet_position: Vector3) -> Array:
	var active_stars: Array = []
	for s in stars_data:
		var sd: Dictionary = s as Dictionary
		if sd.get("is_planet", false):
			continue
		var star_pos: Vector3 = sd["position"]
		var direction: Vector3 = star_pos - planet_position
		var dist: float = direction.length()
		if dist < 1e-6:
			continue
		active_stars.append({
			"direction": direction.normalized(),
			"distance": dist,
			"mass": sd.get("mass", 1000.0),
		})
	return active_stars


func _compute_zone_environments(active_stars: Array, game_days_elapsed: float) -> void:
	var forcing := _calculate_forcing(active_stars)
	if reference_mean_insolation <= 1e-9:
		_calibrate_reference_climate(forcing)
	_advance_climate(forcing, absf(game_days_elapsed), true)


func _calculate_forcing(active_stars: Array) -> Dictionary:
	var lights: Array[float] = []
	var radiations: Array[float] = []
	var weighted_light := 0.0
	var total_weight := 0.0
	var peak_light := 0.0
	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		var normal: Vector3 = _get_zone_normal(z)
		var local_light := 0.0
		var local_radiation := 0.0

		for star in active_stars:
			var s: Dictionary = star as Dictionary
			var star_dir: Vector3 = s["direction"]
			var cos_angle: float = normal.dot(star_dir)
			var dist: float = s["distance"]
			var mass: float = s["mass"]

			var scatter_factor := maxf(dark_side_scatter, cos_angle)
			local_light += mass * 10.0 / (dist * dist + 100.0) * scatter_factor

			var safe_dist: float = max(5.0, dist)
			local_radiation += mass * 200.0 / pow(safe_dist, 2.5) * scatter_factor

		lights.append(local_light)
		radiations.append(local_radiation)
		weighted_light += local_light * z.area_weight
		total_weight += z.area_weight
		peak_light = maxf(peak_light, local_light)

	return {
		"lights": lights,
		"radiations": radiations,
		"mean_light": weighted_light / total_weight if total_weight > 0.0 else 0.0,
		"peak_light": peak_light,
	}


func _calibrate_reference_climate(forcing: Dictionary) -> void:
	reference_mean_insolation = maxf(1e-9, float(forcing.get("mean_light", 0.0)))
	light_norm_divisor = maxf(1e-9, float(forcing.get("peak_light", 0.0)) / maxf(0.01, target_peak_light))
	climate_calibration_offset_c = 0.0
	var weighted_target := 0.0
	var total_weight := 0.0
	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		weighted_target += _get_radiative_target(
			z, float(forcing["lights"][z.zone_id]), float(forcing["mean_light"])
		) * z.area_weight
		total_weight += z.area_weight
	if total_weight > 0.0:
		climate_calibration_offset_c = target_start_temperature - weighted_target / total_weight


func _get_radiative_target(zone: PlanetZone, local_light: float, current_mean_light: float) -> float:
	var atmosphere_mass := _get_atmospheric_mass_fraction(zone)
	var transport_fraction := clampf(atmosphere_redistribution * sqrt(atmosphere_mass), 0.0, 0.95)
	var global_flux_ratio := current_mean_light / maxf(reference_mean_insolation, 1e-9)
	var local_flux_ratio := local_light / maxf(current_mean_light, 1e-9)
	var effective_flux_ratio := global_flux_ratio * lerpf(local_flux_ratio, 1.0, transport_fraction)
	var radiating_temperature_k := REFERENCE_RADIATING_TEMPERATURE_K * pow(maxf(0.005, effective_flux_ratio), 0.25)
	var terrain_modifier: float = TERRAIN_THERMAL_MODIFIER.get(zone.terrain_type, 0.0)
	return (
		radiating_temperature_k - KELVIN_OFFSET
		+ greenhouse_warming_c * atmosphere_mass
		+ terrain_modifier
		+ climate_calibration_offset_c
	)


func _advance_climate(forcing: Dictionary, game_days_elapsed: float, update_phase_state: bool) -> void:
	var mean_light := float(forcing.get("mean_light", 0.0))
	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		z.radiation = float(forcing["radiations"][z.zone_id])
		z.light_intensity = minf(1.0, float(forcing["lights"][z.zone_id]) / light_norm_divisor)
		if update_phase_state:
			_update_atmospheric_phase(z, game_days_elapsed)

	if game_days_elapsed <= 0.0:
		return
	var surface_factor := 1.0 - exp(-surface_response_rate * game_days_elapsed)
	var exchange_factor := 1.0 - exp(-air_surface_exchange_rate * game_days_elapsed)
	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		var target := _get_radiative_target(z, float(forcing["lights"][z.zone_id]), mean_light)
		z.temperature = lerpf(z.temperature, target, surface_factor)
		var temperature_gap := z.temperature - z.air_temperature
		z.temperature -= temperature_gap * exchange_factor * 0.35
		z.air_temperature += temperature_gap * exchange_factor * 0.65
	_apply_two_layer_diffusion(game_days_elapsed)


func _recenter_initial_climate() -> void:
	var average := get_average_environment()
	var offset := target_start_temperature - float(average.get("temperature", target_start_temperature))
	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		z.temperature += offset
		z.air_temperature += offset


func get_zone(zone_id: int) -> PlanetZone:
	if zone_id >= 0 and zone_id < zones.size():
		return zones[zone_id] as PlanetZone
	return null


func get_zone_normal(zone_id: int) -> Vector3:
	var zone := get_zone(zone_id)
	if zone == null:
		return Vector3.ZERO
	return _get_zone_normal(zone)


func get_zone_neighbors(zone_id: int) -> Array:
	if get_zone(zone_id) == null:
		return []
	return (_neighbor_cache.get(zone_id, []) as Array).duplicate()


func get_zone_at(lat: float, lon: float) -> PlanetZone:
	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		if z.lat_bottom <= lat and lat < z.lat_top and z.lon_left <= lon and lon < z.lon_right:
			return z
	return null


func get_average_environment() -> Dictionary:
	var total_weight: float = 0.0
	var avg_temp: float = 0.0
	var avg_air_temp: float = 0.0
	var avg_rad: float = 0.0
	var avg_light: float = 0.0
	var avg_atmosphere_mass: float = 0.0

	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		var w: float = z.area_weight
		avg_temp += z.temperature * w
		avg_air_temp += z.air_temperature * w
		avg_rad += z.radiation * w
		avg_light += z.light_intensity * w
		avg_atmosphere_mass += _get_atmospheric_mass_fraction(z) * w
		total_weight += w

	if total_weight > 0.0:
		avg_temp /= total_weight
		avg_air_temp /= total_weight
		avg_rad /= total_weight
		avg_light /= total_weight
		avg_atmosphere_mass /= total_weight

	var result: Dictionary
	result = {
		"temperature": avg_temp,
		"air_temperature": avg_air_temp,
		"radiation": avg_rad,
		"light_intensity": avg_light,
		"atmosphere_pressure_fraction": avg_atmosphere_mass,
	}
	return result


func get_zone_environment(zone_id: int) -> Dictionary:
	var zone: PlanetZone = get_zone(zone_id)
	if zone == null:
		return {}
	var result: Dictionary
	result = {
		"zone_id": zone.zone_id,
		"lat_center": zone.lat_center,
		"lon_center": zone.lon_center,
		"lat_bottom": zone.lat_bottom,
		"lat_top": zone.lat_top,
		"lon_left": zone.lon_left,
		"lon_right": zone.lon_right,
		"terrain_type": zone.terrain_type,
		"temperature": zone.temperature,
		"air_temperature": zone.air_temperature,
		"radiation": zone.radiation,
		"light_intensity": zone.light_intensity,
		"nitrogen_gas_fraction": zone.nitrogen_gas_fraction,
		"oxygen_gas_fraction": zone.oxygen_gas_fraction,
		"atmosphere_pressure_fraction": _get_atmospheric_mass_fraction(zone),
		"atmosphere_state": _get_atmosphere_state(zone),
		"building_count": zone.building_ids.size(),
		"area_weight": zone.area_weight,
		"resource_deposits": zone.resource_deposits.duplicate(),
		"fertility": zone.fertility,
		"algae_density": zone.algae_density,
		"work_efficiency": zone.get_work_efficiency(),
	}
	return result


func get_illuminated_zones() -> Array:
	var result: Array = []
	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		if z.light_intensity > 0.05:
			result.append(z.zone_id)
	return result


func get_all_zones_summary() -> Array:
	var result: Array = []
	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		result.append({
			"id": z.zone_id,
			"lat_i": z.lat_index,
			"lon_i": z.lon_index,
			"temp": z.temperature,
			"air_temp": z.air_temperature,
			"rad": z.radiation,
			"light": z.light_intensity,
			"atmosphere": _get_atmospheric_mass_fraction(z),
			"atmosphere_state": _get_atmosphere_state(z),
			"terrain": z.terrain_type,
			"buildings": z.building_ids.size(),
			"fertility": z.fertility,
			"algae": z.algae_density,
			"deposits": z.resource_deposits.duplicate(),
		})
	return result


func add_building_to_zone(zone_id: int, building_id: int) -> bool:
	var zone: PlanetZone = get_zone(zone_id)
	if zone != null:
		zone.building_ids.append(building_id)
		return true
	return false


func remove_building_from_zone(zone_id: int, building_id: int) -> void:
	var zone: PlanetZone = get_zone(zone_id)
	if zone != null and building_id in zone.building_ids:
		zone.building_ids.erase(building_id)


func get_state() -> Dictionary:
	var zones_data: Array = []
	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		zones_data.append({
			"zone_id": z.zone_id,
			"terrain_type": z.terrain_type,
			"building_ids": z.building_ids.duplicate(),
			"temperature": z.temperature,
			"air_temperature": z.air_temperature,
			"radiation": z.radiation,
			"light_intensity": z.light_intensity,
			"nitrogen_gas_fraction": z.nitrogen_gas_fraction,
			"oxygen_gas_fraction": z.oxygen_gas_fraction,
			"resource_deposits": z.resource_deposits.duplicate(),
			"fertility": z.fertility,
			"algae_density": z.algae_density,
		})
	var result: Dictionary
	result = {
		"climate_model_version": CLIMATE_MODEL_VERSION,
		"rotation_angle": rotation_angle,
		"light_norm_divisor": light_norm_divisor,
		"dark_side_scatter": dark_side_scatter,
		"reference_mean_insolation": reference_mean_insolation,
		"climate_calibration_offset_c": climate_calibration_offset_c,
		"zones": zones_data,
	}
	return result


func load_state(data: Dictionary) -> bool:
	if int(data.get("climate_model_version", -1)) != CLIMATE_MODEL_VERSION:
		return false
	rotation_angle = float(data["rotation_angle"])
	light_norm_divisor = float(data["light_norm_divisor"])
	dark_side_scatter = float(data["dark_side_scatter"])
	reference_mean_insolation = float(data["reference_mean_insolation"])
	climate_calibration_offset_c = float(data["climate_calibration_offset_c"])
	var zones_data: Array = data["zones"]
	if zones_data.size() != TOTAL_ZONES:
		return false
	for zd in zones_data:
		var zd_dict: Dictionary = zd
		var zone: PlanetZone = get_zone(int(zd_dict["zone_id"]))
		if zone == null:
			return false
		zone.terrain_type = str(zd_dict["terrain_type"])
		zone.building_ids = (zd_dict["building_ids"] as Array).duplicate()
		zone.temperature = float(zd_dict["temperature"])
		zone.air_temperature = float(zd_dict["air_temperature"])
		zone.radiation = float(zd_dict["radiation"])
		zone.light_intensity = float(zd_dict["light_intensity"])
		zone.nitrogen_gas_fraction = float(zd_dict["nitrogen_gas_fraction"])
		zone.oxygen_gas_fraction = float(zd_dict["oxygen_gas_fraction"])
		zone.resource_deposits = (zd_dict["resource_deposits"] as Dictionary).duplicate()
		zone.fertility = float(zd_dict["fertility"])
		zone.algae_density = float(zd_dict["algae_density"])
	return true
