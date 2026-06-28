> ⚠️ **DOCUMENTO SUPERSEDED — NO ES CANON.**
> Esto es material **v3 (premisa vieja: *La Cárcel del Cuteo*)**: torre-mundo donde se vive, eclipse que enloquece, seis clanes `-nir` (Colnir/Kilnir/Durnir/Jernir/Fernir/Skarun), dualidad cómica "Cuteo", Piso 0 → Piso −1.
> Quedó **SUPERSEDED por `docs/lore/BIBLIA_NARRATIVA.md` (v4)** y `docs/lore/FLUJO_JUEGO_BASE.md`. La premisa actual es *La Torre de Killaeth*: fantasía oscura SERIA, clanes por Temple (Karreth/Cindrael/Maelvorn/Threnvar/Caelreth), Veyran de protagonista, Sorin/Liraen/Vhorrak/Morvath, el árbol Vaelroth, el Nudo, el eclipse rojo.
> Se conserva solo como **historia y banco de textos viejos**. **NO usar como fuente de verdad.** Para escribir o auditar lore, andá a la biblia v4.

---

# Propuestas de Lore — 2026-06-26 (EN REVISIÓN, **no canon todavía**)

> Generado por 4 agentes en paralelo sobre el canon existente (`docs/PLAN_NARRATIVO.md` + el `LORE.md` raíz del pixi).
> **Nada de esto está fijado.** Es material para que Felipe lo chequee y marque las 6 decisiones (sección C-6).
> Una vez elegidas las decisiones, esto se consolida en la biblia v3. Historia EN PAUSA por pedido de Felipe.

Índice:
- **A — Aterrizaje canon→juego** (lore por enemigo, mapeo de zonas, gaps, renombres)
- **B — Documentos / coleccionables** (textos paste-ready)
- **C — Guion** (prólogo, jefes, voz, falso final, **6 decisiones**)
- **D — Tono "Cuteo"** (origen + research + recomendación)

---

# A — Aterrizaje del canon a los sistemas

**Premisa base:** el eclipse alteró la red mágica → la gente "pierde la razón" y se **transforma**. Casi ningún enemigo es un monstruo externo; son **habitantes de la torre deformados** por clan/función. Cumple la regla de oro (nada de subsuelo) y conecta con reencuentros + narración ambiental.

## A.1 — Lore por enemigo (atado a los 6 clanes)

| Enemigo | Qué ES en este mundo |
|---|---|
| **rata** | Plaga de la torre, no transformado. Heredan los pisos que los magos abandonaron. Señal de colapso, no de clan. |
| **slime** | Reactivo alquímico **Fernir** desbordado: cultivos de biología mágica que el eclipse soltó de sus tanques. Vida sin mente. |
| **murciélago** | Fauna de huecos y conductos altos (campanarios, tiros de ventilación). Ecosistema, no clan. |
| **araña** | Fauna de archivos y depósitos sellados (telas entre estanterías Colnir/Jernir). Infesta lo cerrado hace tiempo. |
| **zombi** | Habitante común que perdió la mente pero no el cuerpo. El caso más puro de "perder la razón": el vecino que ya no es nadie. |
| **fantasma** | Un **desaparecido reciente** — eco de alguien que el eclipse "borró". Errático: solo le queda el último impulso. |
| **espectro** | Desaparecido **antiguo/Skarun-adyacente**: más definido y agresivo. Por eso aparece tarde (Santuario) y es minion del Liche. |
| **orco** | NO una raza externa (rompe el tono). Reskin → **guardián/bruto Durnir degenerado**: soldado de cuarentena reducido a pura agresión. |
| **cultista** | Seguidores del **mago joven** / artes Skarun incompletas. Los únicos enemigos *con voluntad*: eligieron esto. Disparan magia. |
| **caballero (maldito)** | **Guardián Durnir de élite corrompido** — versión completa y leal del "orco". Hermano temático de Bucle (jefe). |
| **golem_chico** | Creación **Jernir**: autómata de custodia con órdenes corruptas. Versión menor del Gólem Anciano (jefe). |
| **lich / "Liche menor"** | Archivista **Colnir** que intentó preservar su memoria y falló. Intento fallido del arte del jefe Liche. |

