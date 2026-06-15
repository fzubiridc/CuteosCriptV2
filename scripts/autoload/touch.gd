extends Node
## Estado de control táctil. `active` lo prende touch_controls.gd cuando hay
## pantalla táctil. El player lo usa para auto-apuntar (no hay mouse en mobile).

var active := false
