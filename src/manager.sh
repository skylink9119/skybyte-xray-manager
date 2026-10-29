#!/usr/bin/env bash
# SKYBYTE Xray Manager standalone; generated from src/manager.sh and src/core.py.
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
set -Eeuo pipefail
umask 077
VERSION=0.1.28
CORE_VERSION=v26.10.29
SKYBYTE_XRAY_DIR=${SKYBYTE_XRAY_DIR:-/etc/skybyte-xray}
SKYBYTE_XRAY_LIB=${SKYBYTE_XRAY_LIB:-/usr/local/lib/skybyte-xray}
SKYBYTE_XRAY_BINARY=${SKYBYTE_XRAY_BINARY:-$SKYBYTE_XRAY_LIB/xray}
SKYBYTE_XRAY_UNIT=${SKYBYTE_XRAY_UNIT:-/etc/systemd/system/skybyte-xray.service}
SKYBYTE_XRAY_LOCK=${SKYBYTE_XRAY_LOCK:-/run/skybyte-xray.lock}
SKYBYTE_XRAY_SHORTCUT=${SKYBYTE_XRAY_SHORTCUT:-/usr/local/bin/xr}
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
confirmed(){ [[ $1 =~ ^[[:space:]]*[Yy][[:space:]]*$ ]]; }
confirm(){ local answer; answer=$(ask "$1 [y/N]：" "$2 [y/N]: ") || return 1; confirmed "$answer"; }
# Keep report commands attached to the terminal (vnStat live mode needs a TTY).
report_output(){
 local report_status=0 report_reset=$RESET
 if [[ ! -t 1 || -n ${NO_COLOR:-} ]];then "$@";return $?;fi
 printf '%s' "$YELLOW"
 local GREEN=$YELLOW RED=$YELLOW CYAN=$YELLOW RESET=$YELLOW
 (
  export NO_COLOR=1 SYSTEMD_COLORS=0 CLICOLOR=0
  "$@"
 ) || report_status=$?
 printf '%s' "$report_reset"
 return "$report_status"
}
separator(){ printf '%s\n' '------------------------------------------------------------'; }
show_banner(){
 printf '%s\n============================================================\n' "$CYAN"
 cat <<'LOGO'
   ███████╗██╗  ██╗██╗   ██╗██████╗ ██╗   ██╗████████╗███████╗
   ██╔════╝██║ ██╔╝╚██╗ ██╔╝██╔══██╗╚██╗ ██╔╝╚══██╔══╝██╔════╝
   ███████╗█████╔╝  ╚████╔╝ ██████╔╝ ╚████╔╝    ██║   █████╗
   ╚════██║██╔═██╗   ╚██╔╝  ██╔══██╗  ╚██╔╝     ██║   ██╔══╝
   ███████║██║  ██╗   ██║   ██████╔╝   ██║      ██║   ███████╗
   ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═════╝    ╚═╝      ╚═╝   ╚══════╝
LOGO
 printf '               SKYBYTE Xray Manager v%s\n                Reality · Vision · XHTTP\n' "$VERSION"
 printf '============================================================%s\n' "$RESET"
}
OVERVIEW_CACHE=''
OVERVIEW_CACHE_AT=-10
OVERVIEW_CACHE_LANGUAGE=''
show_startup_info(){
 if [[ $OVERVIEW_CACHE_LANGUAGE != "$LANGUAGE" ]] || (( SECONDS - OVERVIEW_CACHE_AT >= 5 )); then
  if ! OVERVIEW_CACHE=$(helper overview --language "$LANGUAGE"); then
   OVERVIEW_CACHE=$(say '状态概览暂不可用，可通过菜单 d 或 l 查看详情。' 'Overview unavailable; use menu d or l for details.')
  fi
  OVERVIEW_CACHE_AT=$SECONDS
  OVERVIEW_CACHE_LANGUAGE=$LANGUAGE
 fi
 separator
 report_output printf '%s\n' "$OVERVIEW_CACHE"
 separator
}

