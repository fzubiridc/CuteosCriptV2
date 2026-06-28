# Sistema narrativo — Guía de estilo y registros (v4)

> Cómo escribir y revisar **todo** el texto de *La Torre de Killaeth* para que suene en el
> tono correcto. Operacionaliza un sistema de **7 registros de escritura**: cualquiera
> (vos, otro dev, o el agente `cuteo-storyteller`) puede tomar este doc y producir una
> pieza que no rompa el canon ni el tono.
>
> **Fuente de verdad del canon:** `docs/lore/BIBLIA_NARRATIVA.md` (v4) — entidades, clanes,
> villanos, catástrofe. **Capa de superficie / qué se juega:** `docs/lore/FLUJO_JUEGO_BASE.md`.
> Esto NO redefine el canon: lo da por sentado y enseña a **escribir** dentro de él.
> Nombres exactos del juego: `scripts/autoload/data.gd`.
>
> **Re-sincronizado a v4 (2026-06-27).** La versión vieja de este doc operaba sobre la premisa
> *La Cárcel del Cuteo* (dualidad humor/tragedia, clanes `-nir`, Skarun, Piso −1). Esa premisa
> **ya no aplica.** Si ves un texto con "Cuteo", "Skarun", "Bucle", "Archimago" o "subsuelo / Piso −1",
> es lore viejo (`docs/PLAN_NARRATIVO.md`, `docs/lore/PROPUESTAS_LORE_2026-06-26.md`, ambos SUPERSEDED).

---

## 1. Propósito

Este documento es la **brújula de voz**. No es lore nuevo, es el manual para producir
lore en tono. Tres usos:

1. **Antes de escribir cualquier texto del juego** (diálogo de jefe, libro, descripción
   de ítem, frase de muerte, cartel de zona): elegís el registro de la sección 3 y
   seguís sus reglas y su ejemplo de calibración.
2. **Antes de canonizar:** generás **3 variantes** (humana / oscura / histórica, ver §6)
   y elegís. Nunca canonices la primera frase que sale.
3. **Para revisar / auditar:** pasás la pieza por el **checklist anti-error** de §7.

**Con el agente `cuteo-storyteller`:** nombrá el registro explícitamente en el pedido
("Escribime en *registro 4, diario personal*, la última anotación de un Threnvar herido sobre…").
El agente usa esta guía como contrato: registro + elemento real del juego + regla de oro. Sin el
agente: mismo flujo a mano, este doc es la referencia.

**Qué NO hace este doc:** no decide la trama (eso es `BIBLIA_NARRATIVA.md` + `FLUJO_JUEGO_BASE.md`),
no fija nombres nuevos (eso pasa por vos), no toca código.

---

## 2. La regla maestra de tono + la regla de oro

### 2.1 Regla maestra: fantasía oscura SERIA

*La Torre de Killaeth* es **fantasía medieval oscura, seria.** No hay comedia por decreto,
no hay cáscara absurda, no hay "Cuteo". El registro base es la **tragedia sobria**: gente con
buenas intenciones que se rompe, poder sin temple, un mundo que se desangra despacio.

**El humor, si aparece:**
- Sale de **un personaje**, no del narrador ni del sistema. Es un rasgo de esa voz (un viejo
  cansado que ironiza, un artífice Maelvorn "chill" que suelta una línea seca), nunca un chiste
  guionado para aliviar.
- Es **raro, orgánico y bueno**, o no está. Preferimos cero chistes a un chiste que corte la
  inmersión.
- **Nunca durante un golpe emocional**, nunca en boca del narrador, nunca en los libros y
  documentos. Esos son el ancla de gravedad.

**Las tres leyes que no se rompen:**

1. **El narrador (prosa, registro 2) y los libros/documentos NO hacen humor.** Su voz es el
   peso del mundo. Si los ponés a bromear, el sistema entero pierde el piso.
