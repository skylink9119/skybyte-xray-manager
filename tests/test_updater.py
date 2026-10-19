# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
"""Release verification and atomic manager replacement with isolated HTTP fixtures."""
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import urllib.error
from unittest import mock
from test_manager import TemporaryFixture, PROJECT, core


class ManagerUpdateTests(TemporaryFixture):
    def setUp(self):
        super().setUp()
        self.directory = self.base/'installed manager'
        self.directory.mkdir()
        self.target = self.directory/'manager.sh'
        self.backup = self.directory/'manager.previous.sh'
        (self.directory/'.owner').write_text(core.OWNER)
        self.old = (PROJECT/'xray-manager.sh').read_bytes()
        self.target.write_bytes(self.old)
        version = list(core.manager_version('v'+core.VERSION)); version[2] += 1
        self.tag = 'v'+'.'.join(map(str, version))
        # A minimal official-shaped diagnostic payload, isolated from real host operations.
        self.payload = core.MANAGER_HEADER + b' generated test payload\n' + (
            'case "$1" in\n--version) echo "SKYBYTE Xray Manager '+self.tag[1:]+'";;\n'
            '--self-check) echo "SKYBYTE Xray Manager '+self.tag[1:]+' OK";;\nesac\n').encode()
        self.manifest = (hashlib.sha256(self.payload).hexdigest()+'  xray-manager.sh\n').encode()
        self.urls = []
        self.refresh_metadata()
        patch = mock.patch.object(core.urllib.request, 'urlopen', side_effect=self.urlopen)
        patch.start(); self.addCleanup(patch.stop)

    def refresh_metadata(self):
        self.metadata = {'tag_name':self.tag, 'draft':False, 'prerelease':False, 'assets':[]}
        for name, data in [('xray-manager.sh', self.payload), ('SHA256SUMS', self.manifest)]:
            self.metadata['assets'].append({'name':name,
                'browser_download_url':f'https://github.com/{core.MANAGER_REPO}/releases/download/{self.tag}/{name}',
                'digest':'sha256:'+hashlib.sha256(data).hexdigest()})

    def urlopen(self, request, **kwargs):
        url = request.full_url if hasattr(request, 'full_url') else request
        self.urls.append(url)
        if url.startswith('https://api.github.com/repos/'+core.MANAGER_REPO+'/releases/'):
            return io.BytesIO(json.dumps(self.metadata).encode())
        if url == f'https://github.com/{core.MANAGER_REPO}/releases/download/{self.tag}/SHA256SUMS':
            return io.BytesIO(self.manifest)
        if url == f'https://github.com/{core.MANAGER_REPO}/releases/download/{self.tag}/xray-manager.sh':
            return io.BytesIO(self.payload)
        raise AssertionError(url)

    def unchanged(self):
        self.assertEqual(self.target.read_bytes(), self.old)
        self.assertFalse(list(self.directory.glob('.manager-update-*')))
        self.assertFalse(list(self.directory.glob('.write-*')))

    def test_verified_atomic_update_preserves_config_and_shortcut(self):
        notes = self.directory/'notes.txt'; notes.write_text('keep')
        state = self.base/'state.json'; state.write_text('credentials stay')
        shortcut = self.base/'xr'; shortcut.write_text('keep shortcut')
        core.manager_update(self.target, self.tag)
        self.assertEqual(self.target.read_bytes(), self.payload)
        self.assertEqual(self.backup.read_bytes(), self.old)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.backup.stat().st_mode & 0o777, 0o700)
        self.assertEqual(notes.read_text(), 'keep')
        self.assertEqual(state.read_text(), 'credentials stay')
        self.assertEqual(shortcut.read_text(), 'keep shortcut')
        self.assertFalse(list(self.directory.glob('.manager-update-*')))

    def test_same_or_older_version_refused_without_network(self):
        for tag in ['v'+core.VERSION, 'v0.0.1']:
            with self.subTest(tag=tag), self.assertRaises(ValueError): core.manager_update(self.target, tag)
        self.assertFalse(self.urls); self.unchanged()

    def test_newer_installed_script_is_not_downgraded_by_old_running_copy(self):
        newer = self.old.replace(('VERSION='+core.VERSION+'\n').encode(), b'VERSION=99.0.0\n', 1)
        self.target.write_bytes(newer)
        with self.assertRaisesRegex(ValueError, '不覆盖'): core.manager_update(self.target, self.tag)
        self.assertEqual(self.target.read_bytes(), newer)
        self.assertFalse(self.urls)

    def test_release_payload_size_is_bounded(self):
        self.payload = b'x'*(core.MAX_MANAGER+1)
        self.manifest = (hashlib.sha256(self.payload).hexdigest()+'  xray-manager.sh\n').encode()
        self.refresh_metadata()
        with self.assertRaises(ValueError): core.manager_update(self.target, self.tag)
        self.unchanged()

    def test_wrong_release_prerelease_or_draft_refused(self):
        original = copy.deepcopy(self.metadata)
        for changes in [{'prerelease':True}, {'draft':True}, {'tag_name':'v99.0.0'}, {'tag_name':'invalid'}]:
            self.metadata = {**copy.deepcopy(original), **changes}
            with self.subTest(changes=changes), self.assertRaises(ValueError): core.manager_update(self.target, self.tag)
            self.unchanged()

    def test_download_failure_retains_original(self):
        with mock.patch.object(core.urllib.request, 'urlopen', side_effect=urllib.error.URLError('offline')):
            with self.assertRaises(urllib.error.URLError): core.manager_update(self.target, self.tag)
        self.unchanged(); self.assertFalse(self.backup.exists())

    def test_asset_digest_manifest_mismatch_and_duplicates_refused(self):
        for mode in ['tamper', 'wrong-manifest', 'duplicate-manifest']:
            with self.subTest(mode=mode):
                self.payload = self.payload.replace(b'generated test', b'generated valid')
                self.manifest = (hashlib.sha256(self.payload).hexdigest()+'  xray-manager.sh\n').encode()
                if mode == 'wrong-manifest': self.manifest = b'0'*64+b'  xray-manager.sh\n'
                if mode == 'duplicate-manifest': self.manifest *= 2
                self.refresh_metadata()
                if mode == 'tamper': self.payload += b'changed'
                with self.assertRaises(ValueError): core.manager_update(self.target, self.tag)
                self.unchanged()
        self.assertFalse(self.backup.exists())

    def test_wrong_asset_url_digest_or_missing_asset_refused(self):
        original = copy.deepcopy(self.metadata)
        for changes in ['url', 'digest', 'missing', 'duplicate']:
            self.metadata = copy.deepcopy(original)
            if changes == 'url': self.metadata['assets'][0]['browser_download_url'] = 'https://example.com/evil'
            if changes == 'digest': self.metadata['assets'][0]['digest'] = ''
            if changes == 'missing': self.metadata['assets'] = self.metadata['assets'][1:]
            if changes == 'duplicate': self.metadata['assets'].append(copy.deepcopy(self.metadata['assets'][0]))
            with self.subTest(changes=changes), self.assertRaises(ValueError): core.manager_update(self.target, self.tag)
            self.unchanged()

    def test_invalid_shell_and_version_selfcheck_refused(self):
        for payload in [core.MANAGER_HEADER+b' test\nif then\n',
                        core.MANAGER_HEADER+b' test\necho WRONG\n']:
            self.payload = payload
            self.manifest = (hashlib.sha256(payload).hexdigest()+'  xray-manager.sh\n').encode()
            self.refresh_metadata()
            with self.subTest(payload=payload), self.assertRaises((ValueError, subprocess.CalledProcessError)):
                core.manager_update(self.target, self.tag)
            self.unchanged()
        self.assertFalse(self.backup.exists())

    def test_failed_post_install_check_restores_previous_script(self):
        check = core.check_manager
        def fail_installed(path, tag):
            if path == self.target: raise ValueError('installed check failed')
            check(path, tag)
        with mock.patch.object(core, 'check_manager', side_effect=fail_installed):
            with self.assertRaises(ValueError): core.manager_update(self.target, self.tag)
        self.unchanged(); self.assertEqual(self.backup.read_bytes(), self.old)

    def test_backup_write_failure_does_not_replace_target(self):
        write = core.write_private
        def fail_backup(path, data, mode=0o600):
            if path == self.backup: raise PermissionError('backup denied')
            return write(path, data, mode)
        with mock.patch.object(core, 'write_private', side_effect=fail_backup):
            with self.assertRaises(PermissionError): core.manager_update(self.target, self.tag)
        self.unchanged()

    def test_foreign_backup_target_and_symlink_refused(self):
        self.backup.write_text('foreign backup')
        with self.assertRaises(ValueError): core.manager_update(self.target, self.tag)
        self.assertEqual(self.backup.read_text(), 'foreign backup')
        self.backup.unlink(); self.target.unlink()
        outside = self.base/'outside'; outside.write_bytes(self.old)
        self.target.symlink_to(outside)
        with self.assertRaises(ValueError): core.manager_update(self.target, self.tag)
        self.assertEqual(outside.read_bytes(), self.old)
        self.assertFalse(self.urls)

    def test_numeric_version_order_and_invalid_versions(self):
        self.assertGreater(core.manager_version('v0.1.10'), core.manager_version('v0.1.9'))
        for tag in ['latest', 'v1.2', 'v1.2.3-rc1', 'v1.2.3\n', '$(id)', None]:
            with self.subTest(tag=tag), self.assertRaises(ValueError): core.manager_version(tag)


