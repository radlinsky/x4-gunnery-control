"""Protect Test Lab firing-event group resolution through inherited MD namespaces."""
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

print('Test Lab firing-event group contracts passed')
