"""科技系统 - 提供科技树管理"""
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple


@dataclass
class TechNode:
    """科技节点"""
    id: str                 # 唯一标识符，如 "telescope"
    name: str               # 显示名称，如 "望远镜"
    description: str        # 描述
    cost: int               # 研究所需基础消耗（例如科学点数或通用进度）
    requirements: dict      # 研究所需环境或资源前提条件（例如 {"population": 100}）
    prerequisites: List[str]= field(default_factory=list) # 前置科技ID
    unlocked: bool = False  # 是否已解锁


class TechTree:
    """科技树管理器"""

    def __init__(self):
        self.nodes: Dict[str, TechNode] = {}
        self._init_default_techs()

    def _init_default_techs(self):
        """初始化默认科技树节点"""
        self.add_node(
            TechNode(
                id="telescope",
                name="望远镜",
                description="能初步观测星空，解锁星图功能的基本模块。",
                cost=100,
                requirements={"population": 50},
                prerequisites=[]
            )
        )
        self.add_node(
            TechNode(
                id="computer",
                name="计算机技术",
                description="强大的计算能力，解锁星体轨道的初步预测与数值分析。",
                cost=300,
                requirements={"population": 200},
                prerequisites=["telescope"]
            )
        )
        self.add_node(
            TechNode(
                id="survival_shelter",
                name="维生庇护所",
                description="能让部分人口度过恶劣的极寒或高温期。",
                cost=150,
                requirements={"population": 100},
                prerequisites=[]
            )
        )

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

    def can_unlock(self, node_id: str, entities_state: dict) -> Tuple[bool, str]:
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
                return False, "前置科技尚未研发完成"

        # 检查人口等资源（实体状态）要求
        # current population
        current_pop = entities_state.get("people_count", 0)
        required_pop = node.requirements.get("population", 0)
        if current_pop < required_pop:
            return False, f"人口不足（需求：{required_pop}，当前：{current_pop}）"
            
        # 其他要求目前根据需要扩展
        
        return True, ""

    def unlock_tech(self, node_id: str):
        """解锁科技（忽略各项检查，由上层先调can_unlock确保）"""
        node = self.nodes.get(node_id)
        if node:
            node.unlocked = True

    def get_state(self) -> dict:
        """获取当前科技树状态摘录"""
        return {
            "unlocked": [k for k, v in self.nodes.items() if v.unlocked]
        }

    def load_state(self, unlocked_nodes: List[str]):
        """载入科技状态"""
        for node_id in unlocked_nodes:
            if node_id in self.nodes:
                self.nodes[node_id].unlocked = True
