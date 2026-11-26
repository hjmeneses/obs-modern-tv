"""Write en/gargantua.shader from gargantua.shader, translating only comments and labels.

Usage: python tools/make_en.py   (then pwsh tools/check.ps1 to confirm both have the same code)
Every Spanish comment or label must be in `pairs`; if one is missing the script stops and says which.
"""
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
src = root / "gargantua.shader"
dst = root / "en" / "gargantua.shader"
t = src.read_text(encoding="utf-8")

header_es, rest = t.split("uniform int background<", 1)
header_en = """// Gargantua: a black hole with an accretion disk, procedural and real time.
// Inspired by the black hole in the film Interstellar (2014).
// For OBS Studio (obs-shaderfilter plugin): Filters → + → User-defined shader → Load shader text
// from file. With Background = Stars, add it to a black color source (it ignores the input image);
// with Background = Scene, add it to a scene or group and the lensing warps the image.
//
// How it works (details in docs/gargantua-spec.md):
//   - One ray per pixel leaves the camera and bends step by step with the acceleration of a photon
//     around a Schwarzschild black hole (Schwarzschild radius = 1).
//   - Each time the ray crosses the disk plane it adds the disk's color; that is why the far side
//     of the disk shows above and below the black hole.
//   - The shadow and the ring are decided from the ray's impact parameter, which is known exactly,
//     so the edge stays smooth whatever the number of steps.
//   - Doppler: the side of the disk moving towards you is brighter (g^3) and whiter.
//   - Everything is computed in linear; exposure, tone mapping, sRGB and dithering go last. The scene
//     skips the tone mapping: where there is no light from the black hole it comes out unchanged.

"""
t = header_en + "uniform int background<" + rest

