"""Transactions, exports, restoration and real IPv4/IPv6 protocol forwarding."""
import base64,copy,json,unittest,urllib.parse
from pathlib import Path
import test_manager as manager
import test_services as services
core=manager.core
PUBLIC='2001:4860:4860::8888'
class BackupStateTests(unittest.TestCase):
 def test_exports_keep_original_links_and_credentials_for_all_protocols(self):
  nodes={k:dict(manager.example_node(k),listen='0.0.0.0',address='8.8.8.8') for k in core.KINDS}
  state={'schema':1,'nodes':nodes};original=copy.deepcopy(state)
  backup=core.ipv6_state(state,PUBLIC)
  self.assertEqual(state,original)
  files=core.render_files(backup,Path('/etc/skybyte-xray'))
  links=files['nodes.txt'].splitlines();self.assertEqual(len(links),6)
  for index,(kind,node) in enumerate(nodes.items()):
   self.assertEqual(links[index],core.node_uri(kind,node))
   parsed=urllib.parse.urlsplit(links[index+3]);old=urllib.parse.urlsplit(links[index])
   self.assertEqual(parsed.hostname,PUBLIC);self.assertEqual(parsed.port,old.port)
   self.assertEqual(parsed.username,old.username);self.assertEqual(parsed.query,old.query)
   cfg=json.loads(files['client-'+kind+'-ipv6.json'])
   self.assertEqual(cfg['outbounds'][0]['settings']['vnext'][0]['address'],PUBLIC)
  self.assertEqual(base64.b64decode(files['subscription-base64.txt']).decode(),files['nodes.txt'])
  self.assertEqual(core.ipv6_state(core.ipv6_state(backup,'2606:4700:4700::1111')),original)
 def test_cdn_preserved_and_loopback_private_bad_metadata_rejected(self):
  node=dict(manager.example_node('xhttp-tls'),cdn=True)
  state={'schema':1,'nodes':{'xhttp-tls':node,'vision':dict(manager.example_node(),listen='0.0.0.0')}}
  backup=core.ipv6_state(state,PUBLIC);self.assertEqual(backup['nodes']['xhttp-tls'],node)
  for value in ('::1','fd00::1','::ffff:8.8.8.8','ff0e::1','2001:db8::1'):
   with self.subTest(value=value),self.assertRaises(ValueError):core.ipv6_state(state,value)
  with self.assertRaises(ValueError):core.ipv6_state({'schema':1,'nodes':{'vision':manager.example_node()}},PUBLIC)
class BackupTransactionTests(services.ServiceFixture):
 def test_backup_roundtrip_and_removal_remove_only_backup_exports(self):
  state=self.installed();state['nodes']['vision']['listen']='0.0.0.0'
  stage=self.stage(core.ipv6_state(state,PUBLIC));core.commit(self.root,stage,Path(manager.ENGINE),self.unit,False,False);core.finalize(self.root,stage)
  saved=core.load_state(self.root);archive=self.base/'backup.tar.gz';core.backup(self.root,archive)
  restored=core.restore_stage(self.root,Path(manager.ENGINE),archive)
  self.assertEqual(core.load_state(restored),saved)
  core.finalize(self.root,restored)
  stage=self.stage(core.ipv6_state(saved));core.commit(self.root,stage,Path(manager.ENGINE),self.unit,False,False);core.finalize(self.root,stage)
  self.assertFalse((self.root/'client-vision-ipv6.json').exists());self.assertTrue((self.root/'client-vision.json').exists())
 def test_failed_readiness_restores_service_exports_and_state(self):
  state=self.installed();self.set_controller(active=True,enabled=True)
  # The fake service controller cannot create a listener: inject the readiness failure.
  state['nodes']['vision']['listen']='0.0.0.0';stage=self.stage(core.ipv6_state(state,PUBLIC))
  before={n:(self.root/n).read_bytes() for n in core.owned_names(core.load_state(self.root))}
  result=self.shell('ipv6_engine(){ return 1; };apply_stage "$2" no ipv6',stage)
  self.assertNotEqual(result.returncode,0)
  for n,data in before.items():self.assertEqual((self.root/n).read_bytes(),data)
  self.assertFalse((self.root/'client-vision-ipv6.json').exists());self.assertTrue(self.state()['active']);self.assertTrue(self.state()['enabled'])
@unittest.skipUnless(manager.ENGINE,'Official Xray required')
class DualStackProtocolTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):manager.EngineTests.setUpClass.__func__(cls)
 @classmethod
 def tearDownClass(cls):manager.EngineTests.tearDownClass.__func__(cls)
 tearDown=manager.EngineTests.tearDown
 setUp=manager.EngineTests.setUp
 real_connection=manager.EngineTests.real_connection
 make_protocol=manager.EngineTests.make_protocol
 def test_ipv6_vision(self):self.real_connection('vision',listen='::',address='::1')
 def test_ipv6_xhttp_reality(self):self.real_connection('xhttp-reality',listen='::',address='::1')
 def test_ipv6_xhttp_tls_verified(self):self.real_connection('xhttp-tls',listen='::',address='::1')
 def test_original_ipv4_still_works_on_dual_stack_listener(self):self.real_connection('vision',listen='::',address='127.0.0.1')