2. **Jamás un chiste durante un golpe emocional.** La gracia, si la hay, va lejos del remate.
3. **Si tenés que aclarar "es gracioso pero también triste", borralo.** Una línea es seria; el
   humor es la excepción que un personaje se gana, no el default.

**Ejemplo BIEN (humor orgánico de un personaje, lejos del golpe):**

> **Artífice Maelvorn** *(entregando una vara, seco, casi divertido):* "La hice para alguien
> que ya no la va a usar. Cuidala mejor que él."

El filo es triste; la sequedad es del personaje. No es un chiste contra la escena, es su forma
de hablar.

**Ejemplo MAL (humor de sistema / chiste sobre la tragedia):**

> ✗ Cartel de combate: **"VHORRAK — ¡esquivá el vapor maldito!"** *(jerga de gameplay graciosa
> encima de una tragedia; rompe el tono serio.)*
> ✗ "El sello se cae a pedazos… qué bajón, ¿no?" *(el narrador comenta con humor; prohibido.)*

### 2.2 La regla de oro: el iceberg oculto hasta el clímax

El juego tiene **dos capas** (ver biblia §0):
- **Capa 1 — LORE / contexto:** el iceberg. Casi todo el lore (Vaelroth, Morvath, el Nudo,
  Vhorrak, la catástrofe completa) está **oculto** al jugador. Existe para que lo de arriba
  tenga sentido, no para volcarlo.
- **Capa 2 — lo que vive Veyran:** el misterio de superficie que se juega y se desentierra por
  capas (heridos con diálogo, notas, libros, ambiente).

**La regla dura:** todo lo que pasa **debajo del piso 0** — el Nudo, el rito de Sorin, Vhorrak,
la grieta, lo profundo — se mantiene **OCULTO hasta el clímax del piso 0**. La torre es lo
conocido; el piso 0 se cree el fondo. Antes de ese momento, "abajo / descenso / fondo / hondo /
profundo" significa **pisos conocidos de la Torre** o **degradación moral** — nunca el mundo que
duerme debajo.

**Corolario — doble lectura:** la mejor frase tiene **sentido inocente ahora** y **otro después
del clímax**. Funciona entera siendo inocente hoy y gana un segundo filo cuando el jugador sabe
qué había abajo.

**Lore vs superficie:** el jugador NO recibe el lore explicado. Lo reconstruye. Nadie te dice
"Morvath está sellado bajo el árbol"; lo armás con un herido que delira, una página de un tratado,
un grabado en una puerta.

**Doble lectura BIEN:**

> "El poder crece donde nadie lo cultiva." *(Nota de un Cindrael.* Ahora = la paradoja que nota
> Veyran, sin nombrar el Nudo. Después = literal: el Numen brota del Nudo, debajo.)*

> "Threnvar contiene lo que sube. Nunca preguntes desde dónde sube." *(Bando.* Ahora = jerga de
> carceleros del velo. Después = la grieta al inframundo.)*

**Doble lectura MAL (rompe la regla de oro):**

> ✗ "Sorin abrió una grieta al inframundo en el Nudo, bajo el piso 0." *(Nombra el mundo oculto
> antes de tiempo. Quema el giro.)*
> ✗ "Hay un dios sellado debajo de la Torre." *(Vuelca el iceberg. Prohibido.)*

La diferencia: la frase buena **funciona entera siendo inocente hoy**. Si solo tiene sentido
sabiendo el giro, es un spoiler disfrazado.

---

## 3. Los 7 registros

Cada texto del juego cae en uno de estos 7 registros. Elegí **uno** y no lo mezcles.
La prueba de que entendés el sistema: leés un ejemplo y sabés de qué registro es sin mirar
el título.

