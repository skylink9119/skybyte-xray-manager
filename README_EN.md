# SKYBYTE Xray Manager

[简体中文](README.md) · [YouTube](https://www.youtube.com/@SKYBYTE9119)

An independent Bash manager for official Xray-core on Ubuntu/Debian. Local test version **0.1.0**, pinned core **v26.3.27**. Chinese and English interfaces. Separate configuration, binary and service paths allow coexistence with SKYBYTE's sing-box manager when ports do not conflict.

## Nodes

| Mode | Transport and security | Default TCP port | Requirements |
| --- | --- | --- | --- |
| VLESS + Reality + Vision | RAW/TCP + Reality, Vision flow | 443 | Reachable TLS 1.3/HTTP2 camouflage target |
| VLESS + XHTTP + Reality | XHTTP + Reality, without Vision flow | 8443 | Same target requirements; no personal domain certificate |
| VLESS + XHTTP + TLS/CDN | XHTTP + verified TLS | 2053 | Domain and existing trusted fullchain/matching private key |

One node per mode; all three can run together on separate ports. Existing modes cannot be silently replaced. Renaming, certificate refresh and core updates preserve credentials. Removal and reinstallation generate new credentials.

Configure IPv4/IPv6 binding, public client address, ports, names and XHTTP paths. Client modes include auto, packet-up, stream-up and stream-one; the server accepts compatible modes. CDN defaults to packet-up and refuses stream-one. See [official XHTTP documentation](https://github.com/XTLS/Xray-core/discussions/4113) and [Reality documentation](https://xtls.github.io/en/config/transports/reality.html).

## Installation

Root, Ubuntu/Debian and systemd are required. Initial binary mappings support amd64 and arm64. Upload and extract the **complete** source package, enter its directory and run:

```bash
bash install.sh
```

Alternatively run `bash xray-manager.sh`. No sudo is needed. Missing bootstrap dependencies prompt for confirmation. APT index errors stop installation instead of continuing with stale indexes. The official stable core download is checked against its GitHub Release SHA256 digest.

This is a local standalone project, not yet published to GitHub. There is no invented online installer URL. Keep install.sh and xray-manager.sh together when using the complete package.

Menus and prompts are bold green; metadata and warnings yellow; links and errors red. YES is case-insensitive. Non-terminal output and NO_COLOR disable color.

## Menu

1. Install/add a node
2. View nodes and client exports
3. Local QR codes
4. Service status, start/stop/restart, validation and logs
5. Rename, remove or refresh TLS certificates
6. Update verified official stable Xray-core
7/8. Back up/restore configuration
9/10/11. Guide, language and uninstall

Permit actual TCP ports in the system firewall and provider security group. The script does not automatically change UFW, SSH ports or cloud security groups.

## Domain TLS and CDN

Supply an existing trusted fullchain and matching private key. The certificate must have the domain's DNS SAN, a system-trusted chain and more than 24 hours remaining validity. Source files are preserved; private copies are used by Xray.

For direct TLS, point the domain at the VPS. For CDN, configure DNS proxying, a supported HTTPS port, origin address and strict origin certificate verification in your provider dashboard. Do not cache, challenge or rewrite the XHTTP path. Cloudflare proxies selected HTTPS ports including 443, 2053 and 8443; check [official port documentation](https://developers.cloudflare.com/fundamentals/reference/network-ports/). Streaming modes also depend on the provider's HTTP2/gRPC support.

No default self-signed TLS or insecure client verification. Existing certificate tools handle issuance/renewal. After external renewal use **5 → 3** to refresh the private certificate copy; credentials are retained and previously active service is restarted. Copies do not automatically follow external renewal.

Reality connects directly and is not transported by ordinary HTTPS CDN proxying. Successful target checks do not prove public client connectivity, resistance to blocking or better speed.

## Exports

Private files under `/etc/skybyte-xray/`:

- nodes.txt: standard VLESS URIs, separated by dashed lines in the terminal.
- subscription-base64.txt: local Base64 node collection.
- client-vision.json, client-xhttp-reality.json, client-xhttp-tls.json: complete Xray client configurations, exposing SOCKS only on 127.0.0.1:10808.

These are local exports, not hosted HTTPS subscriptions. Retrieve through SSH/SFTP. Clients must implement the chosen transport; QR import does not add XHTTP support. Keep UUIDs, Reality credentials, private keys, full links, QR codes and backups private.

## Protection and operations

Owned directories use 700; state, exports, private certificates and backups use 600. Private keys never enter command arguments. The service is skybyte-xray.service and the binary/manager are under /usr/local/lib/skybyte-xray. Existing xray.service, sing-box and panel configurations are not taken over.

Refuses unknown ownership, unmanaged file collisions, symlinks and occupied TCP ports. Candidates are checked by the official engine. Configuration/service transactions restore previous files, activity and boot state on restart failure; startup recovers interrupted changes. Core updates validate existing configuration and roll back on failure. Removing the final protocol stops/disables the owned service.

Production routing blocks common private, loopback and link-local destinations. Backups contain sensitive credentials; protect them. Restore accepts known data only, never executes archived programs, and rejects traversal, links, duplicates and excessive sizes. Uninstall requires a successful backup and preserves backups, unknown files, external certificates, dependencies and firewall rules.

## Development and validation

Edit src/manager.sh and src/core.py. Build the standalone distribution with:

```bash
python3 scripts/build.py
python3 scripts/build.py --check
bash -n install.sh
bash -n src/manager.sh
bash -n xray-manager.sh
shellcheck install.sh src/manager.sh xray-manager.sh
bash xray-manager.sh --self-check
XRAY_BIN=/absolute/path/to/verified/xray python3 -m unittest discover -s tests -v
```

Local validation uses the digest-verified official Darwin/arm64 core, including real authenticated Vision, XHTTP-Reality, verified XHTTP-TLS and packet-up origin connections. Service policy tests use a disposable systemctl controller, not a real systemd boot. Local packet-up does not prove a public CDN works.

Ubuntu 24.04, Debian 12 and Debian 13 GitHub Actions definitions are included. They have not run for this unpushed local repository. Real VPS boot, provider firewall, public CDN and GUI client imports still require validation.

SKYBYTE Manager · [Subscribe to the SKYBYTE YouTube channel](https://www.youtube.com/@SKYBYTE9119).
