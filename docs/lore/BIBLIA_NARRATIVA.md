# BIBLIA NARRATIVA — La Torre de Killaeth (v4)

> **Fuente de verdad del lore.** Fundación v4 (2026-06-27); consolidación de mecanismo y final (2026-06-28).
> **Supersede por completo a la v3** (*La Cárcel del Cuteo*: torre-mundo, eclipse que enloquece, Consejo de 6 clanes `-nir`, dualidad cómica). El v3 vive solo en git.
> Escritura: skill `cuteo-storyteller` + style files en `docs/lore/estilos/` (8 registros). `SISTEMA_NARRATIVO.md` y la skill ya re-sincronizados a v4. SUPERSEDED (v3, no canon): `PLAN_NARRATIVO.md`, `PROPUESTAS_LORE_2026-06-26.md`.

## Cómo leer este doc (estructura de fichas = cambio-fácil)
Cada entidad es una **ficha atómica** con un `id` estable. **Todo se referencia por `id`, no por el nombre literal.** Para cambiar un nombre, editás un solo campo `name` y nada se rompe. Estados:
- **CANON** — fijado.
- **VETABLE** — fijado pero Felipe puede cambiarlo sin costo (típico: nombres).
- **SLOT** — hueco reservado a propósito, se llena después.
- **PENDIENTE** — falta decidir.

---

## 0 · Identidad y tono — CANON
- **Fantasía medieval oscura, SERIA.** Sin comedia por decreto. El humor solo aparece si **un personaje** lo hace, raro, orgánico y bueno; nunca forzado. Preferimos cero chistes a un chiste que corte la inmersión.
- **Título:** *La Torre de Killaeth*. (Fuera "Cárcel" y "Cuteo" de todo el juego. "Bucle" → easter-egg fuera del canon, ver `easter-eggs/`.)
- **Dos capas** (instinto de diseño del dueño):
  - **Capa 1 — LORE / contexto** (este doc): el iceberg. Casi todo oculto al jugador. Hace que lo de arriba tenga sentido.
  - **Capa 2 — lo que VIVE Veyran** (`FLUJO_JUEGO_BASE.md`): el misterio de superficie que se juega y se va desenterrando.
- **Inspiración tonal** (brújula, no copia): Dark Souls/Elden Ring (lore fragmentado, jefes trágicos), Diablo (cripta/descenso), Dragon Age (instituciones mágicas), The Witcher (diálogo aterrizado).

---

## 1 · Cosmología — CANON

