class_name CivilizationEventSystem
extends RefCounted
## State-triggered social and organizational choices. Events only describe a
## situation already present in the simulation; resolving a choice routes real
## costs and effects back through GameState.

const STATE_VERSION := 1
const MIN_INTERVAL_DAYS := 8.0
const MAX_HISTORY := 30

const RESOURCE_NAMES: Dictionary = {
	"food": "食物",
	"iron": "铁",
	"copper": "铜",
	"rare_mineral": "稀有矿物",
	"algae_fuel": "藻类燃料",
	"fossil_fuel": "化石燃料",
	"electricity": "电力",
}

const EVENTS: Array[Dictionary] = [
	{
		"id": "harvest_festival",
		"priority": 50,
		"title": "一次难得的丰收",
		"description": "仓库里堆着比预期更多的食物。是把它们全部留作储备、举办一次庆典提振士气，还是奖励更多家庭生育，需要文明自己决定。",
		"trigger": {"food_above": 450.0, "population_above": 80},
		"min_day": 20.0,
		"once": false,
		"cooldown_days": 150.0,
		"choices": [
			{
				"id": "feast",
				"label": "举办丰收庆典（消耗 60 食物，安定 +12%，健康 +5%）",
				"effects": {"resource": {"food": -60.0}, "stability": 0.12, "health": 0.05},
				"result": "聚落举行了久违的庆典；人们重新相信明天的劳动有意义。",
			},
			{
				"id": "store_all",
				"label": "全部入库，不举办庆典（安定 +3%）",
				"effects": {"stability": 0.03},
				"result": "粮食被仔细登记入库，为可能到来的短缺留下了余地。",
			},
			{
				"id": "support_families",
				"label": "奖励育儿家庭（消耗 80 食物，新增 4 个生育岗位）",
				"effects": {"resource": {"food": -80.0}, "breeders": 4},
				"result": "更多家庭愿意承担养育下一代的时间成本。",
			},
		],
	},
	{
		"id": "cold_warning",
		"priority": 100,
		"title": "寒意先于冬天到来",
		"description": "有人报告夜里结霜比往年更早。文明还没有能力给出精确的寒潮预报，但储备燃料、修补居所或调整劳作都能改变接下来几天的处境。",
		"trigger": {"zone_temp_below": 8.0},
		"min_day": 10.0,
		"once": false,
		"cooldown_days": 120.0,
		"choices": [
			{
				"id": "distribute_fuel",
				"label": "分发储备燃料并修补居所（消耗 25 藻类燃料）",
				"effects": {"resource": {"algae_fuel": -25.0}, "health": 0.06, "stability": 0.04},
				"result": "燃料被送进最冷的聚落，居民对即将到来的寒夜有了准备。",
			},
			{
				"id": "work_through",
				"label": "维持生产，要求大家坚持",
				"effects": {"stability": -0.05, "health": -0.02},
				"result": "生产没有停下，但有人开始抱怨组织者不把寒冷当回事。",
			},
		],
	},
	{
		"id": "food_pressure",
		"priority": 95,
		"title": "口粮清单越来越短",
		"description": "仓库管理员把账本摊开：按当前消耗，储备撑不了多少天。减量、集中采集或照常分配都会留下不同的后果。",
		"trigger": {"food_below_days": 8.0, "population_above": 40},
		"min_day": 12.0,
		"once": false,
		"cooldown_days": 90.0,
		"choices": [
			{
				"id": "ration_now",
				"label": "立即启动定量配给（食物消耗 -25%，劳动效率 -10%，安定 -2%）",
				"effects": {"policy": "rationing", "stability": -0.02},
				"result": "口粮被重新分配；饥饿风险下降，但劳动效率与居民情绪开始承受代价。",
			},
			{
				"id": "emergency_gather",
				"label": "抽调人手突击采集（消耗 30 铁制作工具，获得 40 食物）",
				"effects": {"resource": {"iron": -30.0, "food": 40.0}, "health": -0.03, "stability": 0.02},
				"result": "临时工具和突击采集带回了一批可食用藻类。",
			},
		],
	},
	{
		"id": "miner_insight",
		"priority": 85,
		"title": "矿工的非正式试验",
		"description": "矿场里有人反复加热不同矿石，声称能分辨出更易熔炼的配比。支持试验会占用口粮，但可能让文明更快理解金属。",
		"trigger": {"building_running": "iron_mine"},
		"min_day": 22.0,
		"choices": [
			{
				"id": "support_trials",
				"label": "拨给试验口粮（消耗 30 食物，获得金属工艺线索）",
				"effects": {
					"resource": {"food": -30.0},
					"discovery": {"node_id": "metallurgy", "clue": 0.18, "evidence": {"production_experience": 1.0}},
				},
				"result": "矿工留下了第一批可复查的炉温与配比记录。",
			},
			{
				"id": "keep_mining",
				"label": "要求专注当前产量（安定 +0.02）",
				"effects": {"stability": 0.02},
				"result": "矿石产量没有受到影响，但那些试验被搁置了。",
			},
		],
	},
	{
		"id": "teacher_shortage",
		"priority": 80,
		"title": "没有人愿意长期讲述",
		"description": "掌握知识的人更愿意直接参与生产。若没有固定教学安排，下一代可能只知道结论，不知道结论从何而来。",
		"trigger": {"knowledge_advanced_above": 2, "teaching_plan_count_below": 1},
		"min_day": 30.0,
		"choices": [
			{
				"id": "fund_teaching",
				"label": "抽出粮食支持讲述与记录（消耗 20 食物，获得符号记录线索）",
				"effects": {
					"resource": {"food": -20.0},
					"discovery": {"node_id": "symbolic_record", "clue": 0.16, "evidence": {"oral_repetition": 1.0}},
				},
				"result": "讲述者开始用刻痕和固定语句整理经验。",
			},
			{
				"id": "defer_teaching",
				"label": "先保证眼前生产（安定 -0.02）",
				"effects": {"stability": -0.02},
				"result": "生产继续，但知识的传承仍然依赖少数人的记忆。",
			},
		],
	},
	{
		"id": "worn_equipment",
		"priority": 75,
		"title": "设备开始发出异响",
		"description": "检修人员发现部分设施已经磨损。继续带病运行会降低效率，及时修复则需要占用当地材料。",
		"trigger": {"damaged_buildings_at_least": 1},
		"min_day": 30.0,
		"once": false,
		"cooldown_days": 120.0,
		"choices": [
			{
				"id": "repair_now",
				"label": "立即检修全部受损设施（消耗 35 铁）",
				"effects": {"resource": {"iron": -35.0}, "repair_buildings": 25.0, "stability": 0.02},
				"result": "磨损的部件被更换，设施重新接近满负荷运行。",
			},
			{
				"id": "run_to_failure",
				"label": "继续使用，等待更换时机（安定 -0.03）",
				"effects": {"stability": -0.03, "health": -0.02},
				"result": "生产没有中断，但维护人员对长期风险感到不安。",
			},
		],
	},
	{
		"id": "wanderers",
		"priority": 70,
		"title": "一批外来者请求加入",
		"description": "一支小群体带着少量工具来到聚落边缘，请求分享食物与庇护。接纳会增加人口和劳动力，也会立刻增加口粮压力。",
		"trigger": {"population_above": 120, "food_above": 220.0},
		"min_day": 50.0,
		"choices": [
			{
				"id": "accept_all",
				"label": "全部接纳（消耗 80 食物，人口 +10，安定 +0.04）",
				"effects": {"resource": {"food": -80.0}, "population": 10, "stability": 0.04},
				"result": "外来者被安置在首都附近，聚落多了一批可用的手和口。",
			},
			{
				"id": "screen_them",
				"label": "只接纳能证明技能的人（消耗 30 食物，人口 +4）",
				"effects": {"resource": {"food": -30.0}, "population": 4, "stability": 0.01},
				"result": "少数工匠被留下，其余人继续上路。",
			},
			{
				"id": "turn_away",
				"label": "拒绝并关闭外围通道（安定 -0.05）",
				"effects": {"stability": -0.05},
				"result": "聚落保住了储备，但围墙外的脚步声让一些人难以入睡。",
			},
		],
	},
	{
		"id": "night_sky",
		"priority": 60,
		"title": "夜空中的异常亮点",
		"description": "夜间有人看到一颗此前不显眼的亮星改变了位置。它可能只是寻常天象，也可能是长期记录的开端。",
		"trigger": {"days_above": 8.0},
		"min_day": 8.0,
		"choices": [
			{
				"id": "record_sky",
				"label": "组织夜间观测并刻下位置（消耗 10 食物，获得天象周期线索）",
				"effects": {
					"resource": {"food": -10.0},
					"discovery": {"node_id": "celestial_motion", "clue": 0.16, "evidence": {"sky_cycles": 1.0}},
				},
				"result": "观测者把亮星的位置刻在木板上，并注明了当夜。",
			},
			{
				"id": "let_them_rest",
				"label": "让大家休息，明天还要劳作（健康 +0.03）",
				"effects": {"health": 0.03},
				"result": "聚落获得了安静的一夜，但天空没有留下记录。",
			},
		],
	},
	{
		"id": "children_education",
		"priority": 55,
		"title": "孩子们在工坊外旁听",
		"description": "一些孩子开始模仿工匠的动作。正式组织识字与传艺会占用口粮和劳动时间，但也可能让知识真正留在下一代。",
		"trigger": {"population_above": 120, "knowledge_advanced_above": 1},
		"min_day": 40.0,
		"choices": [
			{
				"id": "start_classes",
				"label": "组织临时识字与传艺班（消耗 40 食物，获得符号记录线索）",
				"effects": {
					"resource": {"food": -40.0},
					"discovery": {"node_id": "symbolic_record", "clue": 0.2, "evidence": {"oral_repetition": 1.0}},
					"stability": 0.03,
				},
				"result": "孩子们第一次用同一套符号记录工具和作物。",
			},
			{
				"id": "send_to_work",
				"label": "让他们先参与生产（安定 -0.02）",
				"effects": {"stability": -0.02},
				"result": "劳动力增加了，但旁听的孩子很快被叫回了田地。",
			},
		],
	},
	{
		"id": "power_blackout",
		"priority": 90,
		"title": "电力负荷超过供给",
		"description": "电网正在超载。优先修复线路、限制非关键设施，还是让所有设施一起降载，会影响生产、维生与居民情绪。",
		"trigger": {"power_shortage": true},
		"min_day": 45.0,
		"choices": [
			{
				"id": "repair_grid",
				"label": "抢修线路并更换部件（消耗 25 铜，修复受损设施）",
				"effects": {"resource": {"copper": -25.0}, "repair_buildings": 20.0, "stability": 0.03},
				"result": "线路恢复，部分受损设施重新接近额定功率。",
			},
			{
				"id": "ration_power",
				"label": "未来 30 天优先保障维生与科研用电（工业设施降载）",
				"effects": {"power_priority_days": 30.0, "power_priority_mode": "lifeline", "stability": -0.02},
				"result": "维生、研究与观测设施优先获得电力，工业设施在缺口期间降载运行。",
			},
		],
	},
	{
		"id": "civic_works",
		"priority": 10,
		"title": "公共工程的争论",
		"description": "聚落需要决定把有限的材料与口粮用在什么地方。道路、庆典和维持现状都有人支持，没有一种选择不占用真实资源。",
		"trigger": {"days_above": 30.0},
		"min_day": 30.0,
		"once": false,
		"cooldown_days": 45.0,
		"choices": [
			{
				"id": "repair_paths",
				"label": "修缮公共道路与仓储（消耗 20 铁，修复设施并提升安定）",
				"effects": {"resource": {"iron": -20.0}, "repair_buildings": 10.0, "stability": 0.04},
				"result": "道路和仓储得到维护，搬运与施工比之前更顺畅。",
			},
			{
				"id": "public_festival",
				"label": "组织公共庆典（消耗 30 食物，安定 +8%，健康 +3%）",
				"effects": {"resource": {"food": -30.0}, "stability": 0.08, "health": 0.03},
				"result": "一次简朴的公共庆典让聚落重新有了共同节奏。",
			},
			{
				"id": "keep_working",
				"label": "维持现状，把资源留作储备（安定 -1%）",
				"effects": {"stability": -0.01},
				"result": "没有额外的公共工程，资源被留在仓库里。",
			},
		],
	},
	{
		"id": "chaos_anxiety",
		"priority": 110,
		"title": "天空不再守时",
		"description": "恒星的位置开始偏离旧记录。有人要求增加庇护，有人只想维持日常。文明还没有足够证据说明接下来会发生什么。",
		"trigger": {"chaos_started": true},
		"min_day": 1.0,
		"choices": [
			{
				"id": "calm_and_prepare",
				"label": "公开记录并组织避险演练（消耗 30 食物，安定 +0.06）",
				"effects": {"resource": {"food": -30.0}, "stability": 0.06},
				"result": "居民知道了该往哪里走，恐慌没有扩散成踩踏。",
			},
			{
				"id": "deny_change",
				"label": "宣称天象只是误读（安定 -0.06，健康 -0.03）",
				"effects": {"stability": -0.06, "health": -0.03},
				"result": "秩序暂时维持，但越来越多的人开始私下收拾行囊。",
			},
		],
	},
]

