extends Control
## Visible-only knowledge graph with domain filtering, search, risk view, zoom, and pan.

signal node_clicked(node_id: String)
signal node_hovered(node_id: String, local_position: Vector2)

const KnowledgeSystemScript = preload("res://scripts/simulation/knowledge_system.gd")
const NODE_SIZE := Vector2(190.0, 78.0)
const TIER_GAP := 265.0
const NODE_GAP := 104.0
const ORIGIN := Vector2(70.0, 60.0)

var zoom: float = 1.0
var view_offset := Vector2.ZERO
var domain_filter: String = "all"
var search_text: String = ""
var risk_view: bool = false
var _node_rects: Dictionary = {}
var _visible_views: Dictionary = {}
var _dragging: bool = false
var _drag_start := Vector2.ZERO
var _hovered_id: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	gui_input.connect(_on_gui_input)
	resized.connect(queue_redraw)


func set_domain_filter(p_domain: String) -> void:
	domain_filter = p_domain
	queue_redraw()


func set_search_text(p_text: String) -> void:
	search_text = p_text.strip_edges().to_lower()
	queue_redraw()


func set_risk_view(p_enabled: bool) -> void:
	risk_view = p_enabled
	queue_redraw()


func _draw() -> void:
	_node_rects.clear()
	_visible_views.clear()
	if not GameState.game_started or GameState.knowledge_system == null:
		return
	for view_value in GameState.knowledge_system.get_visible_nodes():
		var view: Dictionary = view_value
		if domain_filter != "all" and str(view.get("domain", "")) != domain_filter:
			continue
		if not search_text.is_empty():
			var searchable := "%s %s" % [view.get("display_name", ""), view.get("description", "")]
			if search_text not in searchable.to_lower():
				continue
		var node_id := str(view["id"])
		_visible_views[node_id] = view
		_node_rects[node_id] = _node_rect(view)

	for node_id in _visible_views:
		var view: Dictionary = _visible_views[node_id]
		var destination: Rect2 = _node_rects[node_id]
		for prerequisite_id in view.get("prerequisite_ids", []):
			if not _node_rects.has(prerequisite_id):
				continue
			var source: Rect2 = _node_rects[prerequisite_id]
			var prerequisite_view: Dictionary = _visible_views[prerequisite_id]
			var same_domain: bool = prerequisite_view.get("domain", "") == view.get("domain", "")
			var color := Color(0.30, 0.52, 0.86, 0.85) if same_domain else Color(0.38, 0.42, 0.55, 0.48)
			if int(prerequisite_view.get("state", 0)) >= KnowledgeSystemScript.KnowledgeState.MASTERED:
				color = Color(0.32, 0.82, 0.48, 0.88) if same_domain else Color(0.38, 0.65, 0.54, 0.55)
			_draw_bezier(Vector2(source.end.x, source.get_center().y), Vector2(destination.position.x, destination.get_center().y), color)

	for node_id in _visible_views:
		_draw_node(node_id, _visible_views[node_id], _node_rects[node_id])


func _node_rect(p_view: Dictionary) -> Rect2:
	var content_position := ORIGIN + Vector2(int(p_view.get("tier", 0)) * TIER_GAP, int(p_view.get("column", 0)) * NODE_GAP)
	return Rect2(content_position * zoom + view_offset, NODE_SIZE * zoom)


func _draw_bezier(p_start: Vector2, p_finish: Vector2, p_color: Color) -> void:
	var control_x := (p_start.x + p_finish.x) * 0.5
	var points := PackedVector2Array()
	for step in range(21):
		var t := float(step) / 20.0
		var inverse := 1.0 - t
		points.append(
			inverse * inverse * inverse * p_start
			+ 3.0 * inverse * inverse * t * Vector2(control_x, p_start.y)
			+ 3.0 * inverse * t * t * Vector2(control_x, p_finish.y)
			+ t * t * t * p_finish
		)
	draw_polyline(points, p_color, maxf(1.0, 2.0 * zoom), true)


func _draw_node(p_node_id: String, p_view: Dictionary, p_rect: Rect2) -> void:
	if not p_rect.intersects(Rect2(Vector2.ZERO, size)):
		return
	var state := int(p_view.get("state", KnowledgeSystemScript.KnowledgeState.HIDDEN))
	var colors := _state_colors(state)
	if risk_view and state in [KnowledgeSystemScript.KnowledgeState.MASTERED, KnowledgeSystemScript.KnowledgeState.APPLIED]:
		var risk := 1.0 - maxf(
			float(p_view.get("living_transmission", 0.0)),
			maxf(float(p_view.get("record_integrity", 0.0)), float(p_view.get("practice_level", 0.0)))
		)
		colors["border"] = Color(0.25, 0.85, 0.45).lerp(Color(1.0, 0.20, 0.18), clampf(risk, 0.0, 1.0))
	draw_style_box(_node_style(colors["background"], colors["border"], p_node_id == _hovered_id), p_rect)
	var font_size := maxi(10, int(16.0 * zoom))
	var small_size := maxi(9, int(11.0 * zoom))
	draw_string(
		ThemeDB.fallback_font, p_rect.position + Vector2(10.0, 25.0) * zoom,
		str(p_view.get("display_name", p_node_id)), HORIZONTAL_ALIGNMENT_LEFT,
		p_rect.size.x - 20.0 * zoom, font_size, colors["text"]
	)
	draw_string(
		ThemeDB.fallback_font, p_rect.position + Vector2(10.0, 49.0) * zoom,
		"%s · %s" % [_domain_name(str(p_view.get("domain", ""))), p_view.get("state_name", "")],
		HORIZONTAL_ALIGNMENT_LEFT, p_rect.size.x - 20.0 * zoom, small_size, Color(0.70, 0.76, 0.88)
	)
	if state == KnowledgeSystemScript.KnowledgeState.RESEARCHING:
		_draw_progress_bar(p_rect, float(p_view.get("research_progress", 0.0)), Color(1.0, 0.72, 0.2))
	elif state == KnowledgeSystemScript.KnowledgeState.MASTERED:
		var progress_values: Array = p_view.get("engineering_progress", {}).values()
		if not progress_values.is_empty():
			_draw_progress_bar(p_rect, float(progress_values.max()), Color(0.35, 0.82, 1.0))
	elif state == KnowledgeSystemScript.KnowledgeState.APPLIED:
		draw_string(ThemeDB.fallback_font, p_rect.position + Vector2(p_rect.size.x - 28.0 * zoom, 24.0 * zoom), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.48, 1.0, 0.62))


