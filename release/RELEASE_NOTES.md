<!--
Body of the GitHub release, used verbatim by .github/workflows/release.yml.
Plain English, no version numbers (so it does not drift), no engine internals.
NEWS.md is the player-facing history; CHANGELOG.md is the technical record.
-->

- **Target selection is much more informative.** Every ship/station candidate now
  shows its class/type and an **N / total ENGAGEABLE** count for the selected
  turrets. Candidates that are fully ENGAGEABLE are listed first, ahead of the
  normal relationship/distance ordering.
- **Surface-element targeting has been rebuilt for large ships and stations.**
  Filter operational surfaces by **Turret / Shield / Engine** and by installed
  equipment, with alternatives ordered largest-first (XL → L → M → S → XS),
  then paged 20 at a time. Every listed surface has its own ENGAGEABLE count;
  the current aim point stays pinned with distance, shield and hull status.
  Manual refresh and an optional 10-second automatic refresh keep the browser
  current.
- **ENGAGEABLE now reflects the selected turrets' actual geometry.** The ratio
  checks known turret traverse arc, weapon range, and a clear muzzle-to-target
  line of fire past your own ship. Unknown-arc turrets remain in the denominator
  and are reported as **UNKNOWN**. It is still a targeting aid, not a guarantee
  that X4 will authorize or fire a shot.
- **Turret behavior edits can now be made permanent.** Mode/Armed changes made at
  the console are temporary by default; **Update turret behavior** makes the
  current staged settings the new baseline that Gunnery Control restores when
  you get up.
- **Loading a save no longer loses your gunnery session.** Checked turret groups,
  control mode, the active target and POV are restored when you load.
- **Target POV now works after loading.** It used to do nothing until you
  switched to another surface element and back.
- **"Other Turrets: Prefer My Target" and "Release Other Turrets" removed.** The
  Release behaviour was broken by an X4 API limitation — it could not cleanly
  revert `defend`, `missiledefence`, or `mining` modes after a ship-wide
  override. Ticking turret groups and using Direct-control is the supported way
  to direct turrets at a chosen target.
- **Previous / Next controls are in the conventional order.** Previous is now on
  the left and Next on the right in the engaged panel.
