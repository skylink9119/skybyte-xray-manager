#!/usr/bin/env bash
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
# Install a complete local package, or fetch the pinned, verified release payload.
set -Eeuo pipefail
umask 077
RELEASE_VERSION=0.1.15
RELEASE_URL=https://github.com/skylink9119/skybyte-xray-manager/releases/download/v$RELEASE_VERSION

download_manager(){
 local destination=$1
 curl -fsSL --retry 3 --connect-timeout 10 --max-time 180 "$RELEASE_URL/SHA256SUMS" -o "$destination/SHA256SUMS" || return 1
 curl -fsSL --retry 3 --connect-timeout 10 --max-time 180 "$RELEASE_URL/xray-manager.sh" -o "$destination/xray-manager.sh" || return 1
 python3 - "$destination" <<'PY'
import hashlib,re,sys
from pathlib import Path
folder=Path(sys.argv[1])
expected=[]
for line in (folder/'SHA256SUMS').read_text().splitlines():
    fields=line.split()
    if len(fields)==2 and fields[1]=='xray-manager.sh':
        if not re.fullmatch('[a-f0-9]{64}',fields[0]): raise SystemExit('Invalid SHA256 manifest')
        expected.append(fields[0])
if len(expected)!=1 or hashlib.sha256((folder/'xray-manager.sh').read_bytes()).hexdigest()!=expected[0]:
    raise SystemExit('Manager SHA256 mismatch / 主脚本 SHA256 校验失败')
PY
}

install_payload(){
 python3 - "$1" "$2" "$3" "$RELEASE_VERSION" <<'PY'
import os,re,shlex,sys,tempfile
from pathlib import Path
source,directory,shortcut=map(Path,sys.argv[1:4])
target=directory/'manager.sh'
header='#!/usr/bin/env bash\n# SKYBYTE Xray Manager shortcut v1\n'
for item in (source,directory,target,shortcut,*directory.parents,*shortcut.parents):
    if not item.is_absolute() or item.is_symlink(): raise SystemExit('Unsafe install path')
marker=directory/'.owner'
if marker.is_symlink(): raise SystemExit('Unsafe owner marker')
if directory.exists() and (not directory.is_dir() or not marker.is_file() or marker.read_text()!='SKYBYTE-XRAY/1\n'):
    raise SystemExit('Existing directory not managed by SKYBYTE / 已有目录非本脚本管理')
if target.exists() and (not target.is_file() or not target.read_text().startswith('#!/usr/bin/env bash\n# SKYBYTE Xray Manager standalone;')):
    raise SystemExit('Existing file is not SKYBYTE Manager')
if shortcut.exists() and (not shortcut.is_file() or not shortcut.read_text().startswith(header)):
    raise SystemExit('xr already belongs to another program / xr 已被其他程序占用，原文件已保留')
payload=source.read_bytes()
if not payload.startswith(b'#!/usr/bin/env bash\n# SKYBYTE Xray Manager standalone;'):
    raise SystemExit('Invalid SKYBYTE Manager payload')
def manager_version(data):
    versions=re.findall(rb'^VERSION=([0-9]+\.[0-9]+\.[0-9]+)$',data,re.MULTILINE)
    if len(versions)!=1: raise SystemExit('Manager version unknown / 无法识别管理脚本版本，未覆盖文件')
    return tuple(map(int,versions[0].split(b'.')))
incoming=manager_version(payload)
if incoming!=tuple(map(int,sys.argv[4].split('.'))):
    raise SystemExit('Installer/payload version mismatch / 安装入口与主脚本版本不一致')
if target.exists() and manager_version(target.read_bytes())>incoming:
    raise SystemExit('Manager downgrade refused / 已安装的管理脚本版本较新，拒绝降级；请使用最新安装入口或菜单 13')
directory.mkdir(parents=True,exist_ok=True,mode=0o700)
os.chmod(directory,0o700)
shortcut.parent.mkdir(parents=True,exist_ok=True,mode=0o755)
def atomic(path,data,mode):
    fd,temp=tempfile.mkstemp(prefix='.installer-',dir=path.parent)
    try:
        os.fchmod(fd,mode)
        with os.fdopen(fd,'wb') as stream:
            stream.write(data);stream.flush();os.fsync(stream.fileno())
        os.replace(temp,path)
    finally:
        if os.path.exists(temp): os.unlink(temp)
if not marker.exists(): atomic(marker,b'SKYBYTE-XRAY/1\n',0o600)
atomic(target,payload,0o700)
atomic(shortcut,(header+'exec bash '+shlex.quote(str(target))+' "$@"\n').encode(),0o755)
PY
}

confirm_dependencies(){
 local answer
 printf '\033[1;32mInstall base dependencies? / 安装基础依赖？[y/N]: \033[0m' >&2
 IFS= read -r answer || return 1
 [[ $answer =~ ^[[:space:]]*[Yy][[:space:]]*$ ]]
}

install_main() (
 (( EUID == 0 )) || { printf 'Please run as root / 请使用 root\n' >&2; return 1; }
 [[ $(uname -s) == Linux && -d /run/systemd/system ]] || { printf 'Ubuntu/Debian with systemd required\n' >&2; return 1; }
 local os_id script_dir source staging='' tool missing=0
 os_id=$(awk -F= '$1=="ID" {gsub(/"/,"",$2);print $2}' /etc/os-release)
 [[ $os_id == ubuntu || $os_id == debian ]] || { printf 'Ubuntu/Debian only\n' >&2; return 1; }
 script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || return 1
 source=$script_dir/xray-manager.sh
 for tool in python3 flock curl; do command -v "$tool" >/dev/null || missing=1; done
 [[ -s /etc/ssl/certs/ca-certificates.crt ]] || missing=1
 if (( missing )); then
  confirm_dependencies || return 1
  apt-get -o APT::Update::Error-Mode=any update && apt-get install -y python3 util-linux curl ca-certificates || return 1
 fi
 # shellcheck disable=SC2317,SC2329 # Cleanup is invoked by EXIT, including after a download failure.
 cleanup_installer(){ [[ -z $staging ]] || rm -rf -- "$staging"; }
 trap cleanup_installer EXIT
 if [[ ! -e $source && ! -L $source ]]; then
  staging=$(mktemp -d) || return 1
  staging=$(cd -- "$staging" && pwd -P) || return 1
  printf 'Downloading verified SKYBYTE Xray Manager / 下载并校验主脚本……\n'
  download_manager "$staging" || return 1
  source=$staging/xray-manager.sh
 fi
 [[ -f $source && ! -L $source ]] || return 1
 bash -n "$source" && bash "$source" --self-check >/dev/null || return 1
 local lock=/run/skybyte-xray.lock target_dir=/usr/local/lib/skybyte-xray
 [[ ! -L $lock && ( ! -e $lock || -f $lock ) ]] || return 1
 exec 9>"$lock"
 flock -n 9 || { printf 'Another management task is running\n' >&2; return 1; }
 install_payload "$source" "$target_dir" /usr/local/bin/xr || return 1
 exec 9>&-
 cleanup_installer
 staging=''
 printf '\033[1;32mInstalled. Reopen with xr / 安装完成，以后输入 xr 打开菜单。\033[0m\n'
 exec bash "$target_dir/manager.sh"
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then install_main "$@"; fi