class UpdateMenuTests(TemporaryFixture):
    def shell(self, inputs, latest='v0.1.4', fail=False, language='zh', menu=False):
        log = self.base/'commands'
        script = '''source "$1"
helper(){
 printf '%s\\n' "$*" >> "$UPDATE_LOG"
 case $1 in manager-latest) printf '%s' "$LATEST";; manager-update) [[ $UPDATE_FAIL == no ]];; esac
}
LANGUAGE="$2"
'''+ ('main_menu' if menu else 'update_manager')
        result = subprocess.run(['bash', '-c', script, 'test', str(PROJECT/'xray-manager.sh'), language],
            input=inputs, capture_output=True, text=True, env={**os.environ, 'UPDATE_LOG':str(log),
            'LATEST':latest, 'UPDATE_FAIL':'yes' if fail else 'no', 'SKYBYTE_XRAY_LIB':str(self.base/'lib')})
        calls = log.read_text().splitlines() if log.exists() else []
        if log.exists(): log.unlink()
        return result, calls

    def test_confirmation_and_success_exit_menu_in_both_languages(self):
        for language in ['zh', 'en']:
            result, calls = self.shell('13\nYES\n', language=language, menu=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(calls), 2)
            self.assertIn('manager-update --release v0.1.4 --file', calls[1])

    def test_cancel_or_latest_does_not_update(self):
        for inputs, latest in [('no\n', 'v0.1.4'), ('', '')]:
            result, calls = self.shell(inputs, latest=latest)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertEqual(calls, ['manager-latest'])

    def test_failed_update_keeps_menu_usable(self):
        result, calls = self.shell('13\nYES\n0\n', fail=True, menu=True, language='en')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Manager update did not complete', result.stderr + result.stdout)
        self.assertEqual(len(calls), 2)
