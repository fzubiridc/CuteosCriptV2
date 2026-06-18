extends Node
## Contenido data-driven del juego. Portado de `js/data.js` del original.

const TILE: int = 16

## Balance global (BALANCE en data.js).
const BALANCE := {
	"speed_mul": 0.62,        # factor global de velocidad (jugador + mobs)
	"player_ifr": 0.6,        # invulnerabilidad post-daño (s)
	"aggro_radius": 5.5,      # tiles (detección aunque no estés en su sala)
	"aggro_radius_open": 10.0,
	"leash_tiles": 11.0,      # tiles: más lejos de su origen → suelta y vuelve
	"wander_speed": 0.45,     # fracción de spd al deambular
	"wander_home": 3.5,       # tiles: radio de deambuleo
	"shooter_windup": 0.3,    # anticipación antes de disparar
	"shooter_recover": 0.35,
	"elite_chance": 0.08,
	"depth_hp_scale": 0.22,
	"depth_dmg_scale": 0.13,
	"depth_mod_scale": 0.16,
	"drop_coin": 0.30,
	"drop_heart": 0.11,
	"drop_potion": 0.10,
	"drop_item": 0.13,
	"heart_heal": 22,
	"max_potions": 3,
	"bag_size": 24,
	"dash_speed": 330.0,
	"dash_time": 0.16,
	"dash_cd": 1.2,
}

## Enemigos (ENEMIES en data.js). `spd` en la unidad del original;
## la velocidad efectiva = spd * BALANCE.speed_mul.
## ai: "chaser" persigue · "erratic" zigzaguea · "shooter" dispara a distancia.
const ENEMIES := {
	"rata":       {"name": "Rata", "hp": 14, "dmg": 6, "spd": 78, "ai": "chaser", "size": 7},
	"slime":      {"name": "Slime", "hp": 26, "dmg": 8, "spd": 46, "ai": "chaser", "size": 12},
	"lich":       {"name": "Liche menor", "hp": 36, "dmg": 11, "spd": 44, "ai": "shooter", "size": 12, "range": 150, "fire_cd": 1.8, "proj_spd": 150},
	"fantasma":   {"name": "Fantasma", "hp": 18, "dmg": 15, "spd": 70, "ai": "erratic", "size": 11},
	"zombi":      {"name": "Zombi", "hp": 40, "dmg": 12, "spd": 38, "ai": "chaser", "size": 12},
	"orco":       {"name": "Orco", "hp": 36, "dmg": 11, "spd": 52, "ai": "chaser", "size": 13},
	"murcielago": {"name": "Murciélago", "hp": 12, "dmg": 5, "spd": 115, "ai": "erratic", "size": 9},
	"arana":      {"name": "Araña", "hp": 24, "dmg": 9, "spd": 88, "ai": "erratic", "size": 10},
	"arana_v2":     {"name": "Araña", "hp": 24, "dmg": 9, "spd": 90, "ai": "erratic", "size": 11},
	"golem_chico":{"name": "Gólem menor", "hp": 65, "dmg": 16, "spd": 34, "ai": "chaser", "size": 13},
	"espectro":   {"name": "Espectro", "hp": 35, "dmg": 12, "spd": 72, "ai": "erratic", "size": 11},
	"cultista":   {"name": "Cultista", "hp": 30, "dmg": 10, "spd": 50, "ai": "shooter", "size": 11, "range": 160, "fire_cd": 1.5, "proj_spd": 150},
	"caballero":  {"name": "Caballero maldito", "hp": 85, "dmg": 18, "spd": 48, "ai": "chaser", "size": 12},
}

## Zonas (ZONES en data.js). El orden define la progresión.
const ZONES := [
	{"id": "torre", "name": "Torre en Ruinas", "floors": 2, "enemies": ["rata", "slime", "lich", "fantasma", "zombi", "orco", "arana_v2"], "boss": "bucle", "density": 1.0},
	{"id": "cavernas", "name": "Cavernas Hondas", "floors": 2, "enemies": ["murcielago", "arana_v2", "orco", "golem_chico"], "boss": "golem_anciano", "density": 1.15},
	{"id": "santuario", "name": "Santuario Profano", "floors": 2, "enemies": ["espectro", "cultista", "caballero"], "boss": "liche", "density": 1.25},
]

## Jefes (BOSSES en data.js). patterns rotan en ciclo. (kickball del original
## se reemplaza por burst hasta tener la mecánica de la pelota.)
const BOSSES := {
	"bucle":         {"name": "Bucle", "hp": 380, "dmg": 16, "spd": 62, "size": 16, "patterns": ["charge", "chase", "burst", "charge"], "proj_spd": 140},
	"golem_anciano": {"name": "Gólem Anciano", "hp": 550, "dmg": 24, "spd": 32, "size": 18, "patterns": ["chase", "charge", "burst"], "proj_spd": 110},
	"liche":         {"name": "El Liche", "hp": 650, "dmg": 20, "spd": 60, "size": 16, "patterns": ["spread", "summon", "burst", "charge"], "proj_spd": 160, "minion": "espectro"},
}

## Mejoras de nivel (UPGRADES en data.js). Se elige 1 de 3 al azar al subir.
const UPGRADES := [
	{"id": "vigor", "name": "Vigor", "desc": "+20 vida máx. y cura 20"},
	{"id": "fuerza", "name": "Fuerza", "desc": "+12% de daño"},
	{"id": "celeridad", "name": "Celeridad", "desc": "+8 de velocidad"},
	{"id": "precision", "name": "Precisión", "desc": "+6% de crítico"},
	{"id": "frenesi", "name": "Frenesí", "desc": "+10% vel. de ataque"},
	{"id": "piel", "name": "Piel de hierro", "desc": "+3 de defensa"},
]

