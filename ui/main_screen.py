"""主游戏界面 - 2D主游戏画面"""

import pygame
import random
from typing import Optional, List

from .screen_manager import Screen, ScreenType
from .initial_menu import MenuButton
from render.ui import get_font, Panel, Label


class MainScreen(Screen):
    """2D主游戏界面"""

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.buttons: List[MenuButton] = []
        self.stars: List[tuple] = []  # 星空背景星星
        self.panels: List[Panel] = []  # 信息面板
        self.labels: List[Label] = []  # 标签
        self.showing_menu = False  # 是否显示游戏菜单
        self.simulator = None  # 游戏模拟器引用，由外部注入
        self.setup_ui()
        self.generate_stars()

    def generate_stars(self):
        """生成星空背景"""
        width, height = self.screen.get_size()
        self.stars = []
        for _ in range(150):
            x = random.randint(0, width)
            y = random.randint(0, height)
            brightness = random.randint(50, 200)
            size = random.choice([1, 1, 1, 2, 2, 3])
            self.stars.append((x, y, brightness, size))

    def setup_ui(self):
        """设置UI"""
        width, height = self.screen.get_size()

        # 按钮尺寸根据窗口大小缩放
        btn_font_size = max(18, min(28, width // 50))

        # 左上角菜单按钮
        self.menu_button = MenuButton(
            20, 20, max(80, width // 13), max(32, height // 18),
            "菜单",
            callback=self.on_menu_clicked,
            font_size=btn_font_size
        )

        # 右上角星图按钮
        self.starmap_button = MenuButton(
            width - max(140, width // 9) - 20, 20,
            max(120, width // 9), max(40, height // 15),
            "星图",
            callback=self.on_starmap_clicked,
            font_size=btn_font_size + 2
        )

        # 创建信息面板 - 根据窗口大小动态计算
        margin = max(30, int(width * 0.04))
        available_width = width - margin * 2
        panel_width = max(200, (available_width - margin * 2) // 3)
        panel_height = max(200, int(height * 0.45))
        gap = max(15, (available_width - panel_width * 3) // 2)
        start_x = margin
        start_y = max(80, int(height * 0.14))

        # 左侧面板 - 资源
        self.resource_panel = Panel(start_x, start_y, panel_width, panel_height, "资源")
        # 动态添加标签会在render时处理

        # 中间面板 - 文明状态
        self.civilization_panel = Panel(
            start_x + panel_width + gap, start_y,
            panel_width, panel_height, "文明状态"
        )

        # 右侧面板 - 行动
        self.action_panel = Panel(
            start_x + (panel_width + gap) * 2, start_y,
            panel_width, panel_height, "行动"
        )

        self.load_fonts()

    def on_menu_clicked(self):
        """点击菜单按钮"""
        # 切换到游戏菜单
        self.screen_manager.switch_to(ScreenType.GAME_MENU)

    def on_starmap_clicked(self):
        """点击星图按钮"""
        # 切换到3D星图界面
        self.screen_manager.switch_to(ScreenType.STARMAP_VIEW)

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面"""
        super().on_enter(previous_screen, **kwargs)
        self.showing_menu = False

        # 更新屏幕引用，确保尺寸正确
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()

        # 重新生成星空（窗口大小可能改变）
        self.generate_stars()
        self.setup_ui()

    def update(self, dt: float):
        """更新界面"""
        super().update(dt)

        # 更新按钮
        self.menu_button.update(dt)
        self.starmap_button.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件"""
        if not self.active:
            return False

        # 处理按钮事件
        if self.menu_button.handle_event(event):
            return True
        if self.starmap_button.handle_event(event):
            return True

        # ESC键打开游戏菜单
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self.screen_manager.switch_to(ScreenType.GAME_MENU)
                return True

        return False

    def render(self, screen: pygame.Surface):
        """渲染界面"""
        if not self.visible:
            return

        width, height = screen.get_size()

        # 渲染背景
        screen.fill((5, 5, 15))

        # 渲染星空
        for x, y, brightness, size in self.stars:
            color = (brightness, brightness, brightness)
            pygame.draw.circle(screen, color, (x, y), size)

        # 渲染标题
        if 'title' in self.fonts:
            title = self.fonts['title'].render("三体文明", True, (200, 220, 255))
            title_rect = title.get_rect(center=(width // 2, 60))
            screen.blit(title, title_rect)

        # 渲染面板
        self._render_panels(screen)

        # 渲染按钮
        self.menu_button.render(screen)
        self.starmap_button.render(screen)

        # 渲染底部提示
        if 'tiny' in self.fonts:
            hint = self.fonts['tiny'].render(
                "ESC打开菜单 | 点击星图按钮进入3D视图",
                True, (100, 120, 150)
            )
            hint_rect = hint.get_rect(center=(width // 2, height - 20))
            screen.blit(hint, hint_rect)

    def _render_panels(self, screen: pygame.Surface):
        """渲染信息面板"""
        # 获取游戏状态（这里使用模拟数据，实际应从game对象获取）
        # TODO: 从实际游戏状态获取数据

        # 渲染资源面板
        self.resource_panel.render(screen)
        # 在面板上添加动态内容
        self._render_resource_content(screen)

        # 渲染文明状态面板
        self.civilization_panel.render(screen)
        self._render_civilization_content(screen)

        # 渲染行动面板
        self.action_panel.render(screen)
        self._render_action_content(screen)

    def _render_resource_content(self, screen: pygame.Surface):
        """渲染资源面板内容"""
        width, height = screen.get_size()
        panel = self.resource_panel
        font_size = max(14, min(20, width // 64))
        font = get_font(font_size)
        y_offset = max(40, int(panel.rect.height * 0.15))

        # 尝试从模拟器获取资源数据
        if self.simulator:
            state = self.simulator.get_state()
            resources = state.get("entities", {}).get("resources", {})
            # 转换为显示格式
            resource_data = [
                ("能源", str(int(resources.get("energy", 1200))), (255, 200, 100)),
                ("矿物", str(int(resources.get("minerals", 850))), (150, 200, 255)),
                ("食物", str(int(resources.get("food", 2300))), (100, 255, 150)),
                ("人口", str(int(resources.get("population", 500))), (255, 150, 200)),
            ]
        else:
            # 使用默认数据
            resource_data = [
                ("能源", "1200", (255, 200, 100)),
                ("矿物", "850", (150, 200, 255)),
                ("食物", "2300", (100, 255, 150)),
                ("人口", "500", (255, 150, 200)),
            ]

        line_gap = max(25, int(panel.rect.height * 0.1))
        for name, value, color in resource_data:
            text = f"{name}: {value}"
            surf = font.render(text, True, color)
            screen.blit(surf, (panel.rect.x + 15, panel.rect.y + y_offset))
            y_offset += line_gap

    def _render_civilization_content(self, screen: pygame.Surface):
        """渲染文明状态面板内容"""
        width, height = screen.get_size()
        panel = self.civilization_panel
        font_size = max(13, min(18, width // 72))
        small_font_size = max(10, min(14, width // 92))
        font = get_font(font_size)
        small_font = get_font(small_font_size)
        y_offset = max(38, int(panel.rect.height * 0.13))

        # 尝试从模拟器获取数据
        if self.simulator:
            state = self.simulator.get_state()
            entities = state.get("entities", {})
            env_params = state.get("environment", {}).get("params", {})

            people_count = entities.get('people_count', 1250)
            buildings_count = entities.get('buildings_count', 45)
            avg_efficiency = entities.get('avg_efficiency', 0.85)

            items = [
                ("人口总数", f"{people_count:,}", "+15/天"),
                ("建筑数量", f"{buildings_count}", "+2/天"),
                ("平均效率", f"{avg_efficiency:.0%}", "+0.5%/天"),
                ("科技等级", "3级", "1200/2000"),
                ("社会稳定", f"{env_params.get('stability', 0.92):.0%}", "+0.2%/天"),
            ]
        else:
            # 使用默认数据
            items = [
                ("人口总数", "1,250", "+15/天"),
                ("建筑数量", "45", "+2/天"),
                ("平均效率", "85%", "+0.5%/天"),
                ("科技等级", "3级", "1200/2000"),
                ("社会稳定", "92%", "+0.2%/天"),
            ]

        for name, value, trend in items:
            # 名称
            name_surf = font.render(name, True, (180, 200, 220))
            screen.blit(name_surf, (panel.rect.x + 15, panel.rect.y + y_offset))

            # 数值
            value_surf = font.render(value, True, (200, 220, 255))
            screen.blit(value_surf, (panel.rect.x + 150, panel.rect.y + y_offset))

            # 趋势
            trend_color = (100, 255, 100) if "+" in trend else (255, 100, 100)
            trend_surf = small_font.render(trend, True, trend_color)
            screen.blit(trend_surf, (panel.rect.x + 220, panel.rect.y + y_offset + 3))

            y_offset += max(24, int(panel.rect.height * 0.09))

    def _render_action_content(self, screen: pygame.Surface):
        """渲染行动面板内容"""
        width, height = screen.get_size()
        panel = self.action_panel
        font_size = max(14, min(20, width // 64))
        font = get_font(font_size)
        y_offset = max(40, int(panel.rect.height * 0.15))

        # 根据是否有模拟器连接，显示不同的行动
        if self.simulator:
            actions = [
                ("▶ 查看星图", "切换到3D星图视图", (100, 150, 255)),
                ("▶ 建造建筑", "在星球表面建造设施", (100, 255, 150)),
                ("▶ 分配人员", "调整人员工作岗位", (255, 200, 100)),
                ("▶ 科技研究", "研发新技术", (200, 150, 255)),
                ("▶ 外交关系", "管理与其他文明的关系", (255, 150, 200)),
            ]
        else:
            # 离线模式，显示基础操作
            actions = [
                ("▶ 查看星图", "切换到3D星图视图", (100, 150, 255)),
                ("▶ 建造建筑", "在星球表面建造设施", (100, 255, 150)),
                ("▶ 分配人员", "调整人员工作岗位", (255, 200, 100)),
                ("▶ 科技研究", "研发新技术", (200, 150, 255)),
                ("▶ 外交关系", "管理与其他文明的关系", (255, 150, 200)),
            ]

        for name, desc, color in actions:
            # 行动名称
            name_surf = font.render(name, True, color)
            screen.blit(name_surf, (panel.rect.x + 15, panel.rect.y + y_offset))

            y_offset += max(30, int(panel.rect.height * 0.12))
