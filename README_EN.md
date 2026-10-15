# SKYBYTE Xray Manager

[简体中文](README.md) · [YouTube](https://www.youtube.com/@SKYBYTE9119)

If this script helps you, please [subscribe to my SKYBYTE YouTube channel](https://www.youtube.com/@SKYBYTE9119) to support continued maintenance and updates!

<!-- SKYBYTE_AFFILIATE_HEADER_START -->
## VPS provider affiliate links

### 1. Residential / ISP IP: e-commerce and TikTok environments

**[LisaHost](https://lisahost.com/aff.php?aff=11072)**: consider residential / ISP IP plans when evaluating network environments for cross-border e-commerce, TikTok or overseas account workflows. Confirm the IP type and available regions for the specific plan.

### 2. Premium-route VPS: personal use / sharing / relay entry

**[DMIT](https://www.dmit.io/aff.php?aff=18635)**: offers China-optimized network options, including CN2 GIA. Choose daily-use nodes or entry servers based on your budget and actual route tests.

**[BandwagonHost](https://bandwagonhost.com/aff.php?aff=83101)**: compare plans including CN2 GIA options for personal nodes and entry servers.

### 3. Entry VPS: learning / backup nodes

**[RackNerd](https://my.racknerd.com/aff.php?aff=18647)**: check budget VPS and annual offers for learning Ubuntu/Debian, deploying Xray and running backup nodes.

Another option: **[AkileCloud](https://akile.ai/register?aff_code=0be67084-ae2e-4095-a586-2a3ee5c970f0)**.

**Affiliate disclosure:** purchases through these links may earn the author a commission to support SKYBYTE development and maintenance. Prices, routes, bandwidth and IP types depend on the specific plan. Test actual speeds and platform availability on your own network.
<!-- SKYBYTE_AFFILIATE_HEADER_END -->

---

An independent Bash manager for official Xray-core on Ubuntu/Debian. Version **0.1.1**, pinned core **v26.3.27**. Chinese and English interfaces. Separate configuration, binary and service paths allow coexistence with SKYBYTE's sing-box manager when ports do not conflict.

## Nodes

| Mode | Transport and security | Default TCP port | Requirements |
| --- | --- | --- | --- |
| VLESS + Reality + Vision | RAW/TCP + Reality, Vision flow | 443 | Reachable TLS 1.3/HTTP2 camouflage target |
| VLESS + XHTTP + Reality | XHTTP + Reality, without Vision flow | 8443 | Same target requirements; no personal domain certificate |
| VLESS + XHTTP + TLS/CDN | XHTTP + verified TLS | 2053 | Domain and existing trusted fullchain/matching private key |

One node per mode; all three can run together on separate ports. Existing modes cannot be silently replaced. Renaming, certificate refresh and core updates preserve credentials. Removal and reinstallation generate new credentials.

Configure IPv4/IPv6 binding, public client address, ports, names and XHTTP paths. Client modes include auto, packet-up, stream-up and stream-one; the server accepts compatible modes. CDN defaults to packet-up and refuses stream-one. See [official XHTTP documentation](https://github.com/XTLS/Xray-core/discussions/4113) and [Reality documentation](https://xtls.github.io/en/config/transports/reality.html).

## Installation

Root, Ubuntu/Debian and systemd are required. Binary mappings support amd64 and arm64. Run the complete command in the VPS root terminal:

```bash
bash <(curl -fsSL https://github.com/skylink9119/skybyte-xray-manager/releases/download/v0.1.1/install.sh)
```

The installer downloads the matching manager and verifies its release SHA256 before installation. After installation, including after a new SSH login, reopen it with:

```bash
xr
```

Rerun the installer to update the manager while preserving existing node state and credentials. A conflicting third-party xr command stops installation without overwriting it. The sing-box sb shortcut is unaffected.

Alternatively upload and extract the complete release package, enter its directory and run:

```bash
bash install.sh
```

Alternatively run `bash xray-manager.sh`. No sudo is needed. Missing bootstrap dependencies prompt for confirmation. APT index errors stop installation instead of continuing with stale indexes. The official stable core download is checked against its GitHub Release SHA256 digest.

Independent repository: [skylink9119/skybyte-xray-manager](https://github.com/skylink9119/skybyte-xray-manager). Released source lives on main. Releases include the installer, standalone manager, complete source archive and SHA256SUMS. Complete packages install locally; an installer downloaded alone fetches its payload online.

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

XHTTP-Reality requires no personal domain or certificate. The basic configuration does not add Vision flow. Start with Xray's XMUX defaults without mux.cool; measure your route before tuning. This does not guarantee relief from throttling or disconnects.

In this release Xray terminates TLS directly. Automatic Nginx/Caddy deployment, certificate issuance/renewal, custom XMUX controls and H3 selection are not integrated. A real fronting website can reduce direct proxy exposure but cannot guarantee invisibility. HTTP/3 requires client/peer support and reachable UDP. With a CDN, the client may use H3 while the origin still uses H2; this does not require enabling QUIC at the origin.

## Exports

Private files under `/etc/skybyte-xray/`:

- nodes.txt: standard VLESS URIs, separated by dashed lines in the terminal.
- subscription-base64.txt: local Base64 node collection.
- client-vision.json, client-xhttp-reality.json, client-xhttp-tls.json: complete Xray client configurations, exposing SOCKS only on 127.0.0.1:10808.

These are local exports, not hosted HTTPS subscriptions. Retrieve through SSH/SFTP. Clients must implement the chosen transport; QR import does not add XHTTP support. Keep UUIDs, Reality credentials, private keys, full links, QR codes and backups private.

All four isolated connection cases passed with Xray v26.3.27/v26.10.10 clients and servers in both directions; the downloader keeps the stable channel. Original sing-box 1.14.3 passed Vision against the pinned core but has no XHTTP transport. Mihomo 1.19.32 passed XHTTP-TLS/packet-up experiments; Reality experiments failed, so that combination is not promised. Actual Shadowrocket and v2rayN/v2rayNG GUI imports still need device testing. Check the app, embedded core and transport separately.

## Protection and operations

Owned directories use 700; state, exports, private certificates and backups use 600. Private keys never enter command arguments. The service is skybyte-xray.service and the binary/manager are under /usr/local/lib/skybyte-xray. Existing xray.service, sing-box and panel configurations are not taken over.

Refuses unknown ownership, unmanaged file collisions, symlinks and occupied TCP ports. Candidates are checked by the official engine. Configuration/service transactions restore previous files, activity and boot state on restart failure; startup recovers interrupted changes. Core updates validate existing configuration and roll back on failure. Removing the final protocol stops/disables the owned service.

Production routing resolves domain targets before matching private, loopback and link-local blocks. Actual connection regressions cover both private IPs and hostnames. Backups contain sensitive credentials; protect them. Restore accepts known data only, never executes archived programs, and rejects traversal, links, duplicates and excessive sizes. Uninstall requires a successful backup and preserves backups, unknown files, external certificates, dependencies and firewall rules.

For early development installs, updating the manager does not rewrite the running configuration. Back up first, then use **5 → 1** to rename an installed node (the name may stay the same). This regenerates configuration with the hostname-block fix while keeping UUIDs/keys. If config.json was edited manually, save that file separately and reconcile custom settings; state backups do not retain fields outside the manager's model.

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

Ubuntu 24.04, Debian 12 and Debian 13 GitHub Actions definitions are included. Local results and Linux CI results are reported separately. Real VPS boot, provider firewall, public CDN and GUI client imports still require validation.

SKYBYTE Manager · [Subscribe to the SKYBYTE YouTube channel](https://www.youtube.com/@SKYBYTE9119).

## License

Copyright © 2026 SKYBYTE (skylink9119). Manager code uses [GPLv3](LICENSE). Distributed modifications retain notices and provide corresponding source under the GPL. Independent third-party components such as Xray-core keep their own licenses.
