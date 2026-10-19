# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
"""Isolated firewall and sysctl contracts; never change the host network."""
import copy
import json
import os
from pathlib import Path
import subprocess
import unittest
from unittest import mock
from test_manager import core, PROJECT, TemporaryFixture, example_node


class FirewallTests(unittest.TestCase):
    def setUp(self):
        self.commands = []
        self.rules = set()
        self.ufw = False
        self.firewalld = False
        self.fail_add = False
        self.query_error = False
        self.which = mock.patch.object(core.shutil, 'which', side_effect=lambda name: '/mock/'+name if name in ('ufw', 'firewall-cmd') else None)
        self.run = mock.patch.object(core, 'system_command', side_effect=self.command)
        self.which.start(); self.run.start()
        self.addCleanup(self.which.stop); self.addCleanup(self.run.stop)

    def command(self, args, check=True):
        self.commands.append(args)
        code, output = 0, ''
        if args == ['ufw', 'status']:
            output = 'Status: active\n' if self.ufw else 'Status: inactive\n'
        elif args[:2] == ['ufw', 'allow']:
            self.rules.add(('ufw', args[-1]))
        elif args == ['firewall-cmd', '--state']:
            code, output = (0, 'running') if self.firewalld else (252, 'not running')
        elif args == ['firewall-cmd', '--get-default-zone']: output = 'public\n'
        elif args == ['firewall-cmd', '--get-zones']: output = 'public internal\n'
        elif args[0] == 'firewall-cmd':
            rule = (args[1], '--permanent' in args, args[-1].split('=', 1)[-1])
            if '--query-port=' in args[-1]: code = 13 if self.query_error else (0 if rule in self.rules else 1)
            elif '--add-port=' in args[-1]:
                if self.fail_add: code = 13
                else: self.rules.add(rule)
            else: raise AssertionError(args)
        else: raise AssertionError(args)
        if check and code: raise subprocess.CalledProcessError(code, args)
        return subprocess.CompletedProcess(args, code, stdout=output, stderr='')

    def test_ufw_adds_only_requested_tcp_ports_and_is_idempotent(self):
        self.ufw = True
        core.firewall_allow(['8443', 443, 8443]); core.firewall_allow([443])
        self.assertEqual(self.rules, {('ufw', '443'), ('ufw', '8443')})
        for args in self.commands:
            if args[:2] == ['ufw', 'allow']:
                self.assertEqual(args[2:8], ['in', 'proto', 'tcp', 'to', 'any', 'port'])
        self.assertFalse(any(arg in ('enable', 'disable', 'reset', '--reload') for args in self.commands for arg in args))

    def test_firewalld_updates_runtime_and_permanent_in_chosen_zone(self):
        self.firewalld = True
        core.firewall_allow([443], 'internal'); core.firewall_allow([443], 'internal')
        self.assertEqual(self.rules, {('--zone=internal', True, '443/tcp'), ('--zone=internal', False, '443/tcp')})
        self.assertEqual(sum('--add-port=443/tcp' in args for args in self.commands), 2)

    def test_firewalld_default_zone(self):
        self.firewalld = True
        self.assertEqual(core.firewall_allow([2053]), 'firewalld / public')
        self.assertIn(('--zone=public', False, '2053/tcp'), self.rules)

    def test_inactive_or_multiple_active_backends_make_no_changes(self):
        for ufw, firewalld in [(False, False), (True, True)]:
            self.ufw, self.firewalld = ufw, firewalld
            with self.assertRaisesRegex(ValueError, '未修改'): core.firewall_allow([443])
            self.assertFalse(self.rules)

    def test_invalid_input_or_zone_makes_no_changes(self):
        self.firewalld = True
        for ports, zone in [([], ''), ([0], ''), (['443;id'], ''), ([65536], ''), ([443], '--zone=evil'), ([443], 'missing')]:
            with self.subTest(ports=ports, zone=zone), self.assertRaises(ValueError): core.firewall_allow(ports, zone)
        self.assertFalse(self.rules)

    def test_query_error_is_not_treated_as_absent_rule(self):
        self.firewalld = True; self.query_error = True
        with self.assertRaises(ValueError): core.firewall_allow([443])
        self.assertFalse(self.rules)

    def test_permission_error_does_not_claim_success(self):
        self.firewalld = True; self.fail_add = True
        with self.assertRaises(subprocess.CalledProcessError): core.firewall_allow([443])
        self.assertFalse(self.rules)


