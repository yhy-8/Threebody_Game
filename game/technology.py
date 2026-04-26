"""科技系统 - 提供科技树管理，支持多种科技点数和树形依赖结构"""
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple


@dataclass
class TechNode:
    """科技节点"""
    id: str                   # 唯一标识符
    name: str                 # 显示名称
    description: str          # 描述
    effect_description: str   # 解锁后的效果说明

    # 科技点数需求（三种类型）
    research_cost: Dict[str, int] = field(default_factory=dict)
    # 实际资源消耗
    resource_cost: Dict[str, int] = field(default_factory=dict)
    # 环境或资源最低前提条件（如人口下限）
    requirements: Dict[str, float] = field(default_factory=dict)
    # 前置科技ID列表
    prerequisites: List[str] = field(default_factory=list)

    unlocked: bool = False

    # 科技树布局信息
    tier: int = 0             # 层级（从左到右：0=最左）
    column: int = 0           # 列（同层级内的上下位置，0=最上）
    category: str = "basic"   # 分类: basic / applied / theoretical


# ── 科技点数类型常量 ──────────────────────────────────────────────
RESEARCH_BASIC = "basic"           # 基础科研点：人口自然产生
RESEARCH_APPLIED = "applied"       # 应用科研点：需要实验室
RESEARCH_THEORETICAL = "theoretical"  # 理论科研点：需要科学院

RESEARCH_TYPES = [RESEARCH_BASIC, RESEARCH_APPLIED, RESEARCH_THEORETICAL]
RESEARCH_NAMES = {
    RESEARCH_BASIC: "基础科研",
    RESEARCH_APPLIED: "应用科研",
    RESEARCH_THEORETICAL: "理论科研",
}
RESEARCH_COLORS = {
    RESEARCH_BASIC: (120, 200, 255),
    RESEARCH_APPLIED: (255, 200, 100),
    RESEARCH_THEORETICAL: (200, 120, 255),
}


