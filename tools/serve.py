#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""serve.py - server UNICO de las tools web del proyecto (carpeta /tools/).

Reemplaza al viejo rigserver.py del pixi. Ahora el rigtool vive en Godot/tools/ y este
server: (1) sirve la raiz del proyecto Godot, (2) expone el arte CRUDO del pixi bajo
/pixi/ (sin duplicarlo) para que el rigtool lo siga leyendo, (3) auto-guarda todo lo que
las tools postean (rig de varas, manos, anims, bolts, y el config del AoE).

Uso:
  1) Pará cualquier server viejo en 8765/8417 (libera los puertos).
  2) py tools/serve.py
  3) Abrí  http://localhost:8765/tools/

Estaticos:  /...  -> raiz Godot   |   /pixi/...  -> raiz del repo pixi (arte v2_test)
Endpoints:  GET  /api/config | /api/aoe | /api/staffs
            POST /api/config | /api/aoe | /api/hand | /api/staff | /api/staffdelete
                 /api/staffanim | /api/boltanim
"""

import json
import os
import base64
import urllib.parse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = 8765

# tools/serve.py -> parent.parent = raiz del proyecto Godot.
GODOT_ROOT = Path(__file__).resolve().parent.parent
# Repo pixi (legacy): contiene el arte crudo v2_test que el rigtool lee. Se expone en /pixi/.
# Portabilidad: se deriva relativa al proyecto Godot (repos hermanos en .../freelance/).
# Si esa ruta no existe, se cae a la ruta absoluta conocida de esta maquina.
PIXI_ROOT = GODOT_ROOT.parent.parent / "la-carcel-del-cuteo"
if not PIXI_ROOT.exists():
    PIXI_ROOT = Path(r"C:\Users\fezub\freelance\la-carcel-del-cuteo")

RIG_DIR = GODOT_ROOT / "tools" / "rig"
RIG_DIR.mkdir(parents=True, exist_ok=True)
CONFIG_PATH = RIG_DIR / "rig_config.json"
HAND_OUT = RIG_DIR / "hands"
AOE_CONFIG = GODOT_ROOT / "assets" / "fx" / "aoe_config.json"

# Carpetas de varas: al insertar/animar/borrar una, se escribe en AMBOS proyectos.
PIXI_STAFFS = PIXI_ROOT / "assets" / "v2_test" / "staffs"
GODOT_STAFFS = GODOT_ROOT / "assets" / "hero" / "staffs"


def _read_json(path: Path) -> dict:
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception as e:
            print(f"[serve] WARN no pude leer {path}: {e}")
    return {}


def _write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=0), encoding="utf-8")
    os.replace(tmp, path)


def _staff_count() -> int:
    n = 0
    while (PIXI_STAFFS / f"staff{n + 1}.png").exists():
        n += 1
    return n


def _to_trash(path: Path) -> None:
    """A la PAPELERA de Windows (recuperable). Si no se puede, backup local. Nunca borra duro."""
    p = os.path.abspath(str(path))
    try:
        import ctypes
        from ctypes import wintypes

        class SHFILEOPSTRUCTW(ctypes.Structure):
            _fields_ = [
                ("hwnd", wintypes.HWND), ("wFunc", wintypes.UINT),
                ("pFrom", wintypes.LPCWSTR), ("pTo", wintypes.LPCWSTR),
                ("fFlags", ctypes.c_uint16), ("fAnyOperationsAborted", wintypes.BOOL),
                ("hNameMappings", ctypes.c_void_p), ("lpszProgressTitle", wintypes.LPCWSTR),
            ]
        op = SHFILEOPSTRUCTW()
        op.wFunc = 3                                # FO_DELETE
        op.pFrom = p + "\x00\x00"                   # lista doble-null terminada
        op.fFlags = 0x0040 | 0x0010 | 0x0004        # ALLOWUNDO | NOCONFIRMATION | SILENT
        rc = ctypes.windll.shell32.SHFileOperationW(ctypes.byref(op))
        if rc != 0:
            raise OSError(f"SHFileOperation rc={rc}")
    except Exception as e:
        import time
        import shutil
        bak = GODOT_ROOT / "tools" / "_deleted_staffs"
        bak.mkdir(parents=True, exist_ok=True)
        dest = bak / f"{path.name}.{int(time.time())}"
        shutil.move(p, str(dest))
        print(f"[serve] (papelera no disponible: {e}) backup -> {dest}")


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=str(GODOT_ROOT), **k)

    # /pixi/... -> filesystem del pixi (arte crudo); el resto -> raiz Godot.
    def translate_path(self, path):
        clean = urllib.parse.unquote(path.split("?", 1)[0].split("#", 1)[0])
        if clean == "/pixi" or clean.startswith("/pixi/"):
            rel = clean[len("/pixi"):]
            parts = [seg for seg in rel.split("/") if seg not in ("", ".", "..")]  # anti-traversal
            return str(PIXI_ROOT.joinpath(*parts)) if parts else str(PIXI_ROOT)
        return super().translate_path(path)

    def _send_json(self, obj, code=200):
        payload = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def _body(self) -> bytes:
        n = int(self.headers.get("Content-Length", 0) or 0)
        return self.rfile.read(n) if n else b""

    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/api/config":
            return self._send_json({"ok": True, "config": _read_json(CONFIG_PATH)})
        if p == "/api/aoe":
            return self._send_json({"ok": True, "config": _read_json(AOE_CONFIG)})
        if p == "/api/staffs":
            return self._send_json({"ok": True, "count": _staff_count()})
        return super().do_GET()

    def do_POST(self):
        p = self.path.split("?")[0]
        try:
            if p == "/api/config":
                data = json.loads(self._body() or b"{}")
                if not isinstance(data, dict):
                    raise ValueError("config no es objeto")
                _write_json(CONFIG_PATH, data)
                print(f"[serve] rig_config.json ({len(data)} claves)")
                return self._send_json({"ok": True, "saved": len(data)})

            if p == "/api/aoe":
                data = json.loads(self._body() or b"{}")
                if not isinstance(data, dict):
                    raise ValueError("config no es objeto")
                _write_json(AOE_CONFIG, data)
                print(f"[serve] aoe_config.json ({len(data.get('flames', []))} llamas)")
                return self._send_json({"ok": True})

            if p == "/api/hand":
                d = json.loads(self._body() or b"{}")
                char = str(d.get("char", "mage"))
                dirn = str(d.get("dir", "south"))
                url = str(d.get("dataURL", ""))
                b64 = url.split(",", 1)[1] if "," in url else url
                out_dir = HAND_OUT / char
                out_dir.mkdir(parents=True, exist_ok=True)
                out = out_dir / f"{dirn}.png"
                out.write_bytes(base64.b64decode(b64))
                print(f"[serve] mano -> {out}")
                return self._send_json({"ok": True, "path": str(out)})

            if p == "/api/staff":
                d = json.loads(self._body() or b"{}")
                url = str(d.get("dataURL", ""))
                b64 = url.split(",", 1)[1] if "," in url else url
                raw = base64.b64decode(b64)
                n = _staff_count() + 1
                PIXI_STAFFS.mkdir(parents=True, exist_ok=True)
                GODOT_STAFFS.mkdir(parents=True, exist_ok=True)
                (PIXI_STAFFS / f"staff{n}.png").write_bytes(raw)
                (GODOT_STAFFS / f"staff{n}.png").write_bytes(raw)
                print(f"[serve] vara nueva -> staff{n}.png (pixi + godot)")
                return self._send_json({"ok": True, "n": n, "count": n})

            if p == "/api/staffdelete":
                d = json.loads(self._body() or b"{}")
                n = int(d.get("staff", 0))
                count = _staff_count()
                if n < 1 or n > count:
                    raise ValueError(f"vara {n} fuera de rango (1..{count})")
                for base in (PIXI_STAFFS, GODOT_STAFFS):
                    for suf in (".png", "_anim", "_bolt"):
                        victim = base / f"staff{n}{suf}"
                        if victim.exists():
                            _to_trash(victim)
                    for i in range(n + 1, count + 1):
                        for suf in (".png", "_anim", "_bolt"):
                            src = base / f"staff{i}{suf}"
                            if src.exists():
                                src.rename(base / f"staff{i - 1}{suf}")
                print(f"[serve] vara {n} eliminada (Papelera); {count - n} renumeradas")
                return self._send_json({"ok": True, "deleted": n, "count": count - 1})

            if p == "/api/staffanim":
                d = json.loads(self._body() or b"{}")
                n = int(d.get("staff", 0))
                frames = d.get("frames", [])
                if n < 1 or not isinstance(frames, list) or not frames:
                    raise ValueError("staff o frames invalidos")
                for base in (PIXI_STAFFS, GODOT_STAFFS):
                    folder = base / f"staff{n}_anim"
                    if folder.exists():
                        for old in folder.glob("frame_*.png"):
                            old.unlink()
                    folder.mkdir(parents=True, exist_ok=True)
                    for i, url in enumerate(frames):
                        b64 = url.split(",", 1)[1] if "," in url else url
                        (folder / f"frame_{i:03d}.png").write_bytes(base64.b64decode(b64))
                print(f"[serve] anim vara {n}: {len(frames)} frames (pixi + godot)")
                return self._send_json({"ok": True, "staff": n, "frames": len(frames)})

            if p == "/api/boltanim":
                d = json.loads(self._body() or b"{}")
                n = int(d.get("staff", 0))
                kind = str(d.get("kind", "")).strip()
                frames = d.get("frames", [])
                if n < 1 or kind not in ("travel", "impact") or not isinstance(frames, list) or not frames:
                    raise ValueError("staff/kind/frames invalidos")
                for base in (PIXI_STAFFS, GODOT_STAFFS):
                    folder = base / f"staff{n}_bolt" / kind
                    if folder.exists():
                        for old in folder.glob("frame_*.png"):
                            old.unlink()
                    folder.mkdir(parents=True, exist_ok=True)
                    for i, url in enumerate(frames):
                        b64 = url.split(",", 1)[1] if "," in url else url
                        (folder / f"frame_{i:03d}.png").write_bytes(base64.b64decode(b64))
                print(f"[serve] bolt {kind} vara {n}: {len(frames)} frames (pixi + godot)")
                return self._send_json({"ok": True, "staff": n, "kind": kind, "frames": len(frames)})
        except Exception as e:
            return self._send_json({"ok": False, "error": str(e)}, 400)
        self.send_error(404)

    def log_message(self, fmt, *args):
        if args and "/api/" in str(args[0]):
            super().log_message(fmt, *args)


def main():
    os.chdir(str(GODOT_ROOT))
    httpd = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"[serve] Godot: {GODOT_ROOT}")
    print(f"[serve] pixi (arte) en /pixi/ -> {PIXI_ROOT}")
    print(f"[serve] tools:  http://localhost:{PORT}/tools/")
    print(f"[serve] rig_config.json -> {CONFIG_PATH}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[serve] chau")
        httpd.shutdown()


if __name__ == "__main__":
    main()
