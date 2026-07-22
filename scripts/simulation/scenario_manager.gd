class_name ScenarioManager
extends RefCounted
## 难度快照与轨道阶段的唯一所有者。

signal phase_changed(new_phase: String, transition_day: float)

const STABLE_EPHEMERIS := "STABLE_EPHEMERIS"
const CHAOTIC_NBODY := "CHAOTIC_NBODY"
const TRANSITION_STATE_VERSION := 1
const ThreeBodyScript = preload("res://scripts/simulation/three_body.gd")
const StableEphemerisScript = preload("res://scripts/simulation/stable_ephemeris_provider.gd")

var difficulty_id: String = ""
var difficulty_display_name: String = ""
var difficulty_config_version: int = 0
var stable_years: float = 0.0
var days_per_year: float = 365.0
var chaos_start_day: float = 0.0
var simulation_phase: String = CHAOTIC_NBODY
var scenario_seed: int = 0
var chaos_started: bool = true
var actual_transition_day: float = 0.0
var transition_event_triggered: bool = true
var ephemeris
var environment


func create_scenario(p_snapshot: Dictionary, p_seed: int, p_environment) -> bool:
	if not _validate_snapshot(p_snapshot) or p_environment == null:
		return false
	environment = p_environment
	difficulty_id = p_snapshot["difficulty_id"]
	difficulty_display_name = p_snapshot.get("difficulty_display_name", difficulty_id)
	difficulty_config_version = int(p_snapshot["difficulty_config_version"])
	stable_years = float(p_snapshot["stable_years"])
	days_per_year = float(p_snapshot["days_per_year"])
	chaos_start_day = float(p_snapshot["chaos_start_day"])
	scenario_seed = p_seed
	environment.initialize_with_seed(scenario_seed)
	if chaos_start_day <= 0.0:
		simulation_phase = CHAOTIC_NBODY
		chaos_started = true
		actual_transition_day = 0.0
		transition_event_triggered = true
		return true

	ephemeris = StableEphemerisScript.new()
	ephemeris.create(scenario_seed, chaos_start_day)
	if not ephemeris.validate_stable_window().is_empty():
		return false
	simulation_phase = STABLE_EPHEMERIS
	chaos_started = false
	actual_transition_day = -1.0
	transition_event_triggered = false
	_apply_snapshot(ephemeris.snapshot_at(0.0), false)
	return true


func update(p_game_day: float, p_dt: float) -> void:
	if environment == null or p_dt <= 0.0:
		return
	if simulation_phase == CHAOTIC_NBODY:
		environment.update(p_dt)
		return

	var end_day := p_game_day + p_dt
	var ephemeris_end := minf(end_day, chaos_start_day)
	_apply_snapshot(ephemeris.snapshot_at(ephemeris_end), true)
	if end_day + 1e-9 < chaos_start_day:
		return

	simulation_phase = CHAOTIC_NBODY
	chaos_started = true
	actual_transition_day = chaos_start_day
	if not transition_event_triggered:
		transition_event_triggered = true
		phase_changed.emit(simulation_phase, actual_transition_day)
	var remaining_dt := end_day - chaos_start_day
	if remaining_dt > 1e-9:
		environment.update(remaining_dt)


func get_rule_state(p_game_day: float) -> Dictionary:
	return {
		"difficulty_id": difficulty_id,
		"difficulty_display_name": difficulty_display_name,
		"stable_years": stable_years,
		"days_per_year": days_per_year,
		"chaos_start_day": chaos_start_day,
		"simulation_phase": simulation_phase,
		"days_until_chaos": maxf(0.0, chaos_start_day - p_game_day),
		"chaos_started": chaos_started,
	}


