<!--
Body of the GitHub release, used verbatim by .github/workflows/release.yml.
Plain English, no version numbers (so it does not drift), no engine internals.
NEWS.md is the player-facing history; CHANGELOG.md is the technical record.
-->

- **Loading a save no longer loses your gunnery session.** Turret groups, the
  active target, and POV are all restored when you load.
- **Target POV now works after loading.** It used to do nothing until you
  switched to another surface element and back.
- **"Other Turrets: Prefer My Target" and "Release Other Turrets" removed.** The
  Release behaviour was broken by an X4 API limitation — it could not cleanly
  revert `defend`, `missiledefence`, or `mining` modes after a ship-wide
  override. Ticking turret groups and using Direct-control is the supported way
  to direct turrets at a chosen target.