# BUILD_IPV6
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
 local stage=$1 activate=${2:-no} readiness=${3:-no} was_active=no was_enabled=no applied=0 accepted=0
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
  [[ $readiness != ipv6 ]] || ipv6_engine ready || return 1
 fi
 helper finalize --stage "$stage" || return 1
 accepted=1
)
choose_reality_sni(){
 local choice selected
 menu 'Reality 握手域名\n1 Microsoft  www.microsoft.com（默认）\n2 Apple      www.apple.com\n3 Amazon     www.amazon.com\n4 Cloudflare www.cloudflare.com\n5 Google     dl.google.com\n6 自定义域名\n0 返回' 'Reality handshake name\n1 Microsoft  www.microsoft.com (default)\n2 Apple      www.apple.com\n3 Amazon     www.amazon.com\n4 Cloudflare www.cloudflare.com\n5 Google     dl.google.com\n6 Custom domain\n0 Back' >&2
 while :; do
  choice=$(ask '选择 [1]（也可直接输入域名）：' 'Choose [1] (or enter a domain directly): ') || return 1
  case ${choice:-1} in
   1) selected=www.microsoft.com;;
   2) selected=www.apple.com;;
   3) selected=www.amazon.com;;
   4) selected=www.cloudflare.com;;
   5) selected=dl.google.com;;
   6) while :; do
       selected=$(ask '自定义 Reality 握手域名（必填）：' 'Custom Reality handshake domain (required): ') || return 1
       [[ $selected =~ [^[:space:]] ]] && break
       warn '请填写握手域名。' 'Enter a handshake domain.' >&2
      done;;
   0) return 0;;
   *) if [[ $choice =~ ^[0-9]+$ ]]; then
       warn '选项无效，请输入 1–6、0 或域名。' 'Invalid option; enter 1–6, 0 or a domain.' >&2
       continue
      fi
      selected=$choice;;
  esac
  printf '%s\n' "$selected"
  return 0
 done
}
install_check_engine(){ python3 - "$@" <<'PY_INSTALL_CHECKS'
# BUILD_PREFLIGHT
PY_INSTALL_CHECKS
}
install_environment_check(){
 local options=(--project xray --language "$LANGUAGE" --phase environment)
 [[ ${1:-vision} == xhttp-tls ]] || options+=(--reality)
 report_output install_check_engine "${options[@]}" --paths "$SKYBYTE_XRAY_DIR" "$SKYBYTE_XRAY_LIB" "${TMPDIR:-/tmp}"
}
install_port_check(){
 report_output install_check_engine --project xray --language "$LANGUAGE" --phase ports --listen "$2" --tcp-port "$1"
}
install_download_check(){
 local options=(--project xray --language "$LANGUAGE" --phase download)
 [[ ! -x $SKYBYTE_XRAY_BINARY || -L $SKYBYTE_XRAY_BINARY ]] || options+=(--existing-core)
 report_output install_check_engine "${options[@]}"
}
install_reality_target(){
 helper reality-input --target "$2" --sni "$1" || return 1
 say '正在检查 Reality 目标的 DNS、TCP、TLS 与证书（总时限 12 秒）……' 'Checking Reality target DNS, TCP, TLS and certificate (12-second deadline)…'
 if ! report_output reality_engine --project xray --language "$LANGUAGE" --target "$2" --sni "$1";then
  error 'Reality 握手目标检测未通过；请更换网站或修复 VPS 出站网络、DNS、时间与 CA 证书后重试。尚未写入新节点。' 'Reality target failed checks; change the target or repair VPS egress, DNS, clock and CA roots. No new node was written.'
  return 1
 fi
}
installation_check_menu(){
 local choice kind node_port listen sni target
 if [[ $# == 0 || $1 == --menu ]];then
  menu '节点安装前检测（不安装）\n1. TCP + Reality + Vision\n2. XHTTP + Reality\n3. XHTTP + TLS（系统/端口/下载检测）\n0. 返回' 'Node installation checks (no installation)\n1. TCP + Reality + Vision\n2. XHTTP + Reality\n3. XHTTP + TLS (system/port/download checks)\n0. Back'
  [[ ${1:-} != --menu ]] || return 0
  choice=$(ask '> ' '> ') || return 0
 else choice=$1;fi
 case $choice in 1)kind=vision;node_port=443;;2)kind=xhttp-reality;node_port=443;;3)kind=xhttp-tls;node_port=2053;;0)return 0;;*)return 1;;esac
 local entered
 entered=$(ask "TCP 端口 [$node_port]：" "TCP port [$node_port]: ") || return 0;node_port=${entered:-$node_port}
 listen=$(ask '监听：1 IPv4  2 双栈 IPv4+IPv6 [1]：' 'Listen: 1 IPv4  2 Dual-stack IPv4+IPv6 [1]: ') || return 0
 case ${listen:-1} in 1)listen=0.0.0.0;;2)listen=::;;*)return 1;;esac
 install_environment_check "$kind" && install_port_check "$node_port" "$listen" || return 1
 if [[ $kind != xhttp-tls ]];then
  sni=$(choose_reality_sni) || return 1;[[ -n $sni ]] || return 0
  target=$(ask "握手目标 [$sni:443]：" "Handshake target [$sni:443]: ") || return 0;target=${target:-$sni:443}
  install_reality_target "$sni" "$target" || return 1
 fi
 install_download_check
}
install_node(){
 local choice kind node_name node_port host sni target listen path='' mode=auto cert='' private_key='' stage
 local flags=()
 menu '1. VLESS + Reality + Vision\n2. VLESS + XHTTP + Reality\n3. VLESS + XHTTP + TLS / CDN\n4. 节点安装前检测（不安装）\n0. 返回' '1. VLESS + Reality + Vision\n2. VLESS + XHTTP + Reality\n3. VLESS + XHTTP + TLS / CDN\n4. Node installation checks (no installation)\n0. Back'
 choice=$(ask '> ' '> ') || return 1
 case $choice in 1) kind=vision; node_port=443;; 2) kind=xhttp-reality; node_port=443;; 3) kind=xhttp-tls; node_port=2053;; 4) run_submenu installation_check_menu;return;; 0) return 0;; *) return 1;; esac
 node_name=$(ask '节点名称 [SKYBYTE]：' 'Node name [SKYBYTE]: ') || return 1; node_name=${node_name:-SKYBYTE}-$kind
 node_port=$(ask "监听 TCP 端口 [$node_port]：" "TCP listen port [$node_port]: ") || return 1
 case $kind in vision|xhttp-reality) node_port=${node_port:-443};; *) node_port=${node_port:-2053};; esac
 listen=$(ask '监听：1 IPv4  2 双栈 IPv4+IPv6 [1]：' 'Listen: 1 IPv4  2 Dual-stack IPv4+IPv6 [1]: ') || return 1
 case ${listen:-1} in 1) listen=0.0.0.0;; 2) listen=::;; *) return 1;; esac
 while :; do
  host=$(ask '客户端连接地址（必填：本 VPS 的公网 IP 或域名）：' 'Client connection address (required: this VPS public IP/domain): ') || return 1
  [[ $host =~ [^[:space:]] ]] && break
  warn '此项没有默认值，请填写本 VPS 的公网 IP 或域名。' 'There is no default; enter this VPS public IP or domain.'
 done
 helper preflight --port "$node_port" --listen "$listen" --address "$host" --name "$node_name" --kind "$kind" || return 1
 install_environment_check "$kind" && install_port_check "$node_port" "$listen" || return 1
 if [[ $kind == xhttp-tls ]]; then
  sni=$(ask '证书域名 / TLS SNI：' 'Certificate domain / TLS SNI: ') || return 1
  cert=$(ask '已有可信 fullchain 证书文件绝对路径：' 'Absolute path to trusted fullchain certificate: ') || return 1
  private_key=$(ask '私钥文件绝对路径（不修改源文件）：' 'Absolute private-key path (source is preserved): ') || return 1
  helper tls-input --sni "$sni" --cert "$cert" --key "$private_key" || return 1
  local cdn
  cdn=$(ask '通过 CDN 连接？[y/N]：' 'Use a CDN? [y/N]: ') || return 1
  if confirmed "$cdn"; then flags+=(--cdn); mode=packet-up; fi
  warn 'CDN 的 DNS、HTTPS 端口及回源 TLS 验证须在提供商后台配置。' 'Configure CDN DNS, supported HTTPS port and verified origin TLS at your provider.'
 else
  sni=$(choose_reality_sni) || return 1
  [[ -n $sni ]] || return 0
  target=$(ask "握手目标 [$sni:443]：" "Handshake target [$sni:443]: ") || return 1; target=${target:-$sni:443}
  install_reality_target "$sni" "$target" || return 1
 fi
 if [[ $kind == xhttp-* ]]; then
  path=$(ask 'XHTTP 路径（回车自动生成）：' 'XHTTP path (Enter to generate): ') || return 1
  local selected
  selected=$(ask "模式 [$mode]（auto / packet-up / stream-up / stream-one）：" "Mode [$mode] (auto / packet-up / stream-up / stream-one): ") || return 1
  mode=${selected:-$mode}
 fi
 warn '请放行实际 TCP 端口，可用菜单 l 管理系统防火墙；配置检查不等于公网或 CDN 已连通。' 'Allow the actual TCP port using menu l for the host firewall; validation does not prove public/CDN connectivity.'
 if ! confirm '安装并启动所选节点？' 'Install and start the selected node?'; then
  say '已取消节点安装，未下载核心或更改节点配置。' 'Node installation cancelled; no core download or node configuration changes.'
  return 0
 fi
 install_download_check || return 1
 ensure_binary || { error '核心准备失败，具体原因见上方提示。' 'Core preparation failed; see the reason above.'; return 1; }
 flags+=(--kind "$kind" --port "$node_port" --listen "$listen" --address "$host" --sni "$sni" --name "$node_name")
 if [[ $kind == xhttp-tls ]]; then flags+=(--cert "$cert" --key "$private_key")
 else flags+=(--target "$target"); fi
 [[ $kind != xhttp-* ]] || flags+=(--path "$path" --mode "$mode")
 stage=$(helper prepare "${flags[@]}") || { error '节点配置准备失败，具体原因见上方提示。' 'Node configuration preparation failed; see the reason above.'; return 1; }
 apply_stage "$stage" yes || { error '安装失败，原配置已保留或回退。' 'Install failed; previous configuration retained or restored.'; return 1; }
 show_nodes
}
show_parameters(){
 report_output helper parameters --language "$LANGUAGE"
}
show_nodes(){
 [[ -f $SKYBYTE_XRAY_DIR/state.json ]] || { warn '尚未安装节点。' 'No nodes installed.'; return 0; }
 local line nodes index=0
 nodes=$(helper show) || return 1
 warn '节点链接包含凭据，请勿公开。' 'Node links contain credentials; keep them private.'
 while IFS= read -r line; do
  if (( index % 2 == 0 )); then separator; printf '%s%s%s\n' "$YELLOW" "$line" "$RESET"
  else printf '%s%s%s\n' "$RED" "$line" "$RESET"; fi
  index=$((index + 1))
 done <<< "$nodes"
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
 menu '1. Vision
2. XHTTP-Reality
3. XHTTP-TLS
0. 返回' '1. Vision
2. XHTTP-Reality
3. XHTTP-TLS
0. Back' >&2
 local choice
 choice=$(ask '> ' '> ') || return 1
 case $choice in 1) printf 'vision';; 2) printf 'xhttp-reality';; 3) printf 'xhttp-tls';; *) return 1;; esac
}
edit_nodes(){
 local choice kind value stage cert private_key host node_port path
 local flags=()
 # --menu renders only; a numeric argument executes one selected operation.
 if [[ $# == 0 || $1 == --menu ]]; then
 menu '1. 重命名
2. 删除协议
3. 更新 TLS 证书
4. 修改地址/端口/路径
0. 返回' '1. Rename
2. Remove protocol
3. Refresh TLS certificate
4. Edit address/port/path
0. Back'
 [[ ${1:-} != --menu ]] || return 0
 choice=$(ask '> ' '> ') || return 1
 else
  choice=$1
 fi
 [[ $choice != 0 ]] || return 0
 case $choice in 1|2|3|4) :;; *) error '选项无效。' 'Invalid option.';return 1;; esac
 kind=$(choose_kind) || return 0
 case $choice in
  1) value=$(ask '新的节点名称：' 'New node name: ') || return 1; stage=$(helper rename --kind "$kind" --name "$value") || return 1;;
  2) confirm '删除该协议？重新安装会生成新凭据。' 'Remove protocol? Reinstallation generates new credentials.' || return 1
     stage=$(helper remove --kind "$kind") || return 1;;
  3) [[ $kind == xhttp-tls ]] || return 1
     cert=$(ask '新的 fullchain 证书绝对路径：' 'New fullchain certificate absolute path: ') || return 1
     private_key=$(ask '匹配的私钥绝对路径：' 'Matching private-key absolute path: ') || return 1
     stage=$(helper refresh-tls --kind "$kind" --cert "$cert" --key "$private_key") || return 1;;
  4) helper show || return 1
     warn '回车保留原值；修改后请重新导入客户端，并放行新 TCP 端口。TLS SNI 与证书保持原值。' 'Enter keeps the current value; re-import clients after editing and allow the new TCP port. TLS SNI and certificates are preserved.'
     host=$(ask '新的客户端连接地址 [保留]：' 'New client connection address [keep]: ') || return 1
     node_port=$(ask '新的监听 TCP 端口 [保留]：' 'New TCP listen port [keep]: ') || return 1
     [[ -z $host ]] || flags+=(--address "$host")
     [[ -z $node_port ]] || flags+=(--port "$node_port")
     if [[ $kind == xhttp-* ]]; then
      path=$(ask '新的 XHTTP 路径 [保留]：' 'New XHTTP path [keep]: ') || return 1
      [[ -z $path ]] || flags+=(--path "$path")
     fi
     (( ${#flags[@]} )) || return 0
     stage=$(helper edit --kind "$kind" "${flags[@]}") || return 1;;
  *) return 1;;
 esac
 apply_stage "$stage" || return 1
 if [[ $choice == 4 ]]; then
  say '节点已更新；请使用菜单 b 的新链接或导出文件更新客户端。' 'Node updated; update clients with the new links or exports from menu b.'
 fi
}
service_menu(){
 helper guard || return 1
 # --menu renders only; a numeric argument executes one selected operation.
 if [[ $# == 0 || $1 == --menu ]]; then
 menu '1. 状态
2. 启动
3. 停止
4. 重启
5. 配置检查
6. 日志
0. 返回' '1. Status
2. Start
3. Stop
4. Restart
5. Validate
6. Logs
0. Back'
 local choice
 [[ ${1:-} != --menu ]] || return 0
 choice=$(ask '> ' '> ') || return 1
 else
  choice=$1
 fi
 case $choice in
  1) report_output systemctl status skybyte-xray.service --no-pager || true;;
  2) systemctl start skybyte-xray.service;; 3) systemctl stop skybyte-xray.service;; 4) systemctl restart skybyte-xray.service;;
  5) "$SKYBYTE_XRAY_BINARY" run -test -config "$SKYBYTE_XRAY_DIR/config.json";;
  6) report_output journalctl -u skybyte-xray.service -n 60 --no-pager;; 0) return 0;; *) return 1;;
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
 if [[ -f $SKYBYTE_XRAY_UNIT ]]; then
  systemctl stop skybyte-xray.service && systemctl disable skybyte-xray.service || return 1
 fi
 python3 - "$SKYBYTE_XRAY_DIR" "$SKYBYTE_XRAY_UNIT" "$SKYBYTE_XRAY_LIB" "$SKYBYTE_XRAY_SHORTCUT" <<'PY'