**Cuatro categorías legibles:** voluntad perdida (zombi, orco, caballero, golem, lich menor) · ecos de desaparecidos (fantasma, espectro) · fauna/plaga (rata, murciélago, araña) · eligieron (cultista).

## A.2 — Mapeo de las 3 ZONES a capítulos (calza 1:1)

| ZONE | Capítulo | Clan dominante | Qué cuenta el ambiente |
|---|---|---|---|
| **Torre en Ruinas** (`torre`, boss `bucle`) | **Cap I — La torre quebrada** | Durnir (cuarentenas) + restos Fernir | Pisos altos rotos, puertas selladas, vecinos transformados. Primer deterioro + reencuentros. |
| **Cavernas Hondas** (`cavernas`, boss `golem_anciano`) | **Cap II — Las máquinas de la memoria** | Jernir (infraestructura, archivos) | **NO subsuelo:** los grandes vacíos INTERNOS de la torre (tiros de ventilación, conductos arcanos, depósitos colosales). |
| **Santuario Profano** (`santuario`, boss `liche`) | **Cap III — El último piso conocido** | Skarun/Colnir + ecos del joven | Santuario del Consejo, acceso al Piso 0, laboratorio del joven, ecos. "Profano" = aquí se cruzó el límite. |

## A.3 — Gaps y contradicciones (canon vs. implementado)

1. **🔴 "Cavernas Hondas" roza la regla de oro** ("hondas" puede leerse como subsuelo). Fix solo en el campo `name` → **"Entrañas de la Torre"** o "Los Conductos Hondos". "Santuario Profano" está OK (profano = sacrílego).
2. **🟡 "orco" no encaja** en una torre de magos (única raza genérica). → Reskin a "Bruto Durnir". 0 cambio de stats.
3. **🟢 Jefes alineados:** `bucle`→Cap I (Durnir), `golem_anciano`→Cap II (Jernir), `liche`→Cap III (Colnir). Coinciden con el plan.
4. **🟡 Doble araña** (`arana` y `arana_v2`): solo `arana_v2` se usa; `arana` huérfana (candidata a limpieza algún día, no ahora).
5. **🟢 `cultista` shooter en Santuario** es perfecto para sembrar Skarun/joven sin nombrarlos.

## A.4 — Renombres (refuerzan lore, **0 gameplay** — solo `name`/tinte)

| id | name actual | propuesto | Por qué |
|---|---|---|---|
| **orco** | "Orco" | **"Bruto Durnir"** | Saca la raza genérica. **El más importante.** |
| **caballero** | "Caballero maldito" | "Guardián Maldito" (o dejar) + tinte azul-acero | Vincula a Durnir. Opcional. |
| **golem_chico** | "Gólem menor" | "Autómata Jernir" | Marca el clan. Opcional. |
| **lich** | "Liche menor" | "Liche fallido" / "Memoria rota" | Deja claro que es intento fallido del arte del jefe. |
| **espectro** | "Espectro" | (dejar) + tinte violeta frío (Skarun) | Diferenciar del fantasma. |
| **slime** | "Slime" | "Cultivo Fernir" (opcional) | Refuerza origen alquímico. |

**Mínimo esfuerzo / máximo impacto = 2 cambios:** `orco`→"Bruto Durnir" + zona `cavernas` `name`→"Entrañas de la Torre".

**Pregunta de canon abierta:** ¿`fantasma`=desaparecido reciente y `espectro`=antiguo/Skarun? (asumido para diferenciarlos).

---

# B — Documentos / coleccionables (textos paste-ready)

> Respetan la regla de oro: "descenso/abajo/fondo" solo moral o pisos conocidos; doble lectura; nadie dice "los Skarun fueron buenos/malos". Tono medieval-arcano (Cinzel/Marcellus).

