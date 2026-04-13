"""
core/manifest.py — VaultApp V5 文件状态与清单管理模块

设计规范（V5定稿）：
  · SQLite3 WAL 模式
  · 包含快速预检字段：file_size, last_modified
  · 强制串行写入：所有写操作通过 queue.Queue 交由单线程批量处理
  · 批量事务：每50条或超2秒提交一次，失败整批回滚
  · 启动修复机制：完整性检查，损坏自动回滚.bak，重置UPLOADING状态
"""

import sqlite3
import queue
import threading
import time
import os
import shutil
from typing import Dict, Any, List, Optional


class ManifestDB:
    def __init__(self, db_path: str):
        """
        初始化清单数据库。
        Args:
            db_path: manifest.db 的绝对路径
        """
        self.db_path = db_path
        self.bak_path = f"{db_path}.bak"
        
        # 写入队列与后台线程
        self.write_queue = queue.Queue()
        self._stop_event = threading.Event()
        self._writer_thread: Optional[threading.Thread] = None
        
        self._init_db()

    # ═════════════════════════════════════════════════════════════════════════
    # 数据库初始化与自我修复
    # ═════════════════════════════════════════════════════════════════════════

    def _init_db(self):
        """初始化表结构与 Pragma 设置"""
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        
        with sqlite3.connect(self.db_path) as conn:
            # 开启 WAL 模式以支持高并发读
            conn.execute("PRAGMA journal_mode=WAL;")
            conn.execute("PRAGMA synchronous=NORMAL;")
            
            conn.execute("""
                CREATE TABLE IF NOT EXISTS files (
                    path_hash       TEXT PRIMARY KEY,
                    rel_path        TEXT NOT NULL,
                    plain_hash      TEXT,
                    file_size       INTEGER,
                    last_modified   TEXT,
                    enc_filename    TEXT,
                    status          TEXT DEFAULT 'PENDING',
                    retry_count     INTEGER DEFAULT 0,
                    fail_reason     TEXT,
                    updated_at      TEXT
                )
            """)

    def check_and_recover(self) -> bool:
        """
        启动检查：验证完整性，必要时从备份恢复，并重置中断的上传状态。
        Returns:
            bool: 如果数据完整或成功修复返回 True，若彻底损坏需全量同步返回 False。
        """
        needs_rebuild = False
        
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("PRAGMA integrity_check;")
                result = cursor.fetchone()[0]
                if result != "ok":
                    needs_rebuild = True
        except sqlite3.DatabaseError:
            needs_rebuild = True

        if needs_rebuild:
            if os.path.exists(self.bak_path):
                # 尝试从备份恢复
                try:
                    shutil.copy2(self.bak_path, self.db_path)
                    # 再次检查备份的完整性
                    with sqlite3.connect(self.db_path) as conn:
                        if conn.execute("PRAGMA integrity_check;").fetchone()[0] != "ok":
                            raise ValueError("备份文件也已损坏")
                except Exception:
                    # 彻底损坏，清空重建
                    os.remove(self.db_path)
                    self._init_db()
                    return False
            else:
                os.remove(self.db_path)
                self._init_db()
                return False

        # 重置上次异常退出导致的僵尸状态
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("UPDATE files SET status = 'PENDING' WHERE status = 'UPLOADING'")
            conn.commit()
            
        return True

    def backup(self):
        """执行检查点合并并备份数据库（同步引擎每分钟调用）"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute("PRAGMA wal_checkpoint(TRUNCATE);")
            shutil.copy2(self.db_path, self.bak_path)
        except Exception as e:
            print(f"备份 manifest 失败: {e}")

    # ═════════════════════════════════════════════════════════════════════════
    # 读操作 (允许在任何工作线程中并发调用)
    # ═════════════════════════════════════════════════════════════════════════

    def get_file_meta(self, path_hash: str) -> Optional[Dict[str, Any]]:
        """获取单个文件的元数据（用于快速预检）"""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute("SELECT * FROM files WHERE path_hash = ?", (path_hash,))
            row = cursor.fetchone()
            return dict(row) if row else None

    # ═════════════════════════════════════════════════════════════════════════
    # 串行写操作与后台队列引擎
    # ═════════════════════════════════════════════════════════════════════════

    def enqueue_write(self, task: Dict[str, Any]):
        """
        其他工作线程通过此接口提交写任务，不直接操作 DB。
        Args:
            task: 包含更新字段的字典，必须包含 'path_hash'
        """
        self.write_queue.put(task)

    def start_writer_thread(self):
        """启动专用的后台写线程"""
        if self._writer_thread is not None and self._writer_thread.is_alive():
            return
            
        self._stop_event.clear()
        self._writer_thread = threading.Thread(target=self._writer_loop, daemon=True)
        self._writer_thread.start()

    def stop_writer_thread(self):
        """停止写线程，会等待队列中剩余任务处理完毕"""
        self._stop_event.set()
        if self._writer_thread:
            self._writer_thread.join(timeout=5.0)

    def _writer_loop(self):
        """核心批量写入循环（唯一操作 DB 写入的线程）"""
        batch: List[Dict[str, Any]] = []
        last_commit_time = time.time()
        
        while not self._stop_event.is_set() or not self.write_queue.empty():
            try:
                # 阻塞获取，超时时间0.5秒用于定期检查是否需要超时提交或退出
                task = self.write_queue.get(timeout=0.5)
                batch.append(task)
            except queue.Empty:
                pass
                
            current_time = time.time()
            time_elapsed = current_time - last_commit_time
            
            # 触发提交的条件：积累50条，或距上次提交超2秒且队列非空，或要求停止时
            if len(batch) >= 50 or (len(batch) > 0 and time_elapsed >= 2.0) or (self._stop_event.is_set() and len(batch) > 0):
                self._commit_batch(batch)
                batch.clear()
                last_commit_time = time.time()

    def _commit_batch(self, batch: List[Dict[str, Any]]):
        """执行整批事务"""
        with sqlite3.connect(self.db_path) as conn:
            try:
                # 开启事务
                conn.execute("BEGIN TRANSACTION;")
                
                # 先整批保存，防止后续错误恢复时作用域泄露
                saved_hashes = [task['path_hash'] for task in batch]
                
                for task in batch:
                    path_hash = task.pop('path_hash')
                    task['updated_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
                    
                    # 动态构建 UPSERT 语句 (SQLite 3.24+ 支持)
                    # 先查是否存在，如果存在则更新提供的字段，不存在则插入
                    columns = list(task.keys())
                    placeholders = ", ".join(["?"] * len(columns))
                    
                    # 构建 UPDATE 语句部分
                    update_stmt = ", ".join([f"{col}=excluded.{col}" for col in columns])
                    
                    sql = f"""
                        INSERT INTO files (path_hash, {', '.join(columns)})
                        VALUES (?, {placeholders})
                        ON CONFLICT(path_hash) DO UPDATE SET
                        {update_stmt};
                    """
                    
                    values = [path_hash] + [task[col] for col in columns]
                    conn.execute(sql, values)
                    
                conn.commit()
            except Exception as e:
                # 发生异常，整批回滚
                conn.rollback()
                print(f"批量写入 manifest 失败，已回滚: {e}")
                
                # 将任务标记为PENDING并重新放回队列（这里简化处理，实际中可增加重试计数防死循环）
                for task, original_hash in zip(batch, saved_hashes):
                    task['status'] = 'PENDING'
                    task['path_hash'] = original_hash   # 用各自保存的原始 hash 还原
                    self.write_queue.put(task)
