extends RefCounted
## Un muro = un BORDE DE ROMBO de una celda de piso que da al vacío.
## En este layout iso (+X=(256,0), +Y=(128,64)) los 4 lados que importan son las DIAGONALES
## del rombo: NW, NE, SE, SW. El borde superior de un cuarto = NW+NE de cada celda de arriba;
## el inferior = SE+SW. Modelar el borde (no la celda) permite esquinas con dos caras y mapear
## cada borde a su pieza de arte (2 tipos de muro + 2 esquinas).

enum Side { NW, NE, SE, SW }

# Vecino en grid AL OTRO LADO de cada borde de rombo, DEPENDIENTE DE LA PARIDAD de la fila.
# El TileSet es isométrico STACKED (tile_shape=1, layout por defecto): las filas IMPARES están
# desplazadas +media celda en x, así que las diagonales NO son fijas. Confirmado con map_to_local
# (ver closed_room_test): map_to_local(x, y_par)=(256x, 64y); map_to_local(x, y_impar)=(256x+128, 64y).
#   Fila PAR (y%2==0):  NW(-1,-1)  NE(0,-1)  SE(0,1)   SW(-1,1)
#   Fila IMPAR(y%2==1): NW(0,-1)   NE(1,-1)  SE(1,1)   SW(0,1)
# El viejo `DIR` fijo equivalía a la tabla IMPAR → correcto en filas impares, serrucho en pares.
static func neighbor(cell: Vector2i, s: int) -> Vector2i:
	var odd := (cell.y % 2) != 0
	match s:
		Side.NW: return cell + (Vector2i(0, -1) if odd else Vector2i(-1, -1))
		Side.NE: return cell + (Vector2i(1, -1) if odd else Vector2i(0, -1))
		Side.SE: return cell + (Vector2i(1, 1) if odd else Vector2i(0, 1))
		Side.SW: return cell + (Vector2i(0, 1) if odd else Vector2i(-1, 1))
	return cell

# Normal hacia el INTERIOR de la sala, por borde (para iluminación por cara). Aproximada a la
# diagonal del borde en pantalla.
const INWARD_NORMAL := {
	Side.NW: Vector2(0.7, 0.7),
	Side.NE: Vector2(-0.7, 0.7),
	Side.SE: Vector2(-0.7, -0.7),
	Side.SW: Vector2(0.7, -0.7),
}

enum VisualState { OPAQUE, FADED }   # transparencia de fachada (sin dither, sin muros bajos)

var interior_cell: Vector2i   # celda de PISO a la que pertenece este muro
var side: int                 # Side.*
var source_id: int            # source/arte a estampar
var is_facade: bool           # mira hacia la cámara (SE/SW) → reveal de transparencia
var room_id: int = -1

func _init(cell: Vector2i, s: int, src: int, facade: bool) -> void:
	interior_cell = cell
	side = s
	source_id = src
	is_facade = facade

## Bordes TRASEROS (arriba, lejos de la cámara): NW, NE. Los delanteros (SE, SW) miran a la cámara.
static func is_back(s: int) -> bool:
	return s == Side.NW or s == Side.NE
