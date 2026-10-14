#!/usr/bin/env bash
# SKYBYTE Xray Manager standalone; generated from src/manager.sh and src/core.py.
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
set -Eeuo pipefail
umask 077
VERSION=0.1.0
CORE_VERSION=v26.3.27
SKYBYTE_XRAY_DIR=${SKYBYTE_XRAY_DIR:-/etc/skybyte-xray}
SKYBYTE_XRAY_LIB=${SKYBYTE_XRAY_LIB:-/usr/local/lib/skybyte-xray}
SKYBYTE_XRAY_BINARY=${SKYBYTE_XRAY_BINARY:-$SKYBYTE_XRAY_LIB/xray}
SKYBYTE_XRAY_UNIT=${SKYBYTE_XRAY_UNIT:-/etc/systemd/system/skybyte-xray.service}
SKYBYTE_XRAY_LOCK=${SKYBYTE_XRAY_LOCK:-/run/skybyte-xray.lock}
export SKYBYTE_XRAY_DIR SKYBYTE_XRAY_BINARY SKYBYTE_XRAY_UNIT
LANGUAGE=zh
GREEN='' YELLOW='' RED='' CYAN='' RESET=''
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
 GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'; CYAN=$'\033[1;36m'; RESET=$'\033[0m'
fi
say(){ if [[ $LANGUAGE == en ]]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }
menu(){ printf '%s' "$GREEN"; if [[ $LANGUAGE == en ]]; then printf '%b\n' "$2"; else printf '%b\n' "$1"; fi; printf '%s' "$RESET"; }
warn(){ printf '%s' "$YELLOW"; say "$1" "$2"; printf '%s' "$RESET"; }
error(){ printf '%s' "$RED" >&2; say "$1" "$2" >&2; printf '%s' "$RESET" >&2; }
ask(){
 local result
 printf '%s' "$GREEN" >&2
 if [[ $LANGUAGE == en ]]; then printf '%s' "$2" >&2; else printf '%s' "$1" >&2; fi
 printf '%s' "$RESET" >&2
 IFS= read -r result || return 1
 printf '%s' "$result"
}
confirmed(){ [[ $1 =~ ^[Yy][Ee][Ss]$ ]]; }
confirm(){ local answer; answer=$(ask "$1 [YES]: " "$2 [YES]: ") || return 1; confirmed "$answer"; }
separator(){ printf '%s\n' '------------------------------------------------------------'; }

# BUILD_HELPER

environment_check(){
 (( EUID == 0 )) || { error '请以 root 账户运行。' 'Run as root.'; return 1; }
 [[ $(uname -s) == Linux && -d /run/systemd/system ]] || { error '需要 Linux 和 systemd。' 'Linux with systemd is required.'; return 1; }
 [[ -r /etc/os-release ]] || return 1
 local os_id
 os_id=$(awk -F= '$1=="ID" {gsub(/"/,"",$2);print $2}' /etc/os-release)
 [[ $os_id == ubuntu || $os_id == debian ]] || { error '仅支持 Ubuntu/Debian。' 'Ubuntu/Debian only.'; return 1; }
}
apt_refresh(){
 if ! apt-get -o APT::Update::Error-Mode=any update; then
  error 'APT 索引更新失败，请先修复软件源，再重试。' 'APT index refresh failed; fix repository errors before retrying.'
  return 1
 fi
}
dependencies(){
 local tool missing=0
 for tool in python3 openssl curl flock; do command -v "$tool" >/dev/null || missing=1; done
 if (( missing )); then
  confirm '安装缺少的系统依赖？' 'Install missing system dependencies?' || return 1
  apt_refresh && apt-get install -y python3 openssl curl ca-certificates util-linux || return 1
 fi
}
acquire_lock(){
 [[ ! -L $SKYBYTE_XRAY_LOCK && ( ! -e $SKYBYTE_XRAY_LOCK || -f $SKYBYTE_XRAY_LOCK ) ]] || return 1
 exec 9>"$SKYBYTE_XRAY_LOCK"
 flock -n 9 || { error '已有管理任务正在运行。' 'Another management task is running.'; return 1; }
}
choose_language(){
 local result
 menu '=========== Language / 语言 ===========\n1. 简体中文\n2. English' '=========== Language / 语言 ===========\n1. 简体中文\n2. English'
 result=$(ask '> ' '> ') || return 1
 case $result in 1) LANGUAGE=zh;; 2) LANGUAGE=en;; *) return 1;; esac
 if [[ -f $SKYBYTE_XRAY_DIR/.owner ]]; then
  helper guard || return 1
  [[ ! -L $SKYBYTE_XRAY_DIR/language ]] || return 1
  printf '%s\n' "$LANGUAGE" > "$SKYBYTE_XRAY_DIR/language"
 fi
}
load_language(){
 local stored=''
 if [[ -f $SKYBYTE_XRAY_DIR/language && ! -L $SKYBYTE_XRAY_DIR/language ]]; then
  IFS= read -r stored < "$SKYBYTE_XRAY_DIR/language" || true
 fi
 case $stored in zh|en) LANGUAGE=$stored;; *) choose_language;; esac
}
lib_guard(){
 python3 - "$SKYBYTE_XRAY_LIB" "$SKYBYTE_XRAY_BINARY" <<'PY'
import os,sys
from pathlib import Path
p,binary=map(Path,sys.argv[1:])
for item in (p,binary,*p.parents):
 if item.is_symlink(): raise SystemExit('Unsafe binary path / 核心路径异常')
if not p.is_absolute() or binary.parent != p or binary.name != 'xray': raise SystemExit('Invalid binary directory')
marker=p/'.owner'
if marker.is_symlink(): raise SystemExit('Unsafe owner marker')
if p.exists() and (not p.is_dir() or not marker.is_file() or marker.read_text()!='SKYBYTE-XRAY/1\n'):
 raise SystemExit('Existing directory not owned / 拒绝覆盖已有核心目录')
p.mkdir(parents=True,exist_ok=True,mode=0o700)
os.chmod(p,0o700)
if not marker.exists(): marker.write_text('SKYBYTE-XRAY/1\n');os.chmod(marker,0o600)
PY
}
core_asset(){
 case $(uname -m) in x86_64|amd64) printf 'Xray-linux-64.zip';; aarch64|arm64) printf 'Xray-linux-arm64-v8a.zip';;
 *) error '首版支持 amd64 / arm64。' 'This version supports amd64 / arm64.'; return 1;; esac
}
ensure_binary(){
 helper guard && lib_guard || return 1
 if [[ ! -x $SKYBYTE_XRAY_BINARY ]]; then
  local candidate asset
  asset=$(core_asset) || return 1
  candidate=$(mktemp "$SKYBYTE_XRAY_LIB/.download.XXXXXX") || return 1
  say '正在下载并校验官方 Xray 核心……' 'Downloading and verifying official Xray-core…'
  if ! helper download --file "$candidate" --asset "$asset" --tag "$CORE_VERSION"; then rm -f -- "$candidate"; return 1; fi
  if ! "$candidate" version >/dev/null; then rm -f -- "$candidate"; return 1; fi
  mv -f -- "$candidate" "$SKYBYTE_XRAY_BINARY" || return 1
 fi
 [[ ! -L $SKYBYTE_XRAY_DIR/language ]] || return 1
 printf '%s\n' "$LANGUAGE" > "$SKYBYTE_XRAY_DIR/language"
}
restore_service(){
 local active=$1 enabled=$2
 systemctl daemon-reload || return 1
 if [[ $enabled == yes ]]; then systemctl enable skybyte-xray.service >/dev/null 2>&1 || return 1
 else systemctl disable skybyte-xray.service >/dev/null 2>&1 || true; fi
 if [[ $active == yes ]]; then systemctl restart skybyte-xray.service || return 1
 else systemctl stop skybyte-xray.service >/dev/null 2>&1 || true; fi
}
recover(){
 if [[ -d $SKYBYTE_XRAY_DIR/.transaction ]]; then
  local flags active enabled
  warn '恢复未完成的配置事务。' 'Recovering an interrupted configuration transaction.'
  flags=$(helper journal | python3 -c 'import json,sys;x=json.load(sys.stdin);print("yes" if x["active"] else "no", "yes" if x["enabled"] else "no")') || return 1
  read -r active enabled <<< "$flags"
  helper rollback >/dev/null && restore_service "$active" "$enabled" || return 1
 fi
 if [[ -f $SKYBYTE_XRAY_LIB/.old-core ]]; then
  lib_guard || return 1
  [[ ! -L $SKYBYTE_XRAY_LIB/.old-core && ! -L $SKYBYTE_XRAY_LIB/.update-active ]] || return 1
  local previous=no
  if [[ -f $SKYBYTE_XRAY_LIB/.update-active ]]; then IFS= read -r previous < "$SKYBYTE_XRAY_LIB/.update-active" || true; fi
  mv -f -- "$SKYBYTE_XRAY_LIB/.old-core" "$SKYBYTE_XRAY_BINARY" || return 1
  rm -f -- "$SKYBYTE_XRAY_LIB/.update-active"
  [[ $previous != yes ]] || systemctl restart skybyte-xray.service || return 1
 fi
}
apply_stage() (
 local stage=$1 activate=${2:-no} was_active=no was_enabled=no applied=0 accepted=0
 local flags=(--stage "$stage")
 systemctl is-active --quiet skybyte-xray.service && was_active=yes
 systemctl is-enabled --quiet skybyte-xray.service && was_enabled=yes
 [[ $was_active != yes ]] || flags+=(--active)
 [[ $was_enabled != yes ]] || flags+=(--enabled)
 # shellcheck disable=SC2317,SC2329 # EXIT trap invocation is indirect; rollback tests exercise this function.
 cleanup_stage(){
  local status=$?
  if (( applied && ! accepted )); then
   if helper rollback >/dev/null; then restore_service "$was_active" "$was_enabled" || true
   else error '回退失败，已保留恢复事务，请勿手动删除。' 'Rollback failed; recovery journal retained.'; fi
  fi
  if [[ $stage == "$SKYBYTE_XRAY_DIR"/.stage-* && -d $stage && ! -L $stage ]]; then rm -rf -- "$stage"; fi
  return "$status"
 }
 trap cleanup_stage EXIT
 helper commit "${flags[@]}" || return 1
 applied=1
 systemctl daemon-reload || return 1
 local node_count
 node_count=$(python3 - "$SKYBYTE_XRAY_DIR/state.json" <<'PY'
import json,sys
with open(sys.argv[1]) as f: print(len(json.load(f)['nodes']))
PY
) || return 1
 if [[ $node_count == 0 ]]; then
  systemctl stop skybyte-xray.service && systemctl disable skybyte-xray.service >/dev/null 2>&1 || return 1
 elif [[ $activate == yes ]]; then
  systemctl enable skybyte-xray.service >/dev/null 2>&1 && systemctl restart skybyte-xray.service || return 1
 elif [[ $was_active == yes ]]; then systemctl restart skybyte-xray.service || return 1; fi
 if [[ $node_count != 0 && ( $activate == yes || $was_active == yes ) ]]; then
  local attempt running=0
  for ((attempt=0; attempt<5; attempt++)); do
   sleep 1
   if systemctl is-active --quiet skybyte-xray.service; then running=1; break; fi
  done
  (( running )) || return 1
 fi
 helper finalize --stage "$stage" || return 1
 accepted=1
)
install_node(){
 local choice kind node_name node_port host sni target listen path='' mode=auto cert='' private_key='' stage
 local flags=()
 menu '1. VLESS + Reality + Vision\n2. VLESS + XHTTP + Reality\n3. VLESS + XHTTP + TLS / CDN\n0. 返回' '1. VLESS + Reality + Vision\n2. VLESS + XHTTP + Reality\n3. VLESS + XHTTP + TLS / CDN\n0. Back'
 choice=$(ask '> ' '> ') || return 1
 case $choice in 1) kind=vision; node_port=443;; 2) kind=xhttp-reality; node_port=8443;; 3) kind=xhttp-tls; node_port=2053;; 0) return 0;; *) return 1;; esac
 node_name=$(ask '节点名称 [SKYBYTE]：' 'Node name [SKYBYTE]: ') || return 1; node_name=${node_name:-SKYBYTE}-$kind
 node_port=$(ask "监听 TCP 端口 [$node_port]：" "TCP listen port [$node_port]: ") || return 1
 case $kind in vision) node_port=${node_port:-443};; xhttp-reality) node_port=${node_port:-8443};; *) node_port=${node_port:-2053};; esac
 listen=$(ask '监听：1 IPv4  2 IPv6 [1]：' 'Listen: 1 IPv4  2 IPv6 [1]: ') || return 1
 case ${listen:-1} in 1) listen=0.0.0.0;; 2) listen=::;; *) return 1;; esac
 host=$(ask '客户端连接地址（公网 IP 或域名）：' 'Client connection address (public IP/domain): ') || return 1
 if [[ $kind == xhttp-tls ]]; then
  sni=$(ask '证书域名 / TLS SNI：' 'Certificate domain / TLS SNI: ') || return 1
  cert=$(ask '已有可信 fullchain 证书文件绝对路径：' 'Absolute path to trusted fullchain certificate: ') || return 1
  private_key=$(ask '私钥文件绝对路径（不修改源文件）：' 'Absolute private-key path (source is preserved): ') || return 1
  local cdn
  cdn=$(ask '通过 CDN 连接？输入 YES 开启，回车直连：' 'Use a CDN? YES to enable; Enter for direct: ') || return 1
  if confirmed "$cdn"; then flags+=(--cdn); mode=packet-up; fi
  warn 'CDN 的 DNS、HTTPS 端口及回源 TLS 验证须在提供商后台配置。' 'Configure CDN DNS, supported HTTPS port and verified origin TLS at your provider.'
 else
  sni=$(ask 'Reality 握手域名 [www.microsoft.com]：' 'Reality handshake name [www.microsoft.com]: ') || return 1; sni=${sni:-www.microsoft.com}
  target=$(ask "握手目标 [$sni:443]：" "Handshake target [$sni:443]: ") || return 1; target=${target:-$sni:443}
  say '检查目标 TLS 1.3 与 HTTP/2……' 'Checking target TLS 1.3 and HTTP/2…'
  helper probe --target "$target" --sni "$sni" || return 1
 fi
 if [[ $kind == xhttp-* ]]; then
  path=$(ask 'XHTTP 路径（回车自动生成）：' 'XHTTP path (Enter to generate): ') || return 1
  local selected
  selected=$(ask "模式 [$mode]（auto / packet-up / stream-up / stream-one）：" "Mode [$mode] (auto / packet-up / stream-up / stream-one): ") || return 1
  mode=${selected:-$mode}
 fi
 warn '请放行实际 TCP 端口；配置检查不等于公网或 CDN 已连通。' 'Allow the actual TCP port; validation does not prove public/CDN connectivity.'
 confirm '安装并启动所选节点？' 'Install and start the selected node?' || return 1
 ensure_binary || return 1
 flags+=(--kind "$kind" --port "$node_port" --listen "$listen" --address "$host" --sni "$sni" --name "$node_name")
 if [[ $kind == xhttp-tls ]]; then flags+=(--cert "$cert" --key "$private_key")
 else flags+=(--target "$target"); fi
 [[ $kind != xhttp-* ]] || flags+=(--path "$path" --mode "$mode")
 stage=$(helper prepare "${flags[@]}") || return 1
 apply_stage "$stage" yes || { error '安装失败，原配置已保留或回退。' 'Install failed; previous configuration retained or restored.'; return 1; }
 show_nodes
}
show_nodes(){
 [[ -f $SKYBYTE_XRAY_DIR/state.json ]] || { warn '尚未安装节点。' 'No nodes installed.'; return 0; }
 local line index=0
 warn '节点链接包含凭据，请勿公开。' 'Node links contain credentials; keep them private.'
 while IFS= read -r line; do
  if (( index % 2 == 0 )); then separator; printf '%s%s%s\n' "$YELLOW" "$line" "$RESET"
  else printf '%s%s%s\n' "$RED" "$line" "$RESET"; fi
  index=$((index + 1))
 done < <(helper show)
 separator
 warn "文件：$SKYBYTE_XRAY_DIR/nodes.txt、subscription-base64.txt、client-*.json" "Files: $SKYBYTE_XRAY_DIR/nodes.txt, subscription-base64.txt, client-*.json"
}
qr_nodes(){
 helper guard || return 1
 if ! command -v qrencode >/dev/null; then
  confirm '安装本地二维码工具？' 'Install local QR utility?' || return 1
  apt_refresh && apt-get install -y qrencode || return 1
 fi
 local uri
 while IFS= read -r uri; do [[ -z $uri ]] || { separator; printf '%s' "$uri" | qrencode -t ANSIUTF8; }; done < "$SKYBYTE_XRAY_DIR/nodes.txt"
 warn 'XHTTP 扫码需要客户端本身支持 XHTTP；二维码不改变兼容性。' 'XHTTP QR import requires an XHTTP-capable client.'
}
choose_kind(){
 menu '1 Vision  2 XHTTP-Reality  3 XHTTP-TLS  0 返回' '1 Vision  2 XHTTP-Reality  3 XHTTP-TLS  0 Back' >&2
 local choice
 choice=$(ask '> ' '> ') || return 1
 case $choice in 1) printf 'vision';; 2) printf 'xhttp-reality';; 3) printf 'xhttp-tls';; *) return 1;; esac
}
edit_nodes(){
 local choice kind value stage cert private_key
 menu '1 重命名  2 删除协议  3 更新 TLS 证书  0 返回' '1 Rename  2 Remove protocol  3 Refresh TLS certificate  0 Back'
 choice=$(ask '> ' '> ') || return 1
 [[ $choice != 0 ]] || return 0
 kind=$(choose_kind) || return 1
 case $choice in
  1) value=$(ask '新的节点名称：' 'New node name: ') || return 1; stage=$(helper rename --kind "$kind" --name "$value") || return 1;;
  2) confirm '删除该协议？重新安装会生成新凭据。' 'Remove protocol? Reinstallation generates new credentials.' || return 1
     stage=$(helper remove --kind "$kind") || return 1;;
  3) [[ $kind == xhttp-tls ]] || return 1
     cert=$(ask '新的 fullchain 证书绝对路径：' 'New fullchain certificate absolute path: ') || return 1
     private_key=$(ask '匹配的私钥绝对路径：' 'Matching private-key absolute path: ') || return 1
     stage=$(helper refresh-tls --kind "$kind" --cert "$cert" --key "$private_key") || return 1;;
  *) return 1;;
 esac
 apply_stage "$stage" || return 1
}
service_menu(){
 helper guard || return 1
 menu '1 状态  2 启动  3 停止  4 重启  5 配置检查  6 日志  0 返回' '1 Status  2 Start  3 Stop  4 Restart  5 Validate  6 Logs  0 Back'
 local choice
 choice=$(ask '> ' '> ') || return 1
 case $choice in
  1) systemctl status skybyte-xray.service --no-pager || true;;
  2) systemctl start skybyte-xray.service;; 3) systemctl stop skybyte-xray.service;; 4) systemctl restart skybyte-xray.service;;
  5) "$SKYBYTE_XRAY_BINARY" run -test -config "$SKYBYTE_XRAY_DIR/config.json";;
  6) journalctl -u skybyte-xray.service -n 60 --no-pager;; 0) return 0;; *) return 1;;
 esac
}
make_backup(){
 local destination
 destination="$SKYBYTE_XRAY_DIR/backups/backup-$(date +%Y%m%d-%H%M%S)-$RANDOM.tar.gz"
 helper backup --file "$destination" || return 1
 warn "备份含凭据与私钥：$destination" "Backup contains credentials and private keys: $destination"
}
restore_backup(){
 local archive stage
 archive=$(ask '可信备份文件的绝对路径：' 'Absolute path to your trusted backup: ') || return 1
 confirm '恢复配置？现有托管节点将替换为备份，外部文件保留。' 'Restore? Managed nodes will be replaced; external files preserved.' || return 1
 ensure_binary || return 1
 [[ ! -f $SKYBYTE_XRAY_DIR/state.json ]] || make_backup || return 1
 stage=$(helper restore --file "$archive") || return 1
 apply_stage "$stage" || return 1
}
update_core() (
 ensure_binary || return 1
 local tag candidate asset active=no accepted=0 replaced=0
 tag=$(ask "官方稳定版本 [$CORE_VERSION]：" "Official stable version [$CORE_VERSION]: ") || return 1; tag=${tag:-$CORE_VERSION}
 confirm '校验并更新核心？运行中的节点会短暂重启。' 'Verify and update core? Active nodes will briefly restart.' || return 1
 [[ ! -e $SKYBYTE_XRAY_LIB/.old-core && ! -e $SKYBYTE_XRAY_LIB/.update-active ]] || return 1
 candidate=$(mktemp "$SKYBYTE_XRAY_LIB/.update.XXXXXX") || return 1
 # shellcheck disable=SC2317,SC2329 # EXIT trap invocation is indirect; rollback tests exercise this function.
 update_cleanup(){
  local status=$?
  if (( ! accepted && replaced )); then
   mv -f -- "$SKYBYTE_XRAY_LIB/.old-core" "$SKYBYTE_XRAY_BINARY" || return 1
   [[ $active != yes ]] || systemctl restart skybyte-xray.service || true
  fi
  rm -f -- "$candidate"
  [[ -e $SKYBYTE_XRAY_LIB/.old-core ]] || rm -f -- "$SKYBYTE_XRAY_LIB/.update-active"
  return "$status"
 }
 trap update_cleanup EXIT
 asset=$(core_asset) || return 1
 helper download --asset "$asset" --tag "$tag" --file "$candidate" || return 1
 [[ ! -f $SKYBYTE_XRAY_DIR/config.json ]] || "$candidate" run -test -config "$SKYBYTE_XRAY_DIR/config.json" >/dev/null 2>&1 || return 1
 systemctl is-active --quiet skybyte-xray.service && active=yes
 cp -p -- "$SKYBYTE_XRAY_BINARY" "$SKYBYTE_XRAY_LIB/.old-core" || return 1
 printf '%s\n' "$active" > "$SKYBYTE_XRAY_LIB/.update-active"
 mv -f -- "$candidate" "$SKYBYTE_XRAY_BINARY" || return 1
 replaced=1
 if [[ $active == yes ]]; then
  systemctl restart skybyte-xray.service || return 1
  sleep 2
  systemctl is-active --quiet skybyte-xray.service || return 1
 fi
 rm -f -- "$SKYBYTE_XRAY_LIB/.old-core" "$SKYBYTE_XRAY_LIB/.update-active"
 accepted=1
)
uninstall(){
 helper guard && lib_guard || return 1
 confirm '备份后卸载 SKYBYTE Xray Manager？' 'Back up and uninstall SKYBYTE Xray Manager?' || return 1
 make_backup || return 1
 systemctl stop skybyte-xray.service && systemctl disable skybyte-xray.service || return 1
 python3 - "$SKYBYTE_XRAY_DIR" "$SKYBYTE_XRAY_UNIT" "$SKYBYTE_XRAY_LIB" <<'PY'
import json,sys
from pathlib import Path
root,unit,lib=map(Path,sys.argv[1:])
state=json.loads((root/'state.json').read_text())
paths=[root/x for x in ['state.json','config.json','nodes.txt','subscription-base64.txt','language']]
for kind,node in state['nodes'].items():
 paths.append(root/('client-'+kind+'.json'))
 if kind=='xhttp-tls': paths.extend([root/node['cert'],root/node['key']])
paths.extend([unit,lib/'xray'])
if any(p.is_symlink() or (p.exists() and not p.is_file()) for p in paths): raise SystemExit('Unsafe managed file')
if unit.exists() and not unit.read_text().startswith('# SKYBYTE Xray Manager unit v1\n'): raise SystemExit('Unknown service')
manager=lib/'manager.sh'
if manager.exists():
 if manager.is_symlink() or not manager.read_text().startswith('#!/usr/bin/env bash\n# SKYBYTE Xray Manager standalone;'): raise SystemExit('Unknown manager')
 paths.append(manager)
for p in paths:
 if p.exists(): p.unlink()
PY
 systemctl daemon-reload || return 1
 warn '已卸载。备份、未知文件、系统依赖及防火墙规则保留。' 'Removed. Backups, unknown files, dependencies and firewall rules retained.'
 exit 0
}
guide(){
 say 'Copyright © 2026 SKYBYTE (skylink9119)。GPLv3，无担保；可按许可证修改和再分发。' 'Copyright © 2026 SKYBYTE (skylink9119). GPLv3, no warranty; modification and redistribution permitted under the license.'
 say '完整许可证：https://github.com/skylink9119/skybyte-xray-manager/blob/development/LICENSE' 'Full license: https://github.com/skylink9119/skybyte-xray-manager/blob/development/LICENSE'
 say 'Reality/Vision 和 XHTTP-Reality 使用不同 TCP 端口；XHTTP-TLS 需要已有可信域名证书。' 'Vision and XHTTP-Reality use separate TCP ports; XHTTP-TLS needs an existing trusted domain certificate.'
 say 'CDN 模式需设置 DNS、可代理 HTTPS 端口及严格的回源证书验证；不替你配置 CDN。' 'For CDN, configure DNS, a supported HTTPS port and strict origin verification; CDN setup is manual.'
 say '客户端必须支持对应传输。节点文件是本地导出，不是在线订阅 URL。' 'Clients must support the transport. Exports are local files, not online subscription URLs.'
 say '证书为私密副本，外部续期后用“更新 TLS 证书”刷新；不自动签发或续期。' 'Certificates are private copies. After external renewal use Refresh TLS certificate; issuance/renewal is not automatic.'
}
main_menu(){
 while :; do
  printf '%s\n' '============================================================'
  printf '%sSKYBYTE Xray Manager v%s%s\n' "$CYAN" "$VERSION" "$RESET"
  printf '%sYouTube: https://www.youtube.com/@SKYBYTE9119%s\n' "$CYAN" "$RESET"
  say '觉得脚本好用，欢迎订阅我的 YouTube 频道，支持后续维护。' 'If this script helps, subscribe to my YouTube channel to support maintenance.'
  menu '1. 安装 / 添加节点\n2. 查看节点与客户端配置\n3. 节点二维码\n4. 服务与日志\n5. 节点名称 / 删除 / TLS 证书\n6. 更新 Xray 核心\n7. 备份配置\n8. 恢复配置\n9. 使用说明\n10. 切换语言\n11. 卸载\n0. 退出' '1. Install / add nodes\n2. Nodes and client configs\n3. Node QR codes\n4. Service and logs\n5. Rename / remove / TLS certificate\n6. Update Xray-core\n7. Back up configuration\n8. Restore configuration\n9. Guide\n10. Language\n11. Uninstall\n0. Exit'
  local choice
  choice=$(ask '请选择：' 'Choose: ') || return 0
  case $choice in
   1) install_node || error '操作未完成，请检查输入、网络或端口。' 'Operation did not complete; check input, network or ports.';;
   2) show_nodes;; 3) qr_nodes || true;; 4) service_menu || true;; 5) edit_nodes || true;;
   6) update_core || error '核心更新失败，已保留或回退原核心。' 'Core update failed; previous core retained or restored.';;
   7) make_backup || true;; 8) restore_backup || error '恢复失败，原配置已保留或回退。' 'Restore failed; previous configuration retained or restored.';;
   9) guide;; 10) choose_language || true;; 11) uninstall || error '卸载未完成。' 'Uninstall did not complete.';; 0) return 0;;
   *) warn '选项无效。' 'Invalid option.';;
  esac
 done
}
main(){
 case ${1:-} in --version) printf 'SKYBYTE Xray Manager %s\n' "$VERSION"; return 0;; --self-check) helper selfcheck; return;;
 --help) printf 'bash xray-manager.sh [--version|--self-check|--help]\n'; return;; '') :;; *) return 1;; esac
 environment_check && dependencies && acquire_lock || return 1
 recover && load_language && main_menu
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
