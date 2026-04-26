"""科技树子界面 - 树形可视化，悬浮详情，多种科技点数显示"""

import pygame
import math
from typing import Optional, List, Tuple, Dict

from .screen_manager import Screen, ScreenType
from .initial_menu import MenuButton
from render.ui import get_font
from game.technology import TechNode, RESEARCH_TYPES, RESEARCH_NAMES, RESEARCH_COLORS


class TechTreeScreen(Screen):
    """科技树专属子界面 —— 树形依赖可视化"""

    # 节点基准尺寸（1280x720下）— 会在 setup_ui() 中按窗口缩放
    _BASE_NODE_W = 150
    _BASE_NODE_H = 52
    _BASE_TIER_GAP_X = 210
    _BASE_NODE_GAP_Y = 80
    _BASE_MARGIN_LEFT = 130
    _BASE_MARGIN_TOP = 100

    # 节点颜色
    COLOR_LOCKED = (60, 60, 80)           # 未满足前置
    COLOR_RESEARCHABLE = (40, 80, 140)    # 可研发
    COLOR_UNLOCKED = (30, 100, 60)        # 已解锁
    COLOR_BORDER_LOCKED = (80, 80, 100)
    COLOR_BORDER_RESEARCHABLE = (100, 180, 255)
    COLOR_BORDER_UNLOCKED = (100, 255, 130)

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.simulator = None
        self.message = ""
        self.message_timer = 0.0

        # 视图偏移（支持平移）
        self.view_offset_x = 0.0
        self.view_offset_y = 0.0
        self.dragging = False
        self.drag_start = (0, 0)

        # 缩放
        self.zoom = 1.0

        # 悬浮详情
        self.hovered_node_id: Optional[str] = None
        self.hover_pos = (0, 0)

        # 节点位置缓存（屏幕坐标）
        self._node_rects: Dict[str, pygame.Rect] = {}

        self.setup_ui()

    def setup_ui(self):
        """设置UI"""
        width, height = self.screen.get_size()
        scale = min(width / 1280, height / 720)

        # 按窗口大小缩放节点布局
        self.NODE_W = int(self._BASE_NODE_W * scale)
        self.NODE_H = int(self._BASE_NODE_H * scale)
        self.TIER_GAP_X = int(self._BASE_TIER_GAP_X * scale)
        self.NODE_GAP_Y = int(self._BASE_NODE_GAP_Y * scale)
        self.MARGIN_LEFT = int(self._BASE_MARGIN_LEFT * scale)
        self.MARGIN_TOP = int(self._BASE_MARGIN_TOP * scale)

        btn_font_size = max(16, int(22 * scale))
        btn_h = max(32, int(40 * scale))
        btn_w_back = max(100, int(120 * scale))

        # 返回按钮
        self.back_button = MenuButton(
            int(20 * scale), int(20 * scale), btn_w_back, btn_h,
            "← 返回",
            callback=self.on_back,
            font_size=btn_font_size
        )

        self.load_fonts()

    def on_back(self):
        """返回主界面"""
        self.screen_manager.switch_to(ScreenType.MAIN_SCREEN)

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面时响应"""
        super().on_enter(previous_screen, **kwargs)
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()
        self.simulator = self.screen_manager.global_state.get('simulator')
        self.setup_ui()

    def _get_node_screen_rect(self, node: TechNode) -> pygame.Rect:
        """计算节点在屏幕上的矩形位置"""
        scale = self.zoom
        x = self.MARGIN_LEFT + node.tier * self.TIER_GAP_X
        y = self.MARGIN_TOP + node.column * self.NODE_GAP_Y

        sx = int(x * scale + self.view_offset_x)
        sy = int(y * scale + self.view_offset_y)
        sw = int(self.NODE_W * scale)
        sh = int(self.NODE_H * scale)

        return pygame.Rect(sx, sy, sw, sh)

    def _calc_node_rects(self):
        """重新计算所有节点的屏幕位置"""
        self._node_rects.clear()
        if not self.simulator:
            return
        for node_id, node in self.simulator.tech_tree.nodes.items():
            self._node_rects[node_id] = self._get_node_screen_rect(node)

    def update(self, dt: float):
        """更新状态"""
        super().update(dt)
        if self.message_timer > 0:
            self.message_timer -= dt
        self.back_button.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        """事件处理"""
        if not self.active:
            return False

        if self.back_button.handle_event(event):
            return True

        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self.on_back()
                return True

        # 鼠标滚轮缩放
        if event.type == pygame.MOUSEWHEEL:
            old_zoom = self.zoom
            self.zoom = max(0.4, min(2.0, self.zoom + event.y * 0.1))
            # 以鼠标位置为中心缩放
            mx, my = pygame.mouse.get_pos()
            ratio = self.zoom / old_zoom
            self.view_offset_x = mx - (mx - self.view_offset_x) * ratio
            self.view_offset_y = my - (my - self.view_offset_y) * ratio
            return True

        # 鼠标右键拖拽平移
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 3:
            self.dragging = True
            self.drag_start = event.pos
            return True

        if event.type == pygame.MOUSEBUTTONUP and event.button == 3:
            self.dragging = False
            return True

        if event.type == pygame.MOUSEMOTION:
            if self.dragging:
                dx = event.pos[0] - self.drag_start[0]
                dy = event.pos[1] - self.drag_start[1]
                self.view_offset_x += dx
                self.view_offset_y += dy
                self.drag_start = event.pos
                return True

            # 悬浮检测
            mx, my = event.pos
            self.hovered_node_id = None
            self.hover_pos = (mx, my)
            for node_id, rect in self._node_rects.items():
                if rect.collidepoint(mx, my):
                    self.hovered_node_id = node_id
                    break

        # 鼠标左键点击节点进行研发
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            mx, my = event.pos
            for node_id, rect in self._node_rects.items():
                if rect.collidepoint(mx, my):
                    self._try_research(node_id)
                    return True

        return False

    def _try_research(self, node_id: str):
        """尝试研发科技"""
        if not self.simulator:
            return
        tech_tree = self.simulator.tech_tree
        node = tech_tree.get_node(node_id)
        if not node:
            return

        if node.unlocked:
            self.message = f"「{node.name}」已经研发完毕"
            self.message_timer = 2.0
            return

        can_unlock, reason = tech_tree.can_unlock(node_id, self.simulator.entities)

        if can_unlock:
            tech_tree.unlock_tech(node_id, self.simulator.entities)
            self.message = f"✓ 成功研发科技：{node.name}"
            self.message_timer = 3.0
        else:
            self.message = f"✗ 无法研发：{reason}"
            self.message_timer = 3.0

    def render(self, screen: pygame.Surface):
        """界面渲染"""
        if not self.visible:
            return

        screen.fill((12, 15, 25))
        width, height = screen.get_size()
        scale = min(width / 1280, height / 720)

        # 重新计算节点位置
        self._calc_node_rects()

        if self.simulator:
            tech_tree = self.simulator.tech_tree

            # 1. 绘制依赖连线
            self._draw_connections(screen, tech_tree)

            # 2. 绘制节点
            self._draw_nodes(screen, tech_tree, scale)

            # 3. 绘制悬浮详情
            if self.hovered_node_id:
                self._draw_tooltip(screen, tech_tree, scale)

            # 4. 绘制科技点数
            self._draw_research_points(screen, tech_tree, scale)

        # 标题
        if 'title' in self.fonts:
            title_surf = self.fonts['title'].render("科技树", True, (150, 200, 255))
            title_rect = title_surf.get_rect(center=(width // 2, max(35, int(45 * scale))))
            screen.blit(title_surf, title_rect)

        # 返回按钮
        self.back_button.render(screen)

        # 提示信息
        if self.message_timer > 0 and 'normal' in self.fonts:
            alpha = min(1.0, self.message_timer)
            color = (150, 255, 150) if "✓" in self.message else (255, 150, 100)
            msg_surf = self.fonts['normal'].render(self.message, True, color)
            msg_rect = msg_surf.get_rect(center=(width // 2, height - max(40, int(50 * scale))))
            screen.blit(msg_surf, msg_rect)

        # 操作提示
        if 'tiny' in self.fonts:
            hint = self.fonts['tiny'].render(
                "左键点击研发 | 滚轮缩放 | 右键拖拽平移", True, (80, 100, 130)
            )
            screen.blit(hint, (width - hint.get_width() - 15, height - 25))

    def _draw_connections(self, screen: pygame.Surface, tech_tree):
        """绘制科技依赖连线"""
        for node_id, node in tech_tree.nodes.items():
            if node_id not in self._node_rects:
                continue
            dst_rect = self._node_rects[node_id]

            for pre_id in node.prerequisites:
                if pre_id not in self._node_rects:
                    continue
                src_rect = self._node_rects[pre_id]

                # 连线颜色
                pre_node = tech_tree.get_node(pre_id)
                if pre_node and pre_node.unlocked and node.unlocked:
                    color = (60, 180, 80, 200)    # 双绿
                elif pre_node and pre_node.unlocked:
                    color = (80, 140, 220, 180)   # 蓝色（可研发路径）
                else:
                    color = (50, 50, 70, 120)     # 灰色

                # 起点：前置节点的右侧中点
                sx = src_rect.right
                sy = src_rect.centery
                # 终点：当前节点的左侧中点
                ex = dst_rect.left
                ey = dst_rect.centery

                # 使用贝塞尔曲线
                mid_x = (sx + ex) // 2
                points = []
                steps = 20
                for i in range(steps + 1):
                    t = i / steps
                    # 三次贝塞尔
                    x = (1-t)**3 * sx + 3*(1-t)**2*t * mid_x + 3*(1-t)*t**2 * mid_x + t**3 * ex
                    y = (1-t)**3 * sy + 3*(1-t)**2*t * sy + 3*(1-t)*t**2 * ey + t**3 * ey
                    points.append((int(x), int(y)))

                if len(points) > 1:
                    pygame.draw.lines(screen, color[:3], False, points, 2)

    def _draw_nodes(self, screen: pygame.Surface, tech_tree, ui_scale: float):
        """绘制所有科技节点"""
        font_size = max(13, int(16 * self.zoom * ui_scale))
        node_font = get_font(font_size)
        small_font = get_font(max(10, int(12 * self.zoom * ui_scale)))

        for node_id, node in tech_tree.nodes.items():
            if node_id not in self._node_rects:
                continue
            rect = self._node_rects[node_id]

            # 决定颜色
            if node.unlocked:
                bg_color = self.COLOR_UNLOCKED
                border_color = self.COLOR_BORDER_UNLOCKED
                text_color = (200, 255, 200)
            elif tech_tree.is_researchable(node_id):
                bg_color = self.COLOR_RESEARCHABLE
                border_color = self.COLOR_BORDER_RESEARCHABLE
                text_color = (200, 220, 255)
            else:
                bg_color = self.COLOR_LOCKED
                border_color = self.COLOR_BORDER_LOCKED
                text_color = (120, 120, 140)

            # 背景
            pygame.draw.rect(screen, bg_color, rect, border_radius=8)
            # 边框
            border_width = 3 if self.hovered_node_id == node_id else 2
            pygame.draw.rect(screen, border_color, rect, border_width, border_radius=8)

            # 已解锁标记
            if node.unlocked:
                check = small_font.render("✓", True, (100, 255, 100))
                screen.blit(check, (rect.right - 18, rect.top + 4))

            # 名称
            name_surf = node_font.render(node.name, True, text_color)
            name_rect = name_surf.get_rect(center=(rect.centerx, rect.top + rect.height * 0.35))
            screen.blit(name_surf, name_rect)

            # 分类标签
            cat_text = {"basic": "基础", "applied": "应用", "theoretical": "理论"}.get(node.category, "")
            cat_color = RESEARCH_COLORS.get(node.category, (150, 150, 150))
            cat_surf = small_font.render(cat_text, True, cat_color)
            cat_rect = cat_surf.get_rect(center=(rect.centerx, rect.bottom - rect.height * 0.25))
            screen.blit(cat_surf, cat_rect)

    def _draw_tooltip(self, screen: pygame.Surface, tech_tree, ui_scale: float):
        """绘制悬浮详情面板"""
        node = tech_tree.get_node(self.hovered_node_id)
        if not node:
            return

        width, height = screen.get_size()
        font_size = max(14, int(18 * ui_scale))
        tip_font = get_font(font_size)
        small_font = get_font(max(12, int(14 * ui_scale)))
        line_height = font_size + 6

        # 构建内容行
        lines = []
        lines.append((f"【{node.name}】", (255, 255, 255), tip_font))
        lines.append((node.description, (180, 180, 200), small_font))
        lines.append(("", None, small_font))  # 空行
        lines.append((f"效果: {node.effect_description}", (180, 255, 180), small_font))
        lines.append(("", None, small_font))

        # 科技点数需求
        if node.research_cost:
            lines.append(("─ 科技点数需求 ─", (200, 200, 220), small_font))
            for rtype, cost in node.research_cost.items():
                name = RESEARCH_NAMES.get(rtype, rtype)
                current = int(tech_tree.research_points.get(rtype, 0))
                color = RESEARCH_COLORS.get(rtype, (200, 200, 200))
                sufficient = current >= cost
                mark = "✓" if sufficient else "✗"
                lines.append((f"  {mark} {name}: {current}/{cost}", color if sufficient else (255, 100, 100), small_font))

        # 资源消耗
        if node.resource_cost:
            lines.append(("─ 资源消耗 ─", (200, 200, 220), small_font))
            res_names = {"minerals": "矿物", "energy": "能源", "food": "食物"}
            for res, cost in node.resource_cost.items():
                display = res_names.get(res, res)
                if self.simulator:
                    current = int(self.simulator.entities.get_resource(res))
                    sufficient = current >= cost
                    mark = "✓" if sufficient else "✗"
                    lines.append((f"  {mark} {display}: {current}/{cost}",
                                  (200, 200, 200) if sufficient else (255, 100, 100), small_font))

        # 前置科技
        if node.prerequisites:
            lines.append(("─ 前置科技 ─", (200, 200, 220), small_font))
            for pre_id in node.prerequisites:
                pre = tech_tree.get_node(pre_id)
                if pre:
                    status = "✓" if pre.unlocked else "✗"
                    color = (100, 255, 100) if pre.unlocked else (255, 100, 100)
                    lines.append((f"  {status} {pre.name}", color, small_font))

        # 状态
        if node.unlocked:
            lines.append(("", None, small_font))
            lines.append(("★ 已解锁", (100, 255, 100), tip_font))

        # 计算面板尺寸
        max_line_width = 0
        for text, _, font in lines:
            if text:
                max_line_width = max(max_line_width, font.size(text)[0])

        panel_w = max_line_width + 30
        panel_h = len(lines) * line_height + 20

        # 位置（跟随鼠标，但不超出屏幕）
        mx, my = self.hover_pos
        px = mx + 15
        py = my + 15
        if px + panel_w > width:
            px = mx - panel_w - 10
        if py + panel_h > height:
            py = height - panel_h - 10

        # 绘制面板背景
        panel_rect = pygame.Rect(px, py, panel_w, panel_h)
        # 半透明背景
        bg_surface = pygame.Surface((panel_w, panel_h), pygame.SRCALPHA)
        bg_surface.fill((20, 25, 40, 230))
        screen.blit(bg_surface, (px, py))
        pygame.draw.rect(screen, (80, 120, 180), panel_rect, 1, border_radius=6)

        # 绘制文本
        ty = py + 10
        for text, color, font in lines:
            if text and color:
                surf = font.render(text, True, color)
                screen.blit(surf, (px + 15, ty))
            ty += line_height

    def _draw_research_points(self, screen: pygame.Surface, tech_tree, ui_scale: float):
        """绘制顶部科技点数显示"""
        width = screen.get_width()
        font_size = max(14, int(18 * ui_scale))
        rp_font = get_font(font_size)

        x_pos = width - max(200, int(320 * ui_scale))
        y_pos = max(15, int(20 * ui_scale))

        # 背景
        bg_w = max(190, int(300 * ui_scale))
        bg_h = max(65, int(85 * ui_scale))
        bg_rect = pygame.Rect(x_pos - 10, y_pos - 5, bg_w, bg_h)
        bg_surf = pygame.Surface((bg_w, bg_h), pygame.SRCALPHA)
        bg_surf.fill((15, 20, 35, 200))
        screen.blit(bg_surf, (bg_rect.x, bg_rect.y))
        pygame.draw.rect(screen, (60, 80, 120), bg_rect, 1, border_radius=4)

        for rtype in RESEARCH_TYPES:
            name = RESEARCH_NAMES[rtype]
            color = RESEARCH_COLORS[rtype]
            amount = int(tech_tree.research_points.get(rtype, 0))

            text = f"{name}: {amount}"
            surf = rp_font.render(text, True, color)
            screen.blit(surf, (x_pos, y_pos))
            y_pos += font_size + 6
