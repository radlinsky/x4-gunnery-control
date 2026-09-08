#!/usr/bin/env python3
"""Offline contract for Issue #118's MD chair-release handoff."""

from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
MD = ROOT / "md" / "x4_gunnery_control.xml"
root = ET.parse(MD).getroot()


def require(condition, message):
    if not condition:
        raise AssertionError(message)


chair = root.find(".//cue[@name='ChairIngress']")
require(chair is not None, "ChairIngress cue is missing")
release = chair.find("./cues/cue[@name='Release']")
stopped = chair.find("./cues/cue[@name='Stopped']")
require(release is not None, "ChairIngress.Release cue is missing")
require(stopped is not None, "ChairIngress.Stopped cue is missing")

release_event = release.find("./conditions/event_ui_triggered")
require(release_event is not None, "Release must consume an event_ui_triggered")
require(release_event.get("screen") == "'X4GunneryControl'", "Release screen contract drifted")
require(release_event.get("control") == "'chair_release'", "Release control contract drifted")

release_actions = release.find("./actions")
require(release_actions is not None, "Release actions are missing")
release_guard = None
for node in release_actions.findall("do_if"):
    value = node.get("value", "")
    if "not @ChairIngress.$pending" in value:
        release_guard = node
        break
require(release_guard is not None, "Release must guard an already-pending chair handoff")
release_value = release_guard.get("value", "")
for term in ("player.controlled", "$ship == player.container", "$ship.owner == faction.player"):
    require(term in release_value, f"Release guard lost required term: {term}")

release_children = list(release_guard)
require(len(release_children) == 2, "Release guard must contain only pending assignment + leave action")
require(release_children[0].tag == "set_value", "pending ship must be assigned before leave_control_position")
require(release_children[0].get("name") == "ChairIngress.$pending", "pending assignment target drifted")
require(release_children[0].get("exact") == "$ship", "pending assignment must retain the exact observed ship")
require(release_children[1].tag == "leave_control_position", "leave_control_position must follow pending assignment")
require(len(chair.findall(".//leave_control_position")) == 1, "ChairIngress must issue exactly one leave_control_position action")

stopped_event = stopped.find("./conditions/event_player_stopped_control")
require(stopped_event is not None, "Stopped must wait for event_player_stopped_control")
stopped_actions = stopped.find("./actions")
require(stopped_actions is not None, "Stopped actions are missing")
pending_guard = stopped_actions.find("do_if")
require(pending_guard is not None and pending_guard.get("value") == "@ChairIngress.$pending",
        "Stopped must be inert without a pending chair release")

children = list(pending_guard)
require(len(children) == 3, "Stopped pending guard must copy, clear, then revalidate")
require(children[0].tag == "set_value" and children[0].get("name") == "$ship"
        and children[0].get("exact") == "ChairIngress.$pending",
        "Stopped must copy the pending ship before clearing it")
require(children[1].tag == "remove_value" and children[1].get("name") == "ChairIngress.$pending",
        "Stopped must clear the pending handoff before any Lua raise")
require(children[2].tag == "do_if", "Stopped must revalidate context after clearing pending state")

revalidate = children[2]
revalidate_value = revalidate.get("value", "")
for term in ("$ship", "$ship == player.container", "$ship.owner == faction.player"):
    require(term in revalidate_value, f"Stopped revalidation lost required term: {term}")
raise_event = revalidate.find("raise_lua_event")
require(raise_event is not None, "Stopped revalidation must raise the existing onboard ingress event")
require(raise_event.get("name") == "'X4GunneryControl.OpenOnboard'", "Stopped must reuse OpenOnboard")
require(raise_event.get("param") == "$ship", "Stopped must pass the same pending ship to OpenOnboard")

# The supported synchronization boundary is the stopped-control event, not a
# guessed timer. A timing primitive inside ChairIngress would regress that rule.
for forbidden in ("delay", "wait"):
    require(not chair.findall(f".//{forbidden}"), f"ChairIngress must not synchronize with <{forbidden}>")

print("Issue #118 MD chair handoff contract passed")
