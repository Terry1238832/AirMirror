#!/usr/bin/env python3
"""Embed GStreamer from an isolated SDK prefix or a local Homebrew install."""

import os
import argparse
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


def index_libraries(prefix=None):
    roots = [prefix / "lib"] if prefix else [Path("/opt/homebrew/lib"), Path("/usr/local/lib")]
    opt = Path("/opt/homebrew/opt")
    if not prefix and opt.exists():
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


def resolve_dep(dep: str, library_index, isolated=False):
    name = Path(dep).name
    if isolated:
        return library_index.get(name)
    if dep.startswith("/"):
        path = Path(dep)
        if path.exists():
            return path
    return library_index.get(name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--runtime-prefix", type=Path)
    parser.add_argument("--helper-relative-path", default="Contents/Helpers/uxplay")
    parser.add_argument("--arch", choices=["arm64", "x86_64"])
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    app = args.app.resolve()
    uxplay = app / args.helper_relative_path
    if not uxplay.exists():
        sys.exit(f"missing {uxplay}")

    plugin_src = args.runtime_prefix / "lib/gstreamer-1.0" if args.runtime_prefix else Path("/opt/homebrew/lib/gstreamer-1.0")
    if not args.runtime_prefix and not plugin_src.exists():
        plugin_src = Path("/usr/local/lib/gstreamer-1.0")
    frameworks = app / "Contents" / "Frameworks"
    plugins = app / "Contents" / "PlugIns" / "gstreamer"
    if frameworks.exists():
        shutil.rmtree(frameworks)
    if plugins.exists():
        shutil.rmtree(plugins)
    frameworks.mkdir(parents=True)
    plugins.mkdir(parents=True)

    def thin_binary(binary):
        if not args.arch:
            return
        arches = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()
        if args.arch not in arches:
            sys.exit(f"{binary.name} does not support {args.arch}")
        if len(arches) > 1:
            thin = binary.with_suffix(binary.suffix + ".thin")
            run(["lipo", str(binary), "-thin", args.arch, "-output", str(thin)])
            thin.replace(binary)

    thin_binary(uxplay)

    library_index = index_libraries(args.runtime_prefix)
    copied = {}
    queued_names = set()
    queue = []

    def copy_library(source: Path, name: str):
        dest = frameworks / name
        if name in copied:
            return dest
        shutil.copy2(source, dest, follow_symlinks=True)
        os.chmod(dest, 0o755)
        thin_binary(dest)
        copied[name] = dest
        ident = otool_id(dest)
        for dep in otool_deps(dest):
            if dep != ident:
                consider(dep)
        return dest

    def consider(dep: str):
        if not needs_bundle(dep):
            return
        name = Path(dep).name
        if name in copied or name in queued_names:
            return
        source = resolve_dep(dep, library_index, isolated=args.runtime_prefix is not None)
        if source is None:
            if args.strict:
                sys.exit(f"unresolved runtime dependency: {dep}")
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
        thin_binary(dest)
        plugin_dests.append(dest)
        ident = otool_id(dest)
        for dep in otool_deps(dest):
            if dep != ident:
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
            if "/opt/homebrew" in old or "/usr/local" in old or "/Cellar/" in old or (args.strict and not old.startswith("@")):
                subprocess.run(["install_name_tool", "-delete_rpath", old, str(binary)], check=False)

    if "@executable_path/../Frameworks" not in rpaths(uxplay):
        run(["install_name_tool", "-add_rpath", "@executable_path/../Frameworks", str(uxplay)])
    for plugin in plugin_dests:
        if "@loader_path/../../Frameworks" not in rpaths(plugin):
            run(["install_name_tool", "-add_rpath", "@loader_path/../../Frameworks", str(plugin)])
    for library in copied.values():
        if "@loader_path" not in rpaths(library):
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
