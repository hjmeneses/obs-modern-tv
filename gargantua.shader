// Gargantua: agujero negro con disco de acrecion, procedural y en tiempo real.
// Inspirado en el agujero negro de la pelicula Interstellar (2014).
// Para OBS Studio (plugin obs-shaderfilter): ponlo como filtro en una fuente de color negra (o una
// escena vacia) → Filtros → + → User-defined shader → Load shader text from file. No usa la imagen
// de entrada.
//
// Como funciona (detalle en docs/gargantua-spec.md):
//   - Un rayo por pixel sale de la camara y se dobla paso a paso con la aceleracion de un foton
//     alrededor de un agujero de Schwarzschild (radio de Schwarzschild = 1).
//   - Cada vez que el rayo cruza el plano del disco suma su color; por eso se ve la parte de atras
//     del disco por encima y por debajo del agujero.
//   - La sombra y el anillo se deciden con el parametro de impacto del rayo, que se conoce de forma
//     exacta, asi el borde sale suave sin importar los pasos.
//   - Doppler: el lado del disco que se acerca brilla mas (g^3) y se ve mas blanco.
//   - Todo se calcula en lineal; al final van exposicion, tone mapping, sRGB y dithering.

uniform float black_hole_radius<
    string label = "Radio del agujero";
    string widget_type = "slider";
    float minimum = 0.15; float maximum = 0.35; float step = 0.005;
> = 0.22;

uniform float disk_inner_radius<
    string label = "Disco: radio interior (x radio del agujero)";
    string widget_type = "slider";
    float minimum = 1.0; float maximum = 1.5; float step = 0.01;
> = 1.15;

uniform float disk_outer_radius<
    string label = "Disco: radio exterior (x radio del agujero)";
    string widget_type = "slider";
    float minimum = 2.0; float maximum = 3.5; float step = 0.05;
> = 2.8;

uniform float disk_thickness<
    string label = "Disco: grosor (opacidad)";
    string widget_type = "slider";
    float minimum = 0.05; float maximum = 0.30; float step = 0.01;
> = 0.12;

uniform float inclination<
    string label = "Inclinacion de la camara (grados)";
    string widget_type = "slider";
    float minimum = 2.0; float maximum = 30.0; float step = 0.5;
> = 8.0;

uniform float rotation_speed<
    string label = "Velocidad de giro";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.35;

uniform float doppler_strength<
    string label = "Doppler";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 2.0; float step = 0.05;
> = 1.0;

uniform float lensing_strength<
    string label = "Lente gravitacional";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 2.0; float step = 0.05;
> = 1.0;

uniform float disk_brightness<
    string label = "Brillo del disco";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 3.0; float step = 0.05;
> = 1.2;

uniform float glow_intensity<
    string label = "Glow";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 2.0; float step = 0.05;
> = 0.8;

uniform float star_density<
    string label = "Densidad de estrellas";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.5;

uniform float exposure<
    string label = "Exposicion";
    string widget_type = "slider";
    float minimum = 0.5; float maximum = 2.0; float step = 0.05;
> = 1.0;

uniform int quality_steps<
    string label = "Calidad (pasos del rayo)";
    string widget_type = "select";
    int    option_0_value = 32;
    string option_0_label = "32 (bajo)";
    int    option_1_value = 64;
    string option_1_label = "64 (normal)";
    int    option_2_value = 128;
    string option_2_label = "128 (alto: puede bajar los fps en gama baja)";
> = 64;

#define PI 3.14159265
#define TAU 6.28318531
// Radio de la sombra con el lente en 1: 3·sqrt(3)/2 radios de Schwarzschild
#define SHADOW_B 2.59807621
// Distancia de la camara al agujero, en radios de Schwarzschild
#define CAM_DIST 40.0

// Hashes de Dave Hoskins: estables con numeros grandes (no usan sin)
float hash12(float2 p)
{
    float3 p3 = p.xyx * 0.1031;
    p3 = p3 - floor(p3);
    p3 += dot(p3, p3.yzx + 33.33);
    float h = (p3.x + p3.y) * p3.z;
    return h - floor(h);
}

float3 hash32(float2 p)
{
    float3 p3 = p.xyx * float3(0.1031, 0.1030, 0.0973);
    p3 = p3 - floor(p3);
    p3 += dot(p3, p3.yxz + 33.33);
    float3 h = (p3.xxy + p3.yzz) * p3.zyx;
    return h - floor(h);
}

