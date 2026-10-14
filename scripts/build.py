#!/usr/bin/env python3
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
"""Build the reviewable, self-contained Bash distribution."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
shell = (ROOT / 'src/manager.sh').read_text()
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