```
id: god.oriael          name: Oriael (el dios bueno / la fuente)      state: CANON
Ente ancestral de la energía pura (el Numen). No es una figura en el cielo: es Numen
con voluntad. No pudo DESTRUIR a Morvath sin matar todo lo vivo ya tocado por él, así
que eligió no ganar: SE VERTIÓ EN LA TIERRA y se convirtió en el árbol Vaelroth.
No "creó" el árbol: ES el árbol, reducido a raíz. Ya no puede actuar — está disperso,
consumido, SOSTENIENDO la puerta cerrada. Su ausencia es la prueba de su amor y la
razón de que la amenaza sea real: no puede pagar de nuevo. Re-sellar cae sobre los mortales.
refs: [place.vaelroth, concept.numen, god.morvath]
```
```
id: god.morvath         name: Morvath (el dios oscuro del inframundo)  state: CANON
Contraparte de Oriael: ente-raíz de Numen CORROMPIDA, hambriento. Está SELLADO en el
inframundo por el Numen del árbol; no puede cruzar entero. Quiere fundirse con Vaelroth
(= volverse infinito y cruzar al mundo). Sin manos en el mundo: actúa sembrando el
grimorio El Threnodion, que corrompe a quien lo lee. Apex de la cadena de villanos.
refs: [place.vaelroth, item.threnodion, concept.numen_corrupta]
```
```
id: place.vaelroth      name: Vaelroth (el árbol)                      state: CANON
El cuerpo de Oriael hecho raíz. A la vez (a) el SELLO que mantiene encerrado a Morvath
y (b) la FUENTE de todo el Numen (su desborde es lo que permite que existan los magos).
Por qué un árbol: raíces = ancla hacia abajo, crecen a través del inframundo y lo aprietan
(el sello está DENTRO de la cárcel); vivo/perenne = se re-ata solo cada estación (dura
milenios sin guardián) y desborda Numen; vulnerable = se puede **debilitar y CORROMPER** (el
eclipse la debilita; la Numen corrompida la ataca desde abajo). Cuanto más fuerte y limpio el
árbol, más cerrado el sello; debilitarlo o ensuciarlo de corrupción lo abre. (Usar Numen NO
"drena" el árbol — es renovable; ver `concept.numen`.) Está LEJÍSIMOS (no cerca de la Torre).
refs: [god.oriael, place.nudo, faction.custodios, concept.numen]
```
```
id: concept.nudos       name: los nudos                                state: CANON
Las raíces de Vaelroth llegan lejísimos y, en MUCHOS puntos del mundo, se entrelazan,
se engruesan o se acercan a la superficie: esos puntos son los "nudos" — zonas de mucho
Numen, donde es más fácil canalizarlo. NO hay uno solo: están repartidos por el mundo, y
es donde tiende a asentarse/construir la gente de la magia. El mundo NO está mapeado:
bien pueden existir OTRAS torres, órdenes o magos en otros nudos que no conocemos — lore
ABIERTO a propósito, no lo limitamos. Cada nudo es también, en lo local, parte del sello.
refs: [place.vaelroth, place.nudo, concept.numen]
```
```
id: place.nudo          name: el Nudo — el de la Torre  (nombre VETABLE)   state: VETABLE
El nudo sobre el que Killaeth decidió erigir la Torre: rico y potente (fuente de poder
inmensa para los magos). NO es el único ni necesariamente el mayor — es uno de tantos. Nodo LOCAL del sello: drenarlo no
toca el árbol entero, pero abre una GRIETA local al inframundo (suficiente para que
escape una esquirla = Vhorrak). Es donde Sorin hace su rito.
refs: [concept.nudos, place.vaelroth, place.torre, event.catastrofe]
```
```
id: concept.numen       name: Numen                                    state: CANON
Energía con la que obra todo mago. INNATA (cada mago nace con su reserva) + CONECTADA
(toda Numen sale del árbol; la chispa del recién nacido se "enciende" de su desborde).
Usar Numen NO drena el árbol (es renovable); pero si el árbol se **debilita o corrompe**,
TODA la magia flaquea. Los Custodios tienen una cantidad INMENSA de Numen interior (por eso
casi inmortales).
refs: [place.vaelroth, concept.temple]
```
```
id: concept.numen_corrupta  name: Numen corrompida                     state: CANON
NO es una energía rival ("antinumen"): es la MISMA Numen, podrida por el toque de
Morvath. Corroe en vez de chocar ("anti-sello") — los Custodios no la saben repeler
porque su defensa está calibrada contra Numen pura. El clan Threnvar aprendió a
contenerla (por eso temidos pero necesarios, NO "el clan anti").
refs: [god.morvath, clan.threnvar]
```
```
id: concept.temple      name: Temple                                   state: CANON
La forma que el alma de cada mago le da a su Numen. Por su Temple se lo asigna a un
clan de pequeño. (Temple = también temple/carácter: poder sin temple = catástrofe, el
tema central del juego.)
refs: [concept.numen]
```
```
id: event.eclipse       name: el eclipse rojo                          state: CANON
Fenómeno NATURAL, cíclico y PRONOSTICABLE. Durante él la barrera al inframundo se
debilita naturalmente ("respira"). Tiñe el cielo de rojo cuando la membrana se vuelve
translúcida. Los magos preparan el "Refuerzo del Sello" para reforzar la barrera en ese
momento. Vorhael (antiguo) y Sorin (hoy) lo usan como ventana para su rito.
refs: [event.refuerzo, event.catastrofe]
```

---

## 2 · La Torre de Killaeth — CANON

```
id: char.killaeth       name: Killaeth                                 state: CANON
Mago legendario de la **edad de oro de la magia** (ANTES del primer eclipse). CONSTRUYÓ la
Torre SOBRE un Nudo, para dar a los magos una fuente de poder inmensa. Su fundación es el
apogeo del que el primer eclipse (~10.000 años atrás) sería la caída.
Da nombre al juego. (Guiño: "Killa".)
refs: [place.torre, place.nudo]
```
```
id: place.torre         name: la Torre de Killaeth                     state: CANON
Donde se forman los magos: van de chicos a aprender a usar su Numen. Está ARRIBA; el
árbol Vaelroth está lejísimos. Debajo de la Torre: el Nudo, y más abajo, la grieta.
Geografía del base: descenso por la Torre → piso 0 (fondo CREÍDO) → MÁS ABAJO, hasta el Nudo
(clímax). La expansión sale al mundo abierto (tras Vhorrak).
refs: [char.killaeth, place.nudo]
```