func _draw_progress_bar(p_rect: Rect2, p_progress: float, p_color: Color) -> void:
	var bar := Rect2(p_rect.position + Vector2(7.0 * zoom, p_rect.size.y - 9.0 * zoom), Vector2(p_rect.size.x - 14.0 * zoom, 4.0 * zoom))
	draw_rect(bar, Color(0.04, 0.05, 0.08), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(p_progress, 0.0, 1.0), bar.size.y)), p_color, true)


func _state_colors(p_state: int) -> Dictionary:
	match p_state:
		KnowledgeSystemScript.KnowledgeState.RUMOR:
			return {"background": Color(0.18, 0.17, 0.25, 0.96), "border": Color(0.48, 0.45, 0.65), "text": Color(0.78, 0.76, 0.88)}
		KnowledgeSystemScript.KnowledgeState.INSIGHT:
			return {"background": Color(0.16, 0.25, 0.38, 0.96), "border": Color(0.42, 0.68, 0.92), "text": Color(0.84, 0.92, 1.0)}
		KnowledgeSystemScript.KnowledgeState.RESEARCHABLE:
			return {"background": Color(0.12, 0.31, 0.52, 0.96), "border": Color(0.38, 0.78, 1.0), "text": Color(0.86, 0.94, 1.0)}
		KnowledgeSystemScript.KnowledgeState.RESEARCHING:
			return {"background": Color(0.46, 0.31, 0.08, 0.96), "border": Color(1.0, 0.76, 0.26), "text": Color(1.0, 0.90, 0.64)}
		KnowledgeSystemScript.KnowledgeState.MASTERED:
			return {"background": Color(0.12, 0.34, 0.40, 0.96), "border": Color(0.30, 0.84, 0.92), "text": Color(0.80, 1.0, 1.0)}
		KnowledgeSystemScript.KnowledgeState.APPLIED:
			return {"background": Color(0.10, 0.38, 0.22, 0.96), "border": Color(0.38, 1.0, 0.56), "text": Color(0.82, 1.0, 0.86)}
		KnowledgeSystemScript.KnowledgeState.DEGRADED:
			return {"background": Color(0.42, 0.10, 0.12, 0.96), "border": Color(1.0, 0.30, 0.28), "text": Color(1.0, 0.78, 0.76)}
		_:
			return {"background": Color(0.12, 0.12, 0.16), "border": Color(0.3, 0.3, 0.4), "text": Color(0.7, 0.7, 0.8)}


func _node_style(p_background: Color, p_border: Color, p_hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = p_background
	style.border_color = p_border
	style.set_border_width_all(3 if p_hovered else 2)
	style.set_corner_radius_all(8)
	return style


func _domain_name(p_domain: String) -> String:
	return {
		"memory": "记忆", "measurement": "测量", "materials": "材料", "energy": "能量",
		"astronomy": "天文", "life": "生命", "survival": "生存", "natural_law": "自然规律", "engineering": "工程",
	}.get(p_domain, p_domain)


func _on_gui_input(p_event: InputEvent) -> void:
	if p_event is InputEventMouseButton:
		if p_event.button_index == MOUSE_BUTTON_WHEEL_UP and p_event.pressed:
			_zoom_at(p_event.position, 0.1)
			accept_event()
		elif p_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and p_event.pressed:
			_zoom_at(p_event.position, -0.1)
			accept_event()
		elif p_event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = p_event.pressed
			_drag_start = p_event.position
			accept_event()
		elif p_event.button_index == MOUSE_BUTTON_LEFT and p_event.pressed:
			var node_id := _node_at(p_event.position)
			if not node_id.is_empty():
				node_clicked.emit(node_id)
				accept_event()
	elif p_event is InputEventMouseMotion:
		if _dragging:
			view_offset += p_event.position - _drag_start
			_drag_start = p_event.position
			queue_redraw()
			accept_event()
		else:
			var node_id := _node_at(p_event.position)
			if node_id != _hovered_id:
				_hovered_id = node_id
				queue_redraw()
			node_hovered.emit(node_id, p_event.position)


func _zoom_at(p_mouse_position: Vector2, p_delta: float) -> void:
	var old_zoom := zoom
	zoom = clampf(zoom + p_delta, 0.4, 2.0)
	if is_equal_approx(old_zoom, zoom):
		return
	view_offset = p_mouse_position - (p_mouse_position - view_offset) * (zoom / old_zoom)
	queue_redraw()


func _node_at(p_position: Vector2) -> String:
	for node_id in _node_rects:
		if (_node_rects[node_id] as Rect2).has_point(p_position):
			return node_id
	return ""
