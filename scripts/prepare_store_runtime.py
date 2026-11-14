#!/usr/bin/env python3
"""Xcode build phase: embed, constrain and sign the self-contained Store runtime."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
from build_store_engine import fingerprint

ROOT = Path(__file__).resolve().parents[1]


def run(args):
    subprocess.run(list(map(str, args)), check=True)


def main():
    app = Path(sys.argv[1]).resolve()
    identity = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else "-"
    source = ROOT / "Vendor/bin/uxplay-store"
    prefix = ROOT / "Vendor/StoreGStreamer/prefix"
    if not source.exists() or not prefix.exists():
        raise SystemExit("Run python3 scripts/build_store_engine.py before building AirMirrorStore.")
    provenance = source.with_suffix(".json")
    if not provenance.exists():
        raise SystemExit("Missing Store engine provenance; rebuild with scripts/build_store_engine.py.")
    recorded = json.loads(provenance.read_text())
    if recorded.get("fingerprint") != fingerprint() or recorded.get("sha256") != hashlib.sha256(source.read_bytes()).hexdigest():
        raise SystemExit("Store engine inputs changed; rebuild with scripts/build_store_engine.py.")
    helper = app / "Contents/MacOS/uxplay"
    helper.parent.mkdir(parents=True, exist_ok=True)
    # A previously signed helper may still have executable pages cached by macOS.
    # Replace its inode rather than modifying signed executable pages in place.
    helper.unlink(missing_ok=True)
    shutil.copy2(source, helper)
    helper.chmod(0o755)
    legacy = app / "Contents/Helpers/uxplay"
    if legacy.exists():
        legacy.unlink()
    run(["python3", ROOT / "scripts/bundle_runtime.py", app,
         "--runtime-prefix", prefix, "--helper-relative-path", "Contents/MacOS/uxplay",
         "--arch", "arm64", "--strict"])
    binaries = sorted((app / "Contents/Frameworks").glob("*.dylib"))
    binaries += sorted((app / "Contents/PlugIns/gstreamer").glob("*.dylib"))
    inventory = []
    for binary in [*binaries, helper]:
        build = subprocess.check_output(["vtool", "-show-build", str(binary)], text=True)
        minimums = re.findall(r"minos\s+(\S+)", build)
        if not minimums or any(tuple(map(int, version.split("."))) > (14, 0, 0) for version in minimums):
            raise SystemExit(f"Runtime does not support macOS 14: {binary.name}, {minimums}")
        args = ["codesign", "--force", "--sign", identity, "--options", "runtime", "--timestamp=none"]
        if binary == helper:
            args += ["--identifier", "com.liangyu.airmirror.uxplay",
                     "--entitlements", ROOT / "Config/UxPlayStore.entitlements"]
        run([*args, binary])
        inventory.append({"file": str(binary.relative_to(app)), "minimum_macos": minimums,
                          "sha256": hashlib.sha256(binary.read_bytes()).hexdigest()})
    resources = app / "Contents/Resources"
    resources.mkdir(exist_ok=True)
    lock = json.loads((ROOT / "Config/store-runtime-lock.json").read_text())
    license_root = resources / "ThirdPartyLicenses"
    if license_root.exists():
        shutil.rmtree(license_root)
    license_root.mkdir()
    sdk_licenses = prefix / "share/licenses"
    components = ["gstreamer-1.0", "gst-plugins-base-1.0", "gst-plugins-bad-1.0", "glib",
                  "libffi", "orc", "openssl", "ffmpeg", "bzip2", "pcre2", "proxy-libintl", "zlib"]
    notices = ["商店版无线运行时许可说明", "GStreamer SDK " + lock["gstreamer"],
               "实际二进制组件与版本见 StoreRuntimeInventory.json；完整许可文本随包保存在 ThirdPartyLicenses。",
               "SDK 的许可说明由上游提供，分发授权与对应源码交付条件仍须逐项核查。"]
    for name in components:
        source_license = sdk_licenses / name
        if not source_license.is_dir():
            raise SystemExit(f"Missing SDK license directory: {name}")
        shutil.copytree(source_license, license_root / name)
        readme = source_license / "README-LICENSE-INFO.txt"
        notices += ["\n" + name, readme.read_text() if readme.exists() else "许可全文见随包文件。"]
    for name, source_license in [
        ("libplist-LGPL.txt", ROOT / "Vendor/StoreGStreamer" / ("libplist-" + lock["libplist"]) / "COPYING"),
        ("llhttp-MIT.txt", ROOT / "Vendor/UxPlayStore/lib/llhttp/LICENSE-MIT")
    ]:
        shutil.copy2(source_license, license_root / name)
    shutil.copy2(prefix / "share/versions.txt", license_root / "SDKVersions.txt")
    (resources / "StoreRuntimeNotices.txt").write_text("\n\n".join(notices) + "\n")
    (resources / "StoreRuntimeInventory.json").write_text(json.dumps(
        {"versions": {key: value for key, value in lock.items() if key != "downloads"},
         "components": inventory}, indent=2) + "\n")
    print(f"Embedded and signed {len(inventory)} Store runtime binaries for macOS 14+.")


if __name__ == "__main__":
    main()
