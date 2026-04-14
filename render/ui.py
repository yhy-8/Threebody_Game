"""2D UI系统"""
import pygame
import sys
import os
import math
from typing import List, Tuple, Optional, Callable


# 跨平台字体加载
def get_font(size: int) -> pygame.font.Font:
    """获取支持中文的字体，兼容Linux和Windows"""
    # 中文字体候选列表
    font_candidates = [
        # Linux - 修正路径
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-microhei/wqy-microhei.ttc",
        "/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc",
        # Windows
        "C:/Windows/Fonts/msyh.ttc",       # 微软雅黑
        "C:/Windows/Fonts/simhei.ttf",     # 黑体
        "C:/Windows/Fonts/simsun.ttc",     # 宋体
        # 通用
        "simhei",
        "simsun",
        "microsoftyahei",
    ]

    # 先尝试文件路径
    for font_path in font_candidates:
        if os.path.exists(font_path):
            try:
                return pygame.font.Font(font_path, size)
            except:
                continue

    # 使用系统字体名
    for font_name in font_candidates[-4:]:
        try:
            return pygame.font.Font(font_name, size)
        except:
            continue

    # 最后使用默认字体（可能不支持中文）
    return pygame.font.Font(None, size)


class UIElement:
    """UI基类"""

    def __init__(self, x: int, y: int, width: int, height: int):
        self.rect = pygame.Rect(x, y, width, height)
        self.visible = True

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件，返回是否被点击"""
        return False

    def render(self, screen: pygame.Surface):
        pass


class Button(UIElement):
    """按钮"""

    def __init__(
        self,
        x: int, y: int,
        text: str,
        width: int = 120,
        height: int = 40,
        callback: Optional[Callable] = None
    ):
        super().__init__(x, y, width, height)
        self.text = text
        self.callback = callback
        self.hovered = False
        self.clicked = False
        self.font = get_font(28)

    def handle_event(self, event: pygame.event.Event) -> bool:
        if not self.visible:
            return False

        if event.type == pygame.MOUSEMOTION:
            self.hovered = self.rect.collidepoint(event.pos)
        elif event.type == pygame.MOUSEBUTTONDOWN:
            if self.rect.collidepoint(event.pos):
                self.clicked = True
                return True
        elif event.type == pygame.MOUSEBUTTONUP:
            if self.clicked and self.rect.collidepoint(event.pos):
                if self.callback:
                    self.callback()
            self.clicked = False
        return False

    def render(self, screen: pygame.Surface):
        if not self.visible:
            return

        # 背景色
        if self.clicked:
            bg_color = (100, 100, 150)
        elif self.hovered:
            bg_color = (80, 80, 120)
        else:
            bg_color = (60, 60, 100)

        pygame.draw.rect(screen, bg_color, self.rect, border_radius=5)
        pygame.draw.rect(screen, (150, 150, 200), self.rect, 2, border_radius=5)

        # 文字
        text_surf = self.font.render(self.text, True, (255, 255, 255))
        text_rect = text_surf.get_rect(center=self.rect.center)
        screen.blit(text_surf, text_rect)


class Label(UIElement):
    """文本标签"""

    def __init__(self, x: int, y: int, text: str, font_size: int = 24, color: Tuple[int, int, int] = (255, 255, 255)):
        super().__init__(x, y, 0, 0)
        self.text = text
        self.color = color
        self.font = get_font(font_size)

    def set_text(self, text: str):
        self.text = text

    def render(self, screen: pygame.Surface):
        if not self.visible:
            return
        text_surf = self.font.render(self.text, True, self.color)
        screen.blit(text_surf, (self.rect.x, self.rect.y))


class Panel(UIElement):
    """面板容器"""

    def __init__(self, x: int, y: int, width: int, height: int, title: str = ""):
        super().__init__(x, y, width, height)
        self.title = title
        self._elements: List[UIElement] = []  # 私有避免属性冲突
        self.bg_color = (30, 30, 50, 180)
        self.border_color = (80, 80, 120)

    @property
    def elements(self):
        return self._elements

    @elements.setter
    def elements(self, value):
        self._elements = value

    def add(self, element: UIElement):
        self.elements.append(element)

    def handle_event(self, event: pygame.event.Event) -> bool:
        for element in self.elements:
            if element.handle_event(event):
                return True
        return False

    def render(self, screen: pygame.Surface):
        if not self.visible:
            return

        # 半透明背景
        s = pygame.Surface((self.rect.width, self.rect.height))
        s.set_alpha(180)
        s.fill(self.bg_color[:3])
        screen.blit(s, (self.rect.x, self.rect.y))

        # 边框
        pygame.draw.rect(screen, self.border_color, self.rect, 2)

        # 标题
        if self.title:
            font = get_font(32)
            title_surf = font.render(self.title, True, (200, 200, 255))
            screen.blit(title_surf, (self.rect.x + 10, self.rect.y + 5))

        # 渲染子元素（需要加上Panel的偏移量）
        for element in self.elements:
            # 临时调整元素位置到Panel内部
            orig_x, orig_y = element.rect.x, element.rect.y
            element.rect.x += self.rect.x
            element.rect.y += self.rect.y
            element.render(screen)
            # 恢复原位置
            element.rect.x = orig_x
            element.rect.y = orig_y


class Compass(UIElement):
    """罗盘/视角指示器 - 宇宙版"""

    def __init__(self, x: int, y: int, size: int = 140):
        super().__init__(x, y, size, size + 50)
        self.size = size
        self.font = get_font(16)
        self.font_small = get_font(13)

    def update_camera(self, camera):
        """更新摄像机数据"""
        self.camera = camera

    def render(self, screen: pygame.Surface):
        if not self.visible:
            return

        cx = self.rect.x + self.size // 2
        cy = self.rect.y + self.size // 2
        radius = self.size // 2 - 8

        # 半透明背景
        s = pygame.Surface((self.size, self.size + 50), pygame.SRCALPHA)
        s.fill((0, 0, 0, 120))
        screen.blit(s, (self.rect.x, self.rect.y))

        # 外圈 - 深蓝渐变边框
        pygame.draw.circle(screen, (40, 60, 90), (cx, cy), radius, 3)
        pygame.draw.circle(screen, (80, 120, 180), (cx, cy), radius - 3, 1)

        # 绘制方向
        if hasattr(self, 'camera'):
            yaw = self.camera.yaw
            pitch = self.camera.pitch
            pos = self.camera.position

            # 归一化角度到 0-360
            yaw_deg = math.degrees(yaw) % 360
            pitch_deg = math.degrees(pitch)

            # 绘制十字准星
            pygame.draw.line(screen, (60, 80, 120), (cx - radius + 10, cy), (cx + radius - 10, cy), 1)
            pygame.draw.line(screen, (60, 80, 120), (cx, cy - radius + 10), (cx, cy + radius - 10), 1)

            # 前方箭头（主方向）
            arrow_len = radius - 15
            end_x = cx + int(math.sin(yaw) * arrow_len)
            end_y = cy - int(math.cos(yaw) * arrow_len * math.cos(pitch))

            # 箭头连线
            pygame.draw.line(screen, (255, 120, 80), (cx, cy), (end_x, end_y), 3)
            # 箭头头部
            pygame.draw.circle(screen, (255, 150, 100), (end_x, end_y), 5)

            # 相对方向标签 (F=前, B=后, L=左, R=右)
            rel_directions = [
                ("F", 0),
                ("R", -math.pi/2),
                ("B", math.pi),
                ("L", math.pi/2)
            ]
            for label, base_angle in rel_directions:
                # 计算相对角度
                rel_angle = base_angle - yaw
                lx = cx + int(math.sin(rel_angle) * (radius - 8))
                ly = cy - int(math.cos(rel_angle) * (radius - 8))
                color = (255, 200, 150) if abs(rel_angle) < 0.3 else (140, 160, 180)
                text = self.font.render(label, True, color)
                text_rect = text.get_rect(center=(lx, ly))
                screen.blit(text, text_rect)

            # 底部信息面板
            info_y = self.rect.y + self.size + 5

            # 角度信息
            angle_text = f"YAW:{int(yaw_deg):03d}°  PITCH:{int(pitch_deg):02d}°"
            text_surf = self.font_small.render(angle_text, True, (180, 200, 220))
            screen.blit(text_surf, (self.rect.x + 10, info_y))

            # 位置信息
            pos_text = f"POS:{int(pos[0]):+5d} {int(pos[1]):+5d} {int(pos[2]):+5d}"
            pos_surf = self.font_small.render(pos_text, True, (140, 180, 200))
            screen.blit(pos_surf, (self.rect.x + 10, info_y + 18))

            # 深度指示
            depth = abs(pos[2])
            depth_text = f"DEPTH:{int(depth):d}"
            depth_surf = self.font_small.render(depth_text, True, (120, 160, 180))
            screen.blit(depth_surf, (self.rect.x + 10, info_y + 36))


class UIManager:
    """UI管理器"""

    def __init__(self):
        self.elements: List[UIElement] = []
        self.panels: List[Panel] = []
        self.compass: Optional[Compass] = None

    def add_element(self, element: UIElement):
        self.elements.append(element)

    def add_panel(self, panel: Panel):
        self.panels.append(panel)
        self.elements.append(panel)

    def set_compass(self, compass: Compass):
        """设置罗盘"""
        self.compass = compass
        self.elements.append(compass)

    def handle_event(self, event: pygame.event.Event):
        for element in self.elements:
            element.handle_event(event)

    def render(self, screen: pygame.Surface):
        for element in self.elements:
            element.render(screen)


def update_hud(ui_manager: UIManager, state: dict, camera=None):
    """更新HUD数据而不重新创建UI元素"""
    if not ui_manager.panels:
        return

    # 更新顶部面板 - 时间
    if len(ui_manager.panels) > 0 and hasattr(ui_manager.panels[0], 'elements'):
        panel = ui_manager.panels[0]
        if len(panel.elements) >= 4:
            panel.elements[0].set_text(f"时间: {state.get('time', 0):.1f}")
            env = state.get("environment", {}).get("params", {})
            panel.elements[1].set_text(f"光照: {env.get('light_intensity', 0):.2f}")
            panel.elements[2].set_text(f"热量: {env.get('heat_level', 0):.2f}")
            panel.elements[3].set_text(f"稳定性: {env.get('stability', 0):.2f}")

    # 更新底部面板 - 实体状态
    if len(ui_manager.panels) > 1 and hasattr(ui_manager.panels[1], 'elements'):
        panel2 = ui_manager.panels[1]
        entities = state.get("entities", {})
        if len(panel2.elements) >= 3:
            panel2.elements[0].set_text(f"人口: {entities.get('people_count', 0)}")
            panel2.elements[1].set_text(f"建筑: {entities.get('buildings_count', 0)}")
            panel2.elements[2].set_text(f"效率: {entities.get('avg_efficiency', 0):.2f}")

    # 更新罗盘
    if camera and ui_manager.compass:
        ui_manager.compass.update_camera(camera)


def create_hud(state: dict, width: int, height: int, camera=None) -> UIManager:
    """创建HUD（平视显示器）"""
    ui = UIManager()

    # 根据窗口大小缩放
    scale = min(width / 1280, height / 720)
    panel_w = max(200, int(320 * scale))
    panel_h = max(140, int(200 * scale))
    label_size = max(16, int(24 * scale))
    line_gap = max(22, int(30 * scale))

    # 顶部信息面板（避开星图顶部按钮区域，按钮高约40px + 间距）
    top_margin = max(60, int(70 * scale))
    panel = Panel(10, top_margin, panel_w, panel_h, "三体文明")
    ui.add_panel(panel)

    # 时间显示
    y = 45
    time_label = Label(20, y, f"时间: {state.get('time', 0):.1f}", label_size)
    panel.add(time_label)

    # 环境参数
    env = state.get("environment", {}).get("params", {})
    y += line_gap
    light_label = Label(20, y, f"光照: {env.get('light_intensity', 0):.2f}", label_size)
    y += line_gap
    heat_label = Label(20, y, f"热量: {env.get('heat_level', 0):.2f}", label_size)
    y += line_gap
    stability_label = Label(20, y, f"稳定性: {env.get('stability', 0):.2f}", label_size)
    panel.add(light_label)
    panel.add(heat_label)
    panel.add(stability_label)

    # 底部实体状态面板
    entities = state.get("entities", {})
    panel2_h = max(100, int(140 * scale))
    panel2_w = max(180, int(280 * scale))
    panel2 = Panel(10, height - panel2_h - 20, panel2_w, panel2_h, "文明状态")
    ui.add_panel(panel2)

    y = 45
    people_label = Label(20, y, f"人口: {entities.get('people_count', 0)}", label_size)
    y += line_gap
    buildings_label = Label(20, y, f"建筑: {entities.get('buildings_count', 0)}", label_size)
    y += line_gap
    efficiency_label = Label(20, y, f"效率: {entities.get('avg_efficiency', 0):.2f}", label_size)
    panel2.add(people_label)
    panel2.add(buildings_label)
    panel2.add(efficiency_label)

    # 添加罗盘（右上角）- 根据窗口大小缩放，避开帮助按钮
    compass_size = max(60, int(80 * scale))
    compass = Compass(width - compass_size - 10, top_margin, compass_size)
    if camera:
        compass.update_camera(camera)
    ui.set_compass(compass)

    return ui