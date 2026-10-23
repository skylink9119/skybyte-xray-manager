#!/usr/bin/env python3
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
"""Build the reviewable, self-contained Bash distribution."""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
shell = (ROOT / 'src/manager.sh').read_text()
assert shell.count('# BUILD_MEDIA') == 1
media = (ROOT / 'src/media.py').read_text()
compile(media, 'src/media.py', 'exec')
shell = shell.replace('# BUILD_MEDIA', media.split("\nif __name__=='__main__':", 1)[0])
python = (ROOT / 'src/core.py').read_text()
compile(python, 'src/core.py', 'exec')
helper = "helper(){ python3 - \"$@\" <<'SKYBYTE_PYTHON'\n" + python + "\nSKYBYTE_PYTHON\n}\n"
assert shell.count('# BUILD_HELPER') == 1
output = shell.replace('# BUILD_HELPER', helper)
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
target = ROOT / 'xray-manager.sh'
if args.check:
    if not target.is_file() or target.read_text() != output:
        raise SystemExit('Generated script is stale')
else:
    target.write_text(output)
    target.chmod(0o755)

versions=re.findall(r'^RELEASE_VERSION=([0-9]+\.[0-9]+\.[0-9]+)$',(ROOT/'install.sh').read_text(),re.M)
if len(versions)!=1: raise SystemExit('Installer release version unknown')
install_url=f'https://github.com/skylink9119/skybyte-xray-manager/releases/download/v{versions[0]}/install.sh'
bootstrap=(ROOT/'src/bootstrap.sh').read_text().replace('@INSTALL_URL@',install_url)
target=ROOT/'bootstrap.sh'
if args.check:
    if not target.is_file() or target.read_text()!=bootstrap: raise SystemExit('Generated bootstrap is stale')
else:
    target.write_text(bootstrap);target.chmod(0o755)

quickstart='\n'.join(line for line in (ROOT/'src/quickstart.sh').read_text().splitlines() if line and not line.startswith('#'))+'\n'
start='<!-- SKYBYTE_INSTALL_COMMAND_START -->'
end='<!-- SKYBYTE_INSTALL_COMMAND_END -->'
command=start+'\n```bash\n'+quickstart+'```\n'+end
for name in ['README.md','README_EN.md']:
    target=ROOT/name;original=target.read_text()
    if original.count(start)!=1 or original.count(end)!=1: raise SystemExit(name+' installation markers missing')
    result=re.sub(re.escape(start)+r'.*?'+re.escape(end),lambda match:command,original,flags=re.S)
    if args.check:
        if result!=original: raise SystemExit(name+' installation command is stale')
    else: target.write_text(result)