---

## 3 · Los clanes (por Temple) — CANON  ·  nombres VETABLE
Cada clan = una **virtud llevada al extremo** (por eso chocan; nadie es "el malo").

| id | name | Virtud / personalidad | Rol · magia | Disputa |
|---|---|---|---|---|
| `clan.karreth` | **Karreth** | fuerza y honor; buenos, pero vanidosos/narcisistas (les gusta *verse* buenos) | líderes históricos; defensa/wards | desconfía de Threnvar |
| `clan.cindrael` | **Cindrael** | curiosidad, rigor, sabiduría | archivo, historia, saber antiguo; **fuertes en mente, débiles en poder** | — |
| `clan.maelvorn` | **Maelvorn** | carismáticos, "chill", empáticos, no codician | **artífices** (buenos con artefactos/ítems); disfrutan el mundo | se llevan bien con Karreth; poca fricción con Threnvar |
| `clan.threnvar` | **Threnvar** | disciplina, contención | **carceleros del velo**: manejan/contienen la Numen corrompida y la barrera; temidos pero **necesarios**; de aquí salen los pocos que caen (Vorhael, Sorin) | rispideces con Karreth |
| `clan.caelreth` | **Caelreth** | atención, orden, imparcialidad | **vigilancia / orden / paz**; árbitros; **NEUTRO** (los demás tienen más disputas entre sí). Clan de Veyran | media / al margen |

> **Gancho de secundarios:** los magos que hacen el sello (y mueren/quedan heridos en la catástrofe) son sobre todo **Threnvar**. Maelvorn = futura fuente de ítems buenos y de un posible **amigo del protagonista** (SLOT, ver `char.amigo`).

---

## 4 · Los Custodios del Árbol — CANON
```
id: faction.custodios   name: Custodios del Árbol                      state: CANON
Guardianes con Numen interior INMENSO (casi inmortales). Están EN el árbol (lejísimos
de la Torre), en círculo, como pilares vivos del sello: impiden que nadie drene/toque
Vaelroth. Eran 4; UNO cayó en el primer eclipse (con Vorhael) → quedan 3. Su defensa
está calibrada contra Numen pura, no contra la corrompida. Posibles bosses de expansión
(cuando Vhorrak los alcance y corrompa).
refs: [place.vaelroth, char.vorhael, char.vhorrak]
```

---

## 5 · Historia antigua: la primera caída — CANON
```
id: char.vorhael        name: Vorhael                                  state: CANON
El PRECEDENTE: hace **~10.000 años** provocó el **primer eclipse**. Un Threnvar brillante, codicioso de SOLUCIONES
("contenemos grietas mientras el mundo se desangra"). Halló El Threnodion, creyó que
podía sellar el inframundo para siempre tocando Vaelroth, y provocó el primer eclipse
rojo-ritual. Fracasó: cayó un Custodio deteniéndolo (así el mundo supo que los
"inmortales" pueden morir). Quedó arrastrado al inframundo. Es el espejo histórico de
Sorin: el guardián que se volvió la llave. (Aparece como lore/eco; no es jefe del base.)
refs: [item.threnodion, faction.custodios, char.sorin]
```

---

## 6 · El engaño: el grimorio — CANON
```
id: item.threnodion     name: El Threnodion                            state: CANON
Grimorio sembrado por Morvath. Promete un "Rito para sellar el inframundo para siempre"
(y, de regalo, repartir el Numen y acabar la escasez). LA TRAMPA: el rito **convierte Numen
en Numen corrompida** a gran escala (Liraen es el caudal que lo alimenta). El grimorio vende
que "hace falta una gran cantidad de energía para cerrar el inframundo" — y no miente del
todo: SÍ es una obra inmensa. Pero el árbol no se "gasta": esa masa de Numen corrompida, en
la ventana del eclipse (barrera floja) y sin magos defendiéndola, RASGA la grieta en vez de
sellarla. (Verdad de fondo: cuanto más fuerte y limpio el árbol, más cerrado el sello;
corromperlo o debilitarlo lo abre.) Corrompe a quien lo lee/toca.
Por qué cae un sabio: el costo brutal parece prueba de un gran sello; lo tienta con su
VIRTUD (salvar a todos), no su codicia; está lleno de verdades comprobables, así que
mientras más riguroso, más se convence.
Nota a sembrar: una "Cassandra" (un Threnvar que advierte y es ignorado) — Morvath
corrompió la FUENTE (cada copia), no a una persona.
refs: [god.morvath, char.sorin, char.vorhael]
```
> **"la cura":** el sueño con que el grimorio seduce = cerrar el inframundo para siempre → liberar la energía del árbol y repartirla entre todos los magos (fin de la escasez).

