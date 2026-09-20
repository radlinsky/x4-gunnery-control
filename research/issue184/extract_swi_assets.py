"""Extract SWI 0.9.1 HF asset XML (`assets/**.xml`: ships plus the docks, interiors and props they attach)
and its `index/**.xml` name lookup from the owner's ext_01 catalog into the ignored cache.

    python3 research/issue184/extract_swi_assets.py /path/to/starwarsmod_m1

In 0.9.1 HF only `ext_01` holds census input. `ext_02` is md/aiscripts/libraries/t, and the `subst_*`
catalogs hold voice, UI `.xpl` and loading-screen images with no XML at all. `audit_other_catalogs`
rechecks that rather than trusting it, so a future SWI release that moves ship or index XML elsewhere
fails here instead of silently shrinking the census.
"""
import hashlib
import re
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / ".x4-research-cache/issue184/swi_assets"


CENSUS_INPUT = re.compile(r"(assets|index)/.*\.xml$", re.I)


def audit_other_catalogs(mod):
    """Every catalog except ext_01 must hold no census input. -> {catalog: entry count}."""
    seen = {}
    for cat in sorted(mod.glob("*.cat")):
        if cat.stem == "ext_01":
            continue
        entries = [line.rsplit(" ", 3)[0] for line in cat.read_text(encoding="utf-8", errors="replace").splitlines()
                   if line.strip()]
        stray = [e for e in entries if CENSUS_INPUT.match(e)]
        if stray:
            raise SystemExit(f"{cat.name} holds census input this extractor ignores: {stray[:5]}")
        seen[cat.name] = len(entries)
    return seen


def main(mod):
    mod, offset, n = Path(mod), 0, 0
    audited = audit_other_catalogs(mod)
    with open(mod / "ext_01.dat", "rb") as dat:
        for line in (mod / "ext_01.cat").read_text(encoding="utf-8", errors="replace").splitlines():
            m = re.match(r"^(.*) (\d+) (\d+) ([0-9a-f]{32})$", line)
            if not m:
                continue
            path, size, start = m.group(1), int(m.group(2)), offset
            offset += size
            if CENSUS_INPUT.match(path):
                dat.seek(start)
                data = dat.read(size)
                if hashlib.md5(data).hexdigest() != m.group(4):
                    raise SystemExit(f"md5 mismatch: {path}")
                dst = OUT / path
                dst.parent.mkdir(parents=True, exist_ok=True)
                dst.write_bytes(data)
                n += 1
    print(f"extracted {n} files to {OUT}")
    print("other catalogs audited, no census input: " + ", ".join(f"{k} ({v})" for k, v in audited.items()))


if __name__ == "__main__":
    main(sys.argv[1])
