"""游戏内菜单 - 游戏过程中按ESC打开的菜单"""

import os
import json
import pygame
from typing import Optional, List, Dict
from datetime import datetime

from .screen_manager import Screen, ScreenType
from .initial_menu import MenuButton
from render.ui import get_font
from game.save_manager import SaveManager, SaveInfo


class GameMenu(Screen):
    """游戏内菜单界面"""

    # 保存面板状态
    SAVE_NONE = 0
    SAVE_PANEL = 1    # 显示保存面板

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.buttons: List[MenuButton] = []
        self.overlay_alpha = 0.0
        self.menu_y_offset = -50
        self.save_state = self.SAVE_NONE
        self.save_manager = SaveManager()
        self.save_list: List[SaveInfo] = []

        # 保存面板组件
        self.save_name_input = None
        self.quick_save_btn: Optional[MenuButton] = None
        self.manual_save_btn: Optional[MenuButton] = None
        self.save_close_btn: Optional[MenuButton] = None

        # 消息
        self.save_message = ""
        self.save_message_timer = 0.0

        self.setup_ui()

    def setup_ui(self):
        """设置UI"""
        width, height = self.screen.get_size()
        self.scale = scale = min(width / 1280, height / 720)

        btn_w = max(240, int(280 * scale))
        btn_h = max(45, int(55 * scale))
        btn_x = width // 2 - btn_w // 2
        start_y = int(height * 0.28)
        gap = max(55, int(70 * scale))
        btn_fs = max(24, int(36 * scale))

        self.buttons = [
            MenuButton(btn_x, start_y, btn_w, btn_h,
                       "继续游戏", callback=self.on_resume, font_size=btn_fs),
            MenuButton(btn_x, start_y + gap, btn_w, btn_h,
                       "设置", callback=self.on_settings, font_size=btn_fs),
            MenuButton(btn_x, start_y + gap * 2, btn_w, btn_h,
                       "保存游戏", callback=self.on_save, font_size=btn_fs),
            MenuButton(btn_x, start_y + gap * 3, btn_w, btn_h,
                       "返回主菜单", callback=self.on_main_menu, font_size=btn_fs),
        ]

        # ── 保存面板组件 ──
        panel_w = max(450, int(550 * scale))
        panel_x = (width - panel_w) // 2
        panel_y = int(height * 0.18)

        # 文本输入框
        from .start_game_menu import TextInput
        input_w = max(280, int(360 * scale))
        input_h = max(38, int(46 * scale))
        input_x = (width - input_w) // 2
        self.save_name_input = TextInput(
            input_x, panel_y + int(100 * scale), input_w, input_h,
            placeholder="输入存档名称...",
            font_size=max(16, int(20 * scale)),
            max_length=24,
        )

        small_btn_w = max(100, int(130 * scale))
        small_btn_h = max(34, int(42 * scale))
        small_fs = max(16, int(22 * scale))

        # 保存按钮（输入框下方居中）
        save_row_y = panel_y + int(100 * scale) + input_h + int(15 * scale)
        self.manual_save_btn = MenuButton(
            width // 2 - small_btn_w - int(10 * scale), save_row_y,
            small_btn_w, small_btn_h,
            "保存", callback=self.on_save_game, font_size=small_fs,
        )
        self.save_close_btn = MenuButton(
            width // 2 + int(10 * scale), save_row_y,
            small_btn_w, small_btn_h,
            "关闭", callback=self.on_close_save_panel, font_size=small_fs,
        )

        self.load_fonts()

    def on_resume(self):
        """继续游戏"""
        self.save_state = self.SAVE_NONE
        # 恢复模拟器暂停状态
        simulator = self.screen_manager.global_state.get('simulator')
        if simulator and hasattr(self, 'was_paused'):
            simulator.paused = self.was_paused
        self.screen_manager.go_back()

    def on_settings(self):
        """打开设置"""
        self.save_state = self.SAVE_NONE
        # 设置界面打开时，保持暂停状态即可
        self.screen_manager.switch_to(ScreenType.SETTINGS)

    def on_save(self):
        """弹出保存面板"""
        self.save_state = self.SAVE_PANEL
        self.save_list = self.save_manager.scan_saves()
        # 预填存档名
        simulator = self.screen_manager.global_state.get('simulator')
        if simulator:
            day = max(1, int(simulator.time))
            self.save_name_input.text = f"{simulator.universe_name}_Day{day}"
        self.save_name_input.active = True

    def on_save_game(self):
        """保存游戏（统一入口）"""
        name = self.save_name_input.text.strip()
        if not name:
            self.save_message = "请输入存档名称"
            self.save_message_timer = 2.0
            return

        simulator = self.screen_manager.global_state.get('simulator')
        if not simulator:
            self.save_message = "没有游戏数据"
            self.save_message_timer = 2.0
            return

        success, msg = self.save_manager.save_game(simulator, name)
        self.save_message = msg
        self.save_message_timer = 2.5
        if success:
            self.save_list = self.save_manager.scan_saves()

    def on_close_save_panel(self):
        """关闭保存面板"""
        self.save_state = self.SAVE_NONE

    def on_main_menu(self):
        """返回主菜单"""
        self.save_state = self.SAVE_NONE
        if self.screen_manager.current_screen:
            self.screen_manager.current_screen.is_animating_out = False
            self.screen_manager.current_screen.animation_progress = 1.0
        self.screen_manager.clear_stack_and_switch(ScreenType.INITIAL_MENU)

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        super().on_enter(previous_screen, **kwargs)
        self.overlay_alpha = 0.0
        self.menu_y_offset = -50
        self.save_state = self.SAVE_NONE
        self.save_message = ""
        self.save_message_timer = 0.0
        
        # 打开菜单时暂停游戏
        simulator = self.screen_manager.global_state.get('simulator')
        if simulator:
            self.was_paused = simulator.paused
            simulator.paused = True
            
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()
        self.setup_ui()

    def update(self, dt: float):
        super().update(dt)
        if self.overlay_alpha < 0.7:
            self.overlay_alpha = min(0.7, self.overlay_alpha + dt * 3)
        if self.menu_y_offset < 0:
            self.menu_y_offset = min(0, self.menu_y_offset + dt * 200)
        for button in self.buttons:
            button.update(dt)
        if self.save_message_timer > 0:
            self.save_message_timer -= dt
            if self.save_message_timer <= 0:
                self.save_message = ""
        if self.save_name_input:
            self.save_name_input.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        if not self.active:
            return False

        # 保存面板
        if self.save_state == self.SAVE_PANEL:
            return self._handle_save_panel_event(event)

        # 主菜单按钮
        for button in self.buttons:
            if button.handle_event(event):
                return True

        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self.on_resume()
                return True

        return False

    def _handle_save_panel_event(self, event) -> bool:
        if self.save_name_input and self.save_name_input.handle_event(event):
            return True
        if self.manual_save_btn and self.manual_save_btn.handle_event(event):
            return True
        if self.save_close_btn and self.save_close_btn.handle_event(event):
            return True

        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self.on_close_save_panel()
                return True
            if event.key == pygame.K_RETURN:
                self.on_save_game()
                return True

        return True  # 拦截所有事件

    def render(self, screen: pygame.Surface):
        if not self.visible:
            return

        # 半透明遮罩
        overlay = pygame.Surface(screen.get_size())
        overlay.fill((0, 0, 0))
        overlay.set_alpha(int(self.overlay_alpha * 255))
        screen.blit(overlay, (0, 0))

        width, height = screen.get_size()
        scale = self.scale

        # 标题
        if 'subtitle' in self.fonts:
            title = self.fonts['subtitle'].render("游戏菜单", True, (220, 230, 255))
            title_rect = title.get_rect(center=(width // 2, int(height * 0.12) + self.menu_y_offset))
            screen.blit(title, title_rect)

        # 按钮（带滑入动画）
        for button in self.buttons:
            original_y = button.rect.y
            button.rect.y = int(original_y + self.menu_y_offset)
            button.render(screen)
            button.rect.y = original_y

        # 保存面板
        if self.save_state == self.SAVE_PANEL:
            self._render_save_panel(screen, width, height, scale)

        # 保存消息
        if self.save_message:
            self._render_save_message(screen, width, height, scale)

    def _render_save_panel(self, screen, width, height, scale):
        """渲染保存面板"""
        # 遮罩
        dark = pygame.Surface((width, height), pygame.SRCALPHA)
        dark.fill((0, 0, 0, 140))
        screen.blit(dark, (0, 0))

        # 面板背景
        panel_w = max(450, int(520 * scale))
        panel_h = max(260, int(300 * scale))
        panel_x = (width - panel_w) // 2
        panel_y = int(height * 0.18)

        pygame.draw.rect(screen, (25, 30, 50),
                         (panel_x, panel_y, panel_w, panel_h), border_radius=12)
        pygame.draw.rect(screen, (80, 100, 170),
                         (panel_x, panel_y, panel_w, panel_h), 2, border_radius=12)

        # 标题
        title_font = get_font(max(20, int(26 * scale)))
        title = title_font.render("保存游戏", True, (220, 230, 255))
        title_rect = title.get_rect(center=(width // 2, panel_y + int(28 * scale)))
        screen.blit(title, title_rect)

        # 当前宇宙信息
        simulator = self.screen_manager.global_state.get('simulator')
        if simulator:
            info_font = get_font(max(13, int(16 * scale)))
            info = info_font.render(
                f"宇宙: {simulator.universe_name}  |  第{max(1, int(simulator.time))}天",
                True, (150, 170, 200))
            info_rect = info.get_rect(center=(width // 2, panel_y + int(55 * scale)))
            screen.blit(info, info_rect)

        # 存档名称提示
        label_font = get_font(max(13, int(15 * scale)))
        label = label_font.render("存档名称:", True, (140, 150, 180))
        screen.blit(label, (self.save_name_input.rect.x, self.save_name_input.rect.y - int(20 * scale)))

        # 输入框
        self.save_name_input.render(screen)

        # 保存 + 关闭按钮
        self.manual_save_btn.update(0.016)
        self.manual_save_btn.render(screen)
        self.save_close_btn.update(0.016)
        self.save_close_btn.render(screen)

        # 最近存档列表
        if self.save_list:
            list_y = self.manual_save_btn.rect.bottom + max(15, int(20 * scale))
            list_font = get_font(max(11, int(13 * scale)))
            header = list_font.render("最近存档:", True, (100, 120, 150))
            screen.blit(header, (panel_x + 30, list_y))
            list_y += list_font.get_height() + 3

            for i, save in enumerate(self.save_list[:3]):
                text = f"• {save.save_name}  ({save.save_time})"
                surf = list_font.render(text, True, (120, 130, 160))
                screen.blit(surf, (panel_x + 30, list_y + i * (list_font.get_height() + 2)))

    def _render_save_message(self, screen, width, height, scale):
        """渲染保存提示"""
        msg_font = get_font(max(16, int(22 * scale)))
        msg_surf = msg_font.render(self.save_message, True, (100, 255, 150))
        msg_w = msg_surf.get_width() + 40
        msg_h = msg_surf.get_height() + 16
        msg_x = (width - msg_w) // 2
        msg_y = height - max(60, int(70 * scale))

        bg = pygame.Surface((msg_w, msg_h), pygame.SRCALPHA)
        bg.fill((20, 40, 30, 200))
        screen.blit(bg, (msg_x, msg_y))
        pygame.draw.rect(screen, (80, 180, 100),
                         (msg_x, msg_y, msg_w, msg_h), 1, border_radius=6)

        msg_rect = msg_surf.get_rect(center=(width // 2, msg_y + msg_h // 2))
        screen.blit(msg_surf, msg_rect)
