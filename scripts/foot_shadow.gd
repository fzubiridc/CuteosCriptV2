class_name FootShadow
extends Sprite2D
## Sombra de contacto desde los PIES (no del centro): blob elíptico oscuro que
## "asienta" a la entidad en el piso (clave del look 2.5D). Unshaded para que
## las luces no la aclaren. Solo se nota donde hay luz → comportamiento correcto.

## Crea y engancha una sombra de pie a `entity`.
## foot_y: offset vertical hasta los pies. width: ancho del blob en px.
static func attach(entity: Node2D, foot_y: float, width: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load("res://assets/fx/shadow_blob.tres")
	s.modulate = Color(0.0, 0.0, 0.0, 0.5)
	s.position = Vector2(0, foot_y)
	s.z_index = -5   # sobre el piso (-10), debajo de entidades/muros (0)
	s.show_behind_parent = true
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	s.material = mat
	var sc := width / 128.0
	s.scale = Vector2(sc, sc * 0.5)   # elíptico (achatado, vista 3/4)
	entity.add_child(s)
	return s
