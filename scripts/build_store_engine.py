#!/usr/bin/env python3
"""Build an isolated macOS 14 engine; never install into /Library or Homebrew."""
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import sys

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / "Config/store-runtime-lock.json").read_text())
VENDOR = ROOT / "Vendor/StoreGStreamer"
PREFIX = VENDOR / "prefix"


def run(args, **kwargs):
    subprocess.run(list(map(str, args)), check=True, **kwargs)


def fingerprint():
    digest = hashlib.sha256()
    for path in [Path(__file__), ROOT / "Config/store-runtime-lock.json",
                 ROOT / "scripts/patch_uxplay.py", *sorted((ROOT / "scripts/patches").glob("macos_window.*"))]:
        digest.update(path.read_bytes())
    return digest.hexdigest()


def main():
    VENDOR.mkdir(parents=True, exist_ok=True)
    engine = ROOT / "Vendor/bin/uxplay-store"
    provenance = engine.with_suffix(".json")
    if "--if-needed" in sys.argv and engine.exists() and provenance.exists():
        previous = json.loads(provenance.read_text())
        if previous.get("fingerprint") == fingerprint() and previous.get("sha256") == hashlib.sha256(engine.read_bytes()).hexdigest():
            print("Compatible Store engine cache verified.")
            return
    for name, record in LOCK["downloads"].items():
        path = VENDOR / name
        if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != record["sha256"]:
            run(["curl", "--fail", "--location", "--retry", "2", "--output", path, record["url"]])
        if hashlib.sha256(path.read_bytes()).hexdigest() != record["sha256"]:
            raise SystemExit(f"Checksum mismatch: {name}")
        if name.endswith(".pkg"):
            dest = VENDOR / ("development-unpack" if "devel" in name else "runtime-unpack")
            if not dest.exists():
                run(["pkgutil", "--expand-full", path, dest])

    # Component package payloads share one prefix. Skip the system framework symlinks.
    PREFIX.mkdir(exist_ok=True)
    sdk_fingerprint = hashlib.sha256(json.dumps(LOCK["downloads"], sort_keys=True).encode()).hexdigest()
    sdk_stamp = PREFIX / ".sdk-lock"
    if not sdk_stamp.exists() or sdk_stamp.read_text() != sdk_fingerprint:
        for kind in ["runtime-unpack", "development-unpack"]:
            for payload in sorted((VENDOR / kind).glob("*/Payload")):
                if payload.parent.name.startswith("osx-framework"):
                    continue
                run(["ditto", payload, PREFIX])
        sdk_stamp.write_text(sdk_fingerprint)
    for pc in (PREFIX / "lib/pkgconfig").glob("*.pc"):
        text = pc.read_text()
        text = re.sub(r"^prefix=.*$", lambda _: f"prefix={PREFIX}", text, flags=re.M)
        pc.write_text(text)

    env = os.environ.copy()
    env.update({"MACOSX_DEPLOYMENT_TARGET": LOCK["deployment_target"],
                "CFLAGS": "-arch arm64 -mmacosx-version-min=14.0 -O2",
                "CXXFLAGS": "-arch arm64 -mmacosx-version-min=14.0 -O2",
                "LDFLAGS": "-arch arm64 -mmacosx-version-min=14.0",
                "PKG_CONFIG_PATH": str(PREFIX / "lib/pkgconfig"),
                "PKG_CONFIG_LIBDIR": str(PREFIX / "lib/pkgconfig")})
    plist = VENDOR / ("libplist-" + LOCK["libplist"])
    if not plist.exists():
        run(["tar", "-xf", VENDOR / (plist.name + ".tar.bz2"), "-C", VENDOR])
    if not (PREFIX / "lib/libplist-2.0.a").exists():
        run(["./configure", f"--prefix={PREFIX}", "--disable-shared", "--enable-static",
             "--without-cython", "--without-tools", "--without-tests"], cwd=plist, env=env)
        run(["make", "-j", str(min(os.cpu_count() or 4, 8))], cwd=plist, env=env)
        run(["make", "install"], cwd=plist, env=env)

    source = ROOT / "Vendor/UxPlayStore"
    upstream = ROOT / "Vendor/UxPlay"
    if not (upstream / ".git").exists():
        run(["git", "clone", "--no-checkout", "https://github.com/FDH2/UxPlay.git", upstream])
    if subprocess.run(["git", "-C", str(upstream), "cat-file", "-e", LOCK["uxplay"]], capture_output=True).returncode:
        run(["git", "-C", upstream, "fetch", "origin", LOCK["uxplay"]])
    if source.exists():
        shutil.rmtree(source)
    source.mkdir()
    archive = subprocess.check_output(["git", "-C", str(ROOT / "Vendor/UxPlay"),
                                       "archive", LOCK["uxplay"]])
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
        bundle.extractall(source, filter="data")
    run(["python3", ROOT / "scripts/patch_uxplay.py", "--source", source])
    for cmake in [source / "lib/CMakeLists.txt", source / "renderers/CMakeLists.txt"]:
        text = cmake.read_text()
        # Upstream rewrites PKG_CONFIG_PATH to global installations. Keep the isolated prefix.
        text = "\n".join(line for line in text.splitlines()
                         if not re.search(r"set\s*\(\s*ENV\{PKG_CONFIG_PATH\}", line, re.I)) + "\n"
        cmake.write_text(text)
    build = ROOT / "build/StoreEngine"
    run(["cmake", "-S", source, "-B", build, "-DCMAKE_BUILD_TYPE=Release",
         "-DCMAKE_OSX_ARCHITECTURES=arm64", "-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0",
         f"-DCMAKE_PREFIX_PATH={PREFIX}", f"-DOPENSSL_ROOT_DIR={PREFIX}",
         f"-DLIBPLIST={PREFIX / 'lib/libplist-2.0.a'}",
         f"-DLIBCRYPTO={PREFIX / 'lib/libcrypto.a'}",
         "-DPKG_CONFIG_EXECUTABLE=/opt/homebrew/bin/pkgconf"], env=env)
    run(["cmake", "--build", build, "--parallel", str(min(os.cpu_count() or 4, 8))], env=env)
    dest = ROOT / "Vendor/bin/uxplay-store"
    dest.parent.mkdir(exist_ok=True)
    shutil.copy2(build / "uxplay", dest)
    dest.chmod(0o755)
    provenance.write_text(json.dumps({"fingerprint": fingerprint(),
                                     "sha256": hashlib.sha256(dest.read_bytes()).hexdigest()}) + "\n")
    print("Built macOS 14 Store engine with isolated GStreamer " + LOCK["gstreamer"], flush=True)


if __name__ == "__main__":
    main()
