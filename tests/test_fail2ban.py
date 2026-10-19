# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
"""Fail2ban/UFW coexistence contracts; all commands here are isolated mocks."""
import contextlib
import copy
import io
import json
import os
import subprocess
import unittest
from unittest import mock
from test_manager import core, TemporaryFixture


def fail2ban_rules():
    # The reported nft 1.1.3 layout, using documentation addresses.
    items = [
        {'metainfo': {'json_schema_version': 1}},
        {'table': {'family': 'inet', 'name': 'f2b-table', 'handle': 1}},
        {'chain': {'family': 'inet', 'table': 'f2b-table', 'name': 'f2b-chain', 'handle': 1,
                   'type': 'filter', 'hook': 'input', 'prio': -1, 'policy': 'accept'}},
        {'set': {'family': 'inet', 'table': 'f2b-table', 'name': 'addr-set-sshd', 'type': 'ipv4_addr',
                 'handle': 2, 'elem': ['198.51.100.116', '198.51.100.173']}},
        {'rule': {'family': 'inet', 'table': 'f2b-table', 'chain': 'f2b-chain', 'handle': 4, 'expr': [
            {'match': {'op': '==', 'left': {'payload': {'protocol': 'tcp', 'field': 'dport'}}, 'right': 22}},
            {'match': {'op': '==', 'left': {'payload': {'protocol': 'ip', 'field': 'saddr'}}, 'right': '@addr-set-sshd'}},
            {'reject': {'type': 'icmp', 'expr': 'port-unreachable'}}]}}
    ]
    for family in ['ip', 'ip6']:
        items.append({'table': {'family': family, 'name': 'filter'}})
        for name, hook in [('INPUT', 'input'), ('OUTPUT', 'output'), ('FORWARD', 'forward')]:
            items.append({'chain': {'family': family, 'table': 'filter', 'name': name,
                'type': 'filter', 'hook': hook, 'prio': 0, 'policy': 'accept'}})
    return items


class Fail2banInspectionTests(unittest.TestCase):
    def test_reported_layout_coexists_without_modifying_ban_elements(self):
        items = fail2ban_rules(); before = copy.deepcopy(items)
        conflict, preserved = core.nft_inspect(json.dumps({'nftables': items}))
        self.assertIsNone(conflict)
        self.assertEqual(len(preserved), 4)
        self.assertEqual(items, before)

    def test_dual_stack_multiport_drop_and_interval_sets(self):
        items = fail2ban_rules()
        ipv6_set, ipv6_rule = copy.deepcopy(items[3:5])
        ipv6_set['set'].update(name='addr6-set-sshd', type='ipv6_addr', flags=['interval'], elem=['2001:db8::1'])
        ipv6_rule['rule']['expr'][0]['match']['right'] = {'set': [22, 2222]}
        ipv6_rule['rule']['expr'][1]['match'].update(
            left={'payload': {'protocol': 'ip6', 'field': 'saddr'}}, right='@addr6-set-sshd')
        ipv6_rule['rule']['expr'][-1] = {'drop': None}
        items.extend([ipv6_set, ipv6_rule])
        self.assertIsNone(core.nft_conflict(json.dumps({'nftables': items})))
        self.assertEqual(len(core.nft_fail2ban_signature(items)), 6)

    def test_ban_and_counter_updates_do_not_change_structure_signature(self):
        items = fail2ban_rules(); signature = core.nft_fail2ban_signature(items)
        items[3]['set']['elem'] = ['203.0.113.25']
        items[4]['rule']['expr'].insert(-1, {'counter': {'packets': 100, 'bytes': 6000}})
        items[4]['rule']['handle'] = 99
        self.assertEqual(core.nft_fail2ban_signature(items), signature)

    def test_table_name_alone_does_not_bypass_existing_rules(self):
        for verdict in [{'accept': None}, {'jump': {'target': 'other'}}, {'dnat': {'addr': '198.51.100.9'}}]:
            items = fail2ban_rules(); items[4]['rule']['expr'][-1] = verdict
            with self.subTest(verdict=verdict):
                self.assertIsNotNone(core.nft_conflict(json.dumps({'nftables': items})))

    def test_changed_hook_priority_policy_or_extra_chain_remains_guarded(self):
        for key, value in [('hook', 'forward'), ('prio', 0), ('policy', 'drop'), ('type', 'nat')]:
            items = fail2ban_rules(); items[2]['chain'][key] = value
            with self.subTest(key=key):
                self.assertIsNotNone(core.nft_conflict(json.dumps({'nftables': items})))
        items = fail2ban_rules()
        items.append({'chain': {'family': 'inet', 'table': 'f2b-table', 'name': 'custom'}})
        self.assertIsNotNone(core.nft_conflict(json.dumps({'nftables': items})))

    def test_unbounded_wrong_family_and_missing_set_references_remain_guarded(self):
        for change in ['missing-source', 'wrong-family', 'unknown-set', 'negated', 'invalid-port', 'map']:
            items = fail2ban_rules(); expressions = items[4]['rule']['expr']
            if change == 'missing-source': expressions.pop(1)
            elif change == 'wrong-family': expressions[1]['match']['left']['payload']['protocol'] = 'ip6'
            elif change == 'unknown-set': expressions[1]['match']['right'] = '@unknown'
            elif change == 'negated': expressions[1]['match']['op'] = '!='
            elif change == 'invalid-port': expressions[0]['match']['right'] = 0
            elif change == 'map': items[3]['set']['type'] = 'verdict'
            with self.subTest(change=change):
                self.assertIsNotNone(core.nft_conflict(json.dumps({'nftables': items})))

    def test_other_native_rules_and_iptables_fail2ban_are_still_guarded(self):
        items = fail2ban_rules()
        items.append({'rule': {'family': 'ip', 'table': 'filter', 'chain': 'INPUT', 'expr': [{'accept': None}]}})
        self.assertIn('rule ip/filter/INPUT', core.nft_conflict(json.dumps({'nftables': items})))
        self.assertIsNotNone(core.iptables_conflict('*filter\n:INPUT ACCEPT [0:0]\n-A INPUT -j f2b-sshd\nCOMMIT\n'))

    def test_malformed_set_and_unknown_objects_are_not_whitelisted(self):
        for field, value in [('name', ['bad']), ('flags', None), ('elem', None), ('type', 'integer')]:
            items = fail2ban_rules(); items[3]['set'][field] = value
            with self.subTest(field=field):
                self.assertIsNotNone(core.nft_conflict(json.dumps({'nftables': items})))
        items = fail2ban_rules()
        items.append({'flowtable': {'family': 'inet', 'table': 'f2b-table', 'name': 'offload'}})
        self.assertIsNotNone(core.nft_conflict(json.dumps({'nftables': items})))


