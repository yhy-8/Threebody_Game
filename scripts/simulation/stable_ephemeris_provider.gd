class_name StableEphemerisProvider
extends RefCounted
## 可复现的规定星历：主恒星—行星解析二体轨道与两颗远星的连续接近轨迹。

const G := 1.0
const EPHEMERIS_VERSION := 1

var parameters: Dictionary = {}


func create(p_seed: int, p_transition_day: float) -> void:
	var generator := RandomNumberGenerator.new()
	generator.seed = p_seed
	parameters = {
		"version": EPHEMERIS_VERSION,
		"seed": str(p_seed),
		"transition_day": maxf(0.0, p_transition_day),
		"main_mass": generator.randf_range(900.0, 1100.0),
		"main_radius": generator.randf_range(25.0, 35.0),
		"main_color": _color_to_dict(Color(1.0, generator.randf_range(0.72, 0.88), 0.4)),
		"planet_radius_orbit": generator.randf_range(300.0, 350.0),
		"planet_phase": generator.randf_range(0.0, TAU),
		"outer_masses": [generator.randf_range(700.0, 900.0), generator.randf_range(500.0, 700.0)],
		"outer_radii": [generator.randf_range(20.0, 30.0), generator.randf_range(18.0, 25.0)],
		"outer_colors": [
			_color_to_dict(Color(0.4, generator.randf_range(0.72, 0.88), 1.0)),
			_color_to_dict(Color(1.0, generator.randf_range(0.32, 0.48), generator.randf_range(0.32, 0.48))),
		],
		"outer_start_distances": [generator.randf_range(1800.0, 2000.0), generator.randf_range(2250.0, 2500.0)],
		"outer_target_distances": [generator.randf_range(760.0, 820.0), generator.randf_range(1040.0, 1120.0)],
		"outer_phases": [generator.randf_range(0.0, TAU), generator.randf_range(0.0, TAU)],
		"outer_angular_speeds": [generator.randf_range(0.000025, 0.00004), -generator.randf_range(0.000018, 0.000032)],
	}


func load_state(p_state: Dictionary) -> bool:
	if not validate_state(p_state):
		return false
	parameters = p_state.duplicate(true)
	return true


func get_state() -> Dictionary:
	return parameters.duplicate(true)


func validate_state(p_state: Dictionary) -> bool:
	if int(p_state.get("version", 0)) <= 0:
		return false
	for key in ["outer_masses", "outer_radii", "outer_colors", "outer_start_distances", "outer_target_distances", "outer_phases", "outer_angular_speeds"]:
		if not p_state.get(key, null) is Array or p_state[key].size() != 2:
			return false
	return float(p_state.get("main_mass", 0.0)) > 0.0 and float(p_state.get("planet_radius_orbit", 0.0)) > 0.0


func snapshot_at(p_game_day: float) -> Array:
	if parameters.is_empty():
		return []
	var day := clampf(p_game_day, 0.0, float(parameters["transition_day"]))
	var main_mass: float = parameters["main_mass"]
	var planet_distance: float = parameters["planet_radius_orbit"]
	var planet_omega := sqrt(G * main_mass / pow(planet_distance, 3.0))
	var planet_angle: float = parameters["planet_phase"] + planet_omega * day
	var result: Array = [{
		"mass": main_mass,
		"position": Vector3.ZERO,
		"velocity": Vector3.ZERO,
		"color": _dict_to_color(parameters["main_color"]),
		"radius": float(parameters["main_radius"]),
		"is_planet": false,
	}]
	for index in 2:
		result.append(_outer_body_at(index, day))
	result.append({
		"mass": 1.0,
		"position": Vector3(planet_distance * cos(planet_angle), 0.0, planet_distance * sin(planet_angle)),
		"velocity": Vector3(-planet_distance * planet_omega * sin(planet_angle), 0.0, planet_distance * planet_omega * cos(planet_angle)),
		"color": Color(0.392, 0.588, 1.0),
		"radius": 3.0,
		"is_planet": true,
	})
	return result


func validate_stable_window() -> PackedStringArray:
	var errors := PackedStringArray()
	if not validate_state(parameters):
		errors.append("规定星历参数无效")
		return errors
	var transition_day: float = parameters["transition_day"]
	for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var snapshot := snapshot_at(transition_day * fraction)
		for first in snapshot.size():
			for second in range(first + 1, snapshot.size()):
				var minimum_distance: float = snapshot[first]["radius"] + snapshot[second]["radius"]
				if snapshot[first]["position"].distance_to(snapshot[second]["position"]) <= minimum_distance:
					errors.append("稳定星历在 %.0f%% 时发生天体重叠" % (fraction * 100.0))
	return errors


func _outer_body_at(p_index: int, p_day: float) -> Dictionary:
	var transition_day: float = parameters["transition_day"]
	var progress := clampf(p_day / transition_day, 0.0, 1.0) if transition_day > 0.0 else 1.0
	var start_distance: float = parameters["outer_start_distances"][p_index]
	var target_distance: float = parameters["outer_target_distances"][p_index]
	var radial_speed := (target_distance - start_distance) / transition_day if transition_day > 0.0 else 0.0
	var distance := lerpf(start_distance, target_distance, progress)
	var angular_speed: float = parameters["outer_angular_speeds"][p_index]
	var angle: float = parameters["outer_phases"][p_index] + angular_speed * p_day
	return {
		"mass": float(parameters["outer_masses"][p_index]),
		"position": Vector3(distance * cos(angle), 0.0, distance * sin(angle)),
		"velocity": Vector3(
			radial_speed * cos(angle) - distance * angular_speed * sin(angle),
			0.0,
			radial_speed * sin(angle) + distance * angular_speed * cos(angle)
		),
		"color": _dict_to_color(parameters["outer_colors"][p_index]),
		"radius": float(parameters["outer_radii"][p_index]),
		"is_planet": false,
	}


func _color_to_dict(p_color: Color) -> Dictionary:
	return {"r": p_color.r, "g": p_color.g, "b": p_color.b, "a": p_color.a}


func _dict_to_color(p_value: Dictionary) -> Color:
	return Color(p_value.get("r", 1.0), p_value.get("g", 1.0), p_value.get("b", 1.0), p_value.get("a", 1.0))
