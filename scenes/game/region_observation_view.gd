class_name RegionObservationView
extends Control
## Local surface view driven by the selected zone and the live N-body snapshot.

const CelestialRendererScript = preload("res://scripts/rendering/celestial_view_renderer.gd")
const SKY_DISTANCE := 80.0
const TERRAIN_COLORS: Dictionary = {
	"平原": Color(0.16, 0.24, 0.15),
	"高原": Color(0.25, 0.22, 0.16),
	"山地": Color(0.17, 0.18, 0.20),
	"峡谷": Color(0.30, 0.18, 0.13),
	"盆地": Color(0.13, 0.24, 0.21),
	"丘陵": Color(0.21, 0.27, 0.15),
}

var observed_zone_id: int = 0
var local_up := Vector3.UP
var local_east := Vector3.RIGHT
var local_north := Vector3.FORWARD
var _body_observations: Dictionary = {}
var _source_snapshot: Array = []
var _zone_light: float = 0.0
var _terrain_type: String = "平原"
var _last_building_signature: String = ""
var _refresh_elapsed: float = 0.0


func _ready() -> void:
	clip_contents = true
	resized.connect(_layout_building_visuals)
	_setup_environment()
	%CelestialRenderer.configure({
		"position_scale": SKY_DISTANCE,
		"fixed_radius": 1.8,
		"include_planet": false,
		"planet_grid": false,
		"stellar_lights": false,
	})
	%CelestialRenderer.set_coordinate_frame(CelestialRendererScript.FRAME_LOCAL_HORIZON)
	%CelestialRenderer.set_horizon_mask(true)
	if GameState.game_started:
		set_observed_zone(GameState.observed_zone_id)
		refresh_from_state(GameState.get_state())


func _process(p_delta: float) -> void:
	if not GameState.game_started:
		return
	_refresh_elapsed += p_delta
	if _refresh_elapsed >= 0.1:
		_refresh_elapsed = 0.0
		refresh_from_state(GameState.get_state())


func set_observed_zone(p_zone_id: int) -> bool:
	if p_zone_id < 0 or p_zone_id >= 72:
		return false
	if GameState.planet_zones != null and GameState.planet_zones.get_zone(p_zone_id) == null:
		return false
	observed_zone_id = p_zone_id
	_update_local_frame()
	_last_building_signature = ""
	return true


func refresh_from_state(p_state: Dictionary) -> void:
	if GameState.planet_zones == null:
		return
	var zone = GameState.planet_zones.get_zone(observed_zone_id)
	if zone == null:
		return
	_update_local_frame()
	_zone_light = clampf(zone.light_intensity, 0.0, 1.0)
	_terrain_type = zone.terrain_type

	var stars: Array = p_state.get("environment", {}).get("stars", [])
	var planet_position := _find_planet_position(stars)
	var local_bodies: Array = []
	_body_observations.clear()
	_source_snapshot.clear()
	for source_index in range(stars.size()):
		var star: Dictionary = stars[source_index]
		if star.get("is_planet", false):
			continue
		var relative: Vector3 = CelestialRendererScript.to_vector3(star.get("position", {})) - planet_position
		var distance: float = relative.length()
		if distance <= 0.000001:
			continue
		var world_direction: Vector3 = relative / distance
		var local_direction := Vector3(
			world_direction.dot(local_east),
			world_direction.dot(local_up),
			-world_direction.dot(local_north)
		)
		var altitude := asin(clampf(local_direction.y, -1.0, 1.0))
		var azimuth := fposmod(atan2(
			world_direction.dot(local_east), world_direction.dot(local_north)
		), TAU)
		var angular_radius := atan(float(star.get("radius", 1.0)) / distance)
		var render_radius := clampf(tan(angular_radius) * SKY_DISTANCE, 0.75, 7.5)
		var body := star.duplicate(true)
		body["source_index"] = source_index
		body["position"] = local_direction
		body["render_radius"] = render_radius
		local_bodies.append(body)
		_source_snapshot.append({
			"source_index": source_index,
			"position": star.get("position", {}),
			"color": star.get("color", Color.WHITE),
			"collision_state": p_state.get("game_over", false),
		})
		_body_observations[source_index] = {
			"altitude": altitude,
			"azimuth": azimuth,
			"altitude_degrees": rad_to_deg(altitude),
			"azimuth_degrees": rad_to_deg(azimuth),
			"above_horizon": altitude > 0.0,
			"distance": distance,
			"angular_radius": angular_radius,
		}

	if %CelestialRenderer.get_body_nodes().size() != local_bodies.size():
		%CelestialRenderer.rebuild_bodies(local_bodies)
	else:
		%CelestialRenderer.update_bodies(local_bodies)
	_sync_building_visuals()
	queue_redraw()


func get_body_altitude_azimuth(p_source_index: int) -> Dictionary:
	return (_body_observations.get(p_source_index, {}) as Dictionary).duplicate()


func get_render_source_snapshot() -> Array:
	return _source_snapshot.duplicate(true)


func get_building_visual_ids() -> Array[int]:
	var result: Array[int] = []
	for child in %BuildingVisualRoot.get_children():
		result.append(int(child.get_meta("building_id", -1)))
	return result


func _update_local_frame() -> void:
	if GameState.planet_zones == null:
		return
	local_up = GameState.planet_zones.get_zone_normal(observed_zone_id).normalized()
	if local_up.is_zero_approx():
		local_up = Vector3.UP
	var zone = GameState.planet_zones.get_zone(observed_zone_id)
	var longitude := deg_to_rad(zone.lon_center + GameState.planet_zones.rotation_angle)
	local_east = Vector3(-sin(longitude), 0.0, cos(longitude)).normalized()
	local_north = local_east.cross(local_up).normalized()


