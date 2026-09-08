# Control-position release and standing onboard handoff

### `leave_control_position` releases the player's current control position
- X4: 9.00
- Status: shipped-source
- Source: `libraries/md.xsd`; `extensions/ego_dlc_boron/md/gs_boron2.xml`
- Live test: no — source-only as of 2026-09-08
- Finding: The MD schema defines `leave_control_position` as leaving the player's current control position and activating first-person controls. Shipped Boron start logic invokes it when `player.controlled` is set, establishing it as a normal engine-supported way to leave an active control position rather than a private UI workaround.

### `event_player_stopped_control` is the source-backed completion boundary
- X4: 9.00
- Status: shipped-source
- Source: `extensions/ego_dlc_boron/md/gs_boron2.xml`; `md/setup.xml`
- Live test: no — source-only as of 2026-09-08
- Finding: Shipped Boron start logic separates the release request from the follow-up player-placement cue: it calls `leave_control_position` while the player controls an object, then the next cue accepts `event_player_stopped_control` before performing work that requires `player.controlled` to be false. Core setup logic also consumes `event_player_stopped_control` as the normal stopped-control lifecycle event. For an extension handoff, this event is a stronger synchronization point than any fixed delay.

### Release first, then reuse the existing standing onboard target-view path
- X4: 9.00
- Status: inference
- Source: `extensions/ego_dlc_boron/md/gs_boron2.xml`; `ui/core/lua/targetsystem.lua`; `ui/gunnery_control.lua`; `.agents/skills/research-x4-modding/references/ui-lua-menu-camera.md`
- Live test: no — final physical-console parity remains untested as of 2026-09-08
- Finding: The narrow supported handoff is to request `leave_control_position`, wait for `event_player_stopped_control`, then create/reuse the same onboard session used by the standing Map-entry route before invoking the existing external target-view camera path. `targetsystem.lua` maps `gameplanchange = externalfirstperson` to target-system `space` mode, and the existing knowledge base records that the standing onboard target-view path works in game. This avoids creating a chair-origin session that would be torn down by the project's normal `playerGetUp` handling. The final claim that physical-console world clicks become identical to Map entry still requires the correlated live parity test.
