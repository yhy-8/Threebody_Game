extends Control
## 3D starmap with trails, planet grid, star field, and dual camera modes.

const STAR_SHADER_CODE := """
shader_type spatial;
render_mode unshaded;
uniform vec4 base_color : source_color = vec4(1.0);
void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float gradient = 0.25 + 0.75 * pow(facing, 0.45);
	ALBEDO = base_color.rgb * gradient;
	EMISSION = base_color.rgb * (1.2 + 2.8 * facing);
	ALPHA = base_color.a;
}
"""

var _cam_angle_h: float = 0.0
var _cam_angle_v: float = 25.0
var _cam_distance: float = 500.0
var _free_target := Vector3.ZERO
var _dragging: bool = false
var _last_mouse_pos := Vector2.ZERO
var _locked_on_planet: bool = false
var _saved_free_distance: float = 500.0
var _star_meshes: Array[MeshInstance3D] = []
var _trail_meshes: Array[MeshInstance3D] = []
var _prediction_meshes: Array[MeshInstance3D] = []
var _planet_grid: MeshInstance3D
var _render_elapsed: float = 0.0


func _ready() -> void:
	%BackButton.pressed.connect(_on_back_pressed)
	%PauseButton.pressed.connect(_on_pause_pressed)
	%LockButton.pressed.connect(_on_lock_toggled)
	%HelpButton.pressed.connect(_on_help_toggled)
	%CloseHelpButton.pressed.connect(_on_help_toggled)
	%RestartButton.pressed.connect(_on_restart_pressed)
	_setup_star_field()
	if GameState.game_started:
		_update_star_meshes()
		_refresh_info()
	_update_pause_button()
	%GameOverOverlay.visible = GameState.game_over


func _process(p_delta: float) -> void:
	%GameOverOverlay.visible = GameState.game_over
	if GameState.game_over:
		return
	_handle_continuous_input(p_delta)
	_update_camera(p_delta)
	if not GameState.game_started:
		%InfoLabel.text = "尚未开始游戏，无法读取星图模拟数据"
		return
	_render_elapsed += p_delta
	if _render_elapsed >= 0.05:
		_render_elapsed = 0.0
		_update_star_positions()
		_update_trails()
		_refresh_info()


func _setup_star_field() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "StarField"
	particles.amount = 450
	particles.lifetime = 60.0
	particles.preprocess = 60.0
	particles.randomness = 1.0
	particles.visibility_aabb = AABB(Vector3(-2200, -2200, -2200), Vector3(4400, 4400, 4400))
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(1800, 1800, 1800)
	process_material.gravity = Vector3.ZERO
	process_material.initial_velocity_min = 0.0
	process_material.initial_velocity_max = 0.0
	process_material.scale_min = 0.35
	process_material.scale_max = 1.4
	particles.process_material = process_material
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 1.4)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(0.8, 0.88, 1.0, 0.9)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = material
	particles.draw_pass_1 = quad
	%StarMap3D.add_child(particles)


func _update_star_meshes() -> void:
	for mesh in _star_meshes:
		mesh.queue_free()
	for mesh in _trail_meshes:
		mesh.queue_free()
	for mesh in _prediction_meshes:
		mesh.queue_free()
	_star_meshes.clear()
	_trail_meshes.clear()
	_prediction_meshes.clear()
	_planet_grid = null

	var stars_data: Array = GameState.get_state().get("environment", {}).get("stars", [])
	for index in range(stars_data.size()):
		var star: Dictionary = stars_data[index]
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Planet" if star.get("is_planet", false) else "Star%d" % index
		var sphere := SphereMesh.new()
		var radius: float = star.get("radius", 20.0) * 0.5
		sphere.radius = radius
		sphere.height = radius * 2.0
		sphere.radial_segments = 48
		sphere.rings = 24
		mesh_instance.mesh = sphere

		var color: Color = star.get("color", Color.WHITE)
		if star.get("is_planet", false):
			var planet_material := StandardMaterial3D.new()
			planet_material.albedo_color = color
			planet_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			planet_material.emission_enabled = true
			planet_material.emission = color
			planet_material.emission_energy_multiplier = 1.4
			mesh_instance.material_override = planet_material
		else:
			var star_shader := Shader.new()
			star_shader.code = STAR_SHADER_CODE
			var star_material := ShaderMaterial.new()
			star_material.shader = star_shader
			star_material.set_shader_parameter("base_color", color)
			mesh_instance.material_override = star_material
		mesh_instance.set_meta("is_planet", star.get("is_planet", false))
		mesh_instance.set_meta("star_index", index)
		mesh_instance.position = _dict_to_vector(star.get("position", {}))
		%CelestialBodies.add_child(mesh_instance)
		_star_meshes.append(mesh_instance)

		var trail_mesh := MeshInstance3D.new()
		trail_mesh.name = "Trail%d" % index
		%Trails.add_child(trail_mesh)
		_trail_meshes.append(trail_mesh)
		var prediction_mesh := MeshInstance3D.new()
		prediction_mesh.name = "Prediction%d" % index
		%Trails.add_child(prediction_mesh)
		_prediction_meshes.append(prediction_mesh)

		if star.get("is_planet", false):
			_planet_grid = _create_planet_grid(radius * 1.015)
			mesh_instance.add_child(_planet_grid)

	_update_trails()