# ---------- Ítems (portado de items.js / data.js) ----------
const RARITIES := [
	{"id": "comun", "name": "Común", "color": "#9aa0a6", "mods": 0, "mult": 1.0, "w": 50},
	{"id": "magico", "name": "Mágico", "color": "#4f9dff", "mods": 1, "mult": 1.18, "w": 30},
	{"id": "raro", "name": "Raro", "color": "#ffd84f", "mods": 2, "mult": 1.38, "w": 15},
	{"id": "epico", "name": "Épico", "color": "#c45cff", "mods": 3, "mult": 1.65, "w": 5},
]
const MATERIALS := [
	{"id": "madera", "name": "Madera", "mult": 0.8},
	{"id": "hierro", "name": "Hierro", "mult": 1.0},
	{"id": "acero", "name": "Acero", "mult": 1.3},
	{"id": "plata", "name": "Plata", "mult": 1.6},
	{"id": "mitrilo", "name": "Mitrilo", "mult": 2.0},
	{"id": "adamantio", "name": "Adamantio", "mult": 2.5},
]
const SLOTS := ["arma", "casco", "coraza", "botas", "anillo", "amuleto"]
const WEAPON_TYPES := {
	"baston": {"name": "Bastón", "dmg": 15, "cd": 0.70, "mana_cost": 22, "proj_spd": 190, "splash": 18},
	"varita": {"name": "Varita", "dmg": 7, "cd": 0.26, "mana_cost": 9, "proj_spd": 270, "splash": 0},
}
const ARMOR_BASES := {
	"casco": [{"name": "Capucha", "def": 1}, {"name": "Yelmo", "def": 2}],
	"coraza": [{"name": "Túnica", "def": 2}, {"name": "Coraza", "def": 3}],
	"botas": [{"name": "Botas", "def": 1, "spd": 5}],
	"anillo": [{"name": "Anillo", "def": 0, "dmg": 2}],
	"amuleto": [{"name": "Amuleto", "def": 0, "hp": 8}],
}
const MODS := [
	{"key": "dmg", "label": "Daño", "suffix": "del Titán", "base": 3},
	{"key": "def", "label": "Defensa", "suffix": "del Bastión", "base": 2},
	{"key": "hp", "label": "Vida máx.", "suffix": "del Oso", "base": 14},
	{"key": "spd", "label": "Velocidad", "suffix": "del Lobo", "base": 7},
	{"key": "crit", "label": "Crítico %", "suffix": "de la Víbora", "base": 5},
	{"key": "atkspd", "label": "Vel. ataque %", "suffix": "del Halcón", "base": 9},
]
## Rig por staff (portado de V2_STAFF_RIG.staffs en v2hero.js).
## grip = pixel de la imagen del arma que se alinea con la mano del personaje.
## focus = punta del arma (desde acá sale el proyectil).
## rot_deg = rotación visual de la imagen del arma.
## spx = ancho objetivo del arma en px → escala = spx / ancho_nativo. Las
## staff5-8 son de 128px nativas, el resto 64px (ver v2hero.js original).
const STAFF_RIG := [
	{"grip": {"x": 32, "y": 47}, "focus": {"x": 32, "y": 8},  "rot_deg": 0,   "spx": 49},  # staff1
	{"grip": {"x": 31, "y": 43}, "focus": {"x": 31, "y": 8},  "rot_deg": 0,   "spx": 64},
	{"grip": {"x": 32, "y": 46}, "focus": {"x": 32, "y": 8},  "rot_deg": 0,   "spx": 61},
	{"grip": {"x": 32, "y": 47}, "focus": {"x": 32, "y": 7},  "rot_deg": 15,  "spx": 64},
	{"grip": {"x": 38, "y": 89}, "focus": {"x": 13, "y": 32}, "rot_deg": -45, "spx": 64},
	{"grip": {"x": 54, "y": 75}, "focus": {"x": 23, "y": 25}, "rot_deg": -45, "spx": 64},
	{"grip": {"x": 35, "y": 93}, "focus": {"x": 13, "y": 37}, "rot_deg": -45, "spx": 64},
	{"grip": {"x": 41, "y": 88}, "focus": {"x": 21, "y": 39}, "rot_deg": -45, "spx": 51},
	{"grip": {"x": 32, "y": 42}, "focus": {"x": 32, "y": 8},  "rot_deg": 0,   "spx": 64},  # staff9
]

const STAFF_NAMES := [
	["Vara de Aelyr", "Bastón de Vaelith", "Vara de Luneth", "Cetro de Aethiel", "Vara de Sylvar"],
	["Bastón de Caeryn", "Vara de Thaelir", "Cetro de Eryndor", "Vara de Eldorai", "Bastón de Myrieth"],
	["Vara de Auralith", "Bastón de Nythral", "Cetro de Vaelkris", "Vara de Skaelor", "Bastón de Oruneth"],
	["Vara de Nharok", "Bastón de Vharzul", "Cetro de Mordryn", "Vara del Karnoth", "Cetro de Drakmor"],
	["Vara del Mournyx", "Cetro de Umbryss", "Vara del Abyssion", "Bastón del Vorneth", "Cetro del Noctharion"],
	["Vara de Auralith, la Primera Luz", "Cetro de Solkarion", "Bastón de Eldrunar", "Vara de Abyssion", "Cetro de Noctharion"],
]
