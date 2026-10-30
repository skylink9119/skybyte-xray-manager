#!/usr/bin/env bash
# SKYBYTE Xray Manager standalone; generated from src/manager.sh and src/core.py.
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
set -Eeuo pipefail
umask 077
VERSION=0.1.30
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

# shellcheck shell=bash
ipv6_engine(){
 python3 - xray "$SKYBYTE_XRAY_DIR" '' "$@" <<'PY_IPV6'
"""Native IPv6 installation/backup checks. No downloads or routing changes."""
import ipaddress
import json
import pathlib
import socket
import subprocess
import time


def public_ipv6(value):
    if isinstance(value, str) and "%" in value:
        raise ValueError("Scoped IPv6 is not a public entry address")
    try:
        address = ipaddress.IPv6Address(value)
    except (ValueError, TypeError):
        raise ValueError('请输入公网 IPv6，不含方括号、端口或网卡后缀 / Enter a public IPv6 without brackets, port or scope') from None
    if not address.is_global or address.is_multicast or address.ipv4_mapped or address.is_reserved:
        raise ValueError('需要原生公网 IPv6，不能使用回环、内网或映射地址 / Native public IPv6 required')
    return str(address)


def ipv6_candidates():
    result = subprocess.run(['ip', '-j', '-d', '-6', 'addr', 'show', 'scope', 'global'],
                            capture_output=True, text=True, check=True, timeout=4)
    candidates = []
    for interface in json.loads(result.stdout):
        if 'UP' not in interface.get('flags', []):
            continue
        # WARP/WireGuard/TUN egress addresses do not provide public ingress.
        # Detailed link metadata avoids treating those addresses as native VPS IPs.
        kind = interface.get('linkinfo', {}).get('info_kind', '')
        if kind in {'wireguard', 'tun', 'tap', 'sit', 'ip6tnl', 'ipip', 'gre', 'gretap', 'ip6gre', 'ip6gretap', 'vti', 'vti6'} or interface.get('link_type') in {'none', 'sit', 'ip6tnl', 'ipip', 'gre', 'tunnel6'}:
            continue
        for item in interface.get('addr_info', []):
            if item.get('family') != 'inet6' or item.get('scope') != 'global':
                continue
            flags = set(item.get('flags', []))
            if flags & {'tentative', 'dadfailed', 'deprecated', 'temporary'} or any(item.get(k) for k in ('tentative', 'dadfailed', 'deprecated', 'temporary')) or item.get('preferred_life_time') == 0:
                continue
            try:
                value = public_ipv6(item['local'])
            except ValueError:
                continue
            if value not in candidates:
                candidates.append(value)
    return candidates


def ipv6_local(value):
    value = public_ipv6(value)
    if value not in ipv6_candidates():
        raise ValueError('IPv6 未配置在本机可用网卡，或地址尚未就绪 / IPv6 is not assigned and ready on this VPS')
    result = subprocess.run(['ip', '-6', 'route', 'get', '2606:4700:4700::1111', 'from', value],
                            capture_output=True, text=True, check=True, timeout=3)
    if not result.stdout.strip() or any(word in result.stdout.split() for word in ('unreachable', 'prohibit', 'blackhole')):
        raise ValueError('没有可用的 IPv6 路由 / No usable IPv6 route')
    with socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as probe:
        probe.bind((value, 0))
    return value


def ipv6_firewall():
    """UFW must manage IPv6 when active; never silently edit/reload SSH policy."""
    import os
    import shutil
    if not shutil.which('ufw'):
        print('提示：未安装 UFW，请安装防火墙并放行 SSH 和节点端口 / Install a firewall; allow SSH and node ports')
        return
    result = subprocess.run(['ufw', 'status'], capture_output=True, text=True, timeout=5,
                            env={**os.environ, 'LC_ALL': 'C'})
    if result.returncode:
        raise ValueError('无法读取 UFW 状态 / Cannot inspect UFW')
    if result.stdout.startswith('Status: inactive'):
        print('提示：UFW 未启用，请配置防火墙 / UFW is inactive; configure your firewall')
        return
    if not result.stdout.startswith('Status: active'):
        raise ValueError('无法识别 UFW 状态 / Cannot determine UFW status')
    import re
    if not re.search(r'^IPV6\s*=\s*["\x27]?yes["\x27]?\s*(?:#.*)?$', pathlib.Path('/etc/default/ufw').read_text(), re.M | re.I):
        raise ValueError('UFW 已启用但未管理 IPv6；请先设置 IPV6=yes 并核对 SSH 的 IPv6 放行规则 / Active UFW does not manage IPv6; enable IPV6=yes and verify IPv6 SSH rules first')


def ipv6_bind_check(listeners):
    for item in listeners:
        if item['listen'] not in ('0.0.0.0', '::') or item.get('ipv6_only'):
            raise ValueError('仅支持公网通配监听，拒绝更改回环或 IPv6-only 节点 / Public wildcard listeners required; loopback/IPv6-only nodes are preserved')
        if item['listen'] == '::':
            continue
        transport = socket.SOCK_DGRAM if item['protocol'] == 'udp' else socket.SOCK_STREAM
        with socket.socket(socket.AF_INET6, transport) as probe:
            # The current IPv4 listener remains running during preflight.
            probe.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            probe.bind(('::', item['port']))


def ipv6_listeners(project, root, conf=None, users=True):
    root = pathlib.Path(root)
    state = json.loads((root / 'state.json').read_text())
    if project == 'xray':
        return [{'listen': n['listen'], 'port': n['port'], 'protocol': 'tcp'}
                for n in state['nodes'].values() if not n.get('cdn')]
    configs = [pathlib.Path(conf)]
    ledger = root / 'users.json'
    if users and ledger.exists():
        for user in json.loads(ledger.read_text())['users']:
            if not user.get('deleted'):
                identity = user['id']
                import re
                if not re.fullmatch('[0-9a-f]{16}', identity):
                    raise ValueError('Invalid managed user ID')
                configs.append(root / 'users' / identity / 'server.json')
    listeners = []
    for filename in configs:
        for inbound in json.loads(filename.read_text())['inbounds']:
            if inbound['type'] in ('vless', 'hysteria2'):
                listeners.append({'listen': inbound['listen'], 'port': inbound['listen_port'],
                                  'protocol': 'udp' if inbound['type'] == 'hysteria2' else 'tcp',
                                  'ipv6_only': inbound.get('ipv6_only', False)})
    return listeners


def ipv6_ready(listeners):
    """Local TCP dual-stack and UDP6 listener checks; not a public ingress test."""
    deadline = time.monotonic() + 5
    while True:
        try:
            for item in listeners:
                if item['protocol'] == 'tcp':
                    for host in ('127.0.0.1', '::1'):
                        with socket.create_connection((host, item['port']), timeout=.3):
                            pass
                else:
                    result = subprocess.run(['ss', '-H', '-lnu6'], capture_output=True, text=True, check=True, timeout=2)
                    endpoints = [line.split()[3] for line in result.stdout.splitlines() if len(line.split()) > 4]
                    if not any(endpoint.rsplit(':', 1)[-1] == str(item['port']) and endpoint.rsplit(':', 1)[0] in ('*', '[::]', '::') for endpoint in endpoints):
                        raise ValueError('IPv6 UDP listener missing')
            return
        except (OSError, ValueError, subprocess.SubprocessError):
            if time.monotonic() >= deadline:
                raise ValueError('双栈监听检查失败；恢复原配置 / Dual-stack listener check failed; restoring the previous configuration') from None
            time.sleep(.2)


def ipv6_cli(project, root, conf, action, value=''):
    if action == 'detect':
        values = ipv6_candidates()
        if not values:
            raise ValueError('VPS 未发现可用的原生公网 IPv6；请先向服务商开通 / No native public IPv6; provision it with your VPS provider first')
        print('\n'.join(values))
    elif action == 'check-install':
        # A new IPv6 node has no state/configuration yet. Do not load or change it.
        ipv6_local(value)
        ipv6_firewall()
    elif action == 'check':
        ipv6_local(value)
        listeners = ipv6_listeners(project, root, conf)
        if not listeners:
            raise ValueError('没有可用的直连节点；Argo/CDN 节点保持不变 / No direct nodes; Argo/CDN nodes are preserved')
        ipv6_bind_check(listeners)
        ipv6_firewall()
    elif action == 'ready':
        ipv6_ready(ipv6_listeners(project, root, conf, users=False))
    elif action == 'ready-install':
        number = int(value)
        if not 1 <= number <= 65535:
            raise ValueError('Invalid IPv6 listener port')
        listeners = [item for item in ipv6_listeners(project, root, conf, users=False)
                     if item['listen'] == '::' and item['port'] == number]
        if not listeners:
            raise ValueError('New IPv6 listener missing')
        ipv6_ready(listeners)
    elif action == 'status':
        state = json.loads((pathlib.Path(root) / 'state.json').read_text())
        states = list(state['nodes'].values()) if project == 'xray' else [state]
        for node in states:
            backup = node.get('ipv6_backup')
            print(node.get('name', node.get('node_name', 'SKYBYTE')) + ': ' +
                  ('IPv6 备用已配置 / IPv6 backup configured: ' + backup['address'] if backup else '未配置 IPv6 备用 / IPv6 backup not configured'))
        print('客户端网络也必须支持 IPv6；本机检查不等于公网可达。请放行云防火墙的实际 IPv6 TCP/UDP 端口。\nClient IPv6 is required; local checks do not prove public reachability. Allow the actual IPv6 TCP/UDP ports in your provider firewall.')
    else:
        raise ValueError('Invalid IPv6 action')

import sys
try:ipv6_cli(*sys.argv[1:])
except (ValueError,OSError,KeyError,subprocess.SubprocessError) as error:
 print(str(error),file=sys.stderr);sys.exit(1)
PY_IPV6
}
ipv6_install_address(){
 local candidates selected
 if ! command -v ip >/dev/null;then
  say '正在安装 IPv6 检测依赖 iproute2……' 'Installing iproute2 for IPv6 checks…' >&2
  apt_refresh >&2 && apt-get install -y iproute2 >&2 || return 1
  command -v ip >/dev/null || { error '安装后仍找不到 ip，请检查 PATH。' 'ip is still missing; inspect PATH.';return 1; }
 fi
 candidates=$(ipv6_engine detect) || return 1
 say '本机可用公网 IPv6：' 'Available native IPv6:' >&2
 printf '%s\n' "$candidates" >&2
 selected=$(ask '节点 IPv6（回车使用第一个；输入 0 取消）：' 'Node IPv6 (Enter uses first; 0 cancels): ') || return 1
 [[ $selected != 0 ]] || return 2
 selected=${selected:-${candidates%%$'\n'*}}
 ipv6_engine check-install "$selected" >&2 || return 1
 printf '%s\n' "$selected"
}
ipv6_install_menu(){
 local choice
 if [[ $# == 0 || $1 == --menu ]];then
  menu '搭建 IPv6 节点（客户端需支持 IPv6）\n1. VLESS + Reality + Vision（TCP）\n2. VLESS + XHTTP + Reality（TCP）\n3. VLESS + XHTTP + TLS（直连）\n0. 返回' 'Install IPv6 nodes (client IPv6 required)\n1. VLESS + Reality + Vision (TCP)\n2. VLESS + XHTTP + Reality (TCP)\n3. VLESS + XHTTP + TLS (direct)\n0. Back'
  [[ ${1:-} != --menu ]] || return 0
  choice=$(ask '> ' '> ') || return 0
 else choice=$1;fi
 case $choice in 1|2|3)install_node ipv6 "$choice";;0)return 0;;*)return 1;;esac
}
ipv6_menu(){
 local choice candidates selected stage readiness=no
 if [[ $# == 0 || $1 == --menu ]];then
  menu 'IPv6 备用入口\n1 查看 IPv6 备用状态\n2 检测并启用 IPv6 备用入口\n3 移除 IPv6 备用入口（保留原节点）\n0 返回' 'IPv6 backup entry\n1 Show IPv6 backup status\n2 Detect and enable IPv6 backup\n3 Remove IPv6 backup (keep original nodes)\n0 Back'
  [[ ${1:-} != --menu ]] || return 0
  choice=$(ask '> ' '> ') || return 0
 else choice=$1;fi
 case $choice in
  1) report_output ipv6_engine status;;
  2)
   candidates=$(ipv6_engine detect) || return 1
   say "本机可用公网 IPv6：" "Available native IPv6:"
   printf '%s\n' "$candidates"
   selected=$(ask '备用 IPv6（回车使用第一个）：' 'Backup IPv6 (Enter uses first): ') || return 0
   selected=${selected:-${candidates%%$'\n'*}}
   helper node-ports >/dev/null && ipv6_engine check "$selected" || return 1
   warn '保留原地址、UUID、密钥、端口和 SNI，启用双栈监听并额外导出 IPv6 备用节点；CDN 节点保持不变。客户端网络必须支持 IPv6，云防火墙需放行实际 IPv6 端口。参数及链接保存在当前 VPS，请勿公开。' 'Keeps original addresses, UUIDs, keys, ports and SNI. Enables dual-stack and exports IPv6 backup nodes; CDN nodes are preserved. Client IPv6 and provider IPv6 firewall rules are required. Exports remain private on this VPS.'
   confirm '启用 IPv6 备用入口并重载正在运行的节点？' 'Enable IPv6 backup and reload running nodes?' || return 0
   stage=$(helper ipv6-prepare --address "$selected") || return 1
   readiness=ipv6
   apply_stage "$stage" no "$readiness" || return 1
   if [[ $(helper ufw-state) == active ]];then
    helper firewall-allow || return 1
   fi
   report_output ipv6_engine status
   say '重新导入节点后选择“IPv6备用”。已验证本地监听；公网连通需从有 IPv6 的客户端测试。未运行的服务保持停止。' 'Re-import and select the IPv6 backup node. Local listeners checked; test public ingress from an IPv6 client. Stopped services remain stopped.';;
  3)
   confirm '移除 IPv6 备用链接并恢复启用前的监听方式？原节点凭据保持不变。' 'Remove IPv6 backup links and restore previous listeners, keeping credentials?' || return 0
   stage=$(helper ipv6-prepare --disable) || return 1
   apply_stage "$stage" || return 1
   report_output ipv6_engine status;;
  0) return 0;;*) return 1;;
 esac
}

helper(){ python3 - "$@" <<'SKYBYTE_PYTHON'
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
"""SKYBYTE Xray Manager: private configuration, exports and transactions.

Only generated runtime state contains credentials. No imported content is executed.
"""
import argparse
import base64
import copy
import concurrent.futures
import errno
import hashlib
import io
import ipaddress
import json
import os
import platform
import re
import shlex
import shutil
import socket
import ssl
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.error
import urllib.request
import uuid
import zipfile
from pathlib import Path

VERSION = "0.1.30"
CORE_VERSION = "v26.10.29"
OWNER = "SKYBYTE-XRAY/1\n"
UNIT_MARK = "# SKYBYTE Xray Manager unit v1\n"
KINDS = ("vision", "xhttp-reality", "xhttp-tls")
WARP_PROFILES = {
    "netflix": ["netflix.com", "netflix.net", "nflxext.com", "nflximg.com", "nflximg.net", "nflxso.net", "nflxvideo.net"],
    "disney": ["disneyplus.com", "disney-plus.net", "dssott.com", "bamgrid.com"],
    "chatgpt": ["openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com"],
    "gemini": ["gemini.google.com", "aistudio.google.com", "generativelanguage.googleapis.com"],
}
MODES = ("auto", "packet-up", "stream-up", "stream-one")
MAX_ARCHIVE = 16 * 1024 * 1024


def checked_path(value):
    p = Path(value)
    if not p.is_absolute() or any(c in str(p) for c in '\n\r\x00%'):
        raise ValueError("Unsafe path / 路径无效")
    for component in (p, *p.parents):
        if component.is_symlink():
            raise ValueError("Symlink refused / 拒绝符号链接")
    return p


def write_private(path, data, mode=0o600):
    path = checked_path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(prefix=".write-", dir=path.parent)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "wb") as stream:
            stream.write(data if isinstance(data, bytes) else data.encode())
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def json_text(value):
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def domain(value):
    value = value.strip().rstrip(".").lower()
    value = value.encode("idna").decode("ascii")
    if len(value) > 253 or not all(re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", x)
                                    for x in value.split(".")):
        raise ValueError("Invalid domain / 域名无效")
    return value


def address(value):
    value = value.strip()
    if not value:
        raise ValueError("Client address required: enter your VPS public IP or domain / 客户端连接地址必填：请输入本 VPS 的公网 IP 或域名")
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        return domain(value)


def port(value):
    if isinstance(value, bool) or not str(value).isdigit() or not 1 <= int(value) <= 65535:
        raise ValueError("Invalid port / 端口必须为 1–65535")
    return int(value)


def name(value):
    if not value or len(value) > 64 or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError("Invalid node name / 节点名须为 1–64 个字符")
    return value


def xhttp_path(value):
    if not re.fullmatch(r"/[A-Za-z0-9/_~-]{1,127}", value):
        raise ValueError("Invalid XHTTP path / XHTTP 路径必须以 / 开头")
    return value


def key(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]{43}", value):
        raise ValueError("Invalid REALITY key / REALITY 密钥无效")
    if len(base64.urlsafe_b64decode(value + "=")) != 32:
        raise ValueError("Invalid REALITY key")
    return value


def certificate(cert, private_key, host, ca_file=None):
    cert, private_key = checked_path(cert), checked_path(private_key)
    if not cert.is_file() or not private_key.is_file():
        raise ValueError("Certificate files missing / 证书文件不存在")
    if cert.stat().st_size > 1024 * 1024 or private_key.stat().st_size > 1024 * 1024:
        raise ValueError("Certificate file too large")
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    def reject_password():
        raise ValueError("Encrypted private keys are not supported for unattended service startup / 自动启动服务不支持加密私钥，请提供未加密的服务端私钥并妥善保密")
    # Server operation is unattended. Reject encrypted keys without OpenSSL
    # prompting on the administrator's terminal and stalling the menu.
    context.load_cert_chain(str(cert), str(private_key), password=reject_password)
    decoded = ssl._ssl._test_decode_cert(str(cert))
    if ssl.cert_time_to_seconds(decoded["notAfter"]) <= __import__("time").time() + 86400:
        raise ValueError("Certificate expired or expires within 24h / 证书已过期或即将过期")
    host = domain(host)
    def matches(pattern):
        pattern = pattern.lower()
        return pattern == host or (pattern.startswith("*.") and
                                  host.endswith(pattern[1:]) and
                                  len(host.split(".")) == len(pattern.split(".")))
    if not any(matches(v) for k, v in decoded.get("subjectAltName", []) if k == "DNS"):
        raise ValueError("Certificate domain mismatch / 证书域名不匹配")
    command = ["openssl", "verify", "-purpose", "sslserver", "-untrusted", str(cert)]
    if ca_file:
        command += ["-CAfile", str(checked_path(ca_file))]
    command += [str(cert)]
    if subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5).returncode:
        raise ValueError("Certificate chain untrusted / 证书链不受系统信任")