func _create_planet_grid(radius: float) -> MeshInstance3D:
	var grid := MeshInstance3D.new()
	grid.name = "PlanetGrid"
	var immediate := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.3, 0.65, 1.0, 0.72)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	for latitude_index in range(1, 6):
		var latitude := deg_to_rad(-90.0 + latitude_index * 30.0)
		immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
		for segment in range(49):
			var longitude := TAU * float(segment) / 48.0
			immediate.surface_add_vertex(Vector3(
				radius * cos(latitude) * cos(longitude),
				radius * sin(latitude),
				radius * cos(latitude) * sin(longitude)
			))
		immediate.surface_end()
	for longitude_index in range(12):
		var longitude := TAU * float(longitude_index) / 12.0
		immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
		for segment in range(25):
			var latitude := -PI * 0.5 + PI * float(segment) / 24.0
			immediate.surface_add_vertex(Vector3(
				radius * cos(latitude) * cos(longitude),
				radius * sin(latitude),
				radius * cos(latitude) * sin(longitude)
			))
		immediate.surface_end()
	grid.mesh = immediate
	return grid


func _update_star_positions() -> void:
	if not GameState.game_started:
		return
	var stars_data: Array = GameState.get_state().get("environment", {}).get("stars", [])
	for index in range(min(_star_meshes.size(), stars_data.size())):
		_star_meshes[index].position = _dict_to_vector(stars_data[index].get("position", {}))
	if _planet_grid != null:
		_planet_grid.rotation_degrees.y = GameState.planet_zones.rotation_angle


func _update_trails() -> void:
	if not GameState.game_started:
		return
	var stars_data: Array = GameState.get_state().get("environment", {}).get("stars", [])
	for index in range(min(stars_data.size(), _trail_meshes.size())):
		var star: Dictionary = stars_data[index]
		var color: Color = star.get("color", Color.WHITE)
		_trail_meshes[index].mesh = _line_mesh(star.get("trail", []), color, false)
		_prediction_meshes[index].mesh = null

		if GameState.tech_tree.is_unlocked("computer"):
			var prediction_steps := 80 if GameState.tech_tree.is_unlocked("chaos_prediction") else 24
			var prediction_points: Array = []
			var position := _dict_to_vector(star.get("position", {}))
			var velocity := _dict_to_vector(star.get("velocity", {}))
			for step in range(prediction_steps):
				position += velocity * 0.25
				prediction_points.append({"x": position.x, "y": position.y, "z": position.z})
			_prediction_meshes[index].mesh = _line_mesh(prediction_points, Color(color, 0.35), true)


func _line_mesh(points: Array, color: Color, prediction: bool) -> ImmediateMesh:
	var immediate := ImmediateMesh.new()
	if points.size() < 2:
		return immediate
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var primitive := Mesh.PRIMITIVE_LINES if prediction else Mesh.PRIMITIVE_LINE_STRIP
	immediate.surface_begin(primitive, material)
	for index in range(points.size()):
		if prediction and index > 0 and index % 2 == 0:
			continue
		var fade := 0.15 + 0.85 * float(index) / float(maxi(1, points.size() - 1))
		immediate.surface_set_color(Color(color.r, color.g, color.b, color.a * fade))
		immediate.surface_add_vertex(_dict_to_vector(points[index]))
		if prediction and index + 1 < points.size():
			immediate.surface_set_color(Color(color.r, color.g, color.b, color.a * fade))
			immediate.surface_add_vertex(_dict_to_vector(points[index + 1]))
	immediate.surface_end()
	return immediate