var pending: Dictionary = {}
var triggered_ids: Array[String] = []
var triggered_days: Dictionary = {}
var last_event_day: float = -1000.0
var history: Array = []


func reset() -> void:
	pending.clear()
	triggered_ids.clear()
	triggered_days.clear()
	last_event_day = -1000.0
	history.clear()


func get_definition(p_event_id: String) -> Dictionary:
	for definition in EVENTS:
		if str(definition.get("id", "")) == p_event_id:
			return definition.duplicate(true)
	return {}


func evaluate(p_context: Dictionary, p_game_day: float) -> bool:
	if not pending.is_empty():
		return false
	if p_game_day - last_event_day < MIN_INTERVAL_DAYS:
		return false
	var context := p_context.duplicate(true)
	context["game_day"] = p_game_day
	var ordered_events: Array = EVENTS.duplicate(true)
	ordered_events.sort_custom(func(a: Dictionary, b: Dictionary):
		return int(a.get("priority", 0)) > int(b.get("priority", 0))
	)
	for definition in ordered_events:
		var event_id := str(definition.get("id", ""))
		var once := bool(definition.get("once", true))
		if once and event_id in triggered_ids:
			continue
		if (
			not once
			and triggered_days.has(event_id)
			and p_game_day - float(triggered_days[event_id]) < float(definition.get("cooldown_days", 90.0))
		):
			continue
		if p_game_day < float(definition.get("min_day", 0.0)):
			continue
		if not _trigger_matches(definition.get("trigger", {}), context):
			continue
		pending = {
			"event_id": event_id,
			"title": definition.get("title", ""),
			"description": definition.get("description", ""),
			"choices": (definition.get("choices", []) as Array).duplicate(true),
			"triggered_day": p_game_day,
		}
		last_event_day = p_game_day
		return true
	return false


