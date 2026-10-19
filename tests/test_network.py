# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
"""Isolated firewall and sysctl contracts; never change the host network."""
import copy
import json
import os
import shutil
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
            result, calls = self.shell('4\n8443\npublic\nYES\n', language)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('firewall-allow --ports 8443 --zone public', calls)
            result, calls = self.shell('4\n8443\n\nno\n', language)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(any(c.startswith('firewall-allow') for c in calls))

    def test_invalid_tcp_port_refused_before_firewall_operation(self):
        for value in ['0', '65536', '443;id', '', '99999999999999999999']:
            result, calls = self.shell('4\n'+value+'\n')
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(calls)

    def test_bbr_requires_confirmation(self):
        result, calls = self.shell('7\nno\n')
        self.assertEqual(result.returncode, 0); self.assertFalse(calls)
        result, calls = self.shell('7\nYES\n')
        self.assertEqual(result.returncode, 0); self.assertEqual(calls, ['bbr-enable', 'bbr-status'])
        result, calls = self.shell('8\nYES\n')
        self.assertEqual(result.returncode, 0); self.assertEqual(calls, ['bbr-restore', 'bbr-status'])

    def test_grouped_menu_and_renumbered_status_and_all_ports_in_both_languages(self):
        for language, labels in [('zh', ['防火墙', '1 查看防火墙状态', '2 安装并启用 UFW',
                '3 放行全部节点 TCP 端口', '4 放行指定 TCP 端口', '5 停用/卸载 UFW',
                'BBR', '6 查看 BBR 状态', '7 启用 BBR + fq', '8 恢复启用前参数', '0 返回']),
                ('en', ['Firewall', '1 Show firewall status', '2 Install and enable UFW',
                '3 Allow all node TCP ports', '4 Allow a TCP port', '5 Disable/remove UFW',
                'BBR', '6 Show BBR status', '7 Enable BBR + fq', '8 Restore previous settings', '0 Back'])]:
            result, calls = self.shell('0\n', language)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(calls)
            lines = result.stdout.splitlines()
            positions = [lines.index(label) for label in labels]
            self.assertEqual(positions, sorted(positions))
            result, calls = self.shell('1\n', language)
            self.assertEqual(calls, ['firewall-status'])
            result, calls = self.shell('6\n', language)
            self.assertEqual(calls, ['bbr-status'])
            result, calls = self.shell('3\n\nYES\n', language)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls, ['firewall-status', 'node-ports', 'firewall-allow'])

    def test_node_port_preview_contains_no_credentials(self):
        core.ensure_owned(self.root, True)
        state = {'schema':1, 'nodes':{'vision':example_node()}}
        core.write_private(self.root/'state.json', core.json_text(state))
        result = subprocess.run([os.sys.executable, str(PROJECT/'src/core.py'), 'node-ports', '--root', str(self.root)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('TCP '+str(state['nodes']['vision']['port']), result.stdout)
        for field in ['uuid', 'private', 'public', 'short_id']:
            self.assertNotIn(state['nodes']['vision'][field], result.stdout)


class FirewallSetupTests(TemporaryFixture):
    def setUp(self):
        super().setUp()
        self.config = self.base/'ufw-defaults'; self.config.write_text('IPV6=yes\n')
        self.commands = []; self.active = False; self.firewalld = False
        self.raw = False; self.fail_allow = False; self.fail_enable = False; self.fail_disable = False
        self.added = ''; self.ufw_installed = True
        patch = mock.patch.dict(os.environ, {'SSH_CONNECTION':''}); patch.start(); self.addCleanup(patch.stop)
        patch = mock.patch.object(core.shutil, 'which', side_effect=lambda name:
            '/mock/'+name if name in ('nft', 'iptables-save', 'firewall-cmd') or (name == 'ufw' and self.ufw_installed) else None)
        patch.start(); self.addCleanup(patch.stop)
        patch = mock.patch.object(core, 'system_command', side_effect=self.command)
        patch.start(); self.addCleanup(patch.stop)

    def command(self, args, check=True):
        self.commands.append(args)
        code, output = 0, ''
        if args == ['ufw', 'status']: output = 'Status: active\n' if self.active else 'Status: inactive\n'
        elif args == ['firewall-cmd', '--state']: code, output = (0, 'running') if self.firewalld else (252, 'not running')
        elif args == ['nft', '-j', 'list', 'ruleset']: output = json.dumps({'nftables':[{'rule':{'family':'inet','table':'custom','chain':'input','expr':[{'accept':None}]}}] if self.raw else []})
        elif args == ['iptables-save']: output = '*filter\n:INPUT ACCEPT [0:0]\nCOMMIT\n'
        elif args == ['ufw', 'show', 'added']: output = self.added
        elif args[:3] == ['ufw', 'prepend', 'allow']:
            if self.fail_allow: code = 1
        elif args[:2] == ['ufw', 'default']: pass
        elif args == ['ufw', '--force', 'enable']:
            self.active = True
            if self.fail_enable: code = 1
        elif args == ['ufw', '--force', 'disable']:
            if self.fail_disable: code = 1
            else: self.active = False
        else: raise AssertionError(args)
        if check and code: raise subprocess.CalledProcessError(code, args)
        return subprocess.CompletedProcess(args, code, stdout=output, stderr='')

    def test_ssh_and_node_ports_staged_before_enable(self):
        core.ensure_owned(self.root, True)
        node = example_node(); node['port'] = 8443
        core.write_private(self.root/'state.json', core.json_text({'schema':1, 'nodes':{'vision':node}}))
        with mock.patch.dict(os.environ, {'SSH_CONNECTION':'203.0.113.1 50000 203.0.113.2 2222'}):
            core.firewall_setup(self.root, ['22'], ['80', '443'], self.config)
        allows = [a for a in self.commands if a[:3] == ['ufw','prepend','allow']]
        self.assertEqual([a[-1] for a in allows], ['22', '2222', '80', '443', '8443'])
        enable_index = self.commands.index(['ufw','--force','enable'])
        self.assertTrue(all(self.commands.index(a) < enable_index for a in allows))
        self.assertIn(['ufw','default','deny','incoming'], self.commands)
        self.assertIn(['ufw','default','allow','outgoing'], self.commands)
        self.assertTrue(self.active)
        self.assertEqual(core.load_state(self.root)['nodes']['vision'], node)

    def test_existing_firewall_or_native_rules_refused(self):
        for kind in ['ufw','firewalld','raw']:
            self.active = kind == 'ufw'; self.firewalld = kind == 'firewalld'; self.raw = kind == 'raw'
            self.commands.clear()
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                core.firewall_setup(self.root, ['2222'], [], self.config)
            self.assertFalse(any(a[:2] in (['ufw','prepend'], ['ufw','default'], ['ufw','--force']) for a in self.commands))

    def test_unreadable_kernel_rules_never_attempts_activation(self):
        command = self.command
        def denied(args, check=True):
            if args == ['nft','-j','list','ruleset']:
                raise subprocess.CalledProcessError(1, args)
            return command(args, check)
        with mock.patch.object(core, 'system_command', side_effect=denied):
            with self.assertRaisesRegex(ValueError, '已停止'):
                core.firewall_setup(self.root, ['2222'], [], self.config)
        self.assertFalse(self.active)
        self.assertNotIn(['ufw','--force','enable'], self.commands)

    def test_ipv6_disabled_and_restrictive_stored_rules_refused(self):
        for config, added in [('IPV6=no\n',''), ('IPV6=yes\nIPV6=no\n',''), ('IPV6=yes\n','ufw deny 2222/tcp\n')]:
            self.config.write_text(config); self.added = added
            with self.subTest(config=config, added=added), self.assertRaises(ValueError):
                core.firewall_setup(self.root, ['2222'], [], self.config)
        self.assertFalse(self.active)
        self.assertNotIn(['ufw','--force','enable'], self.commands)

    def test_missing_invalid_ssh_or_malformed_connection_refused(self):
        for ssh in [[], ['0'], ['22;id']]:
            with self.subTest(ssh=ssh), self.assertRaises(ValueError): core.firewall_setup(self.root, ssh, [], self.config)
        with mock.patch.dict(os.environ, {'SSH_CONNECTION':'malformed'}):
            with self.assertRaises(ValueError): core.firewall_setup(self.root, ['22'], [], self.config)
        self.assertFalse(self.commands)

    def test_rule_failure_never_enables_firewall(self):
        self.fail_allow = True
        with self.assertRaises(ValueError): core.firewall_setup(self.root, ['2222'], [], self.config)
        self.assertFalse(self.active)
        self.assertNotIn(['ufw','--force','enable'], self.commands)

    def test_failed_enable_rolls_back_to_inactive(self):
        self.fail_enable = True
        with self.assertRaises(ValueError): core.firewall_setup(self.root, ['2222'], [], self.config)
        self.assertFalse(self.active)
        self.assertIn(['ufw','--force','disable'], self.commands)

    def test_failed_disable_reports_console_recovery(self):
        self.fail_enable = True; self.fail_disable = True
        with self.assertRaisesRegex(ValueError, '控制台'): core.firewall_setup(self.root, ['2222'], [], self.config)
        self.assertTrue(self.active)

    def test_missing_ufw_never_attempts_enable(self):
        self.ufw_installed = False
        with self.assertRaisesRegex(ValueError, '先安装'): core.firewall_setup(self.root, ['22'], [], self.config)
        self.assertNotIn(['ufw','--force','enable'], self.commands)


class FirewallInstallMenuTests(TemporaryFixture):
    def shell(self, inputs, apt_fail=False, language='zh'):
        log = self.base/'log'
        script = '''source "$1"
helper(){ printf '%s\\n' "$*" >> "$SETUP_LOG"; }
command(){ if [[ $1 == -v && $2 == ufw ]]; then return 1; fi; builtin command "$@"; }
apt_refresh(){ printf 'apt-refresh\\n' >> "$SETUP_LOG"; }
apt-get(){ printf '%s\\n' "apt-get $*" >> "$SETUP_LOG"; [[ $APT_FAIL == no ]]; }
LANGUAGE="$2"
if network_menu; then exit 0; else exit 1; fi
'''
        result = subprocess.run(['bash','-c',script,'test',str(PROJECT/'xray-manager.sh'),language],
            input=inputs,text=True,capture_output=True,env={**os.environ,'SSH_CONNECTION':'203.0.113.1 50000 203.0.113.2 2222',
            'SETUP_LOG':str(log),'APT_FAIL':'yes' if apt_fail else 'no'})
        calls = log.read_text().splitlines() if log.exists() else []
        if log.exists(): log.unlink()
        return result, calls

    def test_install_then_enable_after_confirmation_in_both_languages(self):
        for language in ['zh','en']:
            result, calls = self.shell('2\n\n80 443\nYES\n', language=language)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn('apt-get install -y ufw', calls)
            setup = 'firewall-setup --ssh-ports 2222 --ports 80 443'
            self.assertIn(setup, calls)
            self.assertLess(calls.index('apt-get install -y ufw'), calls.index(setup))

    def test_cancellation_does_not_install_or_enable(self):
        result, calls = self.shell('2\n\n\nno\n')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse(any(c.startswith('apt-') or c.startswith('firewall-setup --') for c in calls))

    def test_failed_package_install_does_not_enable(self):
        result, calls = self.shell('2\n\n\nYES\n', apt_fail=True)
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(any(c.startswith('firewall-setup --') for c in calls))


class NetfilterInspectionTests(unittest.TestCase):
    def test_empty_tables_and_accept_chains_are_not_firewall_rules(self):
        entries = [{'metainfo':{'json_schema_version':1}}, {'table':{'family':'ip','name':'filter'}},
                   {'chain':{'family':'ip','table':'filter','name':'INPUT','type':'filter','hook':'input','prio':0,'policy':'accept'}},
                   {'chain':{'family':'ip','table':'filter','name':'unused'}}]
        self.assertIsNone(core.nft_conflict(json.dumps({'nftables':entries})))
        self.assertIsNone(core.iptables_conflict('# Generated\n*filter\n:INPUT ACCEPT [2:10]\n:unused - [0:0]\nCOMMIT\n'))

    def test_active_accept_nat_rules_and_drop_policy_are_still_guarded(self):
        for expr in [[{'accept':None}], [{'masquerade':None}]]:
            state = {'nftables':[{'rule':{'family':'ip','table':'nat','chain':'POSTROUTING','expr':expr}}]}
            self.assertIn('rule ip/nat/POSTROUTING', core.nft_conflict(json.dumps(state)))
        state = {'nftables':[{'chain':{'family':'inet','table':'filter','name':'input','hook':'input','policy':'drop'}}]}
        self.assertIn('policy=drop', core.nft_conflict(json.dumps(state)))
        self.assertIn('policy=DROP', core.iptables_conflict('*filter\n:INPUT DROP [0:0]\nCOMMIT'))
        self.assertIn('rule nat/POSTROUTING', core.iptables_conflict('*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -j MASQUERADE\nCOMMIT'))

    def test_unknown_objects_and_unparseable_output_do_not_pass(self):
        for text in ['', 'table inet filter {}', '{}', '{"nftables":null}', '{"nftables":[null]}']:
            with self.subTest(text=text), self.assertRaises(ValueError): core.nft_conflict(text)
        self.assertIsNotNone(core.nft_conflict('{"nftables":[{"set":{"family":"ip","table":"x","name":"x"}}]}'))
        self.assertIsNotNone(core.iptables_conflict('*filter\n:INPUT\nCOMMIT'))
        self.assertIsNotNone(core.iptables_conflict('unknown output'))

    def test_kernel_names_are_sanitized_in_diagnostics(self):
        state = {'nftables':[{'rule':{'family':'inet','table':'bad\x1b[31m\nname','chain':'input','expr':[{'drop':None}]}}]}
        message = core.nft_conflict(json.dumps(state))
        self.assertNotIn('\x1b', message); self.assertNotIn('\n', message)

    def test_two_inspections_allow_default_tables_created_by_iptables_query(self):
        queried = False
        def command(args, check=True):
            nonlocal queried
            if args == ['nft','-j','list','ruleset']:
                output = json.dumps({'nftables':[{'table':{'family':'ip','name':'filter'}},
                    {'chain':{'family':'ip','table':'filter','name':'INPUT','hook':'input','policy':'accept'}}] if queried else []})
            elif args == ['iptables-save']:
                queried = True; output = '*filter\n:INPUT ACCEPT [0:0]\nCOMMIT\n'
            else: raise AssertionError(args)
            return subprocess.CompletedProcess(args,0,stdout=output,stderr='')
        with mock.patch.object(core,'firewall_status',return_value={'ufw':'inactive','firewalld':'unavailable'}), \
             mock.patch.object(core.shutil,'which',side_effect=lambda name: name if name in ('nft','iptables-save') else None), \
             mock.patch.object(core,'system_command',side_effect=command):
            core.firewall_setup_check(); core.firewall_setup_check()

    def test_conflict_reports_exact_command_table_and_chain(self):
        def command(args, check=True):
            if args == ['nft','-j','list','ruleset']:
                output = '{"nftables":[]}'
            elif args == ['ip6tables-save']:
                output = '*filter\n:INPUT DROP [0:0]\nCOMMIT\n'
            else: raise AssertionError(args)
            return subprocess.CompletedProcess(args,0,stdout=output,stderr='')
        with mock.patch.object(core,'firewall_status',return_value={'ufw':'unavailable','firewalld':'unavailable'}), \
             mock.patch.object(core.shutil,'which',side_effect=lambda name: name if name in ('nft','ip6tables-save') else None), \
             mock.patch.object(core,'system_command',side_effect=command):
            with self.assertRaisesRegex(ValueError,'ip6tables-save / filter/INPUT policy=DROP'):
                core.firewall_setup_check()


class UFWDiagnosticTests(unittest.TestCase):
    def test_failed_step_reports_command_and_safe_reason(self):
        error = subprocess.CalledProcessError(1, ['ufw'], stderr="ERROR: Invalid position '1'\nsecret-token-value")
        with mock.patch.object(core,'system_command',side_effect=error):
            with self.assertRaises(ValueError) as caught:
                core.ufw_command(['prepend','allow','2222/tcp'])
        message = str(caught.exception)
        self.assertIn('ufw prepend allow 2222/tcp', message)
        self.assertIn('空规则列表位置无效', message)
        self.assertNotIn('secret-token-value', message)

    def test_permission_and_timeout_have_ufw_context(self):
        failures = [subprocess.CalledProcessError(1,['ufw'],stderr='Permission denied private-details'),
                    subprocess.TimeoutExpired(['ufw'],30)]
        for error in failures:
            with mock.patch.object(core,'system_command',side_effect=error):
                with self.assertRaises(ValueError) as caught: core.ufw_command(['status'])
            self.assertIn('UFW',str(caught.exception))
            self.assertNotIn('private-details',str(caught.exception))


# Distro frontend compatibility without a real netfilter backend. CI installs ufw.
import importlib.util
HAS_UFW = importlib.util.find_spec('ufw') is not None


@unittest.skipUnless(HAS_UFW, 'Install the distro ufw Python package for upstream frontend checks')
class UpstreamUFWFrontendTests(unittest.TestCase):
    def setUp(self):
        import builtins
        import ufw.frontend
        import ufw.common
        patch = mock.patch.object(builtins, '_', lambda text:text, create=True)
        patch.start(); self.addCleanup(patch.stop)
        self.frontend_module = ufw.frontend
        self.error_type = ufw.common.UFWError
        self.frontend = ufw.frontend.UFWFrontend.__new__(ufw.frontend.UFWFrontend)
        class Backend:
            def __init__(self): self.rules = {False:[],True:[]}; self.positions = []
            def get_rules_count(self, v6): return len(self.rules[v6])
            def use_ipv6(self): return True
            def set_rule(self, rule):
                rules = self.rules[rule.v6]
                if rule.position < 0 or rule.position > len(rules): raise AssertionError('invalid backend position')
                self.positions.append((rule.v6,rule.position))
                if rule.position: rules.insert(rule.position-1,rule.dport)
                else: rules.append(rule.dport)
                return 'test-only'
        self.backend = Backend(); self.frontend.backend = self.backend

    def apply(self, arguments):
        parsed = self.frontend_module.parse_command(['ufw',*arguments])
        self.frontend.set_rule(parsed.data['rule'],parsed.data['iptype'])

    def test_insert_one_reproduces_empty_rule_rejection(self):
        with self.assertRaises(self.error_type):
            self.apply(['insert','1','allow','in','proto','tcp','to','any','port','2222'])
        self.assertEqual(self.backend.positions,[])

    def test_prepend_handles_both_families_empty(self):
        self.apply(['prepend','allow','in','proto','tcp','to','any','port','2222'])
        self.assertEqual(self.backend.positions,[(False,0),(True,0)])
        self.assertEqual(self.backend.rules,{False:['2222'],True:['2222']})

    def test_prepend_handles_one_family_empty(self):
        self.backend.rules[False] = ['existing']
        self.apply(['prepend','allow','in','proto','tcp','to','any','port','2222'])
        self.assertEqual(self.backend.positions,[(False,1),(True,0)])


class UFWRemovalTests(unittest.TestCase):
    def setUp(self):
        self.active = True; self.package = 'install ok installed'; self.missing = False
        self.dpkg_fail = False; self.disable_fail = False; self.stays_active = False
        self.calls = []
        patch = mock.patch.object(core.shutil,'which',side_effect=lambda name: None if self.missing else '/mock/'+name)
        patch.start(); self.addCleanup(patch.stop)
        patch = mock.patch.object(core,'system_command',side_effect=self.command)
        patch.start(); self.addCleanup(patch.stop)

    def command(self,args,check=True):
        self.calls.append(args); output = ''; code = 0
        if args == ['ufw','status']: output = 'Status: active\n' if self.active else 'Status: inactive\n'
        elif args == ['ufw','--force','disable']:
            if self.disable_fail: code = 1
            elif not self.stays_active: self.active = False
        elif args == ['dpkg-query','-W','-f=${Status}','ufw']:
            output = self.package if self.package else ''; code = 0 if self.package else 1
        elif args in (['dpkg','--no-act','--remove','ufw'], ['dpkg','--no-act','--purge','ufw']):
            code = 1 if self.dpkg_fail else 0
        else: raise AssertionError(args)
        if check and code: raise subprocess.CalledProcessError(code,args)
        return subprocess.CompletedProcess(args,code,stdout=output,stderr='')

    def test_disable_verified_and_package_retained(self):
        self.assertEqual(core.ufw_disable(),'disabled')
        self.assertFalse(self.active)
        self.assertEqual(self.package,'install ok installed')
        self.assertFalse(any(a[0].startswith('dpkg') for a in self.calls))

    def test_disable_failure_or_active_after_disable_is_not_success(self):
        for fail, stays in [(True,False),(False,True)]:
            self.disable_fail = fail; self.stays_active = stays
            with self.subTest(fail=fail,stays=stays), self.assertRaises(ValueError): core.ufw_disable()
            self.assertTrue(self.active)

    def test_disable_absent_is_noop(self):
        self.missing = True
        self.assertEqual(core.ufw_disable(),'absent')
        self.assertFalse(self.calls)

    def test_plan_uses_dpkg_no_act_before_action_and_changes_nothing(self):
        self.assertEqual(core.ufw_remove_plan(),'ready')
        self.assertIn(['dpkg','--no-act','--remove','ufw'],self.calls)
        self.assertTrue(self.active)
        self.assertFalse(any(a[0] == 'ufw' for a in self.calls))

    def test_dependency_failure_refuses_before_disabling(self):
        self.dpkg_fail = True
        for purge in [False, True]:
            with self.subTest(purge=purge), self.assertRaisesRegex(ValueError,'未改变'):
                core.ufw_remove_plan(purge)
        self.assertTrue(self.active)
        self.assertFalse(any(a[0] == 'ufw' for a in self.calls))

    def test_package_absent_or_config_only_is_noop(self):
        for package in ['', 'deinstall ok config-files', 'unknown ok not-installed']:
            self.package = package; self.calls.clear()
            with self.subTest(package=package): self.assertEqual(core.ufw_remove_plan(),'absent')
            self.assertEqual(len(self.calls),1)

    def test_held_partial_or_missing_files_are_refused(self):
        for package in ['hold ok installed','hold ok config-files','install ok unpacked','install reinstreq half-installed']:
            self.package = package
            for purge in [False, True]:
                with self.subTest(package=package,purge=purge), self.assertRaises(ValueError):
                    core.ufw_remove_plan(purge)
        self.package = 'install ok installed'; self.missing = True
        for purge in [False, True]:
            with self.subTest(purge=purge), self.assertRaisesRegex(ValueError,'文件缺失'):
                core.ufw_remove_plan(purge)
        self.assertTrue(self.active)

    def test_purge_preflight_targets_only_ufw_without_disabling(self):
        self.assertEqual(core.ufw_remove_plan(purge=True),'ready')
        self.assertEqual(self.calls,[['dpkg-query','-W','-f=${Status}','ufw'],
                                    ['dpkg','--no-act','--purge','ufw']])
        self.assertTrue(self.active)

    def test_purge_config_only_works_without_ufw_binary(self):
        self.package = 'deinstall ok config-files'; self.missing = True
        self.assertEqual(core.ufw_package_state(),'config-files')
        self.assertEqual(core.ufw_remove_plan(purge=True),'config-files')
        self.assertIn(['dpkg','--no-act','--purge','ufw'],self.calls)
        self.assertFalse(any(a[0] == 'ufw' for a in self.calls))

    def test_purge_absent_is_noop_and_query_error_is_not_absence(self):
        self.package = ''
        self.assertEqual(core.ufw_remove_plan(purge=True),'absent')
        self.assertEqual(len(self.calls),1)
        with mock.patch.object(core,'system_command',return_value=subprocess.CompletedProcess([],2,stdout='',stderr='')):
            with self.assertRaisesRegex(ValueError,'无法读取'): core.ufw_remove_plan(purge=True)


class UFWRemovalMenuTests(TemporaryFixture):
    def shell(self,inputs,language='zh',remove_fail=False,disable_fail=False,plan='ready',verify='absent',plan_fail=False):
        log = self.base/'remove.log'
        script = '''source "$1"
helper(){
 printf '%s\\n' "$*" >> "$REMOVE_LOG"
 case $1 in
  ufw-state) printf 'active';;
  ufw-remove-plan) [[ $PLAN_FAIL == no ]] || return 1; printf '%s' "$REMOVE_PLAN";;
  ufw-disable) [[ $DISABLE_FAIL == no ]] || return 1; printf 'disabled';;
  ufw-package-state) printf '%s' "$REMOVE_VERIFY";;
  *) return 1;;
 esac
}
dpkg(){ printf '%s\\n' "dpkg $*" >> "$REMOVE_LOG"; [[ $REMOVE_FAIL == no ]]; }
LANGUAGE="$2"
if network_menu; then exit 0; else exit 1; fi
'''
        result = subprocess.run(['bash','-c',script,'test',str(PROJECT/'xray-manager.sh'),language],
            input=inputs,text=True,capture_output=True,env={**os.environ,'REMOVE_LOG':str(log),
            'REMOVE_PLAN':plan,'REMOVE_VERIFY':verify,'REMOVE_FAIL':'yes' if remove_fail else 'no',
            'DISABLE_FAIL':'yes' if disable_fail else 'no','PLAN_FAIL':'yes' if plan_fail else 'no'})
        calls = log.read_text().splitlines() if log.exists() else []
        if log.exists(): log.unlink()
        return result,calls

    def test_remove_after_verified_disable_in_both_languages(self):
        for language in ['zh','en']:
            result,calls = self.shell('5\n2\nYES\n',language=language,verify='config-files')
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(calls,['ufw-remove-plan','ufw-state','ufw-disable','dpkg --remove ufw','ufw-package-state'])

    def test_only_disable_does_not_remove_package(self):
        result,calls = self.shell('5\n1\nYES\n')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(calls,['ufw-state','ufw-disable'])

    def test_cancel_does_not_disable_or_remove(self):
        for option in ['1','2','3']:
            result,calls = self.shell('5\n'+option+'\nno\n')
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertNotIn('ufw-disable',calls)
            self.assertFalse(any(c.startswith('dpkg ') for c in calls))

    def test_disable_failure_prevents_removal(self):
        for option in ['2','3']:
            result,calls = self.shell('5\n'+option+'\nYES\n',disable_fail=True)
            self.assertNotEqual(result.returncode,0)
            self.assertFalse(any(c.startswith('dpkg ') for c in calls))

    def test_removal_failure_does_not_claim_success_or_reenable(self):
        result,calls = self.shell('5\n2\nYES\n',language='en',remove_fail=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('package removal did not complete',result.stderr)
        self.assertNotIn('ufw-package-state',calls)
        self.assertNotIn('package removed',result.stdout)
        self.assertEqual(calls.count('ufw-disable'),1)

    def test_unverified_removal_is_not_success(self):
        result,calls = self.shell('5\n2\nYES\n',verify='installed')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('ufw-package-state',calls)

    def test_absent_package_does_not_disable(self):
        result,calls = self.shell('5\n2\n',plan='absent')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(calls,['ufw-remove-plan'])

    def test_purge_after_verified_disable_in_both_languages(self):
        for language in ['zh','en']:
            result,calls = self.shell('5\n3\nYES\n',language=language)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(calls,['ufw-remove-plan --purge','ufw-state','ufw-disable',
                                    'dpkg --purge ufw','ufw-package-state'])
            self.assertIn('不可恢复' if language == 'zh' else 'cannot be undone',result.stdout)

    def test_purge_remaining_configuration_skips_missing_binary_and_disable(self):
        for language in ['zh','en']:
            result,calls = self.shell('5\n3\nYES\n',language=language,plan='config-files')
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(calls,['ufw-remove-plan --purge','dpkg --purge ufw','ufw-package-state'])

    def test_purge_preflight_failure_or_unknown_plan_makes_no_changes(self):
        for settings in [{'plan_fail':True}, {'plan':'unknown'}]:
            result,calls = self.shell('5\n3\nYES\n',**settings)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(calls,['ufw-remove-plan --purge'])

    def test_purge_failure_reports_partial_state_without_success_or_reenable(self):
        for plan in ['ready','config-files']:
            result,calls = self.shell('5\n3\nYES\n',language='en',plan=plan,remove_fail=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('purge did not complete',result.stderr)
            self.assertIn('some files may already be removed',result.stderr)
            self.assertNotIn('ufw-package-state',calls)
            self.assertNotIn('configuration purged',result.stdout)
            self.assertFalse(any('enable' in c for c in calls))

    def test_purge_retained_configuration_is_not_success(self):
        result,calls = self.shell('5\n3\nYES\n',verify='config-files',language='en')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('could not be verified',result.stderr)

    def test_purge_absent_is_noop(self):
        result,calls = self.shell('5\n3\n',plan='absent')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(calls,['ufw-remove-plan --purge'])


@unittest.skipUnless(shutil.which('dpkg') and shutil.which('ufw'), 'Requires distro dpkg and ufw')
class DpkgRemovalPlanIntegrationTests(unittest.TestCase):
    def test_real_dpkg_no_act_does_not_remove_installed_ufw(self):
        before = core.ufw_package_state()
        self.assertEqual(before,'installed')
        config = Path('/etc/ufw/ufw.conf').read_bytes()
        for purge in [False,True]:
            with self.subTest(purge=purge):
                result = subprocess.run([os.sys.executable,str(PROJECT/'src/core.py'),'ufw-remove-plan',
                    *(['--purge'] if purge else [])],capture_output=True,text=True)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(result.stdout.strip(),'ready')
                self.assertEqual(core.ufw_package_state(),before)
                self.assertEqual(Path('/etc/ufw/ufw.conf').read_bytes(),config)
