"""设置界面 - 游戏各种设置选项"""

import pygame
import json
import os
from typing import Optional, List, Dict, Callable, Any
from dataclasses import dataclass, asdict

from .screen_manager import Screen, ScreenType
from .initial_menu import StarBackground, MenuButton


@dataclass
class GameSettings:
    """游戏设置数据类"""
    # 游戏设置
    time_scale: float = 1.0
    auto_save_interval: int = 300  # 秒
    tutorial_enabled: bool = True

    # 显示设置
    resolution: str = "1280x720"
    fullscreen: bool = False
    quality: str = "medium"
    particles_enabled: bool = True

    # 音频设置
    master_volume: float = 0.8
    music_volume: float = 0.7
    sfx_volume: float = 0.9

    # 控制设置
    mouse_sensitivity: float = 1.0

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> 'GameSettings':
        return cls(**data)


class SettingSlider:
    """设置滑块组件"""

    def __init__(self, x: int, y: int, width: int, label: str,
                 min_value: float, max_value: float, current_value: float,
                 callback: Callable[[float], None] = None,
                 show_value: bool = True, decimal_places: int = 1):
        self.rect = pygame.Rect(x, y, width, 30)
        self.label = label
        self.min_value = min_value
        self.max_value = max_value
        self.current_value = current_value
        self.callback = callback
        self.show_value = show_value
        self.decimal_places = decimal_places
        self.hovered = False
        self.dragging = False

        self.slider_rect = pygame.Rect(x + 100, y + 5, width - 200, 20)
        self.handle_radius = 8

    def get_value_text(self) -> str:
        """获取显示的值文本"""
        if self.decimal_places == 0:
            return str(int(self.current_value))
        return f"{self.current_value:.{self.decimal_places}f}"

    def update(self, dt: float):
        """更新滑块"""
        pass

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件"""
        if event.type == pygame.MOUSEMOTION:
            self.hovered = self.slider_rect.collidepoint(event.pos)

            if self.dragging:
                # 更新滑块值
                rel_x = event.pos[0] - self.slider_rect.x
                ratio = max(0, min(1, rel_x / self.slider_rect.width))
                new_value = self.min_value + (self.max_value - self.min_value) * ratio

                # 四舍五入到指定小数位
                if self.decimal_places == 0:
                    new_value = round(new_value)
                else:
                    new_value = round(new_value, self.decimal_places)

                if new_value != self.current_value:
                    self.current_value = new_value
                    if self.callback:
                        self.callback(self.current_value)

        elif event.type == pygame.MOUSEBUTTONDOWN:
            if event.button == 1:  # 左键
                if self.slider_rect.collidepoint(event.pos):
                    self.dragging = True
                    # 立即更新值
                    rel_x = event.pos[0] - self.slider_rect.x
                    ratio = max(0, min(1, rel_x / self.slider_rect.width))
                    self.current_value = self.min_value + (self.max_value - self.min_value) * ratio
                    if self.callback:
                        self.callback(self.current_value)
                    return True

        elif event.type == pygame.MOUSEBUTTONUP:
            if event.button == 1:
                self.dragging = False

        return False

    def render(self, screen: pygame.Surface, font: pygame.font.Font,
               value_font: pygame.font.Font):
        """渲染滑块"""
        # 绘制标签
        label_surf = font.render(self.label, True, (200, 210, 230))
        screen.blit(label_surf, (self.rect.x, self.rect.y + 2))

        # 绘制滑块轨道
        track_color = (60, 70, 100) if not self.hovered else (80, 90, 130)
        pygame.draw.rect(screen, track_color, self.slider_rect, border_radius=4)

        # 绘制已填充部分
        ratio = (self.current_value - self.min_value) / (self.max_value - self.min_value)
        filled_width = int(self.slider_rect.width * ratio)
        if filled_width > 0:
            filled_rect = pygame.Rect(
                self.slider_rect.x, self.slider_rect.y,
                filled_width, self.slider_rect.height
            )
            fill_color = (120, 150, 220) if not self.dragging else (150, 180, 255)
            pygame.draw.rect(screen, fill_color, filled_rect, border_radius=4)

        # 绘制滑块手柄
        handle_x = self.slider_rect.x + filled_width
        handle_y = self.slider_rect.centery
        handle_color = (200, 210, 255) if not self.dragging else (255, 255, 255)

        pygame.draw.circle(screen, handle_color, (handle_x, handle_y), self.handle_radius)
        pygame.draw.circle(screen, (100, 120, 180), (handle_x, handle_y), self.handle_radius, 2)

        # 绘制值
        if self.show_value:
            value_text = self.get_value_text()
            value_surf = value_font.render(value_text, True, (180, 190, 220))
            value_x = self.slider_rect.right + 15
            screen.blit(value_surf, (value_x, self.rect.y + 2))


class SettingsScreen(Screen):
    """设置界面"""

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.background: Optional[StarBackground] = None
        self.settings = GameSettings()
        self.sliders: List[SettingSlider] = []
        self.current_tab = "game"  # game, display, audio, control
        self.tabs: Dict[str, str] = {
            'game': '游戏',
            'display': '显示',
            'audio': '音频',
            'control': '控制'
        }
        self.buttons: List[MenuButton] = []
        self.setup_ui()
        self.load_settings()

    def setup_ui(self):
        """设置UI"""
        width, height = self.screen.get_size()

        # 创建星空背景
        self.background = StarBackground(width, height, star_count=200)

        # 创建标签页按钮
        tab_width = 100
        tab_height = 40
        tab_start_x = width // 2 - (len(self.tabs) * tab_width) // 2
        tab_y = 120

        self.tab_buttons = []
        for i, (key, label) in enumerate(self.tabs.items()):
            btn = MenuButton(
                tab_start_x + i * (tab_width + 10), tab_y,
                tab_width, tab_height,
                label,
                callback=lambda k=key: self.switch_tab(k),
                font_size=24
            )
            self.tab_buttons.append((key, btn))

        # 创建滑块
        self.create_sliders()

        # 创建底部按钮
        btn_width = 140
        btn_height = 45
        btn_y = height - 80

        self.buttons = [
            MenuButton(
                width // 2 - 160, btn_y, btn_width, btn_height,
                "应用", callback=self.apply_settings, font_size=26
            ),
            MenuButton(
                width // 2 + 20, btn_y, btn_width, btn_height,
                "重置", callback=self.reset_settings, font_size=26
            ),
            MenuButton(
                50, btn_y, 100, btn_height,
                "← 返回", callback=self.on_back, font_size=24
            ),
        ]

        self.load_fonts()

    def create_sliders(self):
        """创建设置滑块"""
        width, height = self.screen.get_size()
        slider_width = 400
        start_x = width // 2 - slider_width // 2
        start_y = 200
        gap = 60

        self.sliders = [
            # 游戏设置
            SettingSlider(
                start_x, start_y, slider_width,
                "时间流逝速度", 0.1, 5.0, self.settings.time_scale,
                lambda v: setattr(self.settings, 'time_scale', v),
                decimal_places=1
            ),
            SettingSlider(
                start_x, start_y + gap, slider_width,
                "自动保存间隔(分钟)", 1, 30, self.settings.auto_save_interval // 60,
                lambda v: setattr(self.settings, 'auto_save_interval', int(v) * 60),
                decimal_places=0
            ),
            # 音频设置
            SettingSlider(
                start_x, start_y, slider_width,
                "主音量", 0.0, 1.0, self.settings.master_volume,
                lambda v: setattr(self.settings, 'master_volume', v),
                decimal_places=2
            ),
            SettingSlider(
                start_x, start_y + gap, slider_width,
                "音乐音量", 0.0, 1.0, self.settings.music_volume,
                lambda v: setattr(self.settings, 'music_volume', v),
                decimal_places=2
            ),
            SettingSlider(
                start_x, start_y + gap * 2, slider_width,
                "音效音量", 0.0, 1.0, self.settings.sfx_volume,
                lambda v: setattr(self.settings, 'sfx_volume', v),
                decimal_places=2
            ),
            # 控制设置
            SettingSlider(
                start_x, start_y, slider_width,
                "鼠标灵敏度", 0.1, 3.0, self.settings.mouse_sensitivity,
                lambda v: setattr(self.settings, 'mouse_sensitivity', v),
                decimal_places=1
            ),
        ]

    def switch_tab(self, tab_name: str):
        """切换设置标签页"""
        self.current_tab = tab_name

    def get_visible_sliders(self) -> List[SettingSlider]:
        """获取当前标签页可见的滑块"""
        tab_ranges = {
            'game': (0, 2),
            'display': (2, 2),  # 暂无显示滑块
            'audio': (2, 5),
            'control': (5, 6),
        }

        start, end = tab_ranges.get(self.current_tab, (0, 0))
        return self.sliders[start:end]

    def load_settings(self):
        """从文件加载设置"""
        settings_path = "data/settings.json"
        if os.path.exists(settings_path):
            try:
                with open(settings_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    self.settings = GameSettings.from_dict(data)
            except Exception as e:
                print(f"加载设置失败: {e}")

        # 更新滑块值
        for slider in self.sliders:
            slider.callback(slider.current_value)

    def save_settings(self):
        """保存设置到文件"""
        os.makedirs("data", exist_ok=True)
        settings_path = "data/settings.json"

        try:
            with open(settings_path, 'w', encoding='utf-8') as f:
                json.dump(self.settings.to_dict(), f, indent=2, ensure_ascii=False)
            return True
        except Exception as e:
            print(f"保存设置失败: {e}")
            return False

    def apply_settings(self):
        """应用设置"""
        if self.save_settings():
            print("设置已保存")
            # TODO: 显示成功提示
        else:
            print("设置保存失败")
            # TODO: 显示错误提示

    def reset_settings(self):
        """重置为默认设置"""
        self.settings = GameSettings()
        # 更新所有滑块
        self.create_sliders()
        print("设置已重置为默认值")

    def on_back(self):
        """返回"""
        self.screen_manager.go_back()

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面"""
        super().on_enter(previous_screen, **kwargs)
        self.current_tab = 'game'
        self.load_settings()

        # 重新设置UI（窗口大小可能改变）
        self.setup_ui()

    def update(self, dt: float):
        """更新界面"""
        super().update(dt)

        if self.background:
            self.background.update(dt)

        for button in self.buttons:
            button.update(dt)

        for key, btn in self.tab_buttons:
            btn.update(dt)

        for slider in self.sliders:
            slider.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件"""
        if not self.active:
            return False

        # 处理标签页按钮
        for key, btn in self.tab_buttons:
            if btn.handle_event(event):
                return True

        # 处理当前标签页的滑块
        for slider in self.get_visible_sliders():
            if slider.handle_event(event):
                return True

        # 处理按钮
        for button in self.buttons:
            if button.handle_event(event):
                return True

        # ESC返回
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self.on_back()
                return True

        return False

    def render(self, screen: pygame.Surface):
        """渲染界面"""
        if not self.visible:
            return

        # 渲染背景
        if self.background:
            self.background.render(screen)

        width, height = screen.get_size()

        # 渲染标题
        if 'subtitle' in self.fonts:
            title = self.fonts['subtitle'].render("游戏设置", True, (220, 230, 255))
            title_rect = title.get_rect(center=(width // 2, 60))
            screen.blit(title, title_rect)

        # 渲染标签页按钮
        for key, btn in self.tab_buttons:
            # 高亮当前标签
            if key == self.current_tab:
                pygame.draw.rect(screen, (80, 100, 160), btn.rect, border_radius=5)
            btn.render(screen)

        # 渲染当前标签页的内容
        tab_names = {
            'game': '游戏设置',
            'display': '显示设置',
            'audio': '音频设置',
            'control': '控制设置'
        }

        if 'normal' in self.fonts:
            tab_title = self.fonts['normal'].render(tab_names.get(self.current_tab, ''), True, (180, 190, 220))
            screen.blit(tab_title, (width // 2 - 200, 180))

        # 渲染可见滑块
        for slider in self.get_visible_sliders():
            from render.ui import get_font
            slider.render(screen, get_font(24), get_font(20))

        # 渲染底部按钮
        for button in self.buttons:
            button.render(screen)
