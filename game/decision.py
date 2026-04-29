"""决策系统 - 管理文明的建造和政策选择（原"政策系统"重构）

新版资源体系下，建筑成本和产出使用细分资源类型。
建筑采用 worker_capacity + per_worker_output 模型。
"""
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Dict, Tuple, Optional

from .entities import RESOURCE_DISPLAY_NAMES


class CivilizationState(Enum):
    """当前文明主要形态状态"""
    NORMAL = "normal"
    DEHYDRATED = "dehydrated"      # 全民脱水状态
    BOOMING = "booming"            # 大生育计划


@dataclass
class Decision:
    """一个决策项（可以是建造建筑或执行政策）"""
    id: str
    name: str
    description: str
    category: str              # "construction" | "policy"
    resource_cost: Dict[str, float] = field(default_factory=dict)
    tech_requirement: str = ""  # 所需科技ID（空表示无需求）
    effects: Dict[str, str] = field(default_factory=dict)  # 效果说明
    cooldown: float = 0.0      # 冷却时间（游戏天）
    requires_zone: bool = False  # 是否需要选择区域放置

    # 建造相关 — 人力驱动模型
    building_type: str = ""    # 建造的建筑类型（仅 construction 类）
    worker_capacity: int = 0   # 最大工人容量
    per_worker_output: Dict[str, float] = field(default_factory=dict)  # 每工人产出/天
    consumption: Dict[str, float] = field(default_factory=dict)  # 建筑消耗/天


# ── 预定义的决策列表 ─────────────────────────────────────────────

