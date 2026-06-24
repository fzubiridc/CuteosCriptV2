# Notas técnicas ISO (de tutorial GDC + nuestra experiencia)

## Confirmado que ya hicimos bien ✓
- **TileMapLayer** (NO el `TileMap` viejo/deprecado).
- **Tile Shape: Isometric, Tile Size 256×128** = "true isometric" (Y = mitad de X).
- **Tiles con grosor/profundidad** (slabs 3D): la imagen trae espacio extra → definir el **texture region al tamaño completo** y usar **texture_origin** para que el tile caiga en la coord correcta. (Nosotros: region 256×142, origin (0,-7).)
- **Y-Sort ON** en el TileMapLayer (Ordering → Y Sort Enabled), si no los tiles se dibujan en orden incorrecto.

## Reglas clave para cuando sumemos MÁS tiles (paredes, props)
- **UN solo texture_origin para TODOS los tiles**, basado en el tile de **menor elevación** del set. Aunque algunos queden "un poco altos", es la única forma de que encastren parejos. ⚠️ importante al meter paredes.
- **Tile sheet único > imágenes sueltas.** Lo industry-standard es 1 PNG con todos los tiles (memoria eficiente). Plan: `ground.png`, `walls.png`, `props.png` separados (que no se infle un solo PNG gigante).

## Herramientas/trucos de Godot a usar
- **Atlas Merging Tool** (TileSet → menú hamburguesa → Open Atlas Merging Tool): mergea tiles sueltos en un solo tilesheet. Tip: "line after column = 12" para PNG compacto.
  - Truco rápido: setear region a 512 temporal → arrastrar TODOS los tiles → dejar que Godot auto-cree las regiones → mergear → volver a 128.
- **Pintar propiedades en masa**: en el TileSet se puede **pintar el texture_origin** sobre muchos tiles a la vez (elegís offset y arrastrás). Idem probabilidad.
- **Bug del editor**: si el dropdown de terrain no aparece, crear una escena nueva y volver → se popula.

## Autotiling (para variación automática, evitar patrones repetidos)
- **Terrain Sets** → matching mode **"Corners and Sides"** (sirve en ~95% de casos).
- Cada tile tiene un **bitmap 3×3**: define qué tiles pueden ir al lado de cuál. Pintás terreno en vez de tiles individuales y Godot elige variantes solo.
- **Variantes de ángulo** (N/O/S/E) rompen el patrón repetitivo. Pintás "terrain" y Godot mezcla.
- **Pintar probabilidad** por tile: comunes con prob alta (ej. 20), raros bajo (2-3) → piso realista, no ruidoso.

## Para probar (ideas)
- **Pedirle a PixelLab "2:1 angle" explícito** en el prompt → capaz respeta mejor el ángulo iso de fábrica (y se reduce/elimina el shear posterior). Probar mañana.
- Pedir el muro con **margen/padding** (centrado, sin tocar bordes) para que no clipee las esquinas (el Creator es 256 fijo).

## Prompts que FUNCIONARON (PixelLab)
Regla: **menos es más** — prompts largos/estrictos lo confunden o empeoran la calidad.

**Tile combinado muro+piso (junta natural)** — adjuntar referencia: `prueba 2` (composite manual muro+piso):
```
using the reference image, same tile, join the wall with the stone floor. maintain style and colours.
Maintain exactly the same angles of the wall and floor borders. Maintain dimensions.
You can add stones or ruble in the union to make it feel more natural.
```
→ dio una junta natural con piedritas/rubble en la unión, manteniendo ángulos y dimensiones. ✅

## Referencias
- **Kenny's isometric dungeon pack** (CC0, gratis) — buen pack de referencia/relleno.
- "Game Development Center" GitHub → **tile map starter kit**.
- **Part 2 del tutorial** = paredes + **physics layers** (colisión que se dibuja junto con el muro para que el player no lo atraviese). ← justo nuestro próximo paso.
