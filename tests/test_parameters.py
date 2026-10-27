"""Node parameter views do not disclose private keys or change deployment state."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
from test_manager import core, example_node, PROJECT


class ParameterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()/'manager'

    def install_state(self, kinds=core.KINDS):
        core.ensure_owned(self.root, create=True)
        nodes = {kind: example_node(kind) for kind in kinds}
        for i, node in enumerate(nodes.values()):
            node['port'] = 4400+i
        state = {'schema': 1, 'nodes': nodes}
        core.write_private(self.root/'state.json', core.json_text(state))
        return state

    def snapshot(self):
        return {str(p): (p.read_bytes(), p.stat().st_mtime_ns, p.stat().st_mode)
                for p in self.root.rglob('*') if p.is_file()}

    def test_all_nodes_fields_privacy_and_read_only_in_both_languages(self):
        state = self.install_state()
        before = self.snapshot()
        with mock.patch.object(core.urllib.request, 'urlopen', side_effect=AssertionError('Network request')), mock.patch.object(core.subprocess, 'run', side_effect=AssertionError('System command')):
            for language in ('zh', 'en'):
                output = core.node_parameters(self.root, language)
                for kind, node in state['nodes'].items():
                    for value in (kind, node['uuid'], node['sni'], str(node['port'])):
                        self.assertIn(value, output)
                    if kind != 'xhttp-tls':
                        for field in ('public', 'short_id', 'target'):
                            self.assertIn(node[field], output)
                        self.assertNotIn(node['private'], output)
                    else:
                        self.assertNotIn(node['key'], output)
                for value in ('VPS', 'SSH', 'l → 2', 'Short ID'):
                    self.assertIn(value, output)
                self.assertIn('KEEP PRIVATE' if language == 'en' else '保密提醒', output)
                self.assertIn('Not applicable' if language == 'en' else '不适用', output)
        self.assertEqual(before, self.snapshot())

    def test_missing_and_empty_state_do_not_create_files(self):
        self.assertIn('尚未安装节点', core.node_parameters(self.root))
        self.assertFalse(self.root.exists())
        self.install_state(())
        before = self.snapshot()
        self.assertIn('No nodes installed', core.node_parameters(self.root, 'en'))
        self.assertEqual(before, self.snapshot())

    def test_unknown_owner_and_symlinks_are_refused(self):
        self.install_state()
        (self.root/'.owner').write_text('foreign')
        with self.assertRaises(ValueError):
            core.node_parameters(self.root)
        (self.root/'.owner').write_text(core.OWNER)
        state = self.root/'state.json'
        elsewhere = self.root.parent/'external.json'
        state.rename(elsewhere)
        state.symlink_to(elsewhere)
        with self.assertRaises(ValueError):
            core.node_parameters(self.root)

    def test_bundled_shell_entry_shows_parameters_without_exports(self):
        state = self.install_state(('vision',))
        before = self.snapshot()
        result = subprocess.run(['bash', '-c', 'source "$1";LANGUAGE=en;show_parameters',
                                 'test', str(PROJECT/'xray-manager.sh')], capture_output=True, text=True,
                                env={**os.environ, 'SKYBYTE_XRAY_DIR': str(self.root), 'NO_COLOR': '1'}, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(state['nodes']['vision']['uuid'], result.stdout)
        self.assertIn('KEEP PRIVATE', result.stdout)
        self.assertNotIn(state['nodes']['vision']['private'], result.stdout)
        self.assertEqual(before, self.snapshot())
