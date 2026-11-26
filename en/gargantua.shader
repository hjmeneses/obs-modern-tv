// Gargantua: a black hole with an accretion disk, procedural and real time.
// Inspired by the black hole in the film Interstellar (2014).
// For OBS Studio (obs-shaderfilter plugin): add it as a filter on a black color source (or an empty
// scene) → Filters → + → User-defined shader → Load shader text from file. It does not use the
// input image.
//
// How it works (details in docs/gargantua-spec.md):
//   - One ray per pixel leaves the camera and bends step by step with the acceleration of a photon
//     around a Schwarzschild black hole (Schwarzschild radius = 1).
//   - Each time the ray crosses the disk plane it adds the disk's color; that is why the far side
//     of the disk shows above and below the black hole.
//   - The shadow and the ring are decided from the ray's impact parameter, which is known exactly,
//     so the edge stays smooth whatever the number of steps.
//   - Doppler: the side of the disk moving towards you is brighter (g^3) and whiter.
//   - Everything is computed in linear light; exposure, tone mapping, sRGB and dithering go last.

uniform float black_hole_radius<
    string label = "Black hole radius";
    string widget_type = "slider";
    float minimum = 0.15; float maximum = 0.35; float step = 0.005;
> = 0.22;

uniform float disk_inner_radius<
    string label = "Disk: inner radius (x black hole radius)";
    string widget_type = "slider";
    float minimum = 1.0; float maximum = 1.5; float step = 0.01;
> = 1.15;

uniform float disk_outer_radius<
    string label = "Disk: outer radius (x black hole radius)";
    string widget_type = "slider";
    float minimum = 2.0; float maximum = 3.5; float step = 0.05;
> = 2.8;

uniform float disk_thickness<
    string label = "Disk: thickness (opacity)";
    string widget_type = "slider";
    float minimum = 0.05; float maximum = 0.30; float step = 0.01;
> = 0.12;

uniform float inclination<
    string label = "Camera inclination (degrees)";
    string widget_type = "slider";
    float minimum = 2.0; float maximum = 30.0; float step = 0.5;
> = 8.0;

uniform float rotation_speed<
    string label = "Rotation speed";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.35;

uniform float doppler_strength<
    string label = "Doppler";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 2.0; float step = 0.05;
> = 1.0;

uniform float lensing_strength<
    string label = "Gravitational lensing";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 2.0; float step = 0.05;
> = 1.0;

uniform float disk_brightness<
    string label = "Disk brightness";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 3.0; float step = 0.05;
> = 1.2;

uniform float glow_intensity<
    string label = "Glow";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 2.0; float step = 0.05;
> = 0.8;

uniform float star_density<
    string label = "Star density";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.5;

uniform float exposure<
    string label = "Exposure";
    string widget_type = "slider";
    float minimum = 0.5; float maximum = 2.0; float step = 0.05;
> = 1.0;

uniform int quality_steps<
    string label = "Quality (ray steps)";
    string widget_type = "select";
    int    option_0_value = 32;
    string option_0_label = "32 (low)";
    int    option_1_value = 64;
    string option_1_label = "64 (normal)";
    int    option_2_value = 128;
    string option_2_label = "128 (high: may lower fps on low-end GPUs)";
> = 64;

#define PI 3.14159265
#define TAU 6.28318531
// Shadow radius with lensing at 1: 3·sqrt(3)/2 Schwarzschild radii
#define SHADOW_B 2.59807621
// Camera distance to the black hole, in Schwarzschild radii
#define CAM_DIST 40.0

// Dave Hoskins' hashes: stable with large numbers (no sin)
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

// Value noise, periodic in x (period cells): the disk angle wraps around without a seam
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

// The spec's palette, in linear: 0 = dark red, 1 = almost white
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

