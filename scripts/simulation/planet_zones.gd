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
	var radiation: float
	var light_intensity: float
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
		radiation = 0.0
		light_intensity = 0.0
		resource_deposits = p_resource_deposits
		fertility = p_fertility
		algae_density = p_algae_density
		building_ids = []
		area_weight = p_area_weight

	func get_work_efficiency() -> float:
		return _calc_work_efficiency(temperature)

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
var thermal_inertia: float
var diffusion_rate: float
var dark_side_scatter: float
var light_to_temp_scale: float = 500.0
var base_temperature: float = -273.15
var light_norm_divisor: float = 1.0
var _neighbor_cache: Dictionary = {}


func _init(env_config: Dictionary = {}) -> void:
	rotation_speed = env_config.get("rotation_speed", 15.0)
	thermal_inertia = env_config.get("thermal_inertia", 0.08)
	diffusion_rate = env_config.get("diffusion_rate", 0.15)
	dark_side_scatter = env_config.get("dark_side_scatter", 0.05)
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


func _apply_diffusion(game_days_elapsed: float) -> void:
	if diffusion_rate <= 0.0 or game_days_elapsed <= 0.0:
		return

	var neighbor_avg: Array = []
	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		var nids: Array = _neighbor_cache.get(z.zone_id, [])
		if nids.size() > 0:
			var total_t: float = 0.0
			for nid in nids:
				var nid_int: int = nid
				var nz: PlanetZone = zones[nid_int] as PlanetZone
				total_t += nz.temperature
			neighbor_avg.append(total_t / nids.size())
		else:
			neighbor_avg.append(z.temperature)

	var factor: float = min(1.0, diffusion_rate * abs(game_days_elapsed))
	for i in zones.size():
		var zone: PlanetZone = zones[i] as PlanetZone
		zone.temperature += (neighbor_avg[i] - zone.temperature) * factor


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

	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		var normal: Vector3 = _get_zone_normal(z)
		var target_light: float = 0.0
		var target_radiation: float = 0.0

		for star in active_stars:
			var s: Dictionary = star as Dictionary
			var star_dir: Vector3 = s["direction"]
			var cos_angle: float = normal.dot(star_dir)
			var dist: float = s["distance"]
			var mass: float = s["mass"]

			var scatter_factor: float
			scatter_factor = maxf(dark_side_scatter, cos_angle)

			var intensity: float = mass * 10.0 / (dist * dist + 100.0) * scatter_factor
			target_light += intensity

			var safe_dist: float = max(5.0, dist)
			var rad: float = mass * 200.0 / pow(safe_dist, 2.5) * scatter_factor
			target_radiation += rad

		var terrain_mod: float = TERRAIN_THERMAL_MODIFIER.get(z.terrain_type, 0.0)
		z.temperature = base_temperature + target_light * light_to_temp_scale + terrain_mod
		z.radiation = target_radiation
		z.light_intensity = min(1.0, target_light / light_norm_divisor)

	for _i in 10:
		_apply_diffusion(1.0)


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
	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		var normal: Vector3 = _get_zone_normal(z)
		var target_light: float = 0.0
		var target_radiation: float = 0.0

		for star in active_stars:
			var s: Dictionary = star as Dictionary
			var star_dir: Vector3 = s["direction"]
			var cos_angle: float = normal.dot(star_dir)
			var dist: float = s["distance"]
			var mass: float = s["mass"]

			var scatter_factor: float
			scatter_factor = maxf(dark_side_scatter, cos_angle)

			var intensity: float = mass * 10.0 / (dist * dist + 100.0) * scatter_factor
			target_light += intensity

			var safe_dist: float = max(5.0, dist)
			var rad: float = mass * 200.0 / pow(safe_dist, 2.5) * scatter_factor
			target_radiation += rad

		var terrain_mod: float = TERRAIN_THERMAL_MODIFIER.get(z.terrain_type, 0.0)
		var target_temp: float = base_temperature + target_light * light_to_temp_scale + terrain_mod

		var inertia_factor: float = min(1.0, thermal_inertia * abs(game_days_elapsed))
		z.temperature += (target_temp - z.temperature) * inertia_factor
		z.radiation = target_radiation
		z.light_intensity = min(1.0, target_light / light_norm_divisor)

	_apply_diffusion(game_days_elapsed)


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
	var avg_rad: float = 0.0
	var avg_light: float = 0.0

	for zone in zones:
		var z: PlanetZone = zone as PlanetZone
		var w: float = z.area_weight
		avg_temp += z.temperature * w
		avg_rad += z.radiation * w
		avg_light += z.light_intensity * w
		total_weight += w

	if total_weight > 0.0:
		avg_temp /= total_weight
		avg_rad /= total_weight
		avg_light /= total_weight

	var result: Dictionary
	result = {
		"temperature": avg_temp,
		"radiation": avg_rad,
		"light_intensity": avg_light,
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
		"radiation": zone.radiation,
		"light_intensity": zone.light_intensity,
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
			"rad": z.radiation,
			"light": z.light_intensity,
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
			"radiation": z.radiation,
			"light_intensity": z.light_intensity,
			"resource_deposits": z.resource_deposits.duplicate(),
			"fertility": z.fertility,
			"algae_density": z.algae_density,
		})
	var result: Dictionary
	result = {
		"rotation_angle": rotation_angle,
		"light_to_temp_scale": light_to_temp_scale,
		"light_norm_divisor": light_norm_divisor,
		"dark_side_scatter": dark_side_scatter,
		"zones": zones_data,
	}
	return result


func load_state(data: Dictionary) -> void:
	rotation_angle = data.get("rotation_angle", 0.0)
	light_to_temp_scale = data.get("light_to_temp_scale", light_to_temp_scale)
	light_norm_divisor = data.get("light_norm_divisor", light_norm_divisor)
	dark_side_scatter = data.get("dark_side_scatter", dark_side_scatter)
	var zones_data: Array = data.get("zones", [])
	for zd in zones_data:
		var zd_dict: Dictionary = zd
		var zone: PlanetZone = get_zone(zd_dict.get("zone_id", -1))
		if zone != null:
			zone.terrain_type = zd_dict.get("terrain_type", zone.terrain_type)
			zone.building_ids = zd_dict.get("building_ids", [])
			zone.temperature = zd_dict.get("temperature", -273.15)
			zone.radiation = zd_dict.get("radiation", 0.0)
			zone.light_intensity = zd_dict.get("light_intensity", 0.0)
			if "resource_deposits" in zd_dict:
				zone.resource_deposits = zd_dict["resource_deposits"]
			if "fertility" in zd_dict:
				zone.fertility = zd_dict["fertility"]
			if "algae_density" in zd_dict:
				zone.algae_density = zd_dict["algae_density"]
