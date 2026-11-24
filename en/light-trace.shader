// Light trace: a line of light with a white core and a coloured glow runs along the outline
// of the source (a text, a logo, an image with transparency), trembling with energy.
// Inspired by the "light saber" style plugins for After Effects. For OBS Studio
// (obs-shaderfilter plugin, "User-defined shader").
//
// Modes:
//   Sweep     the light crosses the source in a straight line (left to right by default) and
//             lights the outline as it passes, leaving a trail
//   Spin      the same, but the light goes once around the centre of the source
//   Electric  stretches of the outline switch on and off at random, like flickering neon
//
// Sequence (Progress 0 -> 100):
//   0-70   The light runs along the outline (in Electric it switches on over 0-20)
//   70-80  The outline stays lit at "Glow left behind"
//   80-100 The trace fades out (if "Fade the trace at the end" is on)
//
// The glow spills outside the source: give it room with the filter's expand options
// (Expand Left/Right/Top/Bottom) or put the text in a source bigger than it.

uniform bool auto_play<
    string label = "Loop (ignores Progress)";
> = true;

uniform float duration<
    string label = "Sequence duration (s)";
    string widget_type = "slider";
    float minimum = 1.0; float maximum = 20.0; float step = 0.5;
> = 4.0;

uniform float progress<
    string label = "Progress (%)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 100.0; float step = 0.1;
> = 50.0;

uniform int mode<
    string label = "Mode";
    string widget_type = "select";
    int    option_0_value = 0;
    string option_0_label = "Sweep: the light crosses the source in a straight line";
    int    option_1_value = 1;
    string option_1_label = "Spin: the light goes once around the centre";
    int    option_2_value = 2;
    string option_2_label = "Electric: stretches that switch on and off";
> = 0;

uniform float sweep_angle<
    string label = "Direction (degrees; 0 = left to right, 90 = top to bottom)";
    string widget_type = "slider";
    float minimum = -180.0; float maximum = 180.0; float step = 1.0;
> = 0.0;

uniform int source_mode<
    string label = "Source";
    string widget_type = "select";
    int    option_0_value = 0;
    string option_0_label = "Appears behind the trace";
    int    option_1_value = 1;
    string option_1_label = "Always visible";
    int    option_2_value = 2;
    string option_2_label = "Hidden (trace only)";
> = 0;

uniform int contour_from<
    string label = "Outline from";
    string widget_type = "select";
    int    option_0_value = 0;
    string option_0_label = "Transparency (alpha)";
    int    option_1_value = 1;
    string option_1_label = "Brightness (for logos on black)";
> = 0;

uniform float threshold<
    string label = "Outline threshold";
    string widget_type = "slider";
    float minimum = 0.05; float maximum = 0.95; float step = 0.01;
> = 0.5;

uniform bool end_fade<
    string label = "Fade the trace at the end";
> = true;

uniform float4 core_color<
    string label = "Core colour";
> = {1.0, 0.97, 0.92, 1.0};

uniform float4 glow_color<
    string label = "Glow colour";
> = {1.0, 0.55, 0.22, 1.0};

uniform float line_width<
    string label = "Core width (px)";
    string widget_type = "slider";
    float minimum = 0.5; float maximum = 12.0; float step = 0.1;
> = 2.5;

uniform float glow_size<
    string label = "Glow reach (px)";
    string widget_type = "slider";
    float minimum = 2.0; float maximum = 60.0; float step = 0.5;
> = 22.0;

uniform float glow_strength<
    string label = "Glow strength";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 4.0; float step = 0.01;
> = 2.0;

uniform float trail<
    string label = "Trail length (fraction of the path)";
    string widget_type = "slider";
    float minimum = 0.02; float maximum = 1.0; float step = 0.01;
> = 0.3;

uniform float residual<
    string label = "Glow left behind";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.3;

uniform float distortion<
    string label = "Trace jitter (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 20.0; float step = 0.1;
> = 2.5;

uniform float energy_speed<
    string label = "Energy speed";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 5.0; float step = 0.01;
> = 1.5;

uniform float flicker<
    string label = "Flicker";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.25;

uniform float segment_size<
    string label = "Electric: stretch length (px)";
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

// Dave Hoskins hash (no sin(), stable with large numbers)
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

// What defines the outline: alpha, or brightness times alpha. 0 outside the source.
float shapeAt(float2 tc)
{
    if (tc.x < 0.0 || tc.x > 1.0 || tc.y < 0.0 || tc.y > 1.0)
        return 0.0;
    float4 c = image.SampleLevel(textureSampler, tc, 0.0);
    if (contour_from == 1)
        return dot(c.rgb, float3(0.2126, 0.7152, 0.0722)) * c.a;
    return c.a;
}

// Approximate distance (px) to the outline, inside or outside: march from the pixel in DIRS
// directions until the threshold is crossed, and interpolate the crossing between two samples.
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

    // Timeline
    float draw = seg(p, 0.0, 0.7);
    float fadeOut = end_fade ? 1.0 - ease(seg(p, 0.8, 1.0)) : 1.0;

    // Where this pixel sits along the path (0 -> 1)
    float2 P = pixel - uv_size * 0.5;
    float ang = radians(sweep_angle);
    float s;
    if (mode == 1)
    {
        s = frac(atan2(P.y, P.x) / 6.2831853 - sweep_angle / 360.0 + 1.0);
    }
    else
    {
        float2 dir = float2(cos(ang), sin(ang));
        float hw = 0.5 * (abs(dir.x) * uv_size.x + abs(dir.y) * uv_size.y);
        s = (dot(P, dir) + hw) / (2.0 * hw);
    }

    // How much light the outline carries here and how much of the source shows
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
        float passed = smoothstep(-0.006, 0.0, behind);                 // 0 ahead of the light
        float b = max(behind, 0.0);
        float tr = exp(-3.0 * b / max(trail, 0.001));
        float spark = exp(-b * 60.0);                                   // brighter tip
        lit = passed * (residual + (1.0 - residual) * tr + 0.8 * spark);
        reveal = smoothstep(0.0, max(trail, 0.04) * 0.5, behind);
    }
    float fl = lerp(1.0, 0.55 + 0.9 * vnoise(float2(t * 23.0, 3.7)), flicker);
    lit *= fadeOut * fl;

    // The trace: core and glow from the distance to the outline (jittered with noise)
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

    // Source under the trace; the light is added (premultiplied)
    float vis = source_mode == 0 ? reveal : (source_mode == 1 ? 1.0 : 0.0);
    float figA = src.a * vis;
    float3 prem = src.rgb * figA + light;
    float alpha = saturate(figA + lightA * (1.0 - figA));
    return float4(saturate(prem / max(alpha, 0.0001)), alpha);
}