## B.1 — Registros Colnir — *"El conocimiento ilumina."*

**Fragmento A — *De la Crónica de los Seis, tomo IX***
> En el año 412 del Concilio, el clan Skarun fue **exiliado** de la torre por unanimidad del Consejo, y partieron por su propio pie hacia tierras que ya no nos pertenecen. Que conste su nombre con honor: ninguno opuso resistencia.
> *— Maestro archivero Velren, mano firme*

*(Doble lectura: "partieron hacia tierras que ya no nos pertenecen" = destierro al exterior; tras la revelación = descenso voluntario a lo que dejó de figurar en los mapas.)*

**Fragmento B — *Mismo tomo, folio siguiente, otra mano***
> Corríjase lo anterior. En el año **409** —tres antes de lo escrito— los Skarun no fueron exiliados: se **extinguieron** durante el invierno largo, y no quedó ninguno para marcharse. He cotejado tres archivos. Los tres dan fechas distintas. Uno de los tres miente, y temo que sea el que yo mismo copié.
> *— Aprendiz que no firma, por prudencia*

*(Anticipa "el archivo que se reescribe".)*

## B.2 — Órdenes Durnir — *"La fuerza protege."*

**Fragmento A — *Bando de cuarentena, sello del escudo***
> Por orden del clan Durnir: queda **sellado todo paso hacia los pisos bajos** hasta nueva voz. Quien cruce sin venia será tratado como contagiado. No es crueldad: es contención. Una torre se sostiene cerrando puertas, no abriéndolas.
> Manténganse en su nivel. Manténganse cuerdos.

**Fragmento B — *Orden de marcha tachada y reescrita***
> Recordad por qué levantamos barreras: **ningún clan descendió tan bajo** como aquel que cruzó el último límite. No hablamos de pisos. Hablamos de lo que un mago se permite hacer. Si vuestra mente os ordena bajar a buscarlos, no es vuestra mente la que habla.

*(Eco directo de la frase del jefe Bucle: "Ningún clan descendió tan bajo".)*

## B.3 — Contrato Kilnir — *"La unión sostiene la torre."*

**Acta de Concordia, cláusula séptima — sello lacrado de los cinco clanes**
> Las partes convienen que **ciertos hechos del año del exilio no serán transcritos en registro público alguno**, y que las copias divergentes serán retiradas de las academias sin destruirse, para preservarlas de mano indebida.
> No llamamos a esto ocultar. Lo llamamos **sostener la paz**. Una verdad dicha a destiempo costó, una vez, diez mil vidas en las plantas altas. Quien firma elige el mal menor con la conciencia tranquila.
> *Anotación al margen, tinta privada:* Que conste que yo me opuse. Y que firmé igual.

*(La versión oficial se eligió, no se descubrió → "la historia oficial fue construida y mantenida activamente".)*

## B.4 — Plano Jernir — *"Toda magia puede construirse."*

**Nota de obra adjunta al plano maestro de conductos — gremio Jernir**
> Conducto primario de energía: nace en la corona de la torre, recorre las cuarenta y dos plantas y **descarga en el Piso 0**, donde se cierra el circuito. No hay nivel inferior que alimentar; el plano termina donde termina la torre.
> Obsérvese una anomalía sin resolver: el conducto pide **más caudal del que cuarenta y dos plantas consumen**. Sobra energía. El maestro de obra anterior anotó "error de cálculo" y cerró el expediente. Yo repetí las cuentas tres veces. No es un error de cálculo.

*(En lenguaje técnico, jamás "subsuelo", planta que algo más abajo está siendo alimentado.)*

## B.5 — Notas Fernir — *"La vida encuentra su camino."*

**Nota A — *Hoja de cama 14***
> Paciente lúcido entre las crisis. Refiere oír **una voz que viene de bajo el suelo**, que lo llama por su nombre de niño. Le expliqué que no hay nada bajo nosotros, que el suelo es solo suelo. Asintió. Una hora después lo hallé arañando las baldosas con las uñas, pidiendo perdón a alguien.
> No hay fiebre. No hay herida. La razón se va sola, como agua entre los dedos.

