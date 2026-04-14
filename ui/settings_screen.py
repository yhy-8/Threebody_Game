"""设置界面 - 游戏各种设置"""

import pygame
import os
import json
from typing import Optional, List, Dict, Callable, Any
from dataclasses import dataclass, asdict
from enum import Enum

from .screen_manager import Screen, ScreenType
from .initial_menu import StarBackground, MenuButton


class SettingTab(Enum):
    """设置标签页"""
    GAME = "游戏"
    DISPLAY = "显示"
    AUDIO = "音频"
    CONTROLS = "控制"


@dataclass
class GameSettings:
    """游戏设置数据类"""
    # 游戏设置
    time_scale: float = 1.0
    auto_save_interval: int = 5  # 分钟
    enable_tutorial: bool = True
    show_notifications: bool = True

    # 显示设置
    resolution: str = "1280x720"
    fullscreen: bool = False
    vsync: bool = True
    quality_level: int = 2  # 0-3
    particle_effects: bool = True
    show_fps: bool = False

    # 音频设置
    master_volume: float = 0.8
    music_volume: float = 0.7
    sfx_volume: float = 0.9
    ambient_volume: float = 0.6
    mute_when_unfocused: bool = True

    # 控制设置
    mouse_sensitivity: float = 1.0
    invert_mouse_y: bool = False
    enable_edge_scrolling: bool = True
    edge_scroll_speed: float = 1.0
    keyboard_layout: str = "qwerty"

    def to_dict(self) -> dict:
        """转换为字典"""
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> 'GameSettings':
        """从字典创建"""
        return cls(**data)