func _update_camera(p_delta: float) -> void:
	var target := _free_target
	if _locked_on_planet:
		for mesh in _star_meshes:
			if mesh.get_meta("is_planet", false):
				target = mesh.position
				break
	var offset := Vector3(
		cos(deg_to_rad(_cam_angle_v)) * cos(deg_to_rad(_cam_angle_h)),
		sin(deg_to_rad(_cam_angle_v)),
		cos(deg_to_rad(_cam_angle_v)) * sin(deg_to_rad(_cam_angle_h))
	) * _cam_distance
	var desired := target + offset
	var smoothing := 1.0 - exp(-8.0 * p_delta)
	%Camera3D.position = %Camera3D.position.lerp(desired, smoothing)
	%Camera3D.look_at(target)


func _handle_continuous_input(p_delta: float) -> void:
	var rotation_speed := 55.0 * p_delta
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		_cam_angle_h -= rotation_speed
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		_cam_angle_h += rotation_speed
	if Input.is_key_pressed(KEY_Q):
		_cam_angle_v = clamp(_cam_angle_v - rotation_speed, -89.0, 89.0)
	if Input.is_key_pressed(KEY_E):
		_cam_angle_v = clamp(_cam_angle_v + rotation_speed, -89.0, 89.0)
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		_cam_distance = max(12.0 if _locked_on_planet else 40.0, _cam_distance - 140.0 * p_delta)
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		_cam_distance = min(2000.0, _cam_distance + 140.0 * p_delta)


func _input(event: InputEvent) -> void:
	if GameState.game_over:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if %HelpPanel.visible:
			%HelpPanel.visible = false
		else:
			_on_back_pressed()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_on_pause_pressed()
		get_viewport().set_input_as_handled()
		return
	if %HelpPanel.visible:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			_last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_cam_distance = max(12.0 if _locked_on_planet else 40.0, _cam_distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_cam_distance = min(2000.0, _cam_distance * 1.1)
	elif event is InputEventMouseMotion and _dragging:
		var delta: Vector2 = event.position - _last_mouse_pos
		_cam_angle_h -= delta.x * 0.3
		_cam_angle_v = clamp(_cam_angle_v - delta.y * 0.3, -89.0, 89.0)
		_last_mouse_pos = event.position


func _refresh_info() -> void:
	if not GameState.game_started or GameState.tech_tree == null:
		%InfoLabel.text = "尚未开始游戏，无法读取星图模拟数据"
		return
	var state: Dictionary = GameState.get_state()
	var environment: Dictionary = state.get("environment", {}).get("params", {})
	var prediction := "实时轨迹"
	if GameState.tech_tree.is_unlocked("chaos_prediction"):
		prediction = "长程混沌预测"
	elif GameState.tech_tree.is_unlocked("computer"):
		prediction = "短程轨道预测"
	%InfoLabel.text = "第 %.1f 天  |  温度 %.1f℃  |  辐射 %.2f  |  %s  |  %s" % [
		state.get("game_time", 0.0), environment.get("temperature", 0.0),
		environment.get("radiation", 0.0), prediction,
		"行星锁定" if _locked_on_planet else "自由视角",
	]


func _dict_to_vector(value) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		return Vector3(value.get("x", 0.0), value.get("y", 0.0), value.get("z", 0.0))
	return Vector3.ZERO


func _on_pause_pressed() -> void:
	GameState.toggle_pause()
	_update_pause_button()


func _update_pause_button() -> void:
	%PauseButton.text = "继续" if GameState.paused else "暂停"


func _on_lock_toggled() -> void:
	_locked_on_planet = not _locked_on_planet
	if _locked_on_planet:
		_saved_free_distance = _cam_distance
		_cam_distance = 55.0
		%LockButton.text = "解锁行星"
	else:
		_cam_distance = _saved_free_distance
		%LockButton.text = "锁定行星"


func _on_help_toggled() -> void:
	%HelpPanel.visible = not %HelpPanel.visible


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")


func _on_restart_pressed() -> void:
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/main_menu/start_game_menu.tscn")
