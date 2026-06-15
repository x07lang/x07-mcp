#!/usr/bin/env python3
"""Bump the x07lang-mcp toolchain pin and/or server version across the repo.

Replaces the error-prone manual multi-file edits with one command.

Usage:
  scripts/bump_release.py --toolchain v0.2.16 --server 0.2.13
  scripts/bump_release.py --server 0.2.14
  scripts/bump_release.py --toolchain v0.2.17 --check   # dry-run, report only

`--toolchain vX.Y.Z` updates:
  - x07-toolchain.toml (channel)
  - .github/workflows/{ci,perf-smoke,trust-registry-monitor}.yml
    (X07_TOOLCHAIN_TAG + the x07-/x07up- tarball names)
  - docs/reference/pins.md
  - x07_version / x07c_version in every project lockfile

`--server A.B.C` updates:
  - servers/x07lang-mcp/x07.mcp.json (version + package version + release URL tag)
  - servers/x07lang-mcp/publish/{manifest.json,server.mcp-registry.json,build_mcpb.sh}
  - servers/x07lang-mcp/dist/server.json
  - servers/x07lang-mcp/config/mcp.server*.json + tests/config/mcp.server*.json

Caches and vendored trees (.agent_cache, packages/, .x07/deps, node_modules,
target, dist tmp toolchains) are never touched.

After running, finish the release by hand (these are build steps, not edits):
  1. regenerate CLI template assets (see scripts/ci/check_all.sh `check_asset` lines)
  2. ./dist/x07-mcp bundle --mcpb --server-dir servers/x07lang-mcp --machine json
     (rebuilds the mcpb and re-stamps its sha256 into the registry manifests)
  3. add a CHANGELOG entry
  4. ./dist/x07-mcp publish --dry-run --server-json servers/x07lang-mcp/dist/server.json \
       --mcpb servers/x07lang-mcp/dist/x07lang-mcp.mcpb --machine json
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER = os.path.join(ROOT, "servers", "x07lang-mcp")
EXCLUDE_DIRS = {".agent_cache", "packages", ".x07", "node_modules", "target", ".git"}

CHECK = False
_TOTAL = 0


def _edit(rel, repls, expect=None):
    """Apply (old, new) string replacements to a file; report counts."""
    global _TOTAL
    full = os.path.join(ROOT, rel)
    if not os.path.exists(full):
        print(f"  --   {rel} (missing, skipped)")
        return
    text = open(full, encoding="utf-8").read()
    n = 0
    new_text = text
    for old, new in repls:
        c = new_text.count(old)
        n += c
        new_text = new_text.replace(old, new)
    if n and not CHECK:
        open(full, "w", encoding="utf-8").write(new_text)
    _TOTAL += n
    flag = ""
    if expect is not None and n != expect:
        flag = f"  !! expected {expect}, got {n}"
    print(f"  {n:3d}  {rel}{flag}")


def _detect(path, pattern, what):
    m = re.search(pattern, open(os.path.join(ROOT, path), encoding="utf-8").read())
    if not m:
        sys.exit(f"error: could not detect current {what} in {path}")
    return m.group(1)


def _lockfiles():
    for dp, dns, fns in os.walk(ROOT):
        dns[:] = [d for d in dns if d not in EXCLUDE_DIRS]
        for fn in fns:
            if fn.endswith(".json"):
                yield os.path.relpath(os.path.join(dp, fn), ROOT)


def bump_toolchain(new_tag):
    old_tag = _detect("x07-toolchain.toml", r'channel\s*=\s*"(v[0-9.]+)"', "toolchain channel")
    if old_tag == new_tag:
        print(f"toolchain already at {new_tag}")
        return
    old_v, new_v = old_tag.lstrip("v"), new_tag.lstrip("v")
    print(f"== toolchain {old_tag} -> {new_tag} ==")
    _edit("x07-toolchain.toml", [(f'channel = "{old_tag}"', f'channel = "{new_tag}"')], expect=1)
    _edit("docs/reference/pins.md", [(old_tag, new_tag)])
    for wf in ("ci.yml", "perf-smoke.yml", "trust-registry-monitor.yml"):
        _edit(
            f".github/workflows/{wf}",
            [(old_tag, new_tag), (f"x07-{old_v}-", f"x07-{new_v}-"), (f"x07up-{old_v}-", f"x07up-{new_v}-")],
        )
    # re-stamp every project lockfile's toolchain version (content hashes are unchanged)
    locks = 0
    for rel in _lockfiles():
        text = open(os.path.join(ROOT, rel), encoding="utf-8").read()
        if f'"x07_version": "{old_v}"' in text or f'"x07_version":"{old_v}"' in text:
            _edit(
                rel,
                [
                    (f'"x07_version": "{old_v}"', f'"x07_version": "{new_v}"'),
                    (f'"x07_version":"{old_v}"', f'"x07_version":"{new_v}"'),
                    (f'"x07c_version": "{old_v}"', f'"x07c_version": "{new_v}"'),
                    (f'"x07c_version":"{old_v}"', f'"x07c_version":"{new_v}"'),
                ],
            )
            locks += 1
    print(f"  ({locks} lockfiles re-stamped)")


def bump_server(new_ver):
    old_ver = _detect("servers/x07lang-mcp/x07.mcp.json", r'"version":\s*"([0-9.]+)"', "server version")
    if old_ver == new_ver:
        print(f"server already at {new_ver}")
        return
    print(f"== server {old_ver} -> {new_ver} ==")
    pretty = (f'"version": "{old_ver}"', f'"version": "{new_ver}"')
    mini = (f'"version":"{old_ver}"', f'"version":"{new_ver}"')
    url = (f"x07lang-mcp-v{old_ver}", f"x07lang-mcp-v{new_ver}")
    _edit("servers/x07lang-mcp/x07.mcp.json", [pretty, url])
    _edit("servers/x07lang-mcp/publish/manifest.json", [pretty])
    _edit("servers/x07lang-mcp/publish/server.mcp-registry.json", [mini])
    _edit("servers/x07lang-mcp/dist/server.json", [mini])
    _edit("servers/x07lang-mcp/publish/build_mcpb.sh",
          [(f'"x07lang-mcp" "{old_ver}"', f'"x07lang-mcp" "{new_ver}"')])
    cfg = os.path.join(SERVER, "config")
    tcfg = os.path.join(SERVER, "tests", "config")
    for d in (cfg, tcfg):
        for fn in sorted(os.listdir(d)):
            if fn.startswith("mcp.server") and fn.endswith(".json"):
                _edit(os.path.relpath(os.path.join(d, fn), ROOT), [pretty, mini])


def main():
    global CHECK
    ap = argparse.ArgumentParser(description="Bump x07lang-mcp toolchain pin / server version.")
    ap.add_argument("--toolchain", metavar="vX.Y.Z", help="new x07 toolchain tag")
    ap.add_argument("--server", metavar="A.B.C", help="new x07lang-mcp server version")
    ap.add_argument("--check", action="store_true", help="dry-run: report changes without writing")
    args = ap.parse_args()
    if not args.toolchain and not args.server:
        ap.error("pass --toolchain and/or --server")
    CHECK = args.check
    if CHECK:
        print("(dry-run; no files written)\n")
    if args.toolchain:
        bump_toolchain(args.toolchain)
    if args.server:
        bump_server(args.server)
    print(f"\n{'would change' if CHECK else 'changed'} {_TOTAL} occurrences")
    if not CHECK and _TOTAL:
        print("\nnext: regenerate CLI assets, rebuild the mcpb, update CHANGELOG, run publish --dry-run")


if __name__ == "__main__":
    main()