---

## 7 · Los villanos (la cadena del presente) — CANON  ·  `char.liraen` VETABLE
```
id: char.sorin          name: Sorin Threnvar                           state: CANON
El "mago malo". Threnvar brillante, corrompido por El Threnodion; CREE que salva al
mundo (sellar el inframundo + repartir el Numen) — intención buena pero codiciosa.
Su buena intención muere recién con la posesión. Más débil que Veyran en dominio (por
eso necesita el grimorio y al joven); su amenaza real empieza cuando Vhorrak lo posee.
Hace su ritual junto al Nudo, varios pisos DEBAJO del piso 0, durante TODO el juego base.
refs: [item.threnodion, char.liraen, char.vhorrak, place.nudo]
```
```
id: char.liraen         name: Liraen  (el joven)   (nombre VETABLE; alt: Aelrith)  state: VETABLE
"Hijo de la savia": nació durante un eclipse menor, saturado de Numen directamente del
árbol/Nudo → poder INMENSO pero DESCONTROLADO (no lo domina del todo). Es la LLAVE: su
Numen abre desde afuera lo que el árbol cierra. Fue **pupilo de Veyran**, que lo tenía
vigilado por su poder inmenso (mentor↔discípulo: sube la apuesta del conflicto). Manipulado
por Sorin; cree que ayuda a salvar el mundo; trágico, NO malvado; no quiere matar a Veyran
(lo bloquea, no lo mata). Antagonista del juego base: el jugador cree que es el villano. Al
salir Vhorrak comprende el horror y **se pasa al lado de Veyran** (juntos cierran la grieta).
Lo anuncia una **profecía** ("La profecía del Hijo de la Savia", en `estilos/canto.md`), de
doble lectura: suena a salvador, en retrospectiva es él.
refs: [char.sorin, char.veyran, place.nudo]
```
```
id: char.vhorrak        name: Vhorrak                                  state: CANON
Una ESQUIRLA de Morvath (no un siervo): un fragmento de su voluntad, pequeño — por eso
CABE por una grieta parcial que el dios entero no puede cruzar. Sin cuerpo es vapor:
posee a Sorin (cuerpo con Numen entrenado y voluntad ya doblada por el grimorio — no
rompe una voluntad, COMPLETA una ya cedida). Quiere ensanchar la grieta y abrirle paso
a Morvath; para eso debe llegar al árbol y a los Custodios. Sale del Nudo y ESCAPA de la
Torre rumbo al árbol (lejos). El villano activo de la expansión.
refs: [god.morvath, char.sorin, faction.custodios]
```
**Escalera de villanos:** Liraen (la llave, manipulado) → Sorin (buena intención hasta la posesión) → Vhorrak (esquirla activa, en el cuerpo de Sorin) → Morvath (apex, sellado). · Vorhael = el eco histórico.

---

