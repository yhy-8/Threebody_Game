"""3D星图界面 - 三体运动可视化"""

import pygame
import numpy as np
from typing import Optional

from .screen_manager import Screen, ScreenType
from .initial_menu import MenuButton
from render.camera import Camera
from render.scene import SceneRenderer
from render.ui import create_hud, update_hud, UIManager


class StarmapView(Screen):
    """3D星图界面"""

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.camera: Optional[Camera] = None
        self.scene: Optional[SceneRenderer] = None
        self.ui_manager: Optional[UIManager] = None
        self.simulator = None  # 游戏模拟器，由外部注入
        self.game_over = False
        self.showing_help = False
        self.setup_ui()

    def setup_ui(self):
        """设置UI"""
        width, height = self.screen.get_size()

        # 返回主界面按钮
        self.back_button = MenuButton(
            20, 20, 120, 40,
            "← 返回",
            callback=self.on_back,
            font_size=22
        )

        # 暂停/继续按钮
        self.pause_button = MenuButton(
            160, 20, 100, 40,
            "暂停",
            callback=self.on_pause_toggle,
            font_size=22
        )

        # 帮助按钮
        self.help_button = MenuButton(
            width - 130, 20, 110, 40,
            "帮助(?)",
            callback=self.on_help_toggle,
            font_size=22
        )

    def init_3d_scene(self, simulator):
        """初始化3D场景（需要外部调用，传入游戏模拟器）"""
        self.simulator = simulator

        # 创建摄像机
        self.camera = Camera(
            position=(0, 0, -500),
            rotation=(0, 0),
            fov=500
        )
        self.camera.speed = 5

        # 创建场景渲染器
        self.scene = SceneRenderer(self.screen, self.camera)

        # 创建UI管理器
        state = self.simulator.get_state()
        width, height = self.screen.get_size()
        self.ui_manager = create_hud(state, width, height, self.camera)

        # 重置游戏状态
        self.game_over = False

    def on_back(self):
        """返回主界面"""
        if self.simulator:
            self.simulator.paused = True
        self.screen_manager.switch_to(ScreenType.MAIN_SCREEN)

    def on_pause_toggle(self):
        """暂停/继续切换"""
        if self.simulator:
            self.simulator.toggle_pause()
            # 更新按钮文字
            self.pause_button.text = "继续" if self.simulator.paused else "暂停"

    def on_help_toggle(self):
        """显示/隐藏帮助"""
        self.showing_help = not self.showing_help

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面"""
        super().on_enter(previous_screen, **kwargs)

        # 如果是从主界面或其他界面进入，可能需要初始化
        if self.camera is None:
            # 等待外部注入simulator后初始化
            pass

        # 重置暂停按钮文字
        if self.simulator:
            self.pause_button.text = "继续" if self.simulator.paused else "暂停"

        # 重新设置UI（窗口大小可能改变）
        self.setup_ui()

    def on_exit(self):
        """退出界面"""
        super().on_exit()
        # 暂停游戏
        if self.simulator:
            self.simulator.paused = True

    def update(self, dt: float):
        """更新界面"""
        super().update(dt)

        # 更新按钮
        self.back_button.update(dt)
        self.pause_button.update(dt)
        self.help_button.update(dt)

        # 更新3D场景
        if self.simulator and not self.game_over:
            # 更新模拟器
            if not self.simulator.paused:
                self.simulator.update(dt)

            # 碰撞检测
            if self.camera and self.scene:
                state = self.simulator.get_state()
                stars = state.get("environment", {}).get("stars", [])
                if self.camera.check_collision(stars):
                    self.game_over = True

            # 更新UI
            if self.ui_manager:
                state = self.simulator.get_state()
                update_hud(self.ui_manager, state, self.camera)

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件"""
        if not self.active:
            return False

        # 如果显示帮助，点击任意位置关闭
        if self.showing_help:
            if event.type == pygame.MOUSEBUTTONDOWN or event.type == pygame.KEYDOWN:
                self.showing_help = False
                return True

        # 处理按钮事件
        if self.back_button.handle_event(event):
            return True
        if self.pause_button.handle_event(event):
            return True
        if self.help_button.handle_event(event):
            return True

        # 处理3D场景输入
        if self.handle_3d_input(event):
            return True

        return False

    def handle_3d_input(self, event: pygame.event.Event) -> bool:
        """处理3D场景输入"""
        if not self.camera:
            return False

        # 鼠标拖拽旋转视角
        if event.type == pygame.MOUSEMOTION and pygame.mouse.get_pressed()[0]:
            self.camera.rotate(event.rel[0], event.rel[1])
            return True

        # 滚轮缩放
        if event.type == pygame.MOUSEWHEEL:
            self.camera.zoom(event.y)
            return True

        # 键盘控制
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_SPACE:
                # 空格暂停/继续
                if self.simulator:
                    self.simulator.toggle_pause()
                    self.pause_button.text = "继续" if self.simulator.paused else "暂停"
                return True

        return False

    def handle_continuous_input(self, keys):
        """处理持续按键（每帧调用）"""
        if not self.camera:
            return

        # WASD移动
        if keys[pygame.K_w] or keys[pygame.K_UP]:
            self.camera.move(forward=self.camera.speed)
        if keys[pygame.K_s] or keys[pygame.K_DOWN]:
            self.camera.move(forward=-self.camera.speed)
        if keys[pygame.K_a] or keys[pygame.K_LEFT]:
            self.camera.move(right=-self.camera.speed)
        if keys[pygame.K_d] or keys[pygame.K_RIGHT]:
            self.camera.move(right=self.camera.speed)
        if keys[pygame.K_q]:
            self.camera.move(up=self.camera.speed)
        if keys[pygame.K_e]:
            self.camera.move(up=-self.camera.speed)

    def render(self, screen: pygame.Surface):
        """渲染界面"""
        if not self.visible:
            return

        # 清空屏幕
        screen.fill((10, 10, 20))

        # 渲染3D场景
        if self.scene and self.simulator:
            # 清空场景
            self.scene.clear((10, 10, 20))

            # 渲染游戏状态
            state = self.simulator.get_state()
            self.scene.render(state)

        # 渲染UI
        if self.ui_manager:
            self.ui_manager.render(screen)

        # 渲染顶部按钮（如果按钮存在）
        if hasattr(self, 'back_button'):
            self.back_button.render(screen)
        if hasattr(self, 'pause_button'):
            self.pause_button.render(screen)
        if hasattr(self, 'help_button'):
            self.help_button.render(screen)

        # 渲染游戏结束画面
        if self.game_over:
            self._render_game_over(screen)

        # 渲染帮助
        if self.showing_help:
            self._render_help(screen)

    def _render_game_over(self, screen: pygame.Surface):
        """渲染游戏结束画面"""
        width, height = screen.get_size()

        # 红色半透明遮罩
        overlay = pygame.Surface((width, height))
        overlay.set_alpha(128)
        overlay.fill((150, 0, 0))
        screen.blit(overlay, (0, 0))

        # 游戏结束文字
        if 'title' in self.fonts:
            text = self.fonts['title'].render("游戏结束!", True, (255, 50, 50))
            text_rect = text.get_rect(center=(width // 2, height // 2 - 30))
            screen.blit(text, text_rect)

        # 提示文字
        if 'normal' in self.fonts:
            hint = self.fonts['normal'].render("你已撞击星球", True, (255, 200, 200))
            hint_rect = hint.get_rect(center=(width // 2, height // 2 + 30))
            screen.blit(hint, hint_rect)

    def _render_help(self, screen: pygame.Surface):
        """渲染帮助界面"""
        width, height = screen.get_size()

        # 半透明黑色遮罩
        overlay = pygame.Surface((width, height))
        overlay.set_alpha(200)
        overlay.fill((0, 0, 0))
        screen.blit(overlay, (0, 0))

        # 帮助面板
        panel_width = 600
        panel_height = 500
        panel_x = (width - panel_width) // 2
        panel_y = (height - panel_height) // 2

        # 绘制面板背景
        pygame.draw.rect(screen, (30, 35, 50), (panel_x, panel_y, panel_width, panel_height), border_radius=12)
        pygame.draw.rect(screen, (80, 90, 120), (panel_x, panel_y, panel_width, panel_height), 2, border_radius=12)

        # 标题
        if 'subtitle' in self.fonts:
            title = self.fonts['subtitle'].render("操作说明", True, (220, 230, 255))
            title_rect = title.get_rect(center=(width // 2, panel_y + 40))
            screen.blit(title, title_rect)

        # 帮助内容
        help_items = [
            ("移动控制", [
                "W/S - 向前/向后移动",
                "A/D - 向左/向右移动",
                "Q/E - 向上/向下移动"
            ]),
            ("视角控制", [
                "鼠标拖拽 - 旋转视角",
                "滚轮 - 缩放视角",
            ]),
            ("其他操作", [
                "空格 - 暂停/继续",
                "ESC - 返回主界面",
                "点击'菜单'按钮 - 打开游戏菜单"
            ])
        ]

        y_offset = panel_y + 90
        section_font = get_font(22)
        item_font = get_font(16)

        for section, items in help_items:
            # 章节标题
            section_surf = section_font.render(section, True, (150, 180, 255))
            screen.blit(section_surf, (panel_x + 30, y_offset))
            y_offset += 30

            # 项目
            for item in items:
                item_surf = item_font.render(item, True, (200, 210, 230))
                screen.blit(item_surf, (panel_x + 50, y_offset))
                y_offset += 22

            y_offset += 10

        # 底部提示
        hint_font = get_font(18)
        hint_surf = hint_font.render("点击任意位置或按任意键关闭帮助", True, (150, 160, 180))
        hint_rect = hint_surf.get_rect(center=(width // 2, panel_y + panel_height - 30))
        screen.blit(hint_surf, hint_rect)
