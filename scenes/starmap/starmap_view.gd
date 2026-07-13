extends Control
## 3D 星图 — 三体运动可视化

const ThreeBodySimScript = preload("res://scripts/simulation/three_body.gd")

var _cam_angle_h: float = 0.0
var _cam_angle_v: float = 30.0
var _cam_distance: float = 500.0
var _dragging: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _locked_on_planet: bool = false


func _ready() -> void:
	%BackButton.pressed.connect(_on_back_pressed)
	%PauseButton.pressed.connect(_on_pause_pressed)
	%LockButton.pressed.connect(_on_lock_toggled)

	if GameState.game_started:
		_update_star_meshes()
		_start_render_timer()


func _start_render_timer() -> void:
	var timer := Timer.new()
	timer.name = "StarmapTimer"
	timer.wait_time = 0.033  # ~30fps for starmap
	timer.timeout.connect(_on_render_tick)
	add_child(timer)
	timer.start()


func _on_render_tick() -> void:
	_update_camera()
	if not GameState.paused:
		_update_star_positions()


func _update_star_meshes() -> void:
	# Clear old meshes
	var parent: Node3D = %StarMap3D
	for child in parent.get_children():
		if child is MeshInstance3D and child != %Camera3D:
			parent.remove_child(child)
			child.queue_free()

	if not GameState.game_started:
		return

	var state: Dictionary = GameState.get_state()
	var stars_data: Array = state["environment"]["stars"]

	for sd in stars_data:
		var s: Dictionary = sd
		var mesh_instance := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = s.get("radius", 20.0) * 0.5
		sphere.height = sphere.radius * 2.0
		mesh_instance.mesh = sphere

		# Set material color
		var mat := StandardMaterial3D.new()
		var col: Dictionary = s.get("color", {})
		mat.albedo_color = Color(
			col.get("r", 1.0), col.get("g", 1.0), col.get("b", 1.0), col.get("a", 1.0)
		)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_instance.material_override = mat

		# Set position
		var pos: Dictionary = s.get("position", {})
		mesh_instance.position = Vector3(
			pos.get("x", 0.0), pos.get("y", 0.0), pos.get("z", 0.0)
		)

		# Set metadata
		mesh_instance.set_meta("is_planet", s.get("is_planet", false))
		mesh_instance.set_meta("star_index", stars_data.find(sd))

		parent.add_child(mesh_instance)


func _update_star_positions() -> void:
	if not GameState.game_started:
		return

	var state: Dictionary = GameState.get_state()
	var stars_data: Array = state["environment"]["stars"]
	var parent: Node3D = %StarMap3D

	for child in parent.get_children():
		if child is MeshInstance3D:
			var idx: int = child.get_meta("star_index", -1)
			if idx >= 0 and idx < stars_data.size():
				var sd: Dictionary = stars_data[idx]
				var pos: Dictionary = sd.get("position", {})
				child.position = Vector3(
					pos.get("x", 0.0), pos.get("y", 0.0), pos.get("z", 0.0)
				)


func _update_camera() -> void:
	var cam: Camera3D = %Camera3D
	if _locked_on_planet:
		# Find planet
		var parent: Node3D = %StarMap3D
		for child in parent.get_children():
			if child is MeshInstance3D and child.get_meta("is_planet", false):
				var offset := Vector3(
					cos(deg_to_rad(_cam_angle_v)) * cos(deg_to_rad(_cam_angle_h)),
					sin(deg_to_rad(_cam_angle_v)),
					cos(deg_to_rad(_cam_angle_v)) * sin(deg_to_rad(_cam_angle_h))
				) * _cam_distance
				cam.position = child.position + offset
				cam.look_at(child.position)
				return

	# Free camera
	var offset := Vector3(
		cos(deg_to_rad(_cam_angle_v)) * cos(deg_to_rad(_cam_angle_h)),
		sin(deg_to_rad(_cam_angle_v)),
		cos(deg_to_rad(_cam_angle_v)) * sin(deg_to_rad(_cam_angle_h))
	) * _cam_distance
	cam.position = offset
	cam.look_at(Vector3.ZERO)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			_last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_distance = max(50.0, _cam_distance - 20.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_distance = min(2000.0, _cam_distance + 20.0)
	elif event is InputEventMouseMotion and _dragging:
		var delta: Vector2 = event.position - _last_mouse_pos
		_cam_angle_h -= delta.x * 0.3
		_cam_angle_v = clamp(_cam_angle_v - delta.y * 0.3, -89.0, 89.0)
		_last_mouse_pos = event.position


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")


func _on_pause_pressed() -> void:
	GameState.toggle_pause()


func _on_lock_toggled() -> void:
	_locked_on_planet = not _locked_on_planet
	%LockButton.text = "解锁" if _locked_on_planet else "锁定行星"