## 8 · La catástrofe — el detonante (LORE) — CANON
```
id: event.refuerzo      name: el Refuerzo del Sello                    state: CANON
Operación LEGÍTIMA de los Threnvar: durante el eclipse pronosticado, canalizan un Numen
enorme (sacado del Nudo) y lo sostienen en equilibrio para reforzar el sello local.
Alta tensión. El joven (Liraen) era pieza clave por su Numen descomunal.
```
```
id: event.catastrofe    name: la catástrofe (el estallido)             state: CANON
1. Eclipse pronosticado. Los Threnvar inician el Refuerzo del Sello junto al Nudo.
   Veyran (Caelreth) está de guardia ARRIBA (no participa: no es Threnvar).
2. Sorin + Liraen, junto al Nudo, corren el rito de El Threnodion: con el caudal de Liraen,
   CONVIERTE Numen en una gran masa de Numen CORROMPIDA.
3. El primer pulso de corrupción REVIENTA el Refuerzo (mata/incapacita a los magos que
   defendían la barrera). Muertos, heridos, desaparecidos; la barrera queda SOLA. La onda
   sube por la Torre → es el AVISO inmediato.
4. Sorin sigue el rito junto al Nudo, debajo del piso 0, durante TODO el juego: corrupción +
   eclipse + barrera sin defensa van rasgando la grieta de a poco.
5. CLÍMAX (piso 0 → el Nudo): Veyran desciende, **gana a Liraen para su lado**, y juntos
   llegan a Sorin (débil) y lo enfrentan. En ese momento la esquirla **Vhorrak** cruza la
   grieta, POSEE a Sorin y ESCAPA de la Torre rumbo al árbol/Custodios. Liraen, al verlo,
   comprende el horror que causaron.
6. VICTORIA AGRIA: Veyran y Liraen **CIERRAN la grieta local** y se quedan con **El Threnodion**
   (para que no se reuse). Pero ya cruzaron criaturas (quedan sueltas en el mundo), se
   abrieron grietas en OTROS nudos sin que nadie lo sepa, y Vhorrak anda libre, poseído.
refs: [event.refuerzo, char.liraen, char.sorin, char.vhorrak, place.nudo]
```
**Base vs expansión:** el juego base = el descenso por la Torre hasta el piso 0 (fondo creído) y MÁS ABAJO, hasta el **Nudo**, donde está el clímax (alianza con Liraen, enfrentar a Sorin, cerrar la grieta). Termina en **victoria agria + cliffhanger**: Vhorrak escapa al mundo. La **expansión** = el mundo abierto (perseguir a Vhorrak hacia el árbol lejano, las otras grietas, las criaturas sueltas); el apocalipsis real (Vhorrak corrompe a los Custodios, libera a Morvath) y los Custodios corrompidos = bosses de expansión.

---

## 9 · El protagonista — CANON
```
id: char.veyran         name: Veyran                                   state: CANON
Clan Caelreth (vigilancia). Mago sabio, sin ambición, observador. Por ser Caelreth es
el primero en notar la paradoja (poder creciendo abajo / magia secándose arriba) y baja
a investigar rompiendo protocolo → su clan = por qué él y nadie más.
**Liraen fue su pupilo**, a quien vigilaba por su poder; el conflicto del base es, en el
fondo, maestro contra discípulo. Poder: MÁS que Sorin (dominio total de su Numen), MENOS que
Liraen en caudal — pero Liraen no se controla y no quiere herirlo. Veyran avanza por técnica
y temple, no por poder.
refs: [clan.caelreth, char.liraen, char.sorin]
```
```
id: char.amigo          name: (amigo Maelvorn del protagonista)        state: SLOT
Hueco reservado: un amigo de Veyran, del clan Maelvorn, que muere / aparece muerto en
algún punto. Conectado a la entrega de ítems buenos (artífices Maelvorn). Llenar luego.
```

---

## 10 · Reglas y pendientes
- **Regla de oro (adaptada):** lo que hay debajo del piso 0 (el Nudo, Sorin, Vhorrak, lo profundo) se mantiene OCULTO hasta el clímax del piso 0. "Abajo / profundo" antes de eso = pisos conocidos o sentido moral.
- **Lore vs superficie:** el jugador NO recibe el lore explicado; lo reconstruye por capas (heridos con diálogo, notas, libros, ambiente). Se escribe con la skill `cuteo-storyteller` + los style files de `docs/lore/estilos/` (8 registros).
- **Nombres VETABLE:** `el Nudo`, `Liraen`. **SLOT:** amigo Maelvorn. **PENDIENTE:** sincronizar `FLUJO_JUEGO_BASE.md` con este final (victoria agria + clímax en el Nudo) y limpiar el drift "drenar"→corrupción en `estilos/leyenda.md`; mapeo fino lore↔juego (hay uno hipotético en `MAPEO_JUEGO_HIPOTETICO.md`); nombre del eclipse menor del nacimiento de Liraen (si hace falta).
- **Fuera del canon:** Bucle (→ `easter-eggs/`).

---
*v4 — fundación cerrada. Próximo: `FLUJO_JUEGO_BASE.md` (Capa 2) y el mapeo a los pisos/mobs/jefes reales del juego.*
