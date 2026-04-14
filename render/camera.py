"""摄像机系统 - 3D投影核心"""
import numpy as np
import math
from typing import Tuple, Optional


class Camera:
    """3D摄像机，支持旋转、平移、缩放"""

    def __init__(
        self,
        position: Tuple[float, float, float] = (0, 0, -500),
        rotation: Tuple[float, float] = (0, 0),
        fov: float = 500
    ):
        self.position = np.array(list(position), dtype=float)
        self.rotation = list(rotation)  # [yaw, pitch]
        self.fov = fov
        self.speed = 5

    @property
    def yaw(self) -> float:
        return self.rotation[0]

    @yaw.setter
    def yaw(self, value: float):
        self.rotation[0] = value

    @property
    def pitch(self) -> float:
        return self.rotation[1]

    @pitch.setter
    def pitch(self, value: float):
        self.rotation[1] = max(-1.5, min(1.5, value))

    def rotate(self, dx: float, dy: float):
        """鼠标拖拽旋转视角"""
        self.yaw += dx * 0.005
        self.pitch += dy * 0.005

    def get_forward_vector(self) -> np.ndarray:
        """获取相机朝向的前方向量（世界坐标）- 指向摄像机前方"""
        # world_to_screen 中的变换: rotate_x(rotate_y(world_point - pos, yaw), pitch)
        # 相机空间的前方是 (0,0,1) (camera_z > 0 = 在前方)
        # 要得到世界坐标的前方向量，需要取逆变换:
        # world_forward = rotate_y(-yaw, rotate_x(-pitch, (0,0,1)))
        point = np.array([0.0, 0.0, 1.0])
        point = self._rotate_x(point, -self.pitch)
        point = self._rotate_y(point, -self.yaw)
        return point

    def get_right_vector(self) -> np.ndarray:
        """获取相机右侧方向向量（世界坐标）"""
        # 相机空间的右方是 (1,0,0)
        point = np.array([1.0, 0.0, 0.0])
        point = self._rotate_x(point, -self.pitch)
        point = self._rotate_y(point, -self.yaw)
        return point

    def get_up_vector(self) -> np.ndarray:
        """获取相机上方方向向量（世界坐标）"""
        # 相机空间中 -Y 对应屏幕上方（因为screen_y = h/2 + y * scale）
        # 但移动时 +Y 世界坐标 = 向上移动相机（场景下移），符合直觉
        # 所以使用 (0,-1,0) 作为相机空间的"上"方向
        point = np.array([0.0, -1.0, 0.0])
        point = self._rotate_x(point, -self.pitch)
        point = self._rotate_y(point, -self.yaw)
        return point

    def move(self, forward: float = 0, right: float = 0, up: float = 0):
        """WASD/方向键移动 - 沿视角方向"""
        forward_vec = self.get_forward_vector()
        right_vec = self.get_right_vector()
        up_vec = self.get_up_vector()

        # 确保position是float类型
        self.position = self.position.astype(np.float64)
        self.position = self.position + forward * forward_vec
        self.position = self.position + right * right_vec
        self.position = self.position + up * up_vec

    def zoom(self, delta: int):
        """滚轮缩放 - 向视角方向前进/后退"""
        forward_vec = self.get_forward_vector()
        # delta > 0 是向前滚（向朝向方向移动），delta < 0 是向后滚
        # 注意：滚轮向上滚是delta=1，向下滚是delta=-1
        move_amount = delta * 30  # 调整移动速度
        # 确保position是float类型
        self.position = self.position.astype(np.float64)
        self.position = self.position + forward_vec * move_amount

    def world_to_screen(
        self,
        x: float,
        y: float,
        z: float,
        screen_size: Tuple[int, int]
    ) -> Optional[Tuple[int, int]]:
        """3D世界坐标 → 2D屏幕坐标"""
        point = np.array([x, y, z], dtype=float)

        # 1. 平移到摄像机空间
        point = point - self.position

        # 2. 旋转变换（先绕Y轴旋转，再绕X轴旋转）
        point = self._rotate_y(point, self.yaw)
        point = self._rotate_x(point, self.pitch)

        # 3. 透视投影 - 使用摄像机空间中的实际深度
        camera_z = point[2]
        if camera_z <= 0:
            return None  # 点在摄像机后方或处于摄像机位置

        scale = self.fov / camera_z

        # 4. 映射到屏幕
        screen_x = int(screen_size[0] / 2 + point[0] * scale)
        screen_y = int(screen_size[1] / 2 + point[1] * scale)

        return (screen_x, screen_y)

    def get_camera_z(self, x: float, y: float, z: float) -> float:
        """获取世界坐标点在摄像机空间中的深度"""
        point = np.array([x, y, z], dtype=float)
        point = point - self.position
        point = self._rotate_y(point, self.yaw)
        point = self._rotate_x(point, self.pitch)
        return point[2]

    def _rotate_y(self, point: np.ndarray, angle: float) -> np.ndarray:
        """绕Y轴旋转（水平视角）"""
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        return np.array([
            point[0] * cos_a + point[2] * sin_a,
            point[1],
            -point[0] * sin_a + point[2] * cos_a
        ])

    def _rotate_x(self, point: np.ndarray, angle: float) -> np.ndarray:
        """绕X轴旋转（垂直视角）"""
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        return np.array([
            point[0],
            point[1] * cos_a - point[2] * sin_a,
            point[1] * sin_a + point[2] * cos_a
        ])

    def get_scale(self, x: float, y: float, z: float) -> float:
        """获取指定世界坐标点的缩放比例"""
        camera_z = self.get_camera_z(x, y, z)
        if camera_z <= 0:
            return 0
        return self.fov / camera_z

    def check_collision(self, stars: list) -> bool:
        """检测星球之间是否发生碰撞（行星撞入恒星）"""
        for i, star_a in enumerate(stars):
            for j, star_b in enumerate(stars):
                if i >= j:
                    continue
                # 只检测涉及行星的碰撞（行星撞恒星 或 恒星撞行星）
                if not star_a.get("is_planet", False) and not star_b.get("is_planet", False):
                    continue
                pos_a = np.array(star_a["position"])
                pos_b = np.array(star_b["position"])
                dist = np.linalg.norm(pos_a - pos_b)
                # 碰撞阈值为两个星球半径之和
                collision_dist = star_a["radius"] + star_b["radius"]
                if dist < collision_dist:
                    return True
        return False