extends Control
## 区域浏览界面 — 2D热力图 + 区域详情

const PlanetZoneManagerScript = preload("res://scripts/simulation/planet_zones.gd")

var view_mode: String = "temperature"  # temperature, radiation, light
var selected_zone_id: int = -1
var zones_summary: Array = []


func _ready() -> void:
	%BackButton.pressed.connect(_on_back_pressed)
	%ModeTemp.pressed.connect(func(): _set_mode("temperature"))
	%ModeRadiation.pressed.connect(func(): _set_mode("radiation"))
	%ModeLight.pressed.connect(func(): _set_mode("light"))
	_refresh_data()


func _set_mode(mode: String) -> void:
	view_mode = mode
	queue_redraw()


func _refresh_data() -> void:
	if not GameState.game_started:
		return
	var state: Dictionary = GameState.get_state()
	var pz_data: Dictionary = state["planet_zones"]
	zones_summary = pz_data.get("zones_summary", [])
	queue_redraw()


func _draw() -> void:
	if zones_summary.is_empty():
		return

	var grid_panel: Panel = %GridPanel
	var grid_rect := grid_panel.get_global_rect()
	var grid_pos := grid_rect.position
	var grid_size := grid_rect.size
	var margin := Vector2(40, 40)
	var draw_size := grid_size - margin * 2
	var cell_w: float = draw_size.x / 12.0
	var cell_h: float = draw_size.y / 6.0

	# Find min/max for current mode
	var values: Array = []
	for z in zones_summary:
		var zd: Dictionary = z
		match view_mode:
			"temperature": values.append(zd.get("temp", 0.0))
			"radiation": values.append(zd.get("rad", 0.0))
			"light": values.append(zd.get("light", 0.0))

	var v_min: float = values.min()
	var v_max: float = values.max()
	var v_range: float = max(v_max - v_min, 1.0)

	for z in zones_summary:
		var zd: Dictionary = z
		var lat_i: int = zd.get("lat_i", 0)
		var lon_i: int = zd.get("lon_i", 0)
		var val: float
		match view_mode:
			"temperature": val = zd.get("temp", 0.0)
			"radiation": val = zd.get("rad", 0.0)
			"light": val = zd.get("light", 0.0)

		var t: float = clamp((val - v_min) / v_range, 0.0, 1.0)
		var color: Color
		match view_mode:
			"temperature":
				color = Color(t, 0.2, 1.0 - t) if t < 0.5 else Color(1.0, (t - 0.5) * 2.0, 0.0)
			"radiation":
				color = Color(t * 0.8, t * 0.3, 1.0 - t * 0.5)
			"light":
				color = Color(t, t, 0.2 + t * 0.6)

		# Mercator: lat 0 (equator) at bottom
		var row: int = 5 - lat_i
		var cell_x: float = grid_pos.x + margin.x + lon_i * cell_w
		var cell_y: float = grid_pos.y + margin.y + row * cell_h

		draw_rect(Rect2(cell_x, cell_y, cell_w, cell_h), color, true)
		draw_rect(Rect2(cell_x, cell_y, cell_w, cell_h), Color(0.2, 0.2, 0.3, 0.5), false)

	# Draw detail panel
	var detail_panel: Panel = %DetailPanel
	var detail_vbox := _get_or_create_vbox(detail_panel)
	_clear_children(detail_vbox)

	match view_mode:
		"temperature": detail_vbox.add_child(_make_label("温度热力图 (%.0f ~ %.0f°C)" % [v_min, v_max]))
		"radiation": detail_vbox.add_child(_make_label("辐射热力图 (%.1f ~ %.1f)" % [v_min, v_max]))
		"light": detail_vbox.add_child(_make_label("光照热力图 (%.2f ~ %.2f)" % [v_min, v_max]))

	detail_vbox.add_child(_make_label("旋转角度: %.1f°" % GameState.planet_zones.rotation_angle))

	if selected_zone_id >= 0 and selected_zone_id < zones_summary.size():
		var zd: Dictionary = zones_summary[selected_zone_id]
		detail_vbox.add_child(_make_label(""))
		detail_vbox.add_child(_make_label("区域 %d" % selected_zone_id))
		detail_vbox.add_child(_make_label("地形: %s" % zd.get("terrain", "?")))
		detail_vbox.add_child(_make_label("温度: %.1f°C" % zd.get("temp", 0.0)))
		detail_vbox.add_child(_make_label("辐射: %.2f" % zd.get("rad", 0.0)))
		detail_vbox.add_child(_make_label("光照: %.2f" % zd.get("light", 0.0)))
		detail_vbox.add_child(_make_label("建筑: %d座" % zd.get("buildings", 0)))


func _get_or_create_vbox(panel: Panel) -> VBoxContainer:
	for child in panel.get_children():
		if child is VBoxContainer:
			return child
	var vbox := VBoxContainer.new()
	vbox.name = "DetailVBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	return vbox


func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")
