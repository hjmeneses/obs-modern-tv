"""Pruebas de aceptación de gargantua.shader (docs/gargantua-spec.md, sección 10).

Arma una escena temporal en OBS con una fuente de color y el shader como filtro, la pone al aire
unos segundos, captura por obs-websocket y mide. Al terminar regresa a la escena que estaba al aire
y borra todo lo que creó. No corre si OBS está transmitiendo o grabando.

La contraseña de obs-websocket se lee de la configuración de OBS en el momento y nunca se imprime.

Requisitos: OBS abierto con obs-websocket y obs-shaderfilter; Python con websocket-client, Pillow y numpy.

    python tools/gargantua_tests.py                 # todas
    python tools/gargantua_tests.py AC01 AC04       # algunas
    python tools/gargantua_tests.py --shader en/gargantua.shader --out capturas

Acceptance tests for gargantua.shader. They build a temporary scene in OBS, capture it through
obs-websocket and measure; everything they create is removed at the end.
"""
import argparse, base64, hashlib, io, json, os, subprocess, sys, tempfile, time, uuid

import numpy as np
import websocket
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENE = "TEST Gargantua"
SOURCE = "TEST Gargantua fondo"
FILTER = "Gargantua"

# Valores por defecto de la spec (sección 6)
DEFAULTS = {
    "black_hole_radius": 0.22, "disk_inner_radius": 1.15, "disk_outer_radius": 2.8, "disk_thickness": 0.12,
    "inclination": 8.0, "rotation_speed": 0.35, "doppler_strength": 1.0, "lensing_strength": 1.0,
    "disk_brightness": 1.2, "glow_intensity": 0.8, "star_density": 0.5, "exposure": 1.0, "quality_steps": 64,
    "background": 0, "center_x": 0.0, "center_y": 0.0, "show_disk": True, "lens_reach": 0.5,
}


# ------------------------------------------------------------------------------ obs-websocket
class OBS:
    def __init__(self):
        cfg_path = os.path.join(os.environ["APPDATA"], "obs-studio", "plugin_config", "obs-websocket", "config.json")
        cfg = json.load(open(cfg_path, encoding="utf-8"))
        self.ws = websocket.create_connection(f"ws://127.0.0.1:{cfg['server_port']}", timeout=60)
        hello = json.loads(self.ws.recv())["d"]
        ident = {"rpcVersion": 1}
        auth = hello.get("authentication")
        if auth:
            secret = base64.b64encode(hashlib.sha256((cfg["server_password"] + auth["salt"]).encode()).digest()).decode()
            ident["authentication"] = base64.b64encode(hashlib.sha256((secret + auth["challenge"]).encode()).digest()).decode()
        self.ws.send(json.dumps({"op": 1, "d": ident}))
        json.loads(self.ws.recv())

    def call(self, req, **data):
        rid = str(uuid.uuid4())
        self.ws.send(json.dumps({"op": 6, "d": {"requestType": req, "requestId": rid, "requestData": data}}))
        while True:
            m = json.loads(self.ws.recv())
            if m["op"] == 7 and m["d"]["requestId"] == rid:
                st = m["d"]["requestStatus"]
                if not st["result"]:
                    raise RuntimeError(f"{req}: {st.get('code')} {st.get('comment')}")
                return m["d"].get("responseData", {})