pairs = [
    ('"Fondo"', '"Background"'),
    ('"Estrellas"', '"Stars"'),
    ('"Escena (la deforma el lente)"', '"Scene (warped by the lensing)"'),
    ('"Posicion X (0 = centro)"', '"Position X (0 = center)"'),
    ('"Posicion Y (0 = centro)"', '"Position Y (0 = center)"'),
    ('"Mostrar disco"', '"Show disk"'),
    ('"Radio del agujero"', '"Black hole radius"'),
    ('"Disco: radio interior (x radio del agujero)"', '"Disk: inner radius (x black hole radius)"'),
    ('"Disco: radio exterior (x radio del agujero)"', '"Disk: outer radius (x black hole radius)"'),
    ('"Disco: grosor (opacidad)"', '"Disk: thickness (opacity)"'),
    ('"Inclinacion de la camara (grados)"', '"Camera inclination (degrees)"'),
    ('"Velocidad de giro"', '"Rotation speed"'),
    ('"Doppler"', '"Doppler"'),
    ('"Lente gravitacional"', '"Gravitational lensing"'),
    ('"Alcance del lente"', '"Lensing reach"'),
    ('"Brillo del disco"', '"Disk brightness"'),
    ('"Glow"', '"Glow"'),
    ('"Densidad de estrellas"', '"Star density"'),
    ('"Exposicion"', '"Exposure"'),
    ('"Calidad (pasos del rayo)"', '"Quality (ray steps)"'),
    ('"32 (bajo)"', '"32 (low)"'),
    ('"64 (normal)"', '"64 (normal)"'),
    ('"128 (alto: puede bajar los fps en gama baja)"', '"128 (high: may lower fps on low-end GPUs)"'),
    ("// Radio de la sombra con el lente en 1: 3·sqrt(3)/2 radios de Schwarzschild",
     "// Shadow radius with lensing at 1: 3·sqrt(3)/2 Schwarzschild radii"),
    ("// Distancia de la camara al agujero, en radios de Schwarzschild",
     "// Camera distance to the black hole, in Schwarzschild radii"),
    ("// Hashes de Dave Hoskins: estables con numeros grandes (no usan sin)",
     "// Dave Hoskins' hashes: stable with large numbers (no sin)"),
    ("// Value noise periodico en x (period celdas): el angulo del disco da la vuelta sin costura",
     "// Value noise, periodic in x (period cells): the disk angle wraps around without a seam"),
    ("// Paleta de la spec, en lineal: 0 = rojo oscuro, 1 = casi blanco",
     "// The spec's palette, in linear: 0 = dark red, 1 = almost white"),
    ("// Factor Doppler g del disco en pos para un rayo con direccion dir (de la camara hacia el disco).",
     "// Doppler factor g of the disk at pos for a ray with direction dir (from the camera to the disk)."),
    ("// La velocidad orbital es la de Kepler vista por un observador quieto: sqrt(0.5 / (r - 1)).",
     "// The orbital speed is Kepler's as seen by a static observer: sqrt(0.5 / (r - 1))."),
    ("// Temperatura relativa del disco: 1 en el borde interior, baja hacia afuera",
     "// Relative disk temperature: 1 at the inner edge, lower outwards"),
    ("// Densidad radial: entra suave en el borde interior y se desvanece hacia el exterior",
     "// Radial density: soft at the inner edge, fading out towards the outer edge"),
    ("// Estrellas en la direccion d: dos capas de rejilla sobre la esfera, con twinkle.",
     "// Stars in direction d: two grid layers on the sphere, with twinkle."),
    ("// pa = tamaño angular de un pixel, para que las estrellas no se pierdan ni hagan aliasing.",
     "// pa = angular size of a pixel, so stars neither vanish nor alias."),
    ("// Deriva lenta, como si la camara orbitara: el leve parallax",
     "// Slow drift, as if the camera were orbiting: the slight parallax"),
    ("// Tone mapping filmico (aproximacion de ACES de Narkowicz): los brillos fuertes se van a blanco",
     "// Filmic tone mapping (Narkowicz's ACES approximation): strong highlights go to white"),
    ("// Pantalla centrada en el agujero, escalada por el lado corto, y hacia arriba",
     "// Screen centered on the black hole, scaled by the short side, y up"),
    ("// ---- Camara -----------------------------------------------------------------------------",
     "// ---- Camera -----------------------------------------------------------------------------"),
    ("// Escala para que la sombra mida black_hole_radius con el lente en 1",
     "// Scale so the shadow measures black_hole_radius with lensing at 1"),
    ("// ---- Lo que se sabe sin trazar: parametro de impacto, sombra y anillo -----------------------",
     "// ---- What is known without tracing: impact parameter, shadow and ring ----------------------"),
    ("// horizonte (con un minimo si no hay lente)", "// horizon (with a minimum when there is no lensing)"),
    ("// borde de la sombra", "// shadow edge"),
    ("// parametro de impacto del rayo", "// the ray's impact parameter"),
    ("// cuanto cambia b en un pixel", "// how much b changes in one pixel"),
    ("// ---- Trazado -------------------------------------------------------------------------------",
     "// ---- Tracing -------------------------------------------------------------------------------"),
    ("            // Ya se aleja y no cruza mas el disco. Lo que le falta por doblarse hasta el infinito\n"
     "            // se suma de una vez (integral exacta de la misma aceleracion en linea recta); si no,\n"
     "            // cada rayo se cortaria en un paso distinto y las estrellas saldrian en escalones.",
     "            // Moving away and past the disk. The bending left until infinity is added at once\n"
     "            // (exact integral of the same acceleration along a straight line); otherwise each ray\n"
     "            // would stop at a different step and the stars would come out in steps."),
    ("// Punto medio (RK2): con Euler el error de cada paso movia las estrellas decenas de pixeles",
     "// Midpoint (RK2): with Euler each step's error moved the stars by tens of pixels"),
    ("// Neblina del disco (glow): luz cerca del plano, sin ruido para que sea barata",
     "// Disk haze (glow): light near the plane, without noise so it stays cheap"),
    ("// ¿Cruza el plano del disco en este paso?", "// Does it cross the disk plane in this step?"),
    ("                // Dos capas que giran rigidas a velocidades distintas: parece rotacion diferencial\n"
     "                // sin que las vetas se estiren sin fin",
     "                // Two layers spinning rigidly at different speeds: it reads as differential\n"
     "                // rotation without the streaks stretching forever"),
    ("// ---- Fondo, anillo y glow ------------------------------------------------------------------",
     "// ---- Background, ring and glow -------------------------------------------------------------"),
    ("    // Las estrellas estan en el infinito: con la camara tan cerca, el lente completo estiraria todo\n"
     "    // el cielo en arcos. Se aplica completo junto a la sombra (anillo de Einstein) y se atenua\n"
     "    // hacia afuera. Es una decision artistica (spec, seccion 7).",
     "    // Stars are at infinity: with the camera this close, full lensing would stretch the whole sky\n"
     "    // into arcs. It applies fully next to the shadow (Einstein ring) and fades outwards. This is\n"
     "    // an artistic choice (spec, section 7)."),
    ("// cuanto del fondo se ve", "// how much of the background shows"),
    ("    // Escena: la direccion final del rayo se vuelve a pasar a la pantalla (la inversa de la camara)\n"
     "    // y ahi se lee la imagen. Se suma el desplazamiento al uv del pixel en lugar de usar el punto\n"
     "    // reconstruido, asi donde el rayo no se desvia la escena sale identica.",
     "    // Scene: the ray's final direction is mapped back to the screen (the camera's inverse) and the\n"
     "    // image is read there. The offset is added to the pixel's uv instead of using the rebuilt\n"
     "    // point, so wherever the ray is not deflected the scene comes out identical."),
    ("    // Lo que cae fuera del cuadro lee la escena en espejo: sin costuras, y junto al anillo salen\n"
     "    // copias cada vez mas comprimidas, como en un lente fuerte",
     "    // Whatever falls outside the frame reads the scene mirrored: no seams, and next to the ring\n"
     "    // ever more squeezed copies show up, as with a strong lens"),
    ("    // Junto a la sombra el rayo se dobla cientos de grados: sirve para el cielo, pero la escena es un\n"
     "    // rectangulo chico. El desvio se satura suave en ~3 veces el tamano angular de la sombra; lejos\n"
     "    // no cambia nada y junto a la sombra queda la imagen secundaria (la escena del otro lado,\n"
     "    // invertida), continua y sin comprimirse sin fin.",
     "    // Next to the shadow the ray bends by hundreds of degrees: fine for the sky, but the scene is a\n"
     "    // small rectangle. The deflection saturates smoothly at ~3 times the shadow's angular size;\n"
     "    // far away nothing changes, and next to the shadow the secondary image remains (the scene from\n"
     "    // the other side, inverted), continuous and without endless squeezing."),
    ("    // El desvio sale de la formula de Schwarzschild a segundo orden (2/b + 15·pi/16/b^2), no del\n"
     "    // trazado: en este rango es casi igual y es suave, sin los escalones del trazado que en la escena\n"
     "    // se ven como lineas. Siempre es hacia el agujero, en el plano de la camara.",
     "    // The deflection comes from Schwarzschild's second-order formula (2/b + 15·pi/16/b^2), not from\n"
     "    // the tracing: in this range it is almost the same and it is smooth, without the tracing's small\n"
     "    // steps that show as lines on the scene. It always points to the black hole, in the camera's plane."),
    ("// Con tope: en los escalones del trazado la derivada se dispara y traeria colores de lejos",
     "// Capped: at the tracing's small steps the derivative shoots up and would bring far colors"),
    ("// Coordenadas de textura en espejo: 0..1, 1..2 al reves, 2..3 al derecho... Sin pasar del centro\n"
     "// de los pixeles de la orilla: el muestreo bilineal ahi mezclaria el borde negro de la textura.",
     "// Mirrored texture coordinates: 0..1, 1..2 reversed, 2..3 forward again... Never past the center\n"
     "// of the edge pixels: bilinear sampling there would mix in the texture's black border."),
    ("    // Donde el lente comprime la escena, varias lecturas en el area del pixel evitan el parpadeo;\n"
     "    // donde no la comprime las cuatro caen en el mismo punto",
     "    // Where the lensing squeezes the scene, several reads over the pixel's area avoid flicker;\n"
     "    // where it does not, all four land on the same point"),
    ("// +1 a la izquierda (se acerca)", "// +1 on the left (approaching)"),
    ("    // Anillo de fotones: es la luz del mismo disco que dio vueltas al agujero, asi que hereda su\n"
     "    // Doppler, su color y sus vetas. Pegado al borde de la sombra y cayendo hacia afuera; hacia\n"
     "    // adentro corta con el mismo borde suave de la sombra.",
     "    // Photon ring: it is light from the disk itself that went around the black hole, so it takes\n"
     "    // the disk's Doppler, color and streaks. It hugs the shadow edge and fades outwards; inwards\n"
     "    // it stops at the same soft shadow edge."),
    ("// velocidad del borde interior del disco", "// speed of the disk's inner edge"),
    ("// sin disco no hay anillo ni halo", "// no disk, no ring or halo"),
    ("// La imagen de una vuelta menos: una linea mas tenue un poco hacia afuera",
     "// The image with one turn less: a fainter line a little further out"),
    ("// ---- Salida ----------------------------------------------------------------------------------",
     "// ---- Output ----------------------------------------------------------------------------------"),
    ("    // Dithering triangular contra el banding, solo donde hay luz del agujero: el centro queda negro\n"
     "    // puro y la escena sin tocar",
     "    // Triangular dithering against banding, only where there is light from the black hole: the\n"
     "    // center stays pure black and the scene untouched"),
    ("// La escena se suma en lineal, sin exposicion ni tone mapping",
     "// The scene is added in linear, without exposure or tone mapping"),
]
for a, b in pairs:
    if a not in t:
        sys.exit("not found: " + a[:70])
    t = t.replace(a, b)

# Anything Spanish left over?
for word in ("camara", "agujero", "radio ", "brillo", " del ", "sombra", "pixel", "estrell", "escena", "fondo"):
    for n, line in enumerate(t.splitlines(), 1):
        if "//" in line and word in line.split("//", 1)[1].lower() or ('"' in line and word in line.lower() and "label" in line):
            print(f"check line {n}: {line.strip()[:100]}")
dst.write_text(t, encoding="utf-8", newline="\n")
print("ok")
