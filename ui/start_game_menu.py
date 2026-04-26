"""开始游戏菜单 - 新游戏（命名宇宙）、继续游戏、加载/删除存档"""

import pygame
import os
from typing import Optional, List, Dict, Tuple
from datetime import datetime

from .screen_manager import Screen, ScreenType
from .initial_menu import StarBackground, MenuButton
from render.ui import get_font
from game.save_manager import SaveManager, SaveInfo


class TextInput:
    """简易文本输入框组件"""

    def __init__(self, x: int, y: int, width: int, height: int,
                 placeholder: str = "", font_size: int = 24,
                 max_length: int = 20):
        self.rect = pygame.Rect(x, y, width, height)
        self.text = ""
        self.placeholder = placeholder
        self.active = False
        self.max_length = max_length
        self.cursor_visible = True
        self.cursor_timer = 0.0
        self.font = get_font(font_size)

    def handle_event(self, event: pygame.event.Event) -> bool:
        if event.type == pygame.MOUSEBUTTONDOWN:
            self.active = self.rect.collidepoint(event.pos)
            return self.active

        if not self.active:
            return False

        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_BACKSPACE:
                self.text = self.text[:-1]
                return True
            elif event.key == pygame.K_RETURN:
                return False  # 让外部处理回车
            elif event.key == pygame.K_ESCAPE:
                self.active = False
                return True

        # 使用 TEXTINPUT 事件支持中文输入法
        if event.type == pygame.TEXTINPUT:
            if len(self.text) < self.max_length:
                self.text += event.text
            return True

        return False

    def update(self, dt: float):
        self.cursor_timer += dt
        if self.cursor_timer > 0.5:
            self.cursor_visible = not self.cursor_visible
            self.cursor_timer = 0.0

    def render(self, screen: pygame.Surface):
        # 背景
        bg_color = (30, 40, 65) if self.active else (25, 30, 50)
        border_color = (100, 150, 255) if self.active else (60, 70, 100)
        pygame.draw.rect(screen, bg_color, self.rect, border_radius=6)
        pygame.draw.rect(screen, border_color, self.rect, 2, border_radius=6)

        # 文字
        pad = 10
        if self.text:
            text_surf = self.font.render(self.text, True, (220, 230, 255))
        else:
            text_surf = self.font.render(self.placeholder, True, (80, 90, 120))
        # 裁剪文字宽度
        max_text_w = self.rect.width - pad * 2
        screen.blit(text_surf, (self.rect.x + pad,
                                self.rect.y + (self.rect.height - text_surf.get_height()) // 2),
                     area=pygame.Rect(0, 0, min(text_surf.get_width(), max_text_w),
                                      text_surf.get_height()))

        # 光标
        if self.active and self.cursor_visible:
            cursor_x = self.rect.x + pad + min(text_surf.get_width() if self.text else 0, max_text_w)
            cursor_y1 = self.rect.y + 6
            cursor_y2 = self.rect.y + self.rect.height - 6
            pygame.draw.line(screen, (200, 220, 255), (cursor_x, cursor_y1), (cursor_x, cursor_y2), 2)


class StartGameMenu(Screen):
    """开始游戏菜单"""

    # 子界面状态
    STATE_MAIN = 0           # 主菜单（新游戏/继续/加载/返回）
    STATE_NAMING = 1         # 新游戏命名
    STATE_LOAD = 2           # 加载存档列表

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.background: Optional[StarBackground] = None
        self.buttons: List[MenuButton] = []
        self.state = self.STATE_MAIN

        # 存档管理
        self.save_manager = SaveManager()
        self.save_list: List[SaveInfo] = []
        self.scroll_offset = 0
        self.selected_save_idx = -1

        # 命名输入
        self.name_input: Optional[TextInput] = None
        self.confirm_button: Optional[MenuButton] = None
        self.cancel_button: Optional[MenuButton] = None

        # 加载界面按钮
        self.load_btn: Optional[MenuButton] = None
        self.delete_btn: Optional[MenuButton] = None
        self.back_button: Optional[MenuButton] = None

        # 消息
        self.message = ""
        self.message_timer = 0.0
        self.message_color = (255, 200, 100)

        # 删除确认
        self.confirm_delete = False
        self.delete_confirm_btn: Optional[MenuButton] = None
        self.delete_cancel_btn: Optional[MenuButton] = None

        self.setup_ui()

    def setup_ui(self):
        """设置UI"""
        width, height = self.screen.get_size()
        self.scale = scale = min(width / 1280, height / 720)

        # 创建星空背景
        self.background = StarBackground(width, height, star_count=250)

        # ── 主菜单按钮 ──
        btn_w = max(240, int(280 * scale))
        btn_h = max(45, int(55 * scale))
        btn_x = width // 2 - btn_w // 2
        start_y = int(height * 0.38)
        gap = max(55, int(70 * scale))
        btn_fs = max(24, int(36 * scale))

        self.buttons = [
            MenuButton(btn_x, start_y, btn_w, btn_h,
                       "新游戏", callback=self.on_new_game, font_size=btn_fs),
            MenuButton(btn_x, start_y + gap, btn_w, btn_h,
                       "继续游戏", callback=self.on_continue_game, font_size=btn_fs),
            MenuButton(btn_x, start_y + gap * 2, btn_w, btn_h,
                       "加载存档", callback=self.on_load_game, font_size=btn_fs),
            MenuButton(btn_x, start_y + gap * 3 + int(15 * scale), btn_w, btn_h,
                       "返回", callback=self.on_back, font_size=btn_fs),
        ]

        # ── 命名界面 ──
        input_w = max(300, int(400 * scale))
        input_h = max(40, int(50 * scale))
        input_x = width // 2 - input_w // 2
        input_y = int(height * 0.45)
        self.name_input = TextInput(
            input_x, input_y, input_w, input_h,
            placeholder="输入宇宙名称...",
            font_size=max(18, int(24 * scale)),
            max_length=16,
        )

        small_btn_w = max(120, int(150 * scale))
        small_btn_h = max(36, int(44 * scale))
        small_fs = max(18, int(24 * scale))
        btn_gap = int(30 * scale)
        confirm_y = input_y + input_h + int(25 * scale)
        self.confirm_button = MenuButton(
            width // 2 - small_btn_w - btn_gap // 2, confirm_y,
            small_btn_w, small_btn_h,
            "开始", callback=self.on_confirm_name, font_size=small_fs,
        )
        self.cancel_button = MenuButton(
            width // 2 + btn_gap // 2, confirm_y,
            small_btn_w, small_btn_h,
            "取消", callback=self.on_cancel_name, font_size=small_fs,
        )

        # ── 加载界面底部按钮 ──
        toolbar_y = height - max(60, int(70 * scale))
        tb_btn_w = max(100, int(130 * scale))
        tb_btn_h = max(36, int(44 * scale))
        tb_fs = max(16, int(22 * scale))

        self.back_button = MenuButton(
            int(20 * scale), toolbar_y, tb_btn_w, tb_btn_h,
            "← 返回", callback=self.on_back_from_load, font_size=tb_fs,
        )
        self.load_btn = MenuButton(
            width // 2 - tb_btn_w - int(10 * scale), toolbar_y,
            tb_btn_w, tb_btn_h,
            "加载", callback=self.on_load_selected, font_size=tb_fs,
        )
        self.delete_btn = MenuButton(
            width // 2 + int(10 * scale), toolbar_y,
            tb_btn_w, tb_btn_h,
            "删除", callback=self.on_delete_selected, font_size=tb_fs,
        )

        # ── 删除确认按钮 ──
        dc_y = int(height * 0.55)
        self.delete_confirm_btn = MenuButton(
            width // 2 - small_btn_w - btn_gap // 2, dc_y,
            small_btn_w, small_btn_h,
            "确认删除", callback=self.on_confirm_delete, font_size=small_fs,
        )
        self.delete_cancel_btn = MenuButton(
            width // 2 + btn_gap // 2, dc_y,
            small_btn_w, small_btn_h,
            "取消", callback=self.on_cancel_delete, font_size=small_fs,
        )

        self.load_fonts()

    # ── 主菜单回调 ──────────────────────────────────

    def on_new_game(self):
        """点击新游戏 → 进入命名界面"""
        self.state = self.STATE_NAMING
        self.name_input.text = ""
        self.name_input.active = True

    def on_continue_game(self):
        """继续最新存档"""
        latest = self.save_manager.find_latest_save()
        if latest:
            self._load_save(latest.filepath)
        else:
            self.message = "没有可用的存档"
            self.message_color = (255, 150, 100)
            self.message_timer = 2.5

    def on_load_game(self):
        """进入加载存档列表"""
        self.state = self.STATE_LOAD
        self.save_list = self.save_manager.scan_saves()
        self.scroll_offset = 0
        self.selected_save_idx = -1
        self.confirm_delete = False

    def on_back(self):
        """返回初始菜单"""
        if self.state != self.STATE_MAIN:
            self.state = self.STATE_MAIN
            self.confirm_delete = False
        else:
            self.screen_manager.clear_stack_and_switch(ScreenType.INITIAL_MENU)

    # ── 命名界面回调 ──────────────────────────────────

    def on_confirm_name(self):
        """确认宇宙名称，开始新游戏"""
        name = self.name_input.text.strip()
        if not name:
            self.message = "请输入宇宙名称"
            self.message_color = (255, 150, 100)
            self.message_timer = 2.0
            return

        self._start_new_game(name)

    def on_cancel_name(self):
        """取消命名，返回主菜单"""
        self.state = self.STATE_MAIN

    def _start_new_game(self, universe_name: str):
        """开始新游戏"""
        self.screen_manager.global_state['game_started'] = True

        from game.simulator import GameSimulator
        simulator = self.screen_manager.global_state.get('simulator')
        if simulator:
            simulator.reset()
        else:
            simulator = GameSimulator()
            self.screen_manager.global_state['simulator'] = simulator

        simulator.universe_name = universe_name
        self.screen_manager.switch_to(ScreenType.MAIN_SCREEN)

    # ── 加载界面回调 ──────────────────────────────────

    def on_back_from_load(self):
        """从加载界面返回"""
        self.state = self.STATE_MAIN
        self.confirm_delete = False

    def on_load_selected(self):
        """加载选中的存档"""
        if 0 <= self.selected_save_idx < len(self.save_list):
            save = self.save_list[self.selected_save_idx]
            self._load_save(save.filepath)

    def on_delete_selected(self):
        """请求删除选中的存档"""
        if 0 <= self.selected_save_idx < len(self.save_list):
            self.confirm_delete = True

    def on_confirm_delete(self):
        """确认删除"""
        if 0 <= self.selected_save_idx < len(self.save_list):
            save = self.save_list[self.selected_save_idx]
            success, msg = self.save_manager.delete_save(save.filepath)
            self.message = msg
            self.message_color = (150, 255, 150) if success else (255, 100, 100)
            self.message_timer = 2.0
            # 刷新列表
            self.save_list = self.save_manager.scan_saves()
            self.selected_save_idx = -1
        self.confirm_delete = False

    def on_cancel_delete(self):
        """取消删除"""
        self.confirm_delete = False

    def _load_save(self, filepath: str):
        """加载存档并进入游戏"""
        self.screen_manager.global_state['game_started'] = True

        from game.simulator import GameSimulator
        simulator = self.screen_manager.global_state.get('simulator')
        if not simulator:
            simulator = GameSimulator()
            self.screen_manager.global_state['simulator'] = simulator

        success, msg = self.save_manager.load_game(filepath, simulator)
        if success:
            print(msg)
            self.screen_manager.switch_to(ScreenType.MAIN_SCREEN)
        else:
            self.message = msg
            self.message_color = (255, 100, 100)
            self.message_timer = 3.0

    # ── 生命周期 ──────────────────────────────────

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        super().on_enter(previous_screen, **kwargs)
        self.state = self.STATE_MAIN
        self.confirm_delete = False
        self.message = ""
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()
        width, height = self.screen.get_size()
        self.background = StarBackground(width, height, star_count=250)
        self.setup_ui()

    def update(self, dt: float):
        super().update(dt)
        if self.background:
            self.background.update(dt)
        for btn in self.buttons:
            btn.update(dt)
        if self.name_input:
            self.name_input.update(dt)
        if self.message_timer > 0:
            self.message_timer -= dt

    def handle_event(self, event: pygame.event.Event) -> bool:
        if not self.active:
            return False

        if self.state == self.STATE_MAIN:
            return self._handle_main_event(event)
        elif self.state == self.STATE_NAMING:
            return self._handle_naming_event(event)
        elif self.state == self.STATE_LOAD:
            return self._handle_load_event(event)

        return False

    def _handle_main_event(self, event) -> bool:
        for btn in self.buttons:
            if btn.handle_event(event):
                return True
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            self.on_back()
            return True
        return False

    def _handle_naming_event(self, event) -> bool:
        if self.name_input and self.name_input.handle_event(event):
            return True
        if self.confirm_button and self.confirm_button.handle_event(event):
            return True
        if self.cancel_button and self.cancel_button.handle_event(event):
            return True
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_RETURN:
                self.on_confirm_name()
                return True
            if event.key == pygame.K_ESCAPE:
                self.on_cancel_name()
                return True
        return False

    def _handle_load_event(self, event) -> bool:
        # 删除确认对话框
        if self.confirm_delete:
            if self.delete_confirm_btn and self.delete_confirm_btn.handle_event(event):
                return True
            if self.delete_cancel_btn and self.delete_cancel_btn.handle_event(event):
                return True
            if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                self.on_cancel_delete()
                return True
            return True  # 拦截所有

        # 底部工具栏
        if self.back_button and self.back_button.handle_event(event):
            return True
        if self.load_btn and self.load_btn.handle_event(event):
            return True
        if self.delete_btn and self.delete_btn.handle_event(event):
            return True

        # 滚轮滚动
        if event.type == pygame.MOUSEWHEEL:
            self.scroll_offset = max(0, self.scroll_offset - event.y * 40)
            return True

        # 点击选择存档
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            idx = self._get_save_at_mouse(event.pos)
            if idx >= 0:
                self.selected_save_idx = idx
                return True

        # 双击加载
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            # pygame 没有原生双击，先跳过
            pass

        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self.on_back_from_load()
                return True
            if event.key == pygame.K_DELETE:
                self.on_delete_selected()
                return True
            if event.key == pygame.K_RETURN:
                self.on_load_selected()
                return True

        return False

    def _get_save_at_mouse(self, pos: Tuple[int, int]) -> int:
        """根据鼠标位置找到对应的存档索引"""
        width, height = self.screen.get_size()
        scale = self.scale

        list_x = int(width * 0.08)
        list_y = int(height * 0.15)
        list_w = int(width * 0.84)
        item_h = max(60, int(70 * scale))
        gap = max(6, int(8 * scale))

        mx, my = pos
        if mx < list_x or mx > list_x + list_w:
            return -1
        if my < list_y:
            return -1

        for i in range(len(self.save_list)):
            iy = list_y + i * (item_h + gap) - self.scroll_offset
            if iy < list_y - item_h or iy > height - 80:
                continue
            if iy <= my <= iy + item_h:
                return i
        return -1

    # ── 渲染 ──────────────────────────────────

    def render(self, screen: pygame.Surface):
        if not self.visible:
            return

        if self.background:
            self.background.render(screen)

        width, height = screen.get_size()
        scale = self.scale

        if self.state == self.STATE_MAIN:
            self._render_main(screen, width, height, scale)
        elif self.state == self.STATE_NAMING:
            self._render_naming(screen, width, height, scale)
        elif self.state == self.STATE_LOAD:
            self._render_load(screen, width, height, scale)

        # 消息
        if self.message_timer > 0 and self.message:
            msg_font = get_font(max(16, int(22 * scale)))
            msg_surf = msg_font.render(self.message, True, self.message_color)
            msg_rect = msg_surf.get_rect(center=(width // 2, height - max(30, int(40 * scale))))
            # 带背景
            bg = pygame.Surface((msg_surf.get_width() + 30, msg_surf.get_height() + 12), pygame.SRCALPHA)
            bg.fill((0, 0, 0, 180))
            screen.blit(bg, (msg_rect.x - 15, msg_rect.y - 6))
            screen.blit(msg_surf, msg_rect)

    def _render_main(self, screen, width, height, scale):
        """渲染主菜单"""
        # 标题
        if 'title' in self.fonts:
            title = self.fonts['title'].render("三体文明", True, (220, 230, 255))
            title_rect = title.get_rect(center=(width // 2, int(height * 0.15)))
            # 发光
            for offset, alpha in [(3, 30), (2, 50), (1, 80)]:
                glow = self.fonts['title'].render("三体文明", True, (150, 170, 220))
                glow.set_alpha(alpha)
                for dx, dy in [(-offset, 0), (offset, 0), (0, -offset), (0, offset)]:
                    screen.blit(glow, title_rect.move(dx, dy))
            screen.blit(title, title_rect)

        # 副标题
        if 'normal' in self.fonts:
            sub = self.fonts['normal'].render("选择一个选项开始你的旅程", True, (140, 150, 180))
            sub_rect = sub.get_rect(center=(width // 2, int(height * 0.28)))
            screen.blit(sub, sub_rect)

        for btn in self.buttons:
            btn.render(screen)

    def _render_naming(self, screen, width, height, scale):
        """渲染命名界面"""
        # 标题
        title_font = get_font(max(28, int(42 * scale)))
        title = title_font.render("命名你的宇宙", True, (200, 220, 255))
        title_rect = title.get_rect(center=(width // 2, int(height * 0.25)))
        screen.blit(title, title_rect)

        # 提示
        hint_font = get_font(max(15, int(18 * scale)))
        hint = hint_font.render("为这个三体世界起一个名字", True, (120, 140, 170))
        hint_rect = hint.get_rect(center=(width // 2, int(height * 0.35)))
        screen.blit(hint, hint_rect)

        # 输入框
        if self.name_input:
            self.name_input.render(screen)

        # 按钮
        if self.confirm_button:
            self.confirm_button.update(0.016)
            self.confirm_button.render(screen)
        if self.cancel_button:
            self.cancel_button.update(0.016)
            self.cancel_button.render(screen)

    def _render_load(self, screen, width, height, scale):
        """渲染加载存档列表"""
        # 标题
        title_font = get_font(max(24, int(34 * scale)))
        title = title_font.render("加载存档", True, (200, 220, 255))
        screen.blit(title, (int(width * 0.08), int(height * 0.04)))

        # 存档数量
        count_font = get_font(max(13, int(16 * scale)))
        count_text = f"共 {len(self.save_list)} 个存档"
        count_surf = count_font.render(count_text, True, (120, 140, 170))
        screen.blit(count_surf, (int(width * 0.08), int(height * 0.10)))

        # 存档列表
        list_x = int(width * 0.08)
        list_y = int(height * 0.15)
        list_w = int(width * 0.84)
        item_h = max(60, int(70 * scale))
        gap = max(6, int(8 * scale))

        # 裁剪区域（不绘制超出边界的部分）
        bottom_limit = height - max(80, int(90 * scale))

        name_font = get_font(max(16, int(20 * scale)))
        detail_font = get_font(max(12, int(15 * scale)))

        if not self.save_list:
            empty_font = get_font(max(18, int(24 * scale)))
            empty = empty_font.render("暂无存档", True, (100, 110, 140))
            empty_rect = empty.get_rect(center=(width // 2, height // 2))
            screen.blit(empty, empty_rect)
        else:
            for i, save in enumerate(self.save_list):
                iy = list_y + i * (item_h + gap) - self.scroll_offset
                if iy + item_h < list_y or iy > bottom_limit:
                    continue

                rect = pygame.Rect(list_x, iy, list_w, item_h)

                # 背景色
                if i == self.selected_save_idx:
                    bg_color = (50, 65, 120)
                    border_color = (120, 160, 255)
                else:
                    bg_color = (25, 30, 55)
                    border_color = (50, 60, 90)

                pygame.draw.rect(screen, bg_color, rect, border_radius=8)
                pygame.draw.rect(screen, border_color, rect, 2, border_radius=8)

                # 存档名称（左侧）
                name_color = (220, 230, 255) if i == self.selected_save_idx else (180, 190, 220)
                name_surf = name_font.render(save.save_name, True, name_color)
                screen.blit(name_surf, (rect.x + 15, rect.y + 8))

                # 详情行（宇宙名 · 天数 · 时间）
                detail_parts = []
                if save.universe_name and save.universe_name != save.save_name:
                    detail_parts.append(f"🌌 {save.universe_name}")
                detail_parts.append(f"第{save.game_day}天")
                detail_parts.append(f"📅 {save.save_time}")
                if save.is_legacy:
                    detail_parts.append("⚠ 旧格式")

                detail_text = "  ·  ".join(detail_parts)
                detail_surf = detail_font.render(detail_text, True, (120, 140, 170))
                screen.blit(detail_surf, (rect.x + 15, rect.y + 8 + name_font.get_height() + 4))

        # 底部工具栏背景
        toolbar_bg = pygame.Surface((width, max(70, int(85 * scale))), pygame.SRCALPHA)
        toolbar_bg.fill((10, 12, 25, 230))
        screen.blit(toolbar_bg, (0, height - max(70, int(85 * scale))))

        # 按钮
        self.back_button.update(0.016)
        self.back_button.render(screen)
        self.load_btn.update(0.016)
        self.load_btn.render(screen)
        self.delete_btn.update(0.016)
        self.delete_btn.render(screen)

        # 提示
        hint_font = get_font(max(12, int(14 * scale)))
        hint = hint_font.render("滚轮滚动 | Enter加载 | Delete删除", True, (80, 90, 120))
        screen.blit(hint, (width - hint.get_width() - int(20 * scale),
                           height - max(25, int(30 * scale))))

        # 删除确认对话框
        if self.confirm_delete and 0 <= self.selected_save_idx < len(self.save_list):
            self._render_delete_confirm(screen, width, height, scale)

    def _render_delete_confirm(self, screen, width, height, scale):
        """渲染删除确认对话框"""
        # 遮罩
        overlay = pygame.Surface((width, height), pygame.SRCALPHA)
        overlay.fill((0, 0, 0, 160))
        screen.blit(overlay, (0, 0))

        # 对话框
        dlg_w = max(350, int(420 * scale))
        dlg_h = max(160, int(200 * scale))
        dlg_x = (width - dlg_w) // 2
        dlg_y = (height - dlg_h) // 2

        pygame.draw.rect(screen, (30, 25, 45), (dlg_x, dlg_y, dlg_w, dlg_h), border_radius=12)
        pygame.draw.rect(screen, (180, 80, 80), (dlg_x, dlg_y, dlg_w, dlg_h), 2, border_radius=12)

        save = self.save_list[self.selected_save_idx]
        warn_font = get_font(max(18, int(24 * scale)))
        name_font = get_font(max(14, int(18 * scale)))

        warn_surf = warn_font.render("确认删除此存档？", True, (255, 120, 120))
        name_surf = name_font.render(save.save_name, True, (200, 200, 220))

        screen.blit(warn_surf, warn_surf.get_rect(center=(width // 2, dlg_y + int(dlg_h * 0.22))))
        screen.blit(name_surf, name_surf.get_rect(center=(width // 2, dlg_y + int(dlg_h * 0.45))))

        # 按钮位置调整到对话框内
        btn_y = dlg_y + int(dlg_h * 0.65)
        btn_w = max(100, int(130 * scale))
        btn_h = max(34, int(40 * scale))
        gap = int(20 * scale)

        self.delete_confirm_btn.rect = pygame.Rect(
            width // 2 - btn_w - gap // 2, btn_y, btn_w, btn_h)
        self.delete_cancel_btn.rect = pygame.Rect(
            width // 2 + gap // 2, btn_y, btn_w, btn_h)

        self.delete_confirm_btn.update(0.016)
        self.delete_confirm_btn.render(screen)
        self.delete_cancel_btn.update(0.016)
        self.delete_cancel_btn.render(screen)
