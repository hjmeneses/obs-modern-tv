// Trazo de luz: una línea de luz con núcleo blanco y resplandor de color recorre el contorno
// de la fuente (un texto, un logo, una imagen con transparencia), con temblor de energía.
// Inspirado en el look de los plugins tipo "sable de luz" de After Effects. Para OBS Studio
// (plugin obs-shaderfilter, "User-defined shader").
//
// Modos:
//   Barrido   la luz cruza la fuente en línea recta (izquierda a derecha por defecto) y
//             enciende el contorno a su paso, dejando una estela
//   Giro      la luz le da la vuelta al título por fuera, como en una pista: por arriba,
//             baja por un extremo, regresa por abajo y sube por el otro, a velocidad pareja
//   Eléctrico tramos del contorno que se encienden y apagan al azar, como neón inestable
//   Radar     una vuelta con velocidad angular constante, como la aguja de un radar
//
// Secuencia (Progreso 0 → 100):
//   0–70   La luz recorre el contorno (en Eléctrico, se enciende en 0–20)
//   70–80  Queda el contorno con el brillo de "Brillo que queda"
//   80–100 Se apaga el trazo (si "Apagar el trazo al final" está activo)
//
// El resplandor se sale de la fuente: dale margen con las opciones de expandir del filtro
// (Expand Left/Right/Top/Bottom) o pon el texto en una fuente más grande que él.

uniform bool auto_play<
    string label = "Reproducir en bucle (ignora Progreso)";
> = true;

uniform float duration<
    string label = "Duracion de la secuencia (s)";
    string widget_type = "slider";
    float minimum = 1.0; float maximum = 20.0; float step = 0.5;
> = 4.0;

uniform float progress<
    string label = "Progreso (%)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 100.0; float step = 0.1;
> = 50.0;

uniform int mode<
    string label = "Modo";
    string widget_type = "select";
    int    option_0_value = 0;
    string option_0_label = "Barrido: la luz cruza la fuente en linea recta";
    int    option_1_value = 1;
    string option_1_label = "Giro: la luz le da la vuelta al titulo por fuera";
    int    option_2_value = 2;
    string option_2_label = "Electrico: tramos que se encienden y apagan";
    int    option_3_value = 3;
    string option_3_label = "Radar: gira con velocidad angular constante";
> = 0;

uniform float sweep_angle<
    string label = "Direccion (grados; 0 = de izquierda a derecha, 90 = de arriba abajo)";
    string widget_type = "slider";
    float minimum = -180.0; float maximum = 180.0; float step = 1.0;
> = 0.0;

uniform int source_mode<
    string label = "Fuente";
    string widget_type = "select";
    int    option_0_value = 0;
    string option_0_label = "Aparece detras del trazo";
    int    option_1_value = 1;
    string option_1_label = "Siempre visible";
    int    option_2_value = 2;
    string option_2_label = "Oculta (solo el trazo)";
> = 0;

uniform int contour_from<
    string label = "Contorno de";
    string widget_type = "select";
    int    option_0_value = 0;
    string option_0_label = "Transparencia (alfa)";
    int    option_1_value = 1;
    string option_1_label = "Brillo (para logos sobre fondo negro)";
> = 0;

uniform float threshold<
    string label = "Umbral del contorno";
    string widget_type = "slider";
    float minimum = 0.05; float maximum = 0.95; float step = 0.01;
> = 0.5;

uniform bool end_fade<
    string label = "Apagar el trazo al final";
> = true;

uniform float4 core_color<
    string label = "Color del nucleo";
> = {1.0, 0.97, 0.92, 1.0};

uniform float4 glow_color<
    string label = "Color del resplandor";
> = {1.0, 0.55, 0.22, 1.0};

uniform float line_width<
    string label = "Grosor del nucleo (px)";
    string widget_type = "slider";
    float minimum = 0.5; float maximum = 12.0; float step = 0.1;
> = 2.5;

uniform float glow_size<
    string label = "Alcance del resplandor (px)";
    string widget_type = "slider";
    float minimum = 2.0; float maximum = 60.0; float step = 0.5;
> = 22.0;

uniform float glow_strength<
    string label = "Intensidad del resplandor";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 4.0; float step = 0.01;
> = 2.0;

uniform float trail<
    string label = "Largo de la estela (fraccion del recorrido)";
    string widget_type = "slider";
    float minimum = 0.02; float maximum = 1.0; float step = 0.01;
