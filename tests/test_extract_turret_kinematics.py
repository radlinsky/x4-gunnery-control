#!/usr/bin/env python3
"""Focused tests for the turret kinematics extractor (Issue #69 Task 69A).

Tests are self-contained: synthetic XML fixtures are defined inline so the
parser is proved against materially different structures, not just the Paranid
L Beam golden anchor.  The Paranid integration test uses real research-cache
files.

Run with:  python3 tests/test_extract_turret_kinematics.py
"""
from __future__ import annotations

import math
import struct
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
from extract_turret_kinematics import (  # noqa: E402
    IDENTITY,
    ZERO,
    Vec3,
    Quat,
    extract_kinematics,
    parse_ani,
    run_census,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _write_xml(tmp: Path, name: str, cls: str, xml_body: str) -> Path:
    p = tmp / f"{name}.xml"
    p.write_text(textwrap.dedent(xml_body))
    return p


def _dist(a: Vec3, b: Vec3) -> float:
    return (a - b).length()


def _quat_angle(q: Quat) -> float:
    """Rotation angle in radians for a unit quaternion."""
    w = max(-1.0, min(1.0, q.qw))
    return 2.0 * math.acos(abs(w))


# ---------------------------------------------------------------------------
# Synthetic fixture 1 – simple yaw/pitch turret (no fixed rotations, no ANI)
#
# Topology: root_socket → yaw_rotator → pitch_gun → laser_endpoint
# Expected: RESOLVED / SIMPLE_YAW_PITCH
# ---------------------------------------------------------------------------

_SIMPLE_XML = """\
<?xml version="1.0"?>
<components>
  <component name="turret_simple_test" class="turret">
    <source geometry="assets/test/turret_simple_test_data"/>
    <connections>
      <connection name="container" tags="contents" value="0"/>
      <connection name="Connection01" tags="part animation ">
        <offset>
          <position x="0" y="2.5" z="0"/>
        </offset>
        <parts><part name="part_socket"/></parts>
      </connection>
      <connection name="con_yaw" tags="part iklink " parent="part_socket">
        <restrictions>
          <restriction type="rotation_y"/>
        </restrictions>
        <parts><part name="part_rotator"/></parts>
      </connection>
      <connection name="con_pitch" tags="part iklink " parent="part_rotator">
        <restrictions>
          <restriction type="rotation_x">
            <limits><min value="-10"/><max value="90"/></limits>
          </restriction>
        </restrictions>
        <offset>
          <position x="0" y="0.5" z="-3.0"/>
        </offset>
        <parts><part name="part_gun"/></parts>
      </connection>
      <connection name="con_laser_01" tags="laser " parent="part_gun">
        <offset>
          <position x="0" y="0" z="5.0"/>
        </offset>
      </connection>
    </connections>
  </component>
</components>
"""


def test_simple_yaw_pitch(tmp_path: Path) -> None:
    tmp = tmp_path
    xml = _write_xml(tmp, "turret_simple_test", "turret", _SIMPLE_XML)
    r = extract_kinematics(xml, [])

    assert r.status == "RESOLVED", f"expected RESOLVED, got {r.status}: {r.reason}"
    assert r.topology == "SIMPLE_YAW_PITCH", r.topology
    assert r.muzzle_count == 1

    # Yaw origin = Connection01 offset = (0, 2.5, 0)
    assert _dist(r.yaw_origin, Vec3(0, 2.5, 0)) < 1e-5, r.yaw_origin

    # Elevation pivot (from yaw to pitch) = con_pitch offset = (0, 0.5, -3.0)
    assert _dist(r.elevation_pivot, Vec3(0, 0.5, -3.0)) < 1e-5, r.elevation_pivot

    # Muzzle offset (from pitch to laser) = con_laser_01 offset = (0, 0, 5.0)
    assert _dist(r.muzzle_offsets[0], Vec3(0, 0, 5.0)) < 1e-5, r.muzzle_offsets[0]

    assert r.pitch_limits == (-10.0, 90.0)


# ---------------------------------------------------------------------------
# Synthetic fixture 2 – fixed rotation between yaw and pitch + multiple muzzles
#
# Models a turret where the pitch axis is tilted slightly (as in Paranid beam).
# Two laser endpoints.  No ANI.
# Expected: RESOLVED / FIXED_ROT_YAW_PITCH with 2 muzzles
# ---------------------------------------------------------------------------

_FIXED_ROT_XML = """\
<?xml version="1.0"?>
<components>
  <component name="turret_fixed_rot_test" class="turret">
    <source geometry="assets/test/turret_fixed_rot_test_data"/>
    <connections>
      <connection name="Connection01" tags="part ">
        <offset>
          <position x="0" y="1.0" z="0"/>
        </offset>
        <parts><part name="part_base"/></parts>
      </connection>
      <connection name="con_yaw" tags="part iklink " parent="part_base">
        <offset>
          <quaternion qx="0" qy="0.3826834324" qz="0" qw="0.9238795325"/>
        </offset>
        <restrictions>
          <restriction type="rotation_y"/>
        </restrictions>
        <parts><part name="part_rotator"/></parts>
      </connection>
      <connection name="con_pivot" tags="part iklink " parent="part_rotator">
        <offset>
          <position x="0" y="2.0" z="-10.0"/>
          <quaternion qx="-0.00433" qy="0" qz="0" qw="0.99999"/>
        </offset>
        <restrictions>
          <restriction type="rotation_x">
            <limits><min value="-5"/><max value="80"/></limits>
          </restriction>
        </restrictions>
        <parts><part name="part_gun"/></parts>
      </connection>
      <connection name="con_barrel" tags="part " parent="part_gun">
        <offset>
          <position x="0" y="0.1" z="8.0"/>
          <quaternion qx="0.00433" qy="0" qz="0" qw="0.99999"/>
        </offset>
        <parts><part name="part_barrel"/></parts>
      </connection>
      <connection name="con_laser_01" tags="laser " parent="part_barrel">
        <offset><position x="-0.36" y="0.27" z="6.0"/></offset>
      </connection>
      <connection name="con_laser_02" tags="laser " parent="part_barrel">
        <offset><position x="0.36" y="0.27" z="6.0"/></offset>
      </connection>
    </connections>
  </component>
</components>
"""


def test_fixed_rot_two_muzzles(tmp_path: Path) -> None:
    tmp = tmp_path
    xml = _write_xml(tmp, "turret_fixed_rot_test", "turret", _FIXED_ROT_XML)
    r = extract_kinematics(xml, [])

    assert r.status == "RESOLVED", f"{r.status}: {r.reason}"
    assert r.topology == "FIXED_ROT_YAW_PITCH", r.topology
    assert r.muzzle_count == 2

    # Yaw origin = Connection01 offset = (0, 1.0, 0)
    assert _dist(r.yaw_origin, Vec3(0, 1.0, 0)) < 1e-5, r.yaw_origin

    # Elevation pivot = con_pivot.pos = (0, 2.0, -10.0)
    assert _dist(r.elevation_pivot, Vec3(0, 2.0, -10.0)) < 1e-4, r.elevation_pivot

    # The normalized model retains the yaw joint frame: lowering this as a bare
    # component-space Ry would be wrong for this authored 45-degree yaw frame.
    assert _quat_angle(r.yaw_joint_frame) > 0.1, r.yaw_joint_frame
    assert r.paths[0].transforms[1].joint_axis == "rotation_y"

    # Non-trivial fixed rotation at pitch joint
    angle = _quat_angle(r.fixed_rot_yaw_to_pitch)
    assert angle > 0.001, f"expected non-zero fixed rotation, got {angle}"

    # Both lasers exist
    assert len(r.muzzle_offsets) == 2


# ---------------------------------------------------------------------------
# Synthetic fixture 3 – missile turret (class="missileturret"), simple structure
#
# Different class, rocket endpoints instead of laser.
# Expected: RESOLVED / MISSILE_SIMPLE
# ---------------------------------------------------------------------------

_MISSILE_XML = """\
<?xml version="1.0"?>
<components>
  <component name="turret_missile_test" class="missileturret">
    <source geometry="assets/test/turret_missile_test_data"/>
    <connections>
      <connection name="con_root" tags="part ">
        <offset><position x="0" y="3.0" z="0"/></offset>
        <parts><part name="part_base"/></parts>
      </connection>
      <connection name="con_yaw" tags="part " parent="part_base">
        <restrictions><restriction type="rotation_y"/></restrictions>
        <parts><part name="part_rotator"/></parts>
      </connection>
      <connection name="con_pitch" tags="part " parent="part_rotator">
        <restrictions>
          <restriction type="rotation_x">
            <limits><min value="-10"/><max value="90"/></limits>
          </restriction>
        </restrictions>
        <offset><position x="0" y="0.5" z="-2.0"/></offset>
        <parts><part name="part_gun"/></parts>
      </connection>
      <connection name="con_rocket_01" tags="rocket" parent="part_gun">
        <offset><position x="-1.0" y="0" z="3.0"/></offset>
      </connection>
      <connection name="con_rocket_02" tags="rocket" parent="part_gun">
        <offset><position x="1.0" y="0" z="3.0"/></offset>
      </connection>
    </connections>
  </component>
</components>
"""


def test_missile_turret(tmp_path: Path) -> None:
    tmp = tmp_path
    xml = _write_xml(tmp, "turret_missile_test", "missileturret", _MISSILE_XML)
    r = extract_kinematics(xml, [])

    assert r.status == "RESOLVED", f"{r.status}: {r.reason}"
    assert r.topology == "MISSILE_SIMPLE", r.topology
    assert r.muzzle_count == 2
    assert _dist(r.yaw_origin, Vec3(0, 3.0, 0)) < 1e-5, r.yaw_origin


# ---------------------------------------------------------------------------
# Synthetic fixture 4 – UNSUPPORTED: missing yaw joint
#
# Intentionally broken structure: no rotation_y restriction.
# Expected: UNSUPPORTED / missing-joints
# ---------------------------------------------------------------------------

_NO_YAW_XML = """\
<?xml version="1.0"?>
<components>
  <component name="turret_no_yaw_test" class="turret">
    <source geometry="assets/test/turret_no_yaw_test_data"/>
    <connections>
      <connection name="con_pitch" tags="part ">
        <restrictions>
          <restriction type="rotation_x">
            <limits><min value="-10"/><max value="90"/></limits>
          </restriction>
        </restrictions>
        <parts><part name="part_gun"/></parts>
      </connection>
      <connection name="con_laser_01" tags="laser " parent="part_gun">
        <offset><position x="0" y="0" z="5.0"/></offset>
      </connection>
    </connections>
  </component>
</components>
"""


def test_unsupported_no_yaw(tmp_path: Path) -> None:
    tmp = tmp_path
    xml = _write_xml(tmp, "turret_no_yaw_test", "turret", _NO_YAW_XML)
    r = extract_kinematics(xml, [])

    assert r.status == "UNSUPPORTED", f"expected UNSUPPORTED, got {r.status}"
    assert "missing-joints" in r.reason, r.reason


# ---------------------------------------------------------------------------
# Synthetic fixture 5 – ANI_BARREL structure without ANI available → AMBIGUOUS
#
# Has an anim_barrel ancestor between pitch and laser.
# With no ANI on disk: AMBIGUOUS.
# With a synthetic ANI: RESOLVED.
# ---------------------------------------------------------------------------

_ANI_BARREL_XML = """\
<?xml version="1.0"?>
<components>
  <component name="turret_ani_barrel_test" class="turret">
    <source geometry="assets/test/turret_ani_barrel_test_data"/>
    <connections>
      <connection name="Connection01" tags="part animation ">
        <offset><position x="0" y="2.0" z="0"/></offset>
        <animations><animation name="turret_active" start="60" end="61"/></animations>
        <parts><part name="part_socket"/></parts>
      </connection>
      <connection name="con_yaw" tags="part " parent="part_socket">
        <restrictions><restriction type="rotation_y"/></restrictions>
        <parts><part name="part_rotator"/></parts>
      </connection>
      <connection name="con_pitch" tags="part " parent="part_rotator">
        <restrictions>
          <restriction type="rotation_x">
            <limits><min value="-5"/><max value="80"/></limits>
          </restriction>
        </restrictions>
        <offset><position x="0" y="1.0" z="-8.0"/></offset>
        <parts><part name="moving_gun"/></parts>
      </connection>
      <connection name="con_barrel" tags="part " parent="moving_gun">
        <offset><position x="0" y="0.1" z="10.0"/></offset>
        <parts><part name="moving_barrel"/></parts>
      </connection>
      <connection name="con_laser_01" tags="laser " parent="moving_barrel">
        <offset><position x="-0.3" y="0.2" z="7.0"/></offset>
      </connection>
    </connections>
  </component>
</components>
"""


def _make_synthetic_ani(tmp: Path, part: str, anim: str, translation: Vec3,
                        extra: tuple[str, Vec3] | None = None) -> Path:
    """Write an ANI with source-proven identity entries for every path part."""
    records = [("part_socket", 0, ZERO), ("part_rotator", 0, ZERO),
               ("moving_gun", 0, ZERO), (part, 1, translation)]
    if extra:
        records.append((extra[0], 1, extra[1]))
    descs, keys = [], []
    for record_part, nkeys, value in records:
        desc = bytearray(160)
        desc[0:len(record_part)] = record_part.encode()
        desc[64:64 + len(anim)] = anim.encode()
        struct.pack_into("<I", desc, 128, nkeys)
        descs.append(bytes(desc))
        if nkeys:
            kf = bytearray(128)
            struct.pack_into("<3f", kf, 0, value.x, value.y, value.z)
            keys.append(bytes(kf))
    header = struct.pack("<II", len(records), len(records) * 160)
    ani_path = tmp / "TURRET_ANI_BARREL_TEST_DATA.ANI"
    ani_path.write_bytes(header + b"\x00" * 8 + b"".join(descs) + b"".join(keys))
    return ani_path


def test_ani_barrel_ambiguous_without_ani(tmp_path: Path) -> None:
    tmp = tmp_path
    """ANI_BARREL turret with no ANI file on disk → AMBIGUOUS."""
    xml = _write_xml(tmp, "turret_ani_barrel_test", "turret", _ANI_BARREL_XML)
    r = extract_kinematics(xml, [])
    assert r.status == "AMBIGUOUS", f"expected AMBIGUOUS, got {r.status}: {r.reason}"
    assert "ani" in r.reason.lower(), r.reason


def test_ani_barrel_resolved_with_ani(tmp_path: Path) -> None:
    tmp = tmp_path
    """ANI_BARREL turret with ANI providing anim_barrel translation → RESOLVED."""
    xml = _write_xml(tmp, "turret_ani_barrel_test", "turret", _ANI_BARREL_XML)
    # barrel moves forward 20m when active
    ani_path = _make_synthetic_ani(tmp, "moving_barrel", "turret_active", Vec3(0, 0, 20.0))
    r = extract_kinematics(xml, [tmp])

    assert r.status == "RESOLVED", f"{r.status}: {r.reason}"
    assert r.topology == "ANI_BARREL", r.topology
    assert r.muzzle_count == 1

    # Muzzle from pitch: con_barrel offset (0,0.1,10) + ANI (0,0,20) → barrel at (0,0.1,30)
    # Then laser offset (-0.3, 0.2, 7.0) from anim_barrel → in pitch-local: (0,0.1,30)+(-0.3,0.2,7)
    # = (-0.3, 0.3, 37.0)
    expected = Vec3(-0.3, 0.3, 37.0)
    assert _dist(r.muzzle_offsets[0], expected) < 1e-3, (
        f"muzzle_from_pitch expected {expected}, got {r.muzzle_offsets[0]}"
    )


def test_pitch_carrier_active_transform_is_represented(tmp_path: Path) -> None:
    """The pitch-created path part is not lost at the pivot boundary."""
    xml = _write_xml(tmp_path, "turret_ani_barrel_test", "turret", _ANI_BARREL_XML)
    _make_synthetic_ani(tmp_path, "moving_gun", "turret_active", Vec3(0, 2, 0),
                        extra=("moving_barrel", ZERO))
    r = extract_kinematics(xml, [tmp_path])
    assert r.status == "RESOLVED", f"{r.status}: {r.reason}"
    assert _dist(r.elevation_pivot, Vec3(0, 3, -8)) < 1e-5, r.elevation_pivot


def test_required_path_ani_data_must_parse(tmp_path: Path) -> None:
    """A truncated active record for a path part is never an implicit zero."""
    xml = _write_xml(tmp_path, "turret_ani_barrel_test", "turret", _ANI_BARREL_XML)
    p = _make_synthetic_ani(tmp_path, "moving_barrel", "turret_active", Vec3(0, 0, 20))
    p.write_bytes(p.read_bytes()[:-128])  # descriptor says one key, but it is absent
    r = extract_kinematics(xml, [tmp_path])
    assert r.status == "AMBIGUOUS", f"{r.status}: {r.reason}"
    assert "ani" in r.reason.lower(), r.reason


def test_missing_path_active_record_fails_closed(tmp_path: Path) -> None:
    """Absent turret_active data for a carried part is not inferred as zero."""
    xml = _write_xml(tmp_path, "turret_ani_barrel_test", "turret", _ANI_BARREL_XML)
    p = _make_synthetic_ani(tmp_path, "moving_barrel", "turret_active", Vec3(0, 0, 20))
    data = bytearray(p.read_bytes())
    data[16 + 3 * 160:16 + 3 * 160 + len(b"moving_barrel")] = b"other_barrel_"
    p.write_bytes(data)
    r = extract_kinematics(xml, [tmp_path])
    assert r.status == "AMBIGUOUS", f"{r.status}: {r.reason}"
    assert "missing" in r.reason, r.reason


def test_active_sibling_does_not_move_muzzle_path(tmp_path: Path) -> None:
    """ANI records belonging to a sibling connection are not path transforms."""
    xml_body = _ANI_BARREL_XML.replace(
        '</connections>',
        '''<connection name="con_sibling" tags="part" parent="part_socket">
             <parts><part name="moving_sibling"/></parts>
           </connection></connections>''',
    )
    xml = _write_xml(tmp_path, "turret_ani_barrel_test", "turret", xml_body)
    _make_synthetic_ani(tmp_path, "moving_barrel", "turret_active", ZERO,
                        extra=("moving_sibling", Vec3(99, 99, 99)))
    r = extract_kinematics(xml, [tmp_path])
    assert r.status == "RESOLVED", f"{r.status}: {r.reason}"
    assert _dist(r.muzzle_offsets[0], Vec3(-0.3, 0.3, 17.0)) < 1e-3, r.muzzle_offsets[0]


def test_changing_active_keys_fail_closed(tmp_path: Path) -> None:
    """A multi-key active pose without a single source-proven transform is unsafe."""
    xml = _write_xml(tmp_path, "turret_ani_barrel_test", "turret", _ANI_BARREL_XML)
    p = _make_synthetic_ani(tmp_path, "moving_barrel", "turret_active", Vec3(0, 0, 20))
    data = bytearray(p.read_bytes())
    struct.pack_into("<I", data, 16 + 3 * 160 + 128, 2)
    second = bytearray(128)
    struct.pack_into("<3f", second, 0, 0, 0, 21)
    p.write_bytes(bytes(data) + bytes(second))
    r = extract_kinematics(xml, [tmp_path])
    assert r.status == "AMBIGUOUS", f"{r.status}: {r.reason}"


# ---------------------------------------------------------------------------
# ANI parser: multi-record sequential keyframe offset
#
# Verifies that kf_offset += nkeys * 128 accumulates correctly when the first
# record has nkeys > 1.  The second record's first keyframe must be read at
# DESC_START + 2*160 + 3*128 (first record has nkeys=3), not at +0.
# ---------------------------------------------------------------------------

def _make_multirecord_ani(tmp: Path) -> Path:
    """Two-record ANI: record 0 has nkeys=3 (translation 1,2,3), record 1 has nkeys=1 (translation 4,5,6)."""
    num_records = 2
    desc0 = bytearray(160)
    desc0[0:len(b"part_one")] = b"part_one"
    desc0[64:64 + len(b"turret_active")] = b"turret_active"
    struct.pack_into("<I", desc0, 128, 3)  # nkeys=3

    desc1 = bytearray(160)
    desc1[0:len(b"part_two")] = b"part_two"
    desc1[64:64 + len(b"turret_active")] = b"turret_active"
    struct.pack_into("<I", desc1, 128, 1)  # nkeys=1

    # Record 0: 3 keyframe blocks, first = (1,2,3)
    kf0_block0 = bytearray(128)
    struct.pack_into("<3f", kf0_block0, 0, 1.0, 2.0, 3.0)
    kf0_block1 = bytearray(128)
    kf0_block2 = bytearray(128)
    struct.pack_into("<3f", kf0_block1, 0, 1.0, 2.0, 3.0)
    struct.pack_into("<3f", kf0_block2, 0, 1.0, 2.0, 3.0)

    # Record 1: 1 keyframe block = (4,5,6)
    kf1_block0 = bytearray(128)
    struct.pack_into("<3f", kf1_block0, 0, 4.0, 5.0, 6.0)

    header = struct.pack("<II", num_records, num_records * 160)
    padding = b"\x00" * 8
    p = tmp / "MULTIRECORD.ANI"
    p.write_bytes(
        header + padding
        + bytes(desc0) + bytes(desc1)
        + bytes(kf0_block0) + bytes(kf0_block1) + bytes(kf0_block2)
        + bytes(kf1_block0)
    )
    return p


def test_ani_multirecord_keyframe_offset(tmp_path: Path) -> None:
    """parse_ani must advance kf_offset by nkeys*128 per record."""
    p = _make_multirecord_ani(tmp_path)
    ani = parse_ani(p)

    t0 = ani.get(("part_one", "turret_active"))
    t1 = ani.get(("part_two", "turret_active"))
    assert t0 is not None, "part_one/turret_active missing"
    assert abs(t0.x - 1.0) < 1e-6 and abs(t0.y - 2.0) < 1e-6 and abs(t0.z - 3.0) < 1e-6, t0
    assert t1 is not None, "part_two/turret_active missing — kf_offset not advanced correctly"
    assert abs(t1.x - 4.0) < 1e-6 and abs(t1.y - 5.0) < 1e-6 and abs(t1.z - 6.0) < 1e-6, t1


# ---------------------------------------------------------------------------
# Integration: Paranid L Beam golden case
#
# Uses real research-cache files. Independently derives the hierarchy and
# verifies it reproduces the geometry from test_issue69_virtual_muzzle_geometry.lua.
# ---------------------------------------------------------------------------

_RESEARCH_CACHE = Path(
    "/home/pc/projects/x4-gunnery-control/.x4-research-cache"
)
_CORPUS_DIR = (
    _RESEARCH_CACHE
    / "extracted/issue69-all-turret-components-9.00"
    / "assets/props/WeaponSystems"
)
_PAR_L_BEAM_XML = (
    _RESEARCH_CACHE
    / "extracted/issue69-all-turret-components-9.00"
    / "assets/props/WeaponSystems/energy/turret_par_l_beam_01_mk1.xml"
)
_ANI_SEARCH_DIRS = [
    _RESEARCH_CACHE / "extracted/issue69-par-l-assets-9.00",
    _RESEARCH_CACHE / "extracted/issue65-remote-fixture",
    _RESEARCH_CACHE / "beam-turret-extract",
]


def _rotate_x(v: Vec3, angle: float) -> Vec3:
    c, s = math.cos(angle), math.sin(angle)
    return Vec3(v.x, c * v.y - s * v.z, s * v.y + c * v.z)


def _rotate_y(v: Vec3, angle: float) -> Vec3:
    c, s = math.cos(angle), math.sin(angle)
    return Vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z)