import json,sys
from pathlib import Path
root,unit,lib,shortcut=map(Path,sys.argv[1:])
state_file=root/'state.json'
state=json.loads(state_file.read_text()) if state_file.exists() else {'nodes':{}}
paths=[root/x for x in ['state.json','config.json','nodes.txt','subscription-base64.txt','language']] if state_file.exists() else []
for kind,node in state['nodes'].items():
 paths.append(root/('client-'+kind+'.json'))
 if 'ipv6_backup' in node:paths.append(root/('client-'+kind+'-ipv6.json'))
 if kind=='xhttp-tls': paths.extend([root/node['cert'],root/node['key']])
paths.extend([unit,lib/'xray'])
if any(p.is_symlink() or (p.exists() and not p.is_file()) for p in paths): raise SystemExit('Unsafe managed file')
if unit.exists() and not unit.read_text().startswith('# SKYBYTE Xray Manager unit v1\n'): raise SystemExit('Unknown service')
manager=lib/'manager.sh'
if manager.exists():
 if manager.is_symlink() or not manager.read_text().startswith('#!/usr/bin/env bash\n# SKYBYTE Xray Manager standalone;'): raise SystemExit('Unknown manager')
 paths.append(manager)
if shortcut.is_file() and not shortcut.is_symlink():
 if shortcut.read_text().startswith('#!/usr/bin/env bash\n# SKYBYTE Xray Manager shortcut v1\n') and str(manager) in shortcut.read_text():
  paths.append(shortcut)
for p in paths:
 if p.exists(): p.unlink()
