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

An independent Bash manager for official Xray-core on Ubuntu/Debian. Version **0.1.19**, pinned core **v26.3.27**. Chinese and English interfaces. Separate configuration, binary and service paths allow coexistence with SKYBYTE's sing-box manager when ports do not conflict.

## Startup overview

The main menu shows OS, architecture, kernel, CPU, memory/swap, root-disk use, uptime and load; actual Xray version, service and boot state, installed protocols/ports, current BBR and configured WARP routing. Related components include the official WARP client, UFW, firewalld, Fail2ban and QR utility, with installation and runtime states distinguished. Probes are local, read-only and bounded to two seconds per command. Missing probes do not block the menu. No credentials are displayed; configured routing is not proof of connectivity.

## WARP routing and platform tests

The WARP menu groups proxy setup, routing and connection tests, with one short option per line and a compact local status. Open **n** to install the official local-proxy client, reuse a loopback SOCKS5 gateway or restore direct routing for this project. Installation uses the [official signed Cloudflare repository](https://pkg.cloudflareclient.com/), asks for terms confirmation and configures local-proxy mode (default `127.0.0.1:40000`). Existing clients or residual registration data stop automatic installation. An existing proxy can be shared with sing-box while each project manages its own routes.

Choose Netflix, Disney+, ChatGPT, Gemini, all four, or custom domain suffixes. Before applying, verify loopback-only listening and a real HTTPS Cloudflare trace request through proxy-side DNS, including `warp=on/plus`, a global egress IP and country. Only matching TCP uses WARP; unmatched traffic stays direct and matching UDP is blocked for application TCP fallback. Domain sniffing cannot guarantee matches for IP-only traffic, ECH or unlisted domains. System default routes are untouched; selected WARP traffic does not silently fall back to direct on failure. Platform access or a specific country is not guaranteed.

Candidate validation, rollback and existing backups cover routing alongside nodes. Credentials and prior service activity are preserved; failed restarts restore configuration. Restored WARP routing requires the corresponding local proxy. Disabling routing/removing the manager retains the WARP package, registration, connection and repository; other projects are untouched.

Option **5** compares anonymous Netflix, Disney+, ChatGPT and Gemini responses through direct IPv4 and WARP. Page access and a successful trace do not prove playback, catalog coverage or account access. No third-party scripts or login credentials are used. Private reports contain classifications/status only in `reports/`, mode 600. See [WARP local proxy mode](https://developers.cloudflare.com/warp-client/warp-modes/) and [Xray SOCKS outbound](https://xtls.github.io/en/config/outbounds/socks.html).

## Nodes

| Mode | Transport and security | Default TCP port | Requirements |
| --- | --- | --- | --- |
| VLESS + Reality + Vision | RAW/TCP + Reality, Vision flow | 443 | Reachable TLS 1.3/HTTP2 camouflage target |
| VLESS + XHTTP + Reality | XHTTP + Reality, without Vision flow | 443 | Same target requirements; no personal domain certificate |
| VLESS + XHTTP + TLS/CDN | XHTTP + verified TLS | 2053 | Domain and existing trusted fullchain/matching private key |

One node per mode; all three can run together on separate ports. TCP/Reality and XHTTP/Reality both default to 443; choose distinct free ports when installing both. Existing node ports are retained. Existing modes cannot be silently replaced. Renaming, certificate refresh and core updates preserve credentials. Removal and reinstallation generate new credentials.

Configure IPv4/IPv6 binding, public client address, ports, names and XHTTP paths. Client modes include auto, packet-up, stream-up and stream-one; the server accepts compatible modes. CDN defaults to packet-up and refuses stream-one. See [official XHTTP documentation](https://github.com/XTLS/Xray-core/discussions/4113) and [Reality documentation](https://xtls.github.io/en/config/transports/reality.html).

## Installation

Root, Ubuntu/Debian and systemd are required. Binary mappings support amd64 and arm64. Run this single command in the VPS root terminal. If curl is missing, curl and CA certificates are installed automatically:

<!-- SKYBYTE_INSTALL_COMMAND_START -->
```bash
(if ! command -v curl >/dev/null; then apt-get update && apt-get install -y curl ca-certificates; fi && script=$(curl -q -fsSL --max-time 60 https://raw.githubusercontent.com/skylink9119/skybyte-xray-manager/main/bootstrap.sh) && bash -c "$script")
```
<!-- SKYBYTE_INSTALL_COMMAND_END -->

The bootstrap downloads the pinned installer into a private temporary directory, stops on download or syntax failure, cleans up afterward and preserves menu input. Working APT repositories are required when curl is missing. The installer still downloads the matching manager and verifies its release SHA256 before installation. Installer and payload versions must match; a newer or unrecognized installed manager is retained. Equal-version reinstallation is supported. After installation, including after a new SSH login, reopen it with:

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

Menus and prompts are bold green; metadata and warnings yellow; links and errors red. Action confirmations use `[y/N]`: type `y` or `Y` to confirm; Enter or `n/N` cancels. Cancelling node installation returns normally to the menu instead of reporting an installation failure. Non-terminal output and NO_COLOR disable color.

The client connection address is required: enter this VPS's public IP or a domain pointing to it. This is separate from the Reality handshake name. Only bracketed defaults accept an empty answer. Address and listening port checks run first. If TCP 443 is occupied, for example by sing-box or a website, select another free port and allow its TCP traffic rather than stopping an existing service. `TLSv1.3 / h2` means only that the handshake target passed its check; configuration and service startup must still complete.

## Reality handshake target checks

Open main menu **o**: **1** checks targets from the current TCP/Reality and XHTTP/Reality configuration; **2** checks a custom target. Enter a hostname or `host:port` (default 443), then an optional separate SNI; Enter uses the target hostname. Duplicate target/SNI pairs are checked once. Custom checks work before Reality is installed.

Results show DNS, the connected TCP address, TLS 1.3, certificate trust / validity / hostname, HTTP/2 ALPN and a clear PASSED / FAILED summary. Each target has a 12-second total network budget. Failures explain the cause without bypassing certificate verification. The menu stays open; `0` returns one level.

Checks cover **this VPS → target** only. They do not edit nodes, credentials or routes, restart services, or verify client, public node-port or CDN connectivity. Healthy targets do not need scheduled rotation; investigate or change them when a check fails.

Choose **3** to replace a target: select an installed Vision or XHTTP/Reality node, choose a preset or custom SNI, then enter the target (default `selected-host:443`). The new target must pass checks before `y` applies it. Failures and cancellation retain the original configuration. UUIDs, key pairs, short IDs, ports, XHTTP paths/modes and other nodes are preserved. Running services briefly restart; application failures roll back configuration, exports and prior service state. Re-import the updated node or update client SNI. XHTTP/TLS-CDN is excluded; no Reality node is installed automatically.

## Menu

The main menu uses case-insensitive letters `a–o`; submenus use numbers. `0` returns one level and `q` exits from the main menu. Completed, cancelled and failed operations keep the current submenu open for consecutive firewall, service, node-edit and WARP operations. Previous main-menu numbers remain compatibility aliases.

a. Install/add a node
- **b**: View nodes and client exports
- **c**: Local QR codes
- **d**: Service status, start/stop/restart, validation and logs
- **e**: Rename, remove, refresh TLS certificates or edit address/port/path
- **f**: Update verified official stable Xray-core
- **g/h**: Back up/restore configuration
- **i/j/k**: Guide, language and uninstall
- **l**: Firewall / BBR
- **m**: Update manager script
- **n**: WARP routing and platform tests
- **o**: Reality target checks and target replacement
- **q**: Exit

Permit actual TCP ports in the system firewall and provider security group. Menu l manages host TCP allows; provider security groups remain manual.

Use **e → 4** to edit an installed node's client address, TCP listen port and XHTTP path. Enter keeps each value; leaving every field blank returns without restarting. Vision has no path prompt. UUIDs, Reality keys, Short IDs, TLS SNI, certificates and other nodes are retained. Input, managed port conflicts and changed port availability are checked before staging. Server configuration, links, Base64 and Xray client JSON are regenerated together. Active services restart with rollback on failure; stopped services stay stopped. Re-import clients from menu b and allow the new TCP port; CDN users must also check provider port support.

The installer offers Reality handshake presets for TCP/Reality and XHTTP/Reality: Microsoft (`www.microsoft.com`, default), Apple (`www.apple.com`), Amazon (`www.amazon.com`), Cloudflare (`www.cloudflare.com`) and Google (`dl.google.com`). The target defaults to the selected domain on `:443` and remains editable. Choose Custom or enter a domain directly; 0 returns. Each selection still undergoes the VPS TLS 1.3, HTTP/2 and certificate check before core download or node configuration changes. Reachability depends on the VPS route.

## Manager self-update

Menu **m** checks this project's latest stable GitHub Release, displays the current/available version and asks for `y` before updating the installed `/usr/local/lib/skybyte-xray/manager.sh`. Preview, equal and older versions are refused, including when an old running copy targets a newer installation. Users of v0.1.3 and earlier must run the v0.1.19 installer once to obtain this menu.

The updater downloads the selected release's manager and `SHA256SUMS` from the fixed project repository, verifies GitHub asset SHA256 values and the manifest, then checks Bash syntax, version and self-check output. It replaces the installed file atomically, retaining the old bytes in `manager.previous.sh`. Failed post-install checks trigger rollback; rollback write failure reports the retained backup. Foreign directories/files and symlinks are refused. Network/API limits, missing assets, integrity failures and permission errors stop the update. Node configurations, credentials, language, Xray-core, services, firewall and BBR settings are retained.

After success the old menu exits; run `xr` again. The backup retains one previous script. Use Git or a source archive to update local source checkouts. Standalone copies must be installed with `install.sh` first; this entry updates only the managed installation.

## Firewall and BBR

Use **l → Firewall / BBR**. The menu groups firewall actions (1–5) and BBR actions (6–8), with one item per line:

- **1**: show UFW/firewalld status plus firewalld default/active zones.
- **2**: install and enable UFW. Refuse active firewalls and effective netfilter state outside the supported Fail2ban structure. Require confirmed SSH ports without assuming 22, merge the current SSH_CONNECTION server port and managed node ports, and accept other TCP services such as websites on 80/443. After preview and `y`, install UFW with APT if missing, stage allows, set deny-incoming/allow-outgoing defaults, then enable it. Restrictive/routed stored UFW rules or invalid IPv6 configuration stop initialization. Failed activation attempts to return to inactive; failed rollback directs the user to the provider console. Added rules, defaults and packages may remain for inspection/retry.
- **3/4**: allow all installed node TCP ports or one selected port (1–65535), with a port preview and `y` confirmation. Select a firewalld zone or press Enter for the default; check that it covers the public interface. Exactly one supported firewall must already be active. This does not install, enable, disable, reset or flush firewalls, change policies/SSH, or remove ports. Runtime and permanent firewalld ports are updated separately without a global reload. On failure some allows may remain; inspect status before retrying.
- **5**: disable/remove UFW. Submenu **1** disables it while keeping the package and rule configuration; **2** removes the package and retains configuration; **3** removes the package and purges UFW rule configuration irreversibly. Check package health, dependencies and locks, ask for `y`, then disable and verify before targeting only `ufw`. Option 3 uses `dpkg --purge ufw` and can clean configuration left by option 2; absent packages without dpkg configuration records do not trigger deletion of unknown files. Held/incomplete packages or dependency conflicts stop the operation; disable failure prevents removal. Purge failure reports potentially partial deletion and does not re-enable UFW automatically. Preflight is read-only, without forced dependencies, autoremove or removing other packages. Other firewalls, iptables/nftables tools, provider rules, nodes, SSH and BBR configuration are outside the cleanup scope; no direct global rule flush is issued. Previously blocked ports may become reachable after disabling UFW.
- **6/7/8**: show BBR status, enable BBR and the fq default, or restore previous values. Uses the existing kernel, attempting `tcp_bbr` / `sch_fq` module loading if needed; never installs a kernel. The dedicated `/etc/sysctl.d/90-skybyte-xray-bbr.conf` stores original values in a comment. Foreign, edited or symlink files are refused. Repeated enabling keeps the first snapshot. Failed application attempts rollback; incomplete rollback retains the recovery file and reports failure.

Supports **Fail2ban/UFW coexistence** for the independent `inet/f2b-table` / `f2b-chain` layout (filter/input, priority -1, ACCEPT policy), containing only TCP port/address-set bans with reject/drop verdicts for IPv4/IPv6. Validate the complete structure rather than trusting names; custom jumps, accepts, NAT, other native rules and iptables-based Fail2ban still require manual review. Preview coexistence before confirmation and verify existing ban structure after UFW activation or rollback, allowing normal address/counter updates. Failed preservation checks report that Fail2ban needs inspection and attempt to disable UFW. The manager does not flush, stop or recreate Fail2ban. Existing bans can still block connections; test a new SSH session after enabling UFW.

The BBR status view leads with a prominent enabled/not-enabled summary (green/yellow on terminals), followed by the current algorithm, default qdisc, available algorithms and management state. The summary uses the running congestion control value; availability or a saved configuration alone does not mean BBR is enabled.

BBR changes the system TCP default, primarily affecting new connections; speed gains vary. The fq default does not replace existing interface queues. Other boot configuration may override these defaults; check status after reboot. Restore removes only the managed file and reapplies saved runtime values, leaving other sysctl files unchanged. Uninstall retains firewall rules and BBR settings; use **12 → 8** first to restore BBR if desired.

This release also fixes initial rule insertion: `prepend allow` handles empty IPv4/IPv6 lists, whereas `insert 1` is rejected by UFW 0.36.2 when no rules exist. UFW failures show the exact command, exit code and a filtered reason without exposing arbitrary external error details.

This release fixes false positives from empty tables by inspecting nft JSON objects. Empty tables, ACCEPT default chains and unreferenced empty user chains alone do not block initialization. Outside the supported Fail2ban structure above, actual rules (including ACCEPT/NAT), DROP policies, sets and unrecognized state still stop initialization, with the inspecting command and table/chain/object shown. Inspection failure never flushes or bypasses rules. Earlier Docker wording was a possibility, not an identified owner.

Confirm every required TCP service before enabling; unlisted services may be blocked, and extra UDP services are not handled by this setup. Keep the current SSH session and verify a second connection after activation. Keep provider console access available; command success does not prove SSH reachability.

Host rules alone do not prove public connectivity. Check provider rules, UFW IPv6 configuration, rule ordering, firewalld zones and CDN port support. Raw nftables/iptables editing is not supported. Tests use isolated command simulators; actual VPS firewall/kernel/reboot acceptance is still required.

References: [UFW](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html), [firewalld](https://firewalld.org/documentation/man-pages/firewall-cmd.html), [Linux TCP sysctls](https://kernel.org/doc/html/latest/networking/ip-sysctl.html), [default queue discipline](https://www.kernel.org/doc/html/latest/admin-guide/sysctl/net.html).

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

The main menu reuses the sing-box project's SKYBYTE ASCII logo with the Xray project name, retaining terminal color and `NO_COLOR` behavior. See the [maintenance review](docs/REVIEW.md) (Chinese) for reproduced fixes and prioritized improvements.

SKYBYTE Manager · [Subscribe to the SKYBYTE YouTube channel](https://www.youtube.com/@SKYBYTE9119).

## License

Copyright © 2026 SKYBYTE (skylink9119). Manager code uses [GPLv3](LICENSE). Distributed modifications retain notices and provide corresponding source under the GPL. Independent third-party components such as Xray-core keep their own licenses.
