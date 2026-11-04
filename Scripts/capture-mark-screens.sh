#!/bin/bash
# Prepared only: capture-owner GO and its concrete guard are required before use.
set -eu
exec python3 - "$@" <<'PY'
import argparse, datetime, hashlib, json, pathlib, plistlib, re, signal, struct, subprocess, sys, time

p = argparse.ArgumentParser(description="Prepare simulator evidence for both OpenGlasses mark contexts.",
    epilog="""PREPARED ONLY; capture execution is unverified. Do not run directly while the
capture-owner guard is pending. Obtain explicit prior capture GO from for-iCommon
and invoke through its supplied guard. Lane ownership is a separate check; this
script neither grants capture GO nor implements/bypasses that external guard.
Requires an already Booted, assigned OpenGlasses iPhone/iPad on the Mac mini.
Installs the supplied simulator .app, changes appearance temporarily, and captures
launch/home PNGs using lane-wrapped simctl only. Never builds, boots, creates,
shuts down, publishes, sends, or starts automatically. Output must be a NEW directory.
Source/package SHAs are caller assertions requiring corresponding build evidence.
The splash lasts 2 seconds; late captures exit 3 and remain unverified. All images
remain unreviewed until inspected for the intended scene, mark and permission UI.
Startup can request location permission; handle it before the approved run.
Exit 0 means four PNGs collected within timing bounds, not approved screenshots.
""", formatter_class=argparse.RawDescriptionHelpFormatter)
for flag, help_text in (("app-path", "Built simulator .app to install"),
    ("udid", "Explicit assigned, already Booted iPhone/iPad UUID"),
    ("source-sha", "Full source commit SHA used for the build"),
    ("common-version", "Resolved ForITCommon semantic version"),
    ("common-sha", "Full resolved ForITCommon commit SHA"), ("output", "New local directory; must not exist")):
    p.add_argument("--" + flag, required=True, help=help_text)
p.add_argument("--phase", required=True, choices=("before", "after"))
a = p.parse_args()
for name, value in (("source-sha", a.source_sha), ("common-sha", a.common_sha)):
    if not re.fullmatch(r"(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})", value):
        p.error("--" + name + " must be a full hexadecimal commit SHA")
if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", a.udid):
    p.error("--udid must be an explicit simulator UUID")
if not re.fullmatch(r"v?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.+-]+)?", a.common_version):
    p.error("--common-version must be a resolved semantic version")
app, out = pathlib.Path(a.app_path).expanduser().resolve(), pathlib.Path(a.output).expanduser().resolve()
if not app.is_dir() or app.suffix != ".app" or not (app / "Info.plist").is_file():
    p.error("--app-path must be a built .app directory with Info.plist")
if out.exists(): p.error("--output must be a new directory that does not exist")
if app == out or app in out.parents:
    p.error("--output must be outside the app bundle")
try:
    with (app / "Info.plist").open("rb") as stream: info = plistlib.load(stream)
except (OSError, ValueError): p.error("cannot read the app Info.plist")
bundle, udid = "com.forit.openglasses.dolores", a.udid.upper()
if info.get("CFBundleIdentifier") != bundle: p.error("the supplied app is not OpenGlasses")
if info.get("DTPlatformName") != "iphonesimulator" and "iPhoneSimulator" not in info.get("CFBundleSupportedPlatforms", []):
    p.error("the app must be built for the iOS simulator")
exename = info.get("CFBundleExecutable", "")
if not exename or pathlib.Path(exename).name != exename or not (app / exename).is_file():
    p.error("the app executable is missing or invalid")
helper = pathlib.Path("/Users/Shared/ci-sim/ci-sim-lane.sh")
if sys.platform != "darwin" or not helper.is_file(): p.error("run on the Mac mini with its current lane helper")

def lane(*parts):
    try:
        r = subprocess.run([str(helper), "--lane", "OpenGlasses", *parts], capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired) as e: raise RuntimeError("lane command unavailable or timed out") from e
    if r.returncode: raise RuntimeError("lane " + parts[0] + " failed (exit %d)" % r.returncode)
    return r.stdout.strip()
def sim(*parts): return lane("simctl", *parts)
def utc(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""): h.update(block)
    return h.hexdigest()