> = 0.3;

uniform float residual<
    string label = "Brillo que queda tras la estela";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.3;

uniform float distortion<
    string label = "Temblor del trazo (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 20.0; float step = 0.1;
> = 2.5;

uniform float energy_speed<
    string label = "Velocidad de la energia";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 5.0; float step = 0.01;
> = 1.5;

uniform float flicker<
    string label = "Parpadeo";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.25;

uniform float segment_size<
    string label = "Electrico: largo de los tramos (px)";
    string widget_type = "slider";
    float minimum = 10.0; float maximum = 400.0; float step = 1.0;
> = 90.0;

#define DIRS 12
#define STEPS 8

float seg(float p, float a, float b)
{
    return saturate((p - a) / (b - a));
}

float ease(float t)
{
    return t * t * (3.0 - 2.0 * t);
}

// Hash de Dave Hoskins (sin sin(), estable con números grandes)
float hash12(float2 p)
{
    float3 p3 = p.xyx * 0.1031;
    p3 = p3 - floor(p3);
    p3 += dot(p3, p3.yzx + 33.33);
    float h = (p3.x + p3.y) * p3.z;
    return h - floor(h);
}

float vnoise(float2 x)
{
    float2 i = floor(x);
    float2 f = x - i;
    f = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + float2(1.0, 0.0));
    float c = hash12(i + float2(0.0, 1.0));
    float d = hash12(i + float2(1.0, 1.0));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float fbm(float2 x)
{
    return 0.65 * vnoise(x) + 0.35 * vnoise(x * 2.13 + 5.2);
}

// Lo que define el contorno: alfa, o brillo por alfa. Fuera de la fuente vale 0.
float shapeAt(float2 tc)
{
    if (tc.x < 0.0 || tc.x > 1.0 || tc.y < 0.0 || tc.y > 1.0)
        return 0.0;
    float4 c = image.SampleLevel(textureSampler, tc, 0.0);
    if (contour_from == 1)
        return dot(c.rgb, float3(0.2126, 0.7152, 0.0722)) * c.a;
    return c.a;
}

// Posición (0 → 1) en el borde del rectángulo de semilados hs, recorrido a velocidad pareja
// desde el centro del lado derecho, en el mismo sentido que atan2 (hacia abajo primero).
// El punto P se lleva al lado más cercano del rectángulo.
float trackPos(float2 P, float2 hs)
{
    float a = hs.x;
    float b = hs.y;
    float L;
    if (a - abs(P.x) < b - abs(P.y))
    {
        float y = clamp(P.y, -b, b);
        if (P.x >= 0.0)
            L = y >= 0.0 ? y : 4.0 * a + 3.0 * b + (y + b);
        else
            L = 2.0 * a + b + (b - y);
    }
    else
    {
        float x = clamp(P.x, -a, a);
        if (P.y >= 0.0)
            L = b + (a - x);
        else
            L = 2.0 * a + 3.0 * b + (x + a);
    }
    return L / (4.0 * (a + b));
}

// Distancia aproximada (px) al contorno, por dentro o por fuera: desde el píxel se avanza en
// DIRS direcciones hasta cruzar el umbral, y el cruce se interpola entre las dos muestras.
float edgeDistance(float2 q, float maxR)
{
    float a0 = shapeAt(q) - threshold;
    bool inside = a0 > 0.0;
    float best = maxR;
    float stepR = maxR / STEPS;
    [loop]
    for (int i = 0; i < DIRS; i++)
    {
        float ang = (i + 0.5) * 6.2831853 / DIRS;
        float2 dir = float2(cos(ang), sin(ang)) * uv_pixel_interval;
        float prev = a0;
        [loop]
        for (int k = 1; k <= STEPS; k++)
        {
            if ((k - 1) * stepR >= best)
                break;
            float a = shapeAt(q + dir * (k * stepR)) - threshold;
            if ((a > 0.0) != inside)
            {
                float f = prev / (prev - a);
                best = min(best, (k - 1 + f) * stepR);
                break;
            }
            prev = a;
        }
    }
    return best;
}