def new_keys(binary):
    result = subprocess.run([str(binary), "x25519"], capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise ValueError("Xray key generation failed / Xray 密钥生成失败")
    fields = {}
    for line in result.stdout.splitlines():
        if ":" in line:
            label, value = line.split(":", 1)
            fields[re.sub(r"[^a-z]", "", label.lower())] = value.strip()
    private = fields.get("privatekey")
    public = fields.get("password") or fields.get("passwordpublickey") or fields.get("publickey")
    return key(private), key(public)


def validate_state(state):
    if not isinstance(state, dict) or set(state) not in ({"schema", "nodes"}, {"schema", "nodes", "warp"}) or state["schema"] != 1:
        raise ValueError("Unknown state format / 非托管状态格式")
    if "warp" in state:
        warp = state["warp"]
        if not isinstance(warp, dict) or set(warp) != {"port", "domains"} or type(warp["port"]) is not int or not 1024 <= warp["port"] <= 65535:
            raise ValueError("Invalid WARP proxy / WARP 代理配置无效")
        domains = warp["domains"]
        if not isinstance(domains, list) or not 1 <= len(domains) <= 128 or any(not isinstance(d, str) or domain(d) != d or "." not in d for d in domains) or len(set(domains)) != len(domains):
            raise ValueError("Invalid WARP domain suffixes / WARP 域名后缀无效")
    if not isinstance(state["nodes"], dict) or not set(state["nodes"]) <= set(KINDS):
        raise ValueError("Invalid protocol state")
    ports = set()
    for kind, node in state["nodes"].items():
        required = {"name", "uuid", "port", "address", "listen", "sni"}
        extra = {"private", "public", "short_id", "target"} if kind != "xhttp-tls" else {"cert", "key", "cdn"}
        if kind.startswith("xhttp"):
            extra |= {"path", "mode"}
        if not isinstance(node, dict) or set(node) not in (required | extra, required | extra | {"ipv6_backup"}):
            raise ValueError("Invalid node fields")
        if "ipv6_backup" in node:
            backup = node["ipv6_backup"]
            if not isinstance(backup, dict) or set(backup) != {"address", "previous_listen"}:
                raise ValueError("Invalid IPv6 backup metadata")
            ip = ipaddress.IPv6Address(backup["address"])
            if not ip.is_global or ip.is_multicast or ip.ipv4_mapped or ip.is_reserved or "%" in backup["address"] or node["listen"] != "::" or backup["previous_listen"] not in ("::", "0.0.0.0") or node.get("cdn"):
                raise ValueError("Invalid IPv6 backup address/listener")
        name(node["name"])
        if str(uuid.UUID(node["uuid"])) != node["uuid"]:
            raise ValueError("Invalid UUID")
        p = port(node["port"])
        if p in ports:
            raise ValueError("Duplicate TCP port / TCP 端口冲突")
        ports.add(p)
        if "warp" in state and p == state["warp"]["port"]:
            raise ValueError("WARP proxy conflicts with a node port / WARP 代理与节点端口冲突")
        address(node["address"])
        domain(node["sni"])
        if node["listen"] not in ("0.0.0.0", "::", "127.0.0.1", "::1"):
            raise ValueError("Invalid listen address")
        if kind != "xhttp-tls":
            key(node["private"])
            key(node["public"])
            if not re.fullmatch(r"[0-9a-f]{16}", node["short_id"]):
                raise ValueError("Invalid short ID")
            target_host, target_port = node["target"].rsplit(":", 1)
            domain(target_host)
            port(target_port)
        else:
            if not isinstance(node["cdn"], bool):
                raise ValueError("Invalid CDN setting")
            for field, suffix in (("cert", "crt"), ("key", "key")):
                if node[field] != f"tls/{node['uuid']}.{suffix}":
                    raise ValueError("Invalid certificate path")
        if kind.startswith("xhttp"):
            xhttp_path(node["path"])
            if node["mode"] not in MODES:
                raise ValueError("Invalid XHTTP mode")
        if kind == "xhttp-tls" and node["cdn"] and node["mode"] == "stream-one":
            raise ValueError("Use packet-up or stream-up for CDN / CDN 请使用 packet-up 或 stream-up")
    return state


def server_config(state, root):
    validate_state(state)
    inbounds = []
    for kind, node in state["nodes"].items():
        user = {"id": node["uuid"], "email": kind + "@skybyte.local"}
        stream = {"network": "raw" if kind == "vision" else "xhttp"}
        if kind == "vision":
            user["flow"] = "xtls-rprx-vision"
        else:
            stream["xhttpSettings"] = {"path": node["path"], "mode": "auto"}
        if kind == "xhttp-tls":
            stream.update(security="tls", tlsSettings={"minVersion": "1.2", "alpn": ["h2", "http/1.1"],
                "certificates": [{"certificateFile": str(root / node["cert"]), "keyFile": str(root / node["key"])}]})
        else:
            stream.update(security="reality", realitySettings={"show": False, "target": node["target"],
                "serverNames": [node["sni"]], "privateKey": node["private"], "shortIds": [node["short_id"]]})
        inbounds.append({"tag": kind, "listen": node["listen"], "port": node["port"], "protocol": "vless",
                         "settings": {"clients": [user], "decryption": "none"}, "streamSettings": stream})
    result = {"log": {"loglevel": "warning"}, "inbounds": inbounds,
            "outbounds": [{"protocol": "freedom", "tag": "direct"}, {"protocol": "blackhole", "tag": "block"}],
            "routing": {"domainStrategy": "IPOnDemand", "rules": [{"type": "field", "ip": ["127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12",
                "192.168.0.0/16", "169.254.0.0/16", "::1/128", "fc00::/7", "fe80::/10"], "outboundTag": "block"}]}}
    if "warp" in state:
        warp = state["warp"]
        result["outbounds"].append({"protocol": "socks", "tag": "warp", "settings": {
            "servers": [{"address": "127.0.0.1", "port": warp["port"]}]}})
        domains = ["domain:" + suffix for suffix in warp["domains"]]
        result["routing"]["rules"] += [
            {"type": "field", "network": "udp", "domain": domains, "outboundTag": "block"},
            {"type": "field", "network": "tcp", "domain": domains, "outboundTag": "warp"}]
        for inbound in inbounds:
            inbound["sniffing"] = {"enabled": True, "destOverride": ["http", "tls", "quic"], "routeOnly": True}
    return result


def warp_prepare(root, binary, number, domains, disable=False):
    ensure_owned(root)
    state = copy.deepcopy(load_state(root))
    if not state["nodes"] and not disable:
        raise ValueError("Install a node before configuring WARP / 请先安装节点，再设置 WARP 分流")
    if disable:
        state.pop("warp", None)
    else:
        state["warp"] = {"port": number, "domains": list(dict.fromkeys(domains))}
    validate_state(state)
    stage = make_stage(root, state)
    try:
        finish_stage(stage, state, binary)
        return stage
    except BaseException:
        shutil.rmtree(stage)
        raise


def warp_status(root, language="zh"):
    root = checked_path(root)
    warp = None
    if root.exists():
        ensure_owned(root)
        warp = load_state(root).get("warp")
    if not warp:
        return "Status: WARP routing disabled" if language == "en" else "当前状态：未启用 WARP 分流"
    if language == "en":
        return f"Routing: Selected domains use WARP\nLocal proxy: 127.0.0.1:{warp['port']} | Suffixes: {len(warp['domains'])}"
    return f"当前模式：仅指定域名使用 WARP\n本机代理：127.0.0.1:{warp['port']} | 域名后缀：{len(warp['domains'])} 个"


def warp_verify(number):
    number = port(number)
    if number < 1024:
        raise ValueError("WARP proxy port must be 1024–65535 / WARP 代理端口须为 1024–65535")
    listeners = system_command(["ss", "-H", "-ltn", f"( sport = :{number} )"]).stdout.splitlines()
    if not listeners or any(len(line.split()) < 4 or line.split()[3] not in (
            f"127.0.0.1:{number}", f"[::1]:{number}", f"::1:{number}") for line in listeners):
        raise ValueError("WARP proxy must listen only on loopback / WARP 代理须已启动且仅监听回环地址")
    result = system_command(["curl", "-q", "-fsSL", "--noproxy", "", "--proxy", f"socks5h://127.0.0.1:{number}",
        "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "4", "--max-time", "10", "--max-filesize", "65536",
        "https://www.cloudflare.com/cdn-cgi/trace"])
    trace = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    try:
        valid = trace.get("warp") in ("on", "plus") and ipaddress.ip_address(trace.get("ip", "")).is_global and re.fullmatch("[A-Z]{2}", trace.get("loc", ""))
    except ValueError:
        valid = False
    if not valid:
        raise ValueError("WARP egress could not be verified; routing unchanged / WARP 出口验证未通过，分流保持原样")
    return trace["ip"], trace["loc"]


def client_config(kind, node, socks_port=10808):
    stream = {"network": "raw" if kind == "vision" else "xhttp"}
    if kind.startswith("xhttp"):
        stream["xhttpSettings"] = {"path": node["path"], "mode": node["mode"], "host": node["sni"]}
    if kind == "xhttp-tls":
        stream.update(security="tls", tlsSettings={"serverName": node["sni"], "allowInsecure": False,
                                                     "alpn": ["h2", "http/1.1"], "fingerprint": "chrome"})
    else:
        stream.update(security="reality", realitySettings={"serverName": node["sni"], "fingerprint": "chrome",
            "publicKey": node["public"], "shortId": node["short_id"], "spiderX": "/"})
    user = {"id": node["uuid"], "encryption": "none"}
    if kind == "vision":
        user["flow"] = "xtls-rprx-vision"
    return {"log": {"loglevel": "warning"}, "inbounds": [{"listen": "127.0.0.1", "port": socks_port,
        "protocol": "socks", "settings": {"auth": "noauth", "udp": True}}], "outbounds": [{"tag": "proxy",
        "protocol": "vless", "settings": {"vnext": [{"address": node["address"], "port": node["port"],
        "users": [user]}]}, "streamSettings": stream}]}


def node_uri(kind, node):
    query = {"encryption": "none", "type": "tcp" if kind == "vision" else "xhttp",
             "security": "tls" if kind == "xhttp-tls" else "reality", "sni": node["sni"], "fp": "chrome"}
    if kind == "vision":
        query["flow"] = "xtls-rprx-vision"
    if kind == "xhttp-tls":
        query.update(allowInsecure="0", alpn="h2,http/1.1")
    else:
        query.update(pbk=node["public"], sid=node["short_id"], spx="/")
    if kind.startswith("xhttp"):
        query.update(path=node["path"], mode=node["mode"], host=node["sni"])
    host = node["address"]
    if ":" in host:
        host = "[" + host + "]"
    return f"vless://{node['uuid']}@{host}:{node['port']}?{urllib.parse.urlencode(query)}#{urllib.parse.quote(node['name'], safe='')}"


def engine_check(binary, config):
    result = subprocess.run([str(binary), "run", "-test", "-config", str(config)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
    if result.returncode:
        raise ValueError("Xray rejected configuration / Xray 配置校验失败")


def load_state(root):
    p = root / "state.json"
    checked_path(p)
    return validate_state(json.loads(p.read_text())) if p.exists() else {"schema": 1, "nodes": {}}


def node_parameters(root, language="zh"):
    def tr(zh, en):
        return en if language == "en" else zh
    lines = [tr("========== 保密提醒 ==========", "========== KEEP PRIVATE =========="),
             tr("本脚本的节点配置、凭据、订阅和备份等重要数据保存在当前 VPS，请妥善保管。",
                "Node configuration, credentials, subscriptions and backups are stored on this VPS. Protect them."),
             tr("请在可信终端查看；不要公开节点参数、完整链接、二维码或截图。",
                "Use a trusted terminal. Do not publish node parameters, full links, QR codes or screenshots."),
             tr("请务必安装并启用防火墙：主菜单 l → 2；先放行 SSH 和实际节点端口。",
                "Install and enable a firewall: main menu l → 2. Allow SSH and actual node ports first.")]
    if not checked_path(root / "state.json").exists():
        return "\n".join(lines + [tr("尚未安装节点。", "No nodes installed.")])
    ensure_owned(root)
    state = load_state(root)
    for kind in KINDS:
        if kind not in state["nodes"]:
            continue
        node = state["nodes"][kind]
        lines += ["-" * 60, node["name"] + " | " + kind,
                  tr("连接地址: ", "Server address: ") + node["address"],
                  tr("端口: ", "Port: ") + str(node["port"]), "UUID: " + node["uuid"]]
        if kind == "xhttp-tls":
            na = tr("不适用（TLS 节点不使用 Reality）", "Not applicable (TLS node does not use Reality)")
            lines += [tr("公钥: ", "Public key: ") + na, "Short ID: " + na,
                      tr("TLS 域名（SNI）: ", "TLS SNI: ") + node["sni"],
                      tr("Reality 握手目标: ", "Reality target: ") + na]
        else:
            lines += [tr("公钥: ", "Public key: ") + node["public"], "Short ID: " + node["short_id"],
                      tr("握手网站（SNI）: ", "Handshake SNI: ") + node["sni"],
                      tr("Reality 握手目标: ", "Reality target: ") + node["target"]]
    if not state["nodes"]:
        lines.append(tr("尚未安装节点。", "No nodes installed."))
    return "\n".join(lines)


def ensure_owned(root, create=False):
    checked_path(root)
    marker = checked_path(root / ".owner")
    if root.exists():
        if not root.is_dir():
            raise ValueError("Managed path is not a directory")
        if marker.exists():
            if marker.read_text() != OWNER:
                raise ValueError("Unknown owner / 已有目录非本脚本管理")
        elif any(root.iterdir()) or not create:
            raise ValueError("Existing configuration refused / 拒绝覆盖现有配置")
    elif not create:
        raise ValueError("Not installed / 尚未安装")
    if create:
        root.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(root, 0o700)
        if not marker.exists():
            write_private(marker, OWNER)
    state = load_state(root)
    for relative in owned_names(state) | {"language", ".transaction"}:
        checked_path(root / relative)


def tls_names(state):
    node = state["nodes"].get("xhttp-tls")
    return {node["cert"], node["key"]} if node else set()


def ipv6_node(node):
    result = copy.deepcopy(node)
    result['address'] = node['ipv6_backup']['address']
    result['name'] += '-IPv6备用'
    return result


def ipv6_state(state, value=None):
    result = copy.deepcopy(state)
    nodes = [n for n in result['nodes'].values() if not n.get('cdn')]
    if not nodes:
        raise ValueError('没有直连节点 / No direct nodes installed')
    for node in nodes:
        if value is None:
            backup = node.pop('ipv6_backup', None)
            if backup:
                node['listen'] = backup['previous_listen']
        else:
            if node['listen'] not in ('::', '0.0.0.0'):
                raise ValueError('回环节点保持不变，请先使用公网监听 / Loopback nodes are preserved; use a public listener first')
            previous = node.get('ipv6_backup', {}).get('previous_listen', node['listen'])
            node['ipv6_backup'] = {'address': str(ipaddress.IPv6Address(value)), 'previous_listen': previous}
            node['listen'] = '::'
    return validate_state(result)


def owned_names(state):
    return {"state.json", "config.json", "nodes.txt", "subscription-base64.txt"} | tls_names(state) | {
        "client-" + k + ".json" for k in state["nodes"]} | {
        "client-" + k + "-ipv6.json" for k, n in state["nodes"].items() if "ipv6_backup" in n}


def render_files(state, root):
    files = {"state.json": json_text(state), "config.json": json_text(server_config(state, root))}
    lines = [node_uri(k, n) for k, n in state["nodes"].items()]
    lines += [node_uri(k, ipv6_node(n)) for k, n in state['nodes'].items() if 'ipv6_backup' in n]
    nodes = "\n".join(lines) + ("\n" if lines else "")
    files["nodes.txt"] = nodes
    files["subscription-base64.txt"] = base64.b64encode(nodes.encode()).decode() + "\n"
    files.update({"client-" + k + ".json": json_text(client_config(k, n)) for k, n in state["nodes"].items()})
    files.update({'client-' + k + '-ipv6.json': json_text(client_config(k, ipv6_node(n)))
                  for k, n in state['nodes'].items() if 'ipv6_backup' in n})
    return files


def check_port(host, number):
    try:
        with socket.socket(socket.AF_INET6 if ":" in host else socket.AF_INET) as listener:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if ":" in host:
                listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            listener.bind((host, number))
    except OSError as error:
        if error.errno == errno.EADDRINUSE:
            raise ValueError(f"TCP {number} is already in use; choose a free port. Existing services are preserved. / TCP {number} 已被占用，请选择空闲端口；不会停止已有服务。") from None
        raise


def installation_preflight(options):
    address(options.address)
    name(options.name)
    number = port(options.port)
    root = checked_path(options.root)
    # Inspect existing state without creating a directory or an ownership marker.
    # An empty directory is also a valid destination for a first installation.
    if root.exists() and (not root.is_dir() or any(root.iterdir())):
        ensure_owned(root)
        nodes = load_state(root)["nodes"]
        if options.kind in nodes:
            raise ValueError("Protocol already installed / 该协议已安装，请使用编辑节点功能；删除后重新安装会更换凭据")
        if number in {node["port"] for node in nodes.values()}:
            raise ValueError("TCP port already used by a managed node / 托管节点端口冲突，请选择其他空闲端口")
    check_port(options.listen, number)


def edit_state(state, kind, client_address=None, node_port=None, path=None):
    state = copy.deepcopy(state)
    if kind not in state["nodes"]:
        raise ValueError("Protocol not installed / 协议未安装")
    node = state["nodes"][kind]
    old_port = node["port"]
    if client_address is not None:
        node["address"] = address(client_address)
    if node_port is not None:
        node["port"] = port(node_port)
    if path is not None:
        if not kind.startswith("xhttp"):
            raise ValueError("XHTTP path requires an XHTTP node / 只有 XHTTP 节点可修改路径")
        node["path"] = xhttp_path(path)
    validate_state(state)
    # The running node owns its current port; probe only a changed port.
    if node["port"] != old_port:
        check_port(node["listen"], node["port"])
    return state


def edit_reality(state, kind, sni, target):
    state = copy.deepcopy(state)
    if kind not in ('vision', 'xhttp-reality') or kind not in state['nodes']:
        raise ValueError('Installed Reality node required / 请先选择已安装的 Reality 节点')
    host, number = target.rsplit(':', 1)
    node = state['nodes'][kind]
    node.update(sni=domain(sni), target=domain(host) + ':' + str(port(number)))
    return validate_state(state)


def prepare(root, binary, options):
    # Validate required input before creating directories or generating credentials.
    client_address = address(options.address)
    node_name, node_port = name(options.name), port(options.port)
    ensure_owned(root, create=True)
    state = copy.deepcopy(load_state(root))
    if options.kind in state["nodes"]:
        raise ValueError("Protocol already installed / 该协议已安装，先删除再安装会更换凭据")
    if node_port in [n["port"] for n in state["nodes"].values()]:
        raise ValueError("TCP port already used by a managed node / 托管节点端口冲突")
    check_port(options.listen, node_port)
    node = {"name": node_name, "uuid": str(uuid.uuid4()), "port": node_port,
            "address": client_address, "listen": options.listen, "sni": domain(options.sni)}
    if options.kind == "xhttp-tls":
        certificate(options.cert, options.key, node["sni"], options.ca_file)
        node.update(cert=f"tls/{node['uuid']}.crt", key=f"tls/{node['uuid']}.key", cdn=options.cdn)
    else:
        private, public = new_keys(binary)
        node.update(private=private, public=public, short_id=os.urandom(8).hex(), target=options.target)
    if options.kind.startswith("xhttp"):
        node.update(path=xhttp_path(options.path or "/" + uuid.uuid4().hex), mode=options.mode)
    state["nodes"][options.kind] = node
    stage = make_stage(root, state)
    try:
        if options.kind == "xhttp-tls":
            write_private(stage / node["cert"], Path(options.cert).read_bytes())
            write_private(stage / node["key"], Path(options.key).read_bytes())
        finish_stage(stage, state, binary)
        return stage
    except BaseException:
        shutil.rmtree(stage)
        raise


def make_stage(root, state):
    validate_state(state)
    stage = Path(tempfile.mkdtemp(prefix=".stage-", dir=root))
    for relative in tls_names(state):
        existing = checked_path(root / relative)
        if existing.is_file():
            write_private(stage / relative, existing.read_bytes())
    return stage


def finish_stage(stage, state, binary):
    for relative, data in render_files(state, stage).items():
        write_private(stage / relative, data)
    engine_check(binary, stage / "config.json")


def unit_content(root, binary):
    return UNIT_MARK + f'''[Unit]
Description=SKYBYTE Xray Manager
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
ExecStart="{binary}" run -config "{root / 'config.json'}"
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
[Install]
WantedBy=multi-user.target
'''


def unit_guard(unit):
    checked_path(unit)
    if unit.exists() and (not unit.is_file() or not unit.read_text().startswith(UNIT_MARK)):
        raise ValueError("Existing service not owned / 拒绝覆盖已有服务")


def commit(root, stage, binary, unit, active, enabled):
    ensure_owned(root)
    stage = checked_path(stage)
    if stage.parent != root or not stage.name.startswith(".stage-"):
        raise ValueError("Invalid stage")
    unit_guard(unit)
    if (root / ".transaction").exists():
        raise ValueError("Pending transaction / 存在待恢复事务")
    old, new = load_state(root), load_state(stage)
    journal = root / ".transaction"
    # Refuse collisions with files that are not described by the previous state.
    old_names = owned_names(old) if (root / "state.json").exists() else set()
    new_files = render_files(new, root)
    changed_names = old_names | owned_names(new)
    for relative in changed_names:
        p = checked_path(root / relative)
        if p.exists() and relative not in old_names:
            raise ValueError("Unmanaged file collision / 拒绝覆盖非托管文件")
    journal.mkdir(mode=0o700)
    saved = []
    try:
        for relative in changed_names:
            p = root / relative
            if p.is_file():
                write_private(journal / "saved" / relative, p.read_bytes())
                saved.append(relative)
        if unit.exists():
            write_private(journal / "unit", unit.read_bytes())
        write_private(journal / "meta.json", json_text({"names": sorted(changed_names), "saved": saved,
            "unit_existed": unit.exists(), "active": bool(active), "enabled": bool(enabled)}))
        for relative in tls_names(new):
            write_private(root / relative, checked_path(stage / relative).read_bytes())
        # Certificates now exist at their final paths; validate again before replacing config.
        write_private(stage / ".final.json", json_text(server_config(new, root)))
        engine_check(binary, stage / ".final.json")
        for relative, data in new_files.items():
            write_private(root / relative, data)
        write_private(unit, unit_content(root, binary), 0o644)
        for relative in old_names - owned_names(new):
            p = root / relative
            if p.is_file():
                p.unlink()
    except BaseException:
        if (journal / "meta.json").exists():
            rollback(root, unit)
        else:
            shutil.rmtree(journal)
        raise


def rollback(root, unit):
    ensure_owned(root)
    unit_guard(unit)
    journal = checked_path(root / ".transaction")
    meta = json.loads((journal / "meta.json").read_text())
    for relative in meta["names"]:
        if relative not in {"state.json", "config.json", "nodes.txt", "subscription-base64.txt"} and not (
            re.fullmatch(r"client-(vision|xhttp-reality|xhttp-tls)(?:-ipv6)?\.json", relative) or
            re.fullmatch(r"tls/[0-9a-f-]{36}\.(crt|key)", relative)):
            raise ValueError("Invalid recovery manifest")
        destination = checked_path(root / relative)
        if relative in meta["saved"]:
            write_private(destination, checked_path(journal / "saved" / relative).read_bytes())
        elif destination.exists():
            destination.unlink()
    if meta["unit_existed"]:
        write_private(unit, (journal / "unit").read_bytes(), 0o644)
    elif unit.exists():
        unit.unlink()
    shutil.rmtree(journal)
    return meta


def finalize(root, stage):
    ensure_owned(root)
    if (root / ".transaction").exists():
        shutil.rmtree(checked_path(root / ".transaction"))
    stage = checked_path(stage)
    if stage.parent == root and stage.name.startswith(".stage-"):
        shutil.rmtree(stage)


def backup(root, output):
    ensure_owned(root)
    state = load_state(root)
    files = {"manifest.json": json_text({"schema": 1, "product": "SKYBYTE Xray Manager"}).encode(),
             "state.json": json_text(state).encode()}
    for relative in tls_names(state):
        files[relative] = checked_path(root / relative).read_bytes()
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w:gz") as archive:
        for relative, data in files.items():
            info = tarfile.TarInfo(relative)
            info.size, info.mode = len(data), 0o600
            archive.addfile(info, io.BytesIO(data))
    output = checked_path(output)
    if output.exists():
        raise ValueError("Backup destination exists / 备份文件已存在")
    write_private(output, stream.getvalue())


def restore_stage(root, binary, archive_path, ca_file=None):
    ensure_owned(root, create=True)
    archive_path = checked_path(archive_path)
    if archive_path.stat().st_size > MAX_ARCHIVE:
        raise ValueError("Backup too large")
    files = {}
    with tarfile.open(archive_path, "r:gz") as archive:
        total = 0
        for item in archive:
            total += item.size
            if not item.isfile() or item.name in files or item.size < 0 or total > MAX_ARCHIVE or len(files) >= 8:
                raise ValueError("Unsafe archive / 不安全的备份")
            if item.name not in ("manifest.json", "state.json") and not re.fullmatch(
                    r"tls/[0-9a-f-]{36}\.(crt|key)", item.name):
                raise ValueError("Unsafe archive path / 不安全的备份路径")
            files[item.name] = archive.extractfile(item).read()
    manifest = json.loads(files["manifest.json"])
    if manifest != {"schema": 1, "product": "SKYBYTE Xray Manager"}:
        raise ValueError("Not a SKYBYTE Xray backup")
    state = validate_state(json.loads(files["state.json"]))
    if set(files) != {"manifest.json", "state.json"} | tls_names(state):
        raise ValueError("Unexpected backup content")
    stage = make_stage(root, state)
    try:
        for relative in tls_names(state):
            write_private(stage / relative, files[relative])
        node = state["nodes"].get("xhttp-tls")
        if node:
            certificate(stage / node["cert"], stage / node["key"], node["sni"], ca_file)
        finish_stage(stage, state, binary)
        return stage
    except BaseException:
        shutil.rmtree(stage)
        raise


def download_binary(destination, asset, tag=CORE_VERSION):
    if not re.fullmatch(r"v[0-9]+(?:\.[0-9]+){2}", tag):
        raise ValueError("Invalid release version")
    allowed = {"Xray-linux-64.zip", "Xray-linux-arm64-v8a.zip", "Xray-macos-64.zip", "Xray-macos-arm64-v8a.zip"}
    if asset not in allowed:
        raise ValueError("Unsupported architecture")
    headers = {"User-Agent": "SKYBYTE-Xray-Manager"}
    if os.environ.get("SKYBYTE_GITHUB_TOKEN"):
        headers["Authorization"] = "Bearer " + os.environ["SKYBYTE_GITHUB_TOKEN"]
    request = urllib.request.Request("https://api.github.com/repos/XTLS/Xray-core/releases/tags/" + tag,
                                     headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        metadata = json.load(response)
    if metadata.get("draft") or metadata.get("prerelease") or metadata.get("tag_name") != tag:
        raise ValueError("Not a stable release")
    candidates = [a for a in metadata["assets"] if a["name"] == asset]
    if len(candidates) != 1:
        raise ValueError("Release asset missing")
    release_asset = candidates[0]
    expected = release_asset.get("digest", "")
    if not re.fullmatch(r"sha256:[a-f0-9]{64}", expected):
        raise ValueError("Official SHA256 unavailable / 官方 SHA256 不可用")
    url = release_asset["browser_download_url"]
    if url != f"https://github.com/XTLS/Xray-core/releases/download/{tag}/{asset}":
        raise ValueError("Unexpected release URL")
    with urllib.request.urlopen(url, timeout=120) as response:
        data = response.read(128 * 1024 * 1024 + 1)
    if len(data) > 128 * 1024 * 1024 or "sha256:" + hashlib.sha256(data).hexdigest() != expected:
        raise ValueError("Release digest mismatch / 核心下载校验失败")
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        entries = [i for i in archive.infolist() if i.filename == "xray"]
        if len(entries) != 1 or entries[0].file_size > 128 * 1024 * 1024:
            raise ValueError("Invalid binary archive")
        binary = archive.read(entries[0])
    write_private(destination, binary, 0o700)


def error_message(error):
    # External exceptions can contain credential-bearing URLs, paths or core output.
    if isinstance(error, ValueError):
        return str(error)
    if isinstance(error, urllib.error.HTTPError):
        return f"Download HTTP {error.code}; check GitHub access, rate limits and release availability / 下载返回 HTTP {error.code}，请检查 GitHub 访问、请求限额及版本是否存在"
    if isinstance(error, ssl.SSLError):
        return "TLS verification or handshake failed; check the target name, certificate and system time / TLS 验证或握手失败，请检查目标域名、证书和系统时间"
    if isinstance(error, (TimeoutError, urllib.error.URLError)):
        return "Network request failed; check DNS, outbound connectivity and retry / 网络请求失败，请检查 DNS、出站连接后重试"
    if isinstance(error, OSError):
        if error.errno in (errno.EACCES, errno.EPERM):
            return "Permission denied; use root and check directory permissions / 权限不足，请使用 root 并检查目录权限"
        if error.errno == errno.ENOENT:
            return "Required file or command missing; check file paths and dependencies / 所需文件或命令不存在，请检查文件路径与系统依赖"
        if error.errno == errno.ENOSPC:
            return "Insufficient disk space; free space before retrying / 磁盘空间不足，请清理空间后重试"
    if isinstance(error, subprocess.SubprocessError):
        return "Core or system command failed; check the binary and service status / 核心或系统命令失败，请检查核心文件及服务状态"
    return "Operation failed; check files, network and permissions / 操作失败，请检查文件、网络与权限"


def system_command(arguments, check=True):
    return subprocess.run(arguments, check=check, capture_output=True, text=True,
                          timeout=30, env={**os.environ, "LC_ALL": "C"})


def overview_read(path):
    try:
        return Path(path).read_text(errors="replace")
    except OSError:
        return ""


def overview_command(arguments):
    """Best-effort local probes must never prevent opening the menu."""
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=2,
                                env={**os.environ, "LC_ALL": "C"})
        return result.stdout.strip() if result.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def overview_commands(commands):
    # All local probes share one short wait instead of stacking their timeouts.
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        results = pool.map(overview_command, commands.values())
        return dict(zip(commands, results))


def startup_overview(root, binary, language="zh"):
    def tr(zh, en):
        return en if language == "en" else zh

    unknown = tr("未知", "Unknown")

    def clean(value):
        # Local host/package metadata is untrusted terminal text, too.
        value = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", str(value))
        return " ".join("".join(c if c.isprintable() else " " for c in value).split())[:240] or unknown

    def gib(value):
        return f"{value / (1024 ** 3):.2f} GiB"

    os_name = unknown
    for line in overview_read("/etc/os-release").splitlines():
        if line.startswith("PRETTY_NAME="):
            try:
                os_name = " ".join(shlex.split(line.split("=", 1)[1])) or unknown
            except ValueError:
                pass
            break
    machine = platform.uname()
    arch = {"x86_64": "amd64", "aarch64": "arm64"}.get(machine.machine, machine.machine)
    cpu = next((line.split(":", 1)[1].strip() for line in overview_read("/proc/cpuinfo").splitlines()
                if line.split(":", 1)[0].strip() in ("model name", "Hardware", "Processor") and ":" in line), unknown)
    memory = {}
    for line in overview_read("/proc/meminfo").splitlines():
        match = re.fullmatch(r"(\w+):\s+(\d+) kB", line)
        if match:
            memory[match[1]] = int(match[2]) * 1024
    total = memory.get("MemTotal", 0)
    available = memory.get("MemAvailable", sum(memory.get(key, 0) for key in ("MemFree", "Buffers", "Cached")))
    used = max(0, total - min(total, available))
    memory_text = f"{gib(used)} / {gib(total)}" if total else unknown
    swap = memory.get("SwapTotal", 0)
    swap_text = f"{gib(max(0, swap - memory.get('SwapFree', 0)))} / {gib(swap)}" if swap else tr("未配置", "Not configured")
    try:
        disk = shutil.disk_usage("/")
        disk_text = f"{gib(disk.used)} / {gib(disk.total)} ({disk.used / disk.total:.0%})" if disk.total else unknown
    except OSError:
        disk_text = unknown
    try:
        minutes = int(float(overview_read("/proc/uptime").split()[0])) // 60
        uptime = tr(f"{minutes // 1440} 天 {minutes // 60 % 24} 小时 {minutes % 60} 分", f"{minutes // 1440}d {minutes // 60 % 24}h {minutes % 60}m")
    except (ValueError, IndexError):
        uptime = unknown
    load = " / ".join(overview_read("/proc/loadavg").split()[:3]) or unknown

    components = [("UFW", "ufw", "ufw.service"), ("firewalld", "firewall-cmd", "firewalld.service"),
                  (tr("WARP 客户端", "WARP client"), "warp-cli", "warp-svc.service"),
                  ("Fail2ban", "fail2ban-client", "fail2ban.service"), (tr("二维码工具", "QR utility"), "qrencode", None)]
    present = {tool: bool(shutil.which(tool)) for _, tool, _ in components}
    units = ["skybyte-xray.service", *[unit for _, tool, unit in components if unit and present[tool]]]
    core_installed = False
    core_version = tr("未安装", "Not installed")
    try:
        checked_path(binary)
        marker = checked_path(binary.parent / ".owner")
        core_installed = binary.is_file() and os.access(binary, os.X_OK) and marker.read_text() == OWNER
    except (OSError, ValueError):
        pass
    commands = {"services": ["systemctl", "show", "--no-pager", "--property=Id,LoadState,ActiveState,UnitFileState", *units]}
    if core_installed:
        commands["version"] = [str(binary), "version"]
    if present["ufw"]:
        commands["ufw"] = ["ufw", "status"]
    readings = overview_commands(commands)
    service_output = readings["services"]
    services = {}
    for block in service_output.split("\n\n"):
        properties = dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
        if properties.get("Id") in units:
            services[properties["Id"]] = properties

    def service_status(unit, installed):
        properties = services.get(unit, {})
        active = properties.get("ActiveState")
        if active in ("active", "reloading"):
            return tr("运行中", "Running")
        if active == "failed":
            return tr("运行失败", "Failed")
        if active in ("activating", "deactivating"):
            return tr("启动中" if active == "activating" else "停止中", "Starting" if active == "activating" else "Stopping")
        if properties.get("LoadState") == "not-found":
            return tr("已安装，服务未注册", "Installed, service not registered") if installed else tr("未安装", "Not installed")
        if active == "inactive":
            return tr("已安装，未运行", "Installed, inactive")
        return tr("已安装，状态未知", "Installed, status unknown") if installed else unknown

    if core_installed:
        version_output = readings["version"]
        match = re.search(r"^Xray\s+(\S+)", version_output)
        core_version = match[1] if match else unknown
    main_service = services.get("skybyte-xray.service", {})
    enabled = main_service.get("UnitFileState", "")
    boot = tr("已启用", "Enabled") if enabled in ("enabled", "enabled-runtime") else (
        tr("未启用", "Disabled") if enabled in ("disabled", "masked", "masked-runtime", "static", "indirect") else unknown)

    nodes = tr("尚未安装节点", "No nodes installed")
    warp_text = tr("未启用分流", "Routing disabled")
    try:
        checked_path(root)
        if root.exists():
            ensure_owned(root)
            state = load_state(root)
            if "warp" in state:
                warp_text = tr("已配置域名分流", "Domain routing configured") + f" | 127.0.0.1:{state['warp']['port']} | {len(state['warp']['domains'])} " + tr("个后缀（连通性见菜单 n）", "suffixes (test connectivity in menu n)")
            names = {"vision": "Reality + Vision", "xhttp-reality": "XHTTP + Reality", "xhttp-tls": "XHTTP + TLS/CDN"}
            nodes = " | ".join(f"{names[kind]}: TCP {node['port']}" for kind, node in state["nodes"].items()) or nodes
    except (OSError, ValueError, KeyError, TypeError):
        nodes = tr("配置读取失败，请检查服务与日志", "Configuration unreadable; check service and logs")

    algorithm = overview_read("/proc/sys/net/ipv4/tcp_congestion_control").strip()
    qdisc = overview_read("/proc/sys/net/core/default_qdisc").strip()
    bbr = tr("已开启 BBR 加速", "BBR acceleration enabled") if algorithm == "bbr" else (
        tr("未开启 BBR 加速", "BBR acceleration not enabled") if algorithm else unknown)
    if algorithm:
        bbr += f" ({algorithm}" + (f" / {qdisc}" if qdisc else "") + ")"
    statuses = []
    for label, tool, unit in components:
        if not present[tool]:
            status = tr("未安装", "Not installed")
        elif tool == "ufw":
            ufw = readings["ufw"]
            status = tr("已启用", "Enabled") if ufw.startswith("Status: active") else (
                tr("已安装，未启用", "Installed, disabled") if ufw.startswith("Status: inactive") else tr("已安装，状态未知", "Installed, status unknown"))
        else:
            status = service_status(unit, True) if unit else tr("已安装", "Installed")
        statuses.append(f"{label}: {status}")
    lines = [tr("服务器配置", "Server configuration"),
             f"  {tr('系统', 'OS')}: {os_name} | {tr('架构', 'Architecture')}: {arch}",
             f"  {tr('内核', 'Kernel')}: {machine.release}",
             f"  CPU: {cpu} ({os.cpu_count() or unknown} vCPU)",
             f"  {tr('内存', 'Memory')}: {memory_text} | Swap: {swap_text}",
             f"  {tr('根分区', 'Root disk')}: {disk_text}",
             f"  {tr('运行时间', 'Uptime')}: {uptime} | {tr('负载 (1/5/15 分)', 'Load (1/5/15 min)')}: {load}",
             tr("运行状态", "Runtime status"),
             f"  Xray: {service_status('skybyte-xray.service', core_installed)} | {tr('开机自启', 'Start on boot')}: {boot}",
             f"  {tr('实际核心版本', 'Installed core version')}: {core_version}",
             f"  {tr('节点', 'Nodes')}: {nodes}",
             f"  BBR: {bbr}",
             f"  WARP: {warp_text}",
             tr("插件/组件（系统检测）", "Plugins/components (system detection)"),
             "  " + " | ".join(statuses[:2]), "  " + " | ".join(statuses[2:])]
    return "\n".join(clean(line) if not line.startswith("  ") else "  " + clean(line) for line in lines)


def ufw_command(arguments, check=True):
    try:
        return system_command(["ufw", *arguments], check=check)
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or "") + (error.stdout or "")
        reason = "check UFW diagnostics / 请检查 UFW 诊断输出"
        for token, label in [("Invalid position", "empty-rule position is invalid / 空规则列表位置无效"),
                             ("Permission denied", "permission/kernel capability denied / 权限或内核能力不足"),
                             ("Could not load logging rules", "logging rules could not load / 日志规则加载失败"),
                             ("iptables", "iptables backend failed / iptables 后端失败")]:
            if token in detail:
                reason = label
                break
        command = "ufw " + " ".join(arguments)
        raise ValueError("UFW step failed: " + command + " (exit " + str(error.returncode) + "); " + reason +
                         " / UFW 操作失败，具体命令如上；未显示外部异常中的敏感内容") from None
    except subprocess.TimeoutExpired:
        raise ValueError("UFW command timed out / UFW 命令超时: ufw " + " ".join(arguments)) from None
    except FileNotFoundError:
        raise ValueError("UFW executable missing; check package/PATH / 找不到 UFW 可执行文件，请检查安装与 PATH") from None


def ufw_state():
    if not shutil.which("ufw"):
        return "absent"
    result = ufw_command(["status"])
    if result.stdout.startswith("Status: active"):
        return "active"
    if result.stdout.startswith("Status: inactive"):
        return "inactive"
    raise ValueError("Cannot determine UFW status / 无法识别 UFW 状态")


def ufw_disable():
    if ufw_state() == "absent":
        return "absent"
    ufw_command(["--force", "disable"])
    if ufw_state() != "inactive":
        raise ValueError("UFW disable not verified; package removal stopped / 未确认 UFW 已停用，停止卸载软件包")
    return "disabled"


def ufw_package_state():
    result = system_command(["dpkg-query", "-W", "-f=${Status}", "ufw"], check=False)
    if result.returncode == 1:
        return "absent"
    if result.returncode != 0:
        raise ValueError("Cannot read UFW package status / 无法读取 UFW 软件包状态")
    status = result.stdout.strip()
    if status == "install ok installed":
        return "installed"
    fields = status.split()
    if (len(fields) == 3 and fields[0] in ("install", "deinstall", "purge", "unknown")
            and fields[1] == "ok" and fields[2] in ("not-installed", "config-files")):
        return "config-files" if fields[2] == "config-files" else "absent"
    raise ValueError("UFW package is held or incomplete; fix package state first / UFW 软件包被保留或状态不完整，请先修复软件包状态")


def ufw_remove_plan(purge=False):
    state = ufw_package_state()
    if state == "absent" or (state == "config-files" and not purge):
        return "absent"
    if state == "installed" and not shutil.which("ufw"):
        raise ValueError("UFW package files are missing; repair it before removal / UFW 软件包文件缺失，请先修复后再停用和卸载")
    try:
        # --no-act MUST precede the action; never remove files during preflight.
        system_command(["dpkg", "--no-act", "--purge" if purge else "--remove", "ufw"])
    except (OSError, subprocess.SubprocessError):
        raise ValueError("UFW removal dependency/lock check failed; no firewall changes / UFW 卸载依赖或锁检查失败，未改变防火墙；请检查依赖 UFW 的软件及软件包锁") from None
    return "config-files" if state == "config-files" else "ready"


def firewall_status():
    status = {"ufw": "unavailable", "firewalld": "unavailable"}
    ufw = ufw_state()
    if ufw != "absent":
        status["ufw"] = ufw
    if shutil.which("firewall-cmd"):
        result = system_command(["firewall-cmd", "--state"], check=False)
        if result.returncode == 0 and result.stdout.strip() == "running":
            status["firewalld"] = "active"
        elif result.returncode == 252:
            status["firewalld"] = "inactive"
        else:
            raise ValueError("Cannot determine firewalld status / 无法识别 firewalld 状态")
    return status


def firewall_allow(numbers, zone=""):
    numbers = sorted({port(number) for number in numbers})
    if not numbers:
        raise ValueError("No TCP ports selected / 没有可放行的 TCP 端口")
    if zone and not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", zone):
        raise ValueError("Invalid firewalld zone / firewalld 区域名称无效")
    status = firewall_status()
    active = [key for key, value in status.items() if value == "active"]
    if len(active) != 1:
        raise ValueError("Exactly one active UFW/firewalld is required; configure your firewall first / 需要仅有一个已启用的 UFW/firewalld，请先配置防火墙；未修改规则")
    if active[0] == "ufw":
        for number in numbers:
            ufw_command(["allow", "in", "proto", "tcp", "to", "any", "port", str(number)])
        return "UFW"
    if not zone:
        zone = system_command(["firewall-cmd", "--get-default-zone"]).stdout.strip()
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", zone):
        raise ValueError("Invalid firewalld zone / firewalld 区域名称无效")
    zones = system_command(["firewall-cmd", "--get-zones"]).stdout.split()
    if zone not in zones:
        raise ValueError("Unknown firewalld zone / firewalld 区域不存在")
    # No reload: change just these ports in the chosen runtime and permanent zone.
    for number in numbers:
        for permanent in (True, False):
            args = ["firewall-cmd", "--zone=" + zone] + (["--permanent"] if permanent else [])
            query = system_command(args + [f"--query-port={number}/tcp"], check=False)
            if query.returncode not in (0, 1):
                raise ValueError("firewalld query failed / firewalld 规则查询失败")
            if query.returncode == 1:
                system_command(args + [f"--add-port={number}/tcp"])
                if system_command(args + [f"--query-port={number}/tcp"], check=False).returncode != 0:
                    raise ValueError("firewalld verification failed / firewalld 放行验证失败")
    return "firewalld / " + zone


def netfilter_label(value):
    # Kernel object names can contain control characters; never emit them verbatim.
    return re.sub(r"[^A-Za-z0-9_.:-]", "?", str(value))[:64]


def nft_objects(text):
    try:
        data = json.loads(text)
    except ValueError:
        raise ValueError("Cannot parse nft JSON; UFW setup stopped / 无法解析 nft JSON，已停止 UFW 初始化") from None
    if not isinstance(data, dict) or not isinstance(data.get("nftables"), list):
        raise ValueError("Unknown nft JSON structure / 无法识别 nft JSON 结构")
    for item in data["nftables"]:
        if not isinstance(item, dict) or len(item) != 1:
            raise ValueError("Unknown nft object / 无法识别 nft 对象")
        kind, value = next(iter(item.items()))
        if not isinstance(value, dict):
            raise ValueError("Unknown nft object fields / 无法识别 nft 对象字段")
    return data["nftables"]


def nft_fail2ban_objects(items):
    """Recognize an isolated, early input chain containing only TCP address bans."""
    members = [item for item in items if any(value.get("family") == "inet" and
               value.get("name" if kind == "table" else "table") == "f2b-table"
               for kind, value in item.items())]
    if not members:
        return []
    tables = [item["table"] for item in members if "table" in item]
    chains = [item["chain"] for item in members if "chain" in item]
    set_values = [item["set"] for item in members if "set" in item]
    if any(not isinstance(value.get("name"), str) for value in set_values):
        return []
    sets = {value["name"]: value for value in set_values}
    rules = [item["rule"] for item in members if "rule" in item]
    if (len(tables) != 1 or len(chains) != 1 or not sets or not rules or
            len(members) != 2 + len(sets) + len(rules)):
        return []
    if set(tables[0]) - {"family", "name", "handle", "comment"}:
        return []
    chain = chains[0]
    if (set(chain) - {"family", "table", "name", "handle", "type", "hook", "prio", "policy", "comment"} or
            type(chain.get("prio")) is not int or
            (chain.get("name"), chain.get("type"), chain.get("hook"), chain.get("prio"), chain.get("policy")) !=
            ("f2b-chain", "filter", "input", -1, "accept")):
        return []
    for name, value in sets.items():
        if (not isinstance(name, str) or not re.fullmatch(r"addr6?-set-[A-Za-z0-9_.-]+", name) or
                value.get("type") != ("ipv6_addr" if name.startswith("addr6-") else "ipv4_addr") or
                set(value) - {"family", "table", "name", "handle", "type", "flags", "elem", "comment",
                              "size", "timeout", "gc-interval"} or
                not isinstance(value.get("flags", []), list) or
                any(flag not in ("interval", "timeout") for flag in value.get("flags", [])) or
                not isinstance(value.get("elem", []), list)):
            return []
    referenced = set()
    for rule in rules:
        if (rule.get("chain") != "f2b-chain" or
                set(rule) - {"family", "table", "chain", "handle", "expr", "comment"}):
            return []
        expressions = rule.get("expr")
        if not isinstance(expressions, list) or len(expressions) not in (3, 4):
            return []
        verdict = expressions[-1]
        if verdict != {"drop": None}:
            if (not isinstance(verdict, dict) or set(verdict) != {"reject"} or
                    verdict["reject"] not in [{"type": family, "expr": "port-unreachable"}
                                               for family in ("icmp", "icmpv6", "icmpx")]):
                return []
        matches = []
        for expression in expressions[:-1]:
            if not isinstance(expression, dict) or len(expression) != 1:
                return []
            if "counter" in expression:
                if (not isinstance(expression["counter"], dict) or
                        set(expression["counter"]) - {"packets", "bytes"}):
                    return []
            elif "match" in expression:
                matches.append(expression["match"])
            else:
                return []
        if len(matches) != 2 or any(not isinstance(match, dict) or
                set(match) != {"op", "left", "right"} or match["op"] != "==" for match in matches):
            return []
        port_matches = [match for match in matches if match["left"] == {"payload": {"protocol": "tcp", "field": "dport"}}]
        if len(port_matches) != 1:
            return []
        ports = port_matches[0]["right"]
        ports = ports.get("set") if isinstance(ports, dict) and set(ports) == {"set"} else [ports]
        if not isinstance(ports, list) or not ports or any(type(number) is not int or not 1 <= number <= 65535 for number in ports):
            return []
        source = next(match for match in matches if match is not port_matches[0])
        reference = source["right"]
        if not isinstance(reference, str) or not reference.startswith("@") or reference[1:] not in sets:
            return []
        address_set = sets[reference[1:]]
        protocol = "ip6" if address_set["type"] == "ipv6_addr" else "ip"
        if source["left"] != {"payload": {"protocol": protocol, "field": "saddr"}}:
            return []
        referenced.add(reference[1:])
    return members if referenced == set(sets) else []


def nft_fail2ban_signature(items):
    # Ban elements and counters change independently under the Fail2ban daemon.
    result = set()
    for item in nft_fail2ban_objects(items):
        kind, value = next(iter(item.items()))
        value = {key: data for key, data in value.items() if key not in ("handle", "elem")}
        if kind == "rule":
            value["expr"] = [expression for expression in value["expr"] if "counter" not in expression]
        result.add(json.dumps({kind: value}, sort_keys=True))
    return result


def nft_inspect(text):
    items = nft_objects(text)
    preserved = nft_fail2ban_objects(items)
    signature = nft_fail2ban_signature(preserved)
    for item in items:
        kind, value = next(iter(item.items()))
        if kind == "metainfo" or item in preserved:
            continue
        location = "/".join(netfilter_label(value.get(field, "?")) for field in ("family", "table", "chain" if kind == "rule" else "name"))
        if kind == "table":
            if not all(isinstance(value.get(field), str) for field in ("family", "name")):
                raise ValueError("Invalid nft table / nft 表信息异常")
            continue
        if kind == "chain":
            if not all(isinstance(value.get(field), str) for field in ("family", "table", "name")):
                raise ValueError("Invalid nft chain / nft 链信息异常")
            if "hook" in value or "policy" in value:
                if value.get("policy") != "accept":
                    return "chain " + location + " policy=" + netfilter_label(value.get("policy", "unknown")), signature
            continue
        # Rules (including ACCEPT/NAT), sets, flowtables and unknown state remain guarded.
        return netfilter_label(kind) + " " + location, signature
    return None, signature


def nft_conflict(text):
    return nft_inspect(text)[0]


def verify_fail2ban_preserved(signature):
    if not signature:
        return
    try:
        current = nft_fail2ban_signature(nft_objects(system_command(["nft", "-j", "list", "ruleset"]).stdout))
        if signature <= current:
            return
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    raise ValueError("Fail2ban preservation not verified; inspect its status before retrying / 未确认原有 Fail2ban 封禁结构保留，请先检查其状态后重试")


def iptables_conflict(text):
    table = "?"
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line == "COMMIT":
            continue
        if line.startswith("*"):
            table = netfilter_label(line[1:])
            continue
        fields = line.split()
        if line.startswith(":") and len(fields) == 3 and fields[1] in ("ACCEPT", "-") and re.fullmatch(r"\[[0-9]+:[0-9]+\]", fields[2]):
            # With no rules anywhere, an unreferenced empty user chain has no effect.
            continue
        if line.startswith(":"):
            return table + "/" + netfilter_label(fields[0][1:]) + " policy=" + netfilter_label(fields[1] if len(fields) > 1 else "unknown")
        if line.startswith("-A ") and len(fields) >= 2:
            return "rule " + table + "/" + netfilter_label(fields[1])
        return "unrecognized entry / 无法识别条目 " + table
    return None


def firewall_setup_check():
    status = firewall_status()
    if status["firewalld"] == "active" or status["ufw"] == "active":
        raise ValueError("A firewall is already active; use the port allow menu / 已有防火墙启用，请使用端口放行菜单，不重复初始化")
    preserved = set()
    # Preserve a validated independent Fail2ban input chain; guard all other rules.
    for command in ("nft", "iptables-save", "ip6tables-save", "iptables-legacy-save", "ip6tables-legacy-save"):
        if not shutil.which(command):
            continue
        args = [command, "-j", "list", "ruleset"] if command == "nft" else [command]
        try:
            rules = system_command(args).stdout
        except (OSError, subprocess.SubprocessError):
            raise ValueError("Cannot inspect " + command + "; UFW setup stopped / 无法检查 " + command + "，已停止 UFW 初始化，请检查权限与内核支持") from None
        if command == "nft":
            conflict, preserved = nft_inspect(rules)
        else:
            conflict = iptables_conflict(rules)
        if conflict:
            raise ValueError("Existing netfilter state: " + command + " / " + conflict +
                             "; inspect it before enabling UFW / 检测到已有规则或策略，来源如上；请先核对，不自动清空或覆盖")
    return preserved


def firewall_setup_plan(root, ssh_ports, extra_ports):
    ssh = {port(number) for number in ssh_ports}
    if not ssh:
        raise ValueError("Confirm at least one SSH TCP port / 必须确认至少一个 SSH TCP 端口")
    connection = os.environ.get("SSH_CONNECTION", "")
    if connection:
        fields = connection.split()
        if len(fields) != 4:
            raise ValueError("Cannot identify current SSH port / 无法识别当前 SSH 连接端口")
        ipaddress.ip_address(fields[0]); ipaddress.ip_address(fields[2])
        ssh.add(port(fields[3]))
    nodes = set()
    root = checked_path(root)
    if root.exists():
        ensure_owned(root)
        nodes = {node["port"] for node in load_state(root)["nodes"].values()}
    return sorted(ssh), sorted((nodes | {port(number) for number in extra_ports}) - ssh)


def firewall_setup(root, ssh_ports, extra_ports, config=Path("/etc/default/ufw")):
    ssh, others = firewall_setup_plan(root, ssh_ports, extra_ports)
    preserved = firewall_setup_check()
    if not shutil.which("ufw"):
        raise ValueError("Install UFW first / 请先安装 UFW")
    text = checked_path(config).read_text()
    values = re.findall(r'^\s*IPV6=["\']?(yes|no)["\']?\s*$', text, re.MULTILINE)
    if values != ["yes"]:
        raise ValueError("UFW requires IPV6=yes; inspect /etc/default/ufw / 请先核对 /etc/default/ufw 并设置 IPV6=yes，避免遗漏 IPv6 防护")
    added = ufw_command(["show", "added"]).stdout
    if re.search(r'^ufw\s+(?:deny|reject|limit|route|insert|prepend)\b', added, re.MULTILINE):
        raise ValueError("Existing restrictive UFW rules require manual review / 已有拒绝、限速或路由 UFW 规则，请手动核对后启用")
    # Stage SSH allows first while inactive; never assume SSH uses port 22.
    for number in ssh + others:
        ufw_command(["prepend", "allow", "in", "proto", "tcp", "to", "any", "port", str(number)])
    ufw_command(["default", "deny", "incoming"])
    ufw_command(["default", "allow", "outgoing"])
    try:
        ufw_command(["--force", "enable"])
        if firewall_status()["ufw"] != "active":
            raise ValueError("UFW did not become active / UFW 未成功启用")
        verify_fail2ban_preserved(preserved)
    except BaseException as error:
        try:
            ufw_command(["--force", "disable"])
            if firewall_status()["ufw"] != "inactive":
                raise ValueError("UFW still active")
            verify_fail2ban_preserved(preserved)
        except (OSError, ValueError, subprocess.SubprocessError):
            raise ValueError("UFW enable/rollback incomplete; check UFW and Fail2ban from provider console / UFW 启用或回退未完成，请通过服务商控制台检查 UFW 与 Fail2ban 状态；配置文件保留") from error
        raise
    return bool(preserved)


BBR_VALUES = {"net.core.default_qdisc": "fq", "net.ipv4.tcp_congestion_control": "bbr"}
BBR_MARK = "# SKYBYTE Xray Manager BBR v1\n"
BBR_PATH = Path("/etc/sysctl.d/90-skybyte-xray-bbr.conf")


def network_values():
    result = {}
    for setting in BBR_VALUES:
        value = system_command(["sysctl", "-n", setting]).stdout.strip()
        if not re.fullmatch(r"[A-Za-z0-9_]+", value):
            raise ValueError("Invalid kernel network value / 内核网络参数无效")
        result[setting] = value
    return result


def bbr_content(previous):
    if set(previous) != set(BBR_VALUES) or any(not isinstance(v, str) or not re.fullmatch(r"[A-Za-z0-9_]+", v) for v in previous.values()):
        raise ValueError("Invalid saved network settings / 原网络设置无效")
    return BBR_MARK + "# previous: " + json.dumps(previous, sort_keys=True) + "\n" + "".join(k + " = " + v + "\n" for k, v in BBR_VALUES.items())


def bbr_previous(path):
    checked_path(path)
    if not path.exists():
        return None
    text = path.read_text()
    if not text.startswith(BBR_MARK + "# previous: "):
        raise ValueError("Existing BBR file is not owned / 已有 BBR 配置不属于本脚本")
    previous = json.loads(text.splitlines()[1].removeprefix("# previous: "))
    if text != bbr_content(previous):
        raise ValueError("BBR file was edited; restore it before continuing / BBR 配置已被修改，请先核对恢复")
    return previous


def write_network_values(values):
    for setting, value in values.items():
        system_command(["sysctl", "-w", setting + "=" + value])
    if network_values() != values:
        raise ValueError("Kernel settings did not take effect / 内核设置未生效")


def rollback_network_values(values):
    # Attempt both settings even when one cannot be restored.
    failed = False
    for setting, value in values.items():
        try:
            system_command(["sysctl", "-w", setting + "=" + value])
        except (OSError, subprocess.SubprocessError):
            failed = True
    return not failed and network_values() == values


def bbr_change(enable, path=BBR_PATH):
    path = checked_path(path)
    previous = bbr_previous(path)
    current = network_values()
    if enable:
        available = system_command(["sysctl", "-n", "net.ipv4.tcp_available_congestion_control"]).stdout.split()
        if "bbr" not in available:
            if shutil.which("modprobe"):
                system_command(["modprobe", "tcp_bbr"], check=False)
            available = system_command(["sysctl", "-n", "net.ipv4.tcp_available_congestion_control"]).stdout.split()
        if "bbr" not in available:
            raise ValueError("Kernel does not provide BBR; no kernel upgrade performed / 当前内核不支持 BBR；未更换内核")
        if shutil.which("modprobe"):
            system_command(["modprobe", "sch_fq"], check=False)
        old_file = path.read_text() if previous is not None else None
        # Persist original values before touching the runtime, for recovery after interruption.
        write_private(path, bbr_content(previous if previous is not None else current), 0o644)
        target = BBR_VALUES
    else:
        if previous is None:
            raise ValueError("No managed BBR settings to restore / 没有本脚本管理的 BBR 设置可恢复")
        old_file = path.read_text()
        target = previous
    try:
        write_network_values(target)
        if not enable:
            path.unlink()
    except BaseException as error:
        try:
            restored = rollback_network_values(current)
        except (OSError, ValueError, subprocess.SubprocessError):
            restored = False
        if not restored:
            raise ValueError("Network rollback incomplete; saved BBR file retained for recovery / 网络参数回退未完成，已保留 BBR 文件，请检查 sysctl") from error
        if old_file is None:
            path.unlink()
        else:
            write_private(path, old_file, 0o644)
        raise


MANAGER_REPO = "skylink9119/skybyte-xray-manager"
MANAGER_HEADER = b"#!/usr/bin/env bash\n# SKYBYTE Xray Manager standalone;"
MAX_MANAGER = 2 * 1024 * 1024


def manager_version(tag):
    if not isinstance(tag, str) or not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ValueError("Invalid manager version / 管理脚本版本无效")
    return tuple(map(int, tag[1:].split(".")))


def manager_release(tag=None):
    if tag is not None:
        manager_version(tag)
    endpoint = "latest" if tag is None else "tags/" + tag
    request = urllib.request.Request("https://api.github.com/repos/" + MANAGER_REPO + "/releases/" + endpoint,
                                     headers={"User-Agent": "SKYBYTE-Xray-Manager", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read(MAX_MANAGER + 1)
    if len(data) > MAX_MANAGER:
        raise ValueError("Release metadata too large / 发布信息过大")
    metadata = json.loads(data)
    actual = metadata.get("tag_name")
    manager_version(actual)
    if metadata.get("draft") or metadata.get("prerelease") or (tag is not None and actual != tag):
        raise ValueError("Not the requested stable manager release / 不是指定的正式管理脚本发布")
    return metadata


def manager_asset(metadata, filename):
    assets = [asset for asset in metadata["assets"] if asset.get("name") == filename]
    if len(assets) != 1:
        raise ValueError("Manager release asset missing or duplicated / 管理脚本发布附件缺失或重复")
    asset = assets[0]
    expected_url = "https://github.com/" + MANAGER_REPO + "/releases/download/" + metadata["tag_name"] + "/" + filename
    if asset.get("browser_download_url") != expected_url:
        raise ValueError("Unexpected manager download URL / 管理脚本下载地址异常")
    digest = asset.get("digest", "")
    if not re.fullmatch(r"sha256:[a-f0-9]{64}", digest):
        raise ValueError("Manager release SHA256 unavailable / 管理脚本官方 SHA256 不可用")
    with urllib.request.urlopen(expected_url, timeout=120) as response:
        payload = response.read(MAX_MANAGER + 1)
    if len(payload) > MAX_MANAGER or "sha256:" + hashlib.sha256(payload).hexdigest() != digest:
        raise ValueError("Manager release SHA256 mismatch / 管理脚本发布 SHA256 校验失败")
    return payload


def manager_target(target):
    target = checked_path(target)
    if target.name != "manager.sh":
        raise ValueError("Update the installed manager.sh only / 仅支持更新已安装的 manager.sh")
    marker = checked_path(target.parent / ".owner")
    if not marker.is_file() or marker.read_text() != OWNER:
        raise ValueError("Manager is not installed here; use install.sh first / 此目录不是已安装的管理器，请先运行 install.sh")
    backup = checked_path(target.parent / "manager.previous.sh")
    for path in (target, backup):
        if path.exists() and (not path.is_file() or not path.read_bytes().startswith(MANAGER_HEADER)):
            raise ValueError("Existing manager/backup is not owned / 已有脚本或备份不属于本管理器")
    if not target.is_file():
        raise ValueError("Installed manager missing / 已安装的管理脚本缺失")
    return target, backup


def check_manager(path, tag):
    system_command(["bash", "-n", str(path)])
    version = system_command(["bash", str(path), "--version"]).stdout.strip()
    selfcheck = system_command(["bash", str(path), "--self-check"]).stdout.strip()
    if version != "SKYBYTE Xray Manager " + tag[1:] or selfcheck != version + " OK":
        raise ValueError("Manager version/self-check mismatch / 管理脚本版本或自检不符")


def manager_update(target, tag):
    if manager_version(tag) <= manager_version("v" + VERSION):
        raise ValueError("Manager downgrade/reinstall refused / 不更新到相同或更旧的管理脚本版本")
    target, backup = manager_target(target)
    old = target.read_bytes()
    installed = re.findall(rb"^VERSION=([0-9]+\.[0-9]+\.[0-9]+)$", old, re.MULTILINE)
    if len(installed) != 1 or manager_version(tag) <= manager_version("v" + installed[0].decode("ascii")):
        raise ValueError("Installed manager is newer or its version is unknown / 已安装脚本版本较新或无法识别，不覆盖")
    metadata = manager_release(tag)
    manifest = manager_asset(metadata, "SHA256SUMS").decode("utf-8")
    checksums = []
    for line in manifest.splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[1] == "xray-manager.sh":
            checksums.append(fields[0])
    if len(checksums) != 1 or not re.fullmatch(r"[a-f0-9]{64}", checksums[0]):
        raise ValueError("Invalid manager checksum manifest / 管理脚本校验清单无效")
    payload = manager_asset(metadata, "xray-manager.sh")
    if hashlib.sha256(payload).hexdigest() != checksums[0] or not payload.startswith(MANAGER_HEADER):
        raise ValueError("Manager payload mismatch / 管理脚本内容校验失败")
    descriptor, filename = tempfile.mkstemp(prefix=".manager-update-", dir=target.parent)
    os.close(descriptor)
    candidate = Path(filename)
    try:
        write_private(candidate, payload, 0o700)
        # Only the verified release payload is executed for its built-in diagnostics.
        check_manager(candidate, tag)
        write_private(backup, old, 0o700)
        write_private(target, payload, 0o700)
        try:
            check_manager(target, tag)
        except BaseException as error:
            try:
                write_private(target, old, 0o700)
            except OSError:
                raise ValueError("Manager rollback incomplete; restore manager.previous.sh / 脚本回退未完成，请从 manager.previous.sh 恢复") from error
            raise
    finally:
        candidate.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["selfcheck", "overview", "warp-prepare", "warp-check", "warp-profile", "warp-status", "prepare", "commit", "rollback", "finalize", "backup", "restore",
                                            "ipv6-prepare", "remove", "rename", "edit", "reality-edit", "reality-targets", "refresh-tls", "show", "parameters", "guard", "download", "probe", "reality-input", "tls-input", "journal", "preflight", "node-kinds", "node-port", "node-ports", "firewall-status", "firewall-allow", "bbr-status", "bbr-enable", "bbr-restore", "manager-latest", "manager-update", "firewall-setup-check", "firewall-setup-plan", "firewall-setup", "ufw-state", "ufw-disable", "ufw-remove-plan", "ufw-package-state"])
    parser.add_argument("--root", default=os.environ.get("SKYBYTE_XRAY_DIR", "/etc/skybyte-xray"))
    parser.add_argument("--binary", default=os.environ.get("SKYBYTE_XRAY_BINARY", "/usr/local/lib/skybyte-xray/xray"))
    parser.add_argument("--unit", default=os.environ.get("SKYBYTE_XRAY_UNIT", "/etc/systemd/system/skybyte-xray.service"))
    parser.add_argument("--kind", choices=KINDS)
    parser.add_argument("--port", default=None)
    parser.add_argument("--listen", choices=["0.0.0.0", "::", "127.0.0.1", "::1"], default="0.0.0.0")
    parser.add_argument("--address", default=None)
    parser.add_argument("--sni", default="www.microsoft.com")
    parser.add_argument("--target", default="www.microsoft.com:443")
    parser.add_argument("--name", default="SKYBYTE")
    parser.add_argument("--path", default=None)
    parser.add_argument("--mode", choices=MODES, default="auto")
    parser.add_argument("--cert", default="")
    parser.add_argument("--key", default="")
    parser.add_argument("--ca-file", default=None)
    parser.add_argument("--cdn", action="store_true")
    parser.add_argument("--stage", default="")
    parser.add_argument("--file", default="")
    parser.add_argument("--active", action="store_true")
    parser.add_argument("--enabled", action="store_true")
    parser.add_argument("--asset", default="Xray-linux-64.zip")
    parser.add_argument("--tag", default=CORE_VERSION)
    parser.add_argument("--ports", nargs="+", default=[])
    parser.add_argument("--zone", default="")
    parser.add_argument("--release", default="")
    parser.add_argument("--ssh-ports", nargs="+", default=[])
    parser.add_argument("--purge", action="store_true")
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--language", choices=["zh", "en"], default="zh")
    parser.add_argument("--proxy-port", type=int, default=40000)
    parser.add_argument("--domains", nargs="+", default=[])
    parser.add_argument("--profile", choices=["all", *WARP_PROFILES], default="all")
    parser.add_argument("--disable", action="store_true")
    options = parser.parse_args()
    if options.command == "parameters":
        print(node_parameters(checked_path(options.root), options.language))
        return
    if options.command == "overview":
        print(startup_overview(Path(options.root), Path(options.binary), options.language))
        return
    if options.command == "warp-profile":
        print(" ".join(WARP_PROFILES[options.profile] if options.profile != "all" else sum(WARP_PROFILES.values(), [])))
        return
    if options.command == "warp-check":
        ip, country = warp_verify(options.proxy_port)
        print(f"WARP 出口已验证 / WARP egress verified: {ip} ({country})")
        return
    if options.command == "warp-status":
        print(warp_status(Path(options.root), options.language))
        return
    if options.command != "edit":
        options.port = options.port if options.port is not None else "443"
        options.address = options.address if options.address is not None else ""
        options.path = options.path if options.path is not None else ""
    if options.command == "ufw-state":
        print(ufw_state())
        return
    if options.command == "ufw-disable":
        print(ufw_disable())
        return
    if options.command == "ufw-package-state":
        print(ufw_package_state())
        return
    if options.command == "ufw-remove-plan":
        print(ufw_remove_plan(options.purge))
        return
    if options.command == "firewall-setup-check":
        if firewall_setup_check():
            print("Compatible Fail2ban TCP bans detected; will preserve them / 检测到可共存的独立 Fail2ban TCP 封禁，将保留现有防护与封禁地址")
        return
    if options.command == "firewall-setup-plan":
        ssh, others = firewall_setup_plan(Path(options.root), options.ssh_ports, options.ports)
        print("SSH TCP: " + ", ".join(map(str, ssh)))
        print("Other TCP / 其他 TCP: " + (", ".join(map(str, others)) or "none / 无"))
        return
    if options.command == "firewall-setup":
        if firewall_setup(Path(options.root), options.ssh_ports, options.ports):
            print("Fail2ban structure preserved; existing bans still apply / 已核对原有 Fail2ban 封禁结构仍在；已有封禁仍可能阻止连接")
        return
    if options.command == "manager-latest":
        tag = manager_release()["tag_name"]
        if manager_version(tag) > manager_version("v" + VERSION):
            print(tag)
        return
    if options.command == "manager-update":
        manager_update(checked_path(options.file), options.release)
        return
    if options.command in ("node-ports", "node-port", "node-kinds"):
        root = checked_path(options.root)
        ensure_owned(root)
        nodes = load_state(root)["nodes"]
        if options.command == "node-port":
            if options.kind not in nodes:
                raise ValueError("该协议尚未安装 / Protocol not installed")
            print(nodes[options.kind]["port"])
            return
        if not nodes:
            raise ValueError("No nodes installed / 尚未安装节点")
        if options.command == "node-kinds":
            print("\n".join(nodes))
            return
        for kind, node in nodes.items():
            print(node["name"] + " | " + kind + " | TCP " + str(node["port"]))
        return
    if options.command == "firewall-status":
        labels = {"active": "active / 已启用", "inactive": "inactive / 未启用", "unavailable": "unavailable / 未安装"}
        for backend, status in firewall_status().items():
            print(backend + ": " + labels[status])
        if shutil.which("firewall-cmd") and system_command(["firewall-cmd", "--state"], check=False).returncode == 0:
            print("Default zone / 默认区域: " + system_command(["firewall-cmd", "--get-default-zone"]).stdout.strip())
            print(system_command(["firewall-cmd", "--get-active-zones"]).stdout.strip())
        if shutil.which("ufw"):
            print(ufw_command(["status", "verbose"]).stdout.strip())
        return
    if options.command == "firewall-allow":
        numbers = options.ports
        if not numbers:
            root = checked_path(options.root)
            ensure_owned(root)
            numbers = [node["port"] for node in load_state(root)["nodes"].values()]
        print(firewall_allow(numbers, options.zone))
        return
    if options.command == "bbr-status":
        current = network_values()
        enabled = current["net.ipv4.tcp_congestion_control"] == "bbr"
        summary = "已开启 BBR 加速 / BBR acceleration enabled" if enabled else "未开启 BBR 加速 / BBR acceleration not enabled"
        color, reset = "", ""
        if sys.stdout.isatty() and not os.environ.get("NO_COLOR"):
            color, reset = ("\033[1;32m" if enabled else "\033[1;33m"), "\033[0m"
        print("\n" + color + "===== " + summary + " =====" + reset + "\n")
        print("当前拥塞控制 / Current algorithm: " + current["net.ipv4.tcp_congestion_control"])
        print("当前默认队列 / Default qdisc: " + current["net.core.default_qdisc"])
        print("可用算法 / Available algorithms: " + system_command(["sysctl", "-n", "net.ipv4.tcp_available_congestion_control"]).stdout.strip())
        print("本脚本管理 / Managed by this manager: " + ("是 / yes" if bbr_previous(BBR_PATH) is not None else "否 / no"))
        return
    if options.command in ("bbr-enable", "bbr-restore"):
        bbr_change(options.command == "bbr-enable")
        return
    if options.command == "selfcheck":
        print("SKYBYTE Xray Manager " + VERSION + " OK")
        return
    if options.command == "preflight":
        installation_preflight(options)
        return
    if options.command == 'reality-input':
        domain(options.sni)
        host, number = options.target.rsplit(':', 1)
        domain(host)
        port(number)
        return
    if options.command == 'tls-input':
        certificate(options.cert, options.key, options.sni, options.ca_file)
        return
    if options.command == "download":
        download_binary(checked_path(options.file), options.asset, options.tag)
        return
    if options.command == "probe":
        host, number = options.target.rsplit(":", 1)
        context = ssl.create_default_context()
        context.minimum_version = ssl.TLSVersion.TLSv1_3
        context.set_alpn_protocols(["h2"])
        with socket.create_connection((domain(host), port(number)), timeout=10) as connection:
            with context.wrap_socket(connection, server_hostname=domain(options.sni)) as secure:
                if secure.selected_alpn_protocol() != "h2":
                    raise ValueError("Target does not negotiate HTTP/2 / 握手目标不支持 HTTP/2")
                print(secure.version() + " / h2")
        return
    root, binary, unit = map(checked_path, (options.root, options.binary, options.unit))
    if options.command == "guard":
        unit_guard(unit)
        ensure_owned(root, create=True)
    elif options.command == "prepare":
        if not options.kind:
            raise ValueError("Protocol required")
        print(prepare(root, binary, options))
    elif options.command == "warp-prepare":
        print(warp_prepare(root, binary, options.proxy_port, options.domains, options.disable))
    elif options.command == "ipv6-prepare":
        ensure_owned(root)
        state = ipv6_state(load_state(root), None if options.disable else options.address)
        stage = make_stage(root, state)
        try:
            finish_stage(stage, state, binary)
            print(stage)
        except BaseException:
            shutil.rmtree(stage)
            raise
    elif options.command == "commit":
        commit(root, Path(options.stage), binary, unit, options.active, options.enabled)
    elif options.command == "rollback":
        print(json_text(rollback(root, unit)))
    elif options.command == "journal":
        ensure_owned(root)
        print((root / ".transaction" / "meta.json").read_text())
    elif options.command == "finalize":
        finalize(root, Path(options.stage))
    elif options.command == "backup":
        backup(root, Path(options.file))
    elif options.command == "restore":
        print(restore_stage(root, binary, Path(options.file), options.ca_file))
    elif options.command == 'reality-targets':
        ensure_owned(root)
        for kind, node in load_state(root)['nodes'].items():
            if kind != 'xhttp-tls':
                print('\t'.join((kind, node['target'], node['sni'])))
    elif options.command == "show":
        ensure_owned(root)
        for kind, node in load_state(root)["nodes"].items():
            print(node["name"] + " | " + kind + " | TCP " + str(node["port"]))
            print(node_uri(kind, node))
            if 'ipv6_backup' in node:
                print(node_uri(kind, ipv6_node(node)))
    else:
        ensure_owned(root)
        state = copy.deepcopy(load_state(root))
        if options.kind not in state["nodes"]:
            raise ValueError("Protocol not installed / 协议未安装")
        if options.command == "remove":
            del state["nodes"][options.kind]
        elif options.command == "rename":
            state["nodes"][options.kind]["name"] = name(options.name)
        elif options.command == "edit":
            state = edit_state(state, options.kind, options.address, options.port, options.path)
        elif options.command == 'reality-edit':
            state = edit_reality(state, options.kind, options.sni, options.target)
            if options.check_only:
                return
        elif options.command == "refresh-tls":
            if options.kind != "xhttp-tls":
                raise ValueError("TLS protocol required")
            node = state["nodes"][options.kind]
            certificate(options.cert, options.key, node["sni"], options.ca_file)
        stage = make_stage(root, state)
        try:
            if options.command == "refresh-tls":
                write_private(stage / node["cert"], Path(options.cert).read_bytes())
                write_private(stage / node["key"], Path(options.key).read_bytes())
            finish_stage(stage, state, binary)
            print(stage)
        except BaseException:
            shutil.rmtree(stage)
            raise


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.SubprocessError, ssl.SSLError, tarfile.TarError,
            zipfile.BadZipFile, TypeError, AttributeError) as error:
        print(error_message(error), file=sys.stderr)
        sys.exit(1)

SKYBYTE_PYTHON
}


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
  case $readiness in
   ipv6) ipv6_engine ready || return 1;;
   ipv6-install:*) ipv6_engine ready-install "${readiness#*:}" || return 1;;
  esac
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
"""Bounded installation diagnostics: no package, firewall or configuration changes."""
import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import platform
import queue
import shutil
import socket
import ssl
import stat
import subprocess
import sys
import threading
import urllib.error
import urllib.request


