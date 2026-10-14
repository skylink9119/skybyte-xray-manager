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
files=['install.sh','xray-manager.sh','README.md','README_EN.md','CHANGELOG.md','LICENSE','.gitignore',
       'src/manager.sh','src/core.py','scripts/build.py','scripts/package.py',
       'tests/test_manager.py','tests/test_services.py','.github/workflows/test.yml']
folder=root/'dist';folder.mkdir(exist_ok=True)
output=folder/'SKYBYTE-Xray-Manager-v0.1.0-test.tar.gz'
with tarfile.open(output,'w:gz') as archive:
    for relative in files:
        archive.add(root/relative,arcname='skybyte-xray-manager-v0.1.0/'+relative,recursive=False)
checksum=hashlib.sha256(output.read_bytes()).hexdigest()
(folder/'SHA256SUMS').write_text(checksum+'  '+output.name+'\n')
print(str(output))
