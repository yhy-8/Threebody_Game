"""三体环境模拟 - 三体运动计算与环境参数输出"""
import numpy as np
from dataclasses import dataclass, field
from typing import List, Tuple


@dataclass
class Star:
    """恒星或行星"""
    mass: float
    position: np.ndarray = field(default_factory=lambda: np.zeros(3))
    velocity: np.ndarray = field(default_factory=lambda: np.zeros(3))
    color: Tuple[int, int, int] = (255, 255, 255)
    radius: float = 20.0
    is_planet: bool = False  # 是否是行星
    trail: List[np.ndarray] = field(default_factory=list)  # 轨迹历史位置


class ThreeBodySimulation:
    """三体运动模拟器"""

    G = 1.0  # 引力常数（简化）
    TRAIL_LENGTH = 60  # 轨迹保留的点数

    def __init__(self):
        self.stars: List[Star] = []
        self.time_scale = 1.0
        self._initialize_stars()

    def _initialize_stars(self):
        """初始化三颗恒星和一颗行星"""
        # 恒星1：橙色主星（类似太阳）
        star1 = Star(
            mass=1000.0,
            position=np.array([0.0, 0.0, 0.0]),
            velocity=np.array([0.0, 0.0, 0.0]),
            color=(255, 200, 100),
            radius=100.0,
            is_planet=False
        )

        # 恒星2：蓝色
        star2 = Star(
            mass=800.0,
            position=np.array([300.0, 0.0, 0.0]),
            velocity=np.array([0.0, 0.0, 1.8]),
            color=(100, 200, 255),
            radius=80.0,
            is_planet=False
        )

        # 恒星3：红色
        star3 = Star(
            mass=600.0,
            position=np.array([-200.0, 0.0, 150.0]),
            velocity=np.array([0.0, 0.0, -1.2]),
            color=(255, 100, 100),
            radius=60.0,
            is_planet=False
        )

        # 行星：蓝色小型天体（类似地球）
        # 行星绕恒星1运行
        planet = Star(
            mass=1.0,
            position=np.array([150.0, 0.0, 0.0]),
            velocity=np.array([0.0, 0.0, 2.5]),
            color=(100, 150, 255),
            radius=2.0,  # 100:2 = 50:1，接近地球太阳比例
            is_planet=True
        )

        self.stars = [star1, star2, star3, planet]

    def compute_forces(self) -> List[np.ndarray]:
        """计算每颗恒星受到的引力"""
        forces = [np.zeros(3) for _ in self.stars]

        for i, star_i in enumerate(self.stars):
            for j, star_j in enumerate(self.stars):
                if i != j:
                    r = star_j.position - star_i.position
                    dist = np.linalg.norm(r)
                    if dist > 1e-6:
                        force = self.G * star_i.mass * star_j.mass * r / (dist ** 3)
                        forces[i] += force

        return forces

    def update(self, dt: float):
        """更新三体运动（使用半隐式欧拉法）"""
        dt = dt * self.time_scale
        forces = self.compute_forces()

        # 更新速度和位置
        for star, force in zip(self.stars, forces):
            # 记录当前位置到轨迹
            star.trail.append(star.position.copy())
            # 限制轨迹长度
            if len(star.trail) > self.TRAIL_LENGTH:
                star.trail.pop(0)

            acceleration = force / star.mass
            star.velocity += acceleration * dt
            star.position += star.velocity * dt

    def get_environment_params(self) -> dict:
        """获取环境参数（光照、热量等）"""
        # 计算各恒星到原点的距离
        distances = [np.linalg.norm(star.position) for star in self.stars]

        # 简化：距离越近，光照和热量越强
        total_intensity = sum(1000.0 / (d + 100) for d in distances)

        return {
            "light_intensity": min(1.0, total_intensity / 3.0),
            "heat_level": min(1.0, total_intensity / 2.5),
            "stability": self._compute_stability(),
        }

    def _compute_stability(self) -> float:
        """计算星系稳定性（基于速度方差）"""
        velocities = np.array([star.velocity for star in self.stars])
        speed = np.linalg.norm(velocities, axis=1)
        # 速度差异越小越稳定
        return 1.0 / (1.0 + np.std(speed))