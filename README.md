# obs-modern-tv

*Modern TV effects for OBS: digital glitches, and more to come.*

Shaders para **OBS Studio** con efectos de la televisión y el streaming de hoy: señal digital que se rompe, compresión dañada, cortes de transmisión…

Es la colección hermana de [obs-retro-tv](https://github.com/hjmeneses/obs-retro-tv), que va de los efectos de los 60.

*[English below](#english)*

## Requisitos

- OBS Studio
- Plugin [obs-shaderfilter](https://github.com/exeldro/obs-shaderfilter)

## Shaders

| Archivo | Qué hace |
|---|---|
| `glitch.shader` | La escena se rompe sola, como si hackearan el stream: glitches pequeños cada 10–30 s y uno completo cada 30–60 s, en momentos al azar. |
| `trazo-de-luz.shader` | Una línea de luz con núcleo blanco y resplandor recorre el contorno de un texto o logo, al estilo de los plugins de "sable de luz". |

## Instalación

1. Descarga los archivos `.shader` (o clona el repo).
2. En OBS, clic derecho sobre la escena o fuente → **Filtros** → **+** → **User-defined shader**.
3. Activa **Load shader text from file** y elige el archivo `.shader`.
4. Ajusta los parámetros.

## Glitch digital (`glitch.shader`)

![Escena limpia, glitch pequeño, limpia otra vez y glitch completo](images/glitch.gif)

<sub>Simulación aproximada del shader en una escena de ejemplo: un glitch pequeño y luego uno completo. En vivo salen al azar cada 10–30 s y cada 30–60 s. / Approximate simulation: a small glitch, then a full one.</sub>

Aplícalo a la **escena** completa (o a una fuente, si solo quieres que falle esa).

| Tipo | Cada cuánto | Qué pasa |
|---|---|---|
| Pequeño | 10–30 s, al azar | Dos o tres tirones: franjas horizontales corridas, separación RGB, algún bloque fuera de lugar |
| Completo | 30–60 s, al azar | Toda la escena se desarma: saltos verticales, pixelado, bloques con colores dañados, líneas de ruido, apagones y destellos. Luego se recupera |

La separación entre dos glitches seguidos siempre queda dentro del rango, aunque lleves horas en vivo. El primero de cada tipo puede llegar antes, porque se cuenta desde que se activa el filtro. Si un pequeño cae durante el completo, manda el completo. Fuera de los glitches la imagen pasa tal cual.

| Parámetro | Efecto |
|---|---|
| Modo | *Normal (al azar)*, o *Probar glitch pequeño / completo* en bucle para ajustarlo sin esperar |
| Glitches pequeños / Glitch completo | Enciende o apaga cada tipo |
| Mínimo / Máximo entre glitches | El rango de segundos entre un glitch y el siguiente |
| Duración / Intensidad | Cuánto dura cada glitch y qué tan fuerte es |
| Separación RGB | Qué tanto se separan los canales de color |
| Tamaño de los bloques | Tamaño de los bloques de compresión dañada |
| Cambios por segundo del glitch | Qué tan "a saltos" se mueve el glitch |
| Semilla | Cambia el patrón de tiempos. Usa una distinta en cada escena para que no fallen todas a la vez |

El conteo empieza cuando se activa el filtro: al recargar el shader o reiniciar OBS empieza de cero.

## Trazo de luz (`trazo-de-luz.shader`)

![Trazo de luz: el contorno se enciende con la fuente oculta, la fuente aparece detrás de la luz, y modo eléctrico](images/trazo-de-luz.png)

<sub>Capturas del shader en OBS: barrido con la fuente oculta, barrido con la fuente apareciendo detrás de la luz, y modo eléctrico. / Captures from OBS: sweep with the source hidden, sweep revealing the source, electric mode.</sub>

Aplícalo a una **fuente de texto, logo o imagen con transparencia**. Como el resplandor sale de la fuente, dale margen con *Expand Left/Right/Top/Bottom* en las opciones del filtro.

Es una secuencia (Progreso de 0 a 100, o en bucle). La luz recorre el contorno durante el 0–70, el contorno queda encendido hasta el 80 y luego se apaga.

| Parámetro | Efecto |
|---|---|
| Modo | *Barrido*: la luz cruza en línea recta. *Giro*: la luz le da la vuelta al título por fuera, como en una pista (por arriba, baja por un extremo, regresa por abajo), con el contorno ya encendido tenue. *Eléctrico*: tramos que se encienden y apagan al azar. *Radar*: una vuelta con velocidad angular constante (en un título ancho se demora en el centro y vuela en los extremos) |
| Dirección | Ángulo del barrido (0 = de izquierda a derecha, 90 = de arriba abajo) o punto de arranque del giro o del radar |
| Fuente | Aparece detrás del trazo, siempre visible u oculta (solo el trazo) |
| Contorno de | Transparencia, o brillo para logos sobre fondo negro |
| Color del núcleo / del resplandor | El centro de la línea y el halo |
| Grosor, alcance e intensidad | Ancho del núcleo, hasta dónde llega el resplandor y qué tan fuerte es |
| Largo de la estela / Brillo que queda | Cuánto dura la cola de luz y cuánto brilla el contorno después |
| Temblor, velocidad de la energía, parpadeo | El temblor del trazo, como de electricidad o fuego |

Con [obs-shader-dock](https://github.com/hjmeneses/obs-shader-dock) lo disparas con ▶ desde el dock.

---

## English

Shaders for **OBS Studio** with today's TV and streaming effects: broken digital signal, damaged compression, dropouts… Sister collection of [obs-retro-tv](https://github.com/hjmeneses/obs-retro-tv).

### Requirements

- OBS Studio
- [obs-shaderfilter](https://github.com/exeldro/obs-shaderfilter) plugin

### Shaders

| File | What it does |
|---|---|
| `en/glitch.shader` | Your scene glitches on its own, as if the stream were being hacked: small glitches every 10–30 s and a full-scene glitch every 30–60 s, at random times. |
| `en/light-trace.shader` | A line of light with a white core and a coloured glow runs along the outline of a text or logo, in the style of "light saber" plugins. |

The English versions, with English labels and comments, are in the [`en/`](en) folder; the Spanish originals are in the root.

**Light trace**: apply it to a text, logo or image with transparency, and give the glow room with the filter's *Expand* options. It is a sequence (Progress 0–100, or loop): the light runs along the outline over 0–70, the outline stays lit until 80, then fades. Modes: *Sweep* (straight line), *Spin* (the light runs around the outside of the title like on a track, over a dimly lit outline), *Electric* (random flickering stretches) and *Radar* (once around at a constant angular speed). The source can appear behind the light, stay visible, or be hidden.

Add it to a scene with **Filters → + → User-defined shader → Load shader text from file**. Set *Mode* to one of the *Test* options to loop a glitch while you tune it. The gap between two glitches always stays within the configured range, however long you are live. Use a different *Seed* on each scene so they don't all glitch together.

## License

MIT
