# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
"""Installer integrity, file ownership and executable shortcut checks."""
import hashlib
import os
import subprocess
import sys
import tarfile
from test_manager import TemporaryFixture, PROJECT


class InstallerTests(TemporaryFixture):
    def setUp(self):
        super().setUp()
        self.lib=self.base/'library'
        self.shortcut=self.base/'bin with spaces'/'xr'
        self.env=os.environ.copy()

    def shell(self,command,*args,input=None):
        return subprocess.run(['bash','-c','source "$1"; '+command,'test',str(PROJECT/'install.sh'),*map(str,args)],
                              env=self.env,input=input,capture_output=True,text=True)

    def test_dependency_confirmation_accepts_y_and_cancels_other_input(self):
        for answer in ['y','Y','  y  ','\tY\t']:
            result=self.shell('confirm_dependencies',input=answer+'\n')
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn('[y/N]',result.stderr)
        for answer in ['','n','N','yes','YES','yy']:
            result=self.shell('confirm_dependencies && printf EXECUTED',input=answer+'\n')
            self.assertNotEqual(result.returncode,0)
            self.assertNotIn('EXECUTED',result.stdout)
        self.assertNotEqual(self.shell('confirm_dependencies',input='').returncode,0)

    def install(self):
        return self.shell('install_payload "$2" "$3" "$4"',PROJECT/'xray-manager.sh',self.lib,self.shortcut)

    def remote(self,manifest=None):
        self.assets=self.base/'assets';self.assets.mkdir()
        payload=(PROJECT/'xray-manager.sh').read_bytes()
        (self.assets/'xray-manager.sh').write_bytes(payload)
        digest=hashlib.sha256(payload).hexdigest()
        (self.assets/'SHA256SUMS').write_text(manifest if manifest is not None else digest+'  xray-manager.sh\n')
        tools=self.base/'tools';tools.mkdir()
        curl=tools/'curl'
        curl.write_text('''#!/usr/bin/env python3
import os,shutil,sys
from pathlib import Path
args=sys.argv[1:]
url=next(x for x in args if x.startswith('https://'))
prefix='https://github.com/skylink9119/skybyte-xray-manager/releases/download/v0.1.13/'
if not url.startswith(prefix): sys.exit(23)
asset=url[len(prefix):]
if asset not in ['SHA256SUMS','xray-manager.sh']: sys.exit(23)
source=Path(os.environ['FAKE_RELEASE_ASSETS'])/asset
if not source.is_file(): sys.exit(22)
shutil.copyfile(source,args[args.index('-o')+1])
''')
        curl.chmod(0o755)
        self.env.update(PATH=str(tools)+os.pathsep+os.environ['PATH'],FAKE_RELEASE_ASSETS=str(self.assets))
        destination=self.base/'download';destination.mkdir()
        return destination

    def test_verified_single_file_download(self):
        destination=self.remote()
        result=self.shell('download_manager "$2"',destination)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual((destination/'xray-manager.sh').read_bytes(),(PROJECT/'xray-manager.sh').read_bytes())

    def test_tampered_payload_rejected(self):
        destination=self.remote()
        (self.assets/'xray-manager.sh').write_bytes(b'not the release payload')
        result=self.shell('download_manager "$2"',destination)
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(self.lib.exists())

    def test_duplicate_checksum_entry_rejected(self):
        destination=self.remote()
        manifest=self.assets/'SHA256SUMS'
        manifest.write_text(manifest.read_text()*2)
        self.assertNotEqual(self.shell('download_manager "$2"',destination).returncode,0)

    def test_missing_checksum_entry_rejected(self):
        destination=self.remote('0'*64+'  another-file.sh\n')
        self.assertNotEqual(self.shell('download_manager "$2"',destination).returncode,0)

    def test_failed_download_stops_before_installation(self):
        destination=self.remote()
        (self.assets/'SHA256SUMS').unlink()
        self.assertNotEqual(self.shell('download_manager "$2"',destination).returncode,0)
        self.assertFalse((destination/'xray-manager.sh').exists())
        self.assertFalse(self.lib.exists())

    def test_install_and_shortcut_forward_arguments(self):
        result=self.install()
        self.assertEqual(result.returncode,0,result.stderr)
        result=subprocess.run([str(self.shortcut),'--version'],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout.strip(),'SKYBYTE Xray Manager 0.1.13')
        self.assertEqual(self.lib.stat().st_mode & 0o777,0o700)
        self.assertEqual((self.lib/'manager.sh').stat().st_mode & 0o777,0o700)
        self.assertEqual((self.lib/'.owner').stat().st_mode & 0o777,0o600)

    def test_reinstall_preserves_runtime_configuration(self):
        self.assertEqual(self.install().returncode,0)
        state=self.root/'state.json';self.root.mkdir();state.write_text('{"existing":"keep"}')
        notes=self.lib/'notes.txt';notes.write_text('keep')
        self.assertEqual(self.install().returncode,0)
        self.assertEqual(state.read_text(),'{"existing":"keep"}')
        self.assertEqual(notes.read_text(),'keep')

    def test_reinstall_refuses_downgrade_before_replacing_files(self):
        self.assertEqual(self.install().returncode, 0)
        target = self.lib/'manager.sh'
        newer = target.read_bytes().replace(b'\nVERSION=0.1.13\n', b'\nVERSION=0.99.0\n', 1)
        target.write_bytes(newer)
        shortcut = self.shortcut.read_bytes()
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('downgrade refused', result.stderr)
        self.assertEqual(target.read_bytes(), newer)
        self.assertEqual(self.shortcut.read_bytes(), shortcut)

    def test_unknown_installed_version_is_not_overwritten(self):
        self.assertEqual(self.install().returncode, 0)
        target = self.lib/'manager.sh'
        unknown = target.read_bytes().replace(b'\nVERSION=0.1.13\n', b'\nVERSION=development\n', 1)
        target.write_bytes(unknown)
        shortcut = self.shortcut.read_bytes()
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('version unknown', result.stderr)
        self.assertEqual(target.read_bytes(), unknown)
        self.assertEqual(self.shortcut.read_bytes(), shortcut)

    def test_payload_requires_one_matching_version_before_installation(self):
        payload = (PROJECT/'xray-manager.sh').read_bytes()
        source = self.base/'candidate.sh'
        for replacement in [b'\nVERSION=0.99.0\n', b'\n', b'\nVERSION=0.1.13\nVERSION=0.1.13\n']:
            with self.subTest(replacement=replacement):
                source.write_bytes(payload.replace(b'\nVERSION=0.1.13\n', replacement, 1))
                result = self.shell('install_payload "$2" "$3" "$4"', source, self.lib, self.shortcut)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.lib.exists())
                self.assertFalse(self.shortcut.exists())

    def test_foreign_library_preserved(self):
        self.lib.mkdir();foreign=self.lib/'config.json';foreign.write_text('keep')
        self.assertNotEqual(self.install().returncode,0)
        self.assertEqual(foreign.read_text(),'keep')
        self.assertFalse(self.shortcut.exists())

    def test_foreign_shortcut_preserved_before_mutation(self):
        self.shortcut.parent.mkdir();self.shortcut.write_text('another program')
        self.assertNotEqual(self.install().returncode,0)
        self.assertEqual(self.shortcut.read_text(),'another program')
        self.assertFalse(self.lib.exists())

    def test_symlink_shortcut_parent_refused(self):
        real=self.base/'real-bin';real.mkdir()
        self.shortcut.parent.symlink_to(real,target_is_directory=True)
        self.assertNotEqual(self.install().returncode,0)
        self.assertFalse((real/'xr').exists())

    def test_package_contains_only_source_and_matching_checksums(self):
        result=subprocess.run([sys.executable,str(PROJECT/'scripts/package.py')],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        folder=PROJECT/'dist'
        for line in (folder/'SHA256SUMS').read_text().splitlines():
            digest,name=line.split()
            self.assertEqual(hashlib.sha256((folder/name).read_bytes()).hexdigest(),digest)
        with tarfile.open(folder/'SKYBYTE-Xray-Manager-v0.1.13.tar.gz') as archive:
            names={item.name for item in archive}
        prefix='skybyte-xray-manager-v0.1.13/'
        self.assertIn(prefix+'LICENSE',names)
        self.assertIn(prefix+'tests/test_installer.py',names)
        self.assertIn(prefix+'docs/REVIEW.md',names)
        self.assertTrue(all(name.startswith(prefix) for name in names))
        self.assertFalse(any('/work/' in name or name.endswith(('state.json','.pem','.key','.crt')) for name in names))
