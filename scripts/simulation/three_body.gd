class_name ThreeBodySimulation
extends RefCounted
## 三体运动模拟器 — RK4 积分 + 轨迹记录 + 环境参数输出

const G: float = 1.0
const TRAIL_LENGTH: int = 200

var stars: Array = []
var time_scale: float = 1.0


class StarData:
	var mass: float
	var position: Vector3
	var velocity: Vector3
	var color: Color
	var radius: float
	var is_planet: bool
	var trail: Array = []

	func _init(p_mass: float, p_position: Vector3, p_velocity: Vector3,
			p_color: Color, p_radius: float, p_is_planet: bool = false) -> void:
		mass = p_mass
		position = p_position
		velocity = p_velocity
		color = p_color
		radius = p_radius
		is_planet = p_is_planet
		trail = []


func _init() -> void:
	_initialize_stars()


func _initialize_stars() -> void:
	randomize()

	var m1: float = randf_range(900.0, 1100.0)
	var m2: float = randf_range(700.0, 900.0)

	var binary_dist: float = randf_range(180.0, 220.0)
	var v_rel: float = sqrt(G * (m1 + m2) / binary_dist)

	var r1: float = binary_dist * (m2 / (m1 + m2))
	var r2: float = binary_dist * (m1 / (m1 + m2))
	var v1: float = v_rel * (m2 / (m1 + m2))
	var v2: float = v_rel * (m1 / (m1 + m2))

	var angle: float = randf_range(0.0, 2.0 * PI)

	var star1: StarData = StarData.new(
		m1,
		Vector3(r1 * cos(angle), 0.0, r1 * sin(angle)),
		Vector3(-v1 * sin(angle), 0.0, v1 * cos(angle)),
		Color(1.0, randf_range(0.706, 0.863), 0.392),
		randf_range(25.0, 35.0),
		false
	)

	var star2: StarData = StarData.new(
		m2,
		Vector3(-r2 * cos(angle), 0.0, -r2 * sin(angle)),
		Vector3(v2 * sin(angle), 0.0, -v2 * cos(angle)),
		Color(0.392, randf_range(0.706, 0.863), 1.0),
		randf_range(20.0, 30.0),
		false
	)

	var m3: float = randf_range(500.0, 700.0)
	var outer_dist: float = randf_range(650.0, 800.0)
	var v_outer: float = sqrt(G * (m1 + m2 + m3) / outer_dist)
	var outer_angle: float = randf_range(0.0, 2.0 * PI)

	var star3: StarData = StarData.new(
		m3,
		Vector3(outer_dist * cos(outer_angle), randf_range(-30.0, 30.0), outer_dist * sin(outer_angle)),
		Vector3(-v_outer * sin(outer_angle), randf_range(-0.05, 0.05), v_outer * cos(outer_angle)),
		Color(1.0, randf_range(0.314, 0.471), randf_range(0.314, 0.471)),
		randf_range(18.0, 25.0),
		false
	)

	var planet_dist: float = outer_dist * randf_range(0.4, 0.5)
	var p_angle: float = randf_range(0.0, 2.0 * PI)
	var v_planet: float = sqrt(G * (m1 + m2) / planet_dist) * randf_range(0.9, 1.1)

	var planet: StarData = StarData.new(
		1.0,
		Vector3(planet_dist * cos(p_angle), 0.0, planet_dist * sin(p_angle)),
		Vector3(-v_planet * sin(p_angle), 0.0, v_planet * cos(p_angle)),
		Color(0.392, 0.588, 1.0),
		3.0,
		true
	)

	stars = [star1, star2, star3, planet]


func compute_forces_for_state(positions: Array) -> Array:
	var forces: Array = []
	for i in stars.size():
		forces.append(Vector3.ZERO)

	for i in stars.size():
		for j in stars.size():
			if i == j:
				continue
			var r: Vector3 = positions[j] - positions[i]
			var dist: float = r.length()
			if dist > 1e-6:
				var star_i: StarData = stars[i]
				var star_j: StarData = stars[j]
				var force: Vector3 = G * star_i.mass * star_j.mass * r / (dist * dist * dist)
				forces[i] = forces[i] + force
	return forces


