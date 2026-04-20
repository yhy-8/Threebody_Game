"""3D星图界面 - 三体运动可视化"""

import pygame
import numpy as np
from typing import Optional

from .screen_manager import Screen, ScreenType
from .initial_menu import MenuButton
from render.camera import Camera
from render.scene import SceneRenderer
from render.ui import create_hud, update_hud, UIManager, get_font


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
        self.restart_button: Optional[MenuButton] = None

        # ── 行星锁定状态 ──
        self.planet_locked = False

        self.setup_ui()

    def setup_ui(self):
        """设置UI"""
        width, height = self.screen.get_size()
        scale = min(width / 1280, height / 720)
        
        btn_font_size = max(16, int(22 * scale))
        btn_h = max(32, int(40 * scale))
        
        btn_w_back = max(100, int(120 * scale))
        btn_w_pause = max(80, int(100 * scale))
        btn_w_lock = max(110, int(140 * scale))
        btn_w_help = max(90, int(110 * scale))

        # 返回主界面按钮
        self.back_button = MenuButton(
            int(20 * scale), int(20 * scale), btn_w_back, btn_h,
            "← 返回",
            callback=self.on_back,
            font_size=btn_font_size
        )

        # 暂停/继续按钮
        pause_x = int(20 * scale) + btn_w_back + int(20 * scale)
        self.pause_button = MenuButton(
            pause_x, int(20 * scale), btn_w_pause, btn_h,
            "暂停",
            callback=self.on_pause_toggle,
            font_size=btn_font_size
        )

        # 锁定行星按钮（暂停按钮右侧）
        lock_x = pause_x + btn_w_pause + int(20 * scale)
        lock_text = "[解锁]" if self.planet_locked else "锁定行星"
        self.lock_button = MenuButton(
            lock_x, int(20 * scale), btn_w_lock, btn_h,
            lock_text,
            callback=self.on_lock_toggle,
            font_size=btn_font_size
        )

        # 帮助按钮
        self.help_button = MenuButton(
            width - btn_w_help - int(20 * scale), int(20 * scale), btn_w_help, btn_h,
            "帮助(?)",
            callback=self.on_help_toggle,
            font_size=btn_font_size
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
        self.screen_manager.switch_to(ScreenType.MAIN_SCREEN)

    def on_pause_toggle(self):
        """暂停/继续切换"""
        if self.simulator:
            self.simulator.toggle_pause()
            # 更新按钮文字
            self.pause_button.text = "继续" if self.simulator.paused else "暂停"

    def on_lock_toggle(self):
        """切换行星锁定状态"""
        if not self.camera or not self.simulator:
            return

        if self.planet_locked:
            # 解锁 —— 恢复自由视角
            self.planet_locked = False
            self.camera.set_lock_target(None)
            self.lock_button.text = "锁定行星"
        else:
            # 锁定 —— 找到行星并锁定
            planet_pos = self._get_planet_position()
            if planet_pos is not None:
                self.planet_locked = True
                self.camera.set_lock_target(planet_pos)
                self.lock_button.text = "[解锁]"

    def _get_planet_position(self) -> Optional[np.ndarray]:
        """从模拟器获取行星位置"""
        if not self.simulator:
            return None
        state = self.simulator.get_state()
        for star in state.get("environment", {}).get("stars", []):
            if star.get("is_planet", False):
                return np.array(star["position"], dtype=float)
        return None

    def on_help_toggle(self):
        """显示/隐藏帮助"""
        self.showing_help = not self.showing_help

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面"""
        super().on_enter(previous_screen, **kwargs)

        # 更新屏幕引用，确保尺寸正确
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()

        # 同步游戏结束状态 - 如果模拟器已重置则清除game_over
        if self.simulator:
            self.game_over = self.simulator.game_over
        else:
            self.game_over = False

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

    def update(self, dt: float):
        """更新界面"""
        super().update(dt)

        # 更新按钮
        self.back_button.update(dt)
        self.pause_button.update(dt)
        self.lock_button.update(dt)
        self.help_button.update(dt)

        # 更新3D场景
        if self.simulator and not self.game_over:
            # 碰撞检测
            if self.camera and self.scene:
                state = self.simulator.get_state()
                stars = state.get("environment", {}).get("stars", [])
                if self.camera.check_collision(stars):
                    self.game_over = True
                    self.simulator.game_over = True  # 同步到模拟器
                    self._create_game_over_button()

            # ── 锁定模式：每帧跟踪行星最新位置 ──
            if self.planet_locked and self.camera:
                planet_pos = self._get_planet_position()
                if planet_pos is not None:
                    self.camera.update_orbit(planet_pos)

            # 更新UI
            if self.ui_manager:
                state = self.simulator.get_state()
                update_hud(self.ui_manager, state, self.camera,
                           locked=self.planet_locked,
                           orbit_distance=self.camera.orbit_distance if self.camera else 0)
                
        # 应用相机设置
        if self.camera:
            settings = self.screen_manager.global_state.get('settings', {})
            self.camera.sensitivity = settings.get('mouse_sensitivity', 1.0)
            self.camera.invert_y = settings.get('invert_mouse_y', False)

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件"""
        if not self.active:
            return False

        # 如果游戏结束，处理重启按钮
        if self.game_over:
            if self.restart_button and self.restart_button.handle_event(event):
                return True
            # 游戏结束时不处理其他3D交互
            if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                self.on_back()
                return True
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
        if self.lock_button.handle_event(event):
            return True
        if self.help_button.handle_event(event):
            return True

        # 处理3D场景输入
        if self.handle_3d_input(event):
            return True

        return False

    def handle_3d_input(self, event: pygame.event.Event) -> bool:
        """处理3D场景输入 —— 根据锁定状态分发"""
        if not self.camera:
            return False

        if self.planet_locked:
            return self._handle_locked_input(event)
        else:
            return self._handle_free_input(event)

    def _handle_free_input(self, event: pygame.event.Event) -> bool:
        """自由视角模式的输入处理（原有逻辑）"""
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

    def _handle_locked_input(self, event: pygame.event.Event) -> bool:
        """锁定行星模式的输入处理"""
        # 鼠标拖拽 → 环绕行星旋转
        if event.type == pygame.MOUSEMOTION and pygame.mouse.get_pressed()[0]:
            self.camera.orbit_rotate(event.rel[0], event.rel[1])
            return True

        # 滚轮 → 拉近/拉远
        if event.type == pygame.MOUSEWHEEL:
            self.camera.orbit_zoom(event.y)
            return True

        # 键盘控制
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_SPACE:
                if self.simulator:
                    self.simulator.toggle_pause()
                    self.pause_button.text = "继续" if self.simulator.paused else "暂停"
                return True

        return False

    def handle_continuous_input(self, keys):
        """处理持续按键（每帧调用）"""
        if not self.camera:
            return

        if self.planet_locked:
            # ── 锁定模式 ──
            # W/S: 拉近/拉远
            if keys[pygame.K_w] or keys[pygame.K_UP]:
                self.camera.orbit_zoom(1.0)
            if keys[pygame.K_s] or keys[pygame.K_DOWN]:
                self.camera.orbit_zoom(-1.0)
            # A/D: 水平环绕
            if keys[pygame.K_a] or keys[pygame.K_LEFT]:
                self.camera.orbit_rotate(-3, 0)
            if keys[pygame.K_d] or keys[pygame.K_RIGHT]:
                self.camera.orbit_rotate(3, 0)
            # Q/E: 垂直俯仰
            if keys[pygame.K_q]:
                self.camera.orbit_rotate(0, -3)
            if keys[pygame.K_e]:
                self.camera.orbit_rotate(0, 3)
        else:
            # ── 自由模式 ──
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
        if hasattr(self, 'lock_button'):
            self.lock_button.render(screen)
        if hasattr(self, 'help_button'):
            self.help_button.render(screen)

        # 渲染游戏结束画面
        if self.game_over:
            self._render_game_over(screen)

        # 渲染帮助
        if self.showing_help:
            self._render_help(screen)

    def _create_game_over_button(self):
        """创建游戏结束界面的按钮"""
        width, height = self.screen.get_size()
        btn_w = max(180, width // 6)
        btn_h = max(45, height // 14)
        btn_font = max(22, min(32, width // 40))

        self.restart_button = MenuButton(
            width // 2 - btn_w // 2, height // 2 + 80,
            btn_w, btn_h,
            "开始新游戏",
            callback=self._on_restart,
            font_size=btn_font
        )

    def _on_restart(self):
        """重启游戏 - 从游戏结束界面"""
        # 重置模拟器
        simulator = self.screen_manager.global_state.get('simulator')
        if simulator:
            simulator.reset()
        self.game_over = False
        self.restart_button = None

        # 解锁行星视角
        self.planet_locked = False
        if self.camera:
            self.camera.set_lock_target(None)

        # 重置摄像机位置
        if self.camera:
            self.camera.position = np.array([0.0, 0.0, -500.0])
            self.camera.rotation = [0, 0]

        # 返回开始游戏菜单
        self.screen_manager.clear_stack_and_switch(ScreenType.START_GAME_MENU)

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
            hint = self.fonts['normal'].render("星球发生碰撞，文明毁灭", True, (255, 200, 200))
            hint_rect = hint.get_rect(center=(width // 2, height // 2 + 30))
            screen.blit(hint, hint_rect)

        # 渲染重启按钮
        if self.restart_button:
            self.restart_button.update(0.016)
            self.restart_button.render(screen)

    def _render_help(self, screen: pygame.Surface):
        """渲染帮助界面 —— 根据锁定状态显示不同操作说明"""
        width, height = screen.get_size()

        # 半透明黑色遮罩
        overlay = pygame.Surface((width, height))
        overlay.set_alpha(200)
        overlay.fill((0, 0, 0))
        screen.blit(overlay, (0, 0))

        # 帮助面板 - 根据窗口大小缩放
        scale = min(width / 1280, height / 720)
        panel_width = min(int(800 * scale), int(width * 0.8))
        panel_height = min(int(600 * scale), int(height * 0.8))
        panel_x = (width - panel_width) // 2
        panel_y = (height - panel_height) // 2

        # 绘制面板背景
        pygame.draw.rect(screen, (30, 35, 50), (panel_x, panel_y, panel_width, panel_height), border_radius=12)
        pygame.draw.rect(screen, (80, 90, 120), (panel_x, panel_y, panel_width, panel_height), 2, border_radius=12)

        # 标题
        title_font_size = max(24, int(48 * scale))
        title_font = get_font(title_font_size)

        if self.planet_locked:
            title_text = "操作说明 — 行星锁定模式"
            title_color = (255, 200, 120)
        else:
            title_text = "操作说明 — 自由视角模式"
            title_color = (220, 230, 255)

        title = title_font.render(title_text, True, title_color)
        title_rect = title.get_rect(center=(width // 2, panel_y + max(30, int(panel_height * 0.08))))
        screen.blit(title, title_rect)

        # 帮助内容 —— 根据锁定状态切换
        if self.planet_locked:
            help_items = [
                ("距离控制", [
                    "W/S - 拉近/拉远行星",
                    "滚轮 - 拉近/拉远行星",
                ]),
                ("环绕控制", [
                    "鼠标拖拽 - 围绕行星旋转观察",
                    "A/D - 水平方向环绕行星",
                    "Q/E - 垂直方向调整俯仰",
                ]),
                ("其他操作", [
                    "空格 - 暂停/继续",
                    "ESC - 返回主界面",
                    "点击'解锁'按钮 - 恢复自由视角"
                ])
            ]
        else:
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
                    "点击'锁定行星'按钮 - 锁定行星视角"
                ])
            ]

        section_font_size = max(16, int(24 * scale))
        item_font_size = max(14, int(18 * scale))
        y_offset = panel_y + max(70, int(panel_height * 0.18))
        section_font = get_font(section_font_size)
        item_font = get_font(item_font_size)

        for section, items in help_items:
            # 章节标题
            section_surf = section_font.render(section, True, (150, 180, 255))
            screen.blit(section_surf, (panel_x + int(30 * scale), y_offset))
            y_offset += max(22, int(panel_height * 0.06))

            # 项目
            for item in items:
                item_surf = item_font.render(item, True, (200, 210, 230))
                screen.blit(item_surf, (panel_x + int(50 * scale), y_offset))
                y_offset += max(18, int(panel_height * 0.045))

            y_offset += max(8, int(panel_height * 0.02))

        # 底部提示
        hint_font_size = max(13, int(18 * scale))
        hint_font = get_font(hint_font_size)
        hint_surf = hint_font.render("点击任意位置或按任意键关闭帮助", True, (150, 160, 180))
        hint_rect = hint_surf.get_rect(center=(width // 2, panel_y + panel_height - int(30 * scale)))
        screen.blit(hint_surf, hint_rect)