class TechTree:
    """科技树管理器

    科技树采用分层树形结构：
    - tier 0: 起始科技（无前置）
    - tier 1: 基础扩展
    - tier 2: 中级科技
    - tier 3: 高级科技
    - tier 4: 终极科技

    科技点数由研究建筑产出：
    - 基础科研点: 人口自然产出 (少量)
    - 应用科研点: 需要「实验室」建筑 + 电力消耗
    - 理论科研点: 需要「科学院」建筑 + 大量电力消耗
    """

    def __init__(self):
        self.nodes: Dict[str, TechNode] = {}
        # 科技点数池
        self.research_points: Dict[str, float] = {
            RESEARCH_BASIC: 0.0,
            RESEARCH_APPLIED: 0.0,
            RESEARCH_THEORETICAL: 0.0,
        }
        self._init_default_techs()

    def _init_default_techs(self):
        """初始化完整的科技树"""

        # ═══════════════════ Tier 0：起始科技（无前置）═══════════════
        self.add_node(TechNode(
            id="telescope",
            name="望远镜",
            description="基础光学设备，能初步观测星空。",
            effect_description="解锁星图功能，可观测三体恒星运动。",
            research_cost={RESEARCH_BASIC: 80},
            resource_cost={"minerals": 50},
            requirements={"population": 50},
            tier=0, column=0, category="basic",
        ))
        self.add_node(TechNode(
            id="survival_shelter",
            name="维生庇护所",
            description="基础的地下掩体设计，提供临时保护。",
            effect_description="允许建造庇护所，降低极端环境下人口损失。",
            research_cost={RESEARCH_BASIC: 60},
            resource_cost={"minerals": 80},
            requirements={"population": 30},
            tier=0, column=1, category="basic",
        ))
        self.add_node(TechNode(
            id="basic_metallurgy",
            name="基础冶金",
            description="掌握金属冶炼的基本工艺。",
            effect_description="解锁实验室和发电站的建造。",
            research_cost={RESEARCH_BASIC: 100},
            resource_cost={"minerals": 100},
            requirements={"population": 60},
            tier=0, column=2, category="basic",
        ))
        self.add_node(TechNode(
            id="basic_agriculture",
            name="基础农业",
            description="系统化的农作物种植技术。",
            effect_description="解锁农场建造，提高食物产出。",
            research_cost={RESEARCH_BASIC: 50},
            resource_cost={"minerals": 30},
            requirements={"population": 20},
            tier=0, column=3, category="basic",
        ))

        # ═══════════════════ Tier 1：基础扩展 ═══════════════════════
        self.add_node(TechNode(
            id="computer",
            name="计算机技术",
            description="强大的计算能力，能进行复杂数值分析。",
            effect_description="解锁轨道预测功能。",
            research_cost={RESEARCH_BASIC: 200, RESEARCH_APPLIED: 50},
            resource_cost={"minerals": 200, "energy": 100},
            requirements={"population": 200},
            prerequisites=["telescope"],
            tier=1, column=0, category="applied",
        ))
        self.add_node(TechNode(
            id="observatory",
            name="天文观测站",
            description="系统化的星空观测设施。",
            effect_description="增强星图精度，显示恒星质量和轨道参数。",
            research_cost={RESEARCH_BASIC: 150},
            resource_cost={"minerals": 150, "energy": 50},
            requirements={"population": 100},
            prerequisites=["telescope"],
            tier=1, column=1, category="basic",
        ))
        self.add_node(TechNode(
            id="deep_shelter",
            name="深地庇护所",
            description="深入地下的大型避难工程。",
            effect_description="建筑防护等级+2，极端环境下保护更多人口。",
            research_cost={RESEARCH_BASIC: 120, RESEARCH_APPLIED: 30},
            resource_cost={"minerals": 500, "energy": 200},
            requirements={"population": 150},
            prerequisites=["survival_shelter"],
            tier=1, column=2, category="applied",
        ))
        self.add_node(TechNode(
            id="laboratory",
            name="实验室",
            description="系统化的科学研究设施。",
            effect_description="解锁实验室建造，产出应用科研点。",
            research_cost={RESEARCH_BASIC: 180},
            resource_cost={"minerals": 300, "energy": 150},
            requirements={"population": 120},
            prerequisites=["basic_metallurgy"],
            tier=1, column=3, category="applied",
        ))
        self.add_node(TechNode(
            id="power_plant",
            name="发电站",
            description="大规模电力生产设施。",
            effect_description="解锁发电站建造，提供稳定电力。",
            research_cost={RESEARCH_BASIC: 140},
            resource_cost={"minerals": 250, "energy": 50},
            requirements={"population": 100},
            prerequisites=["basic_metallurgy"],
            tier=1, column=4, category="basic",
        ))

        # ═══════════════════ Tier 2：中级科技 ═══════════════════════
        self.add_node(TechNode(
            id="chaos_prediction",
            name="混沌预测模型",
            description="基于非线性动力学的三体运动预测。",
            effect_description="星图中显示三体未来数十天的运动轨迹预测。",
            research_cost={RESEARCH_APPLIED: 200, RESEARCH_THEORETICAL: 50},
            resource_cost={"energy": 500},
            requirements={"population": 300},
            prerequisites=["computer"],
            tier=2, column=0, category="theoretical",
        ))
        self.add_node(TechNode(
            id="automation",
            name="自动化控制",
            description="机器替代人工的生产控制系统。",
            effect_description="所有建筑产出效率+30%。",
            research_cost={RESEARCH_APPLIED: 150},
            resource_cost={"minerals": 300, "energy": 200},
            requirements={"population": 200},
            prerequisites=["computer"],
            tier=2, column=1, category="applied",
        ))
        self.add_node(TechNode(
            id="radiation_armor",
            name="防辐射装甲",
            description="高密度辐射屏蔽材料。",
            effect_description="建筑辐射抗性+50%。",
            research_cost={RESEARCH_APPLIED: 100, RESEARCH_BASIC: 80},
            resource_cost={"minerals": 400},
            requirements={"population": 150},
            prerequisites=["deep_shelter"],
            tier=2, column=2, category="applied",
        ))
        self.add_node(TechNode(
            id="applied_physics",
            name="应用物理",
            description="系统化的物理工程学研究。",
            effect_description="解锁高级建筑研究分支。",
            research_cost={RESEARCH_APPLIED: 200},
            resource_cost={"energy": 300},
            requirements={"population": 250},
            prerequisites=["laboratory"],
            tier=2, column=3, category="applied",
        ))
        self.add_node(TechNode(
            id="material_science",
            name="材料科学",
            description="微观结构与材料性能研究。",
            effect_description="解锁高强度合金，建筑耐久度+50%。",
            research_cost={RESEARCH_APPLIED: 180},
            resource_cost={"minerals": 350, "energy": 150},
            requirements={"population": 200},
            prerequisites=["laboratory"],
            tier=2, column=4, category="applied",
        ))

        # ═══════════════════ Tier 3：高级科技 ═══════════════════════
        self.add_node(TechNode(
            id="academy",
            name="科学院",
            description="最高等级的科研机构，汇聚顶尖科学家。",
            effect_description="解锁科学院建造，产出理论科研点。消耗大量电力。",
            research_cost={RESEARCH_APPLIED: 300, RESEARCH_THEORETICAL: 100},
            resource_cost={"minerals": 2000, "energy": 1000, "food": 500},
            requirements={"population": 500},
            prerequisites=["applied_physics", "power_plant"],
            tier=3, column=0, category="theoretical",
        ))
        self.add_node(TechNode(
            id="high_alloy",
            name="高强度合金",
            description="极端条件下仍保持结构完整性的特种合金。",
            effect_description="所有建筑耐久度上限翻倍，热/辐射抗性+30%。",
            research_cost={RESEARCH_APPLIED: 250},
            resource_cost={"minerals": 800, "energy": 400},
            requirements={"population": 300},
            prerequisites=["material_science"],
            tier=3, column=1, category="applied",
        ))

        # ═══════════════════ Tier 4：终极科技 ═══════════════════════
        self.add_node(TechNode(
            id="nuclear_fusion",
            name="可控核聚变",
            description="人造恒星级别的能量来源。",
            effect_description="解锁聚变反应堆，提供近乎无限的清洁能源。",
            research_cost={RESEARCH_THEORETICAL: 500, RESEARCH_APPLIED: 300},
            resource_cost={"minerals": 5000, "energy": 3000},
            requirements={"population": 800},
            prerequisites=["academy"],
            tier=4, column=0, category="theoretical",
        ))

    def add_node(self, node: TechNode):
        self.nodes[node.id] = node

    def get_node(self, node_id: str) -> Optional[TechNode]:
        return self.nodes.get(node_id)

    def is_unlocked(self, node_id: str) -> bool:
        """检查特定科技是否已经解锁"""
        node = self.nodes.get(node_id)
        if node:
            return node.unlocked
        return False

    def produce_research(self, point_type: str, amount: float):
        """产出科技点数（由研究建筑调用）"""
        if point_type in self.research_points:
            self.research_points[point_type] += amount

    def can_unlock(self, node_id: str, entities) -> Tuple[bool, str]:
        """判定目标科技是否满足解锁条件，返回(布尔值，不满足条件时的原因)"""
        node = self.nodes.get(node_id)
        if not node:
            return False, "找不到该科技节点"

        if node.unlocked:
            return False, "该科技已经解锁完毕"

        # 检查前置科技
        for pre_id in node.prerequisites:
            pre_node = self.nodes.get(pre_id)
            if not pre_node or not pre_node.unlocked:
                pre_name = pre_node.name if pre_node else pre_id
                return False, f"前置科技「{pre_name}」尚未研发完成"

        # 检查科技点数
        for rtype, required in node.research_cost.items():
            current = self.research_points.get(rtype, 0)
            if current < required:
                type_name = RESEARCH_NAMES.get(rtype, rtype)
                return False, f"{type_name}点数不足（需求：{required}，当前：{int(current)}）"

        # 检查资源消耗（只检查是否足够，不扣除）
        res_name_map = {
            "population": "人口", "energy": "能源",
            "food": "食物", "minerals": "矿物"
        }
        for res_name, required in node.resource_cost.items():
            current_amt = entities.get_resource(res_name)
            if current_amt < required:
                display_name = res_name_map.get(res_name, res_name)
                return False, f"资源「{display_name}」不足（需求：{required}，当前：{int(current_amt)}）"

        # 检查人口等前提条件
        for req_res, req_amt in node.requirements.items():
            current_amt = entities.get_resource(req_res)
            if current_amt < req_amt:
                display_name = res_name_map.get(req_res, req_res)
                return False, f"{display_name}不足（最低要求：{int(req_amt)}，当前：{int(current_amt)}）"

        return True, ""

    def unlock_tech(self, node_id: str, entities):
        """解锁科技（扣除科技点数和资源，由上层先调can_unlock确保可行）"""
        node = self.nodes.get(node_id)
        if not node:
            return

        # 扣除科技点数
        for rtype, cost in node.research_cost.items():
            if rtype in self.research_points:
                self.research_points[rtype] -= cost

        # 扣除资源
        for res_name, cost in node.resource_cost.items():
            entities.consume_resource(res_name, cost)

        node.unlocked = True

    def get_prerequisites_for(self, node_id: str) -> List[str]:
        """获取某科技的前置科技ID列表"""
        node = self.nodes.get(node_id)
        return node.prerequisites if node else []

    def get_dependents_of(self, node_id: str) -> List[str]:
        """获取依赖于某科技的所有后续科技ID列表"""
        deps = []
        for nid, node in self.nodes.items():
            if node_id in node.prerequisites:
                deps.append(nid)
        return deps

    def is_researchable(self, node_id: str) -> bool:
        """判断科技是否可被研发（前置已解锁，自身未解锁）"""
        node = self.nodes.get(node_id)
        if not node or node.unlocked:
            return False
        for pre_id in node.prerequisites:
            pre = self.nodes.get(pre_id)
            if not pre or not pre.unlocked:
                return False
        return True

    def get_max_tier(self) -> int:
        """获取最大层级"""
        if not self.nodes:
            return 0
        return max(n.tier for n in self.nodes.values())

    def get_nodes_by_tier(self, tier: int) -> List[TechNode]:
        """获取指定层级的所有节点（按column排序）"""
        nodes = [n for n in self.nodes.values() if n.tier == tier]
        nodes.sort(key=lambda n: n.column)
        return nodes

    def get_state(self) -> dict:
        """获取当前科技树状态摘录"""
        return {
            "unlocked": [k for k, v in self.nodes.items() if v.unlocked],
            "research_points": dict(self.research_points),
        }

    def load_state(self, data: dict):
        """载入科技状态"""
        if isinstance(data, dict):
            unlocked_nodes = data.get("unlocked", [])
            points = data.get("research_points", {})
        elif isinstance(data, list):
            # 向后兼容旧版只保存unlocked列表的格式
            unlocked_nodes = data
            points = {}
        else:
            return

        for node_id in unlocked_nodes:
            if node_id in self.nodes:
                self.nodes[node_id].unlocked = True

        for rtype, amount in points.items():
            if rtype in self.research_points:
                self.research_points[rtype] = amount