def _default_decisions() -> Dict[str, Decision]:
    """创建默认决策列表"""
    decisions = {}

    # ═══════════════════ 建筑建造类决策 ═══════════════════════════

    decisions["build_algae_collector"] = Decision(
        id="build_algae_collector",
        name="建造藻类采集场",
        description="采集行星原生藻类，干燥后作为初级燃料。",
        category="construction",
        resource_cost={"iron": 20},
        tech_requirement="",
        requires_zone=True,
        building_type="algae_collector",
        worker_capacity=5,
        per_worker_output={"algae_fuel": 3.0},
        consumption={},
        effects={"algae_fuel": "最多+15/天(满5人)"},
    )

    decisions["build_algae_food_synth"] = Decision(
        id="build_algae_food_synth",
        name="建造藻类食物合成器",
        description="将原生藻类合成为基础可食用维生物质，解决早期食物短缺危机。",
        category="construction",
        resource_cost={"iron": 25},
        tech_requirement="",
        requires_zone=True,
        building_type="algae_food_synth",
        worker_capacity=5,
        per_worker_output={"food": 2.5},
        consumption={},
        effects={"food": "最多+12.5/天(满5人)"},
    )

    decisions["build_iron_mine"] = Decision(
        id="build_iron_mine",
        name="建造铁矿场",
        description="在指定区域开采铁矿石，基础建筑材料。",
        category="construction",
        resource_cost={"iron": 30},
        tech_requirement="",
        requires_zone=True,
        building_type="iron_mine",
        worker_capacity=5,
        per_worker_output={"iron": 2.0},
        consumption={},
        effects={"iron": "最多+10/天(满5人)"},
    )

    decisions["build_copper_mine"] = Decision(
        id="build_copper_mine",
        name="建造铜矿场",
        description="开采铜矿，用于制造电气设备和高级设施。",
        category="construction",
        resource_cost={"iron": 40, "copper": 10},
        tech_requirement="basic_metallurgy",
        requires_zone=True,
        building_type="copper_mine",
        worker_capacity=5,
        per_worker_output={"copper": 1.5},
        consumption={},
        effects={"copper": "最多+7.5/天(满5人)"},
    )

    decisions["build_rare_mine"] = Decision(
        id="build_rare_mine",
        name="建造稀有矿场",
        description="开采稀有矿物，用于高级科技和建筑。",
        category="construction",
        resource_cost={"iron": 60, "copper": 20},
        tech_requirement="basic_metallurgy",
        requires_zone=True,
        building_type="rare_mine",
        worker_capacity=3,
        per_worker_output={"rare_mineral": 0.5},
        consumption={},
        effects={"rare_mineral": "最多+1.5/天(满3人)"},
    )

    decisions["build_farm"] = Decision(
        id="build_farm",
        name="建造农场",
        description="在指定区域建造一座农场，持续产出食物。",
        category="construction",
        resource_cost={"iron": 50},
        tech_requirement="basic_agriculture",
        requires_zone=True,
        building_type="farm",
        worker_capacity=8,
        per_worker_output={"food": 3.0},
        consumption={},
        effects={"food": "最多+24/天(满8人)"},
    )

    decisions["build_fossil_mine"] = Decision(
        id="build_fossil_mine",
        name="建造化石燃料矿井",
        description="开采地下化石燃料沉积层。",
        category="construction",
        resource_cost={"iron": 80, "copper": 20},
        tech_requirement="fossil_fuel_extraction",
        requires_zone=True,
        building_type="fossil_mine",
        worker_capacity=5,
        per_worker_output={"fossil_fuel": 4.0},
        consumption={},
        effects={"fossil_fuel": "最多+20/天(满5人)"},
    )

    decisions["build_algae_power"] = Decision(
        id="build_algae_power",
        name="建造藻类燃烧发电站",
        description="燃烧干燥藻类发电，初级电力来源。",
        category="construction",
        resource_cost={"iron": 60, "copper": 15},
        tech_requirement="basic_electrification",
        requires_zone=True,
        building_type="algae_power_plant",
        worker_capacity=3,
        per_worker_output={"electricity": 5.0},
        consumption={"algae_fuel": 3.0},
        effects={"electricity": "最多+15kW(满3人)", "algae_fuel": "-3/天"},
    )

    decisions["build_fossil_power"] = Decision(
        id="build_fossil_power",
        name="建造化石燃料发电站",
        description="大规模化石燃料发电设施，中级电力来源。",
        category="construction",
        resource_cost={"iron": 120, "copper": 40},
        tech_requirement="power_plant",
        requires_zone=True,
        building_type="fossil_power_plant",
        worker_capacity=3,
        per_worker_output={"electricity": 15.0},
        consumption={"fossil_fuel": 5.0},
        effects={"electricity": "最多+45kW(满3人)", "fossil_fuel": "-5/天"},
    )

    decisions["build_shelter"] = Decision(
        id="build_shelter",
        name="建造庇护所",
        description="保护居民免受极端环境伤害的地下工事。",
        category="construction",
        resource_cost={"iron": 100},
        tech_requirement="survival_shelter",
        requires_zone=True,
        building_type="shelter",
        worker_capacity=0,  # 无需工人
        per_worker_output={},
        consumption={"electricity": 1.0},
        effects={"zone_protection": "+20%", "electricity": "-1kW/天"},
    )

    decisions["build_laboratory"] = Decision(
        id="build_laboratory",
        name="建造实验室",
        description="科学研究设施，产出应用科研点。消耗可观的电力。",
        category="construction",
        resource_cost={"iron": 200, "copper": 80},
        tech_requirement="laboratory",
        requires_zone=True,
        building_type="laboratory",
        worker_capacity=5,
        per_worker_output={},  # 科研点由特殊逻辑产出
        consumption={"electricity": 8.0},
        effects={"applied_research": "+2/天(满员)", "electricity": "-8kW/天"},
    )

    decisions["build_academy"] = Decision(
        id="build_academy",
        name="建造科学院",
        description="最高级别的科研机构，产出理论科研点。极度耗电。",
        category="construction",
        resource_cost={"iron": 800, "copper": 200, "rare_mineral": 50},
        tech_requirement="academy",
        requires_zone=True,
        building_type="academy",
        worker_capacity=8,
        per_worker_output={},
        consumption={"electricity": 25.0, "food": 5.0},
        effects={"theoretical_research": "+1/天(满员)", "electricity": "-25kW/天", "food": "-5/天"},
    )

    decisions["build_deep_shelter"] = Decision(
        id="build_deep_shelter",
        name="建造深地庇护所",
        description="深入地下的巨型避难系统，可容纳大量人口。",
        category="construction",
        resource_cost={"iron": 300, "copper": 60},
        tech_requirement="deep_shelter",
        requires_zone=True,
        building_type="deep_shelter",
        worker_capacity=0,
        per_worker_output={},
        consumption={"electricity": 3.0},
        effects={"zone_protection": "+50%", "electricity": "-3kW/天"},
    )

    decisions["build_radiation_shield"] = Decision(
        id="build_radiation_shield",
        name="建造辐射屏蔽站",
        description="为所在区域提供辐射防护。",
        category="construction",
        resource_cost={"iron": 250, "copper": 50, "rare_mineral": 20},
        tech_requirement="radiation_armor",
        requires_zone=True,
        building_type="radiation_shield",
        worker_capacity=0,
        per_worker_output={},
        consumption={"electricity": 5.0},
        effects={"radiation_resistance": "+50%", "electricity": "-5kW/天"},
    )

    # ═══════════════════ 文明政策类决策 ═══════════════════════════

    decisions["dehydrate"] = Decision(
        id="dehydrate",
        name="全民脱水",
        description="应对极端恶劣环境，大部分建筑停工。资源消耗大幅降低。",
        category="policy",
        resource_cost={},
        effects={"civilization": "进入脱水状态", "consumption": "-80%", "production": "-90%"},
    )

    decisions["rehydrate"] = Decision(
        id="rehydrate",
        name="浸泡复苏",
        description="文明重新激活，恢复正常的建设与繁衍。",
        category="policy",
        resource_cost={},
        effects={"civilization": "恢复正常状态"},
    )

    decisions["boom"] = Decision(
        id="boom",
        name="大生育计划",
        description="在恒纪元中快速增加人口。需要消耗大量食物。",
        category="policy",
        resource_cost={"food": 500},
        effects={"population_growth": "+200%", "food": "-500"},
    )

    decisions["rationing"] = Decision(
        id="rationing",
        name="配给制",
        description="食物消耗减半，但社会安定度和效率大幅下降。",
        category="policy",
        resource_cost={},
        effects={"food_consumption": "-50%", "efficiency": "-30%", "stability": "-20%"},
    )

    decisions["forced_labor"] = Decision(
        id="forced_labor",
        name="工业强心剂",
        description="强制劳动，暂时大幅提高产出，但严重损害人口健康。",
        category="policy",
        resource_cost={},
        effects={"production": "+150%", "health": "-30%", "stability": "-25%"},
    )

    return decisions


