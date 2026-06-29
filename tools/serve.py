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
import re
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
# Polígono de COLISIÓN por pieza de muro (cell-local), editado a mano en wall_origin_tool.html.
# Forma: { "<key_pieza>": [[x,y],...] }  (mismas claves que el texture_origin: wall_nw, corner_top, ...)
WALL_COLLISION_PATH = RIG_DIR / "wall_collision.json"
HAND_OUT = RIG_DIR / "hands"
AOE_CONFIG = GODOT_ROOT / "assets" / "fx" / "aoe_config.json"
SPELLS_CFG = RIG_DIR / "spells.json"
SPELL_ASSETS = GODOT_ROOT / "assets" / "fx" / "spells"
FONT_DIR = GODOT_ROOT / "assets" / "fonts"
FONT_INDEX = FONT_DIR / "font_index.json"

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


def _res_to_path(res_path: str) -> Path:
    if not res_path.startswith("res://"):
        raise ValueError("ruta res:// invalida")
    rel = res_path[len("res://"):].replace("/", os.sep)
    out = (GODOT_ROOT / rel).resolve()
    if GODOT_ROOT.resolve() not in out.parents and out != GODOT_ROOT.resolve():
        raise ValueError("ruta fuera del proyecto")
    return out


def _font_index() -> dict:
    data = _read_json(FONT_INDEX)
    fonts = data.get("fonts", [])
    if not isinstance(fonts, list):
        fonts = []
    return {"fonts": fonts}


def _font_entry(font_id: str) -> dict:
    for entry in _font_index().get("fonts", []):
        if entry.get("id") == font_id or entry.get("font") == font_id:
            return entry
    raise ValueError(f"font no encontrada en font_index.json: {font_id}")


def _parse_bmfont(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    meta = {}
    chars = []
    page_file = ""
    for line in lines:
        if line.startswith("common "):
            for key in ("lineHeight", "base", "scaleW", "scaleH"):
                m = re.search(rf"\b{key}=(-?\d+)", line)
                if m:
                    meta[key] = int(m.group(1))
        elif line.startswith("page "):
            m = re.search(r'\bfile="([^"]+)"', line)
            if m:
                page_file = m.group(1)
        elif line.startswith("char "):
            item = {}
            for key in ("id", "x", "y", "width", "height", "xoffset", "yoffset", "xadvance", "page", "chnl"):
                m = re.search(rf"\b{key}=(-?\d+)", line)
                if m:
                    item[key] = int(m.group(1))
            if "id" in item:
                item["char"] = chr(item["id"])
                chars.append(item)
    return {"meta": meta, "page_file": page_file, "chars": chars, "line_count": len(lines)}


def _apply_bmfont_metrics(path: Path, changes: dict) -> int:
    if not isinstance(changes, dict):
        raise ValueError("changes debe ser un objeto")
    allowed = {"x", "y", "width", "height", "xoffset", "yoffset", "xadvance"}
    normalized = {}
    for key, values in changes.items():
        if not isinstance(values, dict):
            continue
        glyph = key if len(key) == 1 else chr(int(key))
        normalized[ord(glyph)] = {k: int(v) for k, v in values.items() if k in allowed and v is not None}

    lines = path.read_text(encoding="utf-8").splitlines()
    changed = 0
    out = []
    for line in lines:
        if not line.startswith("char "):
            out.append(line)
            continue
        m = re.search(r"\bid=(-?\d+)", line)
        if not m:
            out.append(line)
            continue
        char_id = int(m.group(1))
        patch = normalized.get(char_id)
        if not patch:
            out.append(line)
            continue
        for field, value in patch.items():
            if re.search(rf"\b{field}=-?\d+", line):
                line = re.sub(rf"\b{field}=-?\d+", f"{field}={value}", line)
        changed += 1
        out.append(line)

    if changed:
        bak = path.with_suffix(path.suffix + ".bak")
        bak.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
        path.write_text("\n".join(out) + "\n", encoding="utf-8")
    return changed


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
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        if p == "/api/config":
            return self._send_json({"ok": True, "config": _read_json(CONFIG_PATH)})
        if p == "/api/aoe":
            return self._send_json({"ok": True, "config": _read_json(AOE_CONFIG)})
        if p == "/api/staffs":
            return self._send_json({"ok": True, "count": _staff_count()})
        if p == "/api/spellcfg":
            return self._send_json({"ok": True, "config": _read_json(SPELLS_CFG)})
        if p == "/api/wallcollision":
            return self._send_json({"ok": True, "config": _read_json(WALL_COLLISION_PATH)})
        if p == "/api/fonts":
            return self._send_json({"ok": True, **_font_index()})
        if p == "/api/fontmetrics":
            try:
                font_id = (q.get("font") or [""])[0]
                entry = _font_entry(font_id)
                font_path = _res_to_path(entry["font"])
                parsed = _parse_bmfont(font_path)
                atlas = entry.get("atlas") or str(Path(entry["font"]).with_suffix(".png"))
                return self._send_json({"ok": True, "entry": entry, "atlas": atlas, **parsed})
            except Exception as e:
                return self._send_json({"ok": False, "error": str(e)}, 400)
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

            if p == "/api/spellcfg":
                data = json.loads(self._body() or b"{}")
                if not isinstance(data, dict):
                    raise ValueError("spellcfg no es objeto")
                _write_json(SPELLS_CFG, data)
                print(f"[serve] spells.json ({len(data)} varas)")
                return self._send_json({"ok": True, "saved": len(data)})

            if p == "/api/wallcollision":
                # Guarda el polígono de colisión por pieza de muro (cell-local) -> wall_collision.json.
                data = json.loads(self._body() or b"{}")
                if not isinstance(data, dict):
                    raise ValueError("wallcollision no es objeto")
                _write_json(WALL_COLLISION_PATH, data)
                print(f"[serve] wall_collision.json ({len(data)} piezas)")
                return self._send_json({"ok": True, "saved": len(data)})

            if p == "/api/spellasset":
                d = json.loads(self._body() or b"{}")
                n = int(d.get("staff", 0))
                slot = str(d.get("slot", "")).strip()
                url = str(d.get("dataURL", ""))
                if n < 1 or not re.match(r"^[a-z0-9_]+$", slot) or not url:
                    raise ValueError("staff/slot/dataURL invalidos")
                b64 = url.split(",", 1)[1] if "," in url else url
                out_dir = SPELL_ASSETS / f"staff{n}"
                out_dir.mkdir(parents=True, exist_ok=True)
                out = out_dir / f"{slot}.png"
                out.write_bytes(base64.b64decode(b64))
                rel = str(out.relative_to(GODOT_ROOT)).replace("\\", "/")
                print(f"[serve] spell asset -> {rel}")
                return self._send_json({"ok": True, "path": rel})

            if p == "/api/fontmetrics":
                d = json.loads(self._body() or b"{}")
                entry = _font_entry(str(d.get("font", "")))
                changed = _apply_bmfont_metrics(_res_to_path(entry["font"]), d.get("changes", {}))
                print(f"[serve] font metrics {entry.get('id')}: {changed} glifos")
                return self._send_json({"ok": True, "changed": changed, "font": entry.get("font")})
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
