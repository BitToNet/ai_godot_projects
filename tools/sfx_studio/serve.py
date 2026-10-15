#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""音效调音台 · 本地服务（只用标准库）

为什么需要一个服务，而不是双击 index.html：
  1) 浏览器在 file:// 下既取不到音频素材（fetch 被拦），也写不了磁盘；
  2) 游戏的配置在 Godot 的 user:// 目录里，浏览器按设计就够不着。
所以这里做三件小事：把工程根目录当静态站点发出去（这样 /audio_preview/、/audio/sfx/foley/、
/audio/bgm/ 都能取到素材），再开两个 JSON 接口读写 user://sfx_profile.json。

  GET  /api/health   -> 服务信息：工程名、user:// 目录、配置文件绝对路径、是否已存在
  GET  /api/profile  -> 读配置（不存在就 profile: null）
  POST /api/profile  -> 写配置（原子替换；只允许写这一个路径）

安全边界：默认只监听 127.0.0.1，写入路径由 project.godot 推导，不接受请求里的路径参数。
也就是说，本服务只能改「这个工程的音效配置」，改不了别的文件。
"""

import argparse
import json
import os
import re
import sys
import webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

HERE = Path(__file__).resolve().parent      # tools/sfx_studio
ROOT = HERE.parent.parent                   # 工程根目录（静态站点的根）
PROFILE_NAME = "sfx_profile.json"
STUDIO_URL = "/tools/sfx_studio/"


# --------------------------------------------------------------- project.godot
def _read_project_godot():
    f = ROOT / "project.godot"
    if not f.is_file():
        return ""
    return f.read_text(encoding="utf-8", errors="replace")


def _godot_setting(txt, key, default=None):
    """取 project.godot 里 config/<key> 或 application/config/<key> 的字符串值"""
    for pat in (r'^config/%s\s*=\s*"([^"]*)"' % key,
                r'^application/config/%s\s*=\s*"([^"]*)"' % key):
        m = re.search(pat, txt, re.M)
        if m:
            return m.group(1)
    return default


def project_name():
    return _godot_setting(_read_project_godot(), "name", "unnamed")


def godot_user_dir():
    """Godot 的 user:// 实际落在哪：
    Windows %APPDATA%\\Godot\\app_userdata\\<name>（自定义目录时是 %APPDATA%\\<custom>）
    macOS   ~/Library/Application Support/Godot/app_userdata/<name>
    Linux   ~/.local/share/godot/app_userdata/<name>
    """
    txt = _read_project_godot()
    custom = _godot_setting(txt, "custom_user_dir_name")
    use_custom = "true" in str(_godot_setting(txt, "use_custom_user_dir", "false")).lower()
    name = custom if (use_custom and custom) else project_name()

    if sys.platform.startswith("win"):
        base = Path(os.environ.get("APPDATA", str(Path.home() / "AppData" / "Roaming")))
        return base / name if (use_custom and custom) else base / "Godot" / "app_userdata" / name
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Godot" / "app_userdata" / name
    base = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share")))
    return base / "godot" / "app_userdata" / name


def resolve_profile_path(override=None):
    if override:
        return Path(override).expanduser().resolve()
    env = os.environ.get("WARBAND_SFX_PROFILE_PATH")
    if env:
        return Path(env).expanduser().resolve()
    return godot_user_dir() / PROFILE_NAME


# --------------------------------------------------------------- 读写
def read_profile(path):
    if not path.is_file():
        return None, "配置文件还不存在"
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as e:
        return None, "读不了：%s" % e
    try:
        data = json.loads(raw)
    except ValueError as e:
        return None, "JSON 坏了：%s" % e
    if not isinstance(data, dict):
        return None, "顶层不是对象"
    return data, None


def write_profile(path, data):
    """原子写：先写同目录临时文件再 os.replace，避免游戏正好在启动时读到半截文件"""
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(data, ensure_ascii=False, indent=2, sort_keys=False) + "\n"
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8", newline="\n")
    os.replace(tmp, path)
    return len(text.encode("utf-8"))


# --------------------------------------------------------------- HTTP
class Handler(SimpleHTTPRequestHandler):
    server_version = "SfxStudio/1.0"
    profile_path = None

    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(ROOT), **kw)

    # 只打印 API 调用与 4xx/5xx，静态素材不刷屏
    def log_message(self, fmt, *args):
        line = fmt % args
        if "/api/" in line or " 4" in line or " 5" in line:
            sys.stderr.write("  %s\n" % line)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlsplit(self.path).path
        if path in ("/", "/index.html"):
            self.send_response(302)
            self.send_header("Location", STUDIO_URL)
            self.end_headers()
            return
        if path.endswith("/api/health") or path == "/api/health":
            p = self.profile_path
            self._json({
                "ok": True,
                "mode": "server",
                "project": project_name(),
                "projectRoot": str(ROOT),
                "godotUserDir": str(godot_user_dir()),
                "profilePath": str(p),
                "exists": p.is_file(),
            })
            return
        if path.endswith("/api/profile") or path == "/api/profile":
            data, err = read_profile(self.profile_path)
            self._json({
                "ok": True,
                "available": True,
                "path": str(self.profile_path),
                "exists": data is not None,
                "error": err,
                "profile": data,
            })
            return
        super().do_GET()

    def do_POST(self):
        path = urlsplit(self.path).path
        if not (path.endswith("/api/profile") or path == "/api/profile"):
            self._json({"ok": False, "error": "没有这个接口"}, 404)
            return
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = 0
        if n <= 0 or n > 8 * 1024 * 1024:
            self._json({"ok": False, "error": "请求体为空或过大"}, 400)
            return
        raw = self.rfile.read(n)
        try:
            data = json.loads(raw.decode("utf-8"))
        except (ValueError, UnicodeDecodeError) as e:
            self._json({"ok": False, "error": "JSON 解析失败：%s" % e}, 400)
            return
        if not isinstance(data, dict) or not isinstance(data.get("state"), dict):
            self._json({"ok": False, "error": "缺少 state 对象，拒绝写入"}, 400)
            return
        try:
            size = write_profile(self.profile_path, data)
        except OSError as e:
            self._json({"ok": False, "error": "写文件失败：%s" % e}, 500)
            return
        self._json({"ok": True, "path": str(self.profile_path), "bytes": size})


def port_busy(port):
    import socket
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", port))
        return False
    except OSError:
        return True
    finally:
        s.close()


def main(argv=None):
    ap = argparse.ArgumentParser(description="音效调音台本地服务（静态站点 + user:// 配置读写）")
    ap.add_argument("--port", type=int, default=8787, help="监听端口（默认 8787，被占用会自动往后找）")
    ap.add_argument("--host", default="127.0.0.1", help="监听地址（默认只允许本机）")
    ap.add_argument("--profile-path", default=None, help="直接指定配置文件路径（默认由 project.godot 推导）")
    ap.add_argument("--no-open", action="store_true", help="不要自动打开浏览器")
    ap.add_argument("--print-path", action="store_true", help="只打印配置文件路径就退出")
    args = ap.parse_args(argv)

    path = resolve_profile_path(args.profile_path)
    if args.print_path:
        print(path)
        return 0

    Handler.profile_path = path

    # Windows 上 .js 的 MIME 常被注册表带偏，显式钉住
    Handler.extensions_map = dict(SimpleHTTPRequestHandler.extensions_map)
    Handler.extensions_map.update({
        ".js": "text/javascript",
        ".mjs": "text/javascript",
        ".json": "application/json",
        ".css": "text/css",
        ".html": "text/html; charset=utf-8",
        ".wav": "audio/wav",
        ".ogg": "audio/ogg",
        ".md": "text/markdown; charset=utf-8",
    })

    port = args.port
    while port_busy(port) and port < args.port + 20:
        port += 1
    httpd = ThreadingHTTPServer((args.host, port), Handler)
    url = "http://%s:%d%s" % (args.host, port, STUDIO_URL)

    print("=" * 68)
    print("  音效调音台 · 本地服务已启动")
    print("  工程      : %s" % project_name())
    print("  工程根目录: %s" % ROOT)
    print("  配置文件  : %s%s" % (path, "" if path.is_file() else "   （还没有，保存后生成）"))
    print("  地址      : %s" % url)
    print("  停止      : 在这个窗口按 Ctrl+C")
    print("=" * 68)

    missing = [s for s in ("audio_preview", "audio/sfx/foley", "audio/bgm") if not (ROOT / s).is_dir()]
    if missing:
        print("  [提示] 缺素材目录：%s —— 先跑一次 tools/sfx_studio/start.ps1 生成试听音频。"
              % "、".join(missing))
    if not args.no_open:
        try:
            webbrowser.open(url)
        except Exception as e:      # 打不开浏览器不算致命，手点地址一样用
            print("  [提示] 自动打开浏览器失败（%s），手动访问上面的地址即可。" % e)

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n  已停止。")
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())