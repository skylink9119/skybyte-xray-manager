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

VERSION = "0.1.6"
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


def firewall_status():
    status = {"ufw": "unavailable", "firewalld": "unavailable"}
    if shutil.which("ufw"):
        result = ufw_command(["status"])
        if result.stdout.startswith("Status: active"):
            status["ufw"] = "active"
        elif result.stdout.startswith("Status: inactive"):
            status["ufw"] = "inactive"
        else:
            raise ValueError("Cannot determine UFW status / 无法识别 UFW 状态")
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


def nft_conflict(text):
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
        if kind == "metainfo":
            continue
        if not isinstance(value, dict):
            raise ValueError("Unknown nft object fields / 无法识别 nft 对象字段")
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
                    return "chain " + location + " policy=" + netfilter_label(value.get("policy", "unknown"))
            continue
        # Rules (including ACCEPT/NAT), sets, flowtables and unknown state remain guarded.
        return netfilter_label(kind) + " " + location
    return None


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
    # Do not replace rules belonging to Docker, native nftables or other managers.
    for command in ("nft", "iptables-save", "ip6tables-save", "iptables-legacy-save", "ip6tables-legacy-save"):
        if not shutil.which(command):
            continue
        args = [command, "-j", "list", "ruleset"] if command == "nft" else [command]
        try:
            rules = system_command(args).stdout
        except (OSError, subprocess.SubprocessError):
            raise ValueError("Cannot inspect " + command + "; UFW setup stopped / 无法检查 " + command + "，已停止 UFW 初始化，请检查权限与内核支持") from None
        conflict = nft_conflict(rules) if command == "nft" else iptables_conflict(rules)
        if conflict:
            raise ValueError("Existing netfilter state: " + command + " / " + conflict +
                             "; inspect it before enabling UFW / 检测到已有规则或策略，来源如上；请先核对，不自动清空或覆盖")


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
    firewall_setup_check()
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
    except BaseException as error:
        try:
            ufw_command(["--force", "disable"])
            if firewall_status()["ufw"] != "inactive":
                raise ValueError("UFW still active")
        except (OSError, ValueError, subprocess.SubprocessError):
            raise ValueError("UFW enable/rollback incomplete; check from provider console / UFW 启用或回退未完成，请通过服务商控制台检查；已保留规则") from error
        raise


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
                                            "remove", "rename", "edit", "refresh-tls", "show", "guard", "download", "probe", "journal", "preflight", "node-ports", "firewall-status", "firewall-allow", "bbr-status", "bbr-enable", "bbr-restore", "manager-latest", "manager-update", "firewall-setup-check", "firewall-setup-plan", "firewall-setup"])
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
    options = parser.parse_args()
    if options.command != "edit":
        options.port = options.port if options.port is not None else "443"
        options.address = options.address if options.address is not None else ""
        options.path = options.path if options.path is not None else ""
    if options.command == "firewall-setup-check":
        firewall_setup_check()
        return
    if options.command == "firewall-setup-plan":
        ssh, others = firewall_setup_plan(Path(options.root), options.ssh_ports, options.ports)
        print("SSH TCP: " + ", ".join(map(str, ssh)))
        print("Other TCP / 其他 TCP: " + (", ".join(map(str, others)) or "none / 无"))
        return
    if options.command == "firewall-setup":
        firewall_setup(Path(options.root), options.ssh_ports, options.ports)
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
        print(json_text(network_values()))
        print("Available / 可用: " + system_command(["sysctl", "-n", "net.ipv4.tcp_available_congestion_control"]).stdout.strip())
        print("Managed / 本脚本管理: " + ("yes" if bbr_previous(BBR_PATH) is not None else "no"))
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
