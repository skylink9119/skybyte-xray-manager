# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
import argparse
import base64
import copy
import errno
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import socket
import ssl
import subprocess
import tarfile
import tempfile
import threading
import time
import unittest
from unittest import mock
import urllib.parse
import urllib.error
import uuid
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('core', PROJECT / 'src/core.py')
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)
ENGINE = os.environ.get('XRAY_BIN', '')
WORK = PROJECT / 'work'
WORK.mkdir(exist_ok=True)


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def options(kind='vision', **changes):
    result = argparse.Namespace(kind=kind, port=str(free_port()), address='127.0.0.1',
        listen='127.0.0.1', name='SKYBYTE 测试', sni='localhost', target='localhost:443',
        path='/test/path', mode='auto', cert='', key='', cdn=False, ca_file=None)
    result.__dict__.update(changes)
    return result


def example_node(kind='vision'):
    private = base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip('=')
    public = base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip('=')
    node = {'name':'SKYBYTE 测试', 'uuid':str(uuid.uuid4()), 'port':free_port(),
            'address':'127.0.0.1', 'listen':'127.0.0.1', 'sni':'localhost'}
    if kind == 'xhttp-tls':
        node.update(cert=f"tls/{node['uuid']}.crt", key=f"tls/{node['uuid']}.key", cdn=False)
    else:
        node.update(private=private, public=public, short_id=os.urandom(8).hex(), target='localhost:443')
    if kind.startswith('xhttp'):
        node.update(path='/sample/path', mode='auto')
    return node


