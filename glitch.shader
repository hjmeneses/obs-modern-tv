// Glitch digital aleatorio: la escena se "rompe" sola, como si el stream estuviera hackeado.
//   - Glitches pequeños cada 10–30 s (al azar): franjas corridas, bloques y separación RGB.
//   - Glitch completo cada 30–60 s (al azar): toda la escena se desarma unos segundos.
// Para OBS Studio (plugin obs-shaderfilter): clic derecho sobre la escena → Filtros → + →
// User-defined shader → Load shader text from file.
//
// El shader no guarda estado: los momentos de cada glitch salen de una rejilla con "jitter".
// Con un intervalo de A a B segundos, los eventos caen cada (A+B)/2 ± (B-A)/4, así que la
// separación entre dos seguidos queda siempre entre A y B, sin importar cuánto lleve en vivo.

uniform int test_mode<
    string label = "Modo";
    string widget_type = "select";
    int    option_0_value = 0;
    string option_0_label = "Normal (al azar)";
    int    option_1_value = 1;
    string option_1_label = "Probar glitch pequeno (en bucle)";
    int    option_2_value = 2;
    string option_2_label = "Probar glitch completo (en bucle)";
> = 0;

uniform bool small_enabled<
    string label = "Glitches pequenos";
> = true;

uniform float small_min<
    string label = "Pequenos: minimo entre glitches (s)";
    string widget_type = "slider";
    float minimum = 2.0; float maximum = 120.0; float step = 1.0;
> = 10.0;

uniform float small_max<
    string label = "Pequenos: maximo entre glitches (s)";
    string widget_type = "slider";
    float minimum = 2.0; float maximum = 120.0; float step = 1.0;
> = 30.0;

uniform float small_duration<
    string label = "Pequenos: duracion (s)";
    string widget_type = "slider";
    float minimum = 0.1; float maximum = 3.0; float step = 0.05;
> = 0.5;

uniform float small_strength<
    string label = "Pequenos: intensidad";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.5;

uniform bool big_enabled<
    string label = "Glitch completo";
> = true;

uniform float big_min<
    string label = "Completo: minimo entre glitches (s)";
    string widget_type = "slider";
    float minimum = 5.0; float maximum = 600.0; float step = 1.0;
> = 30.0;

uniform float big_max<
    string label = "Completo: maximo entre glitches (s)";
    string widget_type = "slider";
    float minimum = 5.0; float maximum = 600.0; float step = 1.0;
> = 60.0;

uniform float big_duration<
    string label = "Completo: duracion (s)";
    string widget_type = "slider";
    float minimum = 0.5; float maximum = 10.0; float step = 0.1;
> = 2.5;

uniform float big_strength<
    string label = "Completo: intensidad";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 1.0;

uniform float rgb_split<
    string label = "Separacion RGB";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 3.0; float step = 0.05;
> = 1.0;

uniform float block_size<
    string label = "Tamano de los bloques (px)";
    string widget_type = "slider";
    float minimum = 8.0; float maximum = 200.0; float step = 1.0;
> = 48.0;

uniform float glitch_fps<
    string label = "Cambios por segundo del glitch";
    string widget_type = "slider";
    float minimum = 4.0; float maximum = 60.0; float step = 1.0;
> = 20.0;

uniform int seed<
    string label = "Semilla (cambia el patron de tiempos)";
    string widget_type = "slider";
    int minimum = 0; int maximum = 100; int step = 1;
> = 0;

// Hashes de Dave Hoskins: estables con números grandes (no usan sin)
float hash11(float p)
{
    p = p * 0.1031;
    p = p - floor(p);
    p *= p + 33.33;
    p *= p + p;
    return p - floor(p);
}

float hash12(float2 p)
{
    float3 p3 = p.xyx * 0.1031;
    p3 = p3 - floor(p3);
    p3 += dot(p3, p3.yzx + 33.33);
    float h = (p3.x + p3.y) * p3.z;
    return h - floor(h);
}

