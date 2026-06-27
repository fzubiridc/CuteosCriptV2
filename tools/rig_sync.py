#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rig_sync.py — Converter rigtool -> juego Godot (UNA sola direccion).

El rigtool es la FUENTE DE VERDAD para el rig de las varas (STAFF_RIG).
Este script sincroniza ese rig hacia data.gd SIN pisar las varas que en el
rigtool quedaron en su valor por defecto (las varas "buenas" 1-9 del juego
viven en default dentro del rigtool, asi que NO hay que tocarlas).

Flujo:
  rig_config.json  (rigtool)  --->  STAFF_RIG en data.gd  (juego)

Solo stdlib. Comentarios en espanol.
"""

import argparse
import json
import re
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# Rutas del proyecto. Portabilidad: se derivan relativas a este script.
# rig_sync.py vive en tools/, asi que parent.parent = raiz del proyecto Godot.
# Si la raiz derivada no existe (caso raro), se cae a la ruta absoluta de esta maquina.
# --------------------------------------------------------------------------
GODOT_ROOT = Path(__file__).resolve().parent.parent
if not GODOT_ROOT.exists():
    GODOT_ROOT = Path(
        r"C:\Users\fezub\freelance\Godot-Cuteos-Cript\godot-cuteos-cript"
    )
CONFIG_PATH = GODOT_ROOT / "tools" / "rig" / "rig_config.json"
DATA_PATH = GODOT_ROOT / "scripts" / "autoload" / "data.gd"

# Clave dentro del rig_config.json cuyo VALOR es a su vez un string JSON.
CONFIG_KEY = "walktest:v2"

# fps de animacion de ataque: default 18. Las varas con animfps != 18 se
# sincronizan a `const STAFF_ANIM_FPS := {...}` en data.gd (bloque aparte).
DEF_ANIMFPS = 18
ANIMFPS_RE = re.compile(r"const\s+STAFF_ANIM_FPS\s*:=\s*\{[^}]*\}")

# --------------------------------------------------------------------------
# Default del rigtool (defStaff). Si un staff del config es IGUAL a esto,
# se considera "sin riggear" y NO se pisa el valor que ya tiene data.gd.
# --------------------------------------------------------------------------
DEF_STAFF = {
    "grip": {"x": 32, "y": 46},
    "focus": {"x": 32, "y": 8},
    "spx": 64,
    "rot": 0,
}

# Default razonable para staffs nuevos que tampoco existen en data.gd
# (mismo perfil que defStaff, ya en el formato interno del juego).
DEFAULT_ENTRY = {
    "grip": {"x": 32, "y": 46},
    "focus": {"x": 32, "y": 8},
    "rot_deg": 0,
    "spx": 64,
}

# --------------------------------------------------------------------------
# Formato del bloque (replicado 1:1 de data.gd).
#   indentacion = TAB; line ending = LF.
#   "rot_deg" se alinea a la columna ROT_COL, "spx" a la columna SPX_COL,
#   con un MINIMO de 1 espacio (si el contenido se pasa, no se recorta:
#   ej. staff11 con focus x=101 empuja ambas columnas +1).
# --------------------------------------------------------------------------
ROT_COL = 59
SPX_COL = 75

# Regex para parsear cada entrada ACTUAL de STAFF_RIG en data.gd.
# Captura grip x/y, focus x/y, rot_deg, spx y el comentario de cola TAL CUAL
# (con su "#..." completo) para poder conservarlo byte a byte.
ENTRY_RE = re.compile(
    r'\{\s*"grip"\s*:\s*\{\s*"x"\s*:\s*(-?\d+)\s*,\s*"y"\s*:\s*(-?\d+)\s*\}\s*,'
    r'\s*"focus"\s*:\s*\{\s*"x"\s*:\s*(-?\d+)\s*,\s*"y"\s*:\s*(-?\d+)\s*\}\s*,'
    r'\s*"rot_deg"\s*:\s*(-?\d+)\s*,'
    r'\s*"spx"\s*:\s*(-?\d+)\s*\}\s*,?'
    r'(.*)$'
)


def fmt_entry(grip, focus, rot_deg, spx, comment):
    """Arma UNA linea de STAFF_RIG con el padding por columnas exacto.

    `comment` es el texto de cola completo (ej. '# staff1') o '' si no hay.
    Se antepone con dos espacios, igual que en el original.
    """
    s = '\t{"grip": {"x": %d, "y": %d}, "focus": {"x": %d, "y": %d},' % (
        grip["x"], grip["y"], focus["x"], focus["y"]
    )
    # padding hasta "rot_deg" (minimo 1 espacio)
    pad = ROT_COL - len(s)
    if pad < 1:
        pad = 1
    s += " " * pad
    s += '"rot_deg": %d,' % rot_deg
    # padding hasta "spx" (minimo 1 espacio)
    pad = SPX_COL - len(s)
    if pad < 1:
        pad = 1
    s += " " * pad
    s += '"spx": %d}' % spx
    s += ","
    if comment:
        s += "  " + comment
    return s


def parse_current_block(text):
    """Encuentra el bloque `const STAFF_RIG := [ ... ]` en data.gd.

    Devuelve (start_idx, end_idx, entries) donde:
      - start_idx/end_idx son indices de caracter que delimitan el bloque
        COMPLETO (desde 'const STAFF_RIG' hasta el ']' de cierre, sin el
        salto de linea final).
      - entries es una lista de dicts con grip/focus/rot_deg/spx/comment
        parseados de las lineas actuales (para poder conservarlos).
    Si no encuentra el bloque, devuelve None.
    """
    # Localizar el inicio del bloque.
    m = re.search(r"const\s+STAFF_RIG\s*:=\s*\[", text)
    if not m:
        return None
    start_idx = m.start()

    # Buscar el primer ']' a partir del '[' de apertura. Las entradas no
    # contienen ']' propios, asi que el primer ']' cierra el array.
    open_bracket = text.index("[", m.end() - 1)
    close_bracket = text.find("]", open_bracket)
    if close_bracket == -1:
        return None
    end_idx = close_bracket + 1  # incluir el ']'

    inner = text[open_bracket + 1:close_bracket]

    # Parsear cada linea con contenido del interior del array.
    entries = []
    for raw in inner.split("\n"):
        line = raw.strip()
        if not line:
            continue
        em = ENTRY_RE.search(line)
        if not em:
            # Linea rara dentro del bloque: la ignoramos para el parseo de
            # conservacion, pero no rompemos (el bloque igual se reescribe).
            continue
        gx, gy, fx, fy, rot, spx, tail = em.groups()
        comment = tail.strip()  # ej. '# staff1' o ''
        entries.append({
            "grip": {"x": int(gx), "y": int(gy)},
            "focus": {"x": int(fx), "y": int(fy)},
            "rot_deg": int(rot),
            "spx": int(spx),
            "comment": comment,
        })

    return (start_idx, end_idx, entries)


def load_config_staffs():
    """Lee rig_config.json -> string JSON de CONFIG_KEY -> objeto ST.

    Devuelve la lista ST["staff"].
    """
    if not CONFIG_PATH.exists():
        sys.exit("ERROR: no existe el config del rigtool: %s" % CONFIG_PATH)
    outer = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    if CONFIG_KEY not in outer:
        sys.exit('ERROR: el config no tiene la clave "%s".' % CONFIG_KEY)
    inner = json.loads(outer[CONFIG_KEY])  # el valor es un STRING JSON
    staffs = inner.get("staff")
    if not isinstance(staffs, list):
        sys.exit('ERROR: ST["staff"] no es una lista en el config.')
    return staffs


def is_default(cfg_staff):
    """True si el staff del rigtool esta en su valor por defecto (defStaff)."""
    return (
        cfg_staff.get("grip", {}).get("x") == DEF_STAFF["grip"]["x"]
        and cfg_staff.get("grip", {}).get("y") == DEF_STAFF["grip"]["y"]
        and cfg_staff.get("focus", {}).get("x") == DEF_STAFF["focus"]["x"]
        and cfg_staff.get("focus", {}).get("y") == DEF_STAFF["focus"]["y"]
        and cfg_staff.get("spx") == DEF_STAFF["spx"]
        and cfg_staff.get("rot") == DEF_STAFF["rot"]
    )


def cfg_to_entry(cfg_staff):
    """Mapea un staff del rigtool al dict interno del juego (sin comentario).

    Mapeo de campos: grip->grip, focus->focus, spx->spx, rot->rot_deg.
    """
    return {
        "grip": {"x": cfg_staff["grip"]["x"], "y": cfg_staff["grip"]["y"]},
        "focus": {"x": cfg_staff["focus"]["x"], "y": cfg_staff["focus"]["y"]},
        "rot_deg": cfg_staff["rot"],
        "spx": cfg_staff["spx"],
    }


def build_merged_entries(cfg_staffs, current_entries):
    """Aplica la logica de merge y devuelve (final_entries, acciones).

    final_entries: lista de dicts grip/focus/rot_deg/spx/comment listos.
    acciones: lista de strings para el resumen.
    """
    final = []
    acciones = []
    n = max(len(cfg_staffs), len(current_entries))

    for i in range(n):
        cfg = cfg_staffs[i] if i < len(cfg_staffs) else None
        cur = current_entries[i] if i < len(current_entries) else None
        label = "staff%d" % (i + 1)

        if cfg is None:
            # No hay staff en el config para este indice: conservamos data.gd
            # tal cual (no deberia pasar si config >= data.gd, pero seguro).
            final.append(dict(cur))
            acciones.append("[conserva] %s (no esta en config)" % label)
            continue

        default = is_default(cfg)

        if not default:
            # Staff riggeado en el rigtool -> usar valores del config.
            entry = cfg_to_entry(cfg)
            # Comentario: conservar el que ya tenia data.gd (puede traer notas
            # tipo "(riggeada en rigtool ...)"); si es nuevo, usar "# staffN".
            if cur is not None and cur.get("comment"):
                entry["comment"] = cur["comment"]
            else:
                entry["comment"] = "# " + label
            final.append(entry)
            if cur is None:
                acciones.append("[AGREGA]  %s (riggeado en rigtool)" % label)
            else:
                same = (
                    cur["grip"] == entry["grip"]
                    and cur["focus"] == entry["focus"]
                    and cur["rot_deg"] == entry["rot_deg"]
                    and cur["spx"] == entry["spx"]
                )
                if same:
                    acciones.append(
                        "[=igual=] %s (config == data.gd)" % label
                    )
                else:
                    acciones.append(
                        "[ACTUALIZA] %s grip=(%d,%d) focus=(%d,%d) "
                        "rot=%d spx=%d" % (
                            label,
                            entry["grip"]["x"], entry["grip"]["y"],
                            entry["focus"]["x"], entry["focus"]["y"],
                            entry["rot_deg"], entry["spx"],
                        )
                    )
        else:
            # Staff en default en el rigtool -> NO pisar.
            if cur is not None:
                final.append(dict(cur))
                acciones.append(
                    "[conserva] %s (default en rigtool)" % label
                )
            else:
                # No existe en data.gd y es default -> default razonable.
                entry = dict(DEFAULT_ENTRY)
                entry["grip"] = dict(DEFAULT_ENTRY["grip"])
                entry["focus"] = dict(DEFAULT_ENTRY["focus"])
                entry["comment"] = "# " + label
                final.append(entry)
                acciones.append(
                    "[AGREGA]  %s (default razonable)" % label
                )

    return final, acciones


def render_block(final_entries):
    """Renderiza el bloque completo `const STAFF_RIG := [ ... ]`."""
    out = ["const STAFF_RIG := ["]
    for e in final_entries:
        out.append(
            fmt_entry(e["grip"], e["focus"], e["rot_deg"], e["spx"],
                      e.get("comment", ""))
        )
    out.append("]")
    return "\n".join(out)


def build_animfps_map(cfg_staffs):
    """{indice0: fps} para las varas con animfps != 18 (las demas usan default)."""
    out = {}
    for i, s in enumerate(cfg_staffs):
        try:
            fps = int(round(float(s.get("animfps", DEF_ANIMFPS))))
        except (TypeError, ValueError):
            continue
        if fps > 0 and fps != DEF_ANIMFPS:
            out[i] = fps
    return out


def render_animfps(fps_map):
    """Renderiza `const STAFF_ANIM_FPS := {0: 20, 1: 24}` (o `{}` si vacio)."""
    if not fps_map:
        return "const STAFF_ANIM_FPS := {}"
    items = ", ".join("%d: %d" % (k, v) for k, v in sorted(fps_map.items()))
    return "const STAFF_ANIM_FPS := {%s}" % items


def replace_animfps_block(text, fps_map):
    """Reemplaza el const STAFF_ANIM_FPS en `text`. Devuelve (texto, cambio)."""
    new_block = render_animfps(fps_map)
    m = ANIMFPS_RE.search(text)
    if not m:
        return text, False  # no existe el const: no lo creamos
    if m.group(0) == new_block:
        return text, False
    return text[:m.start()] + new_block + text[m.end():], True


def main():
    ap = argparse.ArgumentParser(
        description="Sincroniza STAFF_RIG desde el rigtool hacia data.gd "
                    "(una direccion, sin pisar varas en default)."
    )
    ap.add_argument(
        "--dry-run", action="store_true",
        help="Imprime el bloque nuevo + resumen, SIN escribir nada."
    )
    args = ap.parse_args()

    if not DATA_PATH.exists():
        sys.exit("ERROR: no existe data.gd: %s" % DATA_PATH)

    # Leemos data.gd como texto (preservando LF).
    original = DATA_PATH.read_text(encoding="utf-8")

    parsed = parse_current_block(original)
    if parsed is None:
        sys.exit(
            "ERROR: no se encontro el bloque `const STAFF_RIG := [ ... ]` "
            "en data.gd. Abortado sin escribir."
        )
    start_idx, end_idx, current_entries = parsed

    cfg_staffs = load_config_staffs()
    final_entries, acciones = build_merged_entries(cfg_staffs, current_entries)

    new_block = render_block(final_entries)

    # Texto final: reemplazamos el bloque STAFF_RIG...
    new_text = original[:start_idx] + new_block + original[end_idx:]
    # ...y sincronizamos STAFF_ANIM_FPS (fps de anim por vara != 18).
    fps_map = build_animfps_map(cfg_staffs)
    new_text, _ = replace_animfps_block(new_text, fps_map)

    identico = (new_text == original)

    # ---- Resumen ----
    print("== rig_sync: rigtool -> data.gd ==")
    print("config : %s" % CONFIG_PATH)
    print("destino: %s" % DATA_PATH)
    print("staffs en config: %d | en data.gd: %d" % (
        len(cfg_staffs), len(current_entries)))
    print("")
    print("Acciones por vara:")
    for a in acciones:
        print("  " + a)
    if fps_map:
        print("anim fps != 18: %s" % {k + 1: v for k, v in sorted(fps_map.items())})
    print("")

    if args.dry_run:
        print("---- BLOQUE GENERADO (dry-run) ----")
        print(new_block)
        print("-----------------------------------")
        print("")
        if identico:
            print("IDEMPOTENTE: el bloque generado == el bloque actual "
                  "(no habria cambios).")
        else:
            print("ATENCION: el bloque generado DIFIERE del actual "
                  "(se escribiria un cambio).")
        return

    # ---- Escritura real ----
    if identico:
        print("Sin cambios: el bloque ya coincide. No se escribe "
              "(data.gd queda byte-identico).")
        return

    # backup
    bak = DATA_PATH.with_suffix(DATA_PATH.suffix + ".bak")
    bak.write_text(original, encoding="utf-8", newline="")
    print("Backup: %s" % bak)

    # escribir preservando LF (newline="" evita que Windows meta CRLF).
    DATA_PATH.write_text(new_text, encoding="utf-8", newline="")
    print("Escrito: %s" % DATA_PATH)


if __name__ == "__main__":
    main()