func get_state() -> Dictionary:
	return {
		"difficulty_id": difficulty_id,
		"difficulty_display_name": difficulty_display_name,
		"difficulty_config_version": difficulty_config_version,
		"stable_years": stable_years,
		"days_per_year": days_per_year,
		"chaos_start_day": chaos_start_day,
		"simulation_phase": simulation_phase,
		"scenario_seed": str(scenario_seed),
		"ephemeris_state": ephemeris.get_state() if ephemeris != null else {},
		"transition_state_version": TRANSITION_STATE_VERSION,
		"chaos_started": chaos_started,
		"actual_transition_day": actual_transition_day,
		"transition_event_triggered": transition_event_triggered,
	}


func load_state(p_state: Dictionary, p_environment, p_game_day: float) -> bool:
	if not validate_state(p_state) or p_environment == null:
		return false
	environment = p_environment
	difficulty_id = p_state["difficulty_id"]
	difficulty_display_name = p_state.get("difficulty_display_name", difficulty_id)
	difficulty_config_version = int(p_state["difficulty_config_version"])
	stable_years = float(p_state["stable_years"])
	days_per_year = float(p_state["days_per_year"])
	chaos_start_day = float(p_state["chaos_start_day"])
	simulation_phase = p_state["simulation_phase"]
	scenario_seed = int(str(p_state["scenario_seed"]))
	chaos_started = p_state.get("chaos_started", simulation_phase == CHAOTIC_NBODY)
	actual_transition_day = float(p_state.get("actual_transition_day", -1.0))
	transition_event_triggered = p_state.get("transition_event_triggered", chaos_started)
	var ephemeris_state: Dictionary = p_state.get("ephemeris_state", {})
	if not ephemeris_state.is_empty():
		ephemeris = StableEphemerisScript.new()
		if not ephemeris.load_state(ephemeris_state):
			return false
	if simulation_phase == STABLE_EPHEMERIS:
		if ephemeris == null:
			return false
		_apply_snapshot(ephemeris.snapshot_at(p_game_day), false)
	return true


func validate_state(p_state: Dictionary) -> bool:
	if not _validate_snapshot(p_state):
		return false
	if p_state.get("simulation_phase", "") not in [STABLE_EPHEMERIS, CHAOTIC_NBODY]:
		return false
	if not p_state.has("scenario_seed"):
		return false
	if p_state.get("simulation_phase") == STABLE_EPHEMERIS:
		var provider := StableEphemerisScript.new()
		if not provider.validate_state(p_state.get("ephemeris_state", {})):
			return false
	return true


func _validate_snapshot(p_snapshot: Dictionary) -> bool:
	for key in ["difficulty_id", "difficulty_config_version", "stable_years", "days_per_year", "chaos_start_day"]:
		if not p_snapshot.has(key):
			return false
	var years := float(p_snapshot["stable_years"])
	var year_days := float(p_snapshot["days_per_year"])
	var start_day := float(p_snapshot["chaos_start_day"])
	return (
		not String(p_snapshot["difficulty_id"]).is_empty()
		and is_finite(years) and years >= 0.0
		and is_finite(year_days) and year_days > 0.0
		and is_finite(start_day) and start_day >= 0.0
		and is_equal_approx(start_day, years * year_days)
	)


func _apply_snapshot(p_snapshot: Array, p_record_trail: bool) -> void:
	if p_snapshot.size() != 4:
		return
	if environment.stars.size() != p_snapshot.size():
		environment.stars.clear()
		for body in p_snapshot:
			environment.stars.append(ThreeBodyScript.StarData.new(
				body["mass"], body["position"], body["velocity"], body["color"], body["radius"], body["is_planet"]
			))
		return
	for index in p_snapshot.size():
		var star = environment.stars[index]
		var body: Dictionary = p_snapshot[index]
		if p_record_trail:
			star.trail.append(star.position)
			if star.trail.size() > environment.TRAIL_LENGTH:
				star.trail.pop_front()
		star.mass = body["mass"]
		star.position = body["position"]
		star.velocity = body["velocity"]
		star.color = body["color"]
		star.radius = body["radius"]
		star.is_planet = body["is_planet"]
