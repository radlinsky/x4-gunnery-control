"""Extract SWI 0.9.1 HF asset XML (`assets/**.xml`: ships plus the docks, interiors and props they attach)
and its `index/**.xml` name lookup from the owner's ext_01 catalog into the ignored cache.

    python3 research/issue184/extract_swi_units.py /path/to/starwarsmod_m1
"""
import hashlib
import re
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / ".x4-research-cache/issue184/swi_assets"


def main(mod):
    mod, offset, n = Path(mod), 0, 0
    with open(mod / "ext_01.dat", "rb") as dat:
        for line in (mod / "ext_01.cat").read_text(encoding="utf-8", errors="replace").splitlines():
            m = re.match(r"^(.*) (\d+) (\d+) ([0-9a-f]{32})$", line)
            if not m:
                continue
            path, size, start = m.group(1), int(m.group(2)), offset
            offset += size
            if re.match(r"(assets|index)/.*\.xml$", path, re.I):
                dat.seek(start)
                data = dat.read(size)
                if hashlib.md5(data).hexdigest() != m.group(4):
                    raise SystemExit(f"md5 mismatch: {path}")
                dst = OUT / path
                dst.parent.mkdir(parents=True, exist_ok=True)
                dst.write_bytes(data)
                n += 1
    print(f"extracted {n} files to {OUT}")


if __name__ == "__main__":
    main(sys.argv[1])