class Report:
    def __init__(self, english=False):
        self.english = english
        self.items = []

    def tr(self, zh, en):
        return en if self.english else zh

    def add(self, status, zh, en, detail_zh, detail_en=None):
        self.items.append((status, self.tr(zh, en),
                           self.tr(detail_zh, detail_en if detail_en is not None else detail_zh)))

    def render(self):
        def clean(value):
            return json.dumps(str(value), ensure_ascii=False)[1:-1]
        print(self.tr('\n========== 节点安装前检测 ==========', '\n========== NODE INSTALLATION CHECK =========='))
        for status, label, detail in self.items:
            title = {'pass': self.tr('通过', 'PASS'), 'warn': self.tr('提醒', 'WARN'), 'fail': self.tr('失败', 'FAIL')}[status]
            print('[' + title + '] ' + clean(label) + ': ' + clean(detail))
        failed = any(item[0] == 'fail' for item in self.items)
        warnings = sum(item[0] == 'warn' for item in self.items)
        summary = self.tr('检测未通过：请先处理失败项，停止本次安装。', 'FAILED: resolve failed checks before installing.') if failed else self.tr(
            '本阶段检测通过；请核对提醒项。', 'This stage passed; review any warnings.')
        color = ('\033[1;31m' if failed else '\033[1;32m') if sys.stdout.isatty() and not os.environ.get('NO_COLOR') else ''
        print(color + '===== ' + summary + ' =====' + ('\033[0m' if color else ''))
        print(self.tr('提醒数量：', 'Warnings: ') + str(warnings))
        print(self.tr('仅检测本 VPS；端口可绑定不代表公网可达。云安全组、NAT 映射和客户端连接须另行核对。',
                      'Checks this VPS only. A bindable port is not proof of public reachability; inspect provider rules, NAT mappings and client access.'))
        return int(failed)