**Nota B — *Hoja de cama 3, misma mano, más tarde***
> Curioso: los que enloquecen más rápido son los que **más abajo vivían**. Los de la corona aún resisten. ¿Sube el mal, o desciende hacia donde ya esperaba?
> Anoto esto y me tiembla el pulso, porque no es una pregunta de sanadora. Que la lea quien sepa más que yo. Si queda alguien.

## B.6 — Fragmentos Skarun — *"Ninguna verdad debe permanecer oculta."*

**Fragmento A — *Sin sello, hallado donde no debería haber nada***
> Vosotros medís la torre por su altura. Nosotros aprendimos a medirla por su **profundidad**, y descubrimos que no son lo mismo número.
> No nos fuimos. Nos quedamos donde dejasteis de mirar.

**Fragmento B — *Letra apresurada, sin fecha, lema antiguo al pie***
> Si lees esto, alguien rompió un sello que cinco manos lacraron. Bien. Una verdad enterrada no deja de ser verdad: solo deja de ser tuya.
> No preguntes qué hicimos. Pregunta **quién necesitó que lo olvidaras**, y por qué te dieron mapas que terminan tan pronto.
> *Ninguna verdad debe permanecer oculta.*

## B.7 — Libro principal: *El Archivo que se Reescribe*

*Compilado por el clan Colnir. Léase sabiendo que no hay dos copias iguales, y que esta tampoco lo será mañana.*

> Esta es la única página que el archivo permite escribir en limpio, y aun así dudo que sobreviva a la noche. Quien la lea sabrá tanto como yo, que es decir: demasiado y nada.
>
> **La versión que se enseña en las academias** dice que los Skarun cometieron una atrocidad sin nombre —pues el nombre, también, fue retirado de los registros— y que por ello el Consejo los **exilió** en el año 412. Una historia limpia. Tiene principio, culpa y castigo. Los pueblos duermen mejor con historias así.
>
> **La versión que guardan los Durnir** no habla de exilio sino de **encierro**: los Skarun no fueron enviados afuera, fueron **contenidos**, sellados tras barreras que el propio clan del escudo levantó y juró no volver a abrir. "No se destierra una enfermedad —escribió uno de sus guardianes—; se la encierra donde no pueda subir."
>
> **La versión que insinúan los Kilnir**, entre cláusulas y silencios, es que **no hubo crimen alguno** lo bastante grande para justificar lo que se hizo, y que el verdadero delito de los Skarun fue saber algo que cinco clanes prefirieron sepultar antes que escuchar. Firmaron un acta. Llamaron paz a la mordaza.
>
> **Y hay una cuarta versión**, que ningún clan firma, que aparece y desaparece de estas páginas como si el papel tuviera vergüenza: que los Skarun **no desaparecieron en absoluto**. Que siguen donde siempre estuvieron. Que fuimos nosotros quienes nos alejamos de ellos, piso a piso, generación tras generación, hasta convencernos de que el lugar donde habitan es el fin del mundo.
>
> No sé cuál es verdadera. He cotejado las cuatro y cada una desmiente a las otras tres con la misma firmeza. Lo único en que coinciden —y esto me quita el sueño— es en una palabra que ninguna explica: todas dicen que los Skarun **descendieron**. Ninguna dice hacia dónde.
>
> Si vuelves a esta página y la encuentras distinta, no es tu memoria la que falla. Es la torre, recordando lo que le conviene. Lee rápido. Y desconfía de quien te diga que ya sabe el final.

---

# C — Guion (beats clave)

## C.1 — Prólogo "El eclipse imposible" (4 planos breves, cierra en control)

