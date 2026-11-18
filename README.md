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

## Instalación

1. Descarga los archivos `.shader` (o clona el repo).
2. En OBS, clic derecho sobre la escena o fuente → **Filtros** → **+** → **User-defined shader**.
3. Activa **Load shader text from file** y elige el archivo `.shader`.
4. Ajusta los parámetros.

## Glitch digital (`glitch.shader`)

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

---

## English

Shaders for **OBS Studio** with today's TV and streaming effects: broken digital signal, damaged compression, dropouts… Sister collection of [obs-retro-tv](https://github.com/hjmeneses/obs-retro-tv).

### Requirements

- OBS Studio
- [obs-shaderfilter](https://github.com/exeldro/obs-shaderfilter) plugin

### Shaders

| File | What it does |
|---|---|
| `glitch.shader` | Your scene glitches on its own, as if the stream were being hacked: small glitches every 10–30 s and a full-scene glitch every 30–60 s, at random times. |

Add it to a scene with **Filters → + → User-defined shader → Load shader text from file**. Parameter labels are in Spanish. Set *Modo* to one of the *Probar* options to loop a glitch while you tune it. The gap between two glitches always stays within the configured range, however long you are live. Use a different *Semilla* (seed) on each scene so they don't all glitch together.

## License

MIT