// Value noise periodico en x (period celdas): el angulo del disco da la vuelta sin costura
float vnoise(float2 x, float period)
{
    float2 i = floor(x);
    float2 f = x - i;
    float2 u = f * f * (3.0 - 2.0 * f);
    float i0 = i.x - period * floor(i.x / period);
    float i1 = i0 + 1.0;
    i1 = i1 - period * floor(i1 / period);
    float a = hash12(float2(i0, i.y));
    float b = hash12(float2(i1, i.y));
    float c = hash12(float2(i0, i.y + 1.0));
    float d = hash12(float2(i1, i.y + 1.0));
    return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}

// Paleta de la spec, en lineal: 0 = rojo oscuro, 1 = casi blanco
float3 diskRamp(float x)
{
    float3 c0 = pow(float3(122.0, 46.0, 13.0) / 255.0, 2.2);
    float3 c1 = pow(float3(193.0, 68.0, 14.0) / 255.0, 2.2);
    float3 c2 = pow(float3(255.0, 158.0, 44.0) / 255.0, 2.2);
    float3 c3 = pow(float3(255.0, 233.0, 168.0) / 255.0, 2.2);
    float3 c4 = pow(float3(255.0, 246.0, 216.0) / 255.0, 2.2);
    x = saturate(x) * 4.0;
    if (x < 1.0)
        return lerp(c0, c1, x);
    if (x < 2.0)
        return lerp(c1, c2, x - 1.0);
    if (x < 3.0)
        return lerp(c2, c3, x - 2.0);
    return lerp(c3, c4, x - 3.0);
}

// Factor Doppler g del disco en pos para un rayo con direccion dir (de la camara hacia el disco).
// La velocidad orbital es la de Kepler vista por un observador quieto: sqrt(0.5 / (r - 1)).
float dopplerG(float3 pos, float3 dir, float r)
{
    float beta = min(sqrt(0.5 / max(r - 1.0, 0.5)) * doppler_strength, 0.9);
    float3 tang = normalize(float3(-pos.z, 0.0, pos.x));
    return sqrt(1.0 - beta * beta) / (1.0 - beta * dot(tang, -dir));
}

// Temperatura relativa del disco: 1 en el borde interior, baja hacia afuera
float diskHeat(float r, float rin)
{
    return pow(rin / r, 1.6) * sqrt(saturate((r - rin * 0.98) / (rin * 0.12)));
}

// Densidad radial: entra suave en el borde interior y se desvanece hacia el exterior
float diskDensity(float r, float rin, float rout)
{
    return smoothstep(rin * 0.98, rin * 1.06, r) * (1.0 - smoothstep(rout * 0.6, rout, r));
}

// Estrellas en la direccion d: dos capas de rejilla sobre la esfera, con twinkle.
// pa = tamaño angular de un pixel, para que las estrellas no se pierdan ni hagan aliasing.
float3 starField(float3 d, float t, float pa)
{
    // Deriva lenta, como si la camara orbitara: el leve parallax
    float a = t * 0.004;
    float ca = cos(a);
    float sa = sin(a);
    d = float3(ca * d.x - sa * d.z, d.y, sa * d.x + ca * d.z);
    float2 sph = float2(atan2(d.x, d.z), asin(clamp(d.y, -1.0, 1.0)));
    float sigma = max(pa * 0.7, 1e-5);
    float total = 0.0;
    for (int layer = 0; layer < 2; layer++) {
        float cell = layer == 0 ? 0.012 : 0.0045;
        float2 g = sph / cell;
        float2 id = floor(g);
        float3 h = hash32(id + float(layer) * 113.0);
        float chance = star_density * (layer == 0 ? 0.35 : 0.5);
        if (h.x < chance) {
            float2 c = (id + 0.2 + 0.6 * h.yz) * cell;
            float2 dd = (sph - c) * float2(cos(sph.y), 1.0);
            float bright = layer == 0 ? 0.15 + 0.85 * pow(h.y, 4.0) : 0.05 + 0.15 * h.z;
            float tw = 0.75 + 0.25 * sin(t * (1.3 + 3.0 * h.z) + TAU * h.y);
            total += bright * tw * exp(-dot(dd, dd) / (2.0 * sigma * sigma));
        }
    }
    return float3(total, total, total) * 0.8;
}

