# Native executable analysis

Read-only analysis of the shipped X4 executable. Use it only after Lua, MD, AI
and XSD sources fail to answer the question; the executable is the last source,
not the first.

This file is the durable home for verified native RVAs, struct offsets, and
tool gotchas. Record a native finding here (or in a focused reference that
carries the same build pin) rather than leaving it in an issue thread.

Never commit the executable, a disassembly dump, decompiler output, or any
extracted proprietary bytes. Keep scratch tooling under the ignored
`.x4-research-cache/` or an external temporary directory.

## Pinned installation

- X4: 9.00 build 611726
- Executable: `/mnt/c/Program Files (x86)/Steam/steamapps/common/X4 Foundations/X4.exe`
- SHA-256: `19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`
- Image base: `0x140000000`

Verify the SHA-256 once per session before using or extending any stored native
finding:
`sha256sum "/mnt/c/Program Files (x86)/Steam/steamapps/common/X4 Foundations/X4.exe"`.
A different hash means every stored RVA and struct offset below is stale;
re-derive it against the new build instead of shifting addresses by hand.
Record addresses as RVAs. The absolute form is the RVA plus the image base, so
RVA `0x0081c960` is `0x14081c960`.

## Standing disassembly recipe

Derive the RVA-to-file-offset mapping from the PE section table once per
build, then reuse it. For an RVA inside a section, the file offset is
`rva - VirtualAddress + PointerToRawData`.

Use the `.pdata` `RUNTIME_FUNCTION` table for function bounds instead of
guessing where a function ends. Each entry is three 4-byte RVAs
(`BeginAddress`, `EndAddress`, `UnwindInfoAddress`). One logical function can
own several non-adjacent ranges; disassemble all of them, or a trace stops at
a range boundary and looks like a tail call that is not there.

Disassemble with Capstone and `skipdata = True`. Without it, the first
jump-table or constant island inside a code range aborts the disassembly and
the remainder of the function is silently missing.

Prefix scratch scripts and helper modules with `x4_` (for example
`x4_pe.py`, `x4_disasm.py`). An unprefixed `pe.py`, `types.py` or `struct.py`
in the working directory shadows a Python standard-library module and produces
import failures that look like tool bugs.

## Search rules that prevent wrong conclusions

Resolve an enum or keyword by walking the full contiguous table, not by
reading the entries next to the string you found. Take the table's base and
stride, index the whole run, and confirm the first and last entries are
well-formed. Nearby entries are the most common source of an off-by-one
mapping that then propagates into every downstream conclusion.

Expect registration code to be interleaved. Names, handlers, and ids are often
emitted in separate runs rather than as adjacent tuples, so a pairing read
straight off the disassembly is a guess. Validate the pairing against a
known anchor whose name/id relationship is independently established — for
example a keyword the shipped MD or Lua source already ties to an observable
behaviour — and only then trust the rest of the run.

Trace a script-visible property backward to the field it actually reads before
reasoning about how the object is constructed. Start at the property getter,
find the load it performs, and identify that field's writers. Reasoning
forward from a plausible constructor instead routinely attributes a value to
the wrong field; the getter is the only side that is pinned to the
script-visible name.

## Prompt and output convention

Start a native question from this file: the pinned executable, the verified
SHA-256, and the stored RVAs and offsets already recorded here and in the
build-pinned references.

Answer only the specific question asked. Do not map the surrounding subsystem
because it is adjacent and the disassembly is already open.

Report RVAs plus minimal pseudocode — enough to show the field, the branch or
the call that carries the answer. Do not paste disassembly listings or
decompiler output.

Classify an executable-derived conclusion as `inference`. A static trace shows
what the code can do, not what the running game did. Promote it only when
independent evidence proves it: `shipped-source` when shipped Lua/MD/AI/XSD
demonstrates the same fact, or `live-tested` when a recorded build/save
reproduces it. Note in the record which analyst labels are your own and which
are real native names.

## Recorded native findings

| Subject | Reference |
|---|---|
| Macro box slots, collision eligibility, and raw authored aim selector | [macro-box-aimtargets.md](macro-box-aimtargets.md) |
| Turret yaw map, mover state, and resting-point gate | [turret-yaw-resting-point-gate.md](turret-yaw-resting-point-gate.md) |
| Target-point turret joint solver route and RVA table | [turret-target-point-joint-solver.md](turret-target-point-joint-solver.md) |
| Aim-feasibility surface: HUD aim exports, `Weapon::Defaults` limits, solver clamp, `GetDistanceBetween`, data-getter key hash | [turret-aim-feasibility-surface.md](turret-aim-feasibility-surface.md) |
| Selected-connection transform composition entry points | [barrelposition-offline-transform-semantics.md](barrelposition-offline-transform-semantics.md) |
| Live interception of the selected `barrelposition` transform | [barrelposition-live-connection-orientation.md](barrelposition-live-connection-orientation.md) |
| Missile-turret guidance query and the guided pre-launch obstruction bypass | [weapon-path-obstruction-groups.md](weapon-path-obstruction-groups.md) |
| PE export table of the engine (2493 named exports) | [ui-lua-menu-camera.md](ui-lua-menu-camera.md) |
