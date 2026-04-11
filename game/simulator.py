"""游戏模拟器 - 状态更新逻辑"""
from typing import Dict, Any
from .environment import ThreeBodySimulation
from .entities import EntityManager


class GameSimulator:
    """游戏模拟器 - 协调环境和实体更新"""

    def __init__(self):
        self.environment = ThreeBodySimulation()
        self.entities = EntityManager()
        self.time = 0.0
        self.paused = False

    def update(self, dt: float):
        """更新游戏状态"""
        if self.paused:
            return

        # 更新环境
        self.environment.update(dt)

        # 获取环境参数并更新实体
        env_params = self.environment.get_environment_params()
        self.entities.update(env_params)

        self.time += dt

    def get_state(self) -> Dict[str, Any]:
        """获取完整游戏状态"""
        return {
            "time": self.time,
            "paused": self.paused,
            "environment": {
                "stars": [
                    {
                        "position": star.position.tolist(),
                        "velocity": star.velocity.tolist(),
                        "color": star.color,
                        "radius": star.radius,
                        "mass": star.mass,
                        "is_planet": star.is_planet,
                        "trail": [p.tolist() for p in star.trail] if star.trail else []
                    }
                    for star in self.environment.stars
                ],
                "params": self.environment.get_environment_params()
            },
            "entities": self.entities.get_state()
        }

    def toggle_pause(self):
        """切换暂停状态"""
        self.paused = not self.paused

    def set_time_scale(self, scale: float):
        """设置时间流逝速度"""
        self.environment.time_scale = max(0.1, min(10.0, scale))