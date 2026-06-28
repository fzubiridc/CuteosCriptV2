# Plan: luz del muro alineada con el piso (proyección en espacio iso)

> Solución encontrada el 2026-06-28 (Felipe + otro agente). El código de aquella exploración quedó
> en `git stash` (`stash@{0}: wip-luz-muro-otro-agente`). Este doc es el plan limpio para
> reimplementarlo sobre el commit `76c8f63` (tag `safe-2026-06-28`).

## El bug central (diagnóstico correcto)

El problema **no** era `wall_lift`, ni el grosor del sprite, ni el `texture_origin`, ni un offset
lateral fino. El bug era que buscábamos/proyectábamos el punto del muro más cercano en
**coordenadas de pantalla/world 2D**, pero en un mundo **isométrico** la cercanía en pantalla NO
representa la cercanía real sobre el plano del piso.

La prueba con la **cruz roja** lo confirmó: la proyección "más cercana" en pantalla caía en un punto
visualmente incorrecto del muro. Al cambiar la proyección a **espacio lógico de piso iso continuo
`(u, v)`**, la cruz roja cayó donde debía.

## La idea correcta para reimplementar

1. Convertir la posición de **pies del player / luz** a espacio continuo de piso iso `(u,v)`.
2. Convertir los **segmentos base de muro** (`WallSegment`) a ese mismo espacio.
3. **Proyectar** ahí (player contra el segmento más cercano).
4. Convertir el resultado de vuelta a mundo/screen.
5. Usar esa proyección como **base** para iluminar el muro (recién ahí falloff/altura/offset).

## Fórmulas (iso 2:1, tile 256×128)

```gdscript
func _screen_to_floor(p: Vector2) -> Vector2:
	return Vector2(
		(p.y / 64.0 + p.x / 128.0) * 0.5,
		(p.y / 64.0 - p.x / 128.0) * 0.5
	)

func _floor_to_screen(p: Vector2) -> Vector2:
	return Vector2(
		128.0 * (p.x - p.y),
		64.0 * (p.x + p.y)
	)
```

Proyección al segmento de muro (punto más cercano sobre la arista base, en espacio de piso):

```gdscript
var pf = _screen_to_floor(player_pos)
var af = _screen_to_floor(edge_a)
var bf = _screen_to_floor(edge_b)

var ab = bf - af
var t = clamp((pf - af).dot(ab) / ab.length_squared(), 0.0, 1.0)
var closest_floor = af + ab * t
var closest_world = _floor_to_screen(closest_floor)
```

## Conclusiones / lecciones

- La solución robusta **no** es adivinar por `UV` ni desplazar la luz a ojo: es usar la **geometría
  real de `WallSegment`**, pero medir/proyectar en el **plano lógico del piso**, no en pantalla.
- Los `texture_origin` nuevos pueden calzar el arte, pero **no** arreglan la proyección de luz solos.
- El shader compartido puede recibir los **segmentos base cercanos**, pero el cálculo debe usar la
  métrica iso `(u,v)`.
- **Debug correcto = cruz roja**: pies proyectados al muro en espacio iso. Si esa cruz cae bien, la
  base matemática está bien. Recién **después** conviene tocar falloff/altura/offset.

## Notas de integración (a resolver al implementar)

- `WallSegment` (`scripts/wall_segment.gd`) ya tiene la fuente lógica de muros (NW/NE/SE/SW, `neighbor()`
  por paridad de fila). De ahí salen los segmentos base `edge_a`/`edge_b` por celda/borde.
- El shader de muros es `shaders/wall_face.gdshader` (aplicado a `IsoWalls`/`IsoWallsBack` por
  `dungeon._make_wall_mat`/`_update_iso_wall_mat`). Hay que decidir si la proyección se hace por-CPU
  (pasar al shader la base proyectada por segmento) o por-píxel en el shader con la métrica iso.
- El material de muros y el de entidades (`LightField.entity_material`) comparten shader: lo nuevo NO
  debe afectar a las entidades.
- Verificación headless: `godot --headless --path . --import` (exit 0, sin SCRIPT ERROR).