> **Nota de nombres (canon v4):** clanes por Temple = **Karreth** (fuerza/honor, vanidosos),
> **Cindrael** (saber, débiles en poder), **Maelvorn** (artífices, "chill"), **Threnvar**
> (carceleros del velo, contienen la Numen corrompida), **Caelreth** (vigilancia/orden, neutro,
> clan de Veyran). Personas: **Veyran** (prota), **Sorin Threnvar** (corrompido por El Threnodion),
> **Liraen** (el joven, la llave, trágico), **Vhorrak** (esquirla de Morvath), **Vorhael** (el
> precedente histórico), **Killaeth** (fundó la Torre). Entidades: **Vaelroth** (el árbol-sello),
> **Oriael / Morvath** (los dioses), **el Nudo**, **el Numen**, **el eclipse rojo**, **El
> Threnodion** (el grimorio), **los Custodios del Árbol**.

---

### Registro 1 — Diálogo natural

**Cuándo:** lo que un personaje **dice en voz alta** ahora mismo. Frases pre/post de jefes
(`data.gd:62-64`), un Threnvar herido que delira, un artífice Maelvorn que entrega un ítem,
los ecos de Sorin, la voz parca de Veyran observando.

**Reglas:**
- Habla un cuerpo (o lo que queda de uno), no un narrador. Tiene aliento, cortes, dudas.
- **Veyran** habla poco y observa con precisión; no explica lo que él ya sabe. Avanza por
  temple, no por verbo.
- Los jefes/antagonistas tienen una **razón comprensible** para pelear. El daño se entiende, no
  se aplaude. Liraen no quiere herirte; Sorin cree que salva el mundo.
- Nadie es omnisciente: versiones **parciales**. Nadie dice "Sorin es el villano" ni "los Threnvar
  son los malos".
- Cero humor en el narrador y los libros. Un personaje puede ser **seco** o irónico si esa es su
  voz; nunca chistoso por aliviar.

**Longitud:** 1–2 oraciones por intervención. Una escena obligatoria, máx. 6 intervenciones
(salvo el clímax). Frase de jefe: una línea que se clave.

**Inspiración:** Darkest Dungeon (la gravedad no se negocia) + The Witcher (diálogo aterrizado) +
la parquedad de alguien que ya vio demasiado.

**Ejemplos (canon v4, tono serio):**

> **Sorin** *(eco, antes de la posesión):* "No vine a romper el sello. Vine a terminarlo, para
> que ninguno de ustedes tenga que volver a temerle. ¿Por qué nadie me deja terminarlo?"

> **Threnvar herido** *(tras la catástrofe):* "Sosteníamos el refuerzo. Y de golpe… no había nada
> que sostener. Alguien se llevó la fuente con nosotros adentro."

> **Veyran** *(ante un cuerpo en su puesto):* "No corrió. Se quedó haciendo lo que le tocaba,
> hasta que lo que le tocaba lo mató."

---

### Registro 2 — Prosa narrativa

**Cuándo:** la **voz que describe la escena** — prólogo (el eclipse rojo), transiciones entre
zonas de la Torre, el descenso, el clímax del piso 0. Texto de cámara, no de personaje.

**Reglas:**
- Concreto y sensorial. Mostrá el deterioro; no lo expliques. Un detalle vale más que un adjetivo.
- Frases cortas, ritmo controlado. El silencio es parte de la prosa.
- Sin humor. Sin moraleja. La imagen carga el sentido.
- Sirve a la **situación primero**: la prosa enmarca lo jugable, no lo reemplaza.

**Longitud:** 2–5 frases por plano. El prólogo son pocos planos breves, no una cinemática.

**Inspiración:** Hollow Knight / Hyper Light Drifter (melancolía por restricción) + la sequedad
de Berserk en sus paneles mudos + el descenso de Diablo.

**Ejemplos (canon v4):**

> *(Prólogo — el eclipse rojo):* El cielo no se oscureció. Se enrojeció, como una herida que se
> abre despacio. Los magos viejos lo habían pronosticado al día. Ninguno había dicho que esta
> vez la membrana no volvería a cerrarse sola.