PY
 systemctl daemon-reload || return 1
 warn '已卸载。备份、未知文件、系统依赖、防火墙规则和 BBR 设置保留；如需恢复 BBR，请在卸载前使用菜单 l → 8。' 'Removed. Backups, unknown files, dependencies, firewall rules and BBR settings retained; restore BBR with menu l → 8 before uninstalling if needed.'
 exit 0
}
guide(){
 say 'Copyright © 2026 SKYBYTE (skylink9119)。GPLv3，无担保；可按许可证修改和再分发。' 'Copyright © 2026 SKYBYTE (skylink9119). GPLv3, no warranty; modification and redistribution permitted under the license.'
 say '完整许可证：https://github.com/skylink9119/skybyte-xray-manager/blob/main/LICENSE' 'Full license: https://github.com/skylink9119/skybyte-xray-manager/blob/main/LICENSE'
 say 'Reality/Vision 和 XHTTP-Reality 使用不同 TCP 端口；XHTTP-TLS 需要已有可信域名证书。' 'Vision and XHTTP-Reality use separate TCP ports; XHTTP-TLS needs an existing trusted domain certificate.'
 say 'XHTTP-Reality 无需自己的域名和证书；默认不添加 Vision flow。先使用核心的 XMUX 默认值，不叠加 mux.cool；速度和抗干扰效果须实测。' 'XHTTP-Reality needs no personal domain/certificate and has no Vision flow. Start with core XMUX defaults, without mux.cool; measure performance on your route.'
 say '当前提供 Xray 直接终止 TLS 的入口；Nginx/Caddy、证书自动续期和 H3 选择尚未集成。H3 需要对端支持和 UDP 可达，不保证改善丢包线路。' 'TLS currently terminates in Xray. Nginx/Caddy, automatic renewal and H3 selection are not integrated. H3 needs peer support and reachable UDP; improvements are not guaranteed.'
 say 'CDN 模式需设置 DNS、可代理 HTTPS 端口及严格的回源证书验证；不替你配置 CDN。' 'For CDN, configure DNS, a supported HTTPS port and strict origin verification; CDN setup is manual.'
 say '客户端必须支持对应传输。节点文件是本地导出，不是在线订阅 URL。' 'Clients must support the transport. Exports are local files, not online subscription URLs.'
 say '证书为私密副本，外部续期后用“更新 TLS 证书”刷新；不自动签发或续期。' 'Certificates are private copies. After external renewal use Refresh TLS certificate; issuance/renewal is not automatic.'
 say '安装前检测：a → 4；检查不代表公网入站可达。短安装入口为 sky9119.cc/xr.sh。' 'Installation checks: a → 4; checks do not prove public inbound access. Short install entry: sky9119.cc/xr.sh.'
 say 'Reality 握手网站检测：主菜单 o，可检查当前节点或自定义目标，也可在检测通过后确认更换；检测通过不代表公网节点已连通。' 'Reality target checks: main menu o, check configured/custom targets or confirm a replacement after checks pass; checks do not prove public node connectivity.'
 say '安装后输入 xr 可重新打开菜单。' 'After installation, run xr to reopen the menu.'
}
firewall_open(){
 local value=${1:-} zone
 local flags=()
 [[ -z $value ]] || flags+=(--ports "$value")
 report_output helper firewall-status || return 1
 zone=$(ask 'firewalld 区域 [回车使用默认区域；UFW 忽略]：' 'firewalld zone [Enter for default; ignored by UFW]: ') || return 1
 [[ -z $zone ]] || flags+=(--zone "$zone")
 warn '只向已启用的 UFW/firewalld 添加入站 TCP 放行，不改 SSH 或默认策略。请同时检查服务商安全组。' 'Adds inbound TCP allows to active UFW/firewalld only; SSH and default policies stay unchanged. Also check provider security groups.'
 if [[ -n $value ]]; then
  confirm "放行 TCP ${value}？" "Allow TCP $value?" || return 0
 else
  helper node-ports || return 1
  confirm '放行以上全部已安装节点的 TCP 端口？' 'Allow TCP ports for all installed nodes above?' || return 0
 fi
 if ! helper firewall-allow ${flags[@]+"${flags[@]}"}; then
  error '防火墙操作未完成，部分放行规则可能已添加；请查看状态后重试。' 'Firewall operation incomplete; some allows may have been added. Check status before retrying.'
  return 1
 fi
 say 'TCP 放行命令已完成；仍需验证区域、IPv6 规则、规则优先级及公网连接。' 'TCP allow commands completed; still verify zone, IPv6 rules, rule priority and public connectivity.'
}
install_firewall(){
 local detected='' ssh_input extra_input
 local ssh_ports=() extra_ports=() flags=()
 helper firewall-setup-check || return 1
 if [[ -n ${SSH_CONNECTION:-} ]]; then detected=${SSH_CONNECTION##* }; fi
 if [[ -n $detected ]]; then
  ssh_input=$(ask "SSH TCP 端口（可空格分隔）[$detected]：" "SSH TCP ports (space-separated) [$detected]: ") || return 1
  ssh_input=${ssh_input:-$detected}
 else
  ssh_input=$(ask 'SSH TCP 端口（必填，可空格分隔，不默认使用 22）：' 'SSH TCP ports (required, space-separated; no assumed port 22): ') || return 1
 fi
 read -r -a ssh_ports <<< "$ssh_input"
 (( ${#ssh_ports[@]} )) || { error '必须填写 SSH 端口。' 'SSH ports are required.'; return 1; }
 extra_input=$(ask '其他需保留的 TCP 端口（空格分隔，例如 80 443；回车无；节点端口自动添加）：' 'Other TCP ports to retain (e.g. 80 443; Enter for none; node ports are automatic): ') || return 1
 read -r -a extra_ports <<< "$extra_input"
 flags+=(--ssh-ports "${ssh_ports[@]}")
 (( ${#extra_ports[@]} == 0 )) || flags+=(--ports "${extra_ports[@]}")
 helper firewall-setup-plan "${flags[@]}" || return 1
 warn '将通过系统 APT 安装 UFW（如缺少），先放行上述 TCP 端口，再启用默认拒绝入站、允许出站。其他未放行服务可能受影响；请确认 SSH 端口并保留服务商控制台入口。服务商安全组仍需单独设置。' 'Installs UFW with APT if missing, allows the TCP ports above, then enables deny-incoming/allow-outgoing defaults. Other services may be blocked; verify SSH ports and keep provider console access available. Provider security groups remain separate.'
 confirm '安装并启用 UFW？' 'Install and enable UFW?' || return 0
 if ! command -v ufw >/dev/null; then
  apt_refresh && apt-get install -y ufw || return 1
 fi
 helper firewall-setup "${flags[@]}" || return 1
 say 'UFW 已启用；请在保留当前 SSH 会话时，新开一个 SSH 连接验证访问。' 'UFW enabled; keep this SSH session and verify access from a new SSH connection.'
 report_output helper firewall-status
}
remove_firewall(){
 local choice current=absent plan='' result action=--remove
 menu '仅操作 UFW：\n1 仅停用，保留软件包和规则配置\n2 卸载软件包，保留规则配置\n3 卸载并清除规则配置\n0 返回' 'UFW only:\n1 Disable only; keep package and rule configuration\n2 Remove package; keep rule configuration\n3 Remove package and purge rule configuration\n0 Back'
 choice=$(ask '> ' '> ') || return 1
 case $choice in 0) return 0;; 1|2|3) :;; *) return 1;; esac
 if [[ $choice != 1 ]]; then
  if [[ $choice == 3 ]]; then
   action=--purge
   plan=$(helper ufw-remove-plan --purge) || return 1
  else
   plan=$(helper ufw-remove-plan) || return 1
  fi
  if [[ $plan == absent ]]; then
   if [[ $choice == 3 ]]; then
    say 'dpkg 未记录 UFW 软件包或残留配置；未清理未知文件。' 'dpkg records no UFW package or residual configuration; unknown files were not deleted.'
   else
    say 'UFW 软件包未安装，无需卸载；残留配置保持原样。' 'UFW package is not installed; nothing to remove. Any residual configuration is retained.'
   fi
   return 0
  fi
  if [[ $plan != ready && ( $plan != config-files || $choice != 3 ) ]]; then
   error '无法确认 UFW 卸载计划，未执行操作。' 'UFW removal plan was not recognized; no action taken.'
   return 1
  fi
 fi
 if [[ $plan == config-files ]]; then
  say 'UFW 软件包已卸载，仅剩规则配置。' 'UFW package is already removed; only configuration remains.'
 else
  current=$(helper ufw-state) || return 1
  say "当前 UFW 状态：$current" "Current UFW state: $current"
  if [[ $choice == 1 && $current == absent ]]; then
   say '未找到 UFW，无需停用。' 'UFW was not found; nothing to disable.'
   return 0
  fi
  warn '停用后 UFW 的主机入站保护将不再生效，原先被阻止的端口可能可达。此操作仅针对 UFW；其他防火墙和服务商安全组仍各自生效。节点、SSH 配置和 BBR 参数保留。' 'Disabling UFW removes its host filtering protection; previously blocked ports may become reachable. Only UFW is targeted; other firewalls and provider rules remain separate. Node, SSH configuration and BBR settings are retained.'
 fi
 if [[ $choice == 3 ]]; then
  warn '将通过 dpkg 清除 UFW 软件包及规则配置，此操作不可恢复；如需保留，请选择第 2 项。其他软件及未知文件不在清理范围内。' 'dpkg will purge the UFW package and rule configuration. This cannot be undone; choose option 2 to retain configuration. Other software and unknown files are outside the cleanup scope.'
  confirm '卸载 UFW 并清除规则配置？' 'Remove UFW and purge its rule configuration?' || return 0
 elif [[ $choice == 2 ]]; then
  confirm '先停用并验证 UFW，再卸载 UFW 软件包（保留配置）？' 'Disable and verify UFW, then remove its package while keeping configuration?' || return 0
 else
  confirm '停用 UFW（保留软件包和配置）？' 'Disable UFW while keeping its package and configuration?' || return 0
 fi
 if [[ $plan != config-files ]]; then
  result=$(helper ufw-disable) || return 1
  if [[ $result != disabled ]]; then
   error '没有确认 UFW 停用成功，未继续卸载。' 'UFW disable was not confirmed; package removal was not attempted.'
   return 1
  fi
 fi
 if [[ $choice == 1 ]]; then
  say 'UFW 已停用，软件包和规则配置保留。' 'UFW disabled; its package and rule configuration are retained.'
  return 0
 fi
 # Target only ufw, with purge selected explicitly; never force dependencies or autoremove.
 if ! dpkg "$action" ufw; then
  if [[ $choice == 3 ]]; then
   error 'UFW 软件包或规则配置清除未完成，可能已部分清除；请检查上方 dpkg 提示。不会自动重新启用。' 'UFW package or configuration purge did not complete; some files may already be removed. Inspect the dpkg output above. It will not be re-enabled automatically.'
  else
   error 'UFW 已停用，但软件包卸载未完成；请检查上方 dpkg 提示。不会自动重新启用。' 'UFW is disabled, but package removal did not complete; inspect the dpkg output above. It will not be re-enabled automatically.'
  fi
  return 1
 fi
 result=$(helper ufw-package-state) || return 1
 if [[ $choice == 3 && $result == absent ]]; then
  say 'UFW 软件包及规则配置已由 dpkg 清除；未清理其他软件或未知文件。' 'UFW package and rule configuration purged by dpkg; other software and unknown files were not deleted.'
 elif [[ $choice == 2 && ( $result == absent || $result == config-files ) ]]; then
  say 'UFW 软件包已卸载，规则配置保留。未卸载 iptables/nftables 或其他防火墙，也未执行全局规则清空。' 'UFW package removed; rule configuration retained. iptables/nftables and other firewalls were not removed, and no global rule flush was performed.'
 else
  error '尚未确认 UFW 软件包卸载或配置清除完成；请检查软件包状态。' 'UFW package removal or configuration purge could not be verified; check package status.'
  return 1
 fi
}
network_menu(){
 local choice value
 # --menu renders only; a numeric argument executes one selected operation.
 if [[ $# == 0 || $1 == --menu ]]; then
 menu '防火墙\n1 查看防火墙状态\n2 安装并启用 UFW\n3 放行全部节点 TCP 端口\n4 放行指定 TCP 端口\n5 停用/卸载 UFW\n\nBBR\n6 查看 BBR 状态\n7 启用 BBR + fq\n8 恢复启用前参数\n\nIPv6 备用入口\n9 IPv6 状态 / 启用 / 移除备用入口\n\n0 返回' 'Firewall\n1 Show firewall status\n2 Install and enable UFW\n3 Allow all node TCP ports\n4 Allow a TCP port\n5 Disable/remove UFW\n\nBBR\n6 Show BBR status\n7 Enable BBR + fq\n8 Restore previous settings\n\nIPv6 backup entry\n9 IPv6 status / enable / remove backup entry\n\n0 Back'
 [[ ${1:-} != --menu ]] || return 0
 choice=$(ask '> ' '> ') || return 1
 else
  choice=$1
 fi
 case $choice in
  1) report_output helper firewall-status;;
  2) install_firewall;;
  3) firewall_open;;
  4) value=$(ask '要放行的 TCP 端口（1–65535）：' 'TCP port to allow (1–65535): ') || return 1
     if [[ ! $value =~ ^[0-9]{1,5}$ ]] || (( 10#$value < 1 || 10#$value > 65535 )); then
      error 'TCP 端口无效。' 'Invalid TCP port.'; return 1
     fi
     firewall_open "$value";;
  5) remove_firewall;;
  6) report_output helper bbr-status;;
  7) warn 'BBR 调整全系统新 TCP 连接的默认拥塞控制；不保证提速，不更换内核或重启服务，也不替换现有网卡队列。' 'BBR changes the system default for new TCP connections; speed gains vary. No kernel replacement, service restart or live interface queue replacement.'
     confirm '保存原参数并启用 BBR + fq？' 'Save previous values and enable BBR + fq?' || return 0
     helper bbr-enable || return 1
     report_output helper bbr-status;;
  8) confirm '恢复本脚本启用 BBR 前的系统参数并移除本脚本的持久化文件？' 'Restore values saved before enabling BBR and remove the managed persistence file?' || return 0
     helper bbr-restore || return 1
     report_output helper bbr-status;;
  0) return 0;; *) return 1;;
 esac
}
update_manager(){
 local tag
 say "当前管理脚本：v${VERSION}，正在检查最新正式版……" "Current manager: v$VERSION; checking the latest stable release…"
 tag=$(helper manager-latest) || return 1
 if [[ -z $tag ]]; then
  say '当前版本已不低于最新正式版。' 'The current version is at least as new as the latest stable release.'
  return 2
 fi
 say "可更新到：$tag" "Available update: $tag"
 confirm '校验并更新管理脚本？节点和核心保持原样，成功后请重新运行 xr。' 'Verify and update the manager? Nodes and core are retained; reopen with xr after success.' || return 2
 if ! helper manager-update --release "$tag" --file "$SKYBYTE_XRAY_LIB/manager.sh"; then
  error '管理脚本更新未完成，请检查上方原因；已有备份位于 manager.previous.sh。' 'Manager update did not complete; check the reason above. Any saved backup is manager.previous.sh.'
  return 1
 fi
 say '管理脚本已更新，旧脚本保存为 manager.previous.sh。请重新输入 xr。' 'Manager updated; the old script is saved as manager.previous.sh. Run xr again.'
}
warp_choose_profile(){
 local selection profile domains
 menu '分流平台\n1 Netflix + Disney+ + ChatGPT + Gemini（默认）\n2 仅 Netflix\n3 仅 Disney+\n4 仅 ChatGPT\n5 仅 Gemini\n6 自定义域名后缀\n0 返回' 'Routing profile\n1 Netflix + Disney+ + ChatGPT + Gemini (default)\n2 Netflix only\n3 Disney+ only\n4 ChatGPT only\n5 Gemini only\n6 Custom domain suffixes\n0 Back' >&2
 selection=$(ask '选择 [1]：' 'Choose [1]: ') || return 1
 case ${selection:-1} in
  1) profile=all;; 2) profile=netflix;; 3) profile=disney;; 4) profile=chatgpt;; 5) profile=gemini;;
  6) domains=$(ask '域名后缀（空格分隔，不含通配符）：' 'Domain suffixes (space-separated, no wildcards): ') || return 1
     [[ -n $domains ]] || return 1; printf '%s\n' "$domains"; return;;
  *) return 1;;
 esac
 helper warp-profile --profile "$profile"
}
warp_apply(){
 local proxy_port=$1 domains stage
 local suffixes=()
 helper node-ports >/dev/null || return 1
 domains=$(warp_choose_profile) || return 0
 read -r -a suffixes <<< "$domains"
 warn '仅匹配的 TCP 域名流量使用 WARP，其余流量直连；匹配的 UDP 拒绝以便应用回退 TCP。WARP 出口通过不代表平台解锁。' 'Only matching TCP domains use WARP; other traffic stays direct. Matching UDP is blocked for TCP fallback. Verified WARP egress does not prove platform access.'
 confirm '应用 WARP 分流并重启原先运行的节点？' 'Apply WARP routing and restart previously running nodes?' || return 0
 helper warp-check --proxy-port "$proxy_port" || return 1
 stage=$(helper warp-prepare --proxy-port "$proxy_port" --domains "${suffixes[@]}") || return 1
 apply_stage "$stage" || return 1
 say 'WARP 分流已应用。可用选项 5 对比直连与 WARP 的平台响应。' 'WARP routing applied. Use option 5 to compare direct and WARP platform responses.'
}
warp_install_client(){
 local os_id code proxy_port tmp item listeners attempt ready=0
 helper node-ports >/dev/null || return 1
 if command -v warp-cli >/dev/null; then
  warn '已安装 WARP 客户端，请选择“使用已有本机代理”，保留现有注册和设置。' 'WARP is already installed; use the existing local proxy option to retain registration and settings.'
  return 1
 fi
 if [[ -e ${SKYBYTE_WARP_DATA_DIR:-/var/lib/cloudflare-warp} || -L ${SKYBYTE_WARP_DATA_DIR:-/var/lib/cloudflare-warp} ]]; then
  error '发现已有 WARP 数据，请先手动核对注册与模式，避免启动已有全局连接。' 'Existing WARP data found; inspect registration and mode before starting a potentially global connection.'
  return 1
 fi
 os_id=$(awk -F= '$1=="ID" {gsub(/"/,"",$2);print $2}' /etc/os-release)
 code=$(awk -F= '$1=="VERSION_CODENAME" {gsub(/"/,"",$2);print $2}' /etc/os-release)
 case $os_id:$code in ubuntu:jammy|ubuntu:noble|ubuntu:resolute|debian:bookworm|debian:trixie) ;; *) error '当前系统版本不在官方 WARP 自动安装支持列表中。' 'This OS release is not supported for automatic WARP installation.'; return 1;; esac
 local repo=/etc/apt/sources.list.d/skybyte-xray-cloudflare-warp.list key=/usr/share/keyrings/skybyte-xray-cloudflare-warp.gpg
 for item in "$repo" "$key"; do [[ ! -e $item && ! -L $item ]] || { error 'WARP 软件源文件已存在，请先核对。' 'WARP repository files already exist; inspect them first.'; return 1; }; done
 say '安装官方 Cloudflare WARP，仅启用本机代理模式。条款：https://www.cloudflare.com/application/terms/ 。卸载管理器会保留 WARP 软件和连接。' 'Install official Cloudflare WARP in local proxy mode. Terms: https://www.cloudflare.com/application/terms/ . Removing the manager retains WARP and its connection.'
 confirm '安装、注册并接受 WARP 条款？' 'Install, register and accept WARP terms?' || return 0
 proxy_port=$(ask '本机 SOCKS5 端口 [40000]：' 'Local SOCKS5 port [40000]: ') || return 0
 proxy_port=${proxy_port:-40000}
 [[ $proxy_port =~ ^[0-9]{4,5}$ ]] && ((10#$proxy_port>=1024 && 10#$proxy_port<=65535)) || return 1
 proxy_port=$((10#$proxy_port))
 # Validate node collisions before installing packages or writing repository files.
 python3 - "$SKYBYTE_XRAY_DIR/state.json" "$proxy_port" <<'PY_WARP_PORT' || return 1
import json,sys
assert all(n['port']!=int(sys.argv[2]) for n in json.load(open(sys.argv[1]))['nodes'].values()), 'Proxy conflicts with a node port / 代理与节点端口冲突'
PY_WARP_PORT
 apt_refresh && apt-get install -y curl ca-certificates gnupg iproute2 || return 1
 listeners=$(ss -H -ltn "( sport = :$proxy_port )") || return 1
 [[ -z $listeners ]] || { error '代理端口已被占用。' 'Proxy port is occupied.'; return 1; }
 tmp=$(mktemp -d "$SKYBYTE_XRAY_DIR/.warp-install.XXXXXX") || return 1
 if ! curl -q -fsSL --noproxy '*' --proto '=https' --proto-redir '=https' --max-time 30 https://pkg.cloudflareclient.com/pubkey.gpg -o "$tmp/key" ||
    ! gpg --batch --yes --dearmor --output "$tmp/keyring" "$tmp/key"; then rm -rf -- "$tmp"; return 1; fi
 install -m 644 "$tmp/keyring" "$key" || { rm -rf -- "$tmp"; return 1; }
 printf 'deb [signed-by=%s] https://pkg.cloudflareclient.com/ %s main\n' "$key" "$code" > "$repo"
 chmod 644 "$repo"; rm -rf -- "$tmp"
 apt_refresh && apt-get install -y cloudflare-warp || return 1
 systemctl enable --now warp-svc.service || return 1
 if warp-cli --accept-tos registration show >/dev/null 2>&1; then
  error '发现已有 WARP 注册，保留现有设置，请手动配置代理后选择选项 2。' 'Existing WARP registration found; retained. Configure its proxy manually and choose option 2.'; return 1
 fi
 warp-cli --accept-tos registration new >/dev/null && warp-cli --accept-tos mode proxy && warp-cli --accept-tos proxy port "$proxy_port" && warp-cli --accept-tos connect || return 1
 for ((attempt=0; attempt<3; attempt++)); do
  if helper warp-check --proxy-port "$proxy_port"; then ready=1; break; fi
  sleep 2
 done
 ((ready)) || { error 'WARP 尚未就绪，节点分流未改变。可稍后选择选项 2 重试。' 'WARP is not ready; node routing is unchanged. Retry with option 2 later.'; return 1; }
 warp_apply "$proxy_port"
}
media_engine(){
 python3 - "$@" <<'PY_DIAGNOSTICS'
# BUILD_MEDIA
import sys
try: diagnostic_main(sys.argv[1:])
except (ValueError, OSError, subprocess.SubprocessError) as error:
 print('检测失败 / Diagnostic failed: '+safe_text(error), file=sys.stderr);sys.exit(1)
PY_DIAGNOSTICS
}
warp_platform_test(){
 local proxy_port=$1
 helper warp-check --proxy-port "$proxy_port" || return 1
 report_output media_engine compare "$SKYBYTE_XRAY_DIR/reports" "$LANGUAGE" "$proxy_port"
}
media_check(){
 local selection action port=''
 if [[ $# == 0 || $1 == --menu || $1 == --interactive ]];then
  menu '========== 专业网络检测 ==========
【流媒体与 AI · UnlockTests】
1. VPS 直连 IPv4（全球 + AI）
2. VPS 直连 IPv6（全球 + AI）
3. VPS 直连双栈
4. WARP 代理出口
5. 直连 IPv4 / WARP 对比
6. 全地区平台（VPS IPv4）

【线路与测速 · 融合怪 Go】
7. 三网回程 / 路由
8. 三网测速（消耗流量）
9. 综合网络测评（消耗流量）
0. 返回' '========== Professional diagnostics ==========
[Media and AI · UnlockTests]
1. VPS direct IPv4 (global + AI)
2. VPS direct IPv6 (global + AI)
3. VPS direct dual stack
4. WARP proxy egress
5. Direct IPv4 / WARP comparison
6. All-region platforms (VPS IPv4)

[Routes and speed · goecs]
7. Return routes / traceroute
8. Speed tests (uses bandwidth)
9. Comprehensive network tests (uses bandwidth)
0. Back'
  [[ ${1:-} != --menu ]] || return 0
  selection=$(ask '> ' '> ') || return 0
 else selection=$1;fi
 case $selection in
  1)action=4;;2)action=6;;3)action=both;;4)action=warp;;5)action=compare;;6)action=all;;
  7)action=route;;8)action=speed;;9)action=full;;0)return 0;;*)return 1;;
 esac
 say '首次按需下载官方检测工具并校验；报告仅在本机，综合检测关闭上传。结果不保证账号可用或实际播放。' 'Official tools are downloaded and verified on demand; reports stay local and benchmark uploads are disabled. Results do not guarantee playback or account access.'
 case $action in
  warp|compare)port=$(ask '本机 SOCKS5 端口 [40000]：' 'Local SOCKS5 port [40000]: ') || return 0
   port=${port:-40000};helper warp-check --proxy-port "$port" || return 1;;
  speed|full)confirm '测速可能消耗大量流量并临时占用带宽，继续？' 'Tests may use substantial traffic and bandwidth. Continue?' || return 0;;
 esac
 report_output media_engine "$action" "$SKYBYTE_XRAY_DIR/reports" "$LANGUAGE" "$port"
}

