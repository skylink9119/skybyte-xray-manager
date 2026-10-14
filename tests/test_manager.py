# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
import argparse
import base64
import copy
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

    def test_yes_is_case_insensitive(self):
        for value in ['yes','YES','Yes','yEs']:
            result=subprocess.run(['bash','-c','source "$1"; confirmed "$2"','test',str(PROJECT/'xray-manager.sh'),value])
            self.assertEqual(result.returncode,0)
        result=subprocess.run(['bash','-c','source "$1"; confirmed no','test',str(PROJECT/'xray-manager.sh')])
        self.assertNotEqual(result.returncode,0)

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

    def test_existing_protocol_not_overwritten(self):
        node=self.make_protocol('vision')
        with self.assertRaises(ValueError): core.prepare(self.root,Path(ENGINE),options())
        self.assertEqual(core.load_state(self.root)['nodes']['vision'],node)

    def test_port_collision_not_overwritten(self):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1',0));listener.listen()
            with self.assertRaises(OSError): core.prepare(self.root,Path(ENGINE),options(port=str(listener.getsockname()[1])))
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

    def real_connection(self,kind,**changes):
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
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                body=b'SKYBYTE authenticated proxy test'
                self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
            def log_message(self,*args): pass
        endpoint=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        http_thread=threading.Thread(target=endpoint.serve_forever,daemon=True);http_thread.start()
        processes=[]
        try:
            node=self.make_protocol(kind,target='localhost:'+str(tls_listener.getsockname()[1]),**changes)
            server=core.server_config(core.load_state(self.root),self.root)
            server['routing']['rules']=[]  # Lab endpoint is loopback; production blocks private destinations.
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
                connection.sendall(b'\x05\x01\x00\x01\x7f\x00\x00\x01'+number.to_bytes(2,'big'))
                header=receive(4);self.assertEqual(header[1],0)
                if header[3]==1: receive(6)
                elif header[3]==4: receive(18)
                else: receive(receive(1)[0]+2)
                connection.sendall(b'GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n')
                response=b''
                while b'SKYBYTE authenticated proxy test' not in response:
                    chunk=connection.recv(4096)
                    if not chunk: break
                    response+=chunk
                self.assertIn(b'SKYBYTE authenticated proxy test',response)
        finally:
            for process in processes:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill();process.wait()
            stopped.set();tls_listener.close();endpoint.shutdown();endpoint.server_close();thread.join(timeout=4);http_thread.join(timeout=2)


if __name__=='__main__': unittest.main()
