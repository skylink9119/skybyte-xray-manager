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

helper(){ python3 - "$@" <<'SKYBYTE_PYTHON'
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
"""SKYBYTE Xray Manager: private configuration, exports and transactions.

Only generated runtime state contains credentials. No imported content is executed.
"""
import argparse
import base64
import copy
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
import urllib.request
import uuid
import zipfile
from pathlib import Path

VERSION = "0.1.0"
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
            "routing": {"rules": [{"type": "field", "ip": ["127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12",
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
    with socket.socket(socket.AF_INET6 if ":" in host else socket.AF_INET) as listener:
        if ":" in host:
            listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        listener.bind((host, number))


def prepare(root, binary, options):
    ensure_owned(root, create=True)
    state = copy.deepcopy(load_state(root))
    if options.kind in state["nodes"]:
        raise ValueError("Protocol already installed / 该协议已安装，先删除再安装会更换凭据")
    if port(options.port) in [n["port"] for n in state["nodes"].values()]:
        raise ValueError("TCP port already used by a managed node / 托管节点端口冲突")
    check_port(options.listen, port(options.port))
    node = {"name": name(options.name), "uuid": str(uuid.uuid4()), "port": port(options.port),
            "address": address(options.address), "listen": options.listen, "sni": domain(options.sni)}
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["selfcheck", "prepare", "commit", "rollback", "finalize", "backup", "restore",
                                            "remove", "rename", "refresh-tls", "show", "guard", "download", "probe", "journal"])
    parser.add_argument("--root", default=os.environ.get("SKYBYTE_XRAY_DIR", "/etc/skybyte-xray"))
    parser.add_argument("--binary", default=os.environ.get("SKYBYTE_XRAY_BINARY", "/usr/local/lib/skybyte-xray/xray"))
    parser.add_argument("--unit", default=os.environ.get("SKYBYTE_XRAY_UNIT", "/etc/systemd/system/skybyte-xray.service"))
    parser.add_argument("--kind", choices=KINDS)
    parser.add_argument("--port", default="443")
    parser.add_argument("--listen", choices=["0.0.0.0", "::", "127.0.0.1", "::1"], default="0.0.0.0")
    parser.add_argument("--address", default="")
    parser.add_argument("--sni", default="www.microsoft.com")
    parser.add_argument("--target", default="www.microsoft.com:443")
    parser.add_argument("--name", default="SKYBYTE")
    parser.add_argument("--path", default="")
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
    options = parser.parse_args()
    if options.command == "selfcheck":
        print("SKYBYTE Xray Manager " + VERSION + " OK")
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
        # Never print external core output, request data, state or credential values.
        message = str(error) if isinstance(error, ValueError) else "Operation failed / 操作失败，请检查文件、网络与权限"
        print(message, file=sys.stderr)
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
 # shellcheck disable=SC2329 # Invoked by the EXIT trap.
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
 # shellcheck disable=SC2329 # Invoked by the EXIT trap.
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
