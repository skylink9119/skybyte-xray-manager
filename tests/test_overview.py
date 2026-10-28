# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
"""Startup inventory is local, read-only and tolerant of unavailable probes."""
import argparse
import json
import os
import subprocess
import sys
import time
from unittest import mock
from test_manager import TemporaryFixture, PROJECT, core, example_node


class OverviewTests(TemporaryFixture):
    def setUp(self):
        super().setUp()
        self.lib = self.base / 'lib'
        self.lib.mkdir()
        self.binary = self.lib / 'xray'
        self.readings = {
            '/etc/os-release': 'PRETTY_NAME="Debian GNU/Linux 13 (trixie)"\n',
            '/proc/cpuinfo': 'processor : 0\nmodel name : Example CPU\n',
            '/proc/meminfo': 'MemTotal: 2097152 kB\nMemAvailable: 1572864 kB\nSwapTotal: 1048576 kB\nSwapFree: 524288 kB\n',
            '/proc/uptime': '90060.00 0.00\n',
            '/proc/loadavg': '0.10 0.20 0.30 1/100 123\n',
            '/proc/sys/net/ipv4/tcp_congestion_control': 'cubic\n',
            '/proc/sys/net/core/default_qdisc': 'fq_codel\n',
        }
        self.tools = set()
        self.service = ('Id=skybyte-xray.service\nLoadState=not-found\nActiveState=inactive\nUnitFileState=\n')
        self.extra_services = ''
        self.ufw = 'Status: inactive'
        self.calls = []

    def installed(self):
        core.ensure_owned(self.root, True)
        nodes = {kind: example_node(kind) for kind in core.KINDS}
        for number, node in enumerate(nodes.values()):
            node['port'] = 443 + number
        core.write_private(self.root / 'state.json', core.json_text({'schema': 1, 'nodes': nodes}))
        self.binary.write_text('not executed in the tests')
        self.binary.chmod(0o700)
        (self.lib / '.owner').write_text(core.OWNER)
        self.service = 'Id=skybyte-xray.service\nLoadState=loaded\nActiveState=active\nUnitFileState=enabled\n'
        return nodes

    def report(self, language='zh'):
        def command(arguments):
            self.calls.append(arguments)
            if arguments[0] == 'systemctl':
                return self.service + self.extra_services
            if arguments == [str(self.binary), 'version']:
                return 'Xray 26.10.10 (Xray, Penetrates Everything.)\n'
            if arguments == ['ufw', 'status']:
                return self.ufw
            raise AssertionError(f'Unexpected probe: {arguments}')
        with mock.patch.object(core, 'overview_read', side_effect=lambda p: self.readings.get(str(p), '')), \
             mock.patch.object(core, 'overview_command', side_effect=command), \
             mock.patch.object(core.shutil, 'which', side_effect=lambda tool: '/usr/bin/' + tool if tool in self.tools else None), \
             mock.patch.object(core.shutil, 'disk_usage', return_value=argparse.Namespace(used=4 * 1024**3, total=20 * 1024**3)), \
             mock.patch.object(core.platform, 'uname', return_value=argparse.Namespace(machine='x86_64', release='6.12-test')), \
             mock.patch.object(core.os, 'cpu_count', return_value=2), \
             mock.patch.object(core.urllib.request, 'urlopen', side_effect=AssertionError('No network in startup')):
            return core.startup_overview(self.root, self.binary, language)

    def test_first_open_without_nodes_or_components_does_not_create_files(self):
        report = self.report()
        for expected in ['Debian GNU/Linux 13', 'amd64', 'Example CPU (2 vCPU)',
                         '0.50 GiB / 2.00 GiB', '0.50 GiB / 1.00 GiB',
                         '4.00 GiB / 20.00 GiB (20%)', '1 天 1 小时 1 分', '0.10 / 0.20 / 0.30',
                         'Xray: 未安装', '尚未安装节点', '未开启 BBR 加速', 'UFW: 未安装', '二维码工具: 未安装']:
            self.assertIn(expected, report)
        self.assertFalse(self.root.exists())
        self.assertFalse(self.binary.exists())
        self.assertEqual(len(self.calls), 1)

    def test_running_core_actual_version_ports_and_components_without_credentials(self):
        nodes = self.installed()
        before = {str(p): p.read_bytes() for p in self.base.rglob('*') if p.is_file()}
        self.tools.update(['ufw', 'firewall-cmd', 'fail2ban-client', 'qrencode'])
        self.ufw = 'Status: active\n'
        self.extra_services = ('\nId=firewalld.service\nLoadState=loaded\nActiveState=inactive\nUnitFileState=disabled\n'
                               '\nId=fail2ban.service\nLoadState=loaded\nActiveState=active\nUnitFileState=enabled\n')
        report = self.report()
        for expected in ['Xray: 运行中', '开机自启: 已启用', '实际核心版本: 26.10.10',
                         'Reality + Vision: TCP 443', 'XHTTP + Reality: TCP 444', 'XHTTP + TLS/CDN: TCP 445',
                         'UFW: 已启用', 'firewalld: 已安装，未运行', 'Fail2ban: 运行中', '二维码工具: 已安装']:
            self.assertIn(expected, report)
        for node in nodes.values():
            for key in ['uuid', 'private', 'public', 'short_id', 'path']:
                if key in node:
                    self.assertNotIn(node[key], report)
        self.assertNotIn('vless://', report)
        self.assertEqual(before, {str(p): p.read_bytes() for p in self.base.rglob('*') if p.is_file()})

    def test_failed_stopped_starting_and_unknown_services_are_distinct(self):
        self.installed()
        for active, expected in [('failed', '运行失败'), ('inactive', '已安装，未运行'), ('activating', '启动中'), ('deactivating', '停止中')]:
            with self.subTest(active=active):
                self.service = f'Id=skybyte-xray.service\nLoadState=loaded\nActiveState={active}\nUnitFileState=disabled\n'
                self.assertIn(f'Xray: {expected} | 开机自启: 未启用', self.report())
        self.service = ''
        self.tools.add('ufw')
        self.ufw = ''
        self.assertIn('Xray: 已安装，状态未知', self.report())
        self.assertIn('UFW: 已安装，状态未知', self.report())

    def test_bbr_uses_running_algorithm_not_saved_configuration(self):
        self.readings['/proc/sys/net/ipv4/tcp_congestion_control'] = 'bbr\n'
        self.readings['/proc/sys/net/core/default_qdisc'] = 'fq\n'
        self.assertIn('已开启 BBR 加速 (bbr / fq)', self.report())
        self.readings['/proc/sys/net/ipv4/tcp_congestion_control'] = ''
        self.assertIn('BBR: 未知', self.report())

    def test_corrupt_or_unowned_configuration_does_not_break_inventory(self):
        self.installed()
        state = self.root / 'state.json'
        for content in ['not json', '{"schema": 9, "nodes": {}}']:
            state.write_text(content)
            self.assertIn('配置读取失败', self.report())
            self.assertEqual(state.read_text(), content)
        (self.root / '.owner').write_text('another manager')
        self.assertIn('配置读取失败', self.report())

    def test_missing_resource_probes_and_terminal_controls_are_safe(self):
        self.readings = {'/etc/os-release': 'PRETTY_NAME="Test\u001b[31m OS"\n',
                         '/proc/cpuinfo': 'model name : Safe\x07 CPU\n', '/proc/uptime': 'bad'}
        report = self.report()
        self.assertIn('Test OS', report)
        self.assertNotIn('\x1b', report)
        self.assertNotIn('\x07', report)
        self.assertIn('内存: 未知', report)
        self.assertIn('运行时间: 未知', report)

    def test_english_and_disabled_components(self):
        self.installed()
        self.tools.add('ufw')
        report = self.report('en')
        for expected in ['Server configuration', 'Runtime status', 'Plugins/components (system detection)',
                         'Xray: Running', 'Installed core version: 26.10.10', 'UFW: Installed, disabled',
                         'BBR acceleration not enabled', 'QR utility: Not installed']:
            self.assertIn(expected, report)

    def test_unowned_or_symlinked_binary_is_not_executed(self):
        self.installed()
        (self.lib / '.owner').unlink()
        self.report()
        self.assertNotIn([str(self.binary), 'version'], self.calls)
        self.calls.clear()
        (self.lib / '.owner').write_text(core.OWNER)
        self.binary.unlink()
        self.binary.symlink_to(PROJECT / 'src/core.py')
        self.report()
        self.assertNotIn([str(self.binary), 'version'], self.calls)

    def test_timeout_and_missing_command_return_unknown_without_raising(self):
        for error in [FileNotFoundError(), subprocess.TimeoutExpired('systemctl', 2)]:
            with mock.patch.object(core.subprocess, 'run', side_effect=error):
                self.assertEqual(core.overview_command(['systemctl', 'show']), '')
        with mock.patch.object(core.subprocess, 'run', return_value=argparse.Namespace(returncode=1, stdout='error', stderr='')) as run:
            self.assertEqual(core.overview_command(['ufw', 'status']), '')
            self.assertEqual(run.call_args.kwargs['timeout'], 2)

    def test_main_menu_refreshes_overview_and_keeps_navigation_after_probe_failure(self):
        script = '''source "$1"
LANGUAGE=$2
calls=$3
helper(){ [[ $1 != overview ]] || { printf 'OVERVIEW %s\\n' "$*" >> "$calls"; return 1; }; }
service_menu(){ printf 'SERVICE_MENU\\n'; }
main_menu
'''
        for language in ['zh', 'en']:
            calls = self.base / ('calls-' + language)
            result = subprocess.run(['bash', '-c', script, 'test', str(PROJECT / 'xray-manager.sh'), language, str(calls)],
                                    input='4\n0\n', capture_output=True, text=True, timeout=5,
                                    env={**os.environ, 'NO_COLOR': '1'})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls.read_text().splitlines(), [f'OVERVIEW overview --language {language}'] * 2)
            self.assertIn('SERVICE_MENU', result.stdout)
            self.assertIn('Overview unavailable' if language == 'en' else '状态概览暂不可用', result.stdout)
            self.assertNotIn('\x1b', result.stdout)

    def test_slow_local_probes_overlap_and_time_out(self):
        # Three stalled probes used to accumulate six seconds of timeout waits.
        command = [sys.executable, '-c', 'import time; time.sleep(20)']
        started = time.monotonic()
        result = core.overview_commands(dict.fromkeys(('services', 'version', 'ufw'), command))
        self.assertEqual(result, dict.fromkeys(('services', 'version', 'ufw'), ''))
        self.assertLess(time.monotonic() - started, 4.5)

    def test_brief_menu_cache_refreshes_for_expiry_and_language(self):
        calls = self.base / 'calls'
        script = '''source "$1"
calls=$2
helper(){ printf 'probe\\n' >> "$calls"; printf 'OVERVIEW\\n'; }
show_startup_info
show_startup_info
LANGUAGE=en
show_startup_info
SECONDS=$((SECONDS+6))
show_startup_info
'''
        result = subprocess.run(['bash', '-c', script, 'test', str(PROJECT / 'xray-manager.sh'), str(calls)],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls.read_text().splitlines(), ['probe'] * 3)
        self.assertEqual(result.stdout.count('OVERVIEW'), 4)

    def test_read_only_views_and_invalid_choices_reuse_failed_snapshot(self):
        calls = self.base / 'calls'
        script = '''source "$1"
calls=$2
helper(){ printf 'probe\\n' >> "$calls"; return 1; }
guide(){ printf 'GUIDE\\n'; }
show_parameters(){ printf 'PARAMETERS\\n'; }
main_menu
'''
        result = subprocess.run(['bash', '-c', script, 'test', str(PROJECT / 'xray-manager.sh'), str(calls)],
                                input='i\ninvalid\np\nq\n', capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls.read_text().splitlines(), ['probe'])
        self.assertIn('GUIDE', result.stdout)
        self.assertIn('PARAMETERS', result.stdout)