def package_locks(paths):
    """APT/dpkg use POSIX record locks; an existing unlocked file is normal."""
    busy, unknown = [], []
    for path in map(Path, paths):
        fd = None
        try:
            if path.is_symlink():
                unknown.append(str(path))
                continue
            fd = os.open(path, os.O_RDWR | getattr(os, 'O_NOFOLLOW', 0))
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                unknown.append(str(path))
                continue
            fcntl.lockf(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.lockf(fd, fcntl.LOCK_UN)
        except FileNotFoundError:
            pass
        except OSError as error:
            if error.errno in (errno.EACCES, errno.EAGAIN) and fd is not None:
                busy.append(str(path))
            else:
                unknown.append(str(path))
        finally:
            if fd is not None:
                os.close(fd)
    return busy, unknown


def environment(report, project, os_release='/etc/os-release', paths=(), reality=False):
    report.add('pass' if os.geteuid() == 0 else 'fail', '运行权限', 'Privileges',
               'root' if os.geteuid() == 0 else '请以 root 账户运行',
               'root' if os.geteuid() == 0 else 'Run as root')
    distro = ''
    try:
        for line in Path(os_release).read_text().splitlines():
            if line.startswith('ID='):
                distro = line.split('=', 1)[1].strip().strip('"\'')
    except OSError:
        pass
    supported = platform.system() == 'Linux' and distro in ('ubuntu', 'debian')
    report.add('pass' if supported else 'fail', '系统支持', 'Operating system',
               'Linux / ' + distro if supported else '需要 Ubuntu/Debian Linux；检测到：' + (distro or platform.system()),
               'Linux / ' + distro if supported else 'Ubuntu/Debian Linux required; detected: ' + (distro or platform.system()))
    architectures = {'x86_64', 'aarch64', 'arm64'}
    if project == 'sing-box':
        architectures |= {'i386', 'i486', 'i586', 'i686', 'armv7l'}
    machine = platform.machine()
    report.add('pass' if machine in architectures else 'fail', '核心架构', 'Core architecture', machine)
    systemd = Path('/run/systemd/system').is_dir()
    report.add('pass' if systemd else 'fail', 'systemd', 'systemd',
               '可用' if systemd else '未发现正在运行的 systemd；无法安装托管服务',
               'Available' if systemd else 'Running systemd not found; managed services cannot be installed')
    if reality:
        report.add('pass' if ssl.HAS_TLSv1_3 else 'fail', 'Python TLS 1.3', 'Python TLS 1.3',
                   '支持握手目标检测' if ssl.HAS_TLSv1_3 else 'Python/OpenSSL 不支持 TLS 1.3，请先升级系统依赖',
                   'Target checks supported' if ssl.HAS_TLSv1_3 else 'Upgrade system Python/OpenSSL for TLS 1.3 target checks')
    busy, unknown = package_locks(['/var/lib/dpkg/lock-frontend', '/var/lib/dpkg/lock',
                                   '/var/lib/apt/lists/lock', '/var/cache/apt/archives/lock'])
    if busy:
        report.add('fail', 'APT/DPKG 锁', 'APT/DPKG locks',
                   '其他软件安装任务正在占用：' + ', '.join(busy) + '；等待任务完成后重试，请勿删除锁文件。',
                   'Another package task holds: ' + ', '.join(busy) + '; wait for it to finish. Do not delete lock files.')
    elif unknown:
        report.add('warn', 'APT/DPKG 锁', 'APT/DPKG locks',
                   '无法确认锁状态，请检查权限或异常路径：' + ', '.join(unknown),
                   'Cannot inspect locks; check permissions or unsafe paths: ' + ', '.join(unknown))
    else:
        report.add('pass', 'APT/DPKG 锁', 'APT/DPKG locks', '当前未被占用', 'Currently available')
    missing = [tool for tool in ('apt-get', 'curl', 'openssl', 'ss', 'ip', 'flock') if not shutil.which(tool)]
    report.add('fail' if 'apt-get' in missing else 'warn' if missing else 'pass', '依赖命令', 'Dependency commands',
               '缺少或不在 PATH：' + ', '.join(missing) + '；请核对 root PATH，安装流程会补齐可安装的依赖。' if missing else '所需命令可用',
               'Missing or outside PATH: ' + ', '.join(missing) + '; inspect root PATH; installation will add available dependencies.' if missing else 'Required commands available')
    seen = set()
    for destination in map(Path, paths):
        current = destination
        while not current.exists() and current != current.parent:
            current = current.parent
        if any(p.is_symlink() for p in (destination, *destination.parents)):
            report.add('fail', '安装路径', 'Installation path', '路径包含符号链接：' + str(destination),
                       'Path contains a symlink: ' + str(destination))
            continue
        try:
            device = current.stat().st_dev
            if device in seen:
                continue
            seen.add(device)
            info = os.statvfs(current)
            free = info.f_bavail * info.f_frsize // (1024 * 1024)
            blocked = bool(info.f_flag & getattr(os, 'ST_RDONLY', 1)) or info.f_favail == 0 or info.f_bavail == 0
            report.add('fail' if blocked else 'warn' if free < 256 else 'pass', '安装存储空间', 'Installation storage',
                       str(current) + '：可用 ' + str(free) + ' MiB' + ('；空间/inode 已耗尽或文件系统只读' if blocked else '；低于 256 MiB，建议先清理' if free < 256 else ''),
                       str(current) + ': ' + str(free) + ' MiB free' + ('; storage/inodes exhausted or filesystem read-only' if blocked else '; below 256 MiB, free space before installing' if free < 256 else ''))
        except OSError:
            report.add('fail', '安装存储空间', 'Installation storage', '无法检查：' + str(destination), 'Cannot inspect: ' + str(destination))


def ports(report, listen, tcp=None, udp=None):
    if tcp is None and udp is None:
        raise ValueError('Port required')
    family = socket.AF_INET6 if ':' in listen else socket.AF_INET
    for protocol, number, kind in (('TCP', tcp, socket.SOCK_STREAM), ('UDP', udp, socket.SOCK_DGRAM)):
        if number is None:
            continue
        if not 1 <= number <= 65535:
            raise ValueError('Invalid port')
        label = protocol + ' ' + str(number)
        try:
            with socket.socket(family, kind) as sock:
                if kind == socket.SOCK_STREAM:
                    # Match server binds: TCP TIME_WAIT is reusable, active listeners are not.
                    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                if family == socket.AF_INET6:
                    sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
                sock.bind((listen, number))
            report.add('pass', label, label, '本机可绑定（' + listen + '）', 'Locally bindable (' + listen + ')')
        except OSError as error:
            occupied = error.errno == errno.EADDRINUSE
            report.add('fail', label, label,
                       '已被占用，请选择其他空闲端口；TCP 与 UDP 分别检查。' if occupied else '无法绑定该地址族/端口，请检查 IPv4/IPv6 与系统权限。',
                       'Occupied; choose another free port. TCP and UDP are checked separately.' if occupied else 'Cannot bind; check IPv4/IPv6 support and privileges.')
    active = []
    for executable, arguments, token in [('ufw', ['status'], 'Status: active'), ('firewall-cmd', ['--state'], 'running')]:
        if not shutil.which(executable):
            continue
        try:
            result = subprocess.run([executable, *arguments], capture_output=True, text=True, timeout=3,
                                    env={**os.environ, 'LC_ALL': 'C'})
            if result.returncode == 0 and token in result.stdout:
                active.append(executable)
        except (OSError, subprocess.SubprocessError):
            pass
    report.add('warn', '防火墙与公网端口', 'Firewall and public ports',
               ('已启用 ' + ', '.join(active) + '；' if active else '未确认已启用 UFW/firewalld，请安装/启用合适的防火墙；') + '先放行 SSH 和实际 TCP/UDP 端口，并核对云安全组；不自动修改规则。',
               ('Active: ' + ', '.join(active) + '. ' if active else 'Active UFW/firewalld not confirmed; install/enable a suitable firewall. ') + 'Allow SSH and actual TCP/UDP ports, and inspect provider rules; rules are not changed.')


def download(report, offline=False, timeout=10, existing_core=False):
    if offline or existing_core:
        report.add('warn', 'GitHub HTTPS', 'GitHub HTTPS',
                   '本机已有核心，本次沿用，跳过不必要的下载联网检测' if existing_core else '离线安装包模式，跳过联网检测',
                   'Existing local core will be reused; unnecessary download/network check skipped' if existing_core else 'Offline asset mode; network check skipped')
        return
    try:
        results = queue.Queue()
        opener = urllib.request.urlopen
        def request_head():
            try:
                request = urllib.request.Request('https://github.com/', method='HEAD', headers={'User-Agent': 'SKYBYTE-Installation-Check'})
                with opener(request, timeout=min(8, timeout), context=ssl.create_default_context()) as response:
                    if not 200 <= response.status < 400:
                        raise urllib.error.HTTPError(request.full_url, response.status, '', {}, None)
                results.put(None)
            except Exception as error:
                results.put(error)
        # Socket timeouts alone do not bound libc DNS resolution.
        threading.Thread(target=request_head, daemon=True).start()
        try:
            error = results.get(timeout=timeout)
        except queue.Empty:
            raise TimeoutError('HTTPS deadline') from None
        if error is not None:
            raise error
        report.add('pass', 'GitHub HTTPS', 'GitHub HTTPS', '首页 HTTPS 与证书验证通过；正式下载仍需校验 API/CDN 与文件摘要',
                   'Homepage HTTPS and certificate verified; downloads still require API/CDN access and digest checks')
    except (OSError, urllib.error.URLError, ValueError) as error:
        reason = getattr(error, 'reason', error)
        if isinstance(reason, ssl.SSLCertVerificationError):
            zh, en = '证书验证失败，请检查 VPS 时间、CA 证书与 HTTPS 拦截', 'Certificate verification failed; check VPS clock, CA roots and HTTPS interception'
        elif isinstance(reason, (TimeoutError, socket.timeout)):
            zh, en = '连接超时，请检查 VPS 出站网络或使用离线安装包', 'Connection timed out; inspect egress connectivity or use offline assets'
        elif isinstance(reason, socket.gaierror):
            zh, en = 'DNS 解析失败，请先修复 VPS DNS', 'DNS lookup failed; repair VPS DNS first'
        elif isinstance(error, urllib.error.HTTPError):
            zh, en = 'HTTP ' + str(error.code) + '，请检查访问限制或限流', 'HTTP ' + str(error.code) + '; check access restrictions or rate limits'
        else:
            zh, en = 'HTTPS 连接失败，请检查出站网络、DNS 与系统时间', 'HTTPS connection failed; inspect egress, DNS and system clock'
        status = 'warn' if isinstance(error, urllib.error.HTTPError) and error.code in (403, 405, 429) else 'fail'
        if status == 'warn':
            zh += '；首页响应不等于发布附件可用性，将由正式下载与摘要校验确认。'
            en += '; homepage status does not establish release-asset availability; verified download will decide.'
        report.add(status, 'GitHub HTTPS', 'GitHub HTTPS', zh, en)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', choices=('sing-box', 'xray'), required=True)
    parser.add_argument('--phase', choices=('environment', 'ports', 'download'), required=True)
    parser.add_argument('--language', default='zh')
    parser.add_argument('--os-release', default='/etc/os-release')
    parser.add_argument('--paths', nargs='*', default=[])
    parser.add_argument('--reality', action='store_true')
    parser.add_argument('--listen', choices=('0.0.0.0', '::', '127.0.0.1', '::1'), default='0.0.0.0')
    parser.add_argument('--tcp-port', type=int)
    parser.add_argument('--udp-port', type=int)
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--existing-core', action='store_true')
    options = parser.parse_args(argv)
    report = Report(options.language in ('en', 'en_US'))
    try:
        if options.phase == 'environment':
            environment(report, options.project, options.os_release, options.paths, options.reality)
        elif options.phase == 'ports':
            ports(report, options.listen, options.tcp_port, options.udp_port)
        else:
            print(report.tr('正在检查 GitHub HTTPS（网络等待上限 10 秒）……',
                            'Checking GitHub HTTPS (10-second network wait limit)…'), flush=True)
            download(report, options.offline, existing_core=options.existing_core)
    except (OSError, ValueError, TypeError):
        report.add('fail', '检测参数', 'Check parameters', '参数无效或无法读取本机环境', 'Invalid parameters or unreadable local environment')
    return report.render()


if __name__ == '__main__':
    sys.exit(main())

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
 local ipv6_install=${1:-} ipv6_status ipv6_ufw_status
 local flags=() apply_options=()
 if [[ $ipv6_install == ipv6 ]];then
  choice=${2:-0}
  case $choice in 1|2|3);;0)return 0;;*)return 1;;esac
 else
  menu '1. VLESS + Reality + Vision\n2. VLESS + XHTTP + Reality\n3. VLESS + XHTTP + TLS / CDN\n4. 节点安装前检测（不安装）\n5. 搭建 IPv6 节点\n0. 返回' '1. VLESS + Reality + Vision\n2. VLESS + XHTTP + Reality\n3. VLESS + XHTTP + TLS / CDN\n4. Node installation checks (no installation)\n5. Install IPv6 nodes\n0. Back'
  choice=$(ask '> ' '> ') || return 1
 fi
 case $choice in 1) kind=vision; node_port=443;; 2) kind=xhttp-reality; node_port=443;; 3) kind=xhttp-tls; node_port=2053;; 4) run_submenu installation_check_menu;return;; 5) run_submenu ipv6_install_menu;return;; 0) return 0;; *) return 1;; esac
 if [[ $ipv6_install == ipv6 ]];then
  if ! command -v ip >/dev/null;then install_environment_check "$kind" || return 1;fi
  host=$(ipv6_install_address) || { ipv6_status=$?;[[ $ipv6_status == 2 ]] && return 0;return 1; }
  listen=::
  warn '使用所选 IPv6 作为节点连接地址，监听支持双栈。客户端网络必须支持 IPv6，云安全组和系统防火墙需放行 IPv6 TCP 端口。纯 IPv6 VPS 访问 IPv4 网站需要另行配置可用出站。已有同协议节点请用 l → 9 增加 IPv6 备用入口。' 'The selected IPv6 is the client address with a dual-stack listener. Client IPv6 and provider/host IPv6 TCP rules are required. IPv6-only VPSs need a separate working egress for IPv4-only sites. Use l → 9 for IPv6 backups on an existing protocol.'
 fi
 node_name=$(ask '节点名称 [SKYBYTE]：' 'Node name [SKYBYTE]: ') || return 1; node_name=${node_name:-SKYBYTE}-$kind
 [[ $ipv6_install != ipv6 ]] || node_name+=-IPv6
 node_port=$(ask "监听 TCP 端口 [$node_port]：" "TCP listen port [$node_port]: ") || return 1
 case $kind in vision|xhttp-reality) node_port=${node_port:-443};; *) node_port=${node_port:-2053};; esac
 if [[ $ipv6_install != ipv6 ]];then
  listen=$(ask '监听：1 IPv4  2 双栈 IPv4+IPv6 [1]：' 'Listen: 1 IPv4  2 Dual-stack IPv4+IPv6 [1]: ') || return 1
  case ${listen:-1} in 1) listen=0.0.0.0;; 2) listen=::;; *) return 1;; esac
  while :; do
   host=$(ask '客户端连接地址（必填：本 VPS 的公网 IP 或域名）：' 'Client connection address (required: this VPS public IP/domain): ') || return 1
   [[ $host =~ [^[:space:]] ]] && break
   warn '此项没有默认值，请填写本 VPS 的公网 IP 或域名。' 'There is no default; enter this VPS public IP or domain.'
  done
 fi
 helper preflight --port "$node_port" --listen "$listen" --address "$host" --name "$node_name" --kind "$kind" || return 1
 install_environment_check "$kind" && install_port_check "$node_port" "$listen" || return 1
 if [[ $kind == xhttp-tls ]]; then
  sni=$(ask '证书域名 / TLS SNI：' 'Certificate domain / TLS SNI: ') || return 1
  cert=$(ask '已有可信 fullchain 证书文件绝对路径：' 'Absolute path to trusted fullchain certificate: ') || return 1
  private_key=$(ask '私钥文件绝对路径（不修改源文件）：' 'Absolute private-key path (source is preserved): ') || return 1
  helper tls-input --sni "$sni" --cert "$cert" --key "$private_key" || return 1
  local cdn
  if [[ $ipv6_install != ipv6 ]];then
   cdn=$(ask '通过 CDN 连接？[y/N]：' 'Use a CDN? [y/N]: ') || return 1
   if confirmed "$cdn"; then flags+=(--cdn); mode=packet-up; fi
   warn 'CDN 的 DNS、HTTPS 端口及回源 TLS 验证须在提供商后台配置。' 'Configure CDN DNS, supported HTTPS port and verified origin TLS at your provider.'
  fi
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
 apply_options=("$stage" yes)
 if [[ $ipv6_install == ipv6 ]];then
  if ! ipv6_engine check-install "$host";then helper finalize --stage "$stage";return 1;fi
  if ! ipv6_ufw_status=$(helper ufw-state);then helper finalize --stage "$stage";return 1;fi
  if [[ $ipv6_ufw_status == active ]];then
   warn '先放行新端口；后续安装失败时，新增放行规则会保留，请自行核对。' 'Allowing the new port first; added rules remain if installation later fails. Review them if needed.'
   if ! helper firewall-allow --ports "$node_port";then helper finalize --stage "$stage";return 1;fi
  fi
  apply_options+=("ipv6-install:$node_port")
 fi
 apply_stage "${apply_options[@]}" || { error '安装失败，原配置已保留或回退。' 'Install failed; previous configuration retained or restored.'; return 1; }
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
5. 修改节点端口
0. 返回' '1. Rename
2. Remove protocol
3. Refresh TLS certificate
4. Edit address/port/path
5. Change node port
0. Back'
 [[ ${1:-} != --menu ]] || return 0
 choice=$(ask '> ' '> ') || return 1
 else
  choice=$1
 fi
 [[ $choice != 0 ]] || return 0
 case $choice in 1|2|3|4|5) :;; *) error '选项无效。' 'Invalid option.';return 1;; esac
 if [[ $choice == 5 ]];then
  kind=$(choose_port_node) || return 0
  edit_node_port "$kind";return
 fi
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
choose_port_node(){
 local kinds kind selection index=1
 local port_node_kinds=()
 kinds=$(helper node-kinds) || return 1
 while IFS= read -r kind;do [[ -z $kind ]] || port_node_kinds+=("$kind");done <<< "$kinds"
 if [[ ${#port_node_kinds[@]} == 1 ]];then printf '%s' "${port_node_kinds[0]}";return;fi
 for kind in "${port_node_kinds[@]}";do printf '%s. %s\n' "$index" "$kind" >&2;index=$((index+1));done
 say '0. 返回' '0. Back' >&2
 selection=$(ask '选择要修改端口的节点：' 'Select a node to change its port: ') || return 1
 [[ $selection =~ ^[1-3]$ ]] && (( selection <= ${#port_node_kinds[@]} )) || return 1
 printf '%s' "${port_node_kinds[$((selection-1))]}"
}
edit_node_port(){
 local kind=$1 current value stage opened=false firewall_state
 current=$(helper node-port --kind "$kind") || return 1
 report_output say "当前节点：$kind" "Current node: $kind"
 value=$(ask "当前 TCP 端口 ${current}，新端口（回车保留）：" "Current TCP port $current; new port (Enter keeps it): ") || return 0
 if [[ -z $value || $value == "$current" ]];then say '端口未变更。' 'Port unchanged.';return 0;fi
 if [[ ! $value =~ ^[0-9]{1,5}$ ]] || (( 10#$value < 1 || 10#$value > 65535 ));then error '端口须为 1–65535。' 'Use a port from 1 to 65535.';return 1;fi
 value=$((10#$value))
 if [[ $value == "$current" ]];then say '端口未变更。' 'Port unchanged.';return 0;fi
 say "TCP：$current → $value" "TCP: $current → $value"
 warn '保留 UUID、密钥、Short ID、握手网站和路径；运行中的节点会短暂重载。已启用 UFW 时放行新端口，云安全组或 firewalld 仍需自行核对。' 'Keeps UUID, keys, Short ID, handshake site and path. Running nodes briefly reload. Active UFW allows the new port; verify provider firewall/firewalld rules separately.'
 confirm '应用端口变更？' 'Apply this port change?' || { say '已取消，端口未变更。' 'Cancelled; port unchanged.';return 0; }
 stage=$(helper edit --kind "$kind" --port "$value") || return 1
 # Keep the current listener until any required UFW rule succeeds.
 firewall_state=$(helper ufw-state) || { helper finalize --stage "$stage" || true;error '无法读取 UFW 状态，节点端口未修改。' 'Cannot inspect UFW; node port unchanged.';return 1; }
 if [[ $firewall_state == active ]];then
  if ! helper firewall-allow --ports "$value";then
   helper finalize --stage "$stage" || true
   error 'UFW 放行未完成，节点端口未修改；请核对防火墙规则。' 'UFW allow incomplete; node port unchanged. Inspect firewall rules.'
   return 1
  fi
  opened=true
 fi
 if ! apply_stage "$stage";then
  [[ $opened != true ]] || warn '节点更新失败，已尝试回退；新端口的 UFW 放行规则保留，请在防火墙菜单核对。' 'Node update failed; rollback attempted. The new UFW allow rule is retained; review it in the firewall menu.'
  return 1
 fi
 say '端口已更新；从 b 获取新节点并重新导入客户端，IPv6 备用同步更新。旧防火墙规则保留。' 'Port updated. Get new nodes from b and re-import them; IPv6 backups are updated too. Old firewall rules are retained.'
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
"""Verified, on-demand upstream diagnostics. No node configuration is read."""
import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import shutil
import sys
import unicodedata
import signal
import subprocess
import tempfile
import threading
import zipfile

TOOLS = {'unlock': ('oneclickvirt/UnlockTests', 'Apache-2.0'), 'ecs': ('oneclickvirt/ecs', 'GPL-3.0')}
MAX_DOWNLOAD = 128 * 1024 * 1024


def clean_env(home):
    env = {k: os.environ[k] for k in ('PATH', 'LANG', 'LC_ALL', 'NO_COLOR', 'SSL_CERT_FILE', 'SSL_CERT_DIR') if k in os.environ}
    env.update(HOME=str(home), TMPDIR=str(home))
    return env


def fetch(url, limit):
    if not url.startswith('https://'):
        raise ValueError('Non-HTTPS diagnostic download refused')
    with tempfile.TemporaryDirectory(prefix='skybyte-diagnostic-download-') as home:
        target = Path(home) / 'download'
        args = ['curl', '-q', '-fsSL', '--proto', '=https', '--proto-redir', '=https',
                '--connect-timeout', '8', '--max-time', '60', '--max-filesize', str(limit),
                '--user-agent', 'SKYBYTE-Diagnostics', '-o', str(target), url]
        result = subprocess.run(args, env=clean_env(home), capture_output=True, timeout=65)
        if result.returncode:
            raise ValueError('Official diagnostic download failed / 官方检测工具下载失败，请检查 GitHub 连接')
        data = target.read_bytes()
    if len(data) > limit:
        raise ValueError('Diagnostic download too large')
    return data


def private_dir(path):
    path = Path(path)
    if not path.is_absolute() or any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError('Unsafe diagnostic directory / 检测目录异常')
    if path.exists() and not path.is_dir():
        raise ValueError('Diagnostic directory is not a directory')
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)
    return path


def asset_name(tool, system=None, machine=None):
    system = (system or platform.system()).lower()
    machine = machine or platform.machine()
    arch = {'x86_64': 'amd64', 'amd64': 'amd64', 'aarch64': 'arm64', 'arm64': 'arm64',
            'armv7l': 'arm', 'armv6l': 'arm', 'i386': '386', 'i686': '386'}.get(machine)
    if system not in ('linux', 'darwin') or arch is None:
        raise ValueError('Unsupported diagnostic architecture / 检测工具不支持此架构')
    return ('ut-' + system + '-' + arch) if tool == 'unlock' else ('goecs_' + system + '_' + arch + '.zip')


def ensure_tool(report_dir, tool):
    repo, _license = TOOLS[tool]
    folder = private_dir(Path(report_dir).parent / 'diagnostic-tools' / tool)
    metadata = json.loads(fetch('https://api.github.com/repos/' + repo + '/releases/latest', 2 * 1024 * 1024))
    tag = metadata.get('tag_name', '')
    if metadata.get('draft') or metadata.get('prerelease') or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,100}', tag):
        raise ValueError('Invalid diagnostic release')
    name = asset_name(tool)
    assets = [x for x in metadata.get('assets', []) if x.get('name') == name]
    if len(assets) != 1:
        raise ValueError('Official diagnostic asset missing')
    asset = assets[0]
    url = 'https://github.com/' + repo + '/releases/download/' + tag + '/' + name
    digest = asset.get('digest', '')
    if asset.get('browser_download_url') != url or not re.fullmatch(r'sha256:[a-f0-9]{64}', digest):
        raise ValueError('Official diagnostic SHA256/URL missing or invalid')
    # Cache the original release asset, not an unverified extracted executable.
    cached = folder / (digest[7:] + '.asset')
    if cached.is_symlink() or (cached.exists() and not cached.is_file()):
        raise ValueError('Unsafe diagnostic cache')
    if cached.exists():
        if cached.stat().st_size > MAX_DOWNLOAD: raise ValueError('Diagnostic cache too large')
        data = cached.read_bytes()
    else:
        print('Downloading verified ' + repo + ' ' + tag + ' …', flush=True)
        data = fetch(url, MAX_DOWNLOAD)
    if len(data) > MAX_DOWNLOAD or hashlib.sha256(data).hexdigest() != digest[7:]:
        raise ValueError('Diagnostic SHA256 mismatch; not executed / 检测工具校验失败，未执行')
    if not cached.exists():
        fd, temp = tempfile.mkstemp(dir=folder, prefix='.download-')
        try:
            with os.fdopen(fd, 'wb') as stream:
                stream.write(data)
            os.replace(temp, cached)
        finally:
            if os.path.exists(temp): os.unlink(temp)
    # Retain only the current verified asset; diagnostics must not grow with every release.
    for previous in folder.glob('*.asset'):
        if previous != cached and re.fullmatch(r'[a-f0-9]{64}[.]asset', previous.name) and previous.is_file() and not previous.is_symlink():
            previous.unlink()
    if tool == 'ecs':
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            entries = [x for x in archive.infolist() if Path(x.filename).name in ('goecs', 'ecs') and not x.is_dir()]
            if len(entries) != 1 or entries[0].file_size > MAX_DOWNLOAD:
                raise ValueError('Invalid official diagnostic archive')
            data = archive.read(entries[0])
    return data, {'repository': repo, 'release': tag, 'asset': name, 'sha256': digest[7:]}


def execute(args, home, timeout, stdout=None, stderr=None, strip_colors=False):
    process = subprocess.Popen(args, cwd=home, env=clean_env(home), stdout=subprocess.PIPE if strip_colors else stdout, stderr=stderr, start_new_session=True)
    reader = None
    if strip_colors:
        def forward():
            for line in iter(process.stdout.readline, b''):
                text = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', line.decode('utf-8', 'replace'))
                sys.stdout.write(text); sys.stdout.flush()
        reader = threading.Thread(target=forward, daemon=True); reader.start()
    try:
        process.wait(timeout=timeout)
    except BaseException:
        try: os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError: pass
        try: process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try: os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            process.wait()
        raise
    finally:
        if reader is not None:
            reader.join()
            process.stdout.close()
    return process


def unlock_arguments(path, port=None, all_platforms=False, language='zh_CN'):
    if path not in ('4', '6', 'warp'):
        raise ValueError('Invalid diagnostic path')
    args = ['-json', '-region', '20' if all_platforms else '0,21', '-conc', '6', '-timeout', '2m',
            '-m', '6' if path == '6' else '4', '-L', 'en' if language in ('en', 'en_US') else 'zh']
    if path == 'warp':
        if type(port) is not int or not 1024 <= port <= 65535:
            raise ValueError('Invalid loopback proxy port')
        args += ['-socks-proxy', 'socks5://127.0.0.1:' + str(port)]
    return args


def ecs_arguments(mode, language='zh_CN'):
    if mode not in ('route', 'speed', 'full'):
        raise ValueError('Invalid benchmark mode')
    # Explicitly opt into each module; upstream default includes uploads/stress tests.
    return ['-menu=false', '-upload=false', '-log=false', '-l', 'zh', '-dns-mode', 'system',
            '-basic=' + str(mode == 'full').lower(), '-ut=' + str(mode == 'full').lower(),
            '-security=' + str(mode == 'full').lower(), '-backtrace=' + str(mode != 'speed').lower(),
            '-nt3=' + str(mode != 'speed').lower(), '-speed=' + str(mode != 'route').lower(),
            '-cpu=false', '-memory=false', '-disk=false', '-email=false', '-ping=false', '-web=false', '-tgdc=false']


def safe_text(value, limit=250):
    # Provider strings must not inject terminal control sequences or extra rows.
    value = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', str(value))
    return ''.join(c for c in value if c.isprintable()).strip()[:limit]


def display_width(text):
    return sum(0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1 for c in text)


def wrap_cell(value, width):
    value = safe_text(value, 1000) or '-'
    lines, line, used = [], '', 0
    for index, char in enumerate(value):
        if char.isspace() and line:
            following = value[index + 1:].split(' ', 1)[0]
            if display_width(following) <= width and used + 1 + display_width(following) > width:
                lines.append(line.rstrip()); line, used = '', 0
                continue
        size = display_width(char)
        if line and used + size > width:
            lines.append(line); line, used = '', 0
        line += char; used += size
    return lines + [line]


def report_table(rows, language='zh_CN', columns=None, color=None):
    """Terminal-cell-aware wrapping keeps Chinese and long provider names aligned."""
    columns = max(50, min(140, columns or shutil.get_terminal_size((100, 24)).columns))
    widths = [10, 7, 4, 6, 7]
    extra = columns - 16 - sum(widths)
    weights = [0.31, 0.19, 0.09, 0.13, 0.28]
    for index, weight in enumerate(weights): widths[index] += int(extra * weight)
    widths[4] += columns - 16 - sum(widths)
    headers = ['平台', '状态', '地区', '类型', '说明'] if language not in ('en', 'en_US') else ['Platform', 'Status', 'Region', 'Type', 'Notes']
    output = []
    def border(left, middle, right):
        return left + middle.join('─' * (width + 2) for width in widths) + right
    def cells(values):
        wrapped = [wrap_cell(value, width) for value, width in zip(values, widths)]
        for i in range(max(map(len, wrapped))):
            parts = []
            for lines, width in zip(wrapped, widths):
                text = lines[i] if i < len(lines) else ''
                parts.append(' ' + text + ' ' * (width - display_width(text) + 1))
            output.append('│' + '│'.join(parts) + '│')
    output.append(border('┌', '┬', '┐')); cells(headers)
    output.append(border('├', '┼', '┤'))
    if not rows:
        rows = [{'name': '无结果 / No results', 'status': 'Unknown'}]
    for index, row in enumerate(rows):
        notes = ' / '.join(dict.fromkeys(x for x in (row.get('error', ''), row.get('info', '')) if x))
        cells([row.get(k, '') for k in ('name', 'status', 'region', 'unlock_type')] + [notes])
        if index < len(rows) - 1: output.append(border('├', '┼', '┤'))
    output.append(border('└', '┴', '┘'))
    if color is None: color = sys.stdout.isatty() and not os.environ.get('NO_COLOR')
    return ('\033[1;33m' if color else '') + '\n'.join(output) + ('\033[0m' if color else '')


def save_report(directory, report):
    directory = private_dir(directory)
    fd, name = tempfile.mkstemp(prefix='diagnostic-', suffix='.json', dir=directory)
    with os.fdopen(fd, 'w') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
    return Path(name)


def run(paths, report_dir, port=None, language='zh_CN', all_platforms=False):
    if not paths or any(p not in ('4', '6', 'warp') for p in paths):
        raise ValueError('Invalid diagnostic paths')
    arguments = [unlock_arguments(p, port, all_platforms, language) for p in paths]
    report_dir = private_dir(report_dir)
    payload, source = ensure_tool(report_dir, 'unlock')
    report = {'engine': source, 'time': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'playback_verified': False, 'runs': []}
    failed = False
    with tempfile.TemporaryDirectory(prefix='.unlock-', dir=report_dir.parent) as home:
        binary = Path(home) / 'ut'; binary.write_bytes(payload); binary.chmod(0o700)
        for path, args in zip(paths, arguments):
            print('\n=== ' + ('SOCKS5 / WARP (address family selected by proxy)' if path == 'warp' else 'VPS direct IPv' + path) + ' ===', flush=True)
            # Output goes to a private file so unexpected upstream output cannot exhaust RAM.
            with tempfile.TemporaryFile() as output:
                try:
                    result = execute([str(binary), *args], home, 140, stdout=output, stderr=subprocess.DEVNULL)
                    output.seek(0); raw = output.read(4 * 1024 * 1024 + 1)
                    if len(raw) > 4 * 1024 * 1024: raise ValueError('Diagnostic result too large')
                    data = json.loads(raw)
                    if not isinstance(data, dict) or data.get('schema_version') != 'goecs.unlocktests/v1' or not isinstance(data.get('results'), list):
                        raise ValueError('Unsupported diagnostic JSON schema')
                    rows = []
                    for item in data['results']:
                        if not isinstance(item, dict): raise ValueError('Invalid provider result')
                        row = {key: safe_text(item.get(key, '')) for key in ('name', 'status', 'region', 'unlock_type', 'info', 'error', 'ip_version')}
                        rows.append(row)
                    error = safe_text(data.get('error', ''))
                    failed = failed or result.returncode != 0 or bool(error) or not rows
                except (subprocess.TimeoutExpired, ValueError) as exc:
                    rows = []; error = safe_text(type(exc).__name__ + ': diagnostic incomplete / 检测未完成'); failed = True
            report['runs'].append({'path': path, 'results': rows, 'error': error})
            print(report_table(rows, language))
            if error: print('检测未完成 / Incomplete: ' + error)
    output = save_report(report_dir, report)
    print('本机报告 / Local report: ' + str(output))
    print('Upstream assessment; account eligibility/playback are not guaranteed. DNS/proxy types do not certify residential IPs.' if language in ('en', 'en_US') else '结果为上游检测判定；不保证账号资格或实际播放。DNS/代理类型为辅助判断，不能当作住宅 IP 认证。')
    if failed: raise ValueError('Diagnostic incomplete; partial report retained / 检测未完成，已保留部分结果')
    return report['runs']


def benchmark(mode, report_dir, language='zh_CN'):
    args = ecs_arguments(mode, language)
    report_dir = private_dir(report_dir)
    payload, source = ensure_tool(report_dir, 'ecs')
    print('VPS direct network only / 仅测试 VPS 直连网络；代理和节点客户端线路不在本检测范围。', flush=True)
    print('Engine: ' + source['repository'] + ' ' + source['release'], flush=True)
    with tempfile.TemporaryDirectory(prefix='.ecs-', dir=report_dir.parent) as home:
        binary = Path(home) / 'goecs'; binary.write_bytes(payload); binary.chmod(0o700)
        result = execute([str(binary), *args], home, 1200, strip_colors=True)
    if result.returncode: raise ValueError('Benchmark incomplete / 综合检测未完成')


def diagnostic_main(argv):
    if len(argv) != 4:
        raise ValueError('Invalid diagnostic invocation')
    action, directory, language, port = argv
    if action in ('route', 'speed', 'full'):
        return benchmark(action, directory, language)
    mapping = {'4': ['4'], '6': ['6'], 'both': ['4', '6'], 'warp': ['warp'], 'compare': ['4', 'warp'], 'all': ['4']}
    if action not in mapping:
        raise ValueError('Unknown diagnostic operation')
    return run(mapping[action], directory, int(port) if port else None, language, action == 'all')

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
"""Read-only REALITY target diagnostics; standard library, no core required."""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import queue
import re
import socket
import ssl
import sys
import threading
import time


def hostname(value):
    if not isinstance(value, str):
        raise ValueError('Invalid hostname')
    if '%' in value or any(ord(char) < 32 or ord(char) == 127 for char in value):
        raise ValueError('Invalid hostname')
    value = value.strip().rstrip('.')
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        pass
    value = value.encode('idna').decode('ascii').lower()
    if len(value) > 253 or not all(re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', part)
                                   for part in value.split('.')):
        raise ValueError('Invalid hostname')
    return value


def target_parts(value, sni=''):
    if not isinstance(value, str):
        raise ValueError('Invalid target')
    value = value.strip()
    number = '443'
    if value.startswith('['):
        match = re.fullmatch(r'\[([^\]]+)\](?::([0-9]+))?', value)
        if not match:
            raise ValueError('Invalid target')
        host, number = match[1], match[2] or '443'
        if ipaddress.ip_address(host).version != 6:
            raise ValueError('Invalid IPv6 target')
    elif value.count(':') == 1:
        host, number = value.rsplit(':', 1)
    else:
        host = value
    host = hostname(host)
    if not re.fullmatch(r'[0-9]{1,5}', number) or not 1 <= int(number) <= 65535:
        raise ValueError('Invalid port')
    return host, int(number), hostname(sni or host)


def target_label(host, number):
    return ('[' + host + ']' if ':' in host else host) + ':' + str(number)


def resolve(host, number, timeout):
    # A daemon resolver bounds DNS even if libc's resolver does not return.
    results = queue.Queue()
    def lookup():
        try:
            results.put(socket.getaddrinfo(host, number, type=socket.SOCK_STREAM))
        except OSError as error:
            results.put(error)
    threading.Thread(target=lookup, daemon=True).start()
    try:
        value = results.get(timeout=timeout)
    except queue.Empty:
        raise TimeoutError('DNS deadline') from None
    if isinstance(value, OSError):
        raise value
    return value


def probe(target, sni='', ca_file=None, timeout=12):
    host, number, sni = target_parts(target, sni)
    checks = {key: {'status': 'skip', 'detail': 'not_checked'}
              for key in ('dns', 'tcp', 'tls', 'certificate', 'h2')}
    result = {'target': target_label(host, number), 'sni': sni, 'checks': checks, 'ok': False}
    started = time.monotonic()
    def remaining():
        value = timeout - (time.monotonic() - started)
        if value <= 0:
            raise TimeoutError('Reality target deadline')
        return value
    stage = 'dns'
    connection = None
    try:
        addresses = resolve(host, number, remaining())
        if not addresses:
            raise socket.gaierror()
        resolved = list(dict.fromkeys(str(ipaddress.ip_address(item[4][0])) for item in addresses))
        checks['dns'] = {'status': 'pass', 'detail': ', '.join(resolved[:4])}
        stage = 'tcp'
        last = None
        for family, kind, protocol, _, endpoint in addresses:
            wait = min(4, remaining())
            connection = socket.socket(family, kind, protocol)
            try:
                connection.settimeout(wait)
                connection.connect(endpoint)
                break
            except OSError as error:
                last = error
                connection.close()
                connection = None
        if connection is None:
            raise last or OSError('No usable address')
        peer = str(ipaddress.ip_address(connection.getpeername()[0]))
        checks['tcp'] = {'status': 'pass', 'detail': target_label(peer, number)}
        stage = 'tls'
        context = ssl.create_default_context(cafile=ca_file)
        context.minimum_version = ssl.TLSVersion.TLSv1_3
        context.set_alpn_protocols(['h2'])
        connection.settimeout(remaining())
        with context.wrap_socket(connection, server_hostname=sni) as secure:
            checks['tls'] = {'status': 'pass', 'detail': secure.version()}
            # create_default_context verifies CA trust, validity and name.
            checks['certificate'] = {'status': 'pass', 'detail': 'verified'}
            stage = 'h2'
            protocol = secure.selected_alpn_protocol()
            checks['h2'] = {'status': 'pass' if protocol == 'h2' else 'fail',
                            'detail': 'h2' if protocol == 'h2' else 'no_h2'}
            result['ok'] = protocol == 'h2'
    except ssl.SSLCertVerificationError as error:
        reason = {9: 'not_yet_valid', 10: 'expired', 62: 'name_mismatch', 64: 'name_mismatch'}.get(
            error.verify_code, 'untrusted')
        checks['certificate'] = {'status': 'fail', 'detail': reason}
    except socket.gaierror:
        checks[stage] = {'status': 'fail', 'detail': 'dns_failed'}
    except (TimeoutError, socket.timeout):
        checks[stage] = {'status': 'fail', 'detail': 'timeout'}
    except ssl.SSLError:
        checks[stage] = {'status': 'fail', 'detail': 'tls_failed'}
    except OSError:
        checks[stage] = {'status': 'fail', 'detail': 'connect_failed' if stage == 'tcp' else 'system_failed'}
    finally:
        if connection is not None:
            connection.close()
    result['elapsed_ms'] = round((time.monotonic() - started) * 1000)
    return result


def configured_targets(path, project):
    path = Path(path)
    if not path.exists():
        return []
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 4 * 1024 * 1024:
        raise ValueError('Invalid configuration file')
    config = json.loads(path.read_text())
    targets = []
    for node in config.get('inbounds', []):
        if project == 'sing-box':
            tls = node.get('tls', {})
            reality = tls.get('reality', {})
            if not tls.get('enabled') or not reality.get('enabled'):
                continue
            handshake = reality['handshake']
            host = hostname(handshake['server'])
            target = target_label(host, handshake.get('server_port', 443))
            names = [tls['server_name']]
        else:
            stream = node.get('streamSettings', {})
            if stream.get('security') != 'reality':
                continue
            reality = stream['realitySettings']
            target = reality.get('target') or reality.get('dest')
            names = reality['serverNames']
        if not isinstance(names, list) or not names:
            raise ValueError('Missing SNI')
        for sni in names:
            # No-SNI REALITY is not configured by either manager.
            if not sni:
                raise ValueError('Empty SNI cannot be checked by this diagnostic')
            host, number, sni = target_parts(target, sni)
            item = (target_label(host, number), sni)
            if item not in targets:
                targets.append(item)
            if len(targets) > 64:
                raise ValueError('Too many targets')
    return targets


def render(result, language):
    english = language in ('en', 'en_US')
    def text(zh, en):
        return en if english else zh
    labels = {'dns': ('DNS 解析', 'DNS resolution'), 'tcp': ('TCP 连接', 'TCP connection'),
              'tls': ('TLS 1.3', 'TLS 1.3'), 'certificate': ('证书校验', 'Certificate'),
              'h2': ('HTTP/2 (ALPN)', 'HTTP/2 (ALPN)')}
    details = {
        'not_checked': ('未完成检测', 'Not checked'),
        'verified': ('信任链、有效期与握手域名匹配', 'Trusted chain, valid dates and matching SNI'),
        'no_h2': ('未协商到 h2', 'h2 was not negotiated'),
        'name_mismatch': ('证书与握手域名不匹配', 'Certificate does not match SNI'),
        'expired': ('证书已过期，请同时检查系统时间', 'Certificate expired; also check the system clock'),
        'not_yet_valid': ('证书尚未生效，请同时检查系统时间', 'Certificate not yet valid; also check the system clock'),
        'untrusted': ('证书链不受信任或验证失败', 'Untrusted certificate chain or verification failed'),
        'dns_failed': ('目标 DNS 解析失败', 'Target DNS lookup failed'),
        'timeout': ('检测超时', 'Timed out'),
        'tls_failed': ('TLS 握手失败，未完成 TLS 1.3 验证', 'TLS handshake failed; TLS 1.3 was not verified'),
        'connect_failed': ('无法连接目标端口', 'Cannot connect to target port'),
        'system_failed': ('本机网络或 CA 证书读取失败', 'Local network or CA store error'),
    }
    print('\n' + text('Reality 握手网站检测', 'Reality handshake target check'))
    print(text('握手目标：', 'Target: ') + result['target'])
    print(text('握手域名：', 'SNI: ') + result['sni'])
    for key, item in result['checks'].items():
        status = {'pass': text('通过', 'PASS'), 'fail': text('失败', 'FAIL'), 'skip': text('未检查', 'SKIP')}[item['status']]
        detail = text(*details[item['detail']]) if item['detail'] in details else item['detail']
        print('  [' + status + '] ' + text(*labels[key]) + ': ' + detail)
    summary = (text('检测通过：TLS 1.3、HTTP/2 与证书正常', 'PASSED: TLS 1.3, HTTP/2 and certificate verified')
               if result['ok'] else text('检测未通过：请根据上方原因检查目标', 'FAILED: inspect the reasons above'))
    color = ('\033[1;32m' if result['ok'] else '\033[1;31m') if sys.stdout.isatty() and not os.environ.get('NO_COLOR') else ''
    print(color + '===== ' + summary + ' =====' + ('\033[0m' if color else ''))
    print(text('检测耗时：', 'Check duration: ') + str(result['elapsed_ms']) + ' ms')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target')
    parser.add_argument('--sni', default='')
    parser.add_argument('--config')
    parser.add_argument('--list', action='store_true', help='List configured target/SNI pairs without probing')
    parser.add_argument('--normalize', action='store_true', help='Print validated host, port and SNI without probing')
    parser.add_argument('--project', choices=('sing-box', 'xray'), required=True)
    parser.add_argument('--language', choices=('zh', 'en', 'zh_CN', 'en_US'), default='zh')
    args = parser.parse_args(argv)
    english = args.language in ('en', 'en_US')
    try:
        if args.target is not None:
            host, number, sni = target_parts(args.target, args.sni)
            targets = [(target_label(host, number), sni)]
        elif args.config:
            targets = configured_targets(args.config, args.project)
        else:
            raise ValueError('Target or configuration required')
    except (ValueError, OSError, KeyError, TypeError, AttributeError, UnicodeError):
        print('Invalid target/SNI or unreadable REALITY configuration; use a hostname or host:port.' if english else
              '目标 / 握手域名无效，或无法读取 Reality 配置；请输入域名或 域名:端口。', file=sys.stderr)
        return 2
    if not targets:
        if args.list:
            return 0
        print('No configured Reality targets; choose custom target check.' if english else
              '未找到已配置的 Reality 握手目标，可选择“检测自定义网站”。')
        return 0
    if args.normalize:
        if args.target is None:
            return 2
        print('\t'.join((host, str(number), sni)))
        return 0
    if args.list:
        for target, sni in targets:
            print(target + '\t' + sni)
        return 0
    failed = False
    for target, sni in targets:
        result = probe(target, sni)
        render(result, args.language)
        failed |= not result['ok']
    print('\nOnly checks this VPS → target. It does not verify client → VPS or CDN connectivity.' if english else
          '\n仅检测本 VPS → 握手目标，不代表客户端 → VPS 或 CDN 已连通。')
    return int(failed)


if __name__ == '__main__':
    sys.exit(main())

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
