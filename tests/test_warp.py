# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
import argparse
import copy
import importlib.util
import json
import os
import socket
import socketserver
import subprocess
import threading
import time
import unittest
from unittest import mock
import test_services as services
from test_manager import TemporaryFixture, PROJECT, ENGINE, core, example_node, free_port

spec = importlib.util.spec_from_file_location('warp_media', PROJECT / 'src/media.py')
media = importlib.util.module_from_spec(spec)
spec.loader.exec_module(media)


class WarpConfigTests(TemporaryFixture):
    def setUp(self):
        super().setUp()
        self.state = {'schema': 1, 'nodes': {'vision': example_node()}}
        self.state['nodes']['vision']['port'] = 443
        self.state['warp'] = {'port': 40000, 'domains': core.WARP_PROFILES['chatgpt'][:]}

    def test_domain_routing_preserves_credentials_private_block_and_direct_default(self):
        original = copy.deepcopy(self.state)
        config = core.server_config(self.state, self.root)
        self.assertEqual(original, self.state)
        self.assertEqual(config['outbounds'][0], {'protocol': 'freedom', 'tag': 'direct'})
        self.assertEqual(config['outbounds'][-1]['settings']['servers'], [{'address': '127.0.0.1', 'port': 40000}])
        rules = config['routing']['rules']
        self.assertIn('127.0.0.0/8', rules[0]['ip'])
        self.assertEqual(rules[0]['outboundTag'], 'block')
        self.assertEqual((rules[1]['network'], rules[1]['outboundTag']), ('udp', 'block'))
        self.assertEqual((rules[2]['network'], rules[2]['outboundTag']), ('tcp', 'warp'))
        self.assertIn('domain:chatgpt.com', rules[2]['domain'])
        self.assertTrue(config['inbounds'][0]['sniffing']['routeOnly'])
        del self.state['warp']
        direct = core.server_config(self.state, self.root)
        self.assertNotIn('sniffing', direct['inbounds'][0])
        self.assertEqual(len(direct['routing']['rules']), 1)

    def test_invalid_domains_port_collisions_and_unknown_fields_are_refused(self):
        for warp in [{'port': 443, 'domains': ['netflix.com']}, {'port': 70000, 'domains': ['netflix.com']},
                     {'port': 40000, 'domains': []}, {'port': 40000, 'domains': ['*.netflix.com']},
                     {'port': 40000, 'domains': ['domain:netflix.com']}, {'port': 40000, 'domains': ['com']},
                     {'port': 40000, 'domains': ['netflix.com', 'netflix.com']},
                     {'port': 40000, 'domains': ['netflix.com'], 'server': '0.0.0.0'}]:
            with self.subTest(warp=warp), self.assertRaises(ValueError):
                core.validate_state({**self.state, 'warp': warp})
        self.state['nodes']['vision']['port'] = 40000
        with self.assertRaisesRegex(ValueError, 'conflicts'):
            core.validate_state(self.state)

    def test_only_loopback_verified_warp_egress_is_accepted(self):
        listener = 'LISTEN 0 128 127.0.0.1:40000 0.0.0.0:*\n'
        trace = 'warp=on\nip=1.1.1.1\nloc=US\n'
        def command(args):
            return argparse.Namespace(stdout=listener if args[0] == 'ss' else trace)
        with mock.patch.object(core, 'system_command', side_effect=command) as run:
            self.assertEqual(core.warp_verify(40000), ('1.1.1.1', 'US'))
            curl = run.call_args.args[0]
            self.assertIn('socks5h://127.0.0.1:40000', curl)
            self.assertEqual(curl[curl.index('--noproxy') + 1], '')
            self.assertNotIn('-k', curl)
            self.assertIn('--proto-redir', curl)
            for bad in ['warp=off\nip=1.1.1.1\nloc=US', 'warp=on', 'warp=on\nip=127.0.0.1\nloc=US', 'warp=on\nip=1.1.1.1\nloc=\u001b[31m']:
                trace = bad
                with self.assertRaises(ValueError): core.warp_verify(40000)
            for bad in ['', 'LISTEN 0 128 0.0.0.0:40000 0.0.0.0:*',
                        'LISTEN 0 128 [::]:40000 [::]:*', listener + 'LISTEN 0 128 10.0.0.1:40000 0.0.0.0:*']:
                listener = bad
                with self.assertRaises(ValueError): core.warp_verify(40000)

    def test_chatgpt_200_is_unknown_explicit_region_error_is_restricted(self):
        def response(code, body):
            return {'code': code, 'body': body, 'url': 'https://chatgpt.com/', 'error': False}
        self.assertEqual(media.classify('ChatGPT', [response(200, '<html>Welcome</html>')])['status'], 'unknown')
        self.assertEqual(media.classify('ChatGPT', [response(403, '{"code":"unsupported_country_region_territory"}')])['status'], 'restricted')
        self.assertEqual(media.classify('ChatGPT', [response(403, 'verify you are human')])['status'], 'verification')
        self.assertEqual(media.classify('Netflix', [response(403, 'unsupported_country')])['status'], 'verification')
        self.assertEqual(media.classify('ChatGPT', [response(200, '<script>const messages={code:"unsupported_country"};</script>Welcome')])['status'], 'unknown')

    def test_gemini_domains_and_anonymous_responses(self):
        self.assertEqual(core.WARP_PROFILES['gemini'], ['gemini.google.com', 'aistudio.google.com', 'generativelanguage.googleapis.com'])
        self.assertNotIn('google.com', core.WARP_PROFILES['gemini'])
        self.assertIn('Gemini', media.PROBES)
        for code, body, expected in [(200, 'Welcome', 'unknown'), (403, 'Verify you are human', 'verification'),
                                     (400, '{"error":{"code":400,"message":"User location is not supported for the API use."}}', 'restricted'),
                                     (200, '<script>const message="not available in your country";</script>Welcome', 'unknown')]:
            response = {'code': code, 'body': body, 'url': 'https://gemini.google.com/', 'error': False}
            self.assertEqual(media.classify('Gemini', [response])['status'], expected)


