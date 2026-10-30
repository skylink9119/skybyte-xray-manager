"""Port-only menu edits retain identity and handle UFW before replacing the listener."""
import json,socket,unittest,urllib.parse
from pathlib import Path
import test_manager as manager
import test_services as services
core=manager.core
class PortEditorTests(services.ServiceFixture):
 def setUp(self):
  super().setUp()
  ufw=self.tools/'ufw';ufw.write_text('''#!/usr/bin/env python3
import os,sys
if sys.argv[1]=='status':
 if os.environ.get('PORT_TEST_UFW')=='error':sys.exit(1)
 print('Status: '+os.environ.get('PORT_TEST_UFW','inactive'))
elif sys.argv[1]=='allow':
 with open(os.environ['PORT_TEST_LOG'],'a') as f:f.write(' '.join(sys.argv[1:])+'\\n')
 if os.environ.get('PORT_TEST_UFW_FAIL'):sys.exit(1)
''');ufw.chmod(0o755)
  self.ufw_log=self.base/'ufw.log';self.env['PORT_TEST_LOG']=str(self.ufw_log)
 def shell(self,command,*arguments):
  return super().shell('LANGUAGE=en;'+command,*arguments)
 def test_blank_and_cancel_keep_original_files_and_stopped_service(self):
  state=self.installed();before={n:(self.root/n).read_bytes() for n in core.owned_names(state)}
  for inputs in ('5\n\n','5\n10443\nn\n'):
   result=self.shell('edit_nodes <<< "$2"',inputs);self.assertEqual(result.returncode,0,result.stderr)
   for n,data in before.items():self.assertEqual((self.root/n).read_bytes(),data)
  self.assertNotIn('restart',self.state()['history']);self.assertFalse(self.ufw_log.exists())
 def test_edit_preserves_all_fields_except_port_and_updates_ipv6_links(self):
  state=self.installed();state['nodes']['vision']['listen']='0.0.0.0';state=core.ipv6_state(state,'2001:4860:4860::8888')
  for n,data in core.render_files(state,self.root).items():core.write_private(self.root/n,data)
  self.set_controller(active=True);number=manager.free_port();self.env['PORT_TEST_UFW']='active'
  result=self.shell('edit_nodes <<< "$2"',f'5\n{number}\ny\n');self.assertEqual(result.returncode,0,result.stderr)
  expected=json.loads(json.dumps(state));expected['nodes']['vision']['port']=number
  self.assertEqual(core.load_state(self.root),expected);self.assertTrue(self.state()['active'])
  links=[urllib.parse.urlsplit(s) for s in (self.root/'nodes.txt').read_text().splitlines()]
  self.assertEqual([u.port for u in links],[number,number]);self.assertIn(str(number),self.ufw_log.read_text())
 def test_ufw_failure_prevents_any_node_or_service_change(self):
  state=self.installed();self.set_controller(active=True);self.env.update(PORT_TEST_UFW='active',PORT_TEST_UFW_FAIL='1')
  before={n:(self.root/n).read_bytes() for n in core.owned_names(state)}
  result=self.shell('edit_nodes <<< "$2"',f'5\n{manager.free_port()}\ny\n');self.assertNotEqual(result.returncode,0)
  for n,data in before.items():self.assertEqual((self.root/n).read_bytes(),data)
  self.assertNotIn('restart',self.state()['history']);self.assertFalse(list(self.root.glob('.stage-*')))
 def test_failed_restart_rolls_back_node_and_keeps_reported_ufw_rule(self):
  state=self.installed();self.set_controller(active=True,enabled=True,fail_restart=True);self.env['PORT_TEST_UFW']='active'
  result=self.shell('edit_nodes <<< "$2"',f'5\n{manager.free_port()}\ny\n');self.assertNotEqual(result.returncode,0)
  self.assertEqual(core.load_state(self.root),state);self.assertTrue(self.state()['active']);self.assertTrue(self.state()['enabled'])
  self.assertIn('UFW allow rule is retained',result.stdout)
 def test_occupied_port_is_rejected_before_any_firewall_rule(self):
  state=self.installed();self.env['PORT_TEST_UFW']='active'
  with socket.socket() as occupied:
   occupied.bind(('127.0.0.1',0));occupied.listen();number=occupied.getsockname()[1]
   result=self.shell('edit_nodes <<< "$2"',f'5\n{number}\ny\n');self.assertNotEqual(result.returncode,0)
  self.assertEqual(core.load_state(self.root),state);self.assertFalse(self.ufw_log.exists())

 def test_unknown_ufw_state_keeps_node_port(self):
  state=self.installed();self.env['PORT_TEST_UFW']='error'
  result=self.shell('edit_nodes <<< "$2"',f'5\n{manager.free_port()}\ny\n');self.assertNotEqual(result.returncode,0)
  self.assertEqual(core.load_state(self.root),state);self.assertFalse(list(self.root.glob('.stage-*')))

 def test_current_port_prompt_in_both_languages(self):
  state=self.installed()
  for language in ('zh','en'):
   result=self.shell('LANGUAGE="$3";edit_nodes <<< "$2"','5\n\n',language)
   self.assertEqual(result.returncode,0,result.stderr);self.assertIn(str(state['nodes']['vision']['port']),result.stderr)
   self.assertNotIn('unbound variable',result.stderr)

 def test_only_installed_nodes_are_listed_when_selecting_port_target(self):
  state=self.installed();state['nodes']['xhttp-reality']=manager.example_node('xhttp-reality')
  core.write_private(self.root/'state.json',core.json_text(state))
  result=self.shell('choose_port_node <<< "$2"','2\n')
  self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(result.stdout,'xhttp-reality')
  self.assertNotIn('xhttp-tls',result.stderr)