1. **Ventanal de la cima.** Torre dormida, cielo limpio, dos lunas. Runas tranquilas. *(Quietud, un segundo de más.)*
2. **La oscuridad llega sin transición.** No avanza como sombra: *aparece*. Las dos lunas siguen encendidas — y aun así no hay luz.
3. **Las runas se encienden al revés.** Recorren el pasillo en orden inverso. Zumbido grave. Abajo, lejos, cae la primera puerta de cuarentena.
4. **Interior, el archimago de espaldas.** Apaga un candil que ya no servía. Voces que no son suyas se filtran. Se gira a la escalera de descenso. **→ control del jugador.**

**Primera frase (canon):** *"Esto no es una noche. Es una interrupción."*
Alt. A: "El cielo no se apagó. Alguien lo apagó." · Alt. B: "Las lunas siguen ahí. La luz, no."

## C.2 — Jefes (pre / durante / post)

**Bucle** — guardián Durnir atrapado repitiendo "impedir el paso":
- PRE: "Archimago. Llega tarde. La orden ya se dio. …¿Qué orden."
- PRE: "Nadie baja. Esa es la línea. Yo soy la línea."
- DURANTE: "Otra vez. Otra vez. Siempre llegás otra vez."
- POST (canon): "Ningún clan… descendió tan bajo. ¿Hacia dónde es abajo."

**Gólem Anciano** — custodio Jernir de la integridad de los archivos:
- PRE: "Registro no coincide. Sujeto recuerda lo que no ocurrió. Corrigiendo."
- DURANTE: "Los Skarun fueron exiliados. Los Skarun se marcharon. Los Skarun nunca— *error*. Recalculando."
- POST: "Si tu memoria es la verdad… entonces yo guardé una mentira. No tengo orden para esto."

**El Liche** — historiador Colnir que conservó su memoria:
- PRE: "No vengo de la muerte. Me quedé. Alguien tenía que recordar antes de que lo reescribieran."
- PRE: "Bajás a saquear lo que yo bajé a salvar. No es lo mismo."
- DURANTE: "Lo conservé todo. Y aun así me falta una página."
- POST: "El Piso 0 no es la salida. Es la última puerta. Yo creí que descender era una metáfora."

## C.3 — Voz del protagonista (muestras)

1. "Las runas se leen al revés. Quien hizo esto sabía leerlas bien."
2. *(cadáver Durnir en su puesto)* "No huyó. Cumplió la orden hasta que la orden lo mató."
3. *(sala sellada por dentro)* "Se encerraron con lo que temían. O con lo que sabían."
4. "Cinco versiones, cinco archivos. Cuatro mienten. O todas."
5. *(reconoce a un transformado)* "Lo conocí cuerdo. No es excusa para que me mate."
6. *(borde de una escalera)* "Sé cuántos pisos faltan. El problema es que el número deje de bajar."

## C.4 — Eco del joven mago ambicioso (sin nombre todavía)

- "La barrera que el Consejo llama 'infranqueable' cede en tres puntos. Lo vi en una tarde. Llevan siglos sin mirar."
- "Durnir lo llama 'límite'. Yo lo llamo cobardía con buena caligrafía. El miedo no es una ley natural."
- "Los fragmentos Skarun estaban incompletos *a propósito*. Alguien quería que yo completara el resto. Bien. Lo completé."

## C.5 — Falso final Piso 0

1. Sala amplia, limpia, **iluminada de verdad** por primera vez. La música respira.
2. Cartel: **"PISO 0 — EL FONDO DE LA TORRE"**. Progreso 100%.
3. El archimago halla la **salida sellada**. Apoya la mano. Silencio de alivio.
4. Un mecanismo reacciona al **registro recuperado del Liche** que lleva encima. Sin que él lo active.
5. El sello no se abre hacia afuera: se abre **hacia abajo**. Un escalón donde no debía haber escalón.
6. Se enciende una numeración imposible: **−1**.

**Últimas líneas (canon):** *"ARCHIMAGO: Todos los mapas terminaban aquí. — VOZ DESCONOCIDA: Los mapas, sí."* (Cortar a negro inmediatamente.)

## C.6 — Las 6 DECISIONES (de Felipe) — opciones + recomendación