float2 hash22(float2 p)
{
    float3 p3 = p.xyx * float3(0.1031, 0.1030, 0.0973);
    p3 = p3 - floor(p3);
    p3 += dot(p3, p3.yzx + 33.33);
    float2 h = (p3.xx + p3.yz) * p3.zy;
    return h - floor(h);
}

// Evento activo en el tiempo t: float2(progreso 0..1, id). Progreso < 0 = no hay evento.
float2 eventAt(float t, float a, float b, float dur, float salt)
{
    float lo = min(a, b);
    float hi = max(a, b);
    float P = max(0.5 * (lo + hi), 0.1);
    float J = 0.25 * (hi - lo);
    float d = clamp(dur, 0.01, max(lo * 0.9, 0.01));    // que no se encimen dos eventos
    float k0 = floor(t / P);
    for (int i = -1; i <= 1; i++) {
        float k = k0 + float(i);
        float s = (k + 0.5) * P + (hash11(k * 1.37 + salt) * 2.0 - 1.0) * J;
        float p = (t - s) / d;
        if (p >= 0.0 && p < 1.0)
            return float2(p, k);
    }
    return float2(-1.0, 0.0);
}

// Modo de prueba: un evento cada (duración + 1 s)
float2 loopAt(float t, float dur)
{
    float cyc = dur + 1.0;
    float p = (t - cyc * floor(t / cyc)) / dur;
    return float2(p < 1.0 ? p : -1.0, floor(t / cyc));
}

// Envolventes: pequeño = un par de tirones; completo = entra, se desarma y se recupera
float envSmall(float p, float id)
{
    float base = sqrt(sin(3.14159265 * p));
    float st = hash12(float2(id * 3.1 + 0.7, floor(p * 7.0)));
    return base * (st > 0.3 ? 1.0 : 0.15);
}

float envBig(float p, float id, float dur)
{
    float a = smoothstep(0.0, 0.06, p) * (1.0 - smoothstep(0.78, 1.0, p));
    float build = 0.55 + 0.45 * sin(3.14159265 * saturate(p * 1.25));
    float st = hash12(float2(id * 5.3 + 2.1, floor(p * dur * 8.0)));
    return a * build * (st > 0.12 ? 1.0 : 0.45);
}