# ------------------------------------------------------------------------------ escena de prueba
class Rig:
    def __init__(self, obs, shader, out, pattern=None, **overrides):
        self.o, self.shader, self.out, self.pattern = obs, shader, out, pattern
        self.size = (1920, 1080)
        self.settings = dict(DEFAULTS, **overrides)

    def __enter__(self):
        o = self.o
        if o.call("GetStreamStatus")["outputActive"] or o.call("GetRecordStatus")["outputActive"]:
            sys.exit("OBS está transmitiendo o grabando: no se corren las pruebas.")
        self.back = o.call("GetCurrentProgramScene")["sceneName"]
        self._remove()
        o.call("CreateScene", sceneName=SCENE)
        if self.pattern:   # modo escena: una imagen de prueba en lugar del color negro
            o.call("CreateInput", sceneName=SCENE, inputName=SOURCE, inputKind="image_source",
                   inputSettings={"file": self.pattern.replace("\\", "/")}, sceneItemEnabled=True)
        else:
            o.call("CreateInput", sceneName=SCENE, inputName=SOURCE, inputKind="color_source_v3",
                   inputSettings={"color": 0xFF000000, "width": 1920, "height": 1080}, sceneItemEnabled=True)
        o.call("CreateSourceFilter", sourceName=SOURCE, filterName=FILTER, filterKind="shader_filter",
               filterSettings={"from_file": True, "shader_file_name": self.shader.replace("\\", "/"), **self.settings})
        o.call("SetCurrentProgramScene", sceneName=SCENE)
        time.sleep(2.0)
        return self

    def __exit__(self, *exc):
        try:
            self.o.call("SetCurrentProgramScene", sceneName=self.back)
        finally:
            self._remove()

    def _remove(self):
        # Primero el filtro: una fuente con filtros puede quedar viva si algún dock la sostiene
        for req, kw in (("RemoveSourceFilter", {"sourceName": SOURCE, "filterName": FILTER}),
                        ("RemoveInput", {"inputName": SOURCE}), ("RemoveScene", {"sceneName": SCENE})):
            try:
                self.o.call(req, **kw)
            except RuntimeError:
                pass

    def set(self, wait=1.0, **kw):
        self.settings.update(kw)
        self.o.call("SetSourceFilterSettings", sourceName=SOURCE, filterName=FILTER, filterSettings=kw)
        time.sleep(wait)

    def enable(self, on, wait=1.0):
        self.o.call("SetSourceFilterEnabled", sourceName=SOURCE, filterName=FILTER, filterEnabled=on)
        time.sleep(wait)

    def resize(self, w, h, wait=1.5):
        self.size = (w, h)
        self.o.call("SetInputSettings", inputName=SOURCE, inputSettings={"width": w, "height": h})
        time.sleep(wait)

    def grab(self, width=None):
        w = width or self.size[0]
        d = self.o.call("GetSourceScreenshot", sourceName=SOURCE, imageFormat="png", imageWidth=w)["imageData"]
        return np.asarray(Image.open(io.BytesIO(base64.b64decode(d.split(",", 1)[1]))).convert("RGB")).astype(np.float32)

    def save(self, img, name):
        Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(os.path.join(self.out, name + ".png"))

    # Geometría de la spec: centro del agujero, radio de la sombra = black_hole_radius × lado corto
    def geometry(self, img):
        h, w = img.shape[:2]
        R = self.settings["black_hole_radius"] * min(w, h)
        cx = w / 2 + self.settings["center_x"] * w
        cy = h / 2 - self.settings["center_y"] * h
        yy, xx = np.mgrid[0:h, 0:w]
        return (xx - cx + 0.5) / R, (cy - yy - 0.5) / R      # en radios de sombra; y hacia arriba


def lum(img):
    return img @ np.array([0.2126, 0.7152, 0.0722], np.float32)


# ------------------------------------------------------------------------------ pruebas
# Franja donde cae el arco del disco por encima de la sombra (en radios de sombra)
def arc_band(x, y):
    return (y > 1.15) & (y < 1.9) & (np.abs(x) < 0.4)


def ac01(r):
    img = r.grab(); r.save(img, "AC01_defecto")
    x, y = r.geometry(img); L = lum(img); d = np.hypot(x, y)
    top_shadow = L[(d < 0.8) & (y > 0)]
    # El arco se mide sin glow: la neblina sola no debe bastar para pasar
    r.set(glow_intensity=0.0); bare = r.grab(); r.set(glow_intensity=DEFAULTS["glow_intensity"])
    # Percentil 90: la franja incluye el hueco oscuro entre el anillo y el arco
    p90 = np.percentile(lum(bare)[arc_band(x, y)], 90)
    ok = top_shadow.max() <= 0.0 and p90 >= 120
    return ok, f"sombra arriba max={top_shadow.max():.1f}/255 (=0); arco sobre la sombra sin glow p90={p90:.1f} (>=120)"


def ac02(r):
    img = r.grab(); x, y = r.geometry(img); L = lum(img)
    side = (np.abs(x) > 1.1) & (np.abs(x) < 2.6) & (np.abs(y) < 0.35)
    left, right = L[side & (x < 0)].mean(), L[side & (x > 0)].mean()
    ratio = max(left, right) / max(min(left, right), 1e-3)
    return ratio >= 1.5, f"izquierda={left:.1f} derecha={right:.1f} razón={ratio:.2f} (>=1.5)"


def disk_zone(r, img):
    x, y = r.geometry(img); d = np.hypot(x, y)
    return (np.abs(y) < 0.45) & (d > 1.15) & (d < 2.6)