| # | Decisión | Opciones | **Recomendado** |
|---|---|---|---|
| 1 | Protagonista | A) Colnir (erudito) · B) sin clan (testigo neutral) · C) Fernir (sanador) | **B + "Veyran"** (alt: A) |
| 2 | Joven ambicioso | A) anónimo hasta tarde · B) nombre temprano · C) apodo de registros | **A → revelar "Sorin" tarde** |
| 3 | "Bucle" | A) apodo (nombre formal "Rennod") · B) nombre formal "Bucle" (+cómico) | **A — apodo, formal "Rennod"** |
| 4 | ¿Liche sobrevive? | A) sobrevive breve · B) no, deja el registro | **B** (el registro detona el −1) |
| 5 | Piso −1 | A) cliffhanger · B) sigue jugable un tramo | **A — cliffhanger** esta campaña |
| 6 | Humor "Cuteo" | A) mínimo · B) capas separadas · C) tragicómico integrado | **B — capas separadas** |

> Decisiones **3 y 6 enlazadas** (apodo ↔ humor en capas). El resto independientes.

---

# D — Tono "Cuteo" (origen + research + recomendación)

## D.1 — ¿Qué era el "Cuteo"?
**Sin etimología documentada** (rastreado en README, CHANGELOG, ANALYSIS, DESIGN_*, código). Aparece solo como branding ("short_name": "El Cuteo"). Quedó **indefinido por diseño** — el chiste-semilla original, anterior al lore trágico (LORE.md es "v2").

**El ADN del humor vive en Bucle:** `manifest.json` = *"Esquivá el tackle de Bucle."* · `data.js` = *"jugador de rugby maldito"* (tackle + patear su pelota, pack `boss_rugby`). Es **absurdo dadaísta-rioplatense de imagen incongruente** (rugbier en una torre de magos), no humor verbal. El `PLAN_NARRATIVO` ya empezó a resolver la tensión con Bucle ("deja de ser solo cómico y describe su condena") → **esa jugada es la plantilla.**

## D.2 — Técnicas de juegos comparables
1. **Narrador modula el tono (Darkest Dungeon):** humor en mecánicas, gravedad blindada en la voz.
2. **Stakes bajos = licencia para el chiste (Hades):** el humor escala inverso a lo que está en juego.
3. **El humor es un dial dinámico (Undertale):** se apaga cuando la tragedia toma el control.
4. **Transición gradual, no corte (anti mood-whiplash):** rampa, no cero-a-cien.
5. **La cáscara tierna ES el setup de la tragedia (Kirby/EarthBound/Deltarune):** el contraste lindo→oscuro *amplifica* el bajón.
6. **Melancolía por restricción (Hollow Knight/Hyper Light Drifter):** tragedia por ambiente y silencio, no diálogo.

## D.3 — Recomendación: **(A) dualidad con la disciplina de (B)**
Cáscara absurda que esconde tragedia, ejecutada con reglas de modulación. Tres razones del propio material:
1. Tu lore YA es sobre **superficies que mienten** (Piso 0 → −1). El título engañoso es la misma figura, una capa afuera.
2. La jugada **ya está probada en Bucle** y funciona → escalar el patrón-Bucle al título entero.
3. (B) es la herramienta para que (A) no se rompa: **humor en la cáscara/mecánica, gravedad en la voz del archimago y los libros.**

**Regla operativa (para escribir todo el juego):**
> El humor vive en la **superficie y los sistemas** (título, nombres de jefes, mecánicas incongruentes, falsa victoria). La tragedia vive en la **voz y la consecuencia** (archimago, libros, lo que les pasó a los que conocías). Nunca un chiste *durante* un golpe emocional; siempre la incongruencia *antes*, para que la caída duela más.

**Acción de regalo:** convertir "Cuteo" en un coleccionable Colnir cerca del Piso 0 que revele que era un **mote cariñoso** del mundo previo a la tragedia → resuelve la decisión #6 y le da un pago emocional al título.