warp_menu(){
 local choice proxy_port stage
 # --menu renders only; a numeric argument executes one selected operation.
 if [[ $# == 0 || $1 == --menu ]]; then
 printf '\n%s%s%s\n' "$CYAN" "$(if [[ $LANGUAGE == en ]]; then printf '========== WARP Manager =========='; else printf '========== WARP 管理 =========='; fi)" "$RESET"
 report_output helper warp-status --language "$LANGUAGE" || return 1
 menu '
【代理设置】
1. 安装官方 WARP 本机代理

【分流设置】
2. 使用已有代理 / 选择分流平台
3. 关闭 WARP 分流，恢复直连

【连接检测】
4. 验证 WARP 出口
5. 对比直连 / WARP 平台响应
6. 专业流媒体 / 回程 / 测速

0. 返回
--------------------------------------' '
[Proxy setup]
1. Install official WARP local proxy

[Routing]
2. Existing proxy / choose platforms
3. Disable WARP routing, restore direct

[Connection tests]
4. Verify WARP egress
5. Compare direct / WARP platform responses
6. Professional media / routes / speed tests

0. Back
--------------------------------------'
 [[ ${1:-} != --menu ]] || return 0
 choice=$(ask '> ' '> ') || return 0
 else
  choice=$1
 fi
 case $choice in
  1) warp_install_client;;
  6) media_check --interactive;;
  2|4|5)
   proxy_port=$(ask '本机 SOCKS5 端口 [40000]：' 'Local SOCKS5 port [40000]: ') || return 0
   proxy_port=${proxy_port:-40000}
   case $choice in 2) warp_apply "$proxy_port";; 4) helper warp-check --proxy-port "$proxy_port";; 5) warp_platform_test "$proxy_port";; esac;;
  3) confirm '关闭本项目 WARP 分流？WARP 软件和其他项目保持原样。' 'Disable WARP routing for this project? WARP and other projects are retained.' || return 0
     stage=$(helper warp-prepare --disable) || return 1
     apply_stage "$stage";;
  0) return 0;; *) return 1;;
 esac
}
reality_engine(){ python3 - "$@" <<'PY_REALITY'
# BUILD_REALITY
PY_REALITY
}
reality_replace(){
 local current choice kind available=no item _old_target _old_sni sni target stage
 current=$(helper reality-targets) || return 1
 [[ -n $current ]] || { warn '未安装 Reality 节点，无需更换；可选择检测自定义网站。' 'No Reality node installed; use a custom target check instead.';return 0; }
 say '当前节点 / 握手目标 / SNI：' 'Current node / target / SNI:'
 printf '%s\n' "$current"
 menu '选择要更换的节点\n1. Reality + Vision\n2. XHTTP + Reality\n0. 返回' 'Select the node to update\n1. Reality + Vision\n2. XHTTP + Reality\n0. Back'
 choice=$(ask '> ' '> ') || return 0
 case $choice in 1) kind=vision;;2) kind=xhttp-reality;;0) return 0;;*) return 1;;esac
 while IFS=$'\t' read -r item _old_target _old_sni;do
  [[ $item != "$kind" ]] || available=yes
 done <<< "$current"
 [[ $available == yes ]] || { error '所选 Reality 节点尚未安装，保留原配置。' 'Selected Reality node is not installed; configuration retained.';return 1; }
 sni=$(choose_reality_sni) || return 0
 [[ -n $sni ]] || return 0
 target=$(ask "握手目标 [$sni:443]（0 返回）：" "Handshake target [$sni:443] (0 to return): ") || return 0
 [[ $target != 0 ]] || return 0
 target=${target:-$sni:443}
 helper reality-edit --kind "$kind" --sni "$sni" --target "$target" --check-only || return 1
 if ! report_output reality_engine --project xray --language "$LANGUAGE" --target "$target" --sni "$sni";then
  error '新目标检测未通过，保留原配置。' 'New target failed checks; original configuration retained.';return 1
 fi
 warn '更换会短暂重启正在运行的服务；保留 UUID、密钥、端口及路径。所选节点的客户端需重新导入更新后的配置。' 'Running services will briefly restart; UUID, keys, port and path are retained. Re-import updated configuration on clients of this node.'
 confirm '将所选节点的 Reality 握手网站更换为上述目标？' 'Apply this Reality handshake target to the selected node?' || return 0
 stage=$(helper reality-edit --kind "$kind" --sni "$sni" --target "$target") || return 1
 apply_stage "$stage" || return 1
 say 'Reality 握手网站已更换；请重新导入节点或更新客户端 SNI。' 'Reality target updated; re-import the node or update client SNI.'
}
reality_menu(){
 local choice target sni
 if [[ $# == 0 || $1 == --menu ]]; then
  menu 'Reality 握手网站检测\n1. 检测当前节点的握手网站\n2. 检测自定义网站\n3. 更换握手网站（先检测后应用）\n0. 返回' 'Reality handshake target checks\n1. Check configured Reality targets\n2. Check a custom target\n3. Change handshake target (check before applying)\n0. Back'
  [[ ${1:-} != --menu ]] || return 0
  choice=$(ask '> ' '> ') || return 0
 else choice=$1; fi
 case $choice in
  1) report_output reality_engine --project xray --language "$LANGUAGE" --config "$SKYBYTE_XRAY_DIR/config.json";;
  2) target=$(ask '握手目标（域名或 域名:端口，0 返回）：' 'Target (hostname or host:port, 0 to return): ') || return 0
     [[ $target != 0 ]] || return 0
     [[ -n $target ]] || { error '请填写握手目标。' 'Enter a target.';return 1; }
     sni=$(ask '握手域名 / SNI（回车使用目标域名）：' 'Handshake SNI (Enter uses target hostname): ') || return 0
     report_output reality_engine --project xray --language "$LANGUAGE" --target "$target" --sni "$sni";;
  3) reality_replace;;
  0) return 0;; *) return 1;;
 esac
}
run_submenu(){
 local handler=$1 choice
 while :; do
  "$handler" --menu || { error '无法打开此菜单，请检查上方提示。' 'Cannot open this menu; inspect the output above.';return 0; }
  say '操作后留在此菜单；0 返回上一层。' 'Stay in this menu after each operation; 0 returns one level.'
  choice=$(ask '> ' '> ') || return 0
  [[ $choice != 0 ]] || return 0
  if [[ $handler == network_menu && $choice == 9 ]];then run_submenu ipv6_menu;continue;fi
  if [[ $handler == warp_menu && $choice == 6 ]];then run_submenu media_check;continue;fi
  if ! ( "$handler" "$choice" ); then
   error '操作未完成或已取消；可在当前菜单继续选择。' 'Operation incomplete or cancelled; choose again in this menu.'
  fi
 done
}
main_menu(){
 while :; do
  show_banner
  show_startup_info
  printf '%sYouTube: https://www.youtube.com/@SKYBYTE9119%s\n' "$CYAN" "$RESET"
  say '觉得脚本好用，欢迎订阅我的 YouTube 频道，支持后续维护。' 'If this script helps, subscribe to my YouTube channel to support maintenance.'
  menu '【节点】
a. 安装 / 添加节点
b. 查看节点与客户端配置
c. 节点二维码
e. 编辑节点 / 删除 / TLS 证书
p. 查看节点参数（注意保密）

【服务与网络】
d. 服务与日志
l. 防火墙 / BBR / IPv6 备用
n. WARP 分流 / 平台检测
o. Reality 握手网站检测

【更新与备份】
f. 更新 Xray 核心
m. 更新管理脚本
g. 备份配置
h. 恢复配置

【设置】
i. 使用说明
j. 切换语言
k. 卸载

q. 退出' '[Nodes]
a. Install / add nodes
b. Nodes and client configs
c. Node QR codes
e. Edit nodes / remove / TLS certificate
p. View node parameters (keep private)

[Services and network]
d. Service and logs
l. Firewall / BBR / IPv6 backup
n. WARP routing / platform tests
o. Reality handshake target checks

[Updates and backups]
f. Update Xray-core
m. Update manager script
g. Back up configuration
h. Restore configuration

[Settings]
i. Guide
j. Language
k. Uninstall

q. Exit'
  local choice
  choice=$(ask '请选择（字母）：' 'Choose (letter): ') || return 0
  # Read-only views reuse a brief in-memory snapshot; management actions refresh it.
  case $choice in a|A|1|d|D|4|e|E|5|f|F|6|h|H|8|j|J|10|k|K|11|l|L|12|m|M|13|n|N|14|o|O|15) OVERVIEW_CACHE_AT=-10;; esac
  case $choice in
   a|A|1) install_node || error '操作未完成或已取消；失败原因见上方提示。' 'Operation did not complete or was cancelled; see the reason above.';;
   b|B|2) show_nodes || error '无法读取节点，配置和导出文件未修改；请检查上方提示。' 'Cannot read nodes; configuration and exports are unchanged. Inspect the output above.';; c|C|3) qr_nodes || true;; d|D|4) run_submenu service_menu;; e|E|5) run_submenu edit_nodes;;
   f|F|6) update_core || error '核心更新失败，已保留或回退原核心。' 'Core update failed; previous core retained or restored.';;
   g|G|7) make_backup || true;; h|H|8) restore_backup || error '恢复失败，原配置已保留或回退。' 'Restore failed; previous configuration retained or restored.';;
   i|I|9) guide;; j|J|10) choose_language || true;; k|K|11) uninstall || error '卸载未完成。' 'Uninstall did not complete.';;
   l|L|12) run_submenu network_menu;;
   m|M|13) if update_manager; then return 0; fi;; q|Q|0) return 0;;
   n|N|14) run_submenu warp_menu;;
   o|O|15) run_submenu reality_menu;;
   p|P|16) show_parameters || error '无法读取节点参数，请检查本机托管配置。' 'Cannot read node parameters; inspect local managed configuration.';;
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
