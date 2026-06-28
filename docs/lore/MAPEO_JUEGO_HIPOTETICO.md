# MAPEO JUEGO ↔ NARRATIVA — borrador HIPOTÉTICO

> ## ⚠️ HIPOTÉTICO / NO CANON — borrador especulativo
> La historia (**biblia v4**, `BIBLIA_NARRATIVA.md`) **NO se modifica para encajar con esto.**
> La narrativa manda; el juego se adapta a ella, no al revés. El contenido actual del
> juego (`scripts/autoload/data.gd`) es **escaso y placeholder**, así que todo lo de abajo
> es una lectura *tentativa* de cómo PODRÍA leerse el contenido existente bajo el canon v4.
> Donde el juego no tenga algo que la narrativa necesita, se dice explícitamente.
>
> **Niveles por propuesta:**
> - **[encaja]** — el contenido actual ya sirve casi tal cual al canon.
> - **[adaptar]** — sirve con un retoque (nombre, descripción, comportamiento).
> - **[reemplazar]** — no tiene lugar en el canon v4; cambiar por algo nuevo.
> - **[falta contenido]** — la narrativa lo pide y el juego no lo tiene.

---

## 0 · Marco de lectura (de dónde sale todo esto)

El juego base, según v4, es **el desastre LOCAL dentro de la Torre de Killaeth**: Veyran
(Caelreth) baja rompiendo protocolo, atraviesa pisos hasta el **piso 0** (el "fondo creído"),
y ahí ve a **Vhorrak** escapar. Debajo del piso 0 está el Nudo y el rito de Sorin — **oculto
hasta el clímax** (regla de oro).

De eso salen dos "fuentes" plausibles para los mobs actuales:
1. **Criaturas del inframundo filtradas por la grieta** (recién al final, cuando el rito se
   completa) — encaja con bichos abisales/espectrales.
2. **Lo que ya habitaba/se corrompió en la Torre y abajo** (alimañas, magos caídos, wards
   rotos, la propia Numen corrompida subiendo por las raíces) — encaja con casi todo el
   bestiario mundano actual.

El bestiario de hoy es genérico de dungeon-crawler (rata, slime, orco, zombi…). Bajo v4
la lectura más limpia es: **la Torre en ruinas tras la catástrofe** está infestada de
alimañas y de magos/cuerpos corrompidos por la onda y por la Numen podrida que sube.

---

## 1 · Mobs (`ENEMIES`)

| id | name actual | Lectura hipotética v4 | Nivel |
|---|---|---|---|
| `rata` | Rata | Alimaña mundana de una Torre abandonada/en ruinas. No necesita lore. | [encaja] |
| `murcielago` | Murciélago | Igual: fauna de pisos hondos y cavernas bajo la Torre. | [encaja] |
| `arana` / `arana_v2` | Araña | Fauna de las galerías profundas (cerca del Nudo). | [encaja] |
| `slime` | Slime | Lo más "videojuego" del set. Releíble como **acumulación de Numen corrompida cuajada** (lodo arcano), pero es un estiramiento. | [adaptar] |
| `zombi` | Zombi | **Mago/guardia muerto en la catástrofe**, reanimado por la corrupción que sube. Encaja fuerte con "magos muertos, heridos, desaparecidos". | [adaptar] |
| `fantasma` | Fantasma | **Eco de un caído del Refuerzo** (los Threnvar que estallaron). Errático = alma sin temple. | [adaptar] |
| `espectro` | Espectro | Igual que fantasma pero más cerca del Nudo / más corrompido. Buen mob de zona profunda. | [adaptar] |
| `orco` | Orco | No hay orcos en el canon v4 (no es un mundo de razas-fantasía clásico). Reskin a **bruto corrompido / cuerpo deformado por la Numen podrida**, o reemplazar. | [reemplazar] |
| `golem_chico` | Gólem menor | **Constructo/ward de la Torre** (Karreth hace defensa/wards; Maelvorn artífices). Autómata de guarda que ahora ataca a todo. Encaja bien. | [adaptar] |
| `caballero` | Caballero maldito | **Guardia de la Torre caído y corrompido** (¿custodia Karreth?). "Maldito" → tocado por la Numen corrompida. | [adaptar] |
| `cultista` | Cultista | Tentador, pero v4 **no tiene culto**: Sorin actúa con Liraen, no con secta. Releíble como **seguidor/aprendiz arrastrado por Sorin** o como **lector del Threnodion corrompido**. Si no, reemplazar. | [adaptar] |
| `lich` | Liche menor | **Mago muerto que persiste por exceso de Numen** (un Threnvar/Cindrael caído que no termina de morir). Shooter a distancia = sigue lanzando hechizos. Encaja con el tono. | [adaptar] |

