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
        scale = min(width / 1280, height / 720)

        # 按钮尺寸根据窗口大小缩放
        btn_font_size = max(16, int(22 * scale))
        btn_w = max(70, int(90 * scale))   # 统一小按钮宽度
        btn_h = max(30, int(38 * scale))
        gap = int(10 * scale)

        # 左上角菜单按钮
        x = int(15 * scale)
        self.menu_button = MenuButton(
            x, int(15 * scale), btn_w, btn_h,
            "菜单",
            callback=self.on_menu_clicked,
            font_size=btn_font_size
        )
        x += btn_w + gap

        # 暂停/继续按钮
        self.pause_button = MenuButton(
            x, int(15 * scale), btn_w, btn_h,
            "暂停",
            callback=self.on_pause_toggle,
            font_size=btn_font_size
        )
        x += btn_w + gap

        # 科技树按钮
        self.tech_button = MenuButton(
            x, int(15 * scale), btn_w, btn_h,
            "科技树",
            callback=self.on_tech_clicked,
            font_size=btn_font_size
        )
        x += btn_w + gap

        # 政策按钮
        self.policy_button = MenuButton(
            x, int(15 * scale), btn_w, btn_h,
            "政策",
            callback=self.on_policy_clicked,
            font_size=btn_font_size
        )
        x += btn_w + gap

        # 区域/建筑浏览按钮
        self.zone_button = MenuButton(
            x, int(15 * scale), btn_w * 2, btn_h,
            "区域 / 建筑",
            callback=self.on_zone_clicked,
            font_size=btn_font_size
        )
        x += btn_w * 2 + gap

        # 右上角星图按钮
        starmap_w = max(90, int(110 * scale))
        self.starmap_button = MenuButton(
            width - starmap_w - int(15 * scale), int(15 * scale),
            starmap_w, btn_h,
            "星图",
            callback=self.on_starmap_clicked,
            font_size=btn_font_size
        )

        # 创建信息面板 - 3个面板
        margin = max(30, int(width * 0.04))
        available_width = width - margin * 2
        panel_width = max(200, (available_width - margin * 2) // 3)
        panel_height = max(200, int(height * 0.45))
        gap = max(15, (available_width - panel_width * 3) // 2)
        start_x = margin
        start_y = max(80, int(height * 0.18))

        # 左侧面板1 - 资源
        self.resource_panel = Panel(start_x, start_y, panel_width, panel_height, "资源总览")

        # 面板2 - 文明状态
        self.civilization_panel = Panel(
            start_x + panel_width + gap, start_y,
            panel_width, panel_height, "文明与状态"
        )
        
        # 面板3 - 环境
        self.environment_panel = Panel(
            start_x + (panel_width + gap) * 2, start_y,
            panel_width, panel_height, "环境监控"
        )

        self.load_fonts()

    def on_pause_toggle(self):
        """点击暂停按钮"""
        if self.simulator:
            self.simulator.toggle_pause()
            self.pause_button.text = "继续" if self.simulator.paused else "暂停"

    def on_menu_clicked(self):
        """点击菜单按钮"""
        # 切换到游戏菜单
        self.screen_manager.switch_to(ScreenType.GAME_MENU)

    def on_starmap_clicked(self):
        """点击星图按钮"""
        if self.simulator and not self.simulator.tech_tree.is_unlocked("telescope"):
            return
        # 切换到3D星图界面
        self.screen_manager.switch_to(ScreenType.STARMAP_VIEW)

    def on_tech_clicked(self):
        """点击科技树按钮"""
        self.screen_manager.switch_to(ScreenType.TECH_TREE)

    def on_policy_clicked(self):
        """点击政策按钮"""
        self.screen_manager.switch_to(ScreenType.DECISION)

    def on_zone_clicked(self):
        """点击区域浏览按钮"""
        self.screen_manager.switch_to(ScreenType.ZONE_VIEW)

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面"""
        super().on_enter(previous_screen, **kwargs)
        self.showing_menu = False

        # 更新屏幕引用，确保尺寸正确
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()

        # 更新重新生成星空并布局
        self.generate_stars()
        self.setup_ui()
        
        # 更新暂停按钮状态
        if self.simulator:
            self.pause_button.text = "继续" if self.simulator.paused else "暂停"
            if not self.simulator.tech_tree.is_unlocked("telescope"):
                self.starmap_button.text = "[锁定]星图"
            else:
                self.starmap_button.text = "星图"

    def update(self, dt: float):
        """更新界面"""
        super().update(dt)

        # 检查自动存档
        if self.simulator and not self.simulator.paused and not self.simulator.game_over:
            current_day = int(self.simulator.time)
            if current_day % 100 == 0 and current_day != getattr(self.simulator, 'last_autosave_day', -1):
                self.simulator.last_autosave_day = current_day
                from game.save_manager import SaveManager
                SaveManager().save_game(self.simulator, save_name=f"自动存档_第{current_day}天")

        # 更新按钮
        self.menu_button.update(dt)
        self.pause_button.update(dt)
        self.tech_button.update(dt)
        self.policy_button.update(dt)
        self.zone_button.update(dt)
        self.starmap_button.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件"""
        if not self.active:
            return False

        # 处理按钮事件
        if self.menu_button.handle_event(event):
            return True
        if self.pause_button.handle_event(event):
            return True
        if self.tech_button.handle_event(event):
            return True
        if self.policy_button.handle_event(event):
            return True
        if self.zone_button.handle_event(event):
            return True
        if self.starmap_button.handle_event(event):
            return True

        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_SPACE:
                if self.simulator:
                    self.simulator.toggle_pause()
                    self.pause_button.text = "继续" if self.simulator.paused else "暂停"
                return True
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

        # 渲染标题（在按钮行下方）— 显示宇宙名称
        display_name = "三体文明"
        if self.simulator and hasattr(self.simulator, 'universe_name'):
            display_name = self.simulator.universe_name
        # 根据名称长度自适应字体大小，避免过长名称溢出
        scale = min(width / 1280, height / 720)
        base_size = max(28, int(40 * scale))
        if len(display_name) > 6:
            base_size = max(22, int(32 * scale))
        title_font = get_font(base_size)
        title = title_font.render(display_name, True, (200, 220, 255))
        title_y = max(55, int(height * 0.07))
        title_rect = title.get_rect(center=(width // 2, title_y))
        screen.blit(title, title_rect)

        # 渲染面板
        self._render_panels(screen)

        # 渲染按钮
        self.menu_button.render(screen)
        self.pause_button.render(screen)
        self.tech_button.render(screen)
        self.policy_button.render(screen)
        self.zone_button.render(screen)
        self.starmap_button.render(screen)
        
        # 渲染游戏时间和说明
        if self.simulator and 'normal' in self.fonts:
            time_text = f"第 {int(self.simulator.time)} 天"
            time_surf = self.fonts['normal'].render(time_text, True, (255, 255, 200))
            time_y = max(90, int(height * 0.14))
            time_rect = time_surf.get_rect(center=(width // 2, time_y))
            screen.blit(time_surf, time_rect)

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
        # 渲染资源面板
        self.resource_panel.render(screen)
        self._render_resource_content(screen)

        # 渲染文明状态面板
        self.civilization_panel.render(screen)
        self._render_civilization_content(screen)
        
        # 渲染环境面板
        self.environment_panel.render(screen)
        self._render_environment_content(screen)

    def _render_resource_content(self, screen: pygame.Surface):
        """渲染资源面板内容"""
        width, height = screen.get_size()
        panel = self.resource_panel
        scale = min(width / 1280, height / 720)
        font_size = max(18, int(24 * scale))
        font = get_font(font_size)
        y_offset = max(40, int(panel.rect.height * 0.15))

        # 尝试从模拟器获取资源数据
        if self.simulator:
            state = self.simulator.get_state()
            resources = state.get("entities", {}).get("resources", {})
            pop_state = state.get("entities", {}).get("population", {})
            # 转换为显示格式
            resource_data = [
                ("电力 (kW)", str(int(resources.get("electricity", 0))), (255, 220, 80)),
                ("铁矿", str(int(resources.get("iron", 0))), (180, 180, 200)),
                ("铜矿", str(int(resources.get("copper", 0))), (220, 160, 100)),
                ("稀有矿", str(int(resources.get("rare_mineral", 0))), (180, 120, 255)),
                ("食物", str(int(resources.get("food", 0))), (100, 255, 150)),
                ("化石燃料", str(int(resources.get("fossil_fuel", 0))), (160, 140, 100)),
                ("藻类燃料", str(int(resources.get("algae_fuel", 0))), (100, 200, 120)),
            ]
        else:
            # 使用默认数据
            resource_data = [
                ("电力 (kW)", "0", (255, 220, 80)),
                ("铁矿", "200", (180, 180, 200)),
                ("铜矿", "30", (220, 160, 100)),
                ("食物", "300", (100, 255, 150)),
            ]

        line_gap = max(20, int(panel.rect.height * 0.1))
        for name, value, color in resource_data:
            text = f"{name}: {value}"
            surf = font.render(text, True, color)
            screen.blit(surf, (panel.rect.x + 15, panel.rect.y + y_offset))
            y_offset += line_gap

    def _render_civilization_content(self, screen: pygame.Surface):
        """渲染文明状态面板内容"""
        width, height = screen.get_size()
        panel = self.civilization_panel
        scale = min(width / 1280, height / 720)
        font_size = max(16, int(22 * scale))
        small_font_size = max(13, int(17 * scale))
        font = get_font(font_size)
        small_font = get_font(small_font_size)
        y_offset = max(38, int(panel.rect.height * 0.13))

        # 尝试从模拟器获取数据
        if self.simulator:
            state = self.simulator.get_state()
            entities = state.get("entities", {})
            env_params = state.get("environment", {}).get("params", {})
            policy = state.get("decision", {}).get("current_state", "normal")
            tech_count = len(state.get("technology", {}).get("unlocked", []))

            buildings_count = entities.get('buildings_count', 0)
            avg_efficiency = entities.get('avg_efficiency', 1.0)
            pop_total = entities.get('population', {}).get('total', 100)

            items = [
                ("人口总数", f"{pop_total} 人", ""),
                ("设施数量", f"{buildings_count} 座", ""),
                ("工业效率", f"{avg_efficiency:.0%}", ""),
                ("已解科技", f"{tech_count} 项", ""),
                ("当前政策", policy.upper(), ""),
            ]
        else:
            # 使用默认数据
            items = [
                ("人口总数", "100 人", ""),
                ("设施数量", "0 座", ""),
                ("工业效率", "100%", ""),
                ("已解科技", "0 项", ""),
                ("当前政策", "NORMAL", ""),
            ]

        for name, value, trend in items:
            # 名称
            name_surf = font.render(name, True, (180, 200, 220))
            screen.blit(name_surf, (panel.rect.x + 15, panel.rect.y + y_offset))

            # 数值 - 位置相对面板宽度
            value_x = panel.rect.x + int(panel.rect.width * 0.5)
            value_surf = font.render(value, True, (200, 220, 255))
            screen.blit(value_surf, (value_x, panel.rect.y + y_offset))

            # 趋势
            trend_color = (100, 255, 100) if "+" in trend else (255, 100, 100)
            trend_x = panel.rect.x + int(panel.rect.width * 0.75)
            trend_surf = small_font.render(trend, True, trend_color)
            screen.blit(trend_surf, (trend_x, panel.rect.y + y_offset + 3))

            y_offset += max(24, int(panel.rect.height * 0.09))

    def _render_environment_content(self, screen: pygame.Surface):
        """渲染环境面板内容"""
        width, height = screen.get_size()
        panel = self.environment_panel
        scale = min(width / 1280, height / 720)
        font_size = max(16, int(22 * scale))
        font = get_font(font_size)
        y_offset = max(38, int(panel.rect.height * 0.13))

        if self.simulator:
            state = self.simulator.get_state()
            env_params = state.get("environment", {}).get("params", {})
            temp = env_params.get("temperature", -273.15)
            rad = env_params.get("radiation", 0.0)
            light = env_params.get("light_intensity", 0.0)
            stability = env_params.get("stability", 0.0)
            
            # 判断颜色
            temp_color = (100, 255, 100)
            if temp < -50: temp_color = (100, 150, 255)
            elif temp > 60: temp_color = (255, 100, 100)
            
            rad_color = (100, 255, 100)
            if rad > 10.0: rad_color = (255, 50, 50)
            elif rad > 2.0: rad_color = (255, 200, 50)
            
            stab_color = (100, 255, 100) if stability > 0.5 else (255, 100, 100)
            
            items = [
                ("表面温度", f"{temp:.1f} ℃  (全球均值)", temp_color),
                ("环境辐射", f"{rad:.2f}  (全球均值)", rad_color),
                ("光照强度", f"{light:.1%}", (255, 255, 150)),
                ("地质稳定", "稳定" if stability > 0.5 else "危险", stab_color),
            ]
        else:
            items = [
                ("表面温度", "22.5 ℃", (100, 255, 100)),
                ("环境辐射", "0.05 辐射度", (100, 255, 100)),
                ("光照强度", "100%", (255, 255, 150)),
                ("地质稳定", "稳定", (100, 255, 100)),
            ]

        for name, value, color in items:
            name_surf = font.render(name, True, (180, 200, 220))
            screen.blit(name_surf, (panel.rect.x + 15, panel.rect.y + y_offset))
            
            value_x = panel.rect.x + int(panel.rect.width * 0.5)
            value_surf = font.render(value, True, color)
            screen.blit(value_surf, (value_x, panel.rect.y + y_offset))
            
            y_offset += max(24, int(panel.rect.height * 0.09))


