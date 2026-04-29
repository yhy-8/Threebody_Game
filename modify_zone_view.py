import re

with open("ui/zone_view_screen.py", "r", encoding="utf-8") as f:
    content = f.read()

# Add list to store dynamic buttons
content = content.replace("self.message_timer = 0.0", "self.message_timer = 0.0\n        self.dynamic_buttons = []\n        self.breeder_buttons = []")

# Update set_selected_zone_id
content = content.replace(
    "self.selected_zone_id = zone_id",
    "self.selected_zone_id = zone_id\n                self._refresh_dynamic_buttons()"
)
content = content.replace(
    "self.selected_zone_id = -1",
    "self.selected_zone_id = -1\n        self._refresh_dynamic_buttons()"
)

# Insert _refresh_dynamic_buttons after set_display_mode
refresh_code = """
    def _refresh_dynamic_buttons(self):
        self.dynamic_buttons.clear()
        self.breeder_buttons.clear()
        if not self.simulator:
            return
            
        width, height = self.screen.get_size()
        scale = self.scale
        panel_x = int(width * 0.58)
        panel_w = width - panel_x - int(15 * scale)
        
        # ── 生育按钮 ──
        y = self._header_h + 5
        font = get_font(max(14, int(17 * scale)))
        y += font.get_height() + 6
        small_font = get_font(max(12, int(14 * scale)))
        y += (small_font.get_height() + 3) * 6 # 5 lines + 1 extra
        
        btn_w = max(20, int(25 * scale))
        btn_h = max(20, int(25 * scale))
        
        btn_y = y - (small_font.get_height() + 3) # approximately on the last overview line
        
        def make_breeder_cb(amount):
            def cb():
                if amount > 0:
                    ok, msg = self.simulator.entities.assign_breeders(amount)
                else:
                    ok, msg = self.simulator.entities.unassign_breeders(-amount)
                self.message = msg
                self.message_timer = 2.0
            return cb
            
        self.breeder_buttons.append(MenuButton(panel_x + panel_w - btn_w * 2 - 10, btn_y, btn_w, btn_h, "-", callback=make_breeder_cb(-1), font_size=max(14, int(18*scale))))
        self.breeder_buttons.append(MenuButton(panel_x + panel_w - btn_w, btn_y, btn_w, btn_h, "+", callback=make_breeder_cb(1), font_size=max(14, int(18*scale))))
        
        if self.selected_zone_id < 0:
            return
            
        # ── 建筑按钮 ──
        y += 20 # after separator
        title_font = get_font(max(16, int(20 * scale)))
        y += title_font.get_height() + 6
        font = get_font(max(13, int(16 * scale)))
        y += (font.get_height() + 2) * 8 # 8 lines
        y += 6
        y += font.get_height() + 4 # header
        
        buildings = self.simulator.entities.get_buildings_in_zone(self.selected_zone_id)
        for b in buildings[:6]:
            btn_y = y
            def make_b_cb(bid, amount):
                def cb():
                    if amount > 0:
                        ok, msg = self.simulator.entities.assign_worker_to_building(bid, amount)
                    else:
                        ok, msg = self.simulator.entities.unassign_worker_from_building(bid, -amount)
                    self.message = msg
                    self.message_timer = 2.0
                return cb
            
            if b.worker_capacity > 0 and b.active and not b.destroyed:
                self.dynamic_buttons.append(MenuButton(panel_x + panel_w - btn_w * 2 - 10, btn_y, btn_w, btn_h, "-", callback=make_b_cb(b.id, -1), font_size=max(14, int(18*scale))))
                self.dynamic_buttons.append(MenuButton(panel_x + panel_w - btn_w, btn_y, btn_w, btn_h, "+", callback=make_b_cb(b.id, 1), font_size=max(14, int(18*scale))))
            y += small_font.get_height() + 2
"""
content = content.replace("    def on_back(self):", refresh_code + "\n    def on_back(self):")

# Update handle_event to handle dynamic buttons
event_code = """
        for btn in self.dynamic_buttons:
            if btn.handle_event(event): return True
        for btn in self.breeder_buttons:
            if btn.handle_event(event): return True
"""
content = content.replace("if self.back_button.handle_event(event):\n            return True", "if self.back_button.handle_event(event):\n            return True" + event_code)

# Update update to update dynamic buttons
update_code = """
        for btn in self.dynamic_buttons: btn.update(dt)
        for btn in self.breeder_buttons: btn.update(dt)
"""
content = content.replace("self.back_button.update(dt)", "self.back_button.update(dt)" + update_code)

# Update render overview to show idle population
overview_render_old = """            (f"受光面: {len(zones.get_illuminated_zones())}/{zones.TOTAL_ZONES} 区域",
             (255, 255, 150)),
            (f"显示模式: {self.MODE_NAMES[self.display_mode]}", (150, 180, 220)),"""
overview_render_new = """            (f"总人口: {self.simulator.entities.population.total} | 闲置: {self.simulator.entities.get_idle_population()}", (200, 255, 200)),
            (f"生育分配: {self.simulator.entities.population.breeders} 人", (255, 150, 200)),"""
content = content.replace(overview_render_old, overview_render_new)

# Render buttons in _render_right_panel
btn_render_code = """
        for btn in self.breeder_buttons:
            btn.render(screen)
        for btn in self.dynamic_buttons:
            btn.render(screen)
"""
content = content.replace("        # ── 分隔线 ──", btn_render_code + "\n        # ── 分隔线 ──")

# Render building details
b_render_old = """                b_text = f"• {b.name} [{status}]"
                b_surf = small_font.render(b_text, True, color)"""
b_render_new = """                workers = f"({b.assigned_workers}/{b.worker_capacity})" if b.worker_capacity > 0 else ""
                b_text = f"• {b.name} [{status}] {workers}"
                b_surf = small_font.render(b_text, True, color)"""
content = content.replace(b_render_old, b_render_new)

with open("ui/zone_view_screen.py", "w", encoding="utf-8") as f:
    f.write(content)
