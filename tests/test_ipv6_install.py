"""Independent IPv6 installation keeps existing protocols and transaction rollback intact."""
import json,os,shlex,subprocess,unittest,urllib.parse
import test_manager as manager
import test_services as services
import test_navigation as navigation
PUBLIC='2001:4860:4860::8888'

class IPv6InstallNavigationTests(unittest.TestCase):
 setUp=navigation.NavigationTests.setUp
 shell=navigation.NavigationTests.shell
 # Run only this class's new scenario; the existing navigation class is separate.
 def test_ipv6_child_selection_and_zero_return_in_both_languages(self):
  for language in ('zh','en'):
   r=self.shell('''install_node(){ echo "INSTALL $*"; }
run_submenu ipv6_install_menu''','2\n1\n0\n',language)
   self.assertIn('INSTALL ipv6 2',r.stdout);self.assertIn('INSTALL ipv6 1',r.stdout)

@unittest.skipUnless(manager.ENGINE,'Official Xray required')
class IPv6InstallTests(services.ServiceFixture):
 def run_install(self,kind='1',failure='',selection='',confirm='y'):
  number=manager.free_port();log=self.base/'ipv6-install.log'
  script='''source "$1"
ip(){ :; }
sleep(){ :; }
original_helper=$(declare -f helper)
eval "${original_helper/helper/original_helper}"
helper(){
 case $1 in
  ufw-state) [[ $FAILURE != ufw-status ]] || return 1;echo active;;
  firewall-allow) echo FIREWALL >> "$INSTALL_LOG";[[ $FAILURE != ufw-allow ]];;
  *) original_helper "$@";;
 esac
}
ipv6_engine(){
 echo "IPV6 $*" >> "$INSTALL_LOG"
 case $1 in
  detect) [[ $FAILURE != detect ]] || return 1;printf '%s\\n' '''+shlex.quote(PUBLIC)+''';;
  check-install) [[ $FAILURE != check && $2 == '''+shlex.quote(PUBLIC)+''' ]];;
  ready-install) [[ $FAILURE != ready ]];;
  *)return 1;;
 esac
}
install_check_engine(){ [[ $FAILURE != ports ]]; }
reality_engine(){ :; }
ensure_binary(){ echo CORE >> "$INSTALL_LOG"; }
show_nodes(){ echo EXPORTED; }
install_node ipv6 "$2"
'''
  # IPv6 selection, name, port, Reality SNI selection, target, XHTTP path/mode, confirm.
  inputs=selection+'\n\n'+str(number)+'\n\n\n'+('\n\n' if kind=='2' else '')+confirm+'\n'
  result=subprocess.run(['bash','-c',script,'test',str(manager.PROJECT/'xray-manager.sh'),kind],
   input=inputs,capture_output=True,text=True,timeout=15,
   env={**self.env,'FAILURE':failure,'NO_COLOR':'1','INSTALL_LOG':str(log)})
  calls=log.read_text() if log.exists() else ''
  return result,number,calls
 def test_fresh_vision_ipv6_primary_address_and_exports(self):
  r,number,calls=self.run_install()
  self.assertEqual(r.returncode,0,r.stderr+r.stdout)
  state=manager.core.load_state(self.root);node=state['nodes']['vision']
  self.assertEqual(node['address'],PUBLIC);self.assertEqual(node['listen'],'::');self.assertEqual(node['port'],number)
  self.assertNotIn('ipv6_backup',node);self.assertTrue(node['name'].endswith('-IPv6'))
  self.assertEqual(urllib.parse.urlsplit((self.root/'nodes.txt').read_text().strip()).hostname,PUBLIC)
  self.assertIn('ready-install '+str(number),calls);self.assertIn('FIREWALL',calls)
 def test_add_ipv6_xhttp_does_not_change_existing_ipv4_vision(self):
  old=self.installed();before=old['nodes']['vision']
  r,number,calls=self.run_install('2')
  self.assertEqual(r.returncode,0,r.stderr+r.stdout)
  state=manager.core.load_state(self.root);self.assertEqual(state['nodes']['vision'],before)
  self.assertEqual(state['nodes']['xhttp-reality']['address'],PUBLIC)
  self.assertIn('ready-install '+str(number),calls)
 def test_cancel_or_failed_checks_do_not_prepare_nodes_or_download_core(self):
  for fail,select,answer in [('detect','','y'),('check','','y'),('ports','','y'),('','0','y'),('','','n')]:
   r,_,calls=self.run_install(failure=fail,selection=select,confirm=answer)
   self.assertEqual(r.returncode==0,not fail,r.stderr+r.stdout)
   self.assertNotIn('CORE',calls);self.assertNotIn('FIREWALL',calls)
   self.assertEqual(manager.core.load_state(self.root)['nodes'],{})
   self.assertFalse((self.root/'config.json').exists());self.assertFalse(self.unit.exists())
 def test_readiness_failure_rolls_back_existing_config_credentials_and_service_flags(self):
  old=self.installed();self.set_controller(active=True,enabled=True)
  before={name:(self.root/name).read_bytes() for name in manager.core.owned_names(old)}
  r,_,_=self.run_install('2','ready');self.assertNotEqual(r.returncode,0)
  for name,data in before.items():self.assertEqual((self.root/name).read_bytes(),data)
  self.assertTrue(self.state()['active']);self.assertTrue(self.state()['enabled'])
  self.assertFalse((self.root/'client-xhttp-reality.json').exists());self.assertFalse((self.root/'.transaction').exists())
 def test_firewall_failure_keeps_existing_node_without_restart(self):
  for failure in ('ufw-status','ufw-allow'):
   old=self.installed();history=len(self.state()['history'])
   r,_,_=self.run_install('2',failure);self.assertNotEqual(r.returncode,0)
   self.assertEqual(manager.core.load_state(self.root),old)
   self.assertNotIn('restart',self.state()['history'][history:])
   self.assertFalse(list(self.root.glob('.stage-*')))