// Doppler factor g of the disk at pos for a ray with direction dir (from the camera to the disk).
// The orbital speed is Kepler's as seen by a static observer: sqrt(0.5 / (r - 1)).
float dopplerG(float3 pos, float3 dir, float r)
{
    float beta = min(sqrt(0.5 / max(r - 1.0, 0.5)) * doppler_strength, 0.9);
    float3 tang = normalize(float3(-pos.z, 0.0, pos.x));
    return sqrt(1.0 - beta * beta) / (1.0 - beta * dot(tang, -dir));
}

// Relative disk temperature: 1 at the inner edge, lower outwards
float diskHeat(float r, float rin)
{
    return pow(rin / r, 1.6) * sqrt(saturate((r - rin * 0.98) / (rin * 0.12)));
}

// Radial density: soft at the inner edge, fading out towards the outer edge
float diskDensity(float r, float rin, float rout)
{
    return smoothstep(rin * 0.98, rin * 1.06, r) * (1.0 - smoothstep(rout * 0.6, rout, r));
}

// Stars in direction d: two grid layers on the sphere, with twinkle.
// pa = angular size of a pixel, so stars neither vanish nor alias.
float3 starField(float3 d, float t, float pa)
{
    // Slow drift, as if the camera were orbiting: the slight parallax
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

// Filmic tone mapping (Narkowicz's ACES approximation): strong highlights go to white
float3 filmic(float3 x)
{
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

float4 mainImage(VertData v_in) : TARGET
{
    float t = elapsed_time;
    float minDim = min(uv_size.x, uv_size.y);
    // Screen centered, scaled by the short side, y up
    float2 p = float2(v_in.uv.x - 0.5, 0.5 - v_in.uv.y) * uv_size / minDim;

    // ---- Camera -----------------------------------------------------------------------------
    float inc = radians(inclination);
    float3 cam = CAM_DIST * float3(0.0, sin(inc), -cos(inc));
    float3 fwd = -normalize(cam);
    float3 right = float3(1.0, 0.0, 0.0);
    float3 up = cross(fwd, right);
    // Scale so the shadow measures black_hole_radius with lensing at 1
    float k = tan(asin(SHADOW_B / CAM_DIST)) / black_hole_radius;
    float3 dir = normalize(fwd + k * (p.x * right + p.y * up));
    float3 dir0 = dir;
    float3 pos = cam;

    // ---- What is known without tracing: impact parameter, shadow and ring ----------------------
    float lens = lensing_strength;
    float rcap = max(lens, 0.5);                            // horizon (with a minimum when there is no lensing)
    float bc = max(SHADOW_B * lens, rcap);                   // shadow edge
    float b = CAM_DIST * sin(atan(k * length(p)));           // the ray's impact parameter
    float pxb = CAM_DIST * k / minDim;                       // how much b changes in one pixel
    float shadow = 1.0 - smoothstep(bc - 0.75 * pxb, bc + 0.75 * pxb, b);
    float3 hv = cross(pos, dir);
    float h2 = dot(hv, hv);

    float rin = disk_inner_radius * SHADOW_B;
    float rout = disk_outer_radius * SHADOW_B;
    float stepK = 8.0 / float(max(quality_steps, 8));

    // ---- Tracing -------------------------------------------------------------------------------
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
            // Moving away and past the disk. The bending left until infinity is added at once
            // (exact integral of the same acceleration along a straight line); otherwise each ray
            // would stop at a different step and the stars would come out in steps.
            float bb = sqrt(h2);
            float s = dot(pos, dir);
            float q = bb * bb + s * s;
            float rest = lens / bb * (1.0 - s * (2.0 * s * s + 3.0 * bb * bb) / (2.0 * q * sqrt(q)));
            float3 toward = normalize(dir * s - pos);
            dir = normalize(dir + toward * rest);
            break;
        }
        float ds = clamp(stepK * r, 0.02, 10.0);
        // Midpoint (RK2): with Euler each step's error moved the stars by tens of pixels
        float3 mid = pos + dir * (0.5 * ds);
        float rm2 = dot(mid, mid);
        float3 acc = -1.5 * lens * h2 * mid / (rm2 * rm2 * sqrt(rm2));
        float3 ndir = normalize(dir + acc * ds);
        float3 npos = pos + (dir + ndir) * (0.5 * ds);

        // Disk haze (glow): light near the plane, without noise so it stays cheap
        float rp = length(pos.xz);
        if (abs(pos.y) < 1.0 && rp > rin * 0.9 && rp < rout * 1.15) {
            float gH = dopplerG(pos, ndir, max(rp, 1.01));
            float heat = diskHeat(max(rp, rin), rin);
            float dens = diskDensity(rp, rin * 0.92, rout * 1.1);
            haze += diskRamp(heat * gH) * (heat * gH * gH * gH) * dens * exp(-abs(pos.y) * 4.0) * ds * trans * 0.02;
        }

        // Does it cross the disk plane in this step?
        if (pos.y * npos.y < 0.0) {
            float f = pos.y / (pos.y - npos.y);
            float3 hit = lerp(pos, npos, f);
            float rh = length(hit.xz);
            if (rh > rin * 0.95 && rh < rout) {
                float dens = diskDensity(rh, rin, rout);
                float phi = atan2(hit.z, hit.x);
                // Two layers spinning rigidly at different speeds: it reads as differential
                // rotation without the streaks stretching forever
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

    // ---- Background, ring and glow -------------------------------------------------------------
    float3 col = disk;
    float pa = k / minDim;
    // Stars are at infinity: with the camera this close, full lensing would stretch the whole sky
    // into arcs. It applies fully next to the shadow (Einstein ring) and fades outwards. This is
    // an artistic choice (spec, section 7).
    float wl = exp(-max(b - 1.25 * bc, 0.0) / (0.5 * max(bc, 0.5)));
    float3 sdir = normalize(lerp(dir0, dir, wl));
    col += trans * (1.0 - shadow) * starField(sdir, t, pa);

    // Photon ring: it is light from the disk itself that went around the black hole, so it takes
    // the disk's Doppler, color and streaks. It hugs the shadow edge and fades outwards; inwards
    // it stops at the same soft shadow edge.
    float lenP = length(p);
    float cosA = lenP > 1e-4 ? -p.x / lenP : 0.0;               // +1 on the left (approaching)
    float betaR = min(0.5 * doppler_strength, 0.9);             // speed of the disk's inner edge
    float gR = sqrt(1.0 - betaR * betaR) / (1.0 - betaR * cosA);
    float angR = atan2(p.y, p.x);
    float nR = vnoise(float2((angR + rotA) * 24.0 / TAU, 3.0), 24.0);
    float wR = max(0.01 * bc, pxb);
    float edge = 1.0 - shadow;
    float ring = edge * exp(-max(b - bc, 0.0) / wR);
    // The image with one turn less: a fainter line a little further out
    ring += 0.3 * exp(-pow((b - (bc + 4.0 * wR)) / (0.7 * wR), 2.0));
    float3 ringCol = diskRamp(0.8 * gR);
    col += trans * ringCol * ring * disk_brightness * 1.4 * (gR * gR * gR) * (0.55 + 0.9 * nR);

    float halo = edge * exp(-max(b - bc, 0.0) / (0.12 * bc));
    col += glow_intensity * (haze * edge + diskRamp(0.55 * gR) * halo * 0.35 * disk_brightness * (gR * gR * gR));

    // ---- Output ----------------------------------------------------------------------------------
    col = filmic(col * exposure * 0.8);
    col = pow(col, 1.0 / 2.2);
    // Triangular dithering against banding, only where there is light: the center stays pure black
    float2 px = v_in.uv * uv_size;
    float dither = (hash12(px) + hash12(px + 71.3) - 1.0) / 255.0;
    float lit = max(col.r, max(col.g, col.b)) > 0.5 / 255.0 ? 1.0 : 0.0;
    col = saturate(col + dither * lit);
    return float4(col, 1.0);
}
