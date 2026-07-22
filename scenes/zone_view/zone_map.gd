extends Control
## Clickable 12x6 Mercator-style planet heatmap.

signal zone_selected(zone_id: int)

var view_mode: String = "temperature"
var selected_zone_id: int = -1
var zones_summary: Array = []
var _hovered_zone_id: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	resized.connect(queue_redraw)


func set_data(p_zones_summary: Array) -> void:
	zones_summary = p_zones_summary
	queue_redraw()


func set_view_mode(p_mode: String) -> void:
	view_mode = p_mode
	queue_redraw()


func set_selected_zone(p_zone_id: int) -> void:
	selected_zone_id = p_zone_id
	queue_redraw()


func _draw() -> void:
	if zones_summary.is_empty():
		return
	var grid := _grid_rect()
	var cell_size := Vector2(grid.size.x / 12.0, grid.size.y / 6.0)
	var range_data := _value_range()
	var value_min: float = range_data.x
	var value_max: float = range_data.y

	for longitude_index in range(12):
		var label := "%d°" % (longitude_index * 30)
		draw_string(ThemeDB.fallback_font,
			Vector2(grid.position.x + longitude_index * cell_size.x + 4.0, grid.position.y - 8.0),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.55, 0.65, 0.85))
	for row in range(6):
		var latitude := 75 - row * 30
		draw_string(ThemeDB.fallback_font,
			Vector2(4.0, grid.position.y + row * cell_size.y + cell_size.y * 0.55),
			"%d°" % latitude, HORIZONTAL_ALIGNMENT_LEFT, 38.0, 11, Color(0.55, 0.65, 0.85))

	for zone_data in zones_summary:
		var zone: Dictionary = zone_data
		var latitude_index: int = zone.get("lat_i", 0)
		var longitude_index: int = zone.get("lon_i", 0)
		var row: int = 5 - latitude_index
		var rect := Rect2(
			grid.position + Vector2(longitude_index * cell_size.x, row * cell_size.y),
			cell_size
		)
		var value: float = _zone_value(zone)
		var known := bool(zone.get("known", false))
		var ratio: float = clampf((value - value_min) / maxf(value_max - value_min, 0.0001), 0.0, 1.0)
		draw_rect(rect, _heat_color(ratio) if known else Color(0.035, 0.04, 0.07, 1.0), true)

		var zone_id: int = zone.get("id", -1)
		var border_color := Color(0.12, 0.15, 0.24, 0.9)
		var border_width := 1.0
		if zone_id == selected_zone_id:
			border_color = Color(1.0, 0.95, 0.35)
			border_width = 3.0
		elif zone_id == _hovered_zone_id:
			border_color = Color(0.78, 0.86, 1.0)
			border_width = 2.0
		draw_rect(rect, border_color, false, border_width)

		var buildings: int = zone.get("buildings", 0)
		if buildings > 0:
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(rect.size.x - 15.0, rect.size.y - 5.0),
				str(buildings), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(1.0, 0.82, 0.35))
		if zone_id == _hovered_zone_id:
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(4.0, 15.0),
				_value_text(value) if known else "未知", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8.0, 11, Color.WHITE)

	var range_text := "%s范围：%s — %s" % [_mode_name(), _value_text(value_min), _value_text(value_max)]
	draw_string(ThemeDB.fallback_font, Vector2(grid.position.x, size.y - 8.0), range_text,
		HORIZONTAL_ALIGNMENT_LEFT, grid.size.x, 13, Color(0.65, 0.75, 0.92))


func _grid_rect() -> Rect2:
	return Rect2(Vector2(44.0, 30.0), Vector2(max(120.0, size.x - 54.0), max(90.0, size.y - 62.0)))


func _value_range() -> Vector2:
	var value_min: float = INF
	var value_max: float = -INF
	for zone_data in zones_summary:
		var zone: Dictionary = zone_data
		if not bool(zone.get("known", false)):
			continue
		var value: float = _zone_value(zone)
		value_min = min(value_min, value)
		value_max = max(value_max, value)
	if value_min == INF:
		return Vector2(0.0, 1.0)
	return Vector2(value_min, value_max)


func _zone_value(zone: Dictionary) -> float:
	match view_mode:
		"radiation": return zone.get("rad", 0.0)
		"light": return zone.get("light", 0.0)
		_: return zone.get("temp", 0.0)


func _heat_color(ratio: float) -> Color:
	match view_mode:
		"light":
			return Color(0.08 + ratio * 0.92, 0.08 + ratio * 0.78, 0.16 + ratio * 0.32)
		"radiation":
			return Color(0.12 + ratio * 0.78, 0.12 + ratio * 0.18, 0.35 + ratio * 0.45)
		_:
			if ratio < 0.5:
				return Color(0.08 + ratio * 0.4, 0.2 + ratio * 1.5, 0.85 - ratio * 0.8)
			return Color(0.35 + ratio * 0.65, 1.35 - ratio * 1.1, 0.05)


func _mode_name() -> String:
	return {"temperature": "温度", "radiation": "辐射", "light": "光照"}.get(view_mode, view_mode)


func _value_text(value: float) -> String:
	match view_mode:
		"temperature": return "%.1f℃" % value
		"light": return "%.0f%%" % (value * 100.0)
		_: return "%.2f" % value


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hovered_zone_id = _zone_at(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var zone_id: int = _zone_at(event.position)
		if zone_id >= 0:
			set_selected_zone(zone_id)
			zone_selected.emit(zone_id)
			accept_event()


func _zone_at(position: Vector2) -> int:
	var grid := _grid_rect()
	if not grid.has_point(position):
		return -1
	var cell_size := Vector2(grid.size.x / 12.0, grid.size.y / 6.0)
	var longitude_index := clampi(int((position.x - grid.position.x) / cell_size.x), 0, 11)
	var row := clampi(int((position.y - grid.position.y) / cell_size.y), 0, 5)
	var latitude_index := 5 - row
	return latitude_index * 12 + longitude_index