class BBRTests(TemporaryFixture):
    def setUp(self):
        super().setUp()
        self.path = self.base/'90-skybyte-xray-bbr.conf'
        self.original = {'net.core.default_qdisc': 'fq_codel', 'net.ipv4.tcp_congestion_control': 'cubic'}
        self.values = copy.deepcopy(self.original)
        self.available = 'reno cubic bbr'
        self.fail = None
        self.silent = False
        self.commands = []
        patch = mock.patch.object(core, 'system_command', side_effect=self.command)
        patch.start(); self.addCleanup(patch.stop)
        patch = mock.patch.object(core.shutil, 'which', return_value='/mock/modprobe')
        patch.start(); self.addCleanup(patch.stop)

    def command(self, args, check=True):
        self.commands.append(args)
        output = ''
        if args[:2] == ['sysctl', '-n']:
            output = self.available if args[2] == 'net.ipv4.tcp_available_congestion_control' else self.values[args[2]]
        elif args[:2] == ['sysctl', '-w']:
            if args[2] == self.fail: raise subprocess.CalledProcessError(1, args)
            k, v = args[2].split('=', 1)
            if not self.silent: self.values[k] = v
        elif args[0] != 'modprobe': raise AssertionError(args)
        return subprocess.CompletedProcess(args, 0, stdout=output+'\n', stderr='')

    def test_enable_repeat_and_restore_original_values(self):
        core.bbr_change(True, self.path)
        self.assertEqual(self.values, core.BBR_VALUES)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o644)
        self.assertEqual(core.bbr_previous(self.path), self.original)
        core.bbr_change(True, self.path)
        core.bbr_change(False, self.path)
        self.assertEqual(self.values, self.original)
        self.assertFalse(self.path.exists())

    def test_unsupported_kernel_does_not_persist_or_change_values(self):
        self.available = 'reno cubic'
        with self.assertRaisesRegex(ValueError, '不支持'): core.bbr_change(True, self.path)
        self.assertEqual(self.values, self.original)
        self.assertFalse(self.path.exists())
        self.assertIn(['modprobe', 'tcp_bbr'], self.commands)

    def test_failed_second_setting_restores_first_and_removes_new_file(self):
        self.fail = 'net.ipv4.tcp_congestion_control=bbr'
        with self.assertRaises(subprocess.CalledProcessError): core.bbr_change(True, self.path)
        self.assertEqual(self.values, self.original)
        self.assertFalse(self.path.exists())

    def test_failed_restore_retains_managed_file_and_enabled_values(self):
        core.bbr_change(True, self.path)
        data = self.path.read_bytes()
        self.fail = 'net.ipv4.tcp_congestion_control=cubic'
        with self.assertRaises(subprocess.CalledProcessError): core.bbr_change(False, self.path)
        self.assertEqual(self.values, core.BBR_VALUES)
        self.assertEqual(self.path.read_bytes(), data)

    def test_silent_failure_detected(self):
        self.silent = True
        with self.assertRaisesRegex(ValueError, '未生效'): core.bbr_change(True, self.path)
        self.assertFalse(self.path.exists())

    def test_foreign_modified_or_symlink_file_refused(self):
        self.path.write_text('foreign')
        with self.assertRaises(ValueError): core.bbr_change(True, self.path)
        self.assertEqual(self.path.read_text(), 'foreign')
        self.path.write_text(core.bbr_content(self.original)+'net.ipv4.ip_forward=1\n')
        with self.assertRaises(ValueError): core.bbr_change(False, self.path)
        self.path.unlink(); outside = self.base/'outside'; outside.write_text('keep')
        self.path.symlink_to(outside)
        with self.assertRaises(ValueError): core.bbr_change(True, self.path)
        self.assertEqual(outside.read_text(), 'keep')
        self.assertFalse(any(a[:2] == ['sysctl', '-w'] for a in self.commands))

    def test_unmanaged_restore_refused(self):
        with self.assertRaisesRegex(ValueError, '没有'): core.bbr_change(False, self.path)
        self.assertEqual(self.values, self.original)

    def test_failed_rollback_keeps_recovery_record(self):
        self.fail = 'net.ipv4.tcp_congestion_control=bbr'
        with mock.patch.object(core, 'rollback_network_values', return_value=False):
            with self.assertRaisesRegex(ValueError, '回退未完成'): core.bbr_change(True, self.path)
        self.assertEqual(core.bbr_previous(self.path), self.original)


class NetworkMenuTests(TemporaryFixture):
    def shell(self, inputs, language='zh'):
        log = self.base/'helper.log'
        script = 'source "$1"; helper(){ printf "%s\\n" "$*" >> "$HELPER_LOG"; }; LANGUAGE="$2"; network_menu'
        result = subprocess.run(['bash', '-c', script, 'test', str(PROJECT/'xray-manager.sh'), language],
            input=inputs, text=True, capture_output=True, env={**os.environ, 'HELPER_LOG':str(log), 'NO_COLOR':'1'})
        calls = log.read_text().splitlines() if log.exists() else []
        if log.exists(): log.unlink()
        return result, calls

    def test_custom_port_confirmation_and_cancellation_in_both_languages(self):
        for language in ['zh', 'en']:
            result, calls = self.shell('3\n8443\npublic\nYES\n', language)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('firewall-allow --ports 8443 --zone public', calls)
            result, calls = self.shell('3\n8443\n\nno\n', language)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(any(c.startswith('firewall-allow') for c in calls))

    def test_invalid_tcp_port_refused_before_firewall_operation(self):
        for value in ['0', '65536', '443;id', '', '99999999999999999999']:
            result, calls = self.shell('3\n'+value+'\n')
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(calls)

    def test_bbr_requires_confirmation(self):
        result, calls = self.shell('5\nno\n')
        self.assertEqual(result.returncode, 0); self.assertFalse(calls)
        result, calls = self.shell('5\nYES\n')
        self.assertEqual(result.returncode, 0); self.assertEqual(calls, ['bbr-enable', 'bbr-status'])
        result, calls = self.shell('6\nYES\n')
        self.assertEqual(result.returncode, 0); self.assertEqual(calls, ['bbr-restore', 'bbr-status'])

    def test_node_port_preview_contains_no_credentials(self):
        core.ensure_owned(self.root, True)
        state = {'schema':1, 'nodes':{'vision':example_node()}}
        core.write_private(self.root/'state.json', core.json_text(state))
        result = subprocess.run([os.sys.executable, str(PROJECT/'src/core.py'), 'node-ports', '--root', str(self.root)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('TCP '+str(state['nodes']['vision']['port']), result.stdout)
        for field in ['uuid', 'private', 'public', 'short_id']:
            self.assertNotIn(state['nodes']['vision'][field], result.stdout)
