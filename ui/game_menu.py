"""游戏内菜单 - 游戏过程中按ESC打开的菜单"""

import os
import json
import pygame
from typing import Optional, List, Dict
from datetime import datetime

from .screen_manager import Screen, ScreenType
from .initial_menu import MenuButton
from render.ui import get_font


class GameMenu(Screen):
    """游戏内菜单界面"""

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.buttons: List[MenuButton] = []
        self.overlay_alpha = 0.0
        self.menu_y_offset = -50
        self.showing_save_slots = False  # 是否显示存档选择
        self.save_slots_info: List[Dict] = []  # 6个槽位信息
        self.save_slot_rects: List[pygame.Rect] = []  # 槽位点击区域
        self.save_slot_hovered: int = -1  # 当前悬停的槽位
        self.save_message = ""  # 保存提示消息
        self.save_message_timer = 0.0
        self.setup_ui()

    def setup_ui(self):
        """设置UI"""
        width, height = self.screen.get_size()

        button_width = 280
        button_height = 55
        button_x = width // 2 - button_width // 2
        start_y = height // 2 - 120
        gap = 70

        self.buttons = [
            MenuButton(
                button_x, start_y,
                button_width, button_height,
                "继续游戏",
                callback=self.on_resume,
                font_size=36
            ),
            MenuButton(
                button_x, start_y + gap,
                button_width, button_height,
                "设置",
                callback=self.on_settings,
                font_size=36
            ),
            MenuButton(
                button_x, start_y + gap * 2,
                button_width, button_height,
                "保存游戏",
                callback=self.on_save,
                font_size=36
            ),
            MenuButton(
                button_x, start_y + gap * 3,
                button_width, button_height,
                "返回主菜单",
                callback=self.on_main_menu,
                font_size=36
            ),
        ]

        self.load_fonts()

    def on_resume(self):
        """继续游戏"""
        self.showing_save_slots = False
        self.screen_manager.go_back()

    def on_settings(self):
        """打开设置"""
        self.showing_save_slots = False
        from .screen_manager import ScreenType
        self.screen_manager.switch_to(ScreenType.SETTINGS)

    def on_save(self):
        """保存游戏 - 打开存档槽位选择"""
        self.showing_save_slots = True
        self._refresh_save_slots()

    def _refresh_save_slots(self):
        """刷新存档槽位信息"""
        self.save_slots_info = []
        for i in range(1, 7):
            save_path = f'data/saves/save_{i}.json'
            info = {'slot': i, 'has_save': False}
            if os.path.exists(save_path):
                try:
                    with open(save_path, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                    info['has_save'] = True
                    info['save_time'] = data.get('save_time', '未知时间')
                    info['game_day'] = data.get('game_day', 0)
                except Exception:
                    pass
            self.save_slots_info.append(info)

    def save_game(self, slot: int):
        """保存游戏到指定槽位"""
        # 获取实际游戏状态
        simulator = self.screen_manager.global_state.get('simulator')
        game_state = {}
        game_day = 1
        if simulator:
            game_state = simulator.to_dict()
            game_day = max(1, int(simulator.time / 60))  # 大致转换为天数

        save_data = {
            'slot': slot,
            'save_time': datetime.now().strftime('%Y-%m-%d %H:%M'),
            'game_day': game_day,
            'game_state': game_state,
        }

        os.makedirs('data/saves', exist_ok=True)
        save_path = f'data/saves/save_{slot}.json'

        try:
            with open(save_path, 'w', encoding='utf-8') as f:
                json.dump(save_data, f, indent=2, ensure_ascii=False)
            self.screen_manager.global_state['current_save_slot'] = slot
            self.save_message = f"已保存到槽位 {slot}"
            self.save_message_timer = 2.0
            print(f"游戏已保存到槽位 {slot}")
            # 刷新槽位信息显示
            self._refresh_save_slots()
        except Exception as e:
            self.save_message = f"保存失败: {e}"
            self.save_message_timer = 3.0
            print(f"保存失败: {e}")

    def on_main_menu(self):
        """返回主菜单"""
        self.showing_save_slots = False
        # TODO: 如果有未保存的更改，显示确认对话框
        from .screen_manager import ScreenType
        # 使用清空栈的方式切换，避免栈污染
        # 同时确保退出动画状态被正确重置
        if self.screen_manager.current_screen:
            self.screen_manager.current_screen.is_animating_out = False
            self.screen_manager.current_screen.animation_progress = 1.0
        self.screen_manager.clear_stack_and_switch(ScreenType.INITIAL_MENU)

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面"""
        super().on_enter(previous_screen, **kwargs)
        # 重置动画状态
        self.overlay_alpha = 0.0
        self.menu_y_offset = -50
        self.showing_save_slots = False
        self.save_message = ""
        self.save_message_timer = 0.0
        # 更新屏幕引用，确保尺寸正确
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()
        # 重新设置UI
        self.setup_ui()

    def update(self, dt: float):
        """更新界面"""
        super().update(dt)

        # 淡入效果
        if self.overlay_alpha < 0.7:
            self.overlay_alpha = min(0.7, self.overlay_alpha + dt * 3)

        # 菜单滑入效果
        if self.menu_y_offset < 0:
            self.menu_y_offset = min(0, self.menu_y_offset + dt * 200)

        for button in self.buttons:
            button.update(dt)

        # 消息计时
        if self.save_message_timer > 0:
            self.save_message_timer -= dt
            if self.save_message_timer <= 0:
                self.save_message = ""

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件"""
        if not self.active:
            return False

        # 如果显示存档选择面板
        if self.showing_save_slots:
            if event.type == pygame.MOUSEMOTION:
                self.save_slot_hovered = -1
                for i, rect in enumerate(self.save_slot_rects):
                    if rect.collidepoint(event.pos):
                        self.save_slot_hovered = i
                        break
                return True

            if event.type == pygame.MOUSEBUTTONDOWN:
                # 检查是否点击了某个槽位
                for i, rect in enumerate(self.save_slot_rects):
                    if rect.collidepoint(event.pos):
                        self.save_game(i + 1)
                        return True
                # 点击面板外部关闭
                width, height = self.screen.get_size()
                panel_w = max(400, int(width * 0.45))
                panel_h = max(380, int(height * 0.6))
                panel_x = (width - panel_w) // 2
                panel_y = (height - panel_h) // 2
                panel_rect = pygame.Rect(panel_x, panel_y, panel_w, panel_h)
                if not panel_rect.collidepoint(event.pos):
                    self.showing_save_slots = False
                return True

            if event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    self.showing_save_slots = False
                    return True

            return True  # 吞掉所有事件，防止穿透

        # 处理按钮事件
        for button in self.buttons:
            if button.handle_event(event):
                return True

        # ESC关闭菜单
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self.on_resume()
                return True

        return False

    def render(self, screen: pygame.Surface):
        """渲染界面"""
        if not self.visible:
            return

        # 绘制半透明遮罩
        overlay = pygame.Surface(screen.get_size())
        overlay.fill((0, 0, 0))
        overlay.set_alpha(int(self.overlay_alpha * 255))
        screen.blit(overlay, (0, 0))

        width, height = screen.get_size()

        # 渲染标题
        if 'subtitle' in self.fonts:
            title = self.fonts['subtitle'].render("游戏菜单", True, (220, 230, 255))
            title_rect = title.get_rect(center=(width // 2, 80 + self.menu_y_offset))
            screen.blit(title, title_rect)

        # 渲染按钮（带滑入动画）
        for button in self.buttons:
            original_y = button.rect.y
            button.rect.y = int(original_y + self.menu_y_offset)
            button.render(screen)
            button.rect.y = original_y

        # 渲染存档选择面板
        if self.showing_save_slots:
            self._render_save_panel(screen)

        # 渲染保存消息
        if self.save_message:
            self._render_save_message(screen)

    def _render_save_panel(self, screen: pygame.Surface):
        """渲染存档选择面板"""
        width, height = screen.get_size()
        scale = min(width / 1280, height / 720)

        # 面板尺寸和位置
        panel_w = max(400, int(width * 0.45))
        panel_h = max(380, int(height * 0.6))
        panel_x = (width - panel_w) // 2
        panel_y = (height - panel_h) // 2

        # 半透明背景遮罩（加深）
        dark_overlay = pygame.Surface((width, height))
        dark_overlay.fill((0, 0, 0))
        dark_overlay.set_alpha(120)
        screen.blit(dark_overlay, (0, 0))

        # 面板背景
        pygame.draw.rect(screen, (25, 30, 50), (panel_x, panel_y, panel_w, panel_h), border_radius=12)
        pygame.draw.rect(screen, (80, 100, 160), (panel_x, panel_y, panel_w, panel_h), 2, border_radius=12)

        # 标题
        title_font_size = max(22, int(30 * scale))
        title_font = get_font(title_font_size)
        title_surf = title_font.render("选择保存槽位", True, (220, 230, 255))
        title_rect = title_surf.get_rect(center=(width // 2, panel_y + max(25, int(panel_h * 0.06))))
        screen.blit(title_surf, title_rect)

        # 提示
        hint_font_size = max(13, int(16 * scale))
        hint_font = get_font(hint_font_size)
        hint_surf = hint_font.render("点击槽位保存游戏，已有存档将被覆盖", True, (150, 160, 180))
        hint_rect = hint_surf.get_rect(center=(width // 2, panel_y + max(50, int(panel_h * 0.13))))
        screen.blit(hint_surf, hint_rect)

        # 存档槽位
        slot_font_size = max(16, int(22 * scale))
        slot_small_font_size = max(12, int(16 * scale))
        slot_font = get_font(slot_font_size)
        slot_small_font = get_font(slot_small_font_size)

        slot_w = max(160, int(panel_w * 0.42))
        slot_h = max(65, int(panel_h * 0.15))
        gap_x = max(10, int(panel_w * 0.04))
        gap_y = max(10, int(panel_h * 0.03))

        cols = 2
        total_slots_w = slot_w * cols + gap_x
        slots_start_x = panel_x + (panel_w - total_slots_w) // 2
        slots_start_y = panel_y + max(75, int(panel_h * 0.2))

        self.save_slot_rects = []

        for i, info in enumerate(self.save_slots_info):
            row = i // cols
            col = i % cols
            sx = slots_start_x + col * (slot_w + gap_x)
            sy = slots_start_y + row * (slot_h + gap_y)
            rect = pygame.Rect(sx, sy, slot_w, slot_h)
            self.save_slot_rects.append(rect)

            # 颜色
            if self.save_slot_hovered == i:
                bg = (55, 65, 110)
                border = (130, 150, 220)
            else:
                bg = (35, 42, 75)
                border = (70, 85, 130)

            pygame.draw.rect(screen, bg, rect, border_radius=8)
            pygame.draw.rect(screen, border, rect, 2, border_radius=8)

            # 当前槽位标记
            current_slot = self.screen_manager.global_state.get('current_save_slot')
            pad = max(8, int(slot_w * 0.04))

            slot_label = f"槽位 {info['slot']}"
            if current_slot == info['slot']:
                slot_label += " ★"

            label_surf = slot_font.render(slot_label, True, (200, 210, 255))
            screen.blit(label_surf, (sx + pad, sy + int(slot_h * 0.12)))

            if info['has_save']:
                detail = f"{info.get('save_time', '')} · 第{info.get('game_day', 0)}天"
                detail_surf = slot_small_font.render(detail, True, (150, 160, 190))
                screen.blit(detail_surf, (sx + pad, sy + int(slot_h * 0.55)))
            else:
                empty_surf = slot_small_font.render("空槽位", True, (100, 110, 140))
                screen.blit(empty_surf, (sx + pad, sy + int(slot_h * 0.55)))

        # 底部关闭提示
        close_font = get_font(max(12, int(15 * scale)))
        close_surf = close_font.render("按 ESC 或点击面板外部关闭", True, (120, 130, 160))
        close_rect = close_surf.get_rect(center=(width // 2, panel_y + panel_h - max(18, int(panel_h * 0.05))))
        screen.blit(close_surf, close_rect)

    def _render_save_message(self, screen: pygame.Surface):
        """渲染保存提示消息"""
        width, height = screen.get_size()
        scale = min(width / 1280, height / 720)
        msg_font_size = max(16, int(22 * scale))
        msg_font = get_font(msg_font_size)

        # 带背景的消息条
        msg_surf = msg_font.render(self.save_message, True, (100, 255, 150))
        msg_w = msg_surf.get_width() + 40
        msg_h = msg_surf.get_height() + 16
        msg_x = (width - msg_w) // 2
        msg_y = height - max(60, int(height * 0.08))

        # 半透明背景
        bg = pygame.Surface((msg_w, msg_h))
        bg.fill((20, 40, 30))
        bg.set_alpha(200)
        screen.blit(bg, (msg_x, msg_y))
        pygame.draw.rect(screen, (80, 180, 100), (msg_x, msg_y, msg_w, msg_h), 1, border_radius=6)

        msg_rect = msg_surf.get_rect(center=(width // 2, msg_y + msg_h // 2))
        screen.blit(msg_surf, msg_rect)