float4 mainImage(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float t = elapsed_time;
    float2 pixel = uv * uv_size;

    float p = auto_play ? frac(t / max(duration, 0.5)) : saturate(progress * 0.01);
    float4 src = image.Sample(textureSampler, uv);

    // Línea de tiempo
    float draw = seg(p, 0.0, 0.7);
    float fadeOut = end_fade ? 1.0 - ease(seg(p, 0.8, 1.0)) : 1.0;

    // Posición de este píxel en el recorrido (0 → 1)
    float2 P = pixel - uv_size * 0.5;
    float ang = radians(sweep_angle);
    float s;
    if (mode == 1)
    {
        // La luz da la vuelta al título por fuera, como en una pista; "Dirección" es el punto
        // de arranque
        float2 hs = uv_size * 0.5;
        float2 start = float2(cos(ang), sin(ang));
        start *= min(hs.x / max(abs(start.x), 0.00001), hs.y / max(abs(start.y), 0.00001));
        s = frac(trackPos(P, hs) - trackPos(start, hs) + 1.0);
    }
    else if (mode == 3)
    {
        s = frac(atan2(P.y, P.x) / 6.2831853 - sweep_angle / 360.0 + 1.0);
    }
    else
    {
        float2 dir = float2(cos(ang), sin(ang));
        float hw = 0.5 * (abs(dir.x) * uv_size.x + abs(dir.y) * uv_size.y);
        s = (dot(P, dir) + hw) / (2.0 * hw);
    }

    // Cuánta luz lleva el contorno aquí y cuánto se ve ya la fuente
    float lit;
    float reveal;
    if (mode == 2)
    {
        float env = ease(seg(p, 0.0, 0.2));
        float n = fbm(pixel / segment_size + float2(t * energy_speed * 0.7, -t * energy_speed * 0.4));
        float on = smoothstep(0.45, 0.6, n);
        lit = env * (residual + (1.0 - residual) * on);
        reveal = env;
    }
    else
    {
        float head = lerp(-0.03, 1.0 + trail, draw);
        float behind = head - s;
        float passed = smoothstep(-0.006, 0.0, behind);                 // 0 delante de la luz
        float b = max(behind, 0.0);
        float tr = exp(-3.0 * b / max(trail, 0.001));
        float spark = exp(-b * 60.0);                                   // punta más brillante
        lit = passed * (residual + (1.0 - residual) * tr + 0.8 * spark);
        reveal = smoothstep(0.0, max(trail, 0.04) * 0.5, behind);
        if (mode == 1)
        {
            // En Giro el contorno ya está tenue antes de que pase la luz, y la fuente aparece
            // con el tiempo, para no cortar las letras por la mitad
            lit = max(lit, residual * ease(seg(p, 0.0, 0.1)));
            reveal = ease(seg(p, 0.15, 0.6));
        }
    }
    float fl = lerp(1.0, 0.55 + 0.9 * vnoise(float2(t * 23.0, 3.7)), flicker);
    lit *= fadeOut * fl;

    // El trazo: núcleo y resplandor según la distancia al contorno (temblando con ruido)
    float3 light = float3(0.0, 0.0, 0.0);
    if (lit > 0.002)
    {
        float2 w = float2(fbm(pixel / 60.0 + t * energy_speed),
                          fbm(pixel / 60.0 + 17.3 - t * energy_speed)) - 0.5;
        float2 q = uv + w * 2.0 * distortion * uv_pixel_interval;
        float maxR = glow_size + line_width;
        float d = edgeDistance(q, maxR);

        float core = 1.0 - smoothstep(line_width * 0.5, line_width * 0.5 + 1.0, d);
        float fall = saturate(1.0 - d / maxR);
        float glow = (0.6 * exp(-d / max(glow_size * 0.12, 0.5)) + 0.4 * exp(-d / max(glow_size * 0.4, 0.5)))
                   * fall * fall;
        float energy = 0.75 + 0.5 * vnoise(pixel / 25.0 + t * energy_speed * 3.0);
        light = (core_color.rgb * core * 1.5 + glow_color.rgb * glow * glow_strength) * lit * energy;
    }
    float lightA = saturate(max(light.r, max(light.g, light.b)));

    // Fuente debajo del trazo; la luz se suma (premultiplicada)
    float vis = source_mode == 0 ? reveal : (source_mode == 1 ? 1.0 : 0.0);
    float figA = src.a * vis;
    float3 prem = src.rgb * figA + light;
    float alpha = saturate(figA + lightA * (1.0 - figA));
    return float4(saturate(prem / max(alpha, 0.0001)), alpha);
}
