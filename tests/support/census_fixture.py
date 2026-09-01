#!/usr/bin/env python3
"""Shared synthetic fixtures for the Issue #72 A2.1 turret asset census tests."""
from __future__ import annotations

import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

from census_common import REQUIRED_SOURCE_SETS  # noqa: E402
from census_pipeline import build_census as _build_census  # noqa: E402


def _ani_bytes(
    *descriptors: (
        tuple[str, str]
        | tuple[str, str, int, int, int, int, int]
        | tuple[str, str, int, int, int, int, int, int]
    ),
    version: int = 1,
    header_padding: int = 0,
    key_offset: int | None = None,
    descriptor_padding: tuple[int, int] = (0, 0),
    key_data: bytes | None = None,
) -> bytes:
    records = []
    total_key_records = 0
    for descriptor in descriptors:
        part, subname = descriptor[:2]
        channel_counts = descriptor[2:7] or (0, 0, 0, 0, 0)
        descriptor_offset_148_raw_bits = descriptor[7] if len(descriptor) == 8 else 0
        total_key_records += sum(channel_counts)
        part_bytes = part.encode("ascii")
        subname_bytes = subname.encode("ascii")
        if len(part_bytes) > 63 or len(subname_bytes) > 63:
            raise ValueError("synthetic ANI descriptor strings must fit with a NUL terminator")
        records.append(
            part_bytes.ljust(64, b"\0")
            + subname_bytes.ljust(64, b"\0")
            + struct.pack(
                "<8I",
                *channel_counts,
                descriptor_offset_148_raw_bits,
                *descriptor_padding,
            )
        )
    descriptor_table = b"".join(records)
    if key_data is None:
        key_data = b"".join(
            bytes([(record_index % 251) + 1]) * 128
            for record_index in range(total_key_records)
        )
    return (
        struct.pack(
            "<4I",
            len(descriptors),
            16 + len(descriptor_table) if key_offset is None else key_offset,
            version,
            header_padding,
        )
        + descriptor_table
        + key_data
    )


def _candidate_key_record(values: tuple[float | int, ...]) -> bytes:
    if len(values) != 32:
        raise ValueError("candidate ANI key record requires exactly 32 typed slots")
    return struct.pack("<3f3if17fi6fI", *values)


def _source_roots(root: Path) -> dict[str, Path]:
    roots = {}
    for name in REQUIRED_SOURCE_SETS:
        path = root / name
        path.mkdir(parents=True)
        (path / "source_set.xml").write_text("<source/>", encoding="utf-8")
        inventory = path / "inventory" / f"unrelated_{name}.ANI"
        inventory.parent.mkdir()
        inventory.write_bytes(_ani_bytes())
        roots[name] = path
    for resource in (
        "geometry/shared.ANI",
        "geometry/missile.ANI",
        "geometry/shared_component.ANI",
        "geometry/component_a.ANI",
        "geometry/component_b.ANI",
        "geometry/component_z.ANI",
        "geometry/current_a.ANI",
        "geometry/current_b.ANI",
        "geometry/current_c.ANI",
        "ASSETS/Exact_CASE_Data.ANI",
    ):
        target = roots["base"] / resource
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(_ani_bytes())
    return roots


def build_census(source_sets: dict[str, Path]) -> dict[str, object]:
    return _build_census(source_sets, source_sets)


def _write(path: Path, relative: str, text: str) -> None:
    target = path / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def _components(*names: str) -> str:
    body = "".join(
        f'<component name="{name}" class="turret"><source geometry="geometry/{name}"/><connections><connection name="{name}_endpoint" tags="laser"/></connections></component>'
        for name in names
    )
    return f"<components>{body}</components>"


def _wares(*records: tuple[str, str, str | None]) -> str:
    body = []
    for ware, component, purposes in records:
        use = "" if purposes is None else f'<use purposes="{purposes}"/>'
        body.append(f'<ware id="{ware}"><component ref="{component}"/>{use}</ware>')
    return "<wares>" + "".join(body) + "</wares>"


def _macros(*records: tuple[str, str, str | None]) -> str:
    body = []
    for name, macro_class, component in records:
        child = "" if component is None else f'<component ref="{component}"/>'
        body.append(f'<macro name="{name}" class="{macro_class}">{child}</macro>')
    return "<macros>" + "".join(body) + "</macros>"
