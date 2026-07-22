class_name KnowledgeGraph
extends RefCounted
## Immutable, data-driven knowledge definitions keyed by stable string IDs.

const DEFAULT_DATA_PATH := "res://resources/knowledge/knowledge_nodes.json"

var data_version: int = 0
var nodes: Dictionary = {}
var _children: Dictionary = {}
var validation_errors: PackedStringArray = PackedStringArray()


func _init(p_data_path: String = DEFAULT_DATA_PATH) -> void:
	_load_data(p_data_path)
	validation_errors = validate()


func _load_data(p_path: String) -> void:
	if not FileAccess.file_exists(p_path):
		validation_errors.append("知识节点数据不存在：%s" % p_path)
		return
	var file := FileAccess.open(p_path, FileAccess.READ)
	if file == null:
		validation_errors.append("无法读取知识节点数据：%s" % p_path)
		return
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK:
		validation_errors.append("知识节点 JSON 无效：%s" % json.get_error_message())
		return
	var root = json.get_data()
	if not root is Dictionary:
		validation_errors.append("知识节点根数据必须是字典")
		return
	data_version = int(root.get("data_version", 0))
	for definition_value in root.get("nodes", []):
		if not definition_value is Dictionary:
			continue
		var definition: Dictionary = definition_value
		var node_id := str(definition.get("id", ""))
		if node_id.is_empty() or nodes.has(node_id):
			validation_errors.append("知识节点 ID 缺失或重复：%s" % node_id)
			continue
		nodes[node_id] = definition.duplicate(true)
	_build_children()


func _build_children() -> void:
	_children.clear()
	for node_id in nodes:
		_children[node_id] = []
	for node_id in nodes:
		var definition: Dictionary = nodes[node_id]
		for prerequisite_id in definition.get("prerequisite_ids", []):
			if _children.has(prerequisite_id):
				_children[prerequisite_id].append(node_id)


func validate() -> PackedStringArray:
	var errors := validation_errors.duplicate()
	if data_version <= 0:
		errors.append("知识图 data_version 必须为正整数")
	if nodes.is_empty():
		errors.append("知识图没有节点")
	for node_id in nodes:
		var definition: Dictionary = nodes[node_id]
		for required_key in ["domain", "name", "rumor_label", "prerequisite_ids", "research_requirements", "engineering_projects", "inheritance_profile"]:
			if not definition.has(required_key):
				errors.append("知识节点 %s 缺少字段 %s" % [node_id, required_key])
		for prerequisite_id in definition.get("prerequisite_ids", []):
			if prerequisite_id == node_id:
				errors.append("知识节点 %s 不能依赖自身" % node_id)
			elif not nodes.has(prerequisite_id):
				errors.append("知识节点 %s 引用不存在的前置 %s" % [node_id, prerequisite_id])
		var project_ids: Dictionary = {}
		for project_value in definition.get("engineering_projects", []):
			if not project_value is Dictionary:
				errors.append("知识节点 %s 的工程项目格式无效" % node_id)
			continue
			var project_id := str(project_value.get("id", ""))
			if project_id.is_empty() or project_ids.has(project_id):
				errors.append("知识节点 %s 的工程项目 ID 缺失或重复" % node_id)
			project_ids[project_id] = true
	_validate_acyclic(errors)
	return errors


func _validate_acyclic(p_errors: PackedStringArray) -> void:
	var visiting: Dictionary = {}
	var visited: Dictionary = {}
	for node_id in nodes:
		_visit_node(node_id, visiting, visited, p_errors)


func _visit_node(p_node_id: String, p_visiting: Dictionary, p_visited: Dictionary, p_errors: PackedStringArray) -> void:
	if p_visited.has(p_node_id):
		return
	if p_visiting.has(p_node_id):
		p_errors.append("知识图存在循环依赖：%s" % p_node_id)
		return
	p_visiting[p_node_id] = true
	var definition: Dictionary = nodes[p_node_id]
	for prerequisite_id in definition.get("prerequisite_ids", []):
		if nodes.has(prerequisite_id):
			_visit_node(prerequisite_id, p_visiting, p_visited, p_errors)
	p_visiting.erase(p_node_id)
	p_visited[p_node_id] = true


func is_valid() -> bool:
	return validation_errors.is_empty()


func get_definition(p_node_id: String) -> Dictionary:
	return (nodes.get(p_node_id, {}) as Dictionary).duplicate(true)


func get_children(p_node_id: String) -> Array:
	return (_children.get(p_node_id, []) as Array).duplicate()


func get_nodes_by_domain(p_domain: String) -> Array:
	var result: Array = []
	for node_id in nodes:
		if str(nodes[node_id].get("domain", "")) == p_domain:
			result.append(node_id)
	return result


func get_domains() -> Array[String]:
	var domains: Array[String] = []
	for definition_value in nodes.values():
		var domain := str(definition_value.get("domain", ""))
		if not domain.is_empty() and domain not in domains:
			domains.append(domain)
	domains.sort()
	return domains