class Fail2banSetupTests(TemporaryFixture):
    def setUp(self):
        super().setUp()
        self.config = self.base/'ufw-default'; self.config.write_text('IPV6=yes\n')
        self.items = fail2ban_rules(); self.active = False; self.calls = []
        self.on_enable = None; self.fail_enable = False
        patch = mock.patch.dict(os.environ, {'SSH_CONNECTION': ''})
        patch.start(); self.addCleanup(patch.stop)
        patch = mock.patch.object(core.shutil, 'which', side_effect=lambda name:
            '/mock/'+name if name in ('nft', 'ufw', 'iptables-save') else None)
        patch.start(); self.addCleanup(patch.stop)
        patch = mock.patch.object(core, 'system_command', side_effect=self.command)
        patch.start(); self.addCleanup(patch.stop)

    def command(self, args, check=True):
        self.calls.append(args)
        output = ''
        if args == ['ufw', 'status']: output = 'Status: active' if self.active else 'Status: inactive'
        elif args == ['nft', '-j', 'list', 'ruleset']: output = json.dumps({'nftables': self.items})
        elif args == ['iptables-save']: output = '*filter\n:INPUT ACCEPT [0:0]\nCOMMIT\n'
        elif args == ['ufw', 'show', 'added']: pass
        elif args[:3] == ['ufw', 'prepend', 'allow']: pass
        elif args[:2] == ['ufw', 'default']: pass
        elif args == ['ufw', '--force', 'enable']:
            self.active = True
            if self.on_enable: self.on_enable()
            if self.fail_enable: raise subprocess.CalledProcessError(1, args)
        elif args == ['ufw', '--force', 'disable']: self.active = False
        else: raise AssertionError(args)
        return subprocess.CompletedProcess(args, 0, stdout=output, stderr='')

    def test_enable_preserves_existing_bans_and_only_changes_ufw(self):
        before = copy.deepcopy(self.items)
        self.assertTrue(core.firewall_setup(self.root, ['22'], ['443'], self.config))
        self.assertTrue(self.active)
        self.assertEqual(self.items, before)
        self.assertEqual(self.calls.count(['nft', '-j', 'list', 'ruleset']), 2)
        self.assertFalse(any(args[0] in ('fail2ban-client', 'systemctl') for args in self.calls))
        self.assertFalse(any(args[0] == 'nft' and args != ['nft', '-j', 'list', 'ruleset'] for args in self.calls))

    def test_new_ban_during_enable_is_allowed(self):
        self.on_enable = lambda: self.items[3]['set']['elem'].append('203.0.113.99')
        self.assertTrue(core.firewall_setup(self.root, ['22'], [], self.config))
        self.assertTrue(self.active)

    def test_missing_fail2ban_rules_after_enable_disables_ufw_and_reports_recovery(self):
        self.on_enable = lambda: self.items.clear()
        with self.assertRaisesRegex(ValueError, '控制台'):
            core.firewall_setup(self.root, ['22'], [], self.config)
        self.assertFalse(self.active)
        self.assertIn(['ufw', '--force', 'disable'], self.calls)

    def test_failed_activation_rolls_back_and_rechecks_existing_fail2ban(self):
        self.fail_enable = True; before = copy.deepcopy(self.items)
        with self.assertRaises(ValueError): core.firewall_setup(self.root, ['22'], [], self.config)
        self.assertFalse(self.active)
        self.assertEqual(self.items, before)
        self.assertEqual(self.calls.count(['nft', '-j', 'list', 'ruleset']), 2)

    def test_unsupported_custom_fail2ban_rules_stop_before_any_ufw_change(self):
        self.items[4]['rule']['expr'][-1] = {'accept': None}
        with self.assertRaisesRegex(ValueError, '已有规则'):
            core.firewall_setup(self.root, ['22'], [], self.config)
        self.assertFalse(any(args[:2] in (['ufw', 'prepend'], ['ufw', 'default'], ['ufw', '--force']) for args in self.calls))

    def test_cli_preview_explains_coexistence_without_listing_banned_addresses(self):
        output = io.StringIO()
        with mock.patch('sys.argv', ['core.py', 'firewall-setup-check']), contextlib.redirect_stdout(output):
            core.main()
        self.assertIn('Fail2ban', output.getvalue())
        self.assertIn('保留', output.getvalue())
        self.assertNotIn('198.51.100.', output.getvalue())