> *(Bajando un tramo de la Torre):* Las varas en las paredes seguían encendidas, pero su luz
> tiraba hacia abajo, como si algo más hondo pidiera el Numen de vuelta. Veyran lo había sentido
> arriba como un número que no cerraba. Acá ya no era un número.

> *(Piso 0, antes del clímax):* Por primera vez en todo el descenso, el suelo era firme y la
> sala estaba en calma. Veyran bajó la vara. Creyó que había llegado al fondo.

---

### Registro 3 — Registro histórico

**Cuándo:** crónicas, actas, bandos, edictos del Consejo de clanes — texto **oficial**, escrito
para durar (o para mentir). Crónicas Cindrael, edictos Karreth, protocolos Threnvar, dictámenes
Caelreth.

**Reglas:**
- Voz institucional, fría, con autoridad. Se cita a sí misma, se fecha, se sella.
- **Aquí vive la contradicción del canon:** versiones que se desmienten entre sí. Recordá que el
  grimorio corrompió la **fuente** (cada copia), así que hubo un Threnvar Cassandra que advirtió y
  fue ignorado: ese tipo de voz enterrada vive acá.
- Eufemismo de poder: "contención", "refuerzo", "sostener el sello" — nunca "lo que de verdad pasó".
- Doble lectura obligatoria en las palabras clave ("contener", "lo que sube", "la fuente", "abajo").
- Nadie firma la verdad completa; firman su parte.

**Longitud:** fragmento corto (3–6 líneas). Un libro principal puede ser la excepción extensa: se
lee de una sentada y justifica su largo.

**Inspiración:** Silmarillion (cronista distante) + Dragon Age / GoT (la historia oficial es
política, y los registros se contradicen).

**Ejemplos (canon v4):**

> *De los Anales del Consejo, antes de la catástrofe — mano Cindrael:* "Quede asentado que el
> clan Threnvar no es objeto de sospecha por contener lo que contiene. Alguien debe hacerlo.
> Que nadie confunda la cercanía al velo con la inclinación a cruzarlo."

> *Folio siguiente, otra mano:* "Corríjase. Hubo uno que advirtió, hace generaciones, que la cura
> ofrecida era la enfermedad escrita al revés. No firmó con nombre. Lo llamaron alarmista y se
> quemó su copia. He hallado tres tratados que repiten su frase y ninguno lo cita. Temo que tenía
> razón, y que la razón fue lo primero que sellamos."

> *Edicto del Refuerzo, sello Threnvar:* "Durante el eclipse, ningún clan ajeno se acerca al Nudo.
> No es desconfianza: es carga. Lo que sostenemos no admite manos de más. Manténganse arriba.
> Manténganse en su sitio."

---

### Registro 4 — Diario personal

**Cuándo:** la voz **íntima y privada** de alguien atravesado por los hechos. Una hoja de
enfermería tras la catástrofe, anotaciones al margen, la última página de un Cindrael antes de
morir, el diario de Sorin (revelado tarde).