func get_pending_view() -> Dictionary:
	return pending.duplicate(true)


func has_pending() -> bool:
	return not pending.is_empty()


func resolve_choice(p_choice_id: String) -> Dictionary:
	if pending.is_empty():
		return {"success": false, "message": "当前没有待决事件"}
	for choice_value in pending.get("choices", []):
		var choice: Dictionary = choice_value
		if str(choice.get("id", "")) == p_choice_id:
			return {
				"success": true,
				"event_id": str(pending.get("event_id", "")),
				"choice": choice.duplicate(true),
			}
	return {"success": false, "message": "该事件没有这个选项"}


func commit_resolution(p_event_id: String, p_choice: Dictionary, p_game_day: float) -> bool:
	if pending.is_empty() or str(pending.get("event_id", "")) != p_event_id:
		return false
	if p_event_id not in triggered_ids:
		triggered_ids.append(p_event_id)
	triggered_days[p_event_id] = p_game_day
	history.append({
		"event_id": p_event_id,
		"title": pending.get("title", ""),
		"choice_id": p_choice.get("id", ""),
		"choice_label": p_choice.get("label", ""),
		"game_day": p_game_day,
	})
	while history.size() > MAX_HISTORY:
		history.pop_front()
	pending.clear()
	return true


func get_state() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"pending": pending.duplicate(true),
		"triggered_ids": triggered_ids.duplicate(),
		"triggered_days": triggered_days.duplicate(),
		"last_event_day": last_event_day,
		"history": history.duplicate(true),
	}


