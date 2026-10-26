#!/usr/bin/env python3
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
"""Package source/installer only; never include runtime credentials or binaries."""
import hashlib
from pathlib import Path
import subprocess
import tarfile

root=Path(__file__).resolve().parents[1]
subprocess.run(['python3',str(root/'scripts/build.py'),'--check'],check=True)
files=['bootstrap.sh','install.sh','xray-manager.sh','README.md','README_EN.md','CHANGELOG.md','LICENSE','.gitignore','docs/REVIEW.md',
       'src/bootstrap.sh','src/quickstart.sh','src/manager.sh','src/core.py','src/media.py','src/reality.py','scripts/build.py','scripts/package.py','scripts/check_firewall_namespace.py',
       'tests/test_bootstrap.py','tests/test_updater.py','tests/test_network.py','tests/test_fail2ban.py','tests/test_manager.py','tests/test_services.py','tests/test_installer.py','tests/test_overview.py','tests/test_warp.py','tests/test_navigation.py','tests/test_reality.py','.github/workflows/test.yml']
folder=root/'dist';folder.mkdir(exist_ok=True)
output=folder/'SKYBYTE-Xray-Manager-v0.1.18.tar.gz'
with tarfile.open(output,'w:gz') as archive:
    for relative in files:
        archive.add(root/relative,arcname='skybyte-xray-manager-v0.1.18/'+relative,recursive=False)
for name in ['bootstrap.sh','install.sh','xray-manager.sh']:
    (folder/name).write_bytes((root/name).read_bytes())
    (folder/name).chmod(0o755)
artifacts=[output,folder/'bootstrap.sh',folder/'install.sh',folder/'xray-manager.sh']
(folder/'SHA256SUMS').write_text(''.join(hashlib.sha256(item.read_bytes()).hexdigest()+'  '+item.name+'\n' for item in artifacts))
print(str(output))