def _vec3_add(a: Vec3, b: Vec3) -> Vec3:
    return Vec3(a.x + b.x, a.y + b.y, a.z + b.z)


_PAR_L_BEAM_ANI = (
    _RESEARCH_CACHE
    / "extracted/issue69-par-l-assets-9.00"
    / "assets/props/WeaponSystems/energy/TURRET_PAR_L_BEAM_01_MK1_DATA.ANI"
)


def test_paranid_l_beam_golden() -> None:
    """Extract Paranid L Beam from real cache; verify against Lua test geometry."""
    if not _PAR_L_BEAM_XML.exists():
        raise unittest.SkipTest("research cache not available")

    # Pin the ANI parse directly — the golden error check depends on these values.
    # Documented in test_issue69_virtual_muzzle_geometry.lua header.
    if _PAR_L_BEAM_ANI.exists():
        ani = parse_ani(_PAR_L_BEAM_ANI)
        rotator_t = ani.get(("part_rotator", "turret_active"))
        barrel_t = ani.get(("anim_barrel", "turret_active"))
        assert rotator_t is not None, "parse_ani: part_rotator/turret_active missing"
        assert abs(rotator_t.y - 6.145042) < 1e-4, f"rotator y={rotator_t.y}"
        assert rotator_t.x == 0.0 and rotator_t.z == 0.0, f"rotator xz non-zero: {rotator_t}"
        assert barrel_t is not None, "parse_ani: anim_barrel/turret_active missing"
        assert abs(barrel_t.y - (-0.23982)) < 1e-4, f"barrel y={barrel_t.y}"
        assert abs(barrel_t.z - 27.710205) < 1e-4, f"barrel z={barrel_t.z}"

    r = extract_kinematics(_PAR_L_BEAM_XML, _ANI_SEARCH_DIRS)

    assert r.status == "RESOLVED", f"Paranid L Beam must be RESOLVED, got {r.status}: {r.reason}"
    assert r.topology == "ANI_BARREL", r.topology
    assert r.muzzle_count >= 1

    # Independently compose the authored inactive path from the model's XML
    # transforms only.  No ANI data or live vector is an input to this result.
    rest_pos, rest_rot = Vec3(0, 0, 0), IDENTITY
    for transform in r.paths[0].transforms:
        rest_pos = _vec3_add(rest_pos, rest_rot.rotate(transform.position))
        rest_rot = rest_rot * transform.rotation
    authored_rest = Vec3(-0.361774, 5.427165, 12.040031)
    assert _dist(rest_pos, authored_rest) < 1e-5, (
        f"authored inactive path {rest_pos} no longer reproduces rest muzzle"
    )

    # --- Reproduce rest-pose muzzle from Lua test constants ---
    # observed_rest = (-0.361774, 5.427165, 12.040031)  within 0.00001 of authored
    #
    # Lua compose_muzzle(zero, zero):
    #   rotator_origin = component_root + vec(0,0,0)   (zero ani at rest)
    #   downstream = rotate(gun_base_quat, barrel_connection) + rotate(gun_barrel_quat, laser_02)
    #   muzzle = rotator_origin + elevation_pivot + downstream
    #
    # Our extractor models the rest muzzle as:
    #   yaw_origin + elevation_pivot + muzzle_from_pivot
    # where muzzle_from_pivot was computed with the ACTIVE ANI translations.
    # For the golden check, we verify the PROSPECTIVE muzzle formula from the Lua test.

    # The Lua test uses these Lua-test values (from lua test):
    # yaw_origin (called 'rotator_origin' in Lua) = component_root + rotator_active_translation
    # elevation_pivot = Connection04 offset position
    # deployed_from_elevation_pivot = muzzle vector in elevation_pivot-local space

    # Verify prospective muzzle matches settled live observations from the Lua test.
    # Settled samples median is around Vec3(0.361781, 11.193646, -39.750679).
    # We compute: virtual_muzzle = yaw_origin + rotate_y(yaw, elevation_pivot + rotate_x(-pitch, m_from_pivot))
    target_yaw = math.pi          # from Lua test
    target_pitch = -0.00135549   # from Lua test

    # Use FIRST muzzle offset (the extractor returns one muzzle per laser connection)
    m = r.muzzle_offsets[0]
    elev = r.elevation_pivot
    yaw_o = r.yaw_origin

    virtual_muzzle = _vec3_add(
        yaw_o,
        _rotate_y(
            _vec3_add(elev, _rotate_x(m, -target_pitch)),
            target_yaw,
        ),
    )

    settled_samples = [
        Vec3(0.361772, 11.193660, -39.750687),
        Vec3(0.361762, 11.193673, -39.750683),
        Vec3(0.361791, 11.193634, -39.750687),
        Vec3(0.361781, 11.193646, -39.750679),
    ]
    max_err = max(_dist(virtual_muzzle, s) for s in settled_samples)
    assert max_err <= 0.5, (
        f"source-backed prospective muzzle {virtual_muzzle} "
        f"exceeds 0.5m tolerance (max_err={max_err:.4f})"
    )

    # Verify yaw_origin (= rotator_origin in Lua) is approximately (0, 8.163, 0)
    # component_root ≈ (0, 2.018, 0) + rotator_active_translation (0, 6.145, 0)
    assert abs(r.yaw_origin.y - 8.163) < 0.01, (
        f"yaw_origin.y expected ~8.163, got {r.yaw_origin.y}"
    )

    # Verify elevation_pivot z is approximately -16.12 (forward tilt of pitch pivot)
    assert abs(r.elevation_pivot.z - (-16.12)) < 0.1, (
        f"elevation_pivot.z expected ~-16.12, got {r.elevation_pivot.z}"
    )

    print(f"Paranid L Beam golden: yaw_origin={r.yaw_origin} "
          f"elev_pivot={r.elevation_pivot} "
          f"muzzle_from_pivot={r.muzzle_offsets[0]} "
          f"max_settled_err={max_err:.4f}m PASS")