class IPv6TLSMenuTests(manager.TemporaryFixture):
 def test_tls_ipv6_is_direct_and_keeps_certificate_verification(self):
  log=self.base/'args'
  script='''source "$1"
ipv6_install_address(){ printf '''+shlex.quote(PUBLIC)+'''; }
ipv6_engine(){ :; };install_check_engine(){ :; };ensure_binary(){ :; };show_nodes(){ :; }
helper(){ echo "$*" >> "$INSTALL_LOG";case $1 in prepare)echo /mock-stage;;ufw-state)echo absent;;esac; }
apply_stage(){ echo "APPLY $*" >> "$INSTALL_LOG"; }
install_node ipv6 3'''
  r=subprocess.run(['bash','-c',script,'test',str(manager.PROJECT/'xray-manager.sh')],input='\n\ncert.example\n/cert.pem\n/key.pem\n\n\ny\n',
   capture_output=True,text=True,timeout=5,env={**os.environ,'NO_COLOR':'1','INSTALL_LOG':str(log)})
  self.assertEqual(r.returncode,0,r.stdout+r.stderr)
  calls=log.read_text();prepared=next(x for x in calls.splitlines() if x.startswith('prepare '))
  self.assertIn('--address '+PUBLIC,prepared);self.assertIn('--listen ::',prepared)
  self.assertIn('--sni cert.example',prepared);self.assertIn('--cert /cert.pem --key /key.pem',prepared)
  self.assertNotIn('--cdn',prepared);self.assertNotIn('CDN?',r.stderr)
 def test_missing_iproute2_is_installed_without_polluting_selected_address(self):
  script='''source "$1"
command(){ if [[ ${1:-} == -v && ${2:-} == ip ]];then declare -F ip >/dev/null;else builtin command "$@";fi; }
apt_refresh(){ echo APT_REFRESH; }
apt-get(){ echo INSTALLED_IPROUTE2;ip(){ :; }; }
ipv6_engine(){ case $1 in detect)echo '''+shlex.quote(PUBLIC)+''';;check-install)echo FIREWALL_NOTE;;esac; }
ipv6_install_address'''
  r=subprocess.run(['bash','-c',script,'test',str(manager.PROJECT/'xray-manager.sh')],input='\n',capture_output=True,text=True,timeout=5,env={**os.environ,'NO_COLOR':'1'})
  self.assertEqual(r.returncode,0,r.stdout+r.stderr);self.assertEqual(r.stdout.strip(),PUBLIC)
  self.assertIn('INSTALLED_IPROUTE2',r.stderr);self.assertIn('FIREWALL_NOTE',r.stderr)
