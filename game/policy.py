"""政策系统 - 管理文明的大型发展策略"""
from enum import Enum
from typing import List, Tuple

class PolicyState(Enum):
    """当前文明主要形态与政策状态"""
    NORMAL = "normal"
    DEHYDRATED = "dehydrated"      # 全民脱水状态
    BOOMING = "booming"            # 大生育计划


class PolicyManager:
    """政策系统"""

    def __init__(self):
        self.current_state = PolicyState.NORMAL
        # 可以用一个列表记录曾经颁布过的单次特殊政策/里程碑
        self.enacted_policies: List[str] = []

    def set_state(self, state: PolicyState):
        """切换当前的政策状态"""
        self.current_state = state

    def enact_policy(self, policy_name: str, entities) -> Tuple[bool, str]:
        """尝试颁布/执行某一项政策或切换状态"""
        
        if policy_name == "dehydrate":
            if self.current_state == PolicyState.DEHYDRATED:
                return False, "当前已经是脱水状态了"
            self.set_state(PolicyState.DEHYDRATED)
            # Todo: 进行脱水后的实际人口保护、建筑停工等副作用
            return True, "已成功开启全民脱水，渡劫模式启动"
            
        elif policy_name == "rehydrate":
            if self.current_state != PolicyState.DEHYDRATED:
                return False, "目前处于浸泡活跃状态，无需浸泡"
            self.set_state(PolicyState.NORMAL)
            return True, "文明浸泡复苏完成，恢复常规运作"
            
        elif policy_name == "boom":
            # 大生育计划需要消耗粮食
            food_needed = 500
            current_food = entities.get_resource("food")
            if current_food < food_needed:
                return False, f"食物不足，无法开启大生育计划(需求:{food_needed}，当前:{int(current_food)})"
                
            entities.consume_resource("food", food_needed)
            self.set_state(PolicyState.BOOMING)
            return True, "大生育计划已开启，人口增长率上升"

        return False, "未知政策"

    def get_state(self) -> dict:
        """序列化输出状态摘要"""
        return {
            "current_state": self.current_state.value,
            "enacted_policies": self.enacted_policies
        }

    def load_state(self, data: dict):
        """反序列化载入"""
        state_str = data.get("current_state", "normal")
        try:
            self.current_state = PolicyState(state_str)
        except ValueError:
            self.current_state = PolicyState.NORMAL
            
        self.enacted_policies = data.get("enacted_policies", [])