def ac03(r, seconds=60.0):
    r.set(rotation_speed=DEFAULTS["rotation_speed"])
    prev, t_prev, rates = None, None, []
    t_end = time.time() + seconds
    while time.time() < t_end:
        img = r.grab(960); t = time.time()
        z = disk_zone(r, img)
        if prev is not None:
            rates.append(np.abs(img[z] - prev[z]).mean() / (t - t_prev))
        prev, t_prev = img, t
    rates = np.array(rates); med = float(np.median(rates))
    ok = med > 0.5 and rates.max() <= 3 * med
    return ok, f"{len(rates)} pares en {seconds:.0f} s; cambio/s mediana={med:.2f} (>0.5) máx={rates.max():.2f} (<= 3×mediana)"


def ac04(r):
    r.set(glow_intensity=0.0)
    r.set(lensing_strength=0.0); a = r.grab(); r.save(a, "AC04_lente0")
    r.set(lensing_strength=1.0); b = r.grab(); r.save(b, "AC04_lente1")
    r.set(glow_intensity=DEFAULTS["glow_intensity"])
    x, y = r.geometry(a)
    band = arc_band(x, y)
    la, lb = np.percentile(lum(a)[band], 90), np.percentile(lum(b)[band], 90)
    diff = np.abs(a - b).mean()
    ok = la < 20 and lb >= 120 and diff >= 8
    return ok, f"arco sobre la sombra (sin glow) p90: lente0={la:.1f} (<20) lente1={lb:.1f} (>=120); diferencia media={diff:.1f} (>=8)"


def ac05(r):
    r.set(rotation_speed=0.0, wait=1.5)
    a = r.grab(); time.sleep(2.0); b = r.grab()
    x, y = r.geometry(a); d = np.hypot(x, y)
    zd = disk_zone(r, a)
    stars = (d > 3.2) & (np.abs(y) > 0.6)
    glow = (d > 1.0) & (d < 1.6) & (y > 0.6)
    dd, ds_ = np.abs(a[zd] - b[zd]).mean(), np.abs(a[stars] - b[stars]).mean()
    g = lum(b)[glow].mean()
    r.set(rotation_speed=DEFAULTS["rotation_speed"])
    ok = dd <= 0.3 and ds_ > 0.02 and g >= 15
    return ok, f"disco cambia={dd:.3f} (<=0.3); estrellas cambian={ds_:.3f} (>0.02); glow={g:.1f} (>=15)"


def gpu_ms(seconds=6.0):
    """Milisegundos de GPU (motor 3D) por cuadro que usa OBS, promedio en `seconds`."""
    ps = ("$p=(Get-Process obs64).Id; $s=Get-Counter \"\\GPU Engine(pid_${p}_*engtype_3D)\\Utilization Percentage\" "
          f"-SampleInterval 1 -MaxSamples {int(seconds)}; "
          "($s | % { ($_.CounterSamples | Measure-Object CookedValue -Sum).Sum } | Measure-Object -Average).Average")
    util = float(subprocess.check_output(["pwsh", "-NoProfile", "-Command", ps], text=True).strip().replace(",", "."))
    return util


def ac06(r):
    vs = r.o.call("GetVideoSettings"); frame_ms = 1000.0 * vs["fpsDenominator"] / vs["fpsNumerator"]
    res = {}
    for label, steps in (("base", None), ("64", 64), ("32", 32)):
        if steps is None:
            r.enable(False, wait=2.0)
        else:
            r.enable(True); r.set(quality_steps=steps, wait=2.0)
        s0 = r.o.call("GetStats")["renderSkippedFrames"]
        util = gpu_ms()
        res[label] = (util * frame_ms / 100.0, r.o.call("GetStats")["renderSkippedFrames"] - s0)
    r.set(quality_steps=DEFAULTS["quality_steps"])
    d64, d32 = res["64"][0] - res["base"][0], res["32"][0] - res["base"][0]
    skip_ok = all(res[k][1] <= max(2, 2 * res["base"][1]) for k in ("64", "32"))
    ok = d64 < 8.0 and d32 < 5.0 and skip_ok
    return ok, (f"GPU agregada: 64 pasos={d64:.2f} ms (<8), 32 pasos={d32:.2f} ms (<5); "
                f"saltados base/64/32={res['base'][1]}/{res['64'][1]}/{res['32'][1]}")


def blur(a, sigma):
    k = np.exp(-0.5 * (np.arange(-3 * int(sigma), 3 * int(sigma) + 1) / sigma) ** 2)
    k /= k.sum()
    a = np.apply_along_axis(lambda v: np.convolve(v, k, mode="same"), 1, a)
    return np.apply_along_axis(lambda v: np.convolve(v, k, mode="same"), 0, a)


