class_name KnowledgeInheritance
extends RefCounted
## Generation-scale retention and disaster shocks; never reads UI controls directly.

const STATE_VERSION := 1
const GENERATION_DAYS := 25.0 * 365.0

var knowledge_system
var last_generation_day: float = 0.0
var generation_index: int = 0
var retention_history: Array = []


func _init(p_knowledge_system) -> void:
	knowledge_system = p_knowledge_system


func update_day(p_game_day: float, p_context: Dictionary) -> Array:
	var results: Array = []
	while p_game_day - last_generation_day >= GENERATION_DAYS:
		last_generation_day += GENERATION_DAYS
		generation_index += 1
		var result: Dictionary = knowledge_system.apply_generation_turnover(p_context)
		result["generation_index"] = generation_index
		result["game_day"] = last_generation_day
		retention_history.append(result.duplicate(true))
		results.append(result)
	return results


func apply_disaster_result(p_loss_vector: Dictionary) -> Dictionary:
	var shock := p_loss_vector.duplicate(true)
	shock["source_id"] = str(p_loss_vector.get("source_id", "disaster:unknown"))
	return knowledge_system.apply_knowledge_shock(shock)


func get_state() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"last_generation_day": last_generation_day,
		"generation_index": generation_index,
		"retention_history": retention_history.duplicate(true),
	}


func load_state(p_data: Dictionary) -> bool:
	if p_data.has("retention_history") and not p_data["retention_history"] is Array:
		return false
	last_generation_day = maxf(0.0, float(p_data.get("last_generation_day", 0.0)))
	generation_index = maxi(0, int(p_data.get("generation_index", 0)))
	retention_history = (p_data.get("retention_history", []) as Array).duplicate(true)
	return true
