#!/usr/bin/env python3
"""Fail closed on channel leaks, external runtime paths and invalid Store packaging."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess


def output(args):
    return subprocess.check_output(list(map(str, args)), stderr=subprocess.STDOUT, text=True)


def entitlements(binary):
    text = output(["codesign", "--display", "--entitlements", "-", "--xml", binary])
    start = text.find("<?xml")
    if start < 0:
        start = text.find("<plist")
    assert start >= 0, f"Missing entitlements: {binary}"
    return plistlib.loads(text[start:].encode())


def validate(app, distribution=False):
    contents = app / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    main = contents / "MacOS" / info["CFBundleExecutable"]
    data = main.read_bytes()
    for forbidden in [b"https://github.com/Terry1238832/AirMirror", b"api.github.com/repos/",
                      b"AXIsProcessTrusted", b"CGEventPost", b"/opt/homebrew", b"DYLD_FALLBACK_LIBRARY_PATH",
                      b"AIRMIRROR_STORE_DIAGNOSTICS"]:
        assert forbidden not in data, f"Store binary includes forbidden implementation: {forbidden!r}"
    wanted = {"com.apple.security.app-sandbox", "com.apple.security.network.client",
              "com.apple.security.network.server", "com.apple.security.device.camera",
              "com.apple.security.device.audio-input", "com.apple.security.device.usb"}
    signed = entitlements(app)
    assert all(signed.get(key) is True for key in wanted), signed
    assert not any("temporary-exception" in key or key == "com.apple.security.cs.disable-library-validation"
                   for key in signed), signed
    assert not signed.get("com.apple.security.get-task-allow"), signed
    helper = contents / "MacOS/uxplay"
    assert entitlements(helper) == {"com.apple.security.app-sandbox": True, "com.apple.security.inherit": True}
    files = [main, helper, *sorted((contents / "Frameworks").glob("*.dylib")),
             *sorted((contents / "PlugIns/gstreamer").glob("*.dylib"))]
    minimum = tuple((list(map(int, info["LSMinimumSystemVersion"].split("."))) + [0, 0])[:3])
    assert minimum == (14, 0, 0), info["LSMinimumSystemVersion"]
    report = []
    teams = set()
    for file in files:
        assert output(["lipo", "-archs", file]).strip() == "arm64", file
        build = output(["vtool", "-show-build", file])
        for version in re.findall(r"minos\s+(\S+)", build):
            parsed = tuple((list(map(int, version.split("."))) + [0, 0])[:3])
            assert parsed <= minimum, (file, version)
        deps = output(["otool", "-L", file]).splitlines()[1:]
        for line in deps:
            dep = line.strip().split(" (", 1)[0]
            assert "/PrivateFrameworks/" not in dep, (file, dep)
            if dep.startswith("/"):
                assert dep.startswith(("/System/Library/", "/usr/lib/")), (file, dep)
            elif dep.startswith("@rpath/"):
                name = Path(dep).name
                assert name == file.name or (contents / "Frameworks" / name).exists(), (file, dep)
        load = output(["otool", "-l", file])
        for match in re.finditer(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset", load):
            assert match.group(1).startswith(("@", "/usr/lib/swift", "/System/Library/")), (file, match.group(1))
        signature = output(["codesign", "-dvv", file])
        assert "runtime" in signature, (file, "Hardened Runtime missing")
        team = re.search(r"^TeamIdentifier=(\S+)$", signature, re.M)
        assert team and team.group(1) != "not", (file, "A real signing team is required for library validation")
        teams.add(team.group(1))
        if distribution:
            assert "Signature=adhoc" not in signature and "Authority=Apple Development:" not in signature, file
            assert re.search(r"Authority=(Apple Distribution|3rd Party Mac Developer Application):", signature), file
        report.append(str(file.relative_to(app)))
    assert len(teams) == 1, "Main app, helper and libraries must have the same signing team"
    for resource in ["PrivacyInfo.xcprivacy", "PrivacyPolicy.txt", "ThirdPartyNotices.txt",
                     "WindowPaste-LICENSE.txt", "UxPlay-LICENSE.txt", "StoreRuntimeInventory.json"]:
        assert (contents / "Resources" / resource).is_file(), resource
    assert (contents / "Resources/StoreRuntimeNotices.txt").is_file()
    assert (contents / "Resources/ThirdPartyLicenses/libplist-LGPL.txt").is_file()
    output(["codesign", "--verify", "--deep", "--strict", app])
    if distribution:
        assert (contents / "embedded.provisionprofile").is_file(), "Missing Store provisioning profile"
    return {"bundle_id": info["CFBundleIdentifier"], "minimum_macos": info["LSMinimumSystemVersion"],
            "binary_count": len(report), "distribution_signing_checked": distribution,
            "checked_binaries": report}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--distribution", action="store_true")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()
    result = validate(args.app.resolve(), args.distribution)
    if args.json:
        args.json.write_text(json.dumps(result, indent=2) + "\n")
    print(f"PASS: sandbox, Store channel, helper inheritance, {result['binary_count']} binaries, macOS 14 runtime closure")
