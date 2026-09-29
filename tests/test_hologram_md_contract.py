"""Guard MD regressions that stock Lua cannot exercise."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


class HologramMDContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = ET.parse(Path("md/x4_gunnery_hologram.xml")).getroot()
        cls.cues = {cue.get("name"): cue for cue in cls.root.iter("cue")}

    def test_periodic_resets_wait_between_cycles(self):
        # checkinterval alone caused a real same-frame freeze in X4.
        for name in ("HologramLease", "HologramSnapshot"):
            cue = self.cues[name]
            self.assertIsNone(cue.get("checkinterval"))
            self.assertIsNotNone(cue.find("delay"))
            self.assertIn(cue.find("delay").get("exact"), ("500ms", "1s"))
        self.assertEqual(self.cues["HologramSnapshot"].find("delay").get("exact"), "500ms")

    def test_shots_do_not_emit_lua_messages(self):
        for name in ("HologramFired", "HologramHit"):
            cue = self.cues[name]
            self.assertEqual(list(cue.iter("raise_lua_event")), [])
            holds = [node for node in cue.iter("set_value") if "1500ms" in node.get("exact", "")]
            self.assertEqual(len(holds), 1)
        snapshot = self.cues["HologramSnapshot"]
        changed = snapshot.find(".//do_if[@value='$bits != $last']")
        self.assertIsNotNone(changed.find("raise_lua_event"))
        self.assertEqual(len(list(snapshot.iter("raise_lua_event"))), 1)

    def test_hits_require_target_selected_weapon_and_nonmissile_attribution(self):
        cue = self.cues["HologramHit"]
        conditions = cue.find("conditions/check_value").get("value")
        self.assertIn("event.param == $target", conditions)
        self.assertIn("event.param3.{1} == $target", conditions)
        guarded = cue.find("actions/do_if")
        self.assertIn("$selected.{$index}", guarded.get("value"))
        self.assertIn("not $weapon.isclass.missileturret", guarded.get("value"))
        self.assertIsNotNone(guarded.find("set_value[@name='$hit.{$weapon}']"))

    def test_geometry_never_crosses_as_numeric_lengths(self):
        for event in self.root.iter("raise_lua_event"):
            self.assertTrue(event.get("param").startswith("'x4gh1:' + $nonce"))
        ready = self.cues["HologramReady"].find("conditions/check_value").get("value")
        self.assertIn("$turrets.count == $expected", ready)
        self.assertIn("event.param3.$nonce == $nonce", ready)


if __name__ == "__main__":
    unittest.main()
