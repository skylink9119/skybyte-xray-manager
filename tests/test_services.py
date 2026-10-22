# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
"""Real configuration transactions with a disposable systemctl controller.

These check rollback policy. They do not claim a real systemd boot test.
"""
import json
import os
from pathlib import Path
import subprocess
import unittest
from test_manager import TemporaryFixture, ENGINE, PROJECT, core, example_node, free_port


@unittest.skipUnless(ENGINE,'Set XRAY_BIN to the official Xray binary')
class ServiceTests(TemporaryFixture):
    def setUp(self):
        super().setUp()
        self.tools=self.base/'tools';self.tools.mkdir()
        self.control=self.base/'systemd.json'
        self.control.write_text(json.dumps({'active':False,'enabled':False,'fail_restart':False,'history':[]}))
        executable=self.tools/'systemctl'
        executable.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
p=Path(os.environ['FAKE_SYSTEMD_STATE'])
x=json.loads(p.read_text());cmd=sys.argv[1];x['history'].append(cmd);result=0
if cmd=='is-active': result=0 if x['active'] else 3
elif cmd=='is-enabled': result=0 if x['enabled'] else 1
elif cmd=='restart':
 if x['fail_restart']: x['fail_restart']=False;x['active']=False;result=1
 else: x['active']=True
elif cmd=='start': x['active']=True
elif cmd=='stop':
 if x.get('fail_stop'): result=1
 else: x['active']=False
