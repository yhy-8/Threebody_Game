extends Node
## 开发者工具状态修改回归测试。


func _ready() -> void:
	var universe_name := "__自动回归_%d" % Time.get_ticks_usec()
	GameState.set_developer_mode(true)
	GameState.new_game(universe_name)
	assert(GameState.confirm_capital(int(GameState.settlement_system.candidate_views[0].get("zone_id", -1))).get("success", false))
	assert(GameState.can_access_starmap())
	var applied: bool = GameState.apply_developer_values({
		"population": {"total": 4321, "stored": 123, "breeders": 321},
		"resources": {"iron": 9876.0, "food": 5432.0},
		"research": {"basic": 111.0, "applied": 222.0, "theoretical": 333.0},
	})
	assert(applied)
	assert(GameState.entities.population.total == 4321)
	assert(GameState.entities.population.stored_population == 123)
	assert(GameState.entities.population.breeders == 321)
	assert(is_equal_approx(GameState.entities.get_resource("iron"), 9876.0))
	assert(is_equal_approx(GameState.entities.get_resource("food"), 5432.0))
	assert(is_equal_approx(GameState.tech_tree.research_points["theoretical"], 333.0))
	assert(GameState.developer_fill_resources(77777.0))
	for resource_id in GameState.entities.resources:
		assert(is_equal_approx(GameState.entities.get_resource(resource_id), 77777.0))
	assert(GameState.developer_unlock_all_technologies())
	for tech_node in GameState.tech_tree.nodes.values():
		assert(tech_node.unlocked)
	assert(SaveManager.save_game(GameState, "开发者工具测试", universe_name))
	var save_path := SaveManager.get_current_save_path()
	assert(save_path.begins_with(ProjectSettings.globalize_path("res://saves/")))
	assert(FileAccess.file_exists(save_path))
	assert(SaveManager.scan_saves().has(universe_name))
	GameState.entities.population.total = 1
	assert(SaveManager.load_game(save_path, GameState))
	assert(GameState.entities.population.total == 4321)
	assert(SaveManager.delete_save(save_path))
	var first_star = GameState.environment.stars[0]
	var second_star = GameState.environment.stars[1]
	first_star.position = second_star.position
	first_star.velocity = second_star.velocity
	assert(GameState.environment.has_collision())
	GameState.paused = false
	GameState.update(0.01)
	assert(GameState.game_over)
	print("DEVELOPER_TOOLS_TEST_OK")
	get_tree().quit()