def ac07(r):
    """Banding: en un degradado lento sin dithering, los pixeles vecinos caen casi siempre en el
    mismo valor de 8 bits (escalones anchos); con dithering, mucho menos. Se mide sin estrellas y
    sin giro, en las zonas que cambian entre 0.05 y 0.3 niveles por pixel. Validada: con dithering
    da ~0.27 y con una copia sin dithering ~0.68."""
    r.set(rotation_speed=0.0, star_density=0.0, wait=1.5)
    img = r.grab(); r.save(img, "AC07_sin_estrellas")
    r.set(rotation_speed=DEFAULTS["rotation_speed"], star_density=DEFAULTS["star_density"])
    L = lum(img); G = blur(L, 3.0)
    gy, gx = np.gradient(G); grad = np.hypot(gx, gy)
    x, y = r.geometry(img); d = np.hypot(x, y)
    mask = (G > 6) & (G < 200) & (grad > 0.05) & (grad < 0.3) & (d > 1.0)
    m2 = mask[:, 1:] & mask[:, :-1]
    q = np.clip(img, 0, 255).astype(np.uint8)
    same = np.all(q[:, 1:] == q[:, :-1], axis=2)[m2]
    if same.size < 5000:
        return False, f"muy pocos pixeles de degradado lento para medir ({same.size})"
    frac = float(same.mean())
    return frac <= 0.45, f"vecinos idénticos en degradados lentos={frac:.2f} (<=0.45) en {same.size} pares"


def ac08(r):
    r.set(rotation_speed=0.0, wait=1.0)
    native = r.grab(); r.save(native, "AC08_1080")
    r.resize(3840, 2160)
    big = r.grab(3840)
    ref = big.reshape(1080, 2, 1920, 2, 3).mean(axis=(1, 3)); r.save(ref, "AC08_referencia_4k")
    r.resize(1920, 1080); r.set(rotation_speed=DEFAULTS["rotation_speed"])
    x, y = r.geometry(native); d = np.hypot(x, y)
    ring = (d > 0.95) & (d < 1.15)
    diff = np.abs(native[ring] - ref[ring]).mean()
    return diff <= 6.0, f"anillo 1080p contra referencia 4K reducida: diferencia media={diff:.2f}/255 (<=6)"


# ------------------------------------------------------------------------------ modo escena (AC09–AC12)
MAGENTA = (255, 0, 255)


