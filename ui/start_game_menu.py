"""开始游戏菜单 - 提供新游戏、继续游戏、加载存档选项"""

import pygame
import os
from typing import Optional, List, Dict, Tuple
from datetime import datetime

from .screen_manager import Screen, ScreenType
from .initial_menu import StarBackground, MenuButton


class SaveSlot:
    """存档槽位显示"""

    def __init__(self, x: int, y: int, width: int, height: int, slot_id: int):
        self.rect = pygame.Rect(x, y, width, height)
        self.slot_id = slot_id
        self.has_save = False
        self.save_info: Dict = {}
        self.hovered = False
        self.selected = False

        # 尝试读取存档信息
        self._load_save_info()

    def _load_save_info(self):
        """加载存档信息"""
        save_path = f"data/saves/save_{self.slot_id}.json"
        if os.path.exists(save_path):
            try:
                import json
                with open(save_path, 'r', encoding='utf-8') as f:
                    self.save_info = json.load(f)
                    self.has_save = True
            except:
                pass

    def update(self, dt: float):
        """更新存档槽位状态"""
        # 可以在这里添加动画或状态更新
        pass

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件"""
        # 空槽位不响应事件
        if not self.has_save:
            return False

        if event.type == pygame.MOUSEMOTION:
            self.hovered = self.rect.collidepoint(event.pos)

        elif event.type == pygame.MOUSEBUTTONDOWN:
            if self.rect.collidepoint(event.pos):
                self.selected = True
                return True

        return False

    def render(self, screen: pygame.Surface, font: pygame.font.Font,
               small_font: pygame.font.Font):
        """渲染存档槽位"""
        # 背景色
        if self.selected:
            bg_color = (60, 80, 130)
            border_color = (150, 180, 255)
        elif self.hovered:
            bg_color = (50, 60, 100)
            border_color = (120, 140, 200)
        else:
            bg_color = (35, 40, 70)
            border_color = (80, 90, 140)

        # 绘制背景
        pygame.draw.rect(screen, bg_color, self.rect, border_radius=8)
        pygame.draw.rect(screen, border_color, self.rect, 2, border_radius=8)

        # 绘制存档信息
        slot_text = f"存档 {self.slot_id}"
        if self.has_save:
            # 显示存档信息
            time_text = self.save_info.get('save_time', '未知时间')
            day_text = f"第 {self.save_info.get('game_day', 0)} 天"

            slot_surf = font.render(slot_text, True, (200, 210, 255))
            time_surf = small_font.render(time_text, True, (150, 160, 190))
            day_surf = small_font.render(day_text, True, (180, 190, 220))

            screen.blit(slot_surf, (self.rect.x + 15, self.rect.y + 10))
            screen.blit(time_surf, (self.rect.x + 15, self.rect.y + 35))
            screen.blit(day_surf, (self.rect.x + 15, self.rect.y + 55))
        else:
            # 空槽位
            slot_surf = font.render(slot_text, True, (150, 160, 180))
            empty_surf = small_font.render("空槽位", True, (120, 130, 150))

            screen.blit(slot_surf, (self.rect.x + 15, self.rect.y + 15))
            screen.blit(empty_surf, (self.rect.x + 15, self.rect.y + 45))


class StartGameMenu(Screen):
    """开始游戏菜单"""

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.background: Optional[StarBackground] = None
        self.buttons: List[MenuButton] = []
        self.save_slots: List[SaveSlot] = []
        self.showing_save_slots = False
        self.selected_slot: Optional[int] = None
        self.back_button: Optional[MenuButton] = None  # 返回按钮（用于存档界面）
        self.setup_ui()

    def setup_ui(self):
        """设置UI"""
        width, height = self.screen.get_size()

        # 创建星空背景
        self.background = StarBackground(width, height, star_count=250)

        # 创建按钮
        button_width = 280
        button_height = 55
        button_x = width // 2 - button_width // 2
        start_y = height // 2 - 50
        gap = 70

        self.buttons = [
            MenuButton(
                button_x, start_y,
                button_width, button_height,
                "新游戏",
                callback=self.on_new_game,
                font_size=38
            ),
            MenuButton(
                button_x, start_y + gap,
                button_width, button_height,
                "继续游戏",
                callback=self.on_continue_game,
                font_size=38
            ),
            MenuButton(
                button_x, start_y + gap * 2,
                button_width, button_height,
                "加载存档",
                callback=self.on_load_game,
                font_size=38
            ),
            MenuButton(
                button_x, start_y + gap * 3 + 20,
                button_width, button_height,
                "返回",
                callback=self.on_back,
                font_size=38
            ),
        ]

        # 创建存档槽位（用于加载存档）
        self.create_save_slots()

        # 创建返回按钮（用于存档界面）
        self.back_button = MenuButton(
            50, height - 80, 120, 45,
            "← 返回",
            callback=self.on_back,
            font_size=28
        )

        self.load_fonts()

    def create_save_slots(self):
        """创建存档槽位显示"""
        width, height = self.screen.get_size()

        slot_width = 280
        slot_height = 90
        gap = 15

        # 计算位置（居中偏右，给左边留出标题空间）
        start_x = width // 2 - slot_width // 2 + 150
        start_y = height // 2 - (slot_height * 3 + gap * 2) // 2

        self.save_slots = []
        for i in range(6):
            row = i // 2
            col = i % 2
            x = start_x + col * (slot_width + 20)
            y = start_y + row * (slot_height + gap)

            slot = SaveSlot(x, y, slot_width, slot_height, i + 1)
            self.save_slots.append(slot)

    def on_new_game(self):
        """点击新游戏"""
        # 检查是否有存档，提示覆盖
        # TODO: 显示确认对话框
        self.start_new_game()

    def start_new_game(self):
        """开始新游戏"""
        # 重置游戏状态
        self.screen_manager.global_state['game_started'] = True
        self.screen_manager.global_state['current_save_slot'] = None

        # 切换到游戏主界面
        from .screen_manager import ScreenType
        self.screen_manager.switch_to(ScreenType.MAIN_SCREEN)

    def on_continue_game(self):
        """点击继续游戏"""
        # 找到最新的存档
        latest_slot = self.find_latest_save()
        if latest_slot:
            self.load_game(latest_slot)
        else:
            # 没有存档，显示提示
            print("没有可用的存档")
            # TODO: 显示提示信息

    def on_load_game(self):
        """点击加载存档 - 显示存档槽位"""
        self.showing_save_slots = True
        # 刷新存档信息
        for slot in self.save_slots:
            slot._load_save_info()

    def on_back(self):
        """点击返回"""
        if self.showing_save_slots:
            self.showing_save_slots = False
            self.selected_slot = None
        else:
            from .screen_manager import ScreenType
            # 清空栈并返回到初始菜单
            # 这确保不会有残留的游戏状态影响后续操作
            self.screen_manager.clear_stack_and_switch(ScreenType.INITIAL_MENU)

    def find_latest_save(self) -> Optional[int]:
        """找到最新的存档槽位"""
        latest_time = None
        latest_slot = None

        for slot in self.save_slots:
            if slot.has_save:
                save_time = slot.save_info.get('save_time', '')
                if latest_time is None or save_time > latest_time:
                    latest_time = save_time
                    latest_slot = slot.slot_id

        return latest_slot

    def load_game(self, slot_id: int):
        """加载指定存档"""
        print(f"加载存档 {slot_id}")

        # 设置游戏状态
        self.screen_manager.global_state['game_started'] = True
        self.screen_manager.global_state['current_save_slot'] = slot_id

        # 切换到游戏主界面
        from .screen_manager import ScreenType
        self.screen_manager.switch_to(ScreenType.MAIN_SCREEN)

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面"""
        super().on_enter(previous_screen, **kwargs)
        self.showing_save_slots = False
        self.selected_slot = None

        # 更新屏幕引用，确保尺寸正确
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()

        # 刷新存档信息
        for slot in self.save_slots:
            slot._load_save_info()

        # 重新初始化背景（确保窗口大小变化时背景正确）
        width, height = self.screen.get_size()
        self.background = StarBackground(width, height, star_count=250)

        # 重新设置UI
        self.setup_ui()

    def update(self, dt: float):
        """更新界面"""
        super().update(dt)

        if self.background:
            self.background.update(dt)

        for button in self.buttons:
            button.update(dt)

        if self.showing_save_slots:
            for slot in self.save_slots:
                if slot.hovered:
                    slot.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件"""
        if not self.active:
            return False

        # 处理存档槽位事件
        if self.showing_save_slots:
            # 先处理返回按钮
            if self.back_button and self.back_button.handle_event(event):
                return True
            # 处理存档槽位
            for slot in self.save_slots:
                if slot.handle_event(event):
                    if slot.selected and slot.has_save:
                        self.load_game(slot.slot_id)
                    return True
            # 点击空白区域不处理，防止穿透
            if event.type == pygame.MOUSEBUTTONDOWN:
                return True
            return False

        # 处理按钮事件
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

        if not self.showing_save_slots:
            # 渲染标题
            if 'title' in self.fonts:
                # 主标题
                title = self.fonts['title'].render("三体文明", True, (220, 230, 255))
                title_rect = title.get_rect(center=(width // 2, height * 0.15))

                # 发光效果
                for offset, alpha in [(3, 30), (2, 50), (1, 80)]:
                    glow = self.fonts['title'].render("三体文明", True, (150, 170, 220))
                    glow.set_alpha(alpha)
                    for dx, dy in [(-offset, 0), (offset, 0), (0, -offset), (0, offset)]:
                        screen.blit(glow, title_rect.move(dx, dy))

                screen.blit(title, title_rect)

            # 渲染按钮
            for button in self.buttons:
                button.render(screen)

        else:
            # 渲染存档选择界面
            # 标题
            if 'subtitle' in self.fonts:
                title = self.fonts['subtitle'].render("选择存档", True, (220, 230, 255))
                title_rect = title.get_rect(center=(width // 2, 60))
                screen.blit(title, title_rect)

            # 提示文字
            if 'small' in self.fonts:
                hint = self.fonts['small'].render("点击存档槽位加载游戏", True, (150, 160, 180))
                hint_rect = hint.get_rect(center=(width // 2, 100))
                screen.blit(hint, hint_rect)

            # 渲染存档槽位
            from render.ui import get_font
            font = get_font(22)
            small_font = get_font(16)

            for slot in self.save_slots:
                slot.render(screen, font, small_font)

            # 渲染返回按钮
            if self.back_button:
                self.back_button.update(0.016)
                self.back_button.render(screen)
