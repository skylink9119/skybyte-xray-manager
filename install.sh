#!/usr/bin/env bash
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
# Install the local, complete SKYBYTE Xray Manager distribution.
set -Eeuo pipefail
umask 077
(( EUID == 0 )) || { printf 'Please run as root / 请使用 root\n' >&2; exit 1; }
[[ $(uname -s) == Linux && -d /run/systemd/system ]] || { printf 'Ubuntu/Debian with systemd required\n' >&2; exit 1; }
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
SOURCE=$SCRIPT_DIR/xray-manager.sh
TARGET_DIR=/usr/local/lib/skybyte-xray
TARGET=$TARGET_DIR/manager.sh
LOCK=/run/skybyte-xray.lock
[[ -f $SOURCE && ! -L $SOURCE ]] || { printf 'Use the complete release package / 请使用完整发布包\n' >&2; exit 1; }
OS_ID=$(awk -F= '$1=="ID" {gsub(/"/,"",$2);print $2}' /etc/os-release)
[[ $OS_ID == ubuntu || $OS_ID == debian ]] || { printf 'Ubuntu/Debian only\n' >&2; exit 1; }
if ! command -v python3 >/dev/null || ! command -v flock >/dev/null; then
 printf '\033[1;32mInstall python3/util-linux? / 安装基础依赖？[YES]: \033[0m' >&2
 IFS= read -r ANSWER || exit 1
 [[ $ANSWER =~ ^[Yy][Ee][Ss]$ ]] || exit 1
 apt-get -o APT::Update::Error-Mode=any update && apt-get install -y python3 util-linux || exit 1
fi
bash -n "$SOURCE" && bash "$SOURCE" --self-check >/dev/null || exit 1
[[ ! -L $LOCK && ( ! -e $LOCK || -f $LOCK ) ]] || exit 1
exec 9>"$LOCK"
flock -n 9 || { printf 'Another management task is running\n' >&2; exit 1; }
python3 - "$TARGET_DIR" "$TARGET" "$SOURCE" <<'PY'
import os,sys,tempfile
from pathlib import Path
directory,target,source=map(Path,sys.argv[1:])
for p in (directory,target,*directory.parents):
 if p.is_symlink(): raise SystemExit('Unsafe install path')
marker=directory/'.owner'
if marker.is_symlink(): raise SystemExit('Unsafe owner marker')
if directory.exists() and (not directory.is_dir() or not marker.is_file() or marker.read_text()!='SKYBYTE-XRAY/1\n'):
 raise SystemExit('Existing directory not managed by SKYBYTE / 已有目录非本脚本管理')
if target.exists() and (not target.is_file() or not target.read_text().startswith('#!/usr/bin/env bash\n# SKYBYTE Xray Manager standalone;')):
 raise SystemExit('Existing file is not SKYBYTE Manager')
directory.mkdir(parents=True,exist_ok=True,mode=0o700)
os.chmod(directory,0o700)
if not marker.exists(): marker.write_text('SKYBYTE-XRAY/1\n');os.chmod(marker,0o600)
fd,temp=tempfile.mkstemp(prefix='.installer-',dir=directory)
try:
 os.fchmod(fd,0o700)
 with os.fdopen(fd,'wb') as f: f.write(source.read_bytes());f.flush();os.fsync(f.fileno())
 os.replace(temp,target)
finally:
 if os.path.exists(temp): os.unlink(temp)
PY
exec 9>&-
exec bash "$TARGET"
