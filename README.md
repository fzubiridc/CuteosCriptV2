# Cárcel del Cuteo — port Godot

Port a Godot del juego original en Pixi. Roguelike de mazmorras con pisos
procedurales, iluminación 2.5D (caras de muro foot-lit + topes + AO) y descenso
por zonas hasta el jefe final.

- `scripts/` — lógica del juego (dungeon, main loop, player, enemigos, etc.)
- `scenes/` — escenas (`.tscn`)
- `shaders/` — shaders (caras de muro, etc.)
- `assets/` — tiles, decoración, fx
- `maps/` — **mapas fijos diseñados en Tiled** (ver abajo)
- `docs/` — planes de port y narrativa, build web

---

## Mapas fijos (Tiled)

Permite reemplazar la generación procedural de un piso por un mapa **diseñado a
mano** en [Tiled](https://www.mapeditor.org/), reusando el mismo pintado 2.5D +
antorchas. Pensado para el **primer piso** (escena de apertura: despertar en la
torre) y cualquier sala fija a futuro (jefes, secretas, eventos).

### Cómo funciona

1. Diseñás el mapa en Tiled con el tileset de diseño (`maps/design.tsx`).
2. Al correr, [`dungeon.gd`](scripts/dungeon.gd) lee el `.tmj`
   (`generate_from_tiled()`), arma el `grid` desde la capa `floor` y los
   marcadores desde la capa `markers`, y pinta con tu estilo 2.5D habitual.
3. [`main.gd`](scripts/main.gd) usa el mapa fijo en el piso que corresponda
   (ver **Mapas por piso**) y coloca spawn / salida / enemigos / cofres desde
   los marcadores.

> El loader **no** importa el tileset visual de Tiled. Tiled se usa solo como
> editor de la **grilla** (piso/muro) y de **marcadores**; el look final lo da
> el renderer del juego en runtime.

### Archivos (`maps/`)

| Archivo | Qué es |
|---|---|
| `design.tsx` | Tileset de diseño (referencia el PNG, con propiedad `kind` por tile) |
| `design_palette.png` | 7 tiles planos de 16px (la paleta) |
| `floor_<N>.tmj` / `.tmx` | Mapa fijo del piso N (ver **Mapas por piso**) |

### Paleta (orden en el tileset, izq→der)

| gid | Color | Significado |
|----:|-------|-------------|
| 1 | gris | piso (floor) |
| 2 | oscuro | muro (wall) |
| 3 | verde | spawn |
| 4 | violeta | salida (exit) |
| 5 | rojo | enemigo |
| 6 | dorado | cofre |
| 7 | naranja | antorcha |
| 8 | cyan | ventana (cielo nocturno + luz de luna) |

### Convención de capas

- **`floor`** (tile layer): pintás piso donde sea **caminable**. Lo que dejás
  vacío = muro. No hace falta pintar muros, solo carvás el piso.
- **`markers`** (tile layer): spawn / salida / enemigos / cofres / antorchas.
  - Un solo `spawn` y un solo `exit` (si hay varios, gana el último leído).
  - Si no hay `spawn`, usa el centro del mapa.
  - **Antorchas:** poné el marcador naranja sobre el tile de **muro** donde la
    querés; la luz cae hacia el sur (dentro de la sala). Si no ponés ninguna,
    el juego auto-coloca antorchas como en procedural.
  - **Ventanas:** marcador cyan sobre la **pared norte** (la que mira "afuera").
    El juego dibuja un cielo nocturno generado en código detrás del vidrio
    transparente y mete una luz de luna fría hacia adentro. El cielo se genera
    en `dungeon.gd` → `_sky_texture()` (bandas + estrellas + luna).

### Tamaño: libre (hasta 256×256)

Los mapas fijos **no** están atados al 64×64 procedural: el grid toma
exactamente el tamaño del mapa de Tiled. Los pisos procedurales siguen en 64×64
(`MAP_W`/`MAP_H`); solo los mapas fijos usan tamaño dinámico.

- Tope duro: **256×256** tiles (`MAX_FIXED` en `dungeon.gd`), un guard de
  performance. Más grande → el loader lo rechaza y cae a procedural.
- **Perf:** el pintado crea un sprite por cada cara de muro + AO. Un mapa muy
  grande = muchos nodos. Como el piso fijo se regenera rara vez (solo al entrar),
  un mapa grande (~100–150 de lado) anda bien; evitá acercarte al tope sin
  necesidad.
- El minimapa se adapta solo al tamaño real del piso (escala dinámica).

### Crear / iterar mapas

- **Nuevo mapa:** copiá `floor_01.tmj`, renombralo, diseñalo. Mantené las capas
  `floor` y `markers` y el tileset `design.tsx`.
- **Config en Tiled:** mapa **ortogonal**, tile **16×16**, formato de capa
  **CSV** (no base64/zlib). El loader acepta **`.tmj` (JSON)** y **`.tmx` (XML)**
  indistintamente — guardá en el que quieras. En `.tmx` las capas tienen que
  estar en CSV.
- **Iterar:** editás el `.tmj`, Ctrl+S, y volvés a correr el juego. No hay que
  tocar código — el loader relee el archivo cada vez.

### Mapas por piso

El juego mira, para cada piso, si existe un mapa fijo y lo usa; si no, ese piso
va procedural. El número es el **piso global** (`depth`: 1, 2, 3… a través de
todas las zonas).

- Nombre: `maps/floor_<N>.tmj` o `.tmx`, con o sin cero adelante
  (`floor_1` o `floor_01` valen igual).
- Ej.: `floor_1.tmj` → primer piso fijo; sin `floor_2.*` → segundo piso
  procedural; `floor_3.tmx` → tercer piso fijo. Etc.
- No hace falta tocar código para agregar un piso: con crear el archivo alcanza.

### Activar / desactivar

En [`main.gd`](scripts/main.gd), `const USE_FIXED_MAPS := true`. Poné `false`
para forzar **todos** los pisos a procedural (ignora los `floor_<N>.*`).

### Export (web/desktop)

Corriendo desde el editor anda directo. Para un **build exportado**, agregá
`*.tmj, *.tmx` al filtro de recursos del export (no se importan como recurso
Godot, así que hay que incluirlos explícitamente para que viajen).

### Pendiente

- Cutscene del eclipse rojo + "despertar" en la torre (el mapa fijo ya está; la
  capa narrativa todavía no).
- Antorchas laterales por marcador (hoy el marcador usa siempre el estilo de
  antorcha de pared norte; las de muro lateral van como refinamiento).
