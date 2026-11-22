// Random digital glitch: the scene "breaks" on its own, as if the stream had been hacked.
//   - Small glitches every 10–30 s (at random): shifted stripes, blocks and RGB split.
//   - Full glitch every 30–60 s (at random): the whole scene falls apart for a few seconds.
// For OBS Studio (obs-shaderfilter plugin): right-click the scene → Filters → + →
// User-defined shader → Load shader text from file.
//
// The shader keeps no state: the time of each glitch comes from a jittered grid. With an
// interval from A to B seconds, events land every (A+B)/2 ± (B-A)/4, so the gap between two in
// a row always stays between A and B, no matter how long you have been live.

uniform int test_mode<
    string label = "Mode";
    string widget_type = "select";
    int    option_0_value = 0;
    string option_0_label = "Normal (random)";
    int    option_1_value = 1;
    string option_1_label = "Test small glitch (loop)";
    int    option_2_value = 2;
    string option_2_label = "Test full glitch (loop)";
> = 0;

uniform bool small_enabled<
    string label = "Small glitches";
> = true;

uniform float small_min<
    string label = "Small: minimum between glitches (s)";
    string widget_type = "slider";
    float minimum = 2.0; float maximum = 120.0; float step = 1.0;
> = 10.0;

uniform float small_max<
    string label = "Small: maximum between glitches (s)";
    string widget_type = "slider";
    float minimum = 2.0; float maximum = 120.0; float step = 1.0;
> = 30.0;

uniform float small_duration<
    string label = "Small: duration (s)";
    string widget_type = "slider";
    float minimum = 0.1; float maximum = 3.0; float step = 0.05;
> = 0.5;

uniform float small_strength<
    string label = "Small: strength";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.5;

uniform bool big_enabled<
    string label = "Full glitch";
> = true;

uniform float big_min<
    string label = "Full: minimum between glitches (s)";
    string widget_type = "slider";
    float minimum = 5.0; float maximum = 600.0; float step = 1.0;
> = 30.0;

uniform float big_max<
    string label = "Full: maximum between glitches (s)";
    string widget_type = "slider";
    float minimum = 5.0; float maximum = 600.0; float step = 1.0;
> = 60.0;

uniform float big_duration<
    string label = "Full: duration (s)";
    string widget_type = "slider";
    float minimum = 0.5; float maximum = 10.0; float step = 0.1;
> = 2.5;

uniform float big_strength<
    string label = "Full: strength";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 1.0;

uniform float rgb_split<
    string label = "RGB split";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 3.0; float step = 0.05;
> = 1.0;

uniform float block_size<
    string label = "Block size (px)";
    string widget_type = "slider";
    float minimum = 8.0; float maximum = 200.0; float step = 1.0;
> = 48.0;

uniform float glitch_fps<
    string label = "Glitch changes per second";
    string widget_type = "slider";
    float minimum = 4.0; float maximum = 60.0; float step = 1.0;
> = 20.0;

uniform int seed<
    string label = "Seed (changes the timing pattern)";
    string widget_type = "slider";
    int minimum = 0; int maximum = 100; int step = 1;
> = 0;

// Dave Hoskins hashes: stable with large numbers (no sin)
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

