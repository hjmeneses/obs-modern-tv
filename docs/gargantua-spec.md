# Gargantúa — shader de agujero negro para OBS

Spec para desarrollo guiado por especificaciones. Este documento es la fuente de verdad: los requisitos y las pruebas se definen antes del código, y un cambio de requisitos se hace aquí primero.

Versión 1.2 de la spec. Las secciones [Cambios en la versión 1.2](#cambios-en-la-versión-12) y [Cambios respecto a la versión 1.0](#cambios-respecto-a-la-versión-10) explican qué cambió y por qué.

## 1. Nombre y objetivo

- **Nombre:** Gargantúa — agujero negro. Inspirado en el agujero negro de *Interstellar* (2014); el título de la película no va en el nombre del filtro.
- **Tipo:** filtro `.shader` para [obs-shaderfilter](https://github.com/exeldro/obs-shaderfilter), procedural, en tiempo real y sin fin.
- **Objetivo:** un agujero negro con disco de acreción como fondo o intro en vivo, sin video pregrabado, que quepa en el presupuesto de una GTX 1650 Ti (sección 8).

No es un video: se aplica sobre una fuente de color o una escena vacía y siempre está animado. Desde la 1.2 también se puede poner sobre una escena: el lente la deforma como al cielo de estrellas.

## 2. Problema que resuelve

Un clip de la película como fondo pesa, se nota el loop y no se puede ajustar en vivo, porque es video fijo. Un shader genera el agujero en cada cuadro, así que el brillo, la velocidad del disco y la intensidad del lente se cambian en vivo sin cortar el stream.

## 3. Alcance

**Dentro:**

- Agujero negro central con anillo de fotones.
- Disco de acreción girando, visto casi de canto y un poco por encima, con la parte de atrás del disco visible por encima y por debajo del agujero por el lente.
- Efecto Doppler: el lado que se acerca más brillante y blanco, el que se aleja más oscuro y rojizo.
- Fondo de estrellas procedural, con leve parallax y deformado por el mismo lente.
- Glow barato.
- Modo escena *(1.2)*: el lente deforma la imagen de entrada en lugar del cielo, con el disco opcional y el agujero en cualquier posición.
- Parámetros ajustables en el panel del filtro.

**Fuera:**

- Relatividad general exacta (métrica completa, tiempo propio, corrimiento gravitacional exacto).
- Disco volumétrico.
- Naves, planetas, texto, audio, modelo 3D.
- Calidad alta por encima de 1080p.

## 4. Referencia visual

Claves que se cumplen sí o sí:

- Centro negro perfecto, sin detalle ni ruido.
- Anillo fino y brillante alrededor del centro.
- Disco horizontal naranja que pasa por delante abajo y por detrás arriba, curvado sobre el agujero.
- Asimetría izquierda-derecha muy marcada por Doppler.
- Fondo negro profundo, no gris.

| Elemento | Color |
| --- | --- |
| Centro | `#000000` |
| Anillo | `#FFF6D8` a `#FFFFFF` |
| Disco interior brillante | `#FFE9A8` |
| Disco medio | `#FF9E2C` |
| Disco exterior | `#C1440E`, tendiendo a `#7A2E0D` en el lado oscuro |
| Fondo | `#000000` con estrellas `#FFFFFF` a baja opacidad |

## 5. Requisitos funcionales

- **RF01:** Renderiza sin imagen de entrada: funciona sobre una fuente vacía o de color.
- **RF02:** El disco gira de forma continua, sin saltos.
- **RF03:** El lente curva la imagen del disco por encima y por debajo del agujero.
- **RF04:** El Doppler se nota a primera vista.
- **RF05:** Todos los parámetros se ajustan en vivo, sin recompilar ni reiniciar OBS.
- **RF06:** Tiene un modo bajo (32 pasos) que cabe en el presupuesto de la sección 8.
- **RF07:** Se ve correcto en 1920×1080 y en vertical 1080×1920 sin estirarse. El tamaño se mide sobre el lado corto; en vertical, lo que no cabe a los lados se recorta.
- **RF08** *(1.2)*: Con `background` = Escena, el fondo es la imagen de entrada deformada por el lente. Donde el lente no la desvía sale idéntica: sin exposición, tone mapping ni dithering.
- **RF09** *(1.2)*: La sombra sigue siendo negro puro sobre la escena, y el lente forma el anillo de Einstein con lo que queda detrás del agujero.
- **RF10** *(1.2)*: El agujero se puede mover a cualquier punto del cuadro (`center_x`, `center_y`), en los dos modos.
- **RF11** *(1.2)*: El disco se puede apagar (`show_disk`); sin disco no hay anillo de fotones ni glow, solo la sombra y el lente.

## 6. Parámetros

Las etiquetas del panel van sin acentos (obs-shaderfilter no los muestra bien), como en los otros shaders del repo.

| Parámetro | Rango | Defecto | Descripción |
| --- | ---: | ---: | --- |
| `background` | Estrellas o Escena | Estrellas | Qué deforma el lente: el cielo procedural o la imagen de entrada *(1.2)* |
| `center_x`, `center_y` | -0.7 a 0.7 | 0 | Posición del agujero en fracciones del ancho y del alto; 0 = centro, y hacia arriba *(1.2)* |
| `show_disk` | sí / no | sí | Disco, anillo de fotones y glow *(1.2)* |
| `black_hole_radius` | 0.15 a 0.35 | 0.22 | Radio aparente de la sombra, en fracción del lado corto, con el lente en 1 |
| `disk_inner_radius` | 1.0 a 1.5 | 1.15 | Inicio del disco, en múltiplos del radio de la sombra |
| `disk_outer_radius` | 2.0 a 3.5 | 2.8 | Final del disco, igual |
| `disk_thickness` | 0.05 a 0.30 | 0.12 | Opacidad y suavidad del disco: más grueso, más opaco |
| `inclination` | 2 a 30 | 8 | Grados de la cámara por encima del plano del disco *(nuevo)* |
| `rotation_speed` | 0.0 a 1.0 | 0.35 | Velocidad de giro de la textura del disco |
| `doppler_strength` | 0.0 a 2.0 | 1.0 | Intensidad de la asimetría |
| `lensing_strength` | 0.0 a 2.0 | 1.0 | Cuánto se dobla la luz. En 0 los rayos van rectos |
| `lens_reach` | 0.1 a 4.0 | 0.5 | Hasta dónde llega el lente sobre el fondo, en radios de la sombra (punto 9 de la sección 7). 0.5 es el valor fijo de la 1.1 *(1.2)* |
| `disk_brightness` | 0.0 a 3.0 | 1.2 | Brillo del disco |
| `glow_intensity` | 0.0 a 2.0 | 0.8 | Intensidad del glow |
| `star_density` | 0.0 a 1.0 | 0.5 | Densidad de estrellas |
| `exposure` | 0.5 a 2.0 | 1.0 | Exposición final |
| `quality_steps` | 32, 64 o 128 | 64 | Pasos del rayo. 32 es el modo bajo; 128 avisa que puede bajar los fps en gama baja |

## 7. Arquitectura técnica

Un rayo por pixel, doblado paso a paso. Es una aproximación, no la métrica completa.

1. Pixel a coordenadas de pantalla, centradas y escaladas por el lado corto (RF07).
2. Cámara en perspectiva a distancia fija, inclinada `inclination` grados sobre el disco. La escala se elige para que la sombra mida `black_hole_radius` con el lente en 1.
3. Unidades del agujero: radio de Schwarzschild = 1. Cada paso suma la aceleración de la órbita de un fotón, `a = -1.5·λ·h²·x/r⁵` (h = momento angular del rayo, λ = `lensing_strength`), con paso proporcional a `r`.
4. El rayo se captura con `r < max(λ, 0.5)` y sale cuando se aleja más allá del disco.
5. Cada vez que cruza el plano del disco entre el radio interior y el exterior, suma el color del disco (de adelante hacia atrás, con opacidad).
6. Textura del disco: 2 octavas de value noise en coordenadas polares, periódico en el ángulo, en dos capas que giran rígidas a velocidades distintas. Así parece rotación diferencial sin que las vetas se estiren sin fin.
7. Doppler: factor `g = √(1-β²) / (1 - β·n)` con la velocidad orbital del disco por `doppler_strength` (β ≤ 0.9). Brillo por `g³` y color corrido hacia blanco o rojo según `g`. Nunca da brillo negativo.
8. La sombra y el anillo se deciden con el parámetro de impacto `b` del rayo, analítico, para que el borde salga suave al pixel (AC08). Sombra: `b < b_c = 2.598·λ`.
9. Estrellas: hash en una rejilla sobre la esfera, con twinkle y una deriva lenta como parallax. Se buscan en la dirección final del rayo, pero el lente sobre ellas se atenúa lejos de la sombra: completo junto a ella (anillo de Einstein) y casi nada en las orillas. Es una decisión artística: las estrellas están en el infinito y, con el agujero ocupando el 22 % del cuadro, un rayo que pasa a 10 radios se desvía 0.2 rad, casi el ancho de la vista; con el lente completo todo el cielo sale estirado en arcos.
10. Glow: halo alrededor del disco acumulado en los pasos cercanos al plano, más un halo del anillo. Ninguno invade la sombra.
11. Todo en lineal; al final exposición, tone mapping, sRGB y dithering (solo donde no es negro).
12. Modo escena *(1.2)*: la dirección del rayo se vuelve a pasar a la pantalla con la inversa de la cámara y ahí se lee la imagen. Se suma el desplazamiento al uv del pixel, no el punto reconstruido, para que donde no hay desvío la escena salga idéntica bit a bit. La escena se suma en lineal después del tone mapping de la luz del agujero.
13. El desvío de la escena no sale del trazado sino de la fórmula de Schwarzschild a segundo orden, `α = 2λ/b + (15π/16)·λ²/b²`, por la misma atenuación del punto 9, y se satura con `tanh` en 3 veces el tamaño angular de la sombra. Junto a la sombra el rayo trazado se dobla cientos de grados: para el cielo está bien, pero la escena es un rectángulo chico y la lectura daba vueltas sin fin (muaré) y mostraba los escalones del trazado como líneas. Saturado, junto a la sombra queda la imagen secundaria (la escena del otro lado, invertida), continua.
14. Lo que cae fuera del cuadro lee la escena en espejo, sin pasar del centro de los pixeles de la orilla. Donde el lente comprime la escena se promedian 4 lecturas en el área del pixel, con tope para que un salto de la derivada no traiga colores de lejos.

`gargantua.shader` (español) y `en/gargantua.shader` (inglés) tienen el mismo código. Los comentarios van en el idioma de cada archivo, como en el resto del repo; el inglés se genera con `tools/make_en.py`. Sin texturas ni dependencias.

## 8. Rendimiento, GTX 1650 Ti

Lo que se mide es el tiempo de GPU que el shader agrega por cuadro, con el filtro a 1920×1080, contra la misma escena sin él. Se calcula con los contadores de Windows de uso del motor 3D de la GPU para el proceso de OBS (`\GPU Engine(*engtype_3D)\Utilization Percentage`): uso × duración del cuadro. El tiempo de render de OBS (`averageFrameRenderTime`) no sirve para esto, porque mide la CPU del hilo de render y el trabajo de la GPU corre aparte.

- Normal (64 pasos): menos de 8 ms.
- Bajo (32 pasos): menos de 5 ms.
- Sin más cuadros saltados por render que sin el filtro.

Para ahorrar más, la fuente de color puede ser más chica (por ejemplo 1440×810) y escalarse en la escena: el shader corre una vez por pixel de la fuente.

## 9. Integración en OBS

- Filtro **User-defined shader** con *Load shader text from file*, sobre una fuente de color negra o una escena vacía. En modo escena, sobre la escena o el grupo que se quiere deformar.
- Los sliders cambian en vivo sin parpadeo ni reinicio; al duplicar la escena se conservan los parámetros (lo hace OBS).
- Se registra en `shaders.js` de [obs-shader-dock](https://github.com/hjmeneses/obs-shader-dock) (y de ahí en [Shader Dock](https://github.com/hjmeneses/shader-dock)) como efecto continuo, con el nombre *Gargantúa*.

## 10. Criterios de aceptación

Las pruebas automáticas están en `tools/gargantua_tests.py`: arman una escena temporal en OBS, capturan por WebSocket y miden. La resolución de prueba es 1920×1080 salvo que se diga otra cosa.

| Id | Criterio | Cómo se mide |
| --- | --- | --- |
| AC01 | Con los valores por defecto se reconoce como un agujero negro con disco lenteado, no un eclipse genérico: centro negro y disco por encima del agujero. | Automático: la mitad superior de la sombra (hasta 0.8 del radio) es negro puro, y en la franja donde cae el arco del disco sobre la sombra (1.15 a 1.9 radios arriba), con el glow apagado, el percentil 90 de brillo es ≥ 120. Además lo revisa una persona con la captura. |
| AC02 | Un lado del disco es claramente más brillante que el otro. | Brillo medio del disco a la izquierda contra la derecha: razón ≥ 1.5. |
| AC03 | El disco gira sin saltos durante 60 s. | 60 s de capturas a ~5 por segundo: hay movimiento y ninguna diferencia entre cuadros seguidos pasa de 3 veces la mediana. |
| AC04 | Cambiar `lensing_strength` de 0 a 1 cambia la curvatura de forma obvia. | En la franja del arco, con el glow apagado: percentil 90 < 20 con lente 0 y ≥ 120 con lente 1; diferencia media entre las dos imágenes ≥ 8. |
| AC05 | Con `rotation_speed` en 0 el disco se detiene, y el glow y las estrellas siguen. | Dos capturas separadas 2 s: la zona del disco no cambia; la zona de estrellas sí (twinkle); el glow sigue presente. |
| AC06 | Cabe en el presupuesto de la sección 8. | Tiempo de GPU agregado (contadores de Windows) y cuadros saltados (WebSocket), en 64 y 32 pasos. |
| AC07 | Sin banding visible en los degradados. | Sin estrellas ni giro, en las zonas que cambian entre 0.05 y 0.3 niveles por pixel: fracción de pixeles vecinos con el mismo valor de 8 bits ≤ 0.45. Sin dithering da ~0.68 y con dithering ~0.27; la prueba se validó con una copia sin dithering, que falla. |
| AC08 | Sin bordes duros ni aliasing fuerte en el anillo y el borde de la sombra. | Se compara el anillo a 1080p contra una referencia renderizada a 4K y reducida: diferencia media en el anillo ≤ 6/255. |

Las del modo escena (1.2) usan una imagen de prueba: degradado con cuadros y un disco magenta en el centro, de un tercio del radio de la sombra, que el agujero tapa. El resto de la imagen nunca es magenta ni negro.

| Id | Criterio | Cómo se mide |
| --- | --- | --- |
| AC09 | Donde el lente no desvía, la escena sale idéntica (RF08). | Contra la misma imagen con el filtro apagado: sin lente y sin disco, diferencia máxima ≤ 2/255 fuera de 0.5 radios; con lente y `lens_reach` al mínimo, a más de 3 radios, percentil 99 ≤ 3 y media ≤ 0.5. Con el alcance por defecto se informa la media a más de 4.5 radios. |
| AC10 | La sombra es negro puro sobre la escena (RF09). | Sin disco, todo lo que está a menos de 0.8 radios es 0; con disco, la mitad de arriba (abajo pasa el disco por delante). |
| AC11 | El anillo de Einstein muestra lo que está detrás del agujero (RF09). | Sin disco: entre 1 y 2.5 radios, al menos 3 % de pixeles magenta; sin el filtro esa franja no tiene magenta, y con él no hay magenta a más de 4 radios. |
| AC12 | El agujero sigue a la posición (RF10). | Con `center_x` = 0.25 y `center_y` = 0.15, sin disco: la sombra en ese punto es 0 y el centro de la pantalla deja ver la escena (brillo medio > 20). |

## 11. Plan por fases

- **Fase 0:** esta spec, las pruebas y `tools/check.ps1` (fxc + paridad español/inglés).
- **Fase 1:** rayo, sombra, disco plano con radios, rotación y Doppler. Pasan AC02, AC03, AC05.
- **Fase 2:** anillo, glow, lente ajustable. Pasan AC01, AC04, AC08.
- **Fase 3:** estrellas, vetas, dithering, modo bajo. Pasan AC06, AC07.
- **Fase 4:** README con captura y tabla de parámetros, video corto de los sliders, registro en el dock y versión.

## 12. Riesgos

- **Rendimiento.** El rayo por pixel cuesta más que un lente falso. Se mitiga con paso proporcional a `r`, salida temprana cuando el rayo ya se aleja del disco y el modo de 32 pasos; AC06 lo vigila desde la fase 1.
- **Disco plano.** Si el ruido es muy regular, el disco se ve plano: dos escalas de ruido y brillo que cambia con el radio.
- **Doppler sutil.** Si se nota poco parece un error de iluminación: el defecto es 1.0, con `g³`.
- **Glow sobre la sombra.** Puede aplastar el anillo y ensuciar el negro: el glow se enmascara con la sombra.
- **Precisión del tiempo.** `elapsed_time` crece sin fin: la fase de giro debe seguir suave tras horas en vivo.

## Cambios en la versión 1.2

| Antes | Ahora | Por qué |
| --- | --- | --- |
| Solo cielo de estrellas; no usa la imagen de entrada | `background`: Estrellas o Escena | Poner el agujero sobre una escena y que la deforme. |
| Agujero siempre al centro | `center_x`, `center_y` | Para ponerlo donde haga falta o animarlo cruzando la escena. |
| Disco siempre visible | `show_disk` | Sin disco queda solo la distorsión del lente. |
| Atenuación del lente fija (0.5 radios) | `lens_reach` | Sobre una escena puede convenir un lente más amplio o más contenido. El defecto es el valor anterior: el modo estrellas no cambia. |
| AC01–AC08 | Más AC09–AC12 | Lo nuevo se prueba igual que lo demás; AC01–AC08 siguen pasando con los valores por defecto. |

## Cambios respecto a la versión 1.0

| Antes | Ahora | Por qué |
| --- | --- | --- |
| MVP con lente falso (desplazar el UV con 1/r); trazado de rayos solo en V2 | Rayo doblado por pixel desde el MVP | Desplazar el UV curva la imagen pero no crea la segunda imagen del disco, la que pasa por encima del agujero, y AC01 la exige. El cálculo da unos 3–5 ms a 64 pasos en una 1650 Ti. |
| `resolution_scale` | Quitado | Un shader de un solo paso corre una vez por pixel de salida: bajar la escala solo pixela, no ahorra GPU. Lo que sí ahorra es una fuente más chica escalada (sección 8). |
| Doppler `1 + s·cos(ángulo)` | `g³` con `g = √(1-β²)/(1-β·n)` | La fórmula anterior da brillo negativo con intensidad mayor que 1. |
| 60 fps en la 1650 Ti | Milisegundos de GPU agregados por cuadro, sin más cuadros saltados | OBS corre a 30 fps en esta máquina; el tiempo de GPU sí se puede medir, con los contadores de Windows. |
| — | `inclination` | El ángulo de la cámara define el look y no tenía control. |
| Nombre "Gargantua - Interstellar Black Hole" | "Gargantúa — agujero negro" | Sin el título de la película en el nombre del filtro. |
| Comentarios en español e inglés en el mismo archivo | Un archivo por idioma | Es la convención del repo y lo verifica `check.ps1`. |
| AC01 "a 2 metros" | Prueba automática + revisión humana | Un criterio que solo juzga una persona no se puede automatizar. |
