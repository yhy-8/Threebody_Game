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
        self.game_over = False  # 游戏是否结束

    def reset(self):
        """重置游戏状态 - 用于开始新游戏"""
        self.environment = ThreeBodySimulation()
        self.entities = EntityManager()
        self.time = 0.0
        self.paused = False
        self.game_over = False

    def update(self, dt: float):
        """更新游戏状态"""
        if self.paused or self.game_over:
            return

        # 更新环境
        self.environment.update(dt)

        # 获取环境参数并更新实体
        env_params = self.environment.get_environment_params()
        self.entities.update(env_params)

        self.time += dt * self.environment.time_scale

    def get_state(self) -> Dict[str, Any]:
        """获取完整游戏状态"""
        return {
            "time": self.time,
            "paused": self.paused,
            "game_over": self.game_over,
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

    def to_dict(self) -> Dict[str, Any]:
        """序列化游戏状态 - 用于保存游戏"""
        return {
            "time": self.time,
            "paused": self.paused,
            "game_over": self.game_over,
            "stars": [
                {
                    "mass": star.mass,
                    "position": star.position.tolist(),
                    "velocity": star.velocity.tolist(),
                    "color": list(star.color),
                    "radius": star.radius,
                    "is_planet": star.is_planet,
                }
                for star in self.environment.stars
            ],
            "entities": self.entities.get_state(),
            "time_scale": self.environment.time_scale,
        }

    def from_dict(self, data: Dict[str, Any]):
        """从字典恢复游戏状态 - 用于加载存档"""
        import numpy as np
        from .environment import Star

        self.time = data.get("time", 0.0)
        self.paused = data.get("paused", False)
        self.game_over = data.get("game_over", False)
        self.environment.time_scale = data.get("time_scale", 1.0)

        # 恢复星球状态
        stars_data = data.get("stars", [])
        if stars_data:
            self.environment.stars = []
            for sd in stars_data:
                star = Star(
                    mass=sd["mass"],
                    position=np.array(sd["position"]),
                    velocity=np.array(sd["velocity"]),
                    color=tuple(sd["color"]),
                    radius=sd["radius"],
                    is_planet=sd.get("is_planet", False),
                )
                self.environment.stars.append(star)

    def toggle_pause(self):
        """切换暂停状态"""
        self.paused = not self.paused

    def set_time_scale(self, scale: float):
        """设置时间流逝速度"""
        self.environment.time_scale = max(0.1, min(10.0, scale))