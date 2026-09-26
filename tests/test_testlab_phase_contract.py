"""Protect Test Lab event-group resolution and complete phase firing inhibition."""
from pathlib import Path
import xml.etree.ElementTree as ET


def check_event_groups(path):
    root = ET.parse(path).getroot()
    groups, events = set(), []

    def walk(node, namespace=None):
        if node.tag == 'cue':
            if namespace is None or node.get('namespace', 'default') != 'default':
                namespace = node.get('name')
        if node.tag == 'create_group':
            groups.add((namespace, node.get('groupname')))
        if node.tag == 'event_weapon_fired' and node.get('group'):
            events.append((namespace, node.get('group')))
        for child in node:
            walk(child, namespace)

    walk(root)
    for namespace, expression in events:
        if '.$' in expression:
            namespace, variable = expression.split('.', 1)
        else:
            variable = expression
        assert (namespace, variable) in groups, (
            path, 'firing listener group has no writer in its namespace', expression)


for path in Path('testlab/x4_gunnery_control_testlab/md').glob('*.xml'):
    check_event_groups(path)

root = ET.parse('testlab/x4_gunnery_control_testlab/md/'
                'x4_gunnery_control_testlab_scenario.xml').getroot()
start = root.find(".//cue[@name='MissilePhaseStart']/actions")
stop = root.find(".//cue[@name='MissilePhaseStop']/actions")
# With only two missile emitters, inhibit every system rather than guessing a
# turret-class-to-ammunition-system mapping. Failed validation never allows fire.
for actions in (start, stop):
    inhibit = actions.find('set_allowed_weapon_systems')
    assert inhibit.get('disallow') == 'all' and inhibit.get('immediate') == 'true'
allow = start.find("do_if[@value='$Valid']/set_allowed_weapon_systems")
assert allow is not None and allow.get('allow') == 'all'
assert start.find('do_else/set_allowed_weapon_systems') is None
assert not any('$PendingRequestId' in value
               for node in start.iter('debug_text') for value in node.attrib.values())
shot = root.find(".//cue[@name='MissilePhaseShot']/actions")
assert shot.find("set_value[@name='ScenarioRoot.$MissilePhaseShots']").get('operation') == 'add'
assert shot.find(".//signal_cue_instantly[@cue='MissilePhaseStop']") is not None
print('Test Lab phase contracts passed')