func update(dt: float) -> void:
	dt = dt * time_scale

	if dt <= 0.0:
		return

	var positions: Array = []
	var velocities: Array = []
	var masses: Array = []
	for star in stars:
		var s: StarData = star as StarData
		positions.append(s.position)
		velocities.append(s.velocity)
		masses.append(s.mass)

	# RK4 Step 1
	var forces1: Array = compute_forces_for_state(positions)
	var a1: Array = []
	for i in forces1.size():
		var m: float = masses[i]
		a1.append(forces1[i] / m)

	# RK4 Step 2
	var pos2: Array = []
	var v2_temp: Array = []
	for i in positions.size():
		pos2.append(positions[i] + velocities[i] * (dt / 2.0))
		v2_temp.append(velocities[i] + a1[i] * (dt / 2.0))
	var forces2: Array = compute_forces_for_state(pos2)
	var a2: Array = []
	for i in forces2.size():
		a2.append(forces2[i] / masses[i])

	# RK4 Step 3
	var pos3: Array = []
	var v3_temp: Array = []
	for i in positions.size():
		pos3.append(positions[i] + v2_temp[i] * (dt / 2.0))
		v3_temp.append(velocities[i] + a2[i] * (dt / 2.0))
	var forces3: Array = compute_forces_for_state(pos3)
	var a3: Array = []
	for i in forces3.size():
		a3.append(forces3[i] / masses[i])

	# RK4 Step 4
	var pos4: Array = []
	for i in positions.size():
		pos4.append(positions[i] + v3_temp[i] * dt)
	var forces4: Array = compute_forces_for_state(pos4)
	var a4: Array = []
	for i in forces4.size():
		a4.append(forces4[i] / masses[i])

	# 综合更新 + 微小随机扰动
	for i in stars.size():
		var star: StarData = stars[i] as StarData

		star.trail.append(star.position)
		if star.trail.size() > TRAIL_LENGTH:
			star.trail.pop_front()

		var avg_a: Vector3 = (a1[i] + 2.0 * a2[i] + 2.0 * a3[i] + a4[i]) / 6.0
		var avg_v: Vector3 = (velocities[i] + 2.0 * v2_temp[i] + 2.0 * v3_temp[i] + (velocities[i] + a3[i] * dt)) / 6.0

		var perturbation: Vector3 = Vector3(
			randf_range(-1e-5, 1e-5),
			randf_range(-1e-5, 1e-5),
			randf_range(-1e-5, 1e-5)
		)

		star.velocity += (avg_a + perturbation) * dt
		star.position += avg_v * dt


func has_collision() -> bool:
	for first_index in range(stars.size()):
		var first: StarData = stars[first_index] as StarData
		for second_index in range(first_index + 1, stars.size()):
			var second: StarData = stars[second_index] as StarData
			if first.position.distance_to(second.position) < first.radius + second.radius:
				return true
	return false


func get_environment_params() -> Dictionary:
	var planet: StarData = null
	for star in stars:
		var s: StarData = star as StarData
		if s.is_planet:
			planet = s
			break

	if planet == null:
		var result: Dictionary
		result = {
			"light_intensity": 0.0,
			"heat_level": 0.0,
			"temperature": -273.15,
			"radiation": 0.0,
			"stability": 0.0,
		}
		return result

	var total_intensity: float = 0.0
	var radiation: float = 0.0

	for star in stars:
		var s: StarData = star as StarData
		if s == planet:
			continue
		var dist: float = (s.position - planet.position).length()
		total_intensity += s.mass * 10.0 / (dist * dist + 100.0)

		var safe_dist: float = max(5.0, dist)
		radiation += s.mass * 200.0 / pow(safe_dist, 2.5)

	var stability: float = _compute_stability(planet)
	var temperature: float = -273.15 + (total_intensity * 7000.0)

	var result: Dictionary
	result = {
		"light_intensity": min(1.0, total_intensity / 8.0),
		"heat_level": total_intensity / 6.0,
		"temperature": temperature,
		"radiation": radiation,
		"stability": stability,
	}
	return result


func _compute_stability(planet: StarData) -> float:
	var total_force: Vector3 = Vector3.ZERO
	for star in stars:
		var s: StarData = star as StarData
		if s == planet:
			continue
		var r: Vector3 = s.position - planet.position
		var dist: float = r.length()
		if dist > 1e-6:
			total_force += G * planet.mass * s.mass * r / (dist * dist * dist)

	var accel: float = total_force.length() / planet.mass
	return 1.0 / (1.0 + accel / 0.1)


func get_stars_data() -> Array:
	var result: Array = []
	for star in stars:
		var s: StarData = star as StarData
		result.append({
			"position": s.position,
			"mass": s.mass,
			"is_planet": s.is_planet,
		})
	return result


func get_planet_position() -> Vector3:
	for star in stars:
		var s: StarData = star as StarData
		if s.is_planet:
			return s.position
	return Vector3.ZERO
