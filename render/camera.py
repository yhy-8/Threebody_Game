"""摄像机系统 - 3D投影核心"""
import numpy as np
import math
from typing import Tuple, Optional


class Camera:
    """3D摄像机，支持旋转、平移、缩放，以及行星锁定轨道模式"""

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
        
        # 增加设置支持
        self.sensitivity = 1.0
        self.invert_y = False
        
        # 引入最小投影深度限制以防止除以零或无穷大溢出导致的卡顿
        self.min_z = 1.0

        # ── 行星锁定轨道模式 ──
        self.locked_target: Optional[np.ndarray] = None  # 锁定目标的世界坐标
        self.orbit_distance: float = 200.0               # 相机到目标的距离
        self.orbit_yaw: float = 0.0                      # 水平环绕角 (弧度)
        self.orbit_pitch: float = 0.3                     # 垂直俯仰角 (弧度)
        self.orbit_distance_min: float = 20.0
        self.orbit_distance_max: float = 2000.0

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
        dy_sign = -1 if self.invert_y else 1
        self.yaw += dx * 0.005 * self.sensitivity
        self.pitch += dy * 0.005 * dy_sign * self.sensitivity

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

    # ── 行星锁定轨道相机方法 ──

    def set_lock_target(self, position: Optional[np.ndarray]):
        """设定或清除锁定目标。设定时根据当前相机位置初始化轨道参数。"""
        if position is None:
            self.locked_target = None
            return

        self.locked_target = np.array(position, dtype=float)

        # 根据当前相机位置计算初始轨道参数
        offset = self.position - self.locked_target
        self.orbit_distance = float(np.linalg.norm(offset))
        self.orbit_distance = max(self.orbit_distance_min,
                                  min(self.orbit_distance_max, self.orbit_distance))

        # 从偏移向量反算球坐标角度
        horiz_dist = math.sqrt(offset[0] ** 2 + offset[2] ** 2)
        self.orbit_yaw = math.atan2(offset[0], offset[2])
        self.orbit_pitch = math.atan2(offset[1], horiz_dist) if horiz_dist > 1e-6 else 0.0
        self.orbit_pitch = max(-math.pi / 2 + 0.05, min(math.pi / 2 - 0.05, self.orbit_pitch))

    def orbit_rotate(self, dx: float, dy: float):
        """鼠标拖拽时环绕目标旋转视角"""
        dy_sign = -1 if self.invert_y else 1
        self.orbit_yaw += dx * 0.005 * self.sensitivity
        self.orbit_pitch += dy * 0.005 * dy_sign * self.sensitivity
        # 限制俯仰角（避免翻转到正上/正下方万向锁）
        self.orbit_pitch = max(-math.pi / 2 + 0.05, min(math.pi / 2 - 0.05, self.orbit_pitch))

    def orbit_zoom(self, delta: float):
        """调整轨道距离（正值拉近，负值拉远）"""
        # 使用指数缩放让近距离时步进小、远距离时步进大，手感自然
        factor = 1 - delta * 0.08
        self.orbit_distance *= factor
        self.orbit_distance = max(self.orbit_distance_min,
                                  min(self.orbit_distance_max, self.orbit_distance))

    def update_orbit(self, target_position: np.ndarray):
        """根据锁定目标的最新位置和球坐标，更新相机位置和朝向。每帧调用。"""
        self.locked_target = np.array(target_position, dtype=float)

        # 球坐标 → 笛卡尔坐标偏移
        cos_p = math.cos(self.orbit_pitch)
        offset = np.array([
            self.orbit_distance * cos_p * math.sin(self.orbit_yaw),
            self.orbit_distance * math.sin(self.orbit_pitch),
            self.orbit_distance * cos_p * math.cos(self.orbit_yaw),
        ])

        self.position = self.locked_target + offset

        # 让相机朝向目标：计算需要的 yaw / pitch
        to_target = self.locked_target - self.position  # 指向目标的向量
        horiz_dist = math.sqrt(to_target[0] ** 2 + to_target[2] ** 2)
        self.rotation[0] = math.atan2(to_target[0], to_target[2])  # yaw
        self.rotation[1] = -math.atan2(to_target[1], horiz_dist) if horiz_dist > 1e-6 else 0.0

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
        if camera_z < self.min_z:
            return None  # 点在摄像机后方或距离过近
            
        scale = self.fov / camera_z
        
        # 4. 映射到屏幕
        screen_x = int(screen_size[0] / 2 + point[0] * scale)
        screen_y = int(screen_size[1] / 2 + point[1] * scale)
        
        # 增加超出合理范围（非常大导致溢出的）点排除
        if abs(screen_x) > screen_size[0] + 2000 or abs(screen_y) > screen_size[1] + 2000:
            return None

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
        if camera_z < self.min_z:
            return 0
        return self.fov / camera_z

    def check_collision(self, stars: list) -> bool:
        """检测星球之间是否发生碰撞（所有的星体间）"""
        for i, star_a in enumerate(stars):
            for j, star_b in enumerate(stars):
                if i >= j:
                    continue
                
                # 获取位置并检查距离
                pos_a = np.array(star_a["position"])
                pos_b = np.array(star_b["position"])
                dist = np.linalg.norm(pos_a - pos_b)
                # 碰撞阈值为两个星球半径之和
                collision_dist = star_a["radius"] + star_b["radius"]
                if dist < collision_dist:
                    return True
        return False