// Tone mapping filmico (aproximacion de ACES de Narkowicz): los brillos fuertes se van a blanco
float3 filmic(float3 x)
{
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

float4 mainImage(VertData v_in) : TARGET
{
    float t = elapsed_time;
    float minDim = min(uv_size.x, uv_size.y);
    // Pantalla centrada, escalada por el lado corto, y hacia arriba
    float2 p = float2(v_in.uv.x - 0.5, 0.5 - v_in.uv.y) * uv_size / minDim;

    // ---- Camara -----------------------------------------------------------------------------
    float inc = radians(inclination);
    float3 cam = CAM_DIST * float3(0.0, sin(inc), -cos(inc));
    float3 fwd = -normalize(cam);
    float3 right = float3(1.0, 0.0, 0.0);
    float3 up = cross(fwd, right);
    // Escala para que la sombra mida black_hole_radius con el lente en 1
    float k = tan(asin(SHADOW_B / CAM_DIST)) / black_hole_radius;
    float3 dir = normalize(fwd + k * (p.x * right + p.y * up));
    float3 dir0 = dir;
    float3 pos = cam;

    // ---- Lo que se sabe sin trazar: parametro de impacto, sombra y anillo -----------------------
    float lens = lensing_strength;
    float rcap = max(lens, 0.5);                            // horizonte (con un minimo si no hay lente)
    float bc = max(SHADOW_B * lens, rcap);                   // borde de la sombra
    float b = CAM_DIST * sin(atan(k * length(p)));           // parametro de impacto del rayo
    float pxb = CAM_DIST * k / minDim;                       // cuanto cambia b en un pixel
    float shadow = 1.0 - smoothstep(bc - 0.75 * pxb, bc + 0.75 * pxb, b);
    float3 hv = cross(pos, dir);
    float h2 = dot(hv, hv);

    float rin = disk_inner_radius * SHADOW_B;
    float rout = disk_outer_radius * SHADOW_B;
    float stepK = 8.0 / float(max(quality_steps, 8));

    // ---- Trazado -------------------------------------------------------------------------------
    float3 disk = float3(0.0, 0.0, 0.0);
    float3 haze = float3(0.0, 0.0, 0.0);
    float trans = 1.0;
    float rotA = t * rotation_speed;
    for (int i = 0; i < quality_steps; i++) {
        float r2 = dot(pos, pos);
        float r = sqrt(r2);
        if (r < rcap || trans < 0.01)
            break;
        if (dot(pos, dir) > 0.0 && r > rout * 1.2) {
            // Ya se aleja y no cruza mas el disco. Lo que le falta por doblarse hasta el infinito
            // se suma de una vez (integral exacta de la misma aceleracion en linea recta); si no,
            // cada rayo se cortaria en un paso distinto y las estrellas saldrian en escalones.
            float bb = sqrt(h2);
            float s = dot(pos, dir);
            float q = bb * bb + s * s;
            float rest = lens / bb * (1.0 - s * (2.0 * s * s + 3.0 * bb * bb) / (2.0 * q * sqrt(q)));
            float3 toward = normalize(dir * s - pos);
            dir = normalize(dir + toward * rest);
            break;
        }
        float ds = clamp(stepK * r, 0.02, 10.0);
        // Punto medio (RK2): con Euler el error de cada paso movia las estrellas decenas de pixeles
        float3 mid = pos + dir * (0.5 * ds);
        float rm2 = dot(mid, mid);
        float3 acc = -1.5 * lens * h2 * mid / (rm2 * rm2 * sqrt(rm2));
        float3 ndir = normalize(dir + acc * ds);
        float3 npos = pos + (dir + ndir) * (0.5 * ds);

        // Neblina del disco (glow): luz cerca del plano, sin ruido para que sea barata
        float rp = length(pos.xz);
        if (abs(pos.y) < 1.0 && rp > rin * 0.9 && rp < rout * 1.15) {
            float gH = dopplerG(pos, ndir, max(rp, 1.01));
            float heat = diskHeat(max(rp, rin), rin);
            float dens = diskDensity(rp, rin * 0.92, rout * 1.1);
            haze += diskRamp(heat * gH) * (heat * gH * gH * gH) * dens * exp(-abs(pos.y) * 4.0) * ds * trans * 0.02;
        }

        // ¿Cruza el plano del disco en este paso?
        if (pos.y * npos.y < 0.0) {
            float f = pos.y / (pos.y - npos.y);
            float3 hit = lerp(pos, npos, f);
            float rh = length(hit.xz);
            if (rh > rin * 0.95 && rh < rout) {
                float dens = diskDensity(rh, rin, rout);
                float phi = atan2(hit.z, hit.x);
                // Dos capas que giran rigidas a velocidades distintas: parece rotacion diferencial
                // sin que las vetas se estiren sin fin
                float na = vnoise(float2((phi - rotA) * 24.0 / TAU, rh * 5.0), 24.0);
                float nb = vnoise(float2((phi - rotA * 0.62) * 48.0 / TAU, rh * 11.0), 48.0);
                float n = 0.65 * na + 0.35 * nb;
                float g = dopplerG(hit, ndir, rh);
                float heat = diskHeat(rh, rin);
                float3 emit = diskRamp(heat * g) * disk_brightness * (0.25 + 1.5 * heat) * (g * g * g) * (0.45 + 0.9 * n);
                float tau = disk_thickness * 7.0 * dens * (0.6 + 0.8 * n) / max(abs(ndir.y), 0.04);
                float alpha = min(1.0 - exp(-tau), 0.97);
                disk += trans * alpha * emit;
                trans *= 1.0 - alpha;
            }
        }
        pos = npos;
        dir = ndir;
    }

    // ---- Fondo, anillo y glow ------------------------------------------------------------------
    float3 col = disk;
    float pa = k / minDim;
    // Las estrellas estan en el infinito: con la camara tan cerca, el lente completo estiraria todo
    // el cielo en arcos. Se aplica completo junto a la sombra (anillo de Einstein) y se atenua
    // hacia afuera. Es una decision artistica (spec, seccion 7).
    float wl = exp(-max(b - 1.25 * bc, 0.0) / (0.5 * max(bc, 0.5)));
    float3 sdir = normalize(lerp(dir0, dir, wl));
    col += trans * (1.0 - shadow) * starField(sdir, t, pa);

    // Anillo de fotones: es la luz del mismo disco que dio vueltas al agujero, asi que hereda su
    // Doppler, su color y sus vetas. Pegado al borde de la sombra y cayendo hacia afuera; hacia
    // adentro corta con el mismo borde suave de la sombra.
    float lenP = length(p);
    float cosA = lenP > 1e-4 ? -p.x / lenP : 0.0;               // +1 a la izquierda (se acerca)
    float betaR = min(0.5 * doppler_strength, 0.9);             // velocidad del borde interior del disco
    float gR = sqrt(1.0 - betaR * betaR) / (1.0 - betaR * cosA);
    float angR = atan2(p.y, p.x);
    float nR = vnoise(float2((angR + rotA) * 24.0 / TAU, 3.0), 24.0);
    float wR = max(0.01 * bc, pxb);
    float edge = 1.0 - shadow;
    float ring = edge * exp(-max(b - bc, 0.0) / wR);
    // La imagen de una vuelta menos: una linea mas tenue un poco hacia afuera
    ring += 0.3 * exp(-pow((b - (bc + 4.0 * wR)) / (0.7 * wR), 2.0));
    float3 ringCol = diskRamp(0.8 * gR);
    col += trans * ringCol * ring * disk_brightness * 1.4 * (gR * gR * gR) * (0.55 + 0.9 * nR);

    float halo = edge * exp(-max(b - bc, 0.0) / (0.12 * bc));
    col += glow_intensity * (haze * edge + diskRamp(0.55 * gR) * halo * 0.35 * disk_brightness * (gR * gR * gR));

    // ---- Salida ----------------------------------------------------------------------------------
    col = filmic(col * exposure * 0.8);
    col = pow(col, 1.0 / 2.2);
    // Dithering triangular contra el banding, solo donde hay luz: el centro queda negro puro
    float2 px = v_in.uv * uv_size;
    float dither = (hash12(px) + hash12(px + 71.3) - 1.0) / 255.0;
    float lit = max(col.r, max(col.g, col.b)) > 0.5 / 255.0 ? 1.0 : 0.0;
    col = saturate(col + dither * lit);
    return float4(col, 1.0);
}
