"""存档管理器 - 统一管理扫描、保存、加载、删除存档"""

import os
import json
import glob
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime


SAVES_DIR = "data/saves"


class SaveInfo:
    """存档元信息（不含完整 game_state）"""

    def __init__(self, filepath: str, save_name: str, universe_name: str,
                 save_time: str, game_day: int, is_legacy: bool = False):
        self.filepath = filepath
        self.save_name = save_name
        self.universe_name = universe_name
        self.save_time = save_time
        self.game_day = game_day
        self.is_legacy = is_legacy  # 旧格式存档标记

    def __repr__(self):
        return f"<SaveInfo '{self.save_name}' day={self.game_day}>"


class SaveManager:
    """存档管理器

    存档文件格式：
    {
        "save_name": "混沌纪元_Day42",
        "universe_name": "混沌纪元",
        "save_time": "2026-04-26 14:15:00",
        "game_day": 42,
        "game_state": { ... }
    }
    """

    def __init__(self, saves_dir: str = SAVES_DIR):
        self.saves_dir = saves_dir
        os.makedirs(self.saves_dir, exist_ok=True)

    def scan_saves(self) -> Dict[str, List[SaveInfo]]:
        """扫描所有存档文件，返回按宇宙分组的 SaveInfo 列表，每个列表按时间倒序"""
        saves_by_universe: Dict[str, List[SaveInfo]] = {}

        # 扫描根目录的遗留存档（*.json）
        for filepath in glob.glob(os.path.join(self.saves_dir, "*.json")):
            info = self._read_save_info(filepath)
            if info:
                uni = info.universe_name
                if uni not in saves_by_universe:
                    saves_by_universe[uni] = []
                saves_by_universe[uni].append(info)
                
        # 扫描各个宇宙文件夹
        for item in os.listdir(self.saves_dir):
            item_path = os.path.join(self.saves_dir, item)
            if os.path.isdir(item_path):
                for filepath in glob.glob(os.path.join(item_path, "*.json")):
                    info = self._read_save_info(filepath)
                    if info:
                        uni = info.universe_name
                        if uni not in saves_by_universe:
                            saves_by_universe[uni] = []
                        saves_by_universe[uni].append(info)

        # 排序
        for uni in saves_by_universe:
            saves_by_universe[uni].sort(key=lambda s: s.save_time, reverse=True)
            
        return saves_by_universe

    def scan_universes(self) -> List[Dict[str, Any]]:
        """扫描所有宇宙并返回摘要信息列表（名称、存档数、最新存档时间）"""
        grouped_saves = self.scan_saves()
        universes = []
        for uni_name, saves in grouped_saves.items():
            if not saves: continue
            universes.append({
                "name": uni_name,
                "count": len(saves),
                "latest_time": saves[0].save_time,
                "latest_filepath": saves[0].filepath
            })
        # 按最新存档时间倒序排序
        universes.sort(key=lambda u: u["latest_time"], reverse=True)
        return universes

    def universe_exists(self, name: str) -> bool:
        """检查宇宙名称是否存在（忽略大小写，防止同名冲突）"""
        target_name = self._sanitize_filename(name).lower()
        if not target_name: return False
        
        # 检查文件夹
        for item in os.listdir(self.saves_dir):
            if os.path.isdir(os.path.join(self.saves_dir, item)):
                if item.lower() == target_name:
                    return True
                    
        # 检查内部命名（包含遗留存档）
        grouped = self.scan_saves()
        for u_name in grouped.keys():
            if self._sanitize_filename(u_name).lower() == target_name:
                return True
                
        return False

    def _read_save_info(self, filepath: str) -> Optional[SaveInfo]:
        """读取单个存档的元信息（不加载完整 game_state）"""
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except (json.JSONDecodeError, IOError, OSError):
            return None

        # 检测旧格式（有 slot 字段）
        if "slot" in data and "save_name" not in data:
            # 旧格式存档
            slot_id = data.get("slot", 0)
            return SaveInfo(
                filepath=filepath,
                save_name=f"旧存档_{slot_id}",
                universe_name="旧存档",
                save_time=data.get("save_time", "未知时间"),
                game_day=data.get("game_day", 0),
                is_legacy=True,
            )

        # 新格式
        return SaveInfo(
            filepath=filepath,
            save_name=data.get("save_name", os.path.basename(filepath)),
            universe_name=data.get("universe_name", "未命名"),
            save_time=data.get("save_time", "未知时间"),
            game_day=data.get("game_day", 0),
            is_legacy=False,
        )

    def save_game(self, simulator, save_name: str,
                  universe_name: str = "") -> Tuple[bool, str]:
        """保存游戏

        Args:
            simulator: GameSimulator 实例
            save_name: 存档显示名称
            universe_name: 宇宙名称

        Returns:
            (success, message)
        """
        if not universe_name:
            universe_name = getattr(simulator, 'universe_name', '未命名宇宙')

        game_day = max(1, int(simulator.time))
        now_str = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

        save_data = {
            "save_name": save_name,
            "universe_name": universe_name,
            "save_time": now_str,
            "game_day": game_day,
            "game_state": simulator.to_dict(),
        }

        # 用时间戳生成唯一文件名
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        safe_save = self._sanitize_filename(save_name)
        safe_universe = self._sanitize_filename(universe_name)
        
        # 将存档放到独立的宇宙文件夹中
        uni_dir = os.path.join(self.saves_dir, safe_universe)
        os.makedirs(uni_dir, exist_ok=True)
        
        filename = f"{timestamp}_{safe_save}.json"
        filepath = os.path.join(uni_dir, filename)

        try:
            with open(filepath, 'w', encoding='utf-8') as f:
                json.dump(save_data, f, indent=2, ensure_ascii=False)
            return True, f"已保存: {save_name}"
        except Exception as e:
            return False, f"保存失败: {e}"

    def quick_save(self, simulator) -> Tuple[bool, str]:
        """快速存档 — 自动命名为 {宇宙名}_Day{天数}"""
        universe_name = getattr(simulator, 'universe_name', '未命名宇宙')
        game_day = max(1, int(simulator.time))
        save_name = f"{universe_name}_Day{game_day}"
        return self.save_game(simulator, save_name, universe_name)

    def load_game(self, filepath: str, simulator) -> Tuple[bool, str]:
        """加载指定存档

        Args:
            filepath: 存档文件路径
            simulator: GameSimulator 实例

        Returns:
            (success, message)
        """
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except Exception as e:
            return False, f"读取存档失败: {e}"

        # 提取 game_state
        game_state = data.get("game_state", {})
        if not game_state:
            return False, "存档数据为空"

        try:
            simulator.from_dict(game_state)
        except Exception as e:
            return False, f"恢复状态失败: {e}"

        # 恢复宇宙名
        universe_name = data.get("universe_name", "")
        if not universe_name:
            # 旧格式没有 universe_name
            universe_name = "旧存档"
        simulator.universe_name = universe_name

        save_name = data.get("save_name", os.path.basename(filepath))
        return True, f"已加载: {save_name}"

    def delete_save(self, filepath: str) -> Tuple[bool, str]:
        """删除存档文件，如果所在宇宙文件夹为空则一并删除
        
        Args:
            filepath: 存档文件路径

        Returns:
            (success, message)
        """
        try:
            if os.path.exists(filepath):
                os.remove(filepath)
                # 尝试删除空文件夹
                parent_dir = os.path.dirname(filepath)
                # 确保 parent_dir 是在 self.saves_dir 之下的第一级子目录
                if os.path.abspath(parent_dir) != os.path.abspath(self.saves_dir) and os.path.isdir(parent_dir):
                    if not os.listdir(parent_dir):
                        try:
                            os.rmdir(parent_dir)
                        except OSError:
                            pass
                return True, "存档已删除"
            return False, "存档文件不存在"
        except Exception as e:
            return False, f"删除失败: {e}"

    def delete_universe(self, universe_name: str) -> Tuple[bool, str]:
        """删除整个宇宙档案及其所有存档"""
        try:
            target_name = self._sanitize_filename(universe_name).lower()
            if not target_name: return False, "无效的宇宙名称"

            deleted_count = 0
            
            # 删除遗留存档中的同名档
            for filepath in glob.glob(os.path.join(self.saves_dir, "*.json")):
                info = self._read_save_info(filepath)
                if info and self._sanitize_filename(info.universe_name).lower() == target_name:
                    os.remove(filepath)
                    deleted_count += 1
            
            # 找到对应的文件夹并清空删除
            for item in os.listdir(self.saves_dir):
                item_path = os.path.join(self.saves_dir, item)
                if os.path.isdir(item_path) and item.lower() == target_name:
                    for filepath in glob.glob(os.path.join(item_path, "*.json")):
                        os.remove(filepath)
                        deleted_count += 1
                    try:
                        os.rmdir(item_path)
                    except OSError:
                        pass
                        
            if deleted_count > 0:
                return True, f"已删除宇宙，清理 {deleted_count} 个存档"
            return False, "未找到该宇宙的存档"
        except Exception as e:
            return False, f"删除宇宙失败: {e}"

    def find_latest_save(self) -> Optional[SaveInfo]:
        """找到全局最新的存档"""
        all_saves = []
        for saves in self.scan_saves().values():
            all_saves.extend(saves)
        if not all_saves: return None
        all_saves.sort(key=lambda s: s.save_time, reverse=True)
        return all_saves[0]

    @staticmethod
    def _sanitize_filename(name: str) -> str:
        """清理文件名中的非法字符"""
        illegal = '<>:"/\\|?*'
        result = name
        for c in illegal:
            result = result.replace(c, '_')
        return result.strip().strip('.')[:50]  # 限制长度