# ---------------------------------------------------------------------------
# Full 79-component census sanity check
# ---------------------------------------------------------------------------

def test_census_counts() -> None:
    """Census over the 79-component corpus; verify expected totals."""
    if not _CORPUS_DIR.exists():
        raise unittest.SkipTest("corpus directory not available")

    results = run_census(_CORPUS_DIR, _ANI_SEARCH_DIRS)
    total = len(results)
    by_status = {}
    for r in results:
        by_status.setdefault(r.status, []).append(r)

    resolved = len(by_status.get("RESOLVED", []))
    ambiguous = len(by_status.get("AMBIGUOUS", []))
    unsupported = len(by_status.get("UNSUPPORTED", []))

    assert total == 79, f"expected 79 components, got {total}"
    assert resolved + ambiguous + unsupported == total

    # Paranid L Beam must be RESOLVED
    par_l_beam = next(
        (r for r in results if r.component == "turret_par_l_beam_01_mk1"), None
    )
    assert par_l_beam is not None, "Paranid L Beam missing from census"
    assert par_l_beam.status == "RESOLVED", (
        f"turret_par_l_beam_01_mk1 must be RESOLVED in census, got {par_l_beam.status}"
    )

    # At least the gen_m_scrapbeam_01_mk2 must be UNSUPPORTED (no class)
    gen_scrap = next(
        (r for r in results if r.component == "turret_gen_m_scrapbeam_01_mk2"), None
    )
    assert gen_scrap is not None
    assert gen_scrap.status == "UNSUPPORTED", gen_scrap.status

    print(f"Census: total={total} RESOLVED={resolved} AMBIGUOUS={ambiguous} "
          f"UNSUPPORTED={unsupported}")

    # Print topology groups for inspection
    topo_counts: dict[str, int] = {}
    for r in by_status.get("RESOLVED", []):
        topo_counts[r.topology] = topo_counts.get(r.topology, 0) + 1
    print(f"Resolved topology groups: {topo_counts}")

    # Print non-resolved reasons
    for status in ("AMBIGUOUS", "UNSUPPORTED"):
        for r in by_status.get(status, []):
            print(f"  {status} {r.component}: {r.reason}")


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------