class SettingSlider:
    """设置滑块组件"""

    def __init__(self, x: int, y: int, width: int, height: int,
                 min_val: float, max_val: float, initial: float,
                 label: str, decimals: int = 1, suffix: str = "",
                 on_change: Optional[Callable[[float], None]] = None):
        self.rect = pygame.Rect(x, y, width, height)
        self.min_val = min_val
        self.max_val = max_val
        self.value = initial
        self.label = label
        self.decimals = decimals
        self.suffix = suffix
        self.on_change = on_change

        self.dragging = False
        self.hovered = False
        track_h = max(6, height // 6)
        self.track_rect = pygame.Rect(x, y + height // 2 - track_h // 2, width, track_h)
        self.handle_radius = max(7, height // 5)

        from render.ui import get_font
        font_size = max(14, int(height * 0.4))
        label_font_size = max(12, int(height * 0.36))
        self.font = get_font(font_size)
        self.label_font = get_font(label_font_size)

    def update(self, dt: float):
        """更新滑块"""
        pass

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件"""
        if event.type == pygame.MOUSEMOTION:
            self.hovered = self.rect.collidepoint(event.pos)
            if self.dragging:
                self._update_value_from_pos(event.pos[0])
                return True

        elif event.type == pygame.MOUSEBUTTONDOWN:
            if event.button == 1:
                if self.rect.collidepoint(event.pos):
                    self.dragging = True
                    self._update_value_from_pos(event.pos[0])
                    return True

        elif event.type == pygame.MOUSEBUTTONUP:
            if event.button == 1:
                self.dragging = False

        return False

    def _update_value_from_pos(self, x: int):
        """从鼠标位置更新值"""
        ratio = (x - self.track_rect.x) / self.track_rect.width
        ratio = max(0, min(1, ratio))
        self.value = self.min_val + ratio * (self.max_val - self.min_val)

        if self.decimals == 0:
            self.value = round(self.value)
        else:
            self.value = round(self.value, self.decimals)

        if self.on_change:
            self.on_change(self.value)

    def render(self, screen: pygame.Surface):
        """渲染滑块"""
        # 绘制标签
        label_surf = self.label_font.render(self.label, True, (180, 190, 220))
        screen.blit(label_surf, (self.rect.x, self.rect.y - 5))

        # 绘制轨道
        track_color = (60, 70, 100) if not self.hovered else (80, 90, 120)
        pygame.draw.rect(screen, track_color, self.track_rect, border_radius=4)

        # 绘制填充部分
        ratio = (self.value - self.min_val) / (self.max_val - self.min_val)
        fill_width = int(self.track_rect.width * ratio)
        fill_rect = pygame.Rect(self.track_rect.x, self.track_rect.y, fill_width, self.track_rect.height)
        fill_color = (100, 150, 220) if not self.dragging else (120, 170, 255)
        pygame.draw.rect(screen, fill_color, fill_rect, border_radius=4)

        # 绘制手柄
        handle_x = self.track_rect.x + fill_width
        handle_y = self.track_rect.centery
        handle_color = (180, 200, 255) if not self.dragging else (220, 230, 255)
        pygame.draw.circle(screen, handle_color, (handle_x, handle_y), self.handle_radius)
        pygame.draw.circle(screen, (100, 120, 160), (handle_x, handle_y), self.handle_radius, 2)

        # 绘制值
        value_text = f"{self.value:.{self.decimals}f}{self.suffix}"
        value_surf = self.font.render(value_text, True, (200, 210, 240))
        screen.blit(value_surf, (self.rect.right - value_surf.get_width(), self.rect.y + self.rect.height // 4))


class SettingCheckbox:
    """设置复选框组件"""

    def __init__(self, x: int, y: int, width: int, height: int,
                 label: str, initial: bool = False,
                 on_change: Optional[Callable[[bool], None]] = None):
        self.rect = pygame.Rect(x, y, width, height)
        self.label = label
        self.checked = initial
        self.on_change = on_change
        self.hovered = False

        from render.ui import get_font
        font_size = max(14, int(height * 0.5))
        self.font = get_font(font_size)
        self.checkbox_size = max(18, int(height * 0.6))

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件"""
        if event.type == pygame.MOUSEMOTION:
            self.hovered = self.rect.collidepoint(event.pos)

        elif event.type == pygame.MOUSEBUTTONDOWN:
            if event.button == 1 and self.rect.collidepoint(event.pos):
                self.checked = not self.checked
                if self.on_change:
                    self.on_change(self.checked)
                return True

        return False

    def render(self, screen: pygame.Surface):
        """渲染复选框"""
        # 绘制复选框
        checkbox_rect = pygame.Rect(
            self.rect.x,
            self.rect.centery - self.checkbox_size // 2,
            self.checkbox_size,
            self.checkbox_size
        )

        # 背景
        bg_color = (60, 70, 100) if not self.hovered else (80, 90, 120)
        if self.checked:
            bg_color = (80, 120, 180)
        pygame.draw.rect(screen, bg_color, checkbox_rect, border_radius=4)
        pygame.draw.rect(screen, (120, 140, 180), checkbox_rect, 2, border_radius=4)

        # 勾选标记
        if self.checked:
            # 绘制对勾
            check_color = (200, 220, 255)
            points = [
                (checkbox_rect.x + 5, checkbox_rect.centery),
                (checkbox_rect.x + 10, checkbox_rect.centery + 5),
                (checkbox_rect.x + 19, checkbox_rect.centery - 6)
            ]
            pygame.draw.lines(screen, check_color, False, points, 3)

        # 绘制标签
        label_surf = self.font.render(self.label, True, (200, 210, 240))
        label_pos = (checkbox_rect.right + 10, checkbox_rect.centery - label_surf.get_height() // 2)
        screen.blit(label_surf, label_pos)


class SettingsScreen(Screen):
    """设置界面"""

    SETTINGS_FILE = "data/settings.json"

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.background: Optional[StarBackground] = None
        self.current_tab = SettingTab.GAME
        self.settings = GameSettings()
        self.load_settings()

        # UI组件
        self.tab_buttons: Dict[SettingTab, MenuButton] = {}
        self.sliders: List[SettingSlider] = []
        self.checkboxes: List[SettingCheckbox] = []
        self.buttons: List[MenuButton] = []

        self.setup_ui()

    def load_settings(self):
        """从文件加载设置"""
        if os.path.exists(self.SETTINGS_FILE):
            try:
                with open(self.SETTINGS_FILE, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    self.settings = GameSettings.from_dict(data)
            except Exception as e:
                print(f"加载设置失败: {e}")

    def save_settings(self):
        """保存设置到文件"""
        try:
            os.makedirs(os.path.dirname(self.SETTINGS_FILE), exist_ok=True)
            with open(self.SETTINGS_FILE, 'w', encoding='utf-8') as f:
                json.dump(self.settings.to_dict(), f, indent=2, ensure_ascii=False)
        except Exception as e:
            print(f"保存设置失败: {e}")

    def setup_ui(self):
        """设置UI"""
        width, height = self.screen.get_size()
        scale = min(width / 1280, height / 720)

        # 创建星空背景
        self.background = StarBackground(width, height, star_count=200)

        # 创建标签页按钮 - 按比例缩放
        tab_width = max(100, int(140 * scale))
        tab_height = max(35, int(45 * scale))
        tab_gap = max(6, int(10 * scale))
        tab_font_size = max(16, int(24 * scale))
        start_x = width // 2 - (tab_width * 4 + tab_gap * 3) // 2
        tab_y = max(60, int(80 * scale))

        self.tab_buttons = {}
        for i, tab in enumerate(SettingTab):
            btn = MenuButton(
                start_x + i * (tab_width + tab_gap), tab_y,
                tab_width, tab_height,
                tab.value,
                callback=lambda t=tab: self.on_tab_changed(t),
                font_size=tab_font_size
            )
            self.tab_buttons[tab] = btn

        # 创建底部按钮
        btn_width = max(90, int(120 * scale))
        btn_height = max(35, int(45 * scale))
        btn_font_size = max(18, int(26 * scale))
        btn_y = height - max(60, int(80 * scale))

        self.buttons = [
            MenuButton(
                width // 2 - btn_width - 20, btn_y,
                btn_width, btn_height,
                "应用",
                callback=self.on_apply,
                font_size=btn_font_size
            ),
            MenuButton(
                width // 2 + 20, btn_y,
                btn_width, btn_height,
                "返回",
                callback=self.on_back,
                font_size=btn_font_size
            ),
        ]

        self.load_fonts()
        self.refresh_tab_content()

    def refresh_tab_content(self):
        """刷新当前标签页内容"""
        self.sliders.clear()
        self.checkboxes.clear()

        width, height = self.screen.get_size()
        scale = min(width / 1280, height / 720)

        # 内容区域参数 - 按比例缩放
        content_width = max(300, int(400 * scale))
        content_x = width // 2 - content_width // 2
        content_y = max(130, int(160 * scale))
        slider_height = max(38, int(50 * scale))
        checkbox_height = max(30, int(40 * scale))
        gap = max(50, int(70 * scale))
        small_gap = max(36, int(50 * scale))

        s = self.settings

        if self.current_tab == SettingTab.GAME:
            # 游戏设置
            self.sliders = [
                SettingSlider(
                    content_x, content_y, content_width, slider_height,
                    0.1, 5.0, s.time_scale,
                    "时间流逝速度", decimals=1, suffix="x",
                    on_change=lambda v: setattr(self.settings, 'time_scale', v)
                ),
                SettingSlider(
                    content_x, content_y + gap, content_width, slider_height,
                    1, 30, s.auto_save_interval,
                    "自动保存间隔", decimals=0, suffix="分钟",
                    on_change=lambda v: setattr(self.settings, 'auto_save_interval', int(v))
                ),
            ]
            self.checkboxes = [
                SettingCheckbox(
                    content_x, content_y + gap * 2, content_width, checkbox_height,
                    "启用教程提示", s.enable_tutorial,
                    on_change=lambda v: setattr(self.settings, 'enable_tutorial', v)
                ),
                SettingCheckbox(
                    content_x, content_y + gap * 2 + small_gap, content_width, checkbox_height,
                    "显示通知消息", s.show_notifications,
                    on_change=lambda v: setattr(self.settings, 'show_notifications', v)
                ),
            ]

        elif self.current_tab == SettingTab.DISPLAY:
            # 显示设置
            self.checkboxes = [
                SettingCheckbox(
                    content_x, content_y, content_width, checkbox_height,
                    "全屏模式", s.fullscreen,
                    on_change=lambda v: setattr(self.settings, 'fullscreen', v)
                ),
                SettingCheckbox(
                    content_x, content_y + small_gap, content_width, checkbox_height,
                    "垂直同步", s.vsync,
                    on_change=lambda v: setattr(self.settings, 'vsync', v)
                ),
                SettingCheckbox(
                    content_x, content_y + small_gap * 2, content_width, checkbox_height,
                    "粒子效果", s.particle_effects,
                    on_change=lambda v: setattr(self.settings, 'particle_effects', v)
                ),
                SettingCheckbox(
                    content_x, content_y + small_gap * 3, content_width, checkbox_height,
                    "显示FPS", s.show_fps,
                    on_change=lambda v: setattr(self.settings, 'show_fps', v)
                ),
            ]
            self.sliders = [
                SettingSlider(
                    content_x, content_y + small_gap * 4 + int(20 * scale), content_width, slider_height,
                    0, 3, s.quality_level,
                    "画质等级", decimals=0, suffix="",
                    on_change=lambda v: setattr(self.settings, 'quality_level', int(v))
                ),
            ]

        elif self.current_tab == SettingTab.AUDIO:
            # 音频设置
            audio_gap = max(50, int(70 * scale))
            self.sliders = [
                SettingSlider(
                    content_x, content_y, content_width, slider_height,
                    0.0, 1.0, s.master_volume,
                    "主音量", decimals=2, suffix="",
                    on_change=lambda v: setattr(self.settings, 'master_volume', v)
                ),
                SettingSlider(
                    content_x, content_y + audio_gap, content_width, slider_height,
                    0.0, 1.0, s.music_volume,
                    "音乐音量", decimals=2, suffix="",
                    on_change=lambda v: setattr(self.settings, 'music_volume', v)
                ),
                SettingSlider(
                    content_x, content_y + audio_gap * 2, content_width, slider_height,
                    0.0, 1.0, s.sfx_volume,
                    "音效音量", decimals=2, suffix="",
                    on_change=lambda v: setattr(self.settings, 'sfx_volume', v)
                ),
                SettingSlider(
                    content_x, content_y + audio_gap * 3, content_width, slider_height,
                    0.0, 1.0, s.ambient_volume,
                    "环境音量", decimals=2, suffix="",
                    on_change=lambda v: setattr(self.settings, 'ambient_volume', v)
                ),
            ]
            self.checkboxes = [
                SettingCheckbox(
                    content_x, content_y + audio_gap * 4 + int(10 * scale), content_width, checkbox_height,
                    "失去焦点时静音", s.mute_when_unfocused,
                    on_change=lambda v: setattr(self.settings, 'mute_when_unfocused', v)
                ),
            ]

        elif self.current_tab == SettingTab.CONTROLS:
            # 控制设置
            self.sliders = [
                SettingSlider(
                    content_x, content_y, content_width, slider_height,
                    0.1, 3.0, s.mouse_sensitivity,
                    "鼠标灵敏度", decimals=1, suffix="x",
                    on_change=lambda v: setattr(self.settings, 'mouse_sensitivity', v)
                ),
                SettingSlider(
                    content_x, content_y + gap, content_width, slider_height,
                    0.5, 2.0, s.edge_scroll_speed,
                    "边缘滚动速度", decimals=1, suffix="x",
                    on_change=lambda v: setattr(self.settings, 'edge_scroll_speed', v)
                ),
            ]
            self.checkboxes = [
                SettingCheckbox(
                    content_x, content_y + gap * 2, content_width, checkbox_height,
                    "反转鼠标Y轴", s.invert_mouse_y,
                    on_change=lambda v: setattr(self.settings, 'invert_mouse_y', v)
                ),
                SettingCheckbox(
                    content_x, content_y + gap * 2 + small_gap, content_width, checkbox_height,
                    "启用边缘滚动", s.enable_edge_scrolling,
                    on_change=lambda v: setattr(self.settings, 'enable_edge_scrolling', v)
                ),
            ]

    def on_tab_changed(self, tab: SettingTab):
        """标签页切换"""
        self.current_tab = tab
        self.refresh_tab_content()

    def on_apply(self):
        """应用设置"""
        self.save_settings()
        self.apply_display_settings()
        print("设置已应用并保存")

    def on_back(self):
        """返回"""
        # 返回上级界面，使用当前屏幕类型的前一个屏幕类型作为fallback
        # 这样可以从设置界面返回到游戏菜单或初始菜单
        prev_type = self.screen_manager.previous_screen_type

        if prev_type is not None:
            self.screen_manager.go_back(fallback_screen=prev_type)
        else:
            from .screen_manager import ScreenType
            self.screen_manager.go_back(fallback_screen=ScreenType.INITIAL_MENU)

    def apply_display_settings(self):
        """应用显示设置"""
        # 获取主屏幕以应用显示设置
        if self.settings.fullscreen:
            pygame.display.set_mode(
                (1920, 1080),  # 使用默认分辨率
                pygame.FULLSCREEN | pygame.DOUBLEBUF
            )
        else:
            width, height = map(int, self.settings.resolution.split('x'))
            pygame.display.set_mode(
                (width, height),
                pygame.RESIZABLE | pygame.DOUBLEBUF
            )

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面"""
        super().on_enter(previous_screen, **kwargs)
        # 更新屏幕引用以确保尺寸正确
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()
        # 重新设置UI以适应可能的窗口大小变化
        self.setup_ui()
        # 确保状态正确
        self.active = True
        self.visible = True
        self.is_animating_out = False
        self.load_settings()
        self.refresh_tab_content()

    def update(self, dt: float):
        """更新界面"""
        super().update(dt)

        if self.background:
            self.background.update(dt)

        # 更新标签页按钮
        for btn in self.tab_buttons.values():
            btn.update(dt)

        # 更新底部按钮
        for btn in self.buttons:
            btn.update(dt)

        # 更新滑块和复选框
        for slider in self.sliders:
            slider.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件"""
        if not self.active:
            return False

        # 处理滑块事件
        for slider in self.sliders:
            if slider.handle_event(event):
                return True

        # 处理复选框事件
        for checkbox in self.checkboxes:
            if checkbox.handle_event(event):
                return True

        # 处理标签页按钮
        for btn in self.tab_buttons.values():
            if btn.handle_event(event):
                return True

        # 处理底部按钮
        for btn in self.buttons:
            if btn.handle_event(event):
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
        scale = min(width / 1280, height / 720)

        # 渲染标题
        if 'title' in self.fonts:
            title = self.fonts['title'].render("设置", True, (220, 230, 255))
            title_rect = title.get_rect(center=(width // 2, max(30, int(40 * scale))))
            screen.blit(title, title_rect)

        # 渲染标签页按钮
        for tab, btn in self.tab_buttons.items():
            # 高亮当前标签
            is_current = tab == self.current_tab
            if is_current:
                # 绘制下划线
                pygame.draw.rect(screen, (100, 150, 220),
                               (btn.rect.x, btn.rect.bottom - 3, btn.rect.width, 3))
            btn.render(screen)

        # 渲染设置内容区域背景 - 按比例缩放
        content_w = max(350, int(500 * scale))
        content_h = max(280, int(350 * scale))
        content_y = max(120, int(140 * scale))
        content_rect = pygame.Rect(width // 2 - content_w // 2, content_y, content_w, content_h)
        pygame.draw.rect(screen, (20, 25, 40, 180), content_rect, border_radius=12)
        pygame.draw.rect(screen, (50, 60, 90), content_rect, 2, border_radius=12)

        # 渲染滑块和复选框
        for slider in self.sliders:
            slider.render(screen)

        for checkbox in self.checkboxes:
            checkbox.render(screen)

        # 渲染底部按钮
        for btn in self.buttons:
            btn.render(screen)

        # 渲染提示文字
        if 'tiny' in self.fonts:
            hint = self.fonts['tiny'].render("* 部分设置需要重启游戏才能生效", True, (120, 130, 150))
            screen.blit(hint, (width // 2 - hint.get_width() // 2, height - 25))