**Nota:** ninguno es "criatura del inframundo" pura todavía. La narrativa pide que **al
final del piso 0** salgan criaturas por la grieta junto con Vhorrak → eso es **[falta
contenido]**: hoy no hay un set de "esquirlas/cosas abisales" distinto del bestiario mundano.

---

## 2 · Zonas (`ZONES`)

El juego tiene 3 zonas × 2 pisos = 6 pisos, en orden: Torre en Ruinas → Cavernas Hondas →
Santuario Profano. La narrativa pide un **descenso por la Torre hasta el piso 0**, así que
el eje vertical ya encaja; los nombres y temas se adaptan.

| id | name actual | Lectura hipotética v4 | Nivel |
|---|---|---|---|
| `torre` | Torre en Ruinas | **Pisos altos/medios de la Torre de Killaeth tras la catástrofe.** Encaja casi literal: ruinas, alimañas, primeros muertos del estallido. El nombre ya es el del canon. | [encaja] |
| `cavernas` | Cavernas Hondas | **El descenso bajo los cimientos de la Torre**, acercándose al Nudo (gran nudo de raíz de Vaelroth). Podría renombrarse a algo que insinúe **raíz/Numen** sin spoilear el Nudo. Fauna profunda (gólems, arañas) encaja. | [adaptar] |
| `santuario` | Santuario Profano | Última zona antes del piso 0. "Profano" choca un poco (no hay religión/culto en v4); mejor leerlo como **la zona del Refuerzo del Sello** (sala ritual de los Threnvar) o **antesala del Nudo**, ya teñida de corrupción. Espectros/liche encajan; "cultista" no. | [adaptar] |

**[falta contenido] clave:** el **piso 0 como clímax** (fondo CREÍDO donde se ve escapar a
Vhorrak) **no existe como tal**. Hoy la 3ª zona termina en un jefe (El Liche) y se acabó.
No hay piso-clímax con set-piece narrativo, ni la insinuación de "hay algo más abajo".

---

## 3 · Jefes (`BOSSES`)

| id | name actual | Lectura hipotética v4 | Nivel |
|---|---|---|---|
| `bucle` | Bucle | **Fuera del canon por decreto** (v4 §10: "Bucle → easter-egg, `easter-eggs/`"). No buscarle lugar en la historia: dejarlo como guiño opcional, no como jefe de la zona Torre en la línea canónica. | [reemplazar] (easter-egg) |
| `golem_anciano` | Gólem Anciano | **Constructo mayor de la Torre / guardián de los cimientos** (artífice Maelvorn o ward Karreth de gran escala). Jefe de "Cavernas/descenso" encaja: algo que Killaeth o los clanes dejaron custodiando el camino al Nudo. Lectura limpia, casi sin tocar. | [adaptar] |
| `liche` | El Liche | **Un mago caído mayor**: candidato a leerse como un **Threnvar/Cindrael poderoso muerto en la catástrofe**. PERO el jefe que la narrativa realmente pide en el clímax es **Liraen (el joven, la llave)** y, tras él, el atisbo de **Vhorrak**. El Liche como jefe final del base **no es el villano del canon** → idealmente **reemplazar** por Liraen, o degradar El Liche a jefe intermedio. | [reemplazar] / [adaptar] |

**[falta contenido] — los antagonistas reales del base no están:**
- **Liraen** (el joven, la llave manipulada) → debería ser el **antagonista del juego base**
  / jefe del clímax. **No existe** en `data.gd`.
- **Vhorrak** (la esquirla) → aparición/escape al final del piso 0. **No existe.**
- **Sorin** → presente como rito OCULTO debajo del piso 0 todo el juego; no es jefe del base
  pero su presencia ambiental (sonido, temblores, notas) **no está**.

---

## 4 · Banco de nombres de varas (`STAFF_NAMES`)

Son nombres inventados, eufónicos, ya agrupados en **6 filas que escalan** (fila 0 = suave/
luminoso → fila 5 = oscuro/épico). Eso encaja sorprendentemente bien con v4 sin tocar nada:
las filas claras pueden leerse como **reliquias Maelvorn** (artífices, "primera luz") y las
oscuras como **artefactos tocados por la corrupción / lo abisal**.

| Fila / ejemplo | Lectura hipotética v4 | Nivel |
|---|---|---|
| Fila 0–1 ("Vara de Aelyr", "Cetro de Aethiel", "Vara de Luneth") | **Reliquias luminosas, obra de artífices Maelvorn** o herencia de la Torre. Tono Numen pura. | [encaja] |
| Fila 2 ("Vara de Auralith", "Bastón de Nythral") | Artefactos de archivo **Cindrael / Karreth** (saber antiguo, defensa). | [encaja] |
| Fila 3–4 ("Vara de Nharok", "Vara del Mournyx", "Cetro de Umbryss", "Vara del Abyssion") | **Artefactos tocados por la Numen corrompida / cosas del Threnvar y del velo.** "Abyssion/Noctharion/Umbryss" leen abisal sin nombrar a Morvath. | [encaja] |
| Fila 5 ("Auralith, la Primera Luz", "Cetro de Noctharion") | **Reliquias legendarias** (un extremo "primera luz" Oriael, otro extremo abisal). Encaja con el pico de rareza. | [encaja] |