func _find_planet_position(p_stars: Array) -> Vector3:
	for star_value in p_stars:
		var star: Dictionary = star_value
		if star.get("is_planet", false):
			return CelestialRendererScript.to_vector3(star.get("position", {}))
	return Vector3.ZERO


func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.background_energy_multiplier = 0.0
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.03, 0.04, 0.08)
	environment.ambient_light_energy = 0.15
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 1.1
	environment.glow_strength = 1.25
	%WorldEnvironment.environment = environment
	%SubViewport.msaa_3d = Viewport.MSAA_4X


func _sync_building_visuals() -> void:
	if GameState.entities == null:
		return
	var buildings: Array = GameState.entities.get_buildings_in_zone(observed_zone_id)
	var signature_parts: Array[String] = []
	for building in buildings:
		signature_parts.append("%d:%s:%s:%s" % [
			building.id, building.under_construction, building.destroyed, building.active,
		])
	var signature := ",".join(signature_parts)
	if signature == _last_building_signature:
		return
	_last_building_signature = signature

	var existing: Dictionary = {}
	for child in %BuildingVisualRoot.get_children():
		existing[int(child.get_meta("building_id", -1))] = child
	for building in buildings:
		var visual: PanelContainer = existing.get(building.id)
		if visual == null:
			visual = _create_building_visual(building)
			%BuildingVisualRoot.add_child(visual)
		else:
			existing.erase(building.id)
		_update_building_visual(visual, building)
	for stale_visual in existing.values():
		stale_visual.queue_free()
	_layout_building_visuals()


func _create_building_visual(p_building) -> PanelContainer:
	var visual := PanelContainer.new()
	visual.set_meta("building_id", p_building.id)
	visual.custom_minimum_size = Vector2(92.0, 72.0)
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.name = "Label"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	visual.add_child(label)
	return visual


func _update_building_visual(p_visual: PanelContainer, p_building) -> void:
	var label: Label = p_visual.get_node("Label")
	label.text = "%s\n%s" % [
		p_building.building_name,
		"施工中" if p_building.under_construction else ("已损毁" if p_building.destroyed else "运行中"),
	]
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.35, 0.18, 0.08, 0.92) if p_building.under_construction else (
		Color(0.42, 0.06, 0.08, 0.92) if p_building.destroyed else Color(0.08, 0.20, 0.26, 0.92)
	)
	style.border_color = Color(0.72, 0.82, 0.9, 0.75)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	p_visual.add_theme_stylebox_override("panel", style)


func _layout_building_visuals() -> void:
	if not is_node_ready():
		return
	var children := %BuildingVisualRoot.get_children()
	if children.is_empty():
		return
	var spacing := minf(112.0, maxf(72.0, (size.x - 80.0) / float(children.size())))
	var start_x := (size.x - spacing * float(children.size() - 1)) * 0.5 - 46.0
	for index in range(children.size()):
		var visual: Control = children[index]
		visual.position = Vector2(start_x + spacing * index, size.y * 0.72)
		visual.size = Vector2(92.0, 72.0)


func _draw() -> void:
	var daylight := clampf(_zone_light, 0.0, 1.0)
	var night_sky := Color(0.004, 0.008, 0.025)
	var day_sky := Color(0.20, 0.43, 0.70)
	var sky_color := night_sky.lerp(day_sky, pow(daylight, 0.55))
	draw_rect(Rect2(Vector2.ZERO, size), sky_color)
	var horizon_y := size.y * 0.62
	var terrain_color: Color = TERRAIN_COLORS.get(_terrain_type, TERRAIN_COLORS["平原"])
	terrain_color = terrain_color.darkened((1.0 - daylight) * 0.55)
	var ridge := PackedVector2Array([
		Vector2(0.0, horizon_y + _ridge_offset(0)),
		Vector2(size.x * 0.16, horizon_y + _ridge_offset(1)),
		Vector2(size.x * 0.34, horizon_y + _ridge_offset(2)),
		Vector2(size.x * 0.55, horizon_y + _ridge_offset(3)),
		Vector2(size.x * 0.76, horizon_y + _ridge_offset(4)),
		Vector2(size.x, horizon_y + _ridge_offset(5)),
		Vector2(size.x, size.y),
		Vector2(0.0, size.y),
	])
	draw_colored_polygon(ridge, terrain_color)
	draw_line(Vector2(0.0, horizon_y), Vector2(size.x, horizon_y), Color(0.72, 0.76, 0.68, 0.45), 2.0)
	var fog_color := sky_color.lerp(Color(0.72, 0.68, 0.56), 0.35)
	draw_rect(Rect2(0.0, horizon_y - 10.0, size.x, 22.0), Color(fog_color, 0.13 + daylight * 0.12))


func _ridge_offset(p_index: int) -> float:
	match _terrain_type:
		"山地":
			return [-5.0, -74.0, -18.0, -98.0, -30.0, -64.0][p_index]
		"高原":
			return [-22.0, -28.0, -18.0, -24.0, -16.0, -20.0][p_index]
		"峡谷":
			return [-16.0, 8.0, -20.0, 16.0, -12.0, 2.0][p_index]
		"盆地":
			return [-18.0, -4.0, 10.0, 14.0, -2.0, -20.0][p_index]
		"丘陵":
			return [-8.0, -28.0, -5.0, -34.0, -8.0, -24.0][p_index]
		_:
			return [-4.0, -10.0, -5.0, -9.0, -4.0, -7.0][p_index]
