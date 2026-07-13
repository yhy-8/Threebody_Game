extends Control
## 科技树界面

const TechTreeScript = preload("res://scripts/simulation/tech_tree.gd")


func _ready() -> void:
	%BackButton.pressed.connect(_on_back_pressed)
	_refresh_display()


func _refresh_display() -> void:
	if not GameState.game_started:
		return

	var points_hbox := %PointsHBox
	_clear_children(points_hbox)

	for rtype in ["basic", "applied", "theoretical"]:
		var amount: float = GameState.tech_tree.research_points.get(rtype, 0.0)
		var name: String = TechTreeScript.RESEARCH_NAMES.get(rtype, rtype)
		var label := Label.new()
		label.text = "%s: %.1f" % [name, amount]
		var col: Color = TechTreeScript.RESEARCH_COLORS.get(rtype, Color.WHITE)
		label.add_theme_color_override("font_color", col)
		points_hbox.add_child(label)

	# Show current research progress
	var progress: Dictionary = GameState.tech_tree.get_research_progress()
	if not progress.is_empty():
		var prog_label := Label.new()
		prog_label.text = "研究: %s (%.0f%%)" % [progress["tech_name"], progress["overall_percent"] * 100]
		points_hbox.add_child(prog_label)

	# Tech tree nodes — draw on TechTreeContainer
	%TechTreeContainer.queue_redraw()


func _draw() -> void:
	if not GameState.game_started:
		return
	_draw_tech_nodes()


func _draw_tech_nodes() -> void:
	var tt = GameState.tech_tree
	var container: Control = %TechTreeContainer
	var max_tier: int = tt.get_max_tier()
	var tier_width: float = container.size.x / float(max_tier + 2)

	const NODE_WIDTH := 140.0
	const NODE_HEIGHT := 60.0

	for tier in range(max_tier + 1):
		var nodes_in_tier: Array = tt.get_nodes_by_tier(tier)
		var x_base: float = 80.0 + tier * tier_width
		var spacing: float = container.size.y / float(nodes_in_tier.size() + 1)

		for i in nodes_in_tier.size():
			var node = nodes_in_tier[i]
			var y: float = spacing * (i + 1) - NODE_HEIGHT / 2.0
			var rect := Rect2(x_base, y, NODE_WIDTH, NODE_HEIGHT)

			var bg_color: Color
			if node.unlocked:
				bg_color = Color(0.2, 0.5, 0.2, 0.8)
			elif node.researching:
				bg_color = Color(0.5, 0.4, 0.1, 0.8)
			elif tt.is_researchable(node.id):
				bg_color = Color(0.2, 0.3, 0.5, 0.8)
			else:
				bg_color = Color(0.15, 0.15, 0.2, 0.6)

			draw_rect(rect, bg_color, true)
			draw_rect(rect, Color(0.4, 0.4, 0.6, 1.0), false)

			draw_string(ThemeDB.fallback_font, Vector2(x_base + 4, y + 22), node.name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
			draw_string(ThemeDB.fallback_font, Vector2(x_base + 4, y + 42),
				"T%d" % node.tier, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.8))

			# Draw lines to prerequisites
			for pre_id in node.prerequisites:
				var pre_node = tt.get_node(pre_id)
				if pre_node != null:
					var pre_tier_nodes: Array = tt.get_nodes_by_tier(pre_node.tier)
					var pre_idx := pre_tier_nodes.find(pre_node)
					if pre_idx >= 0:
						var pre_x: float = 80.0 + pre_node.tier * tier_width + NODE_WIDTH
						var pre_y: float = spacing * (pre_idx + 1)
						draw_line(Vector2(x_base, y + NODE_HEIGHT / 2.0), Vector2(pre_x, pre_y), Color(0.3, 0.3, 0.5, 0.5))


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")
