"""初始菜单界面 - 游戏启动后的第一个界面"""

import pygame
import math
import random
from typing import Optional, List, Tuple

from .screen_manager import Screen, ScreenType


class StarBackground:
    """动态星空背景"""

    def __init__(self, width: int, height: int, star_count: int = 200):
        self.width = width
        self.height = height
        self.stars: List[Tuple[float, float, float, float]] = []  # x, y, size, speed
        self.time = 0.0

        # 生成星星
        for _ in range(star_count):
            x = random.uniform(0, width)
            y = random.uniform(0, height)
            size = random.uniform(0.5, 3.0)
            speed = random.uniform(0.2, 1.0)
            self.stars.append((x, y, size, speed))

    def update(self, dt: float):
        """更新星空动画"""
        self.time += dt

        # 缓慢移动星星
        new_stars = []
        for x, y, size, speed in self.stars:
            # 缓慢向左移动
            new_x = x - speed * dt * 10
            if new_x < 0:
                new_x = self.width
                y = random.uniform(0, self.height)
            new_stars.append((new_x, y, size, speed))
        self.stars = new_stars

    def render(self, screen: pygame.Surface):
        """渲染星空"""
        for x, y, size, speed in self.stars:
            # 闪烁效果
            base_brightness = int(100 + 155 * speed)
            twinkle = math.sin(self.time * 2 + x * 0.01) * 50
            brightness = int(max(50, min(255, base_brightness + twinkle)))

            color = (brightness, brightness, int(brightness * 0.9))
            pygame.draw.circle(screen, color, (int(x), int(y)), int(size))


class MenuButton:
    """菜单按钮"""

    def __init__(self, x: int, y: int, width: int, height: int, text: str,
                 callback=None, font_size: int = 36):
        self.rect = pygame.Rect(x, y, width, height)
        self.text = text
        self.callback = callback
        self.font_size = font_size
        self.hovered = False
        self.clicked = False
        self.animation_offset = 0.0

        from render.ui import get_font
        self.font = get_font(font_size)

    def update(self, dt: float):
        """更新按钮动画"""
        target_offset = 10.0 if self.hovered else 0.0
        self.animation_offset += (target_offset - self.animation_offset) * dt * 10

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件，返回是否被点击"""
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
        """渲染按钮"""
        # 计算动画后的位置
        x = self.rect.x + int(self.animation_offset)
        rect = pygame.Rect(x, self.rect.y, self.rect.width, self.rect.height)

        # 颜色
        if self.clicked:
            bg_color = (80, 90, 140)
            border_color = (150, 160, 220)
        elif self.hovered:
            bg_color = (60, 70, 120)
            border_color = (120, 140, 200)
        else:
            bg_color = (40, 50, 90)
            border_color = (80, 100, 160)

        # 绘制背景
        pygame.draw.rect(screen, bg_color, rect, border_radius=8)
        pygame.draw.rect(screen, border_color, rect, 2, border_radius=8)

        # 绘制文字
        text_surf = self.font.render(self.text, True, (220, 230, 255))
        text_rect = text_surf.get_rect(center=rect.center)
        screen.blit(text_surf, text_rect)


class InitialMenu(Screen):
    """初始菜单界面"""

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.background: Optional[StarBackground] = None
        self.buttons: List[MenuButton] = []
        self.title_alpha = 0.0
        self.setup_ui()

    def setup_ui(self):
        """设置UI"""
        width, height = self.screen.get_size()

        # 创建星空背景
        self.background = StarBackground(width, height, star_count=300)

        # 创建按钮
        button_width = 280
        button_height = 60
        button_x = width // 2 - button_width // 2
        start_y = height // 2 + 50
        gap = 80

        self.buttons = [
            MenuButton(
                button_x, start_y,
                button_width, button_height,
                "开始游戏",
                callback=self.on_start_game,
                font_size=40
            ),
            MenuButton(
                button_x, start_y + gap,
                button_width, button_height,
                "设置",
                callback=self.on_settings,
                font_size=40
            ),
            MenuButton(
                button_x, start_y + gap * 2,
                button_width, button_height,
                "退出",
                callback=self.on_quit,
                font_size=40
            ),
        ]

        self.load_fonts()

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面"""
        super().on_enter(previous_screen, **kwargs)
        self.title_alpha = 0.0

        # 更新屏幕引用，确保尺寸正确
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()

        # 重新设置UI（窗口大小可能改变）
        self.setup_ui()

    def on_start_game(self):
        """点击开始游戏"""
        from .screen_manager import ScreenType
        self.screen_manager.switch_to(ScreenType.START_GAME_MENU)

    def on_settings(self):
        """点击设置"""
        from .screen_manager import ScreenType
        self.screen_manager.switch_to(ScreenType.SETTINGS)

    def on_quit(self):
        """点击退出"""
        pygame.event.post(pygame.event.Event(pygame.QUIT))

    def update(self, dt: float):
        """更新界面"""
        super().update(dt)

        if self.background:
            self.background.update(dt)

        for button in self.buttons:
            button.update(dt)

        # 标题淡入效果
        if self.title_alpha < 1.0:
            self.title_alpha = min(1.0, self.title_alpha + dt * 2)

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件"""
        if not self.active:
            return False

        # 处理按钮事件
        for button in self.buttons:
            if button.handle_event(event):
                return True

        # ESC退出
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                pygame.event.post(pygame.event.Event(pygame.QUIT))
                return True

        return False

    def render(self, screen: pygame.Surface):
        """渲染界面"""
        if not self.visible:
            return

        # 渲染星空背景
        if self.background:
            self.background.render(screen)

        # 渲染标题
        if 'title' in self.fonts:
            title_surf = self.fonts['title'].render("三体文明", True, (200, 220, 255))
            title_rect = title_surf.get_rect(center=(self.rect.centerx, self.rect.height * 0.25))

            # 应用透明度
            if self.title_alpha < 1.0:
                title_surf.set_alpha(int(self.title_alpha * 255))

            # 添加发光效果
            glow_surf = self.fonts['title'].render("三体文明", True, (100, 130, 180))
            glow_surf.set_alpha(80)
            for offset in [(-2, -2), (2, -2), (-2, 2), (2, 2)]:
                screen.blit(glow_surf, title_rect.move(*offset))

            screen.blit(title_surf, title_rect)

            # 副标题
            if 'subtitle' in self.fonts:
                subtitle = self.fonts['subtitle'].render("Three-Body Civilization", True, (150, 170, 200))
                sub_rect = subtitle.get_rect(center=(self.rect.centerx, self.rect.height * 0.25 + 60))
                if self.title_alpha < 1.0:
                    subtitle.set_alpha(int(self.title_alpha * 255))
                screen.blit(subtitle, sub_rect)

        # 渲染按钮
        for button in self.buttons:
            button.render(screen)

        # 版本号
        if 'tiny' in self.fonts:
            version = self.fonts['tiny'].render("v0.1.0 Alpha", True, (100, 100, 120))
            screen.blit(version, (self.rect.width - version.get_width() - 20, self.rect.height - 30))
