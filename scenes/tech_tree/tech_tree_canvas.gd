extends Control
## Interactive technology-tree canvas: drawing, zooming, panning, and hit testing.

signal node_clicked(node_id: String)
signal node_hovered(node_id: String, local_position: Vector2)

const NODE_SIZE := Vector2(170.0, 64.0)
const TIER_GAP := 250.0
const NODE_GAP := 92.0
const ORIGIN := Vector2(70.0, 60.0)

var zoom: float = 1.0
var view_offset := Vector2.ZERO
var _node_rects: Dictionary = {}
var _dragging: bool = false
var _drag_start := Vector2.ZERO
var _hovered_id: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	gui_input.connect(_on_gui_input)
	resized.connect(queue_redraw)


func _draw() -> void:
	_node_rects.clear()
	if not GameState.game_started or GameState.tech_tree == null:
		return

	var tech_tree = GameState.tech_tree
	for node_id in tech_tree.nodes:
		var node = tech_tree.nodes[node_id]
		_node_rects[node_id] = _node_rect(node)

	for node_id in tech_tree.nodes:
		var node = tech_tree.nodes[node_id]
		var dst: Rect2 = _node_rects[node_id]
		for prerequisite_id in node.prerequisites:
			if not _node_rects.has(prerequisite_id):
				continue
			var prerequisite = tech_tree.get_node(prerequisite_id)
			var src: Rect2 = _node_rects[prerequisite_id]
			var color := Color(0.2, 0.22, 0.32, 0.9)
			if prerequisite != null and prerequisite.unlocked and node.unlocked:
				color = Color(0.28, 0.8, 0.42, 0.9)
			elif prerequisite != null and prerequisite.unlocked:
				color = Color(0.35, 0.62, 1.0, 0.9)
			_draw_bezier(
				Vector2(src.end.x, src.get_center().y),
				Vector2(dst.position.x, dst.get_center().y),
				color
			)

	for node_id in tech_tree.nodes:
		_draw_node(node_id, tech_tree.nodes[node_id], _node_rects[node_id])


func _node_rect(node) -> Rect2:
	var content_position := ORIGIN + Vector2(node.tier * TIER_GAP, node.column * NODE_GAP)
	return Rect2(content_position * zoom + view_offset, NODE_SIZE * zoom)


func _draw_bezier(start: Vector2, finish: Vector2, color: Color) -> void:
	var control_x := (start.x + finish.x) * 0.5
	var points := PackedVector2Array()
	for step in range(21):
		var t := float(step) / 20.0
		var inverse := 1.0 - t
		var point := (
			inverse * inverse * inverse * start
			+ 3.0 * inverse * inverse * t * Vector2(control_x, start.y)
			+ 3.0 * inverse * t * t * Vector2(control_x, finish.y)
			+ t * t * t * finish
		)
		points.append(point)
	draw_polyline(points, color, max(1.0, 2.0 * zoom), true)


func _draw_node(node_id: String, node, rect: Rect2) -> void:
	if not rect.intersects(Rect2(Vector2.ZERO, size)):
		return

	var tech_tree = GameState.tech_tree
	var background := Color(0.15, 0.15, 0.2, 0.95)
	var border := Color(0.3, 0.3, 0.42)
	var text_color := Color(0.55, 0.55, 0.65)
	if node.unlocked:
		background = Color(0.12, 0.42, 0.23, 0.96)
		border = Color(0.4, 1.0, 0.55)
		text_color = Color(0.82, 1.0, 0.85)
	elif node.researching:
		background = Color(0.47, 0.31, 0.08, 0.96)
		border = Color(1.0, 0.78, 0.3)
		text_color = Color(1.0, 0.88, 0.62)
	elif tech_tree.is_researchable(node_id):
		background = Color(0.13, 0.3, 0.55, 0.96)
		border = Color(0.4, 0.75, 1.0)
		text_color = Color(0.82, 0.9, 1.0)

	draw_style_box(_node_style(background, border, node_id == _hovered_id), rect)
	var font_size := maxi(10, int(16.0 * zoom))
	var small_size := maxi(9, int(12.0 * zoom))
	var name_position := rect.position + Vector2(10.0 * zoom, 24.0 * zoom)
	draw_string(ThemeDB.fallback_font, name_position, node.name,
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0 * zoom, font_size, text_color)

	var category_name: String = {
		"basic": "基础", "applied": "应用", "theoretical": "理论",
	}.get(node.category, "")
	draw_string(ThemeDB.fallback_font,
		rect.position + Vector2(10.0 * zoom, 47.0 * zoom),
		"T%d  %s" % [node.tier, category_name], HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 20.0 * zoom, small_size, Color(0.7, 0.75, 0.88))

	if node.unlocked:
		draw_string(ThemeDB.fallback_font,
			rect.position + Vector2(rect.size.x - 25.0 * zoom, 22.0 * zoom),
			"✓", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.4, 1.0, 0.5))
	elif node.researching:
		var info: Dictionary = tech_tree.get_research_progress()
		var progress: float = info.get("overall_percent", 0.0)
		var bar := Rect2(
			rect.position + Vector2(6.0 * zoom, rect.size.y - 8.0 * zoom),
			Vector2(rect.size.x - 12.0 * zoom, 4.0 * zoom)
		)
		draw_rect(bar, Color(0.08, 0.08, 0.1), true)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)),
			Color(1.0, 0.72, 0.2), true)


func _node_style(background: Color, border: Color, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	var width := 3 if hovered else 2
	style.set_border_width_all(width)
	style.set_corner_radius_all(8)
	return style


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 0.1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, -0.1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
			_drag_start = event.position
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var node_id := _node_at(event.position)
			if not node_id.is_empty():
				node_clicked.emit(node_id)
				accept_event()
	elif event is InputEventMouseMotion:
		if _dragging:
			view_offset += event.position - _drag_start
			_drag_start = event.position
			queue_redraw()
			accept_event()
		else:
			var node_id := _node_at(event.position)
			if node_id != _hovered_id:
				_hovered_id = node_id
				queue_redraw()
			node_hovered.emit(node_id, event.position)


func _zoom_at(mouse_position: Vector2, delta: float) -> void:
	var old_zoom := zoom
	zoom = clamp(zoom + delta, 0.4, 2.0)
	if is_equal_approx(old_zoom, zoom):
		return
	var ratio := zoom / old_zoom
	view_offset = mouse_position - (mouse_position - view_offset) * ratio
	queue_redraw()


func _node_at(position: Vector2) -> String:
	for node_id in _node_rects:
		var rect: Rect2 = _node_rects[node_id]
		if rect.has_point(position):
			return node_id
	return ""