@unittest.skipUnless(ENGINE, 'Set XRAY_BIN to the official Xray binary')
class WarpTransactionTests(services.ServiceFixture):
    def test_apply_disable_backup_restore_preserve_uuid_keys_and_stopped_service(self):
        old = self.installed()
        stage = core.warp_prepare(self.root, core.Path(ENGINE), 40000, core.WARP_PROFILES['chatgpt'])
        result = self.shell('apply_stage "$2"', stage)
        self.assertEqual(result.returncode, 0, result.stderr)
        new = core.load_state(self.root)
        self.assertEqual(old['nodes'], new['nodes'])
        self.assertFalse(self.state()['active'])
        backup = self.base / 'warp-backup.tar.gz'
        core.backup(self.root, backup)
        stage = core.warp_prepare(self.root, core.Path(ENGINE), 40000, [], disable=True)
        self.assertEqual(self.shell('apply_stage "$2"', stage).returncode, 0)
        self.assertEqual(core.load_state(self.root), old)
        stage = core.restore_stage(self.root, core.Path(ENGINE), backup)
        self.assertEqual(self.shell('apply_stage "$2"', stage).returncode, 0)
        self.assertEqual(core.load_state(self.root), new)

    def test_restart_failure_rolls_back_warp_configuration_and_activity(self):
        old = self.installed()
        self.set_controller(active=True, enabled=True, fail_restart=True)
        stage = core.warp_prepare(self.root, core.Path(ENGINE), 40000, core.WARP_PROFILES['netflix'])
        result = self.shell('apply_stage "$2"', stage)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(core.load_state(self.root), old)
        self.assertTrue(self.state()['active'])
        self.assertTrue(self.state()['enabled'])


