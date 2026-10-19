#!/usr/bin/env bash
# SKYBYTE Xray Manager standalone; generated from src/manager.sh and src/core.py.
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
set -Eeuo pipefail
umask 077
VERSION=0.1.10
CORE_VERSION=v26.3.27
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
confirmed(){ [[ $1 =~ ^[Yy][Ee][Ss]$ ]]; }
confirm(){ local answer; answer=$(ask "$1 [YES]: " "$2 [YES]: ") || return 1; confirmed "$answer"; }
separator(){ printf '%s\n' '------------------------------------------------------------'; }

helper(){ python3 - "$@" <<'SKYBYTE_PYTHON'
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
"""SKYBYTE Xray Manager: private configuration, exports and transactions.

Only generated runtime state contains credentials. No imported content is executed.
"""
import argparse
import base64
import copy
import errno
import hashlib
import io
import ipaddress
import json
import os
import re
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

VERSION = "0.1.10"
CORE_VERSION = "v26.3.27"
OWNER = "SKYBYTE-XRAY/1\n"
UNIT_MARK = "# SKYBYTE Xray Manager unit v1\n"
KINDS = ("vision", "xhttp-reality", "xhttp-tls")
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
    context.load_cert_chain(str(cert), str(private_key))
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
    if subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
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
    if not isinstance(state, dict) or set(state) != {"schema", "nodes"} or state["schema"] != 1:
        raise ValueError("Unknown state format / 非托管状态格式")
    if not isinstance(state["nodes"], dict) or not set(state["nodes"]) <= set(KINDS):
        raise ValueError("Invalid protocol state")
    ports = set()
    for kind, node in state["nodes"].items():
        required = {"name", "uuid", "port", "address", "listen", "sni"}
        extra = {"private", "public", "short_id", "target"} if kind != "xhttp-tls" else {"cert", "key", "cdn"}
        if kind.startswith("xhttp"):
            extra |= {"path", "mode"}
        if not isinstance(node, dict) or set(node) != required | extra:
            raise ValueError("Invalid node fields")
        name(node["name"])
        if str(uuid.UUID(node["uuid"])) != node["uuid"]:
            raise ValueError("Invalid UUID")
        p = port(node["port"])
        if p in ports:
            raise ValueError("Duplicate TCP port / TCP 端口冲突")
        ports.add(p)
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
    return {"log": {"loglevel": "warning"}, "inbounds": inbounds,
            "outbounds": [{"protocol": "freedom", "tag": "direct"}, {"protocol": "blackhole", "tag": "block"}],
            "routing": {"domainStrategy": "IPOnDemand", "rules": [{"type": "field", "ip": ["127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12",
                "192.168.0.0/16", "169.254.0.0/16", "::1/128", "fc00::/7", "fe80::/10"], "outboundTag": "block"}]}}


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


def owned_names(state):
    return {"state.json", "config.json", "nodes.txt", "subscription-base64.txt"} | tls_names(state) | {
        "client-" + k + ".json" for k in state["nodes"]}


def render_files(state, root):
    files = {"state.json": json_text(state), "config.json": json_text(server_config(state, root))}
    lines = [node_uri(k, n) for k, n in state["nodes"].items()]
    nodes = "\n".join(lines) + ("\n" if lines else "")
    files["nodes.txt"] = nodes
    files["subscription-base64.txt"] = base64.b64encode(nodes.encode()).decode() + "\n"
    files.update({"client-" + k + ".json": json_text(client_config(k, n)) for k, n in state["nodes"].items()})
    return files


def check_port(host, number):
    try:
        with socket.socket(socket.AF_INET6 if ":" in host else socket.AF_INET) as listener:
            if ":" in host:
                listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            listener.bind((host, number))
    except OSError as error:
        if error.errno == errno.EADDRINUSE:
            raise ValueError(f"TCP {number} is already in use; choose a free port. Existing services are preserved. / TCP {number} 已被占用，请选择空闲端口；不会停止已有服务。") from None
        raise


def installation_preflight(options):
    address(options.address)
    name(options.name)
    check_port(options.listen, port(options.port))


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
            re.fullmatch(r"client-(vision|xhttp-reality|xhttp-tls)\.json", relative) or
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
    parser.add_argument("command", choices=["selfcheck", "prepare", "commit", "rollback", "finalize", "backup", "restore",
                                            "remove", "rename", "edit", "refresh-tls", "show", "guard", "download", "probe", "journal", "preflight", "node-ports", "firewall-status", "firewall-allow", "bbr-status", "bbr-enable", "bbr-restore", "manager-latest", "manager-update", "firewall-setup-check", "firewall-setup-plan", "firewall-setup", "ufw-state", "ufw-disable", "ufw-remove-plan", "ufw-package-state"])
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
    options = parser.parse_args()
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
    if options.command == "node-ports":
        root = checked_path(options.root)
        ensure_owned(root)
        nodes = load_state(root)["nodes"]
        if not nodes:
            raise ValueError("No nodes installed / 尚未安装节点")
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
    elif options.command == "show":
        ensure_owned(root)
        for kind, node in load_state(root)["nodes"].items():
            print(node["name"] + " | " + kind + " | TCP " + str(node["port"]))
            print(node_uri(kind, node))
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
 while :; do
  host=$(ask '客户端连接地址（必填：本 VPS 的公网 IP 或域名）：' 'Client connection address (required: this VPS public IP/domain): ') || return 1
  [[ $host =~ [^[:space:]] ]] && break
  warn '此项没有默认值，请填写本 VPS 的公网 IP 或域名。' 'There is no default; enter this VPS public IP or domain.'
 done
 helper preflight --port "$node_port" --listen "$listen" --address "$host" --name "$node_name" || return 1
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
 warn '请放行实际 TCP 端口，可用菜单 12 管理系统防火墙；配置检查不等于公网或 CDN 已连通。' 'Allow the actual TCP port using menu 12 for the host firewall; validation does not prove public/CDN connectivity.'
 confirm '安装并启动所选节点？' 'Install and start the selected node?' || return 1
 ensure_binary || { error '核心准备失败，具体原因见上方提示。' 'Core preparation failed; see the reason above.'; return 1; }
 flags+=(--kind "$kind" --port "$node_port" --listen "$listen" --address "$host" --sni "$sni" --name "$node_name")
 if [[ $kind == xhttp-tls ]]; then flags+=(--cert "$cert" --key "$private_key")
 else flags+=(--target "$target"); fi
 [[ $kind != xhttp-* ]] || flags+=(--path "$path" --mode "$mode")
 stage=$(helper prepare "${flags[@]}") || { error '节点配置准备失败，具体原因见上方提示。' 'Node configuration preparation failed; see the reason above.'; return 1; }
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
 local choice kind value stage cert private_key host node_port path
 local flags=()
 menu '1 重命名  2 删除协议  3 更新 TLS 证书  4 修改地址/端口/路径  0 返回' '1 Rename  2 Remove protocol  3 Refresh TLS certificate  4 Edit address/port/path  0 Back'
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
  say '节点已更新；请使用菜单 2 的新链接或导出文件更新客户端。' 'Node updated; update clients with the new links or exports from menu 2.'
 fi
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
 python3 - "$SKYBYTE_XRAY_DIR" "$SKYBYTE_XRAY_UNIT" "$SKYBYTE_XRAY_LIB" "$SKYBYTE_XRAY_SHORTCUT" <<'PY'
import json,sys
from pathlib import Path
root,unit,lib,shortcut=map(Path,sys.argv[1:])
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
if shortcut.is_file() and not shortcut.is_symlink():
 if shortcut.read_text().startswith('#!/usr/bin/env bash\n# SKYBYTE Xray Manager shortcut v1\n') and str(manager) in shortcut.read_text():
  paths.append(shortcut)
for p in paths:
 if p.exists(): p.unlink()
PY
 systemctl daemon-reload || return 1
 warn '已卸载。备份、未知文件、系统依赖、防火墙规则和 BBR 设置保留；如需恢复 BBR，请在卸载前使用菜单 12 → 8。' 'Removed. Backups, unknown files, dependencies, firewall rules and BBR settings retained; restore BBR with menu 12 → 8 before uninstalling if needed.'
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
 say '安装后输入 xr 可重新打开菜单。' 'After installation, run xr to reopen the menu.'
}
firewall_open(){
 local value=${1:-} zone
 local flags=()
 [[ -z $value ]] || flags+=(--ports "$value")
 helper firewall-status || return 1
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
 helper firewall-status
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
 menu '防火墙\n1 查看防火墙状态\n2 安装并启用 UFW\n3 放行全部节点 TCP 端口\n4 放行指定 TCP 端口\n5 停用/卸载 UFW\n\nBBR\n6 查看 BBR 状态\n7 启用 BBR + fq\n8 恢复启用前参数\n\n0 返回' 'Firewall\n1 Show firewall status\n2 Install and enable UFW\n3 Allow all node TCP ports\n4 Allow a TCP port\n5 Disable/remove UFW\n\nBBR\n6 Show BBR status\n7 Enable BBR + fq\n8 Restore previous settings\n\n0 Back'
 choice=$(ask '> ' '> ') || return 1
 case $choice in
  1) helper firewall-status;;
  2) install_firewall;;
  3) firewall_open;;
  4) value=$(ask '要放行的 TCP 端口（1–65535）：' 'TCP port to allow (1–65535): ') || return 1
     if [[ ! $value =~ ^[0-9]{1,5}$ ]] || (( 10#$value < 1 || 10#$value > 65535 )); then
      error 'TCP 端口无效。' 'Invalid TCP port.'; return 1
     fi
     firewall_open "$value";;
  5) remove_firewall;;
  6) helper bbr-status;;
  7) warn 'BBR 调整全系统新 TCP 连接的默认拥塞控制；不保证提速，不更换内核或重启服务，也不替换现有网卡队列。' 'BBR changes the system default for new TCP connections; speed gains vary. No kernel replacement, service restart or live interface queue replacement.'
     confirm '保存原参数并启用 BBR + fq？' 'Save previous values and enable BBR + fq?' || return 0
     helper bbr-enable || return 1
     helper bbr-status;;
  8) confirm '恢复本脚本启用 BBR 前的系统参数并移除本脚本的持久化文件？' 'Restore values saved before enabling BBR and remove the managed persistence file?' || return 0
     helper bbr-restore || return 1
     helper bbr-status;;
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
main_menu(){
 while :; do
  printf '%s\n' '============================================================'
  printf '%sSKYBYTE Xray Manager v%s%s\n' "$CYAN" "$VERSION" "$RESET"
  printf '%sYouTube: https://www.youtube.com/@SKYBYTE9119%s\n' "$CYAN" "$RESET"
  say '觉得脚本好用，欢迎订阅我的 YouTube 频道，支持后续维护。' 'If this script helps, subscribe to my YouTube channel to support maintenance.'
  menu '1. 安装 / 添加节点\n2. 查看节点与客户端配置\n3. 节点二维码\n4. 服务与日志\n5. 编辑节点 / 删除 / TLS 证书\n6. 更新 Xray 核心\n7. 备份配置\n8. 恢复配置\n9. 使用说明\n10. 切换语言\n11. 卸载\n12. 防火墙 / BBR\n13. 更新管理脚本\n0. 退出' '1. Install / add nodes\n2. Nodes and client configs\n3. Node QR codes\n4. Service and logs\n5. Edit nodes / remove / TLS certificate\n6. Update Xray-core\n7. Back up configuration\n8. Restore configuration\n9. Guide\n10. Language\n11. Uninstall\n12. Firewall / BBR\n13. Update manager script\n0. Exit'
  local choice
  choice=$(ask '请选择：' 'Choose: ') || return 0
  case $choice in
   1) install_node || error '操作未完成或已取消；失败原因见上方提示。' 'Operation did not complete or was cancelled; see the reason above.';;
   2) show_nodes;; 3) qr_nodes || true;; 4) service_menu || true;; 5) edit_nodes || true;;
   6) update_core || error '核心更新失败，已保留或回退原核心。' 'Core update failed; previous core retained or restored.';;
   7) make_backup || true;; 8) restore_backup || error '恢复失败，原配置已保留或回退。' 'Restore failed; previous configuration retained or restored.';;
   9) guide;; 10) choose_language || true;; 11) uninstall || error '卸载未完成。' 'Uninstall did not complete.';;
   12) network_menu || error '网络设置未完成，具体原因见上方提示。' 'Network settings did not complete; see the reason above.';;
   13) if update_manager; then return 0; fi;; 0) return 0;;
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