def make_pattern(path, w=1920, h=1080, R=0.22 * 1080):
    """Imagen de prueba: degradado con cuadros (detalle en todas partes) y un disco magenta en el
    centro, del tamaño de un tercio de la sombra: queda tapado por el agujero y solo puede verse si
    el lente lo trae al anillo de Einstein. El resto de la imagen nunca es magenta ni negro."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    check = ((xx // 48 + yy // 48) % 2).astype(np.float32)
    img = np.stack([40 + 160 * xx / w, 90 + 130 * yy / h, 40 + 60 * check], axis=2)
    img[np.hypot(xx - w / 2 + 0.5, yy - h / 2 + 0.5) < R / 3] = MAGENTA
    Image.fromarray(img.astype(np.uint8)).save(path)


def is_magenta(img):
    return (img[..., 0] > 180) & (img[..., 1] < 70) & (img[..., 2] > 180)


def ac09(r):
    """Fuera del agujero la escena sale idéntica: sin lente en todo el cuadro; con lente y el alcance
    al mínimo, a más de 3 radios. Con el alcance por defecto solo se informa (a 4.5 radios el
    desvío todavía es de ~1 pixel, a propósito)."""
    r.set(show_disk=False, lensing_strength=0.0, wait=1.5)
    a = r.grab(); r.save(a, "AC09_lente0")
    r.enable(False, wait=1.5); ref = r.grab(); r.enable(True, wait=1.0)
    x, y = r.geometry(a); d = np.hypot(x, y)
    m0 = np.abs(a - ref).max(axis=2)[d > 0.5].max()
    r.set(lensing_strength=1.0, lens_reach=0.1, wait=1.5)
    b = r.grab(); r.save(b, "AC09_alcance_min")
    diff = np.abs(b - ref).max(axis=2)[d > 3.0]
    r.set(lens_reach=DEFAULTS["lens_reach"], wait=1.5)
    c = r.grab(); r.save(c, "AC09_alcance_defecto")
    info = np.abs(c - ref).max(axis=2)[d > 4.5].mean()
    r.set(show_disk=True)
    ok = m0 <= 2 and np.percentile(diff, 99) <= 3 and diff.mean() <= 0.5
    return ok, (f"sin lente: diferencia max={m0:.0f}/255 (<=2); alcance mínimo a >3 radios: "
                f"p99={np.percentile(diff, 99):.1f} (<=3) media={diff.mean():.2f} (<=0.5); "
                f"alcance por defecto a >4.5 radios: media={info:.2f} (informativo)")


def ac10(r):
    """La sombra es negro puro sobre la escena: sin disco, toda; con disco, la mitad de arriba (en la
    de abajo pasa el disco por delante, igual que en AC01)."""
    out = []
    for disk in (True, False):
        r.set(show_disk=disk, wait=1.5)
        img = r.grab(); r.save(img, f"AC10_disco_{int(disk)}")
        x, y = r.geometry(img)
        zone = (np.hypot(x, y) < 0.8) & ((y > 0) if disk else True)
        out.append(lum(img)[zone].max())
    r.set(show_disk=True)
    return max(out) <= 0.0, f"sombra max con disco={out[0]:.1f} sin disco={out[1]:.1f} (=0)"


def ac11(r):
    """Anillo de Einstein: el magenta del centro, tapado por la sombra, aparece alrededor."""
    r.set(show_disk=False, wait=1.5)
    img = r.grab(); r.save(img, "AC11_anillo_einstein")
    r.enable(False, wait=1.5); ref = r.grab(); r.enable(True, wait=1.0)
    r.set(show_disk=True)
    x, y = r.geometry(img); d = np.hypot(x, y)
    ann = (d > 1.0) & (d < 2.5)
    frac, frac_ref = is_magenta(img)[ann].mean(), is_magenta(ref)[ann].mean()
    far = is_magenta(img)[d > 4.0].mean()
    ok = frac >= 0.03 and frac_ref == 0 and far == 0
    return ok, (f"magenta en 1–2.5 radios={frac:.3f} (>=0.03; sin filtro={frac_ref:.0f}); "
                f"lejos={far:.0f} (=0)")


def ac12(r):
    """Posición: la sombra sigue a Posición X/Y y el centro de la pantalla deja ver la escena."""
    r.set(center_x=0.25, center_y=0.15, show_disk=False, wait=1.5)
    img = r.grab(); r.save(img, "AC12_posicion")
    x, y = r.geometry(img); d = np.hypot(x, y)
    shadow = lum(img)[d < 0.8].max()
    h, w = img.shape[:2]; yy, xx = np.mgrid[0:h, 0:w]
    middle = lum(img)[np.hypot(xx - w / 2, yy - h / 2) < 20].mean()
    r.set(center_x=0.0, center_y=0.0, show_disk=True)
    ok = shadow <= 0.0 and middle > 20
    return ok, f"sombra en (0.25, 0.15) max={shadow:.1f} (=0); centro de la pantalla={middle:.1f} (>20)"


TESTS = {"AC01": ac01, "AC02": ac02, "AC03": ac03, "AC04": ac04, "AC05": ac05, "AC06": ac06, "AC07": ac07, "AC08": ac08}
SCENE_TESTS = {"AC09": ac09, "AC10": ac10, "AC11": ac11, "AC12": ac12}


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("tests", nargs="*", help="AC01 … AC12 (por defecto todas)")
    ap.add_argument("--shader", default="gargantua.shader", help="ruta relativa al repo o absoluta")
    ap.add_argument("--out", default=os.path.join(tempfile.gettempdir(), "gargantua-tests"), help="carpeta de capturas")
    ap.add_argument("--seconds", type=float, default=60.0, help="duración de AC03")
    a = ap.parse_args()
    shader = a.shader if os.path.isabs(a.shader) else os.path.join(ROOT, a.shader)
    if not os.path.exists(shader):
        sys.exit(f"No existe {shader}")
    os.makedirs(a.out, exist_ok=True)
    names = [t.upper() for t in a.tests] or list(TESTS) + list(SCENE_TESTS)
    failed = 0
    obs = OBS()

    def run(r, group):
        nonlocal failed
        for n in [n for n in names if n in group]:
            try:
                ok, detail = group[n](r, a.seconds) if n == "AC03" else group[n](r)
            except Exception as e:  # una prueba rota no detiene las demás
                ok, detail = False, f"error: {e}"
            failed += not ok
            print(f"[{'PASA' if ok else 'FALLA'}] {n}  {detail}", flush=True)

    if any(n in TESTS for n in names):
        with Rig(obs, shader, a.out) as r:
            run(r, TESTS)
    if any(n in SCENE_TESTS for n in names):
        pattern = os.path.join(a.out, "patron.png")
        make_pattern(pattern)
        with Rig(obs, shader, a.out, pattern=pattern, background=1) as r:
            run(r, SCENE_TESTS)
    print(f"\nCapturas en {a.out}")
    print("Todo pasa" if not failed else f"{failed} prueba(s) fallan")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