def _run_all() -> None:
    tests = [
        ("simple_yaw_pitch",              True,  test_simple_yaw_pitch),
        ("fixed_rot_two_muzzles",         True,  test_fixed_rot_two_muzzles),
        ("missile_turret",                True,  test_missile_turret),
        ("unsupported_no_yaw",            True,  test_unsupported_no_yaw),
        ("ani_barrel_ambiguous",          True,  test_ani_barrel_ambiguous_without_ani),
        ("ani_barrel_resolved",           True,  test_ani_barrel_resolved_with_ani),
        ("pitch_carrier_active",          True,  test_pitch_carrier_active_transform_is_represented),
        ("required_path_ani_data",         True,  test_required_path_ani_data_must_parse),
        ("missing_path_ani_record",       True,  test_missing_path_active_record_fails_closed),
        ("active_sibling_isolated",        True,  test_active_sibling_does_not_move_muzzle_path),
        ("changing_active_keys",          True,  test_changing_active_keys_fail_closed),
        ("ani_multirecord_kf_offset",       True,  test_ani_multirecord_keyframe_offset),
        ("paranid_l_beam_golden",         False, test_paranid_l_beam_golden),
        ("census_counts",                 False, test_census_counts),
    ]

    passed = failed = skipped = 0
    for name, needs_tmp, fn in tests:
        try:
            if needs_tmp:
                with tempfile.TemporaryDirectory() as td:
                    fn(Path(td))
            else:
                fn()
            print(f"  PASS  {name}")
            passed += 1
        except unittest.SkipTest as exc:
            print(f"  SKIP  {name}: {exc}")
            skipped += 1
        except AssertionError as exc:
            print(f"  FAIL  {name}: {exc}")
            failed += 1
        except Exception as exc:
            print(f"  ERROR {name}: {exc}")
            failed += 1

    print(f"\n{passed} passed, {failed} failed, {skipped} skipped")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    _run_all()
