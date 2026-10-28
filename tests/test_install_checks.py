"""Automatic and standalone preflight gates cannot alter a failed deployment."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from test_manager import PROJECT


class InstallationCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def run_case(self, failure='', inputs='1\n\n\n\n203.0.113.10\n\n\ny\n', language='zh'):
        script = '''source "$1"
LANGUAGE=$2
helper(){ echo "HELPER $*";case $1 in preflight|reality-input|tls-input)return 0;;*)touch "$SENTINEL";;esac; }
install_check_engine(){ echo "CHECK $*";[[ $* != *"--phase $FAIL_PHASE"* ]]; }
reality_engine(){ echo "TARGET $*";[[ $FAIL_PHASE != target ]]; }
ensure_binary(){ touch "$SENTINEL"; }
apply_stage(){ touch "$SENTINEL"; }
show_nodes(){ :; }
install_node'''
        result = subprocess.run(['bash','-c',script,'test',str(PROJECT/'xray-manager.sh'),language],
                                input=inputs,capture_output=True,text=True,timeout=5,
                                env={**os.environ,'NO_COLOR':'1','FAIL_PHASE':failure or 'none',
                                     'SENTINEL':str(self.root/'unexpected-write'),
                                     'SKYBYTE_XRAY_DIR':str(self.root/'managed')})
        return result

    def test_failed_stages_stop_before_core_or_configuration(self):
        for language in ('zh','en'):
            for failure in ('environment','ports','target','download'):
                with self.subTest(language=language,failure=failure):
                    result = self.run_case(failure,language=language)
                    self.assertNotEqual(result.returncode,0,result.stdout+result.stderr)
                    self.assertFalse((self.root/'unexpected-write').exists())
                    self.assertFalse((self.root/'managed').exists())
                    if failure == 'target':
                        self.assertIn('Reality target failed checks' if language=='en' else 'Reality 握手目标检测未通过',result.stdout+result.stderr)

    def test_standalone_checks_do_not_ask_to_install_and_return_on_zero(self):
        result = self.run_case(inputs='4\n1\n\n1\n\n\n0\n')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        for phase in ('environment','ports','download'):
            self.assertIn('--phase '+phase,result.stdout)
        self.assertIn('--target www.microsoft.com:443',result.stdout)
        self.assertNotIn('[y/N]',result.stderr)
        self.assertFalse((self.root/'unexpected-write').exists())
        self.assertFalse((self.root/'managed').exists())

    def test_reality_input_validation_is_local_and_rejects_invalid_values(self):
        for target in ('https://example.com:443','example.com:65536','example.com:not-a-port'):
            result = subprocess.run(['python3',str(PROJECT/'src/core.py'),'reality-input','--root',str(self.root/'managed'),
                                     '--sni','example.com','--target',target],capture_output=True,text=True,timeout=5)
            self.assertNotEqual(result.returncode,0)
            self.assertFalse((self.root/'managed').exists())