**Sugerencia (opcional, no urgente):** si alguna vez se quiere anclar al canon, reservar
1–2 nombres legendarios para guiños a `item.threnodion` (NO una vara: es grimorio) o a
reliquias de los Custodios. Hoy **no hace falta tocar nada**.

---

## 5 · Materiales y rarezas (`MATERIALS`, `RARITIES`)

| Elemento | Lectura hipotética v4 | Nivel |
|---|---|---|
| Rarezas (Común→Épico) | Genéricas de RPG; no contradicen nada. Se pueden recolorear/renombrar luego sin costo narrativo. | [encaja] |
| Materiales (Madera…Adamantio) | Cadena clásica de metales/fantasía. Neutra respecto al canon; "Mitrilo/Adamantio" son tropos genéricos, no canon v4, pero **no estorban**. | [encaja] |
| **[falta contenido]** | v4 gira sobre **Numen** (pura vs corrompida) y **Temple**. No hay ningún material/rareza que represente eso (p. ej. un material "tocado por la corrupción" con riesgo/recompensa, o ítems alineados a clan). Oportunidad futura, no obligación. | [falta contenido] |

---

## 6 · Lo que le FALTA al juego para servir a la narrativa v4

Resumen de huecos (todo **[falta contenido]**), ordenado por peso narrativo:

1. **El piso 0 como clímax** — set-piece donde se ve escapar a Vhorrak; "fondo creído" con
   la insinuación de que hay algo más abajo (el Nudo). Hoy la 3ª zona simplemente termina.
2. **Liraen como antagonista/rival recurrente** — el joven que reaparece, trágico, que el
   jugador cree el villano. No hay sistema de **rival recurrente** ni el personaje.
3. **Vhorrak (esquirla) y la grieta** — aparición final + criaturas del inframundo saliendo
   por la grieta (un set de mobs abisales distinto del bestiario mundano).
4. **Sorin presente-pero-oculto** — rito debajo del piso 0 durante todo el juego: temblores,
   onda inicial (el "aviso" de la catástrofe), sonido ambiental. Nada de esto existe.
5. **NPCs heridos con diálogo** — la narrativa se reconstruye por capas a través de
   **heridos/sobrevivientes** de la catástrofe. El juego no tiene NPCs ni diálogo.
6. **Sistema de notas / libros / lore ambiental** — la v4 dice explícito que el jugador
   reconstruye el lore por **notas, libros, ambiente**. No hay sistema de coleccionables de
   texto ni lore de ítem.
7. **El amigo Maelvorn (SLOT)** — muerto/aparece muerto, ligado a la entrega de ítems
   buenos. No existe.
8. **Identidad de clan en el contenido** — clanes (Caelreth/Threnvar/Maelvorn…) no se
   reflejan en mobs, ítems ni zonas. Veyran (protagonista Caelreth) no tiene marca de clan.
9. **El eclipse rojo** — fenómeno central del detonante; no aparece como ambiente/skybox ni
   como evento.
10. **Tono SERIO** — v4 saca "Cuteo/Cárcel" y la comedia por decreto. Nombres como "Bucle"
    o el tono placeholder de algunos mobs deben revisarse para no romper la inmersión.

---

## 7 · Tabla de veredictos (one-glance)

| Contenido | Veredicto dominante |
|---|---|
| Mobs mundanos (rata, murciélago, araña) | [encaja] |
| Mobs de muertos/ecos (zombi, fantasma, espectro, lich) | [adaptar] |
| Mobs sin lugar (orco, cultista; slime dudoso) | [reemplazar]/[adaptar] |
| Zona `torre` | [encaja] |
| Zonas `cavernas`, `santuario` | [adaptar] |
| Jefe `bucle` | [reemplazar] (easter-egg) |
| Jefe `golem_anciano` | [adaptar] |
| Jefe `liche` | [reemplazar]/[adaptar] |
| `STAFF_NAMES` (todas las filas) | [encaja] |
| Materiales / rarezas | [encaja] |
| Piso 0, Liraen, Vhorrak, Sorin, NPCs, notas, amigo Maelvorn, eclipse | [falta contenido] |

---

*Borrador especulativo. La biblia v4 es la fuente de verdad; este doc se adapta a ella, nunca al revés.*