func load_state(p_data: Dictionary) -> bool:
	if (
		int(p_data.get("state_version", -1)) != STATE_VERSION
		or not p_data.get("pending", null) is Dictionary
		or not p_data.get("triggered_ids", null) is Array
		or not p_data.get("history", null) is Array
	):
		return false
	pending = (p_data["pending"] as Dictionary).duplicate(true)
	triggered_ids.assign(p_data["triggered_ids"])
	triggered_days = (p_data.get("triggered_days", {}) as Dictionary).duplicate()
	last_event_day = float(p_data.get("last_event_day", -1000.0))
	history = (p_data["history"] as Array).duplicate(true)
	return true


func _trigger_matches(p_trigger: Dictionary, p_context: Dictionary) -> bool:
	for key in p_trigger:
		var required = p_trigger[key]
		match str(key):
			"food_above":
				if float(p_context.get("food_stock", 0.0)) < float(required):
					return false
			"food_below_days":
				if float(p_context.get("food_days", 999.0)) > float(required):
					return false
			"population_above":
				if int(p_context.get("population", 0)) < int(required):
					return false
			"building_running":
				if str(required) not in (p_context.get("operating_building_types", []) as Array):
					return false
			"zone_temp_below":
				if float(p_context.get("min_populated_temperature", 999.0)) > float(required):
					return false
			"zone_temp_above":
				if float(p_context.get("max_populated_temperature", -999.0)) < float(required):
					return false
			"damaged_buildings_at_least":
				if int(p_context.get("damaged_building_count", 0)) < int(required):
					return false
			"knowledge_advanced_above":
				if int(p_context.get("knowledge_advanced", 0)) < int(required):
					return false
			"teaching_plan_count_below":
				if int(p_context.get("teaching_plan_count", 0)) >= int(required):
					return false
			"power_shortage":
				if bool(p_context.get("power_shortage", false)) != bool(required):
					return false
			"chaos_started":
				if bool(p_context.get("chaos_started", false)) != bool(required):
					return false
			"days_above":
				if float(p_context.get("game_day", 0.0)) < float(required):
					return false
			_:
				return false
	return true