elif cmd=='enable': x['enabled']=True
elif cmd=='disable': x['enabled']=False
p.write_text(json.dumps(x));sys.exit(result)
''')
        executable.chmod(0o755)
        self.env={**os.environ,'PATH':str(self.tools)+os.pathsep+os.environ['PATH'],
            'FAKE_SYSTEMD_STATE':str(self.control),'SKYBYTE_XRAY_DIR':str(self.root),
            'SKYBYTE_XRAY_BINARY':ENGINE,'SKYBYTE_XRAY_UNIT':str(self.unit),'SKYBYTE_XRAY_LIB':str(self.base/'lib')}
        core.ensure_owned(self.root,True)

    def state(self): return json.loads(self.control.read_text())
    def set_controller(self,**changes):
        data=self.state();data.update(changes);self.control.write_text(json.dumps(data))
    def installed(self):
        state={'schema':1,'nodes':{'vision':example_node()}}
        for relative,data in core.render_files(state,self.root).items(): core.write_private(self.root/relative,data)
        core.write_private(self.unit,core.unit_content(self.root,Path(ENGINE)),0o644)
        return state
    def stage(self,state):
        stage=core.make_stage(self.root,state)
        core.finish_stage(stage,state,Path(ENGINE))
        return stage
    def shell(self,command,*arguments):
        return subprocess.run(['bash','-c','source "$1"; '+command,'test',str(PROJECT/'xray-manager.sh'),*map(str,arguments)],
            env=self.env,capture_output=True,text=True)

    def test_first_install_success_starts_and_enables_owned_service(self):
        state={'schema':1,'nodes':{'vision':example_node()}}
        result=self.shell('apply_stage "$2" yes',self.stage(state))
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertTrue(self.state()['active']);self.assertTrue(self.state()['enabled'])
        self.assertEqual(core.load_state(self.root),state)
        self.assertFalse((self.root/'.transaction').exists())

    def test_failed_restart_restores_config_activity_and_boot_state(self):
        old=self.installed();new=json.loads(json.dumps(old));new['nodes']['vision']['name']='new name'
        self.set_controller(active=True,enabled=False,fail_restart=True)
        result=self.shell('apply_stage "$2" yes',self.stage(new))
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(core.load_state(self.root),old)
        self.assertTrue(self.state()['active']);self.assertFalse(self.state()['enabled'])
        self.assertFalse((self.root/'.transaction').exists())

    def test_failed_first_install_removes_only_new_managed_files(self):
        user_file=self.root/'my-notes';user_file.write_text('keep this')
        self.set_controller(fail_restart=True)
        result=self.shell('apply_stage "$2" yes',self.stage({'schema':1,'nodes':{'vision':example_node()}}))
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(self.state()['active']);self.assertFalse(self.state()['enabled'])
        self.assertFalse((self.root/'state.json').exists());self.assertFalse(self.unit.exists())
        self.assertEqual(user_file.read_text(),'keep this')

    def test_stopped_service_stays_stopped_during_rename(self):
        old=self.installed();new=json.loads(json.dumps(old));new['nodes']['vision']['name']='renamed'
        result=self.shell('apply_stage "$2"',self.stage(new))
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse(self.state()['active'])
        self.assertNotIn('restart',self.state()['history'])
        self.assertEqual(core.load_state(self.root)['nodes']['vision']['uuid'],old['nodes']['vision']['uuid'])

    def test_edit_menu_preserves_credentials_and_stopped_service(self):
        for language in ['zh', 'en']:
            with self.subTest(language=language):
                old = self.installed()
                result = self.shell('LANGUAGE="$2"; edit_nodes <<< "$3"', language,
                                    '4\n1\nnew.example.com\n\n')
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = json.loads(json.dumps(old))
                expected['nodes']['vision']['address'] = 'new.example.com'
                self.assertEqual(core.load_state(self.root), expected)
                self.assertFalse(self.state()['active'])
                self.assertNotIn('restart', self.state()['history'])

    def test_xhttp_edit_menu_updates_path_and_restarts_active_service(self):
        state = {'schema': 1, 'nodes': {'xhttp-reality': example_node('xhttp-reality')}}
        for relative, data in core.render_files(state, self.root).items():
            core.write_private(self.root/relative, data)
        core.write_private(self.unit, core.unit_content(self.root, Path(ENGINE)), 0o644)
        new_port = free_port()
        while new_port == state['nodes']['xhttp-reality']['port']: new_port = free_port()
        self.set_controller(active=True, enabled=True)
        result = self.shell('edit_nodes <<< "$2"', f'4\n2\nnew.example.com\n{new_port}\n/new/path\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        state['nodes']['xhttp-reality'].update(address='new.example.com', port=new_port, path='/new/path')
        self.assertEqual(core.load_state(self.root), state)
        self.assertTrue(self.state()['active'])
        self.assertTrue(self.state()['enabled'])
        self.assertIn('restart', self.state()['history'])

    def test_edit_menu_blank_input_does_not_restart(self):
        old = self.installed()
        self.set_controller(active=True)
        result = self.shell('edit_nodes <<< "$2"', '4\n1\n\n\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(core.load_state(self.root), old)
        self.assertNotIn('restart', self.state()['history'])

    def test_edit_restart_failure_restores_exports_and_credentials(self):
        old = self.installed()
        original = {n: (self.root/n).read_bytes() for n in core.owned_names(old)}
        self.set_controller(active=True, enabled=True, fail_restart=True)
        result = self.shell('edit_nodes <<< "$2"', '4\n1\nnew.example.com\n\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(core.load_state(self.root), old)
        for relative, data in original.items():
            self.assertEqual((self.root/relative).read_bytes(), data)
        self.assertTrue(self.state()['active'])
        self.assertTrue(self.state()['enabled'])
        self.assertFalse((self.root/'.transaction').exists())

    def test_interrupted_transaction_recovered_before_next_menu(self):
        old=self.installed();new=json.loads(json.dumps(old));new['nodes']['vision']['name']='uncommitted'
        core.commit(self.root,self.stage(new),Path(ENGINE),self.unit,True,True)
        result=self.shell('recover')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(core.load_state(self.root),old)
        self.assertTrue(self.state()['active']);self.assertTrue(self.state()['enabled'])

    def test_removing_last_protocol_stops_and_disables_service(self):
        self.installed();self.set_controller(active=True,enabled=True)
        result=self.shell('apply_stage "$2"',self.stage({'schema':1,'nodes':{}}))
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse(self.state()['active']);self.assertFalse(self.state()['enabled'])
        self.assertEqual(core.load_state(self.root)['nodes'],{})

    def fake_apt(self):
        executable=self.tools/'apt-get'
        executable.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
p=Path(os.environ['FAKE_APT_LOG'])
lines=json.loads(p.read_text()) if p.exists() else []
lines.append(sys.argv[1:]);p.write_text(json.dumps(lines))
sys.exit(100 if 'update' in sys.argv else 0)
''')
        executable.chmod(0o755)
        log=self.base/'apt.json'
        self.env['FAKE_APT_LOG']=str(log)
        return log

    def test_dependency_index_failure_does_not_run_install(self):
        log=self.fake_apt()
        script='source "$1"; command(){ if [[ $1 == -v && $2 == python3 ]]; then return 1; fi; builtin command "$@"; }; dependencies'
        result=subprocess.run(['bash','-c',script,'test',str(PROJECT/'xray-manager.sh')],
            env=self.env,input='y\n',capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        calls=json.loads(log.read_text())
        self.assertEqual(len(calls),1)
        self.assertIn('APT::Update::Error-Mode=any',calls[0])
        self.assertNotIn('install',calls[0])

    def test_qr_index_failure_does_not_run_install(self):
        log=self.fake_apt()
        script='source "$1"; command(){ if [[ $1 == -v && $2 == qrencode ]]; then return 1; fi; builtin command "$@"; }; qr_nodes'
        result=subprocess.run(['bash','-c',script,'test',str(PROJECT/'xray-manager.sh')],
            env=self.env,input='Y\n',capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(len(json.loads(log.read_text())),1)

    def uninstall_fixture(self,foreign=False,installed=True):
        if installed: self.installed()
        lib=self.base/'lib';lib.mkdir()
        (lib/'.owner').write_text(core.OWNER)
        binary=lib/'xray'
        if installed:
            binary.write_text('#!/usr/bin/env bash\nexit 0\n');binary.chmod(0o700)
        (lib/'manager.sh').write_text((PROJECT/'xray-manager.sh').read_text())
        shortcut=self.base/'xr'
        shortcut.write_text('foreign command' if foreign else '#!/usr/bin/env bash\n# SKYBYTE Xray Manager shortcut v1\nexec bash '+str(lib/'manager.sh')+' "$@"\n')
        self.env.update(SKYBYTE_XRAY_BINARY=str(binary),SKYBYTE_XRAY_SHORTCUT=str(shortcut))
        return shortcut

    def test_uninstall_removes_owned_shortcut_and_preserves_backup(self):
        shortcut=self.uninstall_fixture()
        result=self.shell('uninstall <<< Y')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse(shortcut.exists())
        self.assertTrue(list((self.root/'backups').glob('*.tar.gz')))

    def test_uninstall_preserves_replaced_shortcut(self):
        shortcut=self.uninstall_fixture(foreign=True)
        result=self.shell('uninstall <<< y')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(shortcut.read_text(),'foreign command')

    def test_uninstall_without_nodes_or_unit_removes_manager_and_keeps_backup(self):
        shortcut = self.uninstall_fixture(installed=False)
        note = self.root/'my-notes'; note.write_text('keep this')
        config = self.root/'config.json'; config.write_text('unmanaged configuration')
        result = self.shell('uninstall <<< Y')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(shortcut.exists())
        self.assertFalse((self.base/'lib/manager.sh').exists())
        self.assertTrue(list((self.root/'backups').glob('*.tar.gz')))
        self.assertEqual(note.read_text(), 'keep this')
        self.assertEqual(config.read_text(), 'unmanaged configuration')
        self.assertNotIn('stop', self.state()['history'])
        self.assertNotIn('disable', self.state()['history'])

    def test_uninstall_stop_failure_keeps_manager_and_configuration(self):
        shortcut = self.uninstall_fixture()
        original = (self.root/'state.json').read_bytes()
        self.set_controller(active=True, fail_stop=True)
        result = self.shell('uninstall <<< Y')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(shortcut.exists())
        self.assertTrue((self.base/'lib/manager.sh').exists())
        self.assertEqual((self.root/'state.json').read_bytes(), original)
        self.assertTrue(self.state()['active'])
        self.assertNotIn('disable', self.state()['history'])


if __name__=='__main__': unittest.main()
