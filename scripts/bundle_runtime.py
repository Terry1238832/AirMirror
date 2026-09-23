#!/usr/bin/env python3
"""Copy Homebrew GStreamer and its libraries into the app bundle."""

import os
import shutil
import subprocess
import sys
from pathlib import Path

PLUGINS = [
    "libgstcoreelements.dylib",
    "libgstapp.dylib",
    "libgstlibav.dylib",
    "libgstplayback.dylib",
    "libgstautodetect.dylib",
    "libgstvideoparsersbad.dylib",
    "libgstaudioconvert.dylib",
    "libgstaudioresample.dylib",
    "libgstvolume.dylib",
    "libgstlevel.dylib",
    "libgstosxaudio.dylib",
    "libgsttypefindfunctions.dylib",
    "libgstaudioparsers.dylib",
]

SKIP_PREFIXES = ("/usr/lib/", "/System/")


def run(args):
    subprocess.run(args, check=True)


def otool_id(path: Path):
    out = subprocess.check_output(["otool", "-D", str(path)], text=True, errors="replace")
    lines = [line.strip() for line in out.splitlines() if line.strip()]
    return lines[1] if len(lines) >= 2 else None


def otool_deps(path: Path):
    out = subprocess.check_output(["otool", "-L", str(path)], text=True, errors="replace")
    deps = []
    for index, line in enumerate(out.splitlines()):
        if index == 0:
            continue
        line = line.strip()
        if not line:
            continue
        deps.append(line.split(" (", 1)[0].strip())
    return deps


def rpaths(path: Path):
    out = subprocess.check_output(["otool", "-l", str(path)], text=True, errors="replace")
    found = []
    lines = out.splitlines()
    for index, line in enumerate(lines):
        if "LC_RPATH" not in line:
            continue
        for follow in lines[index + 1 : index + 6]:
            follow = follow.strip()
            if follow.startswith("path "):
                found.append(follow.split(" (", 1)[0].removeprefix("path ").strip())
                break
    return found


def index_libraries():
    roots = [Path("/opt/homebrew/lib"), Path("/usr/local/lib")]
    opt = Path("/opt/homebrew/opt")
    if opt.exists():
        roots.extend(path / "lib" for path in opt.iterdir() if (path / "lib").is_dir())
    found = {}
    for root in roots:
        if not root.exists():
            continue
        for path in root.glob("*.dylib"):
            found.setdefault(path.name, path)
    return found


def needs_bundle(dep: str) -> bool:
    if not dep or dep.startswith("@"):
        return dep.startswith("@rpath/") or dep.startswith("@loader_path/") or dep.startswith("@executable_path/")
    return not dep.startswith(SKIP_PREFIXES)


def resolve_dep(dep: str, library_index):
    name = Path(dep).name
    if dep.startswith("/"):
        path = Path(dep)
        if path.exists():
            return path
    return library_index.get(name)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: bundle_runtime.py App.app")
    app = Path(sys.argv[1]).resolve()
    uxplay = app / "Contents" / "Helpers" / "uxplay"
    if not uxplay.exists():
        sys.exit(f"missing {uxplay}")

    plugin_src = Path("/opt/homebrew/lib/gstreamer-1.0")
    if not plugin_src.exists():
        plugin_src = Path("/usr/local/lib/gstreamer-1.0")
    frameworks = app / "Contents" / "Frameworks"
    plugins = app / "Contents" / "PlugIns" / "gstreamer"
    if frameworks.exists():
        shutil.rmtree(frameworks)
    if plugins.exists():
        shutil.rmtree(plugins)
    frameworks.mkdir(parents=True)
    plugins.mkdir(parents=True)

    library_index = index_libraries()
    copied = {}
    queued_names = set()
    queue = []

    def copy_library(source: Path, name: str):
        dest = frameworks / name
        if name in copied:
            return dest
        shutil.copy2(source, dest, follow_symlinks=True)
        os.chmod(dest, 0o755)
        copied[name] = dest
        for dep in otool_deps(dest):
            consider(dep)
        return dest

    def consider(dep: str):
        if not needs_bundle(dep):
            return
        name = Path(dep).name
        if name in copied or name in queued_names:
            return
        source = resolve_dep(dep, library_index)
        if source is None:
            print(f"warning: unresolved {dep}", file=sys.stderr)
            return
        queued_names.add(name)
        queue.append((source, name))

    plugin_dests = []
    for name in PLUGINS:
        source = plugin_src / name
        if not source.exists():
            sys.exit(f"missing GStreamer plugin {source}")
        dest = plugins / name
        shutil.copy2(source, dest, follow_symlinks=True)
        os.chmod(dest, 0o755)
        plugin_dests.append(dest)
        for dep in otool_deps(dest):
            consider(dep)

    for dep in otool_deps(uxplay):
        consider(dep)

    while queue:
        source, name = queue.pop()
        copy_library(source, name)

    binaries = [uxplay, *plugin_dests, *copied.values()]

    for binary in binaries:
        ident = otool_id(binary)
        for dep in otool_deps(binary):
            if not needs_bundle(dep):
                continue
            new = f"@rpath/{Path(dep).name}"
            if dep == ident:
                run(["install_name_tool", "-id", new, str(binary)])
            elif dep != new:
                run(["install_name_tool", "-change", dep, new, str(binary)])
        for old in rpaths(binary):
            if "/opt/homebrew" in old or "/usr/local" in old or "/Cellar/" in old:
                subprocess.run(["install_name_tool", "-delete_rpath", old, str(binary)], check=False)

    run(["install_name_tool", "-add_rpath", "@executable_path/../Frameworks", str(uxplay)])
    for plugin in plugin_dests:
        run(["install_name_tool", "-add_rpath", "@loader_path/../../Frameworks", str(plugin)])
    for library in copied.values():
        run(["install_name_tool", "-add_rpath", "@loader_path", str(library)])

    for binary in binaries:
        run(["codesign", "--force", "--sign", "-", str(binary)])

    leftovers = []
    for binary in binaries:
        for dep in otool_deps(binary):
            if dep.startswith("/opt/") or dep.startswith("/usr/local/"):
                leftovers.append(f"{binary.name}: {dep}")
    if leftovers:
        sys.exit("still linked outside the bundle:\n" + "\n".join(leftovers))
    print(f"bundled {len(copied)} libraries and {len(plugin_dests)} plugins")


if __name__ == "__main__":
    main()