float4 mainImage(VertData v_in) : TARGET
{
    float2 uv0 = v_in.uv;
    float t = elapsed_time;
    float sd = float(seed) * 17.31;

    // ---- ¿Hay glitch ahora? -------------------------------------------------------------
    float I = 0.0;      // intensidad total
    float B = 0.0;      // parte "completa" (efectos que solo salen en el glitch grande)
    float id = 0.0;

    float2 es = float2(-1.0, 0.0);
    float2 eb = float2(-1.0, 0.0);
    if (test_mode == 1) {
        es = loopAt(t, small_duration);
    } else if (test_mode == 2) {
        eb = loopAt(t, big_duration);
    } else {
        if (small_enabled)
            es = eventAt(t, small_min, small_max, small_duration, sd + 0.37);
        if (big_enabled)
            eb = eventAt(t, big_min, big_max, big_duration, sd + 91.7);
    }
    if (es.x >= 0.0) {
        I = envSmall(es.x, es.y) * small_strength;
        id = es.y;
    }
    if (eb.x >= 0.0) {
        float e = envBig(eb.x, eb.y, big_duration) * big_strength;
        if (e >= I) {
            I = e;
            B = e;
            id = eb.y + 5000.0;
        }
    }

    float4 clean = image.Sample(textureSampler, uv0);
    if (I < 0.002)
        return clean;

    // Tiempo "a saltos": el glitch cambia de forma a glitch_fps, no en cada cuadro
    float f = floor(t * glitch_fps) + id * 31.7 + sd;
    float2 uv = uv0;
    float2 px = uv_pixel_interval;

    // ---- Salto vertical (solo completo) -------------------------------------------------
    if (hash11(f * 1.31 + 4.2) < 0.25 * B) {
        uv.y += (hash11(f * 2.71) - 0.5) * 0.35;
        uv.y -= floor(uv.y);
    }

    // ---- Franjas horizontales corridas ----------------------------------------------------
    float rows = lerp(10.0, 45.0, hash11(f * 0.37 + 1.0));
    float row = floor(uv.y * rows);
    if (hash12(float2(row, f)) < 0.12 + 0.5 * I) {
        float sh = (hash12(float2(row + 5.3, f + 1.9)) - 0.5) * 2.0;
        uv.x += sh * (0.03 + 0.25 * B) * I;
    }
    // ondulación fina por línea
    float ln = floor(uv.y / px.y / 3.0);
    uv.x += (hash12(float2(ln, f)) - 0.5) * 0.006 * I;

    // ---- Bloques que se mueven (compresión rota) -----------------------------------------
    float2 bs = float2(block_size * 2.0, block_size) * px;
    float2 cell = floor(uv / bs);
    float hb = hash12(cell + f * 1.73);
    bool corrupt = false;
    if (hb < 0.06 * I + 0.3 * B) {
        uv += (hash22(cell + f) - 0.5) * (0.08 + 0.3 * B);
        corrupt = hash12(cell * 1.9 + f) < 0.4 + 0.4 * B;
    }

    // ---- Pixelado de toda la escena (solo completo) --------------------------------------
    if (hash11(f * 0.71 + 8.0) < 0.3 * B) {
        float ps = lerp(6.0, 40.0, hash11(f * 3.3)) * B;
        float2 g = max(ps, 1.0) * px;
        uv = (floor(uv / g) + 0.5) * g;
    }

    uv.x -= floor(uv.x);            // lo que se sale por un lado entra por el otro
    uv = saturate(uv);

    // ---- Separación RGB -------------------------------------------------------------------
    float dir = hash11(f * 0.53) < 0.5 ? -1.0 : 1.0;
    float2 off = float2(dir * rgb_split * (0.003 + 0.02 * I + 0.03 * B), 0.0);
    off.y = (hash11(f * 1.9) - 0.5) * rgb_split * 0.008 * B;
    float4 cr = image.Sample(textureSampler, saturate(uv + off));
    float4 cg = image.Sample(textureSampler, uv);
    float4 cb = image.Sample(textureSampler, saturate(uv - off));
    float3 col = float3(cr.r, cg.g, cb.b);
    float alpha = max(cg.a, max(cr.a, cb.a));

    // ---- Bloques con color dañado --------------------------------------------------------
    if (corrupt) {
        float m = hash12(cell + f * 0.37 + 9.0);
        if (m < 0.25)
            col = 1.0 - col;                                    // invertido
        else if (m < 0.5)
            col = col.gbr;                                      // canales cruzados
        else if (m < 0.75)
            col = floor(col * 3.0 + 0.5) / 3.0;                 // posterizado
        else
            col = (hash11(m * 91.0 + f) < 0.5) ? float3(1.0, 0.0, 1.0) : float3(0.0, 1.0, 0.4);
    }

    // ---- Líneas de ruido ------------------------------------------------------------------
    float nl = floor(uv0.y / px.y / 2.0);
    if (hash12(float2(nl, f + 3.3)) < 0.015 * I + 0.05 * B) {
        float n = hash12(float2(floor(uv0.x / px.x / 4.0), nl + f));
        col = lerp(col, float3(n, n, n), 0.85);
        alpha = max(alpha, 0.85);
    }

    // ---- Líneas de barrido y apagones (solo completo) ------------------------------------
    float scan = (frac(uv0.y / px.y * 0.5) < 0.5) ? 1.0 : 0.0;
    col *= 1.0 - 0.18 * I * scan;
    if (hash11(f * 2.13 + 3.0) < 0.06 * B)
        col *= 0.1;                                             // cuadro casi negro
    else if (hash11(f * 4.7 + 1.0) < 0.04 * B)
        col = lerp(col, float3(1.0, 1.0, 1.0), 0.6);            // destello

    return float4(saturate(col), alpha);
}