@unittest.skipUnless(ENGINE, 'Set XRAY_BIN to the official Xray binary')
class WarpEngineTests(TemporaryFixture):
    def test_gemini_domain_uses_local_socks_outbound_with_remote_dns(self):
        destinations = []
        def read(stream, count):
            data = b''
            while len(data) < count:
                chunk = stream.recv(count - len(data))
                if not chunk: raise ConnectionError('SOCKS stream ended early')
                data += chunk
            return data
        class Gateway(socketserver.BaseRequestHandler):
            def handle(self):
                self.request.settimeout(5)
                greeting = read(self.request, 2)
                read(self.request, greeting[1])
                self.request.sendall(b'\x05\x00')
                request = read(self.request, 4)
                if request[3] != 3: raise AssertionError('Expected proxy-side domain resolution')
                host = read(self.request, read(self.request, 1)[0]).decode()
                number = int.from_bytes(read(self.request, 2), 'big')
                destinations.append((host, number))
                self.request.sendall(b'\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00')
                read(self.request, 1)
                self.request.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 17\r\nConnection: close\r\n\r\nSKYBYTE WARP TEST')
        gateway = socketserver.TCPServer(('127.0.0.1', 0), Gateway)
        thread = threading.Thread(target=gateway.serve_forever, kwargs={'poll_interval': .05}, daemon=True)
        thread.start()
        inbound_port = free_port()
        state = {'schema': 1, 'nodes': {}, 'warp': {'port': gateway.server_address[1], 'domains': core.WARP_PROFILES['gemini']}}
        config = core.server_config(state, self.root)
        # Isolated SOCKS lab: keep domain routing but avoid external DNS entirely.
        config['routing']['domainStrategy'] = 'AsIs'
        config['inbounds'] = [{'listen': '127.0.0.1', 'port': inbound_port, 'protocol': 'socks', 'settings': {'auth': 'noauth'}}]
        filename = self.base / 'warp-engine.json'
        core.write_private(filename, core.json_text(config))
        core.engine_check(core.Path(ENGINE), filename)
        process = subprocess.Popen([ENGINE, 'run', '-config', str(filename)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 5
            while True:
                try:
                    connection = socket.create_connection(('127.0.0.1', inbound_port), timeout=.2)
                    break
                except OSError:
                    if time.monotonic() > deadline: raise
                    time.sleep(.05)
            with connection:
                connection.settimeout(5)
                connection.sendall(b'\x05\x01\x00')
                self.assertEqual(read(connection, 2), b'\x05\x00')
                host = b'gemini.google.com'
                connection.sendall(b'\x05\x01\x00\x03' + bytes([len(host)]) + host + b'\x00\x50')
                header = read(connection, 4)
                self.assertEqual(header[1], 0)
                read(connection, 6 if header[3] == 1 else 18)
                connection.sendall(b'GET / HTTP/1.1\r\nHost: gemini.google.com\r\n\r\n')
                response = b''
                while b'SKYBYTE WARP TEST' not in response:
                    chunk = connection.recv(4096)
                    if not chunk: break
                    response += chunk
                self.assertIn(b'SKYBYTE WARP TEST', response)
            self.assertEqual(destinations, [('gemini.google.com', 80)])
        finally:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
            gateway.shutdown(); gateway.server_close(); thread.join(timeout=2)


class WarpMenuTests(TemporaryFixture):
    def shell(self, inputs, failed=False, language='zh'):
        log = self.base / 'calls'
        script = '''source "$1"
LANGUAGE=$2
helper(){
 printf '%s\\n' "$*" >> "$WARP_LOG"
 case $1 in
  warp-profile) printf 'chatgpt.com openai.com';;
  warp-check) [[ $WARP_FAILED != yes ]];;
  warp-prepare) printf '/mock-stage';;
 esac
}
apply_stage(){ printf 'apply %s\\n' "$*" >> "$WARP_LOG"; }
warp_menu
'''
        result = subprocess.run(['bash', '-c', script, 'test', str(PROJECT / 'xray-manager.sh'), language],
                                input=inputs, text=True, capture_output=True, timeout=5,
                                env={**os.environ, 'WARP_LOG': str(log), 'WARP_FAILED': 'yes' if failed else 'no', 'NO_COLOR': '1'})
        calls = log.read_text().splitlines() if log.exists() else []
        log.unlink(missing_ok=True)
        return result, calls

    def test_profile_y_confirmation_uses_existing_transaction_in_both_languages(self):
        for language in ['zh', 'en']:
            result, calls = self.shell('2\n40001\n4\ny\n', language=language)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('warp-profile --profile chatgpt', calls)
            self.assertIn('warp-check --proxy-port 40001', calls)
            self.assertIn('warp-prepare --proxy-port 40001 --domains chatgpt.com openai.com', calls)
            self.assertEqual(calls[-1], 'apply /mock-stage')

    def test_cancellation_and_failed_egress_never_apply_routing(self):
        for inputs, failed in [('2\n\n4\n\n', False), ('2\n\n0\n', False), ('2\n\n4\ny\n', True), ('3\nn\n', False)]:
            with self.subTest(inputs=inputs):
                result, calls = self.shell(inputs, failed)
                self.assertFalse(any(call.startswith(('warp-prepare', 'apply')) for call in calls))
        result, calls = self.shell('3\nY\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('warp-prepare --disable', calls)
        self.assertEqual(calls[-1], 'apply /mock-stage')

    def test_gemini_profile_is_available_in_both_languages(self):
        for language in ['zh', 'en']:
            result, calls = self.shell('2\n\n5\nY\n', language=language)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('warp-profile --profile gemini', calls)

    def test_official_install_cancel_and_residual_data_do_not_install_or_start(self):
        residual = self.base / 'old-warp-data'
        script = '''source "$1"
helper(){ :; }
command(){ if [[ $1 == -v && $2 == warp-cli ]]; then return 1; fi; builtin command "$@"; }
awk(){ if [[ $* == *VERSION_CODENAME* ]]; then echo bookworm; else echo debian; fi; }
apt_refresh(){ echo UNEXPECTED_INSTALL; return 1; }
systemctl(){ echo UNEXPECTED_SERVICE; return 1; }
warp_install_client
'''
        env = {**os.environ, 'SKYBYTE_WARP_DATA_DIR': str(residual), 'NO_COLOR': '1'}
        for exists in [False, True]:
            if exists: residual.mkdir()
            result = subprocess.run(['bash', '-c', script, 'test', str(PROJECT / 'xray-manager.sh')],
                                    input='n\n', text=True, capture_output=True, timeout=5, env=env)
            self.assertNotIn('UNEXPECTED', result.stdout + result.stderr)
            self.assertIn('已有 WARP 数据' if exists else '[y/N]', result.stdout + result.stderr)