// Event active at time t: float2(progress 0..1, id). Progress < 0 = no event.
float2 eventAt(float t, float a, float b, float dur, float salt)
{
    float lo = min(a, b);
    float hi = max(a, b);
    float P = max(0.5 * (lo + hi), 0.1);
    float J = 0.25 * (hi - lo);
    float d = clamp(dur, 0.01, max(lo * 0.9, 0.01));    // two events never overlap
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

// Test mode: one event every (duration + 1 s)
float2 loopAt(float t, float dur)
{
    float cyc = dur + 1.0;
    float p = (t - cyc * floor(t / cyc)) / dur;
    return float2(p < 1.0 ? p : -1.0, floor(t / cyc));
}

// Envelopes: small = a couple of jerks; full = comes in, falls apart and recovers
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

    // ---- Is there a glitch now? ---------------------------------------------------------
    float I = 0.0;      // total strength
    float B = 0.0;      // "full" part (effects that only show in the big glitch)
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

    // "Stepped" time: the glitch changes shape at glitch_fps, not every frame
    float f = floor(t * glitch_fps) + id * 31.7 + sd;
    float2 uv = uv0;
    float2 px = uv_pixel_interval;

    // ---- Vertical jump (full only) ------------------------------------------------------
    if (hash11(f * 1.31 + 4.2) < 0.25 * B) {
        uv.y += (hash11(f * 2.71) - 0.5) * 0.35;
        uv.y -= floor(uv.y);
    }

    // ---- Shifted horizontal stripes --------------------------------------------------------
    float rows = lerp(10.0, 45.0, hash11(f * 0.37 + 1.0));
    float row = floor(uv.y * rows);
    if (hash12(float2(row, f)) < 0.12 + 0.5 * I) {
        float sh = (hash12(float2(row + 5.3, f + 1.9)) - 0.5) * 2.0;
        uv.x += sh * (0.03 + 0.25 * B) * I;
    }
    // fine per-line wobble
    float ln = floor(uv.y / px.y / 3.0);
    uv.x += (hash12(float2(ln, f)) - 0.5) * 0.006 * I;

    // ---- Moving blocks (broken compression) ----------------------------------------------
    float2 bs = float2(block_size * 2.0, block_size) * px;
    float2 cell = floor(uv / bs);
    float hb = hash12(cell + f * 1.73);
    bool corrupt = false;
    if (hb < 0.06 * I + 0.3 * B) {
        uv += (hash22(cell + f) - 0.5) * (0.08 + 0.3 * B);
        corrupt = hash12(cell * 1.9 + f) < 0.4 + 0.4 * B;
    }

    // ---- Whole-scene pixelation (full only) ---------------------------------------------
    if (hash11(f * 0.71 + 8.0) < 0.3 * B) {
        float ps = lerp(6.0, 40.0, hash11(f * 3.3)) * B;
        float2 g = max(ps, 1.0) * px;
        uv = (floor(uv / g) + 0.5) * g;
    }

    uv.x -= floor(uv.x);            // what leaves one side comes in the other
    uv = saturate(uv);

    // ---- RGB split ------------------------------------------------------------------------
    float dir = hash11(f * 0.53) < 0.5 ? -1.0 : 1.0;
    float2 off = float2(dir * rgb_split * (0.003 + 0.02 * I + 0.03 * B), 0.0);
    off.y = (hash11(f * 1.9) - 0.5) * rgb_split * 0.008 * B;
    float4 cr = image.Sample(textureSampler, saturate(uv + off));
    float4 cg = image.Sample(textureSampler, uv);
    float4 cb = image.Sample(textureSampler, saturate(uv - off));
    float3 col = float3(cr.r, cg.g, cb.b);
    float alpha = max(cg.a, max(cr.a, cb.a));

    // ---- Blocks with damaged color --------------------------------------------------------
    if (corrupt) {
        float m = hash12(cell + f * 0.37 + 9.0);
        if (m < 0.25)
            col = 1.0 - col;                                    // inverted
        else if (m < 0.5)
            col = col.gbr;                                      // swapped channels
        else if (m < 0.75)
            col = floor(col * 3.0 + 0.5) / 3.0;                 // posterized
        else
            col = (hash11(m * 91.0 + f) < 0.5) ? float3(1.0, 0.0, 1.0) : float3(0.0, 1.0, 0.4);
    }

    // ---- Noise lines -----------------------------------------------------------------------
    float nl = floor(uv0.y / px.y / 2.0);
    if (hash12(float2(nl, f + 3.3)) < 0.015 * I + 0.05 * B) {
        float n = hash12(float2(floor(uv0.x / px.x / 4.0), nl + f));
        col = lerp(col, float3(n, n, n), 0.85);
        alpha = max(alpha, 0.85);
    }

    // ---- Scan lines and blackouts (full only) -------------------------------------------
    float scan = (frac(uv0.y / px.y * 0.5) < 0.5) ? 1.0 : 0.0;
    col *= 1.0 - 0.18 * I * scan;
    if (hash11(f * 2.13 + 3.0) < 0.06 * B)
        col *= 0.1;                                             // near-black frame
    else if (hash11(f * 4.7 + 1.0) < 0.04 * B)
        col = lerp(col, float3(1.0, 1.0, 1.0), 0.6);            // flash

    return float4(saturate(col), alpha);
}
