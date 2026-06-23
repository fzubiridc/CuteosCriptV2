# Set de assets ISO — Cárcel del Cuteo

Reglas para TODA pieza (que no se rompa el tileado):
- **Flat-lit**: luz pareja/neutra, sin fuente de luz, sin sombras proyectadas, sin glow. La luz va por código (PointLight2D + CanvasModulate). Mantener solo sombreado de forma.
- **Mismo footprint**: mismo tamaño de rombo / mismo ancla y largo de pared en todas. La variación de detalle OK; la del footprint rompe el encastre.
- **256×256** canvas (Creator), anclar al estilo del wall maestro.
- **Ángulo**: ajustar a mano al molde del wall maestro (el Creator no da dial de ángulo confiable).
- **Opcional premium**: pedir normal map de cada pieza → sombreado direccional real en Godot.

---

## CORE — mínimo para renderizar una sala
- [x] **Wall NE** (flat-lit, 30° angle) — `wall_master.png` → WALL MAESTRO (referencia de todo)
- [x] **Wall NO** — espejo horizontal → `wall_master_mirror.png`
- [x] **Floor** (flat-lit, 256×142 c/grosor) — `floor_256x128.png` en TileSet iso `iso_dungeon_v3.tres` (tile_size 256×128, texture_origin 0,-7, Y-sort ON). ✅ ANDANDO
- [ ] **Esquina exterior** (convexa, apunta a cámara)
- [ ] **Esquina interior** (cóncava, rincón)
- [ ] **Puerta** — estados cerrada + abierta

## SECONDARY — navegación y variedad
- [ ] **Escalera / salida** (bajada al siguiente piso)
- [ ] **Borde de piso / cornisa** (el desnivel en los bordes de sala — "mirar afuera")
- [ ] **Variantes de wall** (grietas, estandarte, ventana) para romper repetición

## PROPS — van encima, separados (luz por código)
- [ ] **Antorcha iso** (el bracket; la luz/titileo por código)
- [ ] **Cofre**
- [ ] **Barril / decoración**

## POLISH / opcional
- [ ] **Normal maps** de cada pieza (si vamos por iluminación premium)
- [ ] **Variantes de piso** (charcos, grietas)

---

## Tenemos (en assets/iso/)
- `wall_master.png` (NE, flat-lit 20°) ← MAESTRO
- `wall_master_mirror.png` (NO, espejo)
- `wall_master_warm.png` (variante más marrón, post)
- `floor.png` (achatado — pendiente regen flat-lit)
- viejos a borrar: `wall_base.png`, `wall_base_mirror.png`, `_preview*.png`, `_cmp*.png`