func describe_effects(p_choice: Dictionary) -> String:
	var effects: Dictionary = p_choice.get("effects", {})
	var parts: Array[String] = []
	var resources: Dictionary = effects.get("resource", {})
	for resource_id in resources:
		parts.append("%s %+d" % [
			RESOURCE_NAMES.get(str(resource_id), str(resource_id)),
			int(resources[resource_id]),
		])
	if effects.has("stability"):
		parts.append("安定 %+d%%" % int(round(float(effects["stability"]) * 100.0)))
	if effects.has("health"):
		parts.append("健康 %+d%%" % int(round(float(effects["health"]) * 100.0)))
	if effects.has("population"):
		parts.append("人口 %+d" % int(effects["population"]))
	if effects.has("breeders"):
		parts.append("生育岗位 %+d" % int(effects["breeders"]))
	if effects.has("repair_buildings"):
		parts.append("修复耐久 +%d" % int(effects["repair_buildings"]))
	if effects.has("policy"):
		var policy_names := {"rationing": "定量配给"}
		parts.append("启动政策：%s" % str(policy_names.get(str(effects["policy"]), effects["policy"])))
	if effects.has("power_priority_days"):
		parts.append("电力优先级 %d 天" % int(effects["power_priority_days"]))
	if effects.has("discovery"):
		parts.append("知识线索")
	return "，".join(parts) if not parts.is_empty() else "无直接资源影响"