class ValidationTests(unittest.TestCase):
    def test_domains_and_ipv6(self):
        self.assertEqual(core.domain('Sub.Example.COM.'), 'sub.example.com')
        self.assertEqual(core.address('2001:db8::1'), '2001:db8::1')

    def test_reject_command_injection(self):
        for value in ['$(id)', 'example.com;id', 'hello\nexample.com', '/tmp/evil', 'https://example.com']:
            with self.subTest(value=value), self.assertRaises(ValueError): core.address(value)

    def test_reject_invalid_ports(self):
        for p in ['0', '65536', '-1', '443;id', True, '443.0']:
            with self.subTest(port=p), self.assertRaises(ValueError): core.port(p)

    def test_unicode_name_and_no_control_codes(self):
        self.assertEqual(core.name('香港 节点'), '香港 节点')
        for value in ['', 'x'*65, 'bad\x1b[31m', 'bad\nname']:
            with self.assertRaises(ValueError): core.name(value)

    def test_xhttp_paths(self):
        self.assertEqual(core.xhttp_path('/a/b_1-2'), '/a/b_1-2')
        for value in ['path', '/abc?token=1', '/abc#x', '/abc\n', '/abc;id']:
            with self.assertRaises(ValueError): core.xhttp_path(value)

    def test_three_modes_generate_different_configs(self):
        nodes = {kind:example_node(kind) for kind in core.KINDS}
        nodes['xhttp-tls']['port'] = max(n['port'] for n in nodes.values()) + 1
        while len({n['port'] for n in nodes.values()}) != 3:
            nodes['xhttp-reality']['port'] = free_port()
        config = core.server_config({'schema':1,'nodes':nodes}, Path('/example'))
        vision, reality, tls = config['inbounds']
        self.assertEqual(vision['streamSettings']['network'], 'raw')
        self.assertEqual(vision['settings']['clients'][0]['flow'], 'xtls-rprx-vision')
        self.assertNotIn('flow', reality['settings']['clients'][0])
        self.assertNotIn('flow', tls['settings']['clients'][0])
        self.assertEqual(reality['streamSettings']['security'], 'reality')
        self.assertEqual(tls['streamSettings']['security'], 'tls')

    def test_tls_validation_stays_enabled(self):
        node = example_node('xhttp-tls')
        client = core.client_config('xhttp-tls', node)
        self.assertFalse(client['outbounds'][0]['streamSettings']['tlsSettings']['allowInsecure'])
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(core.node_uri('xhttp-tls', node)).query)
        self.assertEqual(query['allowInsecure'], ['0'])

    def test_uri_encodes_name_path_and_ipv6(self):
        node = example_node('xhttp-reality')
        node.update(name='香港 A & B',address='2001:db8::1')
        uri = urllib.parse.urlsplit(core.node_uri('xhttp-reality', node))
        self.assertEqual(uri.hostname, '2001:db8::1')
        self.assertEqual(urllib.parse.unquote(uri.fragment), node['name'])
        self.assertEqual(urllib.parse.parse_qs(uri.query)['path'], ['/sample/path'])
        self.assertNotIn('flow', urllib.parse.parse_qs(uri.query))

    def test_no_private_key_in_client_exports(self):
        node = example_node()
        for output in [core.node_uri('vision',node), core.json_text(core.client_config('vision',node))]:
            self.assertNotIn(node['private'], output)
            self.assertNotIn('privateKey',output)

    def test_duplicate_ports_refused(self):
        a,b=example_node(),example_node('xhttp-reality')
        b['port']=a['port']
        with self.assertRaises(ValueError): core.validate_state({'schema':1,'nodes':{'vision':a,'xhttp-reality':b}})

    def test_unknown_state_and_paths_refused(self):
        node=example_node('xhttp-tls');node['key']='../../outside'
        with self.assertRaises(ValueError): core.validate_state({'schema':1,'nodes':{'xhttp-tls':node}})
        with self.assertRaises(ValueError): core.validate_state({'schema':2,'nodes':{}})
        with self.assertRaises(ValueError): core.validate_state({'schema':1,'nodes':{},'shell':'run'})

    def test_cdn_stream_one_refused(self):
        node=example_node('xhttp-tls');node.update(cdn=True,mode='stream-one')
        with self.assertRaises(ValueError): core.validate_state({'schema':1,'nodes':{'xhttp-tls':node}})

    def test_new_key_cli_does_not_pass_secrets(self):
        private=base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip('=')
        public=base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip('=')
        with mock.patch.object(core.subprocess,'run',return_value=argparse.Namespace(returncode=0,stdout=f'PrivateKey: {private}\nPassword: {public}\n')) as run:
            self.assertEqual(core.new_keys('/engine'),(private,public))
            self.assertEqual(run.call_args.args[0],['/engine','x25519'])

    def test_key_error_does_not_print_private_output(self):
        private='SECRET_NOT_FOR_LOGS'
        with mock.patch.object(core.subprocess,'run',return_value=argparse.Namespace(returncode=1,stdout=private)):
            with self.assertRaises(ValueError) as error: core.new_keys('/engine')
        self.assertNotIn(private,str(error.exception))

    def test_service_uses_separate_name_and_restricts_permissions(self):
        unit=core.unit_content(Path('/etc/skybyte-xray'),Path('/usr/local/lib/skybyte-xray/xray'))
        self.assertIn('UMask=0077',unit)
        self.assertIn('NoNewPrivileges=true',unit)
        self.assertIn('ProtectSystem=strict',unit)

    def test_single_letter_confirmation_is_case_insensitive(self):
        for value in ['y','Y','  y  ','\tY\t']:
            result=subprocess.run(['bash','-c','source "$1"; confirmed "$2"','test',str(PROJECT/'xray-manager.sh'),value])
            self.assertEqual(result.returncode,0)
        for value in ['', 'n', 'N', 'no', 'yes', 'YES', 'yy', 'y e s']:
            result=subprocess.run(['bash','-c','source "$1"; confirmed "$2" && printf EXECUTED','test',str(PROJECT/'xray-manager.sh'),value],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertNotIn('EXECUTED',result.stdout)

    def test_menu_newlines_and_no_color(self):
        result=subprocess.run(['bash','-c','source "$1"; menu "one\\ntwo" "one\\ntwo"','test',str(PROJECT/'xray-manager.sh')],capture_output=True,text=True,env={**os.environ,'NO_COLOR':'1'})
        self.assertEqual(result.stdout,'one\ntwo\n')
        self.assertNotIn('\x1b',result.stdout)


class TemporaryFixture(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=WORK)
        self.base=Path(self.temp.name)
        self.root=self.base/'managed'
        self.unit=self.base/'skybyte-xray.service'

    def tearDown(self): self.temp.cleanup()


class RealityHandshakeMenuTests(TemporaryFixture):
    def shell(self, inputs, language='zh', probe_fail=False):
        log = self.base/'handshake-menu.log'
        script = '''source "$1"
helper(){
 printf '%s\\n' "$*" >> "$HANDSHAKE_LOG"
 case $1 in
  preflight|reality-input|tls-input) return 0;;
  probe) [[ $HANDSHAKE_PROBE_FAIL == no ]];;
  prepare) printf '/mock-stage';;
  *) return 1;;
 esac
}
ensure_binary(){ printf 'ensure-binary\\n' >> "$HANDSHAKE_LOG"; }
apply_stage(){ printf 'apply %s\\n' "$*" >> "$HANDSHAKE_LOG"; }
show_nodes(){ :; }
install_check_engine(){ :; }
reality_engine(){
 local target= sni=
 while (($#));do case $1 in --target)target=$2;shift 2;;--sni)sni=$2;shift 2;;*)shift;;esac;done
 printf '%s\\n' "probe --target $target --sni $sni" >> "$HANDSHAKE_LOG"
 [[ $HANDSHAKE_PROBE_FAIL == no ]]
}
LANGUAGE=$2
install_node
'''
        result = subprocess.run(['bash', '-c', script, 'test', str(PROJECT/'xray-manager.sh'), language],
            input=inputs, capture_output=True, text=True, timeout=10,
            env={**os.environ, 'HANDSHAKE_LOG':str(log), 'NO_COLOR':'1',
                 'HANDSHAKE_PROBE_FAIL':'yes' if probe_fail else 'no'})
        calls = log.read_text().splitlines() if log.exists() else []
        log.unlink(missing_ok=True)
        return result, calls

    def inputs(self, selection, target='', kind='1'):
        return kind+'\n\n\n\n203.0.113.10\n'+selection+target+'\n'+('\n\n' if kind == '2' else '')+'Y\n'

    def test_enter_keeps_microsoft_default_in_both_languages(self):
        for language in ['zh','en']:
            result, calls = self.shell(self.inputs('\n'), language)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('probe --target www.microsoft.com:443 --sni www.microsoft.com', calls)
            prepared = next(call for call in calls if call.startswith('prepare '))
            self.assertIn('--sni www.microsoft.com', prepared)
            self.assertIn('--target www.microsoft.com:443', prepared)
            self.assertTrue(calls[0].startswith('preflight '))
            self.assertLess(calls.index('probe --target www.microsoft.com:443 --sni www.microsoft.com'), calls.index('ensure-binary'))

    def test_preset_sni_and_target_reach_both_reality_transports(self):
        for language in ['zh','en']:
            for kind, selection, host in [('1','2\n','www.apple.com'),('2','4\n','www.cloudflare.com')]:
                result, calls = self.shell(self.inputs(selection, kind=kind), language)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('probe --target '+host+':443 --sni '+host, calls)
                prepared = next(call for call in calls if call.startswith('prepare '))
                self.assertIn('监听 TCP 端口 [443]' if language == 'zh' else 'TCP listen port [443]', result.stderr)
                self.assertIn('preflight --port 443 ', calls[0])
                self.assertIn('--kind '+('vision' if kind == '1' else 'xhttp-reality'), calls[0])
                self.assertIn('--port 443 ', prepared)
                self.assertIn('--sni '+host, prepared)
                self.assertIn('--target '+host+':443', prepared)
                self.assertIn('apply /mock-stage yes', calls)

    def test_custom_domain_and_target_override_are_preserved(self):
        for language in ['zh','en']:
            result, calls = self.shell(self.inputs('6\ncustom.example.com\n', 'origin.example.com:8443'), language)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('probe --target origin.example.com:8443 --sni custom.example.com', calls)
            prepared = next(call for call in calls if call.startswith('prepare '))
            self.assertIn('--sni custom.example.com', prepared)
            self.assertIn('--target origin.example.com:8443', prepared)

    def test_direct_domain_input_still_works(self):
        result, calls = self.shell(self.inputs('direct.example.com\n'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('probe --target direct.example.com:443 --sni direct.example.com', calls)

    def test_invalid_number_and_blank_custom_domain_reprompt(self):
        result, calls = self.shell(self.inputs('99\n6\n\ncustom.example.com\n'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('选项无效', result.stderr)
        self.assertIn('请填写握手域名', result.stderr)
        self.assertIn('probe --target custom.example.com:443 --sni custom.example.com', calls)
        self.assertEqual(sum(call.startswith('probe ') for call in calls), 1)

    def test_back_and_failed_probe_stop_before_core_or_configuration_changes(self):
        result, calls = self.shell(self.inputs('0\n'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(call.startswith('preflight ') for call in calls))
        for kind in ['1','2']:
            result, calls = self.shell(self.inputs('2\n', kind=kind), probe_fail=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('probe --target www.apple.com:443 --sni www.apple.com', calls)
            self.assertFalse(any(call.startswith(('ensure-binary','prepare ','apply ')) for call in calls))

    def test_install_confirmation_cancellation_and_y_have_clear_results(self):
        for language in ['zh','en']:
            for answer in ['', 'n', 'N', 'no', 'yes', 'YES', 'y', 'Y']:
                inputs = self.inputs('2\n').removesuffix('Y\n')+answer+'\n'
                result, calls = self.shell(inputs, language)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('[y/N]', result.stderr)
                self.assertNotIn('[YES]', result.stderr)
                if answer in ['y','Y']:
                    self.assertIn('ensure-binary', calls)
                    self.assertIn('apply /mock-stage yes', calls)
                else:
                    self.assertIn('已取消节点安装' if language == 'zh' else 'Node installation cancelled', result.stdout)
                    self.assertFalse(any(call.startswith(('ensure-binary','prepare ','apply ')) for call in calls))

    def test_tls_certificate_flow_does_not_show_reality_presets(self):
        result, calls = self.shell('3\n\n\n\n203.0.113.10\ntls.example.com\n/cert.pem\n/key.pem\n\n\n\nY\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('Microsoft', result.stdout+result.stderr)
        self.assertFalse(any(call.startswith('probe ') for call in calls))
        prepared = next(call for call in calls if call.startswith('prepare '))
        self.assertIn('--kind xhttp-tls', prepared)
        self.assertIn('--kind xhttp-tls', calls[0])
        self.assertIn('--cert /cert.pem --key /key.pem', prepared)

    def test_cdn_choice_uses_y_and_defaults_to_direct(self):
        for language in ['zh','en']:
            for answer in ['y','Y','n','N','']:
                inputs='3\n\n\n\n203.0.113.10\ntls.example.com\n/cert.pem\n/key.pem\n'+answer+'\n\n\ny\n'
                result,calls=self.shell(inputs,language)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertIn('[y/N]',result.stderr)
                prepared=next(call for call in calls if call.startswith('prepare '))
                self.assertEqual('--cdn' in prepared,answer in ['y','Y'])
                self.assertIn('apply /mock-stage yes',calls)


class InstallationInputTests(TemporaryFixture):
    def cli(self, *arguments):
        return subprocess.run(['bash', '-c', 'source "$1"; helper preflight "${@:2}"',
            'test', str(PROJECT/'xray-manager.sh'), '--root', str(self.root), *arguments],
            capture_output=True, text=True, timeout=10)

    def test_missing_client_address_rejected_without_creating_config(self):
        result = self.cli('--address', '   ')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('客户端连接地址必填', result.stderr)
        self.assertFalse(self.root.exists())

    def test_invalid_port_rejected_without_creating_config(self):
        result = self.cli('--address', 'example.com', '--port', '65536')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('1–65535', result.stderr)
        self.assertFalse(self.root.exists())

    def test_available_port_preflight_does_not_create_config(self):
        result = self.cli('--address', 'example.com', '--listen', '127.0.0.1', '--port', str(free_port()))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.root.exists())

    def test_empty_destination_preflight_does_not_create_owner_marker(self):
        self.root.mkdir()
        result = self.cli('--kind', 'vision', '--address', 'example.com', '--listen', '127.0.0.1', '--port', str(free_port()))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_existing_mode_is_rejected_on_another_free_port(self):
        core.ensure_owned(self.root, True)
        state = {'schema':1, 'nodes':{'vision':example_node()}}
        core.write_private(self.root/'state.json', core.json_text(state))
        number = free_port()
        while number == state['nodes']['vision']['port']: number = free_port()
        original = (self.root/'state.json').read_bytes()
        result = self.cli('--kind', 'vision', '--address', 'example.com', '--listen', '127.0.0.1', '--port', str(number))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('该协议已安装', result.stderr)
        self.assertIn('编辑节点', result.stderr)
        self.assertEqual((self.root/'state.json').read_bytes(), original)
        self.assertFalse(list(self.root.glob('.stage-*')))

    def test_stopped_managed_port_conflict_is_rejected_without_mutation(self):
        core.ensure_owned(self.root, True)
        state = {'schema':1, 'nodes':{'vision':example_node()}}
        core.write_private(self.root/'state.json', core.json_text(state))
        original = (self.root/'state.json').read_bytes()
        result = self.cli('--kind', 'xhttp-reality', '--address', 'example.com', '--listen', '127.0.0.1',
                          '--port', str(state['nodes']['vision']['port']))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('托管节点端口冲突', result.stderr)
        self.assertEqual((self.root/'state.json').read_bytes(), original)
        self.assertFalse(list(self.root.glob('.stage-*')))

    def test_occupied_port_has_actionable_message(self):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0)); listener.listen()
            number = listener.getsockname()[1]
            result = self.cli('--address', 'example.com', '--listen', '127.0.0.1', '--port', str(number))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(f'TCP {number}', result.stderr)
            self.assertIn('已被占用', result.stderr)
            self.assertIn('choose a free port', result.stderr)
            self.assertFalse(self.root.exists())

    def test_blank_address_reprompts_and_port_conflict_stops_before_network(self):
        sentinel = self.base/'unexpected-action'
        script = '''source "$1"
helper(){
 if [[ $1 == preflight ]]; then python3 "$CORE_SOURCE" "$@"
 else touch "$UNEXPECTED_INSTALL_ACTION"; return 1; fi
}
ensure_binary(){ touch "$UNEXPECTED_INSTALL_ACTION"; return 1; }
LANGUAGE=$2
install_node
'''
        with socket.socket() as listener:
            listener.bind(('0.0.0.0', 0)); listener.listen()
            number = listener.getsockname()[1]
            for language in ['zh', 'en']:
                with self.subTest(language=language):
                    result = subprocess.run(['bash', '-c', script, 'test', str(PROJECT/'xray-manager.sh'), language],
                        input=f'1\n\n{number}\n1\n   \n127.0.0.1\n', capture_output=True, text=True, timeout=10,
                        env={**os.environ, 'CORE_SOURCE':str(PROJECT/'src/core.py'),
                             'UNEXPECTED_INSTALL_ACTION':str(sentinel), 'SKYBYTE_XRAY_DIR':str(self.root)})
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('没有默认值' if language == 'zh' else 'There is no default', result.stdout)
                    self.assertIn(f'TCP {number}', result.stderr)
                    self.assertFalse(sentinel.exists())
                    self.assertFalse(self.root.exists())

    def test_port_taken_after_preflight_preserves_existing_config(self):
        core.ensure_owned(self.root, True)
        state = {'schema':1, 'nodes':{'vision':example_node()}}
        for relative, data in core.render_files(state, self.root).items():
            core.write_private(self.root/relative, data)
        original = {path.name:path.read_bytes() for path in self.root.iterdir() if path.is_file()}
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0)); listener.listen()
            with self.assertRaisesRegex(ValueError, '已被占用'):
                core.prepare(self.root, Path('/unavailable-core'),
                             options('xhttp-reality', port=str(listener.getsockname()[1])))
        self.assertEqual(original, {path.name:path.read_bytes() for path in self.root.iterdir() if path.is_file()})
        self.assertFalse(list(self.root.glob('.stage-*')))

    def test_error_categories_do_not_expose_external_secrets(self):
        secret = 'SECRET_NOT_FOR_LOGS'
        cases = [(PermissionError(errno.EACCES, secret, '/'+secret), '权限不足'),
                 (FileNotFoundError(errno.ENOENT, secret, '/'+secret), '不存在'),
                 (OSError(errno.ENOSPC, secret), '磁盘空间不足'),
                 (urllib.error.HTTPError('https://'+secret, 403, secret, {}, None), 'HTTP 403'),
                 (urllib.error.URLError(secret), '网络请求失败'),
                 (ssl.SSLError(secret), 'TLS 验证'),
                 (subprocess.CalledProcessError(1, [secret], output=secret), '命令失败')]
        for error, expected in cases:
            with self.subTest(category=type(error).__name__):
                message = core.error_message(error)
                self.assertIn(expected, message)
                self.assertNotIn(secret, message)


class EditTests(unittest.TestCase):
    def test_edit_preserves_credentials_other_nodes_and_original(self):
        for kind in core.KINDS:
            with self.subTest(kind=kind):
                state = {'schema': 1, 'nodes': {k: example_node(k) for k in core.KINDS}}
                original = copy.deepcopy(state)
                changed_port = free_port()
                while changed_port in [n['port'] for n in state['nodes'].values()]:
                    changed_port = free_port()
                path = '/changed/path' if kind.startswith('xhttp') else None
                edited = core.edit_state(state, kind, 'node.example.com', changed_port, path)
                expected = copy.deepcopy(original)
                expected['nodes'][kind].update(address='node.example.com', port=changed_port)
                if path: expected['nodes'][kind]['path'] = path
                self.assertEqual(edited, expected)
                self.assertEqual(state, original)

    def test_unchanged_port_is_not_probed(self):
        state = {'schema': 1, 'nodes': {'vision': example_node()}}
        with mock.patch.object(core, 'check_port', side_effect=AssertionError('current port')):
            edited = core.edit_state(state, 'vision', '2001:db8::1', state['nodes']['vision']['port'])
        self.assertEqual(edited['nodes']['vision']['address'], '2001:db8::1')

    def test_reject_invalid_edits_and_missing_node(self):
        state = {'schema': 1, 'nodes': {'vision': example_node(), 'xhttp-reality': example_node('xhttp-reality')}}
        for kind, changes in [('vision', {'client_address': 'bad;id'}),
                              ('vision', {'client_address': ''}),
                              ('vision', {'node_port': '0'}),
                              ('vision', {'node_port': state['nodes']['xhttp-reality']['port']}),
                              ('vision', {'path': '/path'}),
                              ('xhttp-reality', {'path': '/bad?query'}),
                              ('xhttp-tls', {'client_address': 'example.com'})]:
            with self.subTest(kind=kind, changes=changes), self.assertRaises(ValueError):
                core.edit_state(state, kind, **changes)

    def test_reject_occupied_port(self):
        state = {'schema': 1, 'nodes': {'vision': example_node()}}
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0)); listener.listen()
            with self.assertRaisesRegex(ValueError, '已被占用'):
                core.edit_state(state, 'vision', node_port=listener.getsockname()[1])


class FileTests(TemporaryFixture):
    def test_private_atomic_write(self):
        destination=self.base/'file'
        core.write_private(destination,'private')
        self.assertEqual(destination.stat().st_mode & 0o777,0o600)
        self.assertEqual(destination.read_text(),'private')

    def test_symlinks_and_ancestors_refused(self):
        real=self.base/'real';real.mkdir()
        link=self.base/'link';link.symlink_to(real,target_is_directory=True)
        with self.assertRaises(ValueError): core.write_private(link/'file','data')

    def test_foreign_configuration_preserved(self):
        self.root.mkdir();p=self.root/'config.json';p.write_text('foreign')
        with self.assertRaises(ValueError): core.ensure_owned(self.root,True)
        self.assertEqual(p.read_text(),'foreign')

    def test_foreign_service_preserved(self):
        self.unit.write_text('[Service]\nExecStart=/someone/else\n')
        with self.assertRaises(ValueError): core.unit_guard(self.unit)
        self.assertIn('/someone/else',self.unit.read_text())

    def test_owned_root_private(self):
        core.ensure_owned(self.root,True)
        self.assertEqual(self.root.stat().st_mode & 0o777,0o700)
        self.assertEqual((self.root/'.owner').stat().st_mode & 0o777,0o600)

    def test_language_symlink_refused(self):
        core.ensure_owned(self.root,True)
        outside=self.base/'outside';outside.write_text('do not modify')
        (self.root/'language').symlink_to(outside)
        with self.assertRaises(ValueError): core.ensure_owned(self.root)
        self.assertEqual(outside.read_text(),'do not modify')

    def test_commit_and_rollback_preserve_unknown_file(self):
        core.ensure_owned(self.root,True)
        unknown=self.root/'notes.txt';unknown.write_text('user notes')
        stage=core.make_stage(self.root,{'schema':1,'nodes':{'vision':example_node()}})
        core.write_private(stage/'state.json',core.json_text({'schema':1,'nodes':{'vision':example_node()}}))
        with mock.patch.object(core,'engine_check'):
            core.commit(self.root,stage,Path('/engine'),self.unit,False,False)
        self.assertTrue((self.root/'nodes.txt').exists())
        self.assertEqual(unknown.read_text(),'user notes')
        flags=core.rollback(self.root,self.unit)
        self.assertFalse(flags['active'])
        self.assertFalse((self.root/'state.json').exists())
        self.assertFalse(self.unit.exists())
        self.assertEqual(unknown.read_text(),'user notes')

    def test_failed_validation_does_not_replace_existing_state(self):
        core.ensure_owned(self.root,True)
        old={'schema':1,'nodes':{'vision':example_node()}}
        for path,data in core.render_files(old,self.root).items(): core.write_private(self.root/path,data)
        stage=core.make_stage(self.root,{'schema':1,'nodes':{}})
        core.write_private(stage/'state.json',core.json_text({'schema':1,'nodes':{}}))
        with mock.patch.object(core,'engine_check',side_effect=ValueError('bad engine')):
            with self.assertRaises(ValueError): core.commit(self.root,stage,Path('/engine'),self.unit,True,True)
        self.assertEqual(core.load_state(self.root),old)
        self.assertFalse((self.root/'.transaction').exists())

    def test_unknown_managed_filename_collision_refused(self):
        core.ensure_owned(self.root,True)
        (self.root/'config.json').write_text('foreign custom config')
        stage=core.make_stage(self.root,{'schema':1,'nodes':{}})
        core.write_private(stage/'state.json',core.json_text({'schema':1,'nodes':{}}))
        with self.assertRaises(ValueError): core.commit(self.root,stage,Path('/engine'),self.unit,False,False)
        self.assertEqual((self.root/'config.json').read_text(),'foreign custom config')

    def test_backup_is_private_and_does_not_overwrite(self):
        core.ensure_owned(self.root,True)
        destination=self.base/'backup.tar.gz'
        core.backup(self.root,destination)
        self.assertEqual(destination.stat().st_mode & 0o777,0o600)
        with self.assertRaises(ValueError): core.backup(self.root,destination)

    def test_archive_rejects_traversal_links_duplicates(self):
        core.ensure_owned(self.root,True)
        for attack in ['traversal','link','duplicate']:
            archive=self.base/(attack+'.tar.gz')
            with tarfile.open(archive,'w:gz') as output:
                item=tarfile.TarInfo('../outside' if attack=='traversal' else 'state.json')
                if attack=='link': item.type=tarfile.SYMTYPE;item.linkname='/etc/passwd';output.addfile(item)
                else:
                    item.size=2;output.addfile(item,io.BytesIO(b'{}'))
                    if attack=='duplicate': output.addfile(item,io.BytesIO(b'{}'))
            with self.subTest(attack=attack),self.assertRaises(ValueError):
                core.restore_stage(self.root,Path('/engine'),archive)

    def test_download_checks_official_digest(self):
        archive=io.BytesIO()
        with zipfile.ZipFile(archive,'w') as output: output.writestr('xray',b'test engine')
        data=archive.getvalue()
        asset='Xray-linux-64.zip'
        metadata={'tag_name':core.CORE_VERSION,'draft':False,'prerelease':False,'assets':[{'name':asset,
            'browser_download_url':f'https://github.com/XTLS/Xray-core/releases/download/{core.CORE_VERSION}/{asset}',
            'digest':'sha256:'+hashlib.sha256(data).hexdigest()}]}
        with mock.patch.dict(os.environ,SKYBYTE_GITHUB_TOKEN='test-metadata-token'), mock.patch.object(core.urllib.request,'urlopen',side_effect=[io.BytesIO(json.dumps(metadata).encode()),io.BytesIO(data)]) as fetch:
            core.download_binary(self.base/'xray',asset)
        metadata_request=fetch.call_args_list[0].args[0]
        self.assertEqual(metadata_request.get_header('Authorization'),'Bearer test-metadata-token')
        self.assertIsInstance(fetch.call_args_list[1].args[0],str)
        self.assertEqual((self.base/'xray').read_bytes(),b'test engine')
        self.assertEqual((self.base/'xray').stat().st_mode & 0o777,0o700)

    def test_download_digest_mismatch_rejected(self):
        asset='Xray-linux-64.zip'
        metadata={'tag_name':core.CORE_VERSION,'draft':False,'assets':[{'name':asset,
            'browser_download_url':f'https://github.com/XTLS/Xray-core/releases/download/{core.CORE_VERSION}/{asset}',
            'digest':'sha256:'+'0'*64}]}
        with mock.patch.object(core.urllib.request,'urlopen',side_effect=[io.BytesIO(json.dumps(metadata).encode()),io.BytesIO(b'tampered')]):
            with self.assertRaises(ValueError): core.download_binary(self.base/'xray',asset)
        self.assertFalse((self.base/'xray').exists())

    def test_download_unknown_url_rejected(self):
        asset='Xray-linux-64.zip'
        metadata={'tag_name':core.CORE_VERSION,'assets':[{'name':asset,'browser_download_url':'http://untrusted/xray',
            'digest':'sha256:'+'0'*64}]}
        with mock.patch.object(core.urllib.request,'urlopen',return_value=io.BytesIO(json.dumps(metadata).encode())):
            with self.assertRaises(ValueError): core.download_binary(self.base/'xray',asset)


@unittest.skipUnless(ENGINE,'Set XRAY_BIN to the verified official Xray binary')
class EngineTests(TemporaryFixture):
    @classmethod
    def setUpClass(cls):
        cls.cert_temp=tempfile.TemporaryDirectory(dir=WORK)
        cls.cert_base=Path(cls.cert_temp.name)
        cls.cert=cls.cert_base/'cert.pem';cls.private_key=cls.cert_base/'key.pem'
        config=cls.cert_base/'openssl.cnf'
        config.write_text('[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=extensions\n[dn]\nCN=localhost\n[extensions]\nsubjectAltName=DNS:localhost\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,digitalSignature,keyEncipherment,keyCertSign\nextendedKeyUsage=serverAuth\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\n')
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','3',
            '-config',str(config),'-keyout',str(cls.private_key),'-out',str(cls.cert)],
            check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

    @classmethod
    def tearDownClass(cls): cls.cert_temp.cleanup()

    def make_protocol(self,kind,**changes):
        settings=options(kind,**changes)
        if kind=='xhttp-tls': settings.cert=str(self.cert);settings.key=str(self.private_key);settings.ca_file=str(self.cert)
        stage=core.prepare(self.root,Path(ENGINE),settings)
        core.commit(self.root,stage,Path(ENGINE),self.unit,False,False)
        core.finalize(self.root,stage)
        return core.load_state(self.root)['nodes'][kind]

    def test_all_three_configs_accepted_by_official_core(self):
        for kind in core.KINDS:
            node=self.make_protocol(kind)
            filename=self.root/('client-'+kind+'.json')
            core.engine_check(Path(ENGINE),filename)
            self.assertIn(node['uuid'],filename.read_text())
        self.assertEqual(len(core.load_state(self.root)['nodes']),3)

    def test_cli_edit_regenerates_valid_exports_and_preserves_certificates(self):
        for kind in core.KINDS:
            self.make_protocol(kind)
        old = core.load_state(self.root)
        tls = {n: (self.root/n).read_bytes() for n in core.tls_names(old)}
        for kind in core.KINDS:
            new_port = free_port()
            while new_port in [n['port'] for n in core.load_state(self.root)['nodes'].values()]:
                new_port = free_port()
            args = ['--address', 'new.example.com', '--port', str(new_port)]
            if kind.startswith('xhttp'): args += ['--path', '/new/path']
            result = subprocess.run([os.sys.executable, str(PROJECT/'src/core.py'), 'edit',
                '--root', str(self.root), '--unit', str(self.unit), '--binary', ENGINE, '--kind', kind, *args], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            stage = Path(result.stdout.strip())
            self.assertEqual(core.load_state(self.root)['nodes'][kind], old['nodes'][kind])
            core.commit(self.root, stage, Path(ENGINE), self.unit, False, False)
            core.finalize(self.root, stage)
            node = core.load_state(self.root)['nodes'][kind]
            for field in set(old['nodes'][kind]) - {'address', 'port', 'path'}:
                self.assertEqual(node[field], old['nodes'][kind][field])
            self.assertEqual(node['address'], 'new.example.com')
            self.assertEqual(node['port'], new_port)
            if kind.startswith('xhttp'): self.assertEqual(node['path'], '/new/path')
            core.engine_check(Path(ENGINE), self.root/('client-'+kind+'.json'))
            self.assertIn(core.node_uri(kind, node), (self.root/'nodes.txt').read_text())
            self.assertEqual(base64.b64decode((self.root/'subscription-base64.txt').read_text()).decode(),
                             (self.root/'nodes.txt').read_text())
            for relative, data in tls.items(): self.assertEqual((self.root/relative).read_bytes(), data)

    def test_existing_protocol_not_overwritten(self):
        node=self.make_protocol('vision')
        with self.assertRaises(ValueError): core.prepare(self.root,Path(ENGINE),options())
        self.assertEqual(core.load_state(self.root)['nodes']['vision'],node)

    def test_port_collision_not_overwritten(self):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1',0));listener.listen()
            with self.assertRaisesRegex(ValueError, '已被占用'):
                core.prepare(self.root,Path(ENGINE),options(port=str(listener.getsockname()[1])))
        self.assertFalse((self.root/'state.json').exists())

    def test_certificate_key_and_hostname_validation(self):
        core.certificate(self.cert,self.private_key,'localhost',str(self.cert))
        with self.assertRaises(ValueError): core.certificate(self.cert,self.private_key,'other.example',str(self.cert))
        with self.assertRaises(ValueError): core.certificate(self.cert,self.private_key,'localhost')
        alternate=self.cert_base/'other.key'
        subprocess.run(['openssl','genrsa','-out',str(alternate),'2048'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        with self.assertRaises(ssl.SSLError): core.certificate(self.cert,alternate,'localhost',str(self.cert))

    def test_certificate_sources_preserved(self):
        before=self.private_key.read_bytes()
        self.make_protocol('xhttp-tls')
        self.assertEqual(self.private_key.read_bytes(),before)
        node=core.load_state(self.root)['nodes']['xhttp-tls']
        self.assertEqual((self.root/node['key']).stat().st_mode & 0o777,0o600)

    def test_backup_restore_preserves_uuid_keys_and_exports(self):
        for kind in core.KINDS: self.make_protocol(kind)
        original=core.load_state(self.root)
        uri_before=(self.root/'nodes.txt').read_text()
        archive=self.base/'backup.tar.gz';core.backup(self.root,archive)
        stage=core.restore_stage(self.root,Path(ENGINE),archive,str(self.cert))
        self.assertEqual(core.load_state(stage),original)
        core.commit(self.root,stage,Path(ENGINE),self.unit,False,False)
        core.finalize(self.root,stage)
        self.assertEqual((self.root/'nodes.txt').read_text(),uri_before)

    def test_real_vision_connection(self): self.real_connection('vision')
    def test_real_xhttp_reality_connection(self): self.real_connection('xhttp-reality')
    def test_real_xhttp_tls_verified_connection(self): self.real_connection('xhttp-tls')
    def test_real_cdn_packet_up_origin_connection(self): self.real_connection('xhttp-tls',cdn=True,mode='packet-up')
    def test_private_ip_rejected(self): self.real_connection('vision',block_private=True)
    def test_private_hostname_rejected(self): self.real_connection('vision',block_private=True,destination_host='localhost')

    def test_edited_nodes_forward_with_preserved_credentials(self):
        for kind in core.KINDS:
            with self.subTest(kind=kind):
                self.real_connection(kind, edit_before_connect=True)

    def real_connection(self,kind,block_private=False,destination_host=None,edit_before_connect=False,**changes):
        # Private lab: trusted local CA, HTTPS camouflage target, and local HTTP endpoint.
        tls_listener=socket.socket();tls_listener.bind(('127.0.0.1',0));tls_listener.listen();tls_listener.settimeout(0.25)
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.minimum_version=ssl.TLSVersion.TLSv1_3
        context.load_cert_chain(str(self.cert),str(self.private_key));context.set_alpn_protocols(['h2'])
        stopped=threading.Event()
        def tls_worker():
            while not stopped.is_set():
                try:
                    connection,_=tls_listener.accept();connection.settimeout(3)
                    try:
                        with context.wrap_socket(connection,server_side=True) as secure:
                            try: secure.recv(4096)
                            except (OSError,ssl.SSLError): pass
                    except (OSError,ssl.SSLError): connection.close()
                except socket.timeout: pass
                except OSError: break
        thread=threading.Thread(target=tls_worker,daemon=True);thread.start()
        import http.server
        reached=threading.Event()
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                reached.set()
                body=b'SKYBYTE authenticated proxy test'
                self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
            def log_message(self,*args): pass
        endpoint=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        http_thread=threading.Thread(target=endpoint.serve_forever,daemon=True);http_thread.start()
        processes=[]
        try:
            node=self.make_protocol(kind,target='localhost:'+str(tls_listener.getsockname()[1]),**changes)
            if edit_before_connect:
                new_port = free_port()
                while new_port in [n['port'] for n in core.load_state(self.root)['nodes'].values()]:
                    new_port = free_port()
                state = core.edit_state(core.load_state(self.root), kind, 'localhost', new_port,
                                        '/edited/forwarding' if kind.startswith('xhttp') else None)
                stage = core.make_stage(self.root, state)
                core.finish_stage(stage, state, Path(ENGINE))
                core.commit(self.root, stage, Path(ENGINE), self.unit, False, False)
                core.finalize(self.root, stage)
                edited = core.load_state(self.root)['nodes'][kind]
                for field in set(node) - {'address', 'port', 'path'}:
                    self.assertEqual(edited[field], node[field])
                node = edited
            server=core.server_config(core.load_state(self.root),self.root)
            if not block_private:
                server['routing']['rules']=[]  # Allow only the isolated lab's endpoint in connection tests.
            server_path=self.base/'lab-server.json';core.write_private(server_path,core.json_text(server))
            socks_port=free_port();client=core.client_config(kind,node,socks_port)
            if kind=='xhttp-tls':
                client['outbounds'][0]['streamSettings']['tlsSettings']['certificates']=[{
                    'certificateFile':str(self.cert),'usage':'verify'}]
            client_path=self.base/'lab-client.json';core.write_private(client_path,core.json_text(client))
            core.engine_check(Path(ENGINE),server_path);core.engine_check(Path(ENGINE),client_path)
            for config_path in [server_path,client_path]:
                processes.append(subprocess.Popen([ENGINE,'run','-config',str(config_path)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL))
            for _ in range(50):
                try:
                    with socket.create_connection(('127.0.0.1',socks_port),timeout=.2): break
                except OSError: time.sleep(.1)
            for process in processes: self.assertIsNone(process.poll(),'Lab process failed to start')
            with socket.create_connection(('127.0.0.1',socks_port),timeout=15) as connection:
                connection.settimeout(20)
                def receive(count):
                    data=b''
                    while len(data)<count:
                        chunk=connection.recv(count-len(data))
                        if not chunk: raise AssertionError('Proxy closed before authenticated response')
                        data+=chunk
                    return data
                connection.sendall(b'\x05\x01\x00');self.assertEqual(receive(2),b'\x05\x00')
                number=endpoint.server_address[1]
                target=b'\x01\x7f\x00\x00\x01' if destination_host is None else b'\x03'+bytes([len(destination_host)])+destination_host.encode()
                connection.sendall(b'\x05\x01\x00'+target+number.to_bytes(2,'big'))
                header=receive(4);self.assertEqual(header[1],0)
                if header[3]==1: receive(6)
                elif header[3]==4: receive(18)
                else: receive(receive(1)[0]+2)
                connection.sendall(b'GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n')
                response=b''
                if block_private: connection.settimeout(2)
                while b'SKYBYTE authenticated proxy test' not in response:
                    try: chunk=connection.recv(4096)
                    except (socket.timeout,ConnectionResetError):
                        if block_private: break
                        raise
                    if not chunk: break
                    response+=chunk
                if block_private:
                    self.assertFalse(reached.is_set(),'Private HTTP endpoint was reached through the proxy')
                    self.assertNotIn(b'SKYBYTE authenticated proxy test',response)
                else: self.assertIn(b'SKYBYTE authenticated proxy test',response)
        finally:
            for process in processes:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill();process.wait()
            stopped.set();tls_listener.close();endpoint.shutdown();endpoint.server_close();thread.join(timeout=4);http_thread.join(timeout=2)


if __name__=='__main__': unittest.main()