try:
    if lane("owner", udid) != "OpenGlasses": raise RuntimeError("device is not assigned to OpenGlasses")
    lane("check", udid)
    inventory = json.loads(sim("list", "--json"))
    matches = [(rid, d) for rid, devices in inventory["devices"].items() for d in devices if d.get("udid", "").upper() == udid]
    if len(matches) != 1: raise RuntimeError("assigned device not uniquely found")
    rid, device = matches[0]
    dtype = device.get("deviceTypeIdentifier", "")
    if not any(dtype.startswith("com.apple.CoreSimulator.SimDeviceType." + kind) for kind in ("iPhone-", "iPad-")):
        raise RuntimeError("assigned device must be an iPhone or iPad")
    if device.get("state") != "Booted" or not device.get("isAvailable", False): raise RuntimeError("assigned device is not Booted/available")
    runtime = next((r for r in inventory["runtimes"] if r.get("identifier") == rid), None)
    if runtime is None or ".iOS-" not in rid: raise RuntimeError("device has no known iOS runtime")
    original = sim("ui", udid, "appearance").lower()
    if original not in ("light", "dark"): raise RuntimeError("original appearance is unknown")
except (RuntimeError, ValueError, KeyError) as e: sys.exit("capture refused: " + str(e))

try: out.mkdir(parents=True, exist_ok=False)
except OSError: p.error("cannot create --output exclusively; use a new directory that does not exist")
meta = {"schema_version": 1, "verification": "unreviewed", "created_utc": utc(), "phase": a.phase,
    "source_sha": a.source_sha.lower(), "forit_common": {"version": a.common_version, "sha": a.common_sha.lower()},
    "source_package_identity": "caller-provided; binary correspondence requires build evidence",
    "app": {"bundle_id": bundle, "path": str(app), "executable_sha256": digest(app / exename),
            "version": info.get("CFBundleShortVersionString"), "build": info.get("CFBundleVersion")},
    "device": {"udid": udid, "name": device.get("name"), "type": dtype, "state_checked": "Booted",
               "owner_checked": "OpenGlasses", "checked_utc": utc()},
    "runtime": {"identifier": rid, "version": runtime.get("version"), "build": runtime.get("buildversion")},
    "method": "ci-sim-lane.sh --lane OpenGlasses simctl io screenshot --type=png",
    "original_appearance": original, "images": [], "collection_complete": False}
def save():
    temporary = out / ".PROVENANCE.json.tmp"
    temporary.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    temporary.replace(out / "PROVENANCE.json")
def capture(appearance, scene, launched):
    path = out / (a.phase + "-" + appearance + "-" + scene + ".png")
    started = time.monotonic()
    sim("io", udid, "screenshot", "--type=png", str(path))
    completed = time.monotonic()
    with path.open("rb") as stream: header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR": raise RuntimeError("output is not a PNG")
    width, height = struct.unpack(">II", header[16:24])
    if not width or not height: raise RuntimeError("PNG dimensions are invalid")
    meta["images"].append({"file": path.name, "sha256": digest(path), "width": width, "height": height,
        "appearance": appearance, "scene": scene, "captured_utc": utc(), "method": meta["method"], "verification": "unreviewed",
        "capture_started_seconds_after_launch_invocation": round(started - launched, 6),
        "capture_completed_seconds_after_launch_invocation": round(completed - launched, 6),
        "timing_verified": completed - launched < 2.0 if scene == "launch" else None})
    save()

failure, launched_app, cleanup_errors = None, False, 0
save()
signals = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)
def interrupt(signum, frame): raise RuntimeError("interrupted by " + signal.Signals(signum).name)
try:
    for signum in signals: signal.signal(signum, interrupt)
    sim("install", udid, str(app))
    for appearance in ("light", "dark"):
        sim("ui", udid, "appearance", appearance)
        if sim("ui", udid, "appearance").lower() != appearance: raise RuntimeError("appearance mismatch")
        launched, launched_app = time.monotonic(), True
        sim("launch", "--terminate-running-process", udid, bundle, "-doloresAPIKey", "screenshot-only", "-listeningEnabled", "NO")
        time.sleep(0.65)  # Let the 0.6s fade-in run; onAppear can start after launch invocation.
        capture(appearance, "launch", launched)
        time.sleep(3.0)
        capture(appearance, "home", launched)
    meta["collection_complete"] = True
except (RuntimeError, OSError, ValueError) as e: failure, meta["error"] = str(e), str(e)
finally:
    # A second termination signal must not interrupt the bounded cleanup/save.
    for signum in signals: signal.signal(signum, signal.SIG_IGN)
    if launched_app:
        try: sim("terminate", udid, bundle)
        except RuntimeError: cleanup_errors += 1
    try: sim("ui", udid, "appearance", original)
    except RuntimeError: cleanup_errors += 1
    meta.update(cleanup_errors=cleanup_errors, finished_utc=utc())
    save()
unverified = sum(image["timing_verified"] is False for image in meta["images"])
print("pngs=%d unreviewed=%d timing_unverified=%d cleanup_errors=%d" % (len(meta["images"]), len(meta["images"]), unverified, cleanup_errors))
if failure: sys.exit("capture failed: " + failure)
if unverified or cleanup_errors: sys.exit(3)
PY