class DecisionManager:
    """决策管理器 - 管理建筑建造和政策执行"""

    def __init__(self):
        self.current_state = CivilizationState.NORMAL
        self.available_decisions: Dict[str, Decision] = _default_decisions()
        self.active_policies: List[str] = []   # 当前生效的政策ID列表
        self.cooldowns: Dict[str, float] = {}  # 决策冷却计时器
        self.enacted_history: List[str] = []   # 历史记录

        # 建筑ID计数器
        self._next_building_id: int = 1

    def get_next_building_id(self) -> int:
        """获取下一个建筑ID"""
        bid = self._next_building_id
        self._next_building_id += 1
        return bid

    def get_construction_decisions(self) -> List[Decision]:
        """获取所有建筑建造类决策"""
        return [d for d in self.available_decisions.values() if d.category == "construction"]

    def get_policy_decisions(self) -> List[Decision]:
        """获取所有政策类决策"""
        return [d for d in self.available_decisions.values() if d.category == "policy"]

    def can_execute(self, decision_id: str, entities, tech_tree=None) -> Tuple[bool, str]:
        """检查某个决策是否可以执行"""
        decision = self.available_decisions.get(decision_id)
        if not decision:
            return False, "未知的决策"

        # 检查冷却时间
        if decision_id in self.cooldowns and self.cooldowns[decision_id] > 0:
            remaining = self.cooldowns[decision_id]
            return False, f"冷却中（剩余 {remaining:.0f} 天）"

        # 检查科技需求
        if decision.tech_requirement and tech_tree:
            if not tech_tree.is_unlocked(decision.tech_requirement):
                tech_node = tech_tree.get_node(decision.tech_requirement)
                tech_name = tech_node.name if tech_node else decision.tech_requirement
                return False, f"需要先研发科技「{tech_name}」"

        # 检查资源
        for res_name, cost in decision.resource_cost.items():
            current = entities.get_resource(res_name)
            display = RESOURCE_DISPLAY_NAMES.get(res_name, res_name)
            if current < cost:
                return False, f"资源「{display}」不足（需求：{int(cost)}，当前：{int(current)}）"

        # 政策类的特殊检查
        if decision.category == "policy":
            return self._check_policy_conditions(decision_id)

        return True, ""

    def _check_policy_conditions(self, policy_id: str) -> Tuple[bool, str]:
        """检查政策的特殊前提条件"""
        if policy_id == "dehydrate":
            if self.current_state == CivilizationState.DEHYDRATED:
                return False, "当前已经是脱水状态"
        elif policy_id == "rehydrate":
            if self.current_state != CivilizationState.DEHYDRATED:
                return False, "目前不在脱水状态，无需浸泡"
        elif policy_id == "boom":
            if self.current_state == CivilizationState.DEHYDRATED:
                return False, "脱水状态下无法执行生育计划"

        return True, ""

    def execute_decision(self, decision_id: str, entities, tech_tree=None,
                         zone_manager=None, zone_id: int = -1) -> Tuple[bool, str, Optional[int]]:
        """执行决策

        Returns: (success, message, building_id_or_none)
        """
        can, reason = self.can_execute(decision_id, entities, tech_tree)
        if not can:
            return False, reason, None

        decision = self.available_decisions[decision_id]

        # 扣除资源
        for res_name, cost in decision.resource_cost.items():
            entities.consume_resource(res_name, cost)

        # 设置冷却
        if decision.cooldown > 0:
            self.cooldowns[decision_id] = decision.cooldown

        # 记录历史
        self.enacted_history.append(decision_id)

        if decision.category == "construction":
            return self._execute_construction(decision, entities, zone_manager, zone_id)
        elif decision.category == "policy":
            return self._execute_policy(decision_id, entities)

        return False, "未知决策类型", None

    def _execute_construction(self, decision: Decision, entities,
                              zone_manager, zone_id: int) -> Tuple[bool, str, Optional[int]]:
        """执行建筑建造"""
        from .entities import Building

        if decision.requires_zone and zone_id < 0:
            return False, "需要选择一个建造区域", None

        building_id = self.get_next_building_id()

        building = Building(
            id=building_id,
            name=decision.name.replace("建造", ""),
            building_type=decision.building_type,
            zone_id=zone_id if decision.requires_zone else -1,
            worker_capacity=decision.worker_capacity,
            per_worker_output=dict(decision.per_worker_output),
            consumption=dict(decision.consumption),
        )

        entities.add_building(building)

        # 在区域管理器中注册
        if zone_manager and decision.requires_zone and zone_id >= 0:
            zone_manager.add_building_to_zone(zone_id, building_id)

        zone_info = f"（区域 {zone_id}）" if zone_id >= 0 else ""
        worker_info = f"，需分配最多{decision.worker_capacity}名工人" if decision.worker_capacity > 0 else ""
        return True, f"已建造 {building.name}{zone_info}{worker_info}", building_id

    def _execute_policy(self, policy_id: str, entities) -> Tuple[bool, str, None]:
        """执行政策"""
        if policy_id == "dehydrate":
            self.current_state = CivilizationState.DEHYDRATED
            return True, "已成功开启全民脱水，渡劫模式启动", None
        elif policy_id == "rehydrate":
            self.current_state = CivilizationState.NORMAL
            return True, "文明浸泡复苏完成，恢复常规运作", None
        elif policy_id == "boom":
            self.current_state = CivilizationState.BOOMING
            return True, "大生育计划已开启，人口增长率上升", None
        elif policy_id == "rationing":
            if "rationing" not in self.active_policies:
                self.active_policies.append("rationing")
            return True, "配给制已生效", None
        elif policy_id == "forced_labor":
            if "forced_labor" not in self.active_policies:
                self.active_policies.append("forced_labor")
            return True, "工业强心剂已注入", None

        return False, "未知政策", None

    def update_cooldowns(self, dt: float, time_scale: float):
        """更新冷却计时器"""
        game_days = dt * time_scale
        expired = []
        for did, remaining in self.cooldowns.items():
            self.cooldowns[did] = remaining - game_days
            if self.cooldowns[did] <= 0:
                expired.append(did)
        for did in expired:
            del self.cooldowns[did]

    def get_state(self) -> dict:
        """序列化输出状态"""
        return {
            "current_state": self.current_state.value,
            "active_policies": list(self.active_policies),
            "cooldowns": dict(self.cooldowns),
            "enacted_history": list(self.enacted_history),
            "next_building_id": self._next_building_id,
        }

    def load_state(self, data: dict):
        """反序列化载入"""
        state_str = data.get("current_state", "normal")
        try:
            self.current_state = CivilizationState(state_str)
        except ValueError:
            self.current_state = CivilizationState.NORMAL

        self.active_policies = data.get("active_policies", [])
        self.cooldowns = data.get("cooldowns", {})
        self.enacted_history = data.get("enacted_history", [])
        self._next_building_id = data.get("next_building_id", 1)
