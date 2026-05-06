"""科技系统 - 提供科技树管理，支持多种科技点数和树形依赖结构"""
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

from .entities import RESOURCE_DISPLAY_NAMES


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
    researching: bool = False  # 是否正在研究中

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

    def __init__(self, config: dict = None):
        self.nodes: Dict[str, TechNode] = {}
        # 科技点数池
        self.research_points: Dict[str, float] = {
            RESEARCH_BASIC: 0.0,
            RESEARCH_APPLIED: 0.0,
            RESEARCH_THEORETICAL: 0.0,
        }
        # 当前正在研究的科技ID（一次只能研究一个）
        self.researching_tech_id: Optional[str] = None
        # 当前研究已投入的各类科技点数 {point_type: accumulated}
        self.research_progress: Dict[str, float] = {}
        self._config = config or {}
        self._init_default_techs(config)

    def _init_default_techs(self, config: dict = None):
        """初始化完整的科技树 — 优先从 config["technology"] 读取，否则使用硬编码默认值"""
        tech_config = (config or {}).get("technology", {})

        if tech_config:
            for tech_id, tdata in tech_config.items():
                self.add_node(TechNode(
                    id=tech_id,
                    name=tdata.get("name", tech_id),
                    description=tdata.get("description", ""),
                    effect_description=tdata.get("effect_description", ""),
                    research_cost=tdata.get("research_cost", {}),
                    resource_cost=tdata.get("resource_cost", {}),
                    requirements=tdata.get("requirements", {}),
                    prerequisites=tdata.get("prerequisites", []),
                    tier=tdata.get("tier", 0),
                    column=tdata.get("column", 0),
                    category=tdata.get("category", "basic"),
                ))
            return

        # 硬编码默认科技树（config缺失时使用）

        # ═══════════════════ Tier 0：起始科技（无前置）═══════════════
        self.add_node(TechNode(
            id="telescope",
            name="望远镜",
            description="基础光学设备，能初步观测星空。",
            effect_description="解锁星图功能，可观测三体恒星运动。",
            research_cost={RESEARCH_BASIC: 80},
            resource_cost={"iron": 50},
            requirements={"population": 50},
            tier=0, column=0, category="basic",
        ))
        self.add_node(TechNode(
            id="survival_shelter",
            name="维生庇护所",
            description="基础的地下掩体设计，提供临时保护。",
            effect_description="允许建造庇护所，降低极端环境下人口损失。",
            research_cost={RESEARCH_BASIC: 60},
            resource_cost={"iron": 80},
            requirements={"population": 30},
            tier=0, column=1, category="basic",
        ))
        self.add_node(TechNode(
            id="basic_metallurgy",
            name="基础冶金",
            description="掌握金属冶炼的基本工艺。",
            effect_description="解锁铜矿和稀有矿物的开采，以及实验室建造。",
            research_cost={RESEARCH_BASIC: 100},
            resource_cost={"iron": 100},
            requirements={"population": 60},
            tier=0, column=2, category="basic",
        ))
        self.add_node(TechNode(
            id="basic_agriculture",
            name="基础农业",
            description="系统化的农作物种植技术。",
            effect_description="解锁农场建造，提高食物产出。",
            research_cost={RESEARCH_BASIC: 50},
            resource_cost={"iron": 30},
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
            resource_cost={"iron": 150, "copper": 50},
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
            resource_cost={"iron": 100, "copper": 50},
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
            resource_cost={"iron": 400, "copper": 100},
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
            resource_cost={"iron": 200, "copper": 80},
            requirements={"population": 120},
            prerequisites=["basic_metallurgy"],
            tier=1, column=3, category="applied",
        ))
        self.add_node(TechNode(
            id="basic_electrification",
            name="基础电气化",
            description="掌握电力的产生和使用。",
            effect_description="解锁藻类发电站，开始使用电力网络。",
            research_cost={RESEARCH_BASIC: 100},
            resource_cost={"iron": 150, "copper": 50},
            requirements={"population": 80},
            prerequisites=["basic_metallurgy"],
            tier=1, column=4, category="basic",
        ))
        self.add_node(TechNode(
            id="fossil_fuel_extraction",
            name="化石燃料开采",
            description="从地底提取高能量的化石燃料。",
            effect_description="解锁化石燃料矿井。",
            research_cost={RESEARCH_BASIC: 120},
            resource_cost={"iron": 120, "copper": 30},
            requirements={"population": 100},
            prerequisites=["basic_metallurgy"],
            tier=1, column=5, category="basic",
        ))


        # ═══════════════════ Tier 2：中级科技 ═══════════════════════
        self.add_node(TechNode(
            id="power_plant",
            name="火力发电站",
            description="大规模化石燃料电力生产设施。",
            effect_description="解锁火力发电站建造，提供稳定的大量电力。",
            research_cost={RESEARCH_APPLIED: 140},
            resource_cost={"iron": 200, "copper": 100},
            requirements={"population": 150},
            prerequisites=["basic_electrification", "fossil_fuel_extraction"],
            tier=2, column=0, category="basic",
        ))
        self.add_node(TechNode(
            id="chaos_prediction",
            name="混沌预测模型",
            description="基于非线性动力学的三体运动预测。",
            effect_description="星图中显示三体未来数十天的运动轨迹预测。",
            research_cost={RESEARCH_APPLIED: 200, RESEARCH_THEORETICAL: 50},
            resource_cost={"algae_fuel": 300},
            requirements={"population": 300},
            prerequisites=["computer"],
            tier=2, column=1, category="theoretical",
        ))
        self.add_node(TechNode(
            id="automation",
            name="自动化控制",
            description="机器替代人工的生产控制系统。",
            effect_description="所有建筑产出效率+30% (提升全局自动化倍率)。",
            research_cost={RESEARCH_APPLIED: 150},
            resource_cost={"iron": 200, "copper": 150},
            requirements={"population": 200},
            prerequisites=["computer", "basic_electrification"],
            tier=2, column=2, category="applied",
        ))
        self.add_node(TechNode(
            id="radiation_armor",
            name="防辐射装甲",
            description="高密度辐射屏蔽材料。",
            effect_description="建筑辐射抗性+50%。",
            research_cost={RESEARCH_APPLIED: 100, RESEARCH_BASIC: 80},
            resource_cost={"iron": 300, "rare_mineral": 20},
            requirements={"population": 150},
            prerequisites=["deep_shelter"],
            tier=2, column=3, category="applied",
        ))
        self.add_node(TechNode(
            id="applied_physics",
            name="应用物理",
            description="系统化的物理工程学研究。",
            effect_description="解锁高级建筑研究分支。",
            research_cost={RESEARCH_APPLIED: 200},
            resource_cost={"rare_mineral": 30},
            requirements={"population": 250},
            prerequisites=["laboratory"],
            tier=2, column=4, category="applied",
        ))
        self.add_node(TechNode(
            id="material_science",
            name="材料科学",
            description="微观结构与材料性能研究。",
            effect_description="解锁高强度合金，建筑耐久度+50%。",
            research_cost={RESEARCH_APPLIED: 180},
            resource_cost={"iron": 300, "copper": 100},
            requirements={"population": 200},
            prerequisites=["laboratory"],
            tier=2, column=5, category="applied",
        ))

        # ═══════════════════ Tier 3：高级科技 ═══════════════════════
        self.add_node(TechNode(
            id="academy",
            name="科学院",
            description="最高等级的科研机构，汇聚顶尖科学家。",
            effect_description="解锁科学院建造，产出理论科研点。消耗大量电力。",
            research_cost={RESEARCH_APPLIED: 300, RESEARCH_THEORETICAL: 100},
            resource_cost={"iron": 1500, "copper": 500, "rare_mineral": 100},
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
            resource_cost={"iron": 800, "copper": 200, "rare_mineral": 50},
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
            resource_cost={"iron": 3000, "copper": 1000, "rare_mineral": 500},
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
        """产出科技点数（由研究建筑调用）
        
        如果有正在研究的科技且需要该类型点数，优先注入研究进度，
        剩余部分才进入点数池。
        """
        if point_type not in self.research_points:
            return

        remaining = amount

        # 如果有正在研究的科技，优先注入
        if self.researching_tech_id:
            node = self.nodes.get(self.researching_tech_id)
            if node and node.researching:
                needed = node.research_cost.get(point_type, 0)
                already = self.research_progress.get(point_type, 0.0)
                gap = max(0.0, needed - already)
                if gap > 0 and remaining > 0:
                    inject = min(remaining, gap)
                    self.research_progress[point_type] = already + inject
                    remaining -= inject

                    # 检查是否所有类型的需求都已满足
                    self._check_research_completion()

        # 剩余进入点数池
        if remaining > 0:
            self.research_points[point_type] += remaining

    def can_start_research(self, node_id: str, entities) -> Tuple[bool, str]:
        """判定目标科技是否可以开始研究
        
        检查：前置科技、资源消耗、人口要求。
        不检查科技点数（点数在研究过程中逐渐投入）。
        """
        node = self.nodes.get(node_id)
        if not node:
            return False, "找不到该科技节点"

        if node.unlocked:
            return False, "该科技已经解锁完毕"

        if node.researching:
            return False, "该科技正在研究中"

        if self.researching_tech_id:
            current = self.nodes.get(self.researching_tech_id)
            current_name = current.name if current else self.researching_tech_id
            return False, f"正在研究「{current_name}」，一次只能研究一个科技"

        # 检查前置科技
        for pre_id in node.prerequisites:
            pre_node = self.nodes.get(pre_id)
            if not pre_node or not pre_node.unlocked:
                pre_name = pre_node.name if pre_node else pre_id
                return False, f"前置科技「{pre_name}」尚未研发完成"

        # 检查资源消耗（只检查是否足够，不扣除）
        for res_name, required in node.resource_cost.items():
            current_amt = entities.get_resource(res_name)
            if current_amt < required:
                display_name = RESOURCE_DISPLAY_NAMES.get(res_name, res_name)
                return False, f"资源「{display_name}」不足（需求：{required}，当前：{int(current_amt)}）"

        # 检查人口等前提条件
        for req_res, req_amt in node.requirements.items():
            current_amt = entities.get_resource(req_res)
            if current_amt < req_amt:
                display_name = RESOURCE_DISPLAY_NAMES.get(req_res, req_res)
                return False, f"{display_name}不足（最低要求：{int(req_amt)}，当前：{int(current_amt)}）"

        return True, ""

    def can_unlock(self, node_id: str, entities) -> Tuple[bool, str]:
        """判定目标科技是否满足解锁条件（保留用于向后兼容）"""
        can, reason = self.can_start_research(node_id, entities)
        if not can:
            return False, reason
        # 额外检查科技点数是否足够（立即解锁模式）
        node = self.nodes.get(node_id)
        for rtype, required in node.research_cost.items():
            current = self.research_points.get(rtype, 0)
            if current < required:
                type_name = RESEARCH_NAMES.get(rtype, rtype)
                return False, f"{type_name}点数不足（需求：{required}，当前：{int(current)}）"
        return True, ""

    def start_research(self, node_id: str, entities) -> Tuple[bool, str]:
        """开始研究科技
        
        立即扣除物质资源（iron, copper等），但不扣除科技点数。
        科技点数在研究过程中由科技建筑逐渐注入。
        """
        can, reason = self.can_start_research(node_id, entities)
        if not can:
            return False, reason

        node = self.nodes.get(node_id)

        # 扣除资源
        for res_name, cost in node.resource_cost.items():
            entities.consume_resource(res_name, cost)

        # 设置研究状态
        node.researching = True
        self.researching_tech_id = node_id
        self.research_progress = {rtype: 0.0 for rtype in node.research_cost}

        return True, f"开始研究「{node.name}」"

    def cancel_research(self) -> Tuple[bool, str]:
        """取消当前研究
        
        已投入的科技点数退回到点数池，但物质资源不退回。
        """
        if not self.researching_tech_id:
            return False, "当前没有正在进行的研究"

        node = self.nodes.get(self.researching_tech_id)
        if not node:
            self.researching_tech_id = None
            self.research_progress.clear()
            return False, "研究节点不存在"

        # 退回已投入的科技点数
        for rtype, amount in self.research_progress.items():
            if amount > 0 and rtype in self.research_points:
                self.research_points[rtype] += amount

        name = node.name
        node.researching = False
        self.researching_tech_id = None
        self.research_progress.clear()

        return True, f"已取消研究「{name}」，科技点数已退回"

    def _check_research_completion(self):
        """检查当前研究是否已完成"""
        if not self.researching_tech_id:
            return

        node = self.nodes.get(self.researching_tech_id)
        if not node:
            return

        # 检查所有类型的需求是否已满足
        for rtype, required in node.research_cost.items():
            accumulated = self.research_progress.get(rtype, 0.0)
            if accumulated < required:
                return  # 还没完成

        # 所有需求满足，完成研究
        self._complete_research(node)

    def _complete_research(self, node: TechNode):
        """完成研究，解锁科技"""
        node.unlocked = True
        node.researching = False
        self.researching_tech_id = None
        self.research_progress.clear()

        # 如果解锁了自动化科技，提升全局自动化倍率
        # （需要通过 entities 设置，这里仅标记，由 simulator 处理）

    def unlock_tech(self, node_id: str, entities):
        """立即解锁科技（向后兼容，扣除科技点数和资源）"""
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
        node.researching = False

        # 如果解锁了自动化科技，提升全局自动化倍率
        if node_id == "automation":
            entities.population.automation_multiplier += 0.3

    def get_research_progress(self) -> Optional[Dict]:
        """获取当前研究进度信息
        
        Returns:
            None 如果没有进行中的研究，否则返回:
            {
                'tech_id': str,
                'tech_name': str,
                'progress': {point_type: (current, required)},
                'overall_percent': float  # 0.0 ~ 1.0
            }
        """
        if not self.researching_tech_id:
            return None

        node = self.nodes.get(self.researching_tech_id)
        if not node:
            return None

        progress = {}
        total_current = 0.0
        total_required = 0.0
        for rtype, required in node.research_cost.items():
            current = self.research_progress.get(rtype, 0.0)
            progress[rtype] = (current, float(required))
            total_current += current
            total_required += required

        overall = total_current / max(total_required, 0.001)

        return {
            'tech_id': self.researching_tech_id,
            'tech_name': node.name,
            'progress': progress,
            'overall_percent': min(1.0, overall),
        }

    def is_researching(self, node_id: str) -> bool:
        """检查指定科技是否正在研究中"""
        return self.researching_tech_id == node_id

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
        """判断科技是否可被研发（前置已解锁，自身未解锁且未在研究中）"""
        node = self.nodes.get(node_id)
        if not node or node.unlocked or node.researching:
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
            "researching": [k for k, v in self.nodes.items() if v.researching],
            "research_points": dict(self.research_points),
            "researching_tech_id": self.researching_tech_id,
            "research_progress": dict(self.research_progress),
        }

    def load_state(self, data: dict):
        """载入科技状态"""
        if isinstance(data, dict):
            unlocked_nodes = data.get("unlocked", [])
            researching_nodes = data.get("researching", [])
            points = data.get("research_points", {})
        elif isinstance(data, list):
            # 向后兼容旧版只保存unlocked列表的格式
            unlocked_nodes = data
            researching_nodes = []
            points = {}
        else:
            return

        for node_id in unlocked_nodes:
            if node_id in self.nodes:
                self.nodes[node_id].unlocked = True

        for node_id in researching_nodes:
            if node_id in self.nodes:
                self.nodes[node_id].researching = True

        for rtype, amount in points.items():
            if rtype in self.research_points:
                self.research_points[rtype] = amount

        # 恢复研究进度
        self.researching_tech_id = data.get("researching_tech_id", None)
        self.research_progress = data.get("research_progress", {})