**Reglas:**
- Primera persona, sin público. Le tiembla el pulso. Se contradice, se asusta, duda de su cordura.
- Lo opuesto al registro 3: el histórico oculta, el diario **confiesa**. Aquí está el humano.
- Detalle clínico que se vuelve íntimo: un síntoma, un nombre, un gesto que no se va.
- Doble lectura desde la angustia, no desde la autoridad ("una voz que viene de más abajo de lo
  que hay").
- El de Sorin: talento, impaciencia, **buena intención que se vuelve codicia de soluciones** —
  nunca villano de caricatura. Su voz cree de verdad que salva a todos.

**Longitud:** 3–6 líneas. Corto y con una herida adentro.

**Inspiración:** las notas de personaje de The Witcher (lo cotidiano que se tuerce) + la primera
persona quebrada de Berserk en sus pausas.

**Ejemplos (canon v4):**

> *(Hoja de un enfermero, tras el estallido del Refuerzo):* "El herido del catre cuatro está
> lúcido entre temblores. Dice que oye su propio nombre llamándolo desde más hondo que el Nudo.
> Le dije que no hay nada más hondo que el Nudo. Asintió. A la hora lo encontré con la oreja
> pegada al suelo, pidiéndole perdón a alguien que no estaba."

> *(Última anotación de un Cindrael):* "Llevo toda la vida cotejando archivos. Recién hoy entiendo
> por qué tres tratados serios prometen la misma cura y los tres mienten en la misma dirección. No
> los escribió la misma mano. Los corrompió la misma fuente. Si lees esto, no confíes en el libro
> que te convenza más rápido."

> *(Diario de Sorin, sin nombre todavía):* "Threnvar lo llama 'contener'. Yo lo llamo administrar
> el desangre con buena letra. Hay una forma de cerrarlo para siempre. El costo es enorme, sí —
> pero un costo enorme es la prueba de que el sello vale. Nadie quiere mirar el número. Yo lo miré."

---

### Registro 5 — Tratado arcano / grimorio

**Cuándo:** texto **técnico-mágico**: teoría del Numen y del sello, notas de un artífice Maelvorn
sobre una vara, la mecánica del Refuerzo, páginas de El Threnodion (corruptoras), el arte de
contener la Numen corrompida.

**Reglas:**
- Lenguaje preciso, de oficio. La magia es **ingeniería del Numen**, no misticismo vago. Mide,
  calcula, repite cuentas.
- **El horror entra por la anomalía técnica**, no por el grito: "la reserva del Nudo cae más rápido
  de lo que el árbol entero podría reponer". El dato es la amenaza.
- Nunca dice "inframundo" ni "dios sellado": dice "el sello", "la fuente", "la dirección del rito",
  "el caudal". La regla de oro se respeta en jerga de artífice.
- **El Threnodion no miente:** su trampa es que invierte la *dirección* (la energía ES el cerrojo,
  no el combustible). Cuando escribas una página suya, que sea rigurosa y verificable — por eso
  seduce a un sabio. Sobrio, sin jerga inventada críptica, sin inglés.

**Longitud:** 3–6 líneas. Una observación técnica con un agujero negro adentro.

**Inspiración:** los apartes técnicos de Warhammer (maquinaria sagrada, ritual de mantenimiento) +
la precisión seca de un manual que describe algo que no debería existir.

**Ejemplos (canon v4):**

> *(Nota de un artífice Maelvorn, sobre una vara legendaria):* "Esta vara no genera Numen: lo
> ordena. Una mano sin temple le pide más caudal del que su portador puede sostener, y la vara
> obedece. No falla la vara. Falla quien la empuña creyendo que el poder es lo mismo que el dominio."

> *(Página de El Threnodion):* "Para cerrar el inframundo de forma definitiva, vierte en el rito
> toda la energía de la raíz. El costo es total; por eso el sello será total. Cada cuenta de esta
> página es cierta. Coteja cuanto quieras: cuanto más riguroso seas, más pronto verás que no hay
> otro camino." *(La trampa: esa energía ES el sello. Verterla no lo cierra, lo abre.)*

> *(Tratado Threnvar sobre el velo):* "La Numen que sube por la raíz no choca con nuestras
> defensas: las corroe, porque es la misma Numen, sólo que podrida. Calibrar el ward contra ella
> exige aceptar que no estamos repeliendo a un enemigo. Estamos conteniendo algo nuestro que se
> echó a perder."

---

### Registro 6 — Lore de ítem

**Cuándo:** el texto de sabor de un objeto — varas legendarias (banco en `data.gd:144-151`),
reliquias, materiales raros, artefactos Maelvorn.

**Reglas:**
- **Una sola frase**, máximo dos. El ítem no cuenta una novela: insinúa una.
- Densidad sobre extensión: la frase implica una historia entera sin narrarla (el molde
  Dark Souls / Diablo).
- El nombre ya hace la mitad del trabajo; la frase le da el filo trágico o el misterio.
- Las varas son **artefactos Maelvorn** (los artífices): muchas tienen un dueño que cayó, o un
  exceso que no se controla. Doble lectura cuando se pueda ("contener", "lo que sostiene", "raíz").
- Sobrio. Nada de stats en la prosa (los stats son el ítem; esto es la voz).

**Longitud:** 1 frase (ideal), 2 como techo.

**Inspiración:** descripciones de ítem de Dark Souls / Elden Ring (historia comprimida en una
línea) + el peso mítico de los nombres del Silmarillion.

**Ejemplos (canon v4):**

> **Vara del primer Custodio:** "La empuñó uno de los cuatro que rodean el árbol. Ahora son tres,
> y la vara pesa por los dos."

> **Esquirla de raíz:** "Un fragmento del árbol que sostiene todo. Aún tira hacia abajo, buscando
> el resto de sí."

> **Vara de Vorhael (corroída):** "Contuvo grietas durante siglos. Después intentó cerrarlas
> todas de una vez. Lo que le pasó a la mano se ve en el mango."

---

### Registro 7 — Pista ambiental

**Cuándo:** texto **mínimo anclado a un objeto o lugar** del mundo: cartel de zona, inscripción en
una puerta sellada, marca en una pared, lo grabado en un sello, una sala que el escenario "dice"
sin palabras. Lo más cerca de contar **sin texto**.

**Reglas:**
- Máxima economía. Una frase, a veces tres palabras. La situación carga el resto.
- Funciona **pegado a lo que el jugador ve**: la frase + la sala sellada por dentro = el sentido.
- Es la prioridad narrativa más alta del plan (situación > ambiente > documento): preferí esto
  antes que un diálogo siempre que se pueda.
- Doble lectura concentrada: un cartel que el clímax del piso 0 va a desmentir.
- Cero exposición. Si explica, dejó de ser pista.

**Longitud:** 1 frase o menos. Un cartel: pocas palabras.

**Inspiración:** la narración por entorno de Hollow Knight / Dark Souls (un objeto colocado cuenta
más que un párrafo) — el escenario es el narrador.

**Ejemplos (canon v4):**

> *(Cartel del piso 0, antes del clímax):* **"PISO 0 — RAÍZ DE LA TORRE."**
> *(El giro lo desmiente poco después: la raíz no termina acá.)*

> *(Grabado en una puerta sellada por los Threnvar):* "Cerramos esto desde arriba. Que nadie lo
> abra desde abajo."

> *(Inscripción al borde del descenso al Nudo, antes de saber qué es):* "Más allá empieza lo que
> sostenemos. No es para visitarlo. Es para que siga ahí."

---

## 4. Tabla resumen

| # | Registro | Uso | Longitud | Voz |
|---|---|---|---|---|
| 1 | **Diálogo natural** | Lo que un personaje dice ahora (jefes, heridos, Veyran, ecos de Sorin) | 1–2 oraciones | Cuerpo que habla; parco, parcial; humor solo orgánico de un personaje |
| 2 | **Prosa narrativa** | Cámara: prólogo (eclipse rojo), transiciones, clímax del piso 0 | 2–5 frases/plano | Narrador sensorial, seco, sin moraleja ni humor |
| 3 | **Registro histórico** | Crónicas, actas, edictos, protocolos del Consejo | 3–6 líneas (libro = excepción larga) | Institucional, fría, se contradice; eufemismo de poder |
| 4 | **Diario personal** | Voz íntima: hoja de enfermería, márgenes, diario de Sorin | 3–6 líneas | Primera persona quebrada, confiesa, duda de su cordura |
| 5 | **Tratado arcano** | Técnico-mágico: Numen, sello, El Threnodion, varas | 3–6 líneas | Preciso, de oficio; el horror entra por el dato |
| 6 | **Lore de ítem** | Sabor de varas/reliquias (artefactos Maelvorn) | 1 frase (2 máx) | Densa, comprimida, mítica |
| 7 | **Pista ambiental** | Carteles, inscripciones, grabados anclados a un lugar | 1 frase o menos | Mínima, pegada a lo visible; el entorno narra |

---

## 5. Paleta de inspiración — brújula, no copia

Referentes para calibrar el oído. **Tomamos la técnica, no el contenido.** Nada de elfos, nada de
jerga prestada, nada de copiar líneas.

| Referente | Qué TOMAR | Qué EVITAR |
|---|---|---|
| **Dark Souls / Elden Ring** | Lore de ítem comprimido; narración por entorno; jefes trágicos; lore fragmentado | Crípticovacío sin pago; oscuridad como pose; nombres impronunciables |
| **Diablo** | Densidad gótica; el descenso/cripta; nombres de objeto con peso; ambiente opresivo | Edginess gratuita; demonios genéricos; exposición de cinemática |
| **Dragon Age** | Instituciones mágicas; códices opcionales; historia oficial vs. registros que la desmienten | Volcado de wiki; árboles de diálogo eternos; lore que frena el juego |
| **The Witcher** | Diálogo aterrizado; notas de personaje cotidianas que se tuercen; gris moral real | Cinismo de marca; vulgaridad como tono; sarcasmo del protagonista |
| **Tolkien / Silmarillion** | Cronista distante; peso mítico de los nombres; tono de escritura antigua | Arcaísmo recargado; genealogías; bien/mal absolutos |
| **Game of Thrones** | La verdad es política; nadie tiene la versión completa; eufemismo de poder | Shock por shock; crueldad decorativa; demasiados nombres a la vez |
| **Berserk / Warhammer** | Paneles mudos que pesan; maquinaria sagrada con horror técnico; fatalismo | Grimdark de catálogo; gore como sustituto del sentido; desesperanza plana |

**Brújula de una línea:** *Souls/Diablo* para los ítems, el descenso y el ambiente; *Dragon
Age/GoT* para los archivos que se contradicen; *Witcher* para los diarios y el diálogo;
*Silmarillion* para los nombres y la cosmología; *Berserk/Warhammer* para el horror técnico y los
silencios. **El tono base es serio en todos.** El humor no sale de ninguna paleta: sale de un
personaje, raro, y nunca del narrador ni los libros.

---

## 6. Cómo pedir / escribir

### 6.1 El patrón de 3 variantes (antes de canonizar)

Nunca canonices la primera línea. Para cualquier pieza importante, generá **3 variantes** y elegí
(o combiná):

- **Variante humana:** la más directa y emocional. ¿Cómo lo diría alguien que lo vivió?
- **Variante oscura:** sube la doble lectura y la consecuencia. Más sombra, menos consuelo.
- **Variante histórica:** la pasa por la voz institucional / distante. Fría, citable, contradictoria.

Las tres en el registro pedido. Comparás cuál clava el tono y respeta la regla de oro; muchas
veces la final es un cruce (lo humano de una, la doble lectura de otra).

**Ejemplo — post-combate de un jefe trágico (Liraen, la llave manipulada):**
- *Humana:* "No te quería lastimar. Nunca te quise lastimar. Pero no puedo parar esto."
- *Oscura:* "Me dijeron que esto nos salvaba a todos. Recién ahora veo lo que abrí."
- *Histórica:* "El niño de la savia fue pieza del Refuerzo. Nadie escribió qué pasa cuando la
  pieza decide por su cuenta."

→ Para el momento jugable conviene la **humana** o un cruce humana+oscura (Liraen es trágico, no
malvado). La histórica sirve para un documento, no para su boca.

### 6.2 Cómo nombrar el registro al pedir

Pedí siempre con: **registro + elemento real + intención**. Formato:

> "Registro **N** (`nombre`), para **\[elemento real de `data.gd` / del juego]**, que haga
> **\[doble lectura / golpe / siembra de lore / etc.]**. Largo: \[según tabla §4]."

**Buenos prompts:**

> ✓ "Registro 6 (lore de ítem) para una vara legendaria Maelvorn. Una frase. Que insinúe que su
> dueño cayó por exceso de poder sin temple. Sin nombrar el Nudo."

> ✓ "Registro 3 (histórico) para un edicto **Threnvar** del Refuerzo del Sello. 4 líneas, eufemismo
> de poder, que respete la regla de oro (no nombrar el inframundo)."

> ✓ "Registro 1 (diálogo) — 3 frases pre-combate de un jefe que era un Threnvar del Refuerzo, ahora
> herido y delirando. Voz parcial, sin humor, con una pista del estallido."

**Malos prompts (qué evitar):**

> ✗ "Escribime algo épico sobre la Torre." *(Sin registro, sin elemento, sin largo. Sale genérico.)*
> ✗ "Dame todo el lore de Morvath y Vaelroth." *(Volcado del iceberg; rompe la regla de oro y
> "nadie tiene la versión completa".)*
> ✗ "Una línea graciosa del narrador en el clímax." *(Rompe la regla maestra: el narrador no hace
> humor, menos en el golpe.)*

---

## 7. Checklist anti-error

Pasá **toda** pieza por estas preguntas antes de darla por buena. Si alguna falla, reescribí.

**Tono y reglas duras (innegociables):**
- [ ] **¿Rompe la regla de oro?** ¿Dice o sugiere lo que hay debajo del piso 0 (el Nudo, la
      grieta, el inframundo, Vhorrak, los dioses) en sentido literal antes del clímax? → Si sí, **fuera**.
- [ ] **¿Mete humor donde no va?** ¿Hay un chiste durante un golpe emocional? ¿El narrador o un
      libro hacen humor? → Si sí, **cortar**. El humor solo si es de un personaje, orgánico y lejos
      del remate.
- [ ] **¿Vuelca el iceberg?** ¿Le explica al jugador lore que debería reconstruir solo? → Cortar
      exposición; dejar la pieza para que se arme por capas.
- [ ] **¿Tiene doble lectura?** (En piezas clave.) ¿Funciona entera siendo inocente HOY, y gana un
      segundo sentido después? Si solo tiene sentido sabiendo el giro, es spoiler.

**Voz y registro:**
- [ ] **¿Suena como otro registro?** ¿Un diario que suena a crónica oficial? ¿Un ítem que se volvió
      párrafo? ¿Un cartel que explica? → Reencauzar al registro correcto (§3).
- [ ] **¿Respeta la longitud** de la tabla §4? (Ítem = 1 frase, no un cuento. Escena ≤ 6
      intervenciones.)
- [ ] **¿Veyran habla poco y preciso**, sin explicar lo que ya sabe?

**Sustancia:**
- [ ] **¿Explica de más?** ¿Le dice al jugador lo que la situación ya muestra? → Cortar exposición.
- [ ] **¿Alguien tiene la versión completa / omnisciente?** Nadie dice "Sorin es el villano" ni
      "los Threnvar son los malos". Versiones parciales, siempre.
- [ ] **¿La revelación importante tiene al menos dos interpretaciones?**
- [ ] **¿Los nombres son canon v4?** Clanes Karreth/Cindrael/Maelvorn/Threnvar/Caelreth; personas
      Veyran/Sorin/Liraen/Vhorrak/Vorhael/Killaeth; entidades Vaelroth/Oriael/Morvath/Numen/Nudo/
      Threnodion/Custodios. **Nada de** "-nir", Skarun, Bucle, Archimago, Cuteo, subsuelo/Piso −1.
      (Cotejá `data.gd` y `BIBLIA_NARRATIVA.md`.)
- [ ] **¿El antagonista tiene una razón comprensible** para pelear? Liraen no quiere herirte; Sorin
      cree que salva el mundo. El daño se entiende, no se festeja.

**La prueba final:** leéla en voz alta. Si suena a chiste cuando debería doler, si vuelca el
iceberg, o si explica cuando debería insinuar, todavía no está.
