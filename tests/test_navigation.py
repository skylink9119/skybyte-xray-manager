"""Continuous keyboard navigation, with host services and packages stubbed out."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]


class NavigationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)

    def shell(self, code, inputs, language='zh'):
        script = '''source "$1"
LANGUAGE=$2
show_startup_info(){ echo OVERVIEW; }
helper(){ echo "HELPER $*"; }
install_firewall(){ echo INSTALL_ENABLE_UFW; }
systemctl(){ echo "SYSTEMCTL $*"; }
'''+code
        result = subprocess.run(['bash','-c',script,'test',str(PROJECT/'xray-manager.sh'),language],
                                input=inputs,text=True,capture_output=True,timeout=5,
                                env={**os.environ,'NO_COLOR':'1','SKYBYTE_XRAY_DIR':self.temp.name})
        self.assertEqual(result.returncode,0,result.stderr+result.stdout)
        return result

    def test_firewall_operations_stay_open_until_zero_in_both_languages(self):
        for language in ('zh','en'):
            result=self.shell('main_menu','L\n2\n1\n6\n0\nq\n',language)
            self.assertLess(result.stdout.index('INSTALL_ENABLE_UFW'),result.stdout.index('HELPER firewall-status'))
            self.assertIn('HELPER bbr-status',result.stdout)
            self.assertEqual(result.stdout.count('OVERVIEW'),2)
            self.assertEqual(result.stdout.splitlines().count('0 Back' if language=='en' else '0 返回'),4)
            self.assertIn('l. ',result.stdout)
            self.assertIn('q. ',result.stdout)

    def test_failed_operation_invalid_input_and_cancel_do_not_leave_menu(self):
        code='''install_firewall(){ echo INSTALL_FAILED;return 1; }
main_menu'''
        result=self.shell(code,'l\n999\n2\n4\nbad\n7\nn\n1\n0\nQ\n')
        self.assertIn('INSTALL_FAILED',result.stdout)
        self.assertIn('HELPER firewall-status',result.stdout)
        self.assertNotIn('HELPER bbr-enable',result.stdout)
        self.assertIn('可在当前菜单继续选择',result.stderr)
        self.assertEqual(result.stdout.count('OVERVIEW'),2)

    def test_service_operations_continue_after_failure(self):
        code='''systemctl(){ echo "SYSTEMCTL $*";[[ $1 != start ]]; }
main_menu'''
        result=self.shell(code,'d\n2\n1\n4\n0\nq\n')
        self.assertIn('SYSTEMCTL start',result.stdout)
        self.assertIn('SYSTEMCTL status',result.stdout)
        self.assertIn('SYSTEMCTL restart',result.stdout)
        self.assertEqual(result.stdout.count('OVERVIEW'),2)

    def test_warp_cancel_and_tests_continue_in_same_menu(self):
        code='''warp_install_client(){ echo WARP_INSTALL;return 1; }
warp_platform_test(){ echo PLATFORM_TEST; }
main_menu'''
        result=self.shell(code,'n\n1\n3\nn\n4\n\n5\n\n0\nq\n')
        self.assertIn('WARP_INSTALL',result.stdout)
        self.assertIn('HELPER warp-check --proxy-port 40000',result.stdout)
        self.assertIn('PLATFORM_TEST',result.stdout)
        self.assertNotIn('HELPER warp-prepare',result.stdout)
        self.assertEqual(result.stdout.count('OVERVIEW'),2)

    def test_eof_returns_without_looping(self):
        for inputs in ('','l\n','l\n1\n','d\n','n\n','e\n','o\n','o\n2\n'):
            result=self.shell('main_menu',inputs)
            self.assertLess(len(result.stdout),20000)

    def test_reality_checks_stay_open_after_failure_and_accept_custom_sni(self):
        for language in ('zh', 'en'):
            result = self.shell('''reality_engine(){ printf 'REALITY %s\\n' "$*";return 1; }
main_menu''', 'O\n1\n2\ntarget.example:8443\nsni.example\n2\n0\n0\nq\n', language)
            self.assertIn('--project xray --language '+language+' --config ', result.stdout)
            self.assertIn('--target target.example:8443 --sni sni.example', result.stdout)
            self.assertEqual(result.stdout.count('REALITY '), 2)
            self.assertEqual(result.stdout.count('OVERVIEW'), 2)

    def test_all_letters_reach_the_matching_main_entry(self):
        actions={'a':'install_node','b':'show_nodes','c':'qr_nodes','f':'update_core',
                 'g':'make_backup','h':'restore_backup','i':'guide','j':'choose_language',
                 'k':'uninstall','m':'update_manager','p':'show_parameters'}
        for letter,action in actions.items():
            code=action+'(){ echo ACTION_'+action+';return '+('2' if letter=='m' else '0')+'; };main_menu'
            result=self.shell(code,letter.upper()+'\nq\n')
            self.assertIn('ACTION_'+action,result.stdout)